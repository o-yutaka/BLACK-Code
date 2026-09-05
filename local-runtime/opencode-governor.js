import crypto from "node:crypto"
import fs from "node:fs"
import path from "node:path"
import { execFileSync } from "node:child_process"

const calls = new Map()
const sessions = new Map()
const ignoredDirs = new Set([".git", ".black", ".venv", "node_modules", "target", "dist", "build", "__pycache__"])

function enabled() {
  return Boolean(process.env.BLACK_CODE_GOVERNOR_DIR && process.env.BLACK_CODE_PROJECT_ROOT)
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex")
}

function projectRoot(fallback) {
  return path.resolve(process.env.BLACK_CODE_PROJECT_ROOT || fallback || process.cwd())
}

function stateDir() {
  return path.resolve(process.env.BLACK_CODE_GOVERNOR_DIR)
}

function continuityPath(root) {
  return path.join(stateDir(), `${sha256(root.toLowerCase())}.json`)
}

function git(root, args) {
  try {
    return execFileSync("git", ["-C", root, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      maxBuffer: 64 * 1024 * 1024,
    }).trimEnd()
  } catch {
    return null
  }
}

function fileDigest(file) {
  try {
    const stat = fs.statSync(file)
    if (!stat.isFile()) return ""
    if (stat.size > 32 * 1024 * 1024) return `large:${stat.size}:${Math.trunc(stat.mtimeMs)}`
    return sha256(fs.readFileSync(file))
  } catch {
    return "missing"
  }
}

function fallbackTreeDigest(root) {
  const rows = []
  const stack = [root]
  while (stack.length && rows.length < 4000) {
    const current = stack.pop()
    let entries = []
    try { entries = fs.readdirSync(current, { withFileTypes: true }) } catch { continue }
    entries.sort((a, b) => a.name.localeCompare(b.name))
    for (const entry of entries) {
      if (ignoredDirs.has(entry.name)) continue
      const full = path.join(current, entry.name)
      if (entry.isDirectory()) stack.push(full)
      else if (entry.isFile()) rows.push(`${path.relative(root, full).replaceAll("\\", "/")}:${fileDigest(full)}`)
      if (rows.length >= 4000) break
    }
  }
  return sha256(rows.sort().join("\n"))
}

function workspaceFingerprint(root) {
  const head = git(root, ["rev-parse", "HEAD"])
  if (!head) return `nogit:${fallbackTreeDigest(root)}`
  const diff = git(root, ["diff", "--binary", "HEAD", "--", "."]) ?? ""
  const untrackedRaw = git(root, ["ls-files", "--others", "--exclude-standard", "-z"]) ?? ""
  const untracked = untrackedRaw.split("\0").filter(Boolean).sort().map((relative) => {
    const full = path.resolve(root, relative)
    if (!full.startsWith(root + path.sep) && full !== root) return `${relative}:outside`
    return `${relative.replaceAll("\\", "/")}:${fileDigest(full)}`
  })
  return sha256(JSON.stringify({ head, diff, untracked }))
}

function loadContinuity(root) {
  try { return JSON.parse(fs.readFileSync(continuityPath(root), "utf8")) } catch { return null }
}

function persist(state) {
  if (!enabled()) return
  try {
    fs.mkdirSync(stateDir(), { recursive: true })
    const current = workspaceFingerprint(state.root)
    const record = {
      schema_version: "2.0",
      project_root: state.root,
      updated_at: new Date().toISOString(),
      last_session_id: state.sessionID,
      baseline_hash: state.baselineHash,
      last_workspace_hash: current,
      last_verified_hash: state.verifiedHash,
      verification_token: state.token,
      verification_profile: state.profile,
      unverified: current !== state.verifiedHash && (current !== state.baselineHash || state.priorUnverified),
    }
    const target = continuityPath(state.root)
    const temp = `${target}.${process.pid}.tmp`
    fs.writeFileSync(temp, JSON.stringify(record, null, 2), "utf8")
    fs.renameSync(temp, target)
  } catch {}
}

function stateFor(sessionID, fallbackRoot) {
  const id = sessionID || "session"
  let state = sessions.get(id)
  if (state) return state
  const root = projectRoot(fallbackRoot)
  const current = workspaceFingerprint(root)
  const prior = loadContinuity(root)
  const priorUnverified = Boolean(prior?.unverified && prior?.last_workspace_hash === current && prior?.last_verified_hash !== current)
  state = {
    sessionID: id,
    root,
    baselineHash: current,
    verifiedHash: prior?.last_verified_hash === current ? current : null,
    token: prior?.last_verified_hash === current ? prior?.verification_token ?? null : null,
    profile: prior?.last_verified_hash === current ? prior?.verification_profile ?? null : null,
    priorUnverified,
    lastFailure: null,
  }
  sessions.set(id, state)
  return state
}

function callKey(input) {
  return `${input?.sessionID ?? "session"}:${input?.callID ?? input?.callId ?? Math.random()}`
}

function shellLike(tool) {
  return tool === "bash" || tool === "shell"
}

function editLike(tool) {
  return tool === "edit" || tool === "write" || tool === "apply_patch"
}

function normalizedCommand(value) {
  return String(value ?? "").trim().replace(/\s+/g, " ")
}

function isFinalVerifyCommand(command) {
  return /(^|[;&|]\s*)(?:black-code-verify(?:\.cmd|\.ps1)?\b|(?:powershell(?:\.exe)?|pwsh(?:\.exe)?)\b[^;&|\n]*verification-gate\.ps1\b)/i.test(command)
}

function verificationToken(state, current, command) {
  const payload = {
    schema_version: "2.0",
    workspace_hash: current,
    command_hash: sha256(command),
    profile: "governed-final-v2",
  }
  return sha256(JSON.stringify(payload))
}

function outputExitCode(output) {
  const value = output?.metadata?.exitCode ?? output?.metadata?.exit_code
  return Number.isInteger(value) ? value : null
}

export const BlackCodeGovernor = async ({ directory, worktree } = {}) => ({
  "tool.execute.before": async (input, output) => {
    if (!enabled()) return
    const state = stateFor(input?.sessionID, worktree || directory)
    const args = output?.args ?? {}
    calls.set(callKey(input), { tool: input?.tool ?? "unknown", args })
    if (!shellLike(input?.tool)) return
    const command = normalizedCommand(args.command)
    if (!command || !state.lastFailure) return
    const current = workspaceFingerprint(state.root)
    if (state.lastFailure.command === command && state.lastFailure.workspaceHash === current) {
      throw new Error("BLACK CODE repeat guard: this exact command already failed against the same workspace state. Inspect the failure and change the cause, input, command, or strategy before retrying.")
    }
  },

  "tool.execute.after": async (input, output) => {
    if (!enabled()) return
    const state = stateFor(input?.sessionID, worktree || directory)
    const key = callKey(input)
    const saved = calls.get(key)
    calls.delete(key)
    const tool = input?.tool ?? saved?.tool ?? "unknown"
    const args = saved?.args ?? {}

    if (editLike(tool)) {
      state.verifiedHash = null
      state.token = null
      state.profile = null
      state.priorUnverified = true
      persist(state)
      return
    }

    if (!shellLike(tool)) return
    const command = normalizedCommand(args.command)
    const exitCode = outputExitCode(output)
    const current = workspaceFingerprint(state.root)

    if (exitCode !== null && exitCode !== 0) {
      state.lastFailure = { command, workspaceHash: current }
      persist(state)
      return
    }
    if (exitCode === 0) state.lastFailure = null

    if (exitCode === 0 && isFinalVerifyCommand(command)) {
      state.verifiedHash = current
      state.profile = "governed-final-v2"
      state.token = verificationToken(state, current, command)
      state.priorUnverified = false
      persist(state)
    }
  },

  "experimental.text.complete": async (input, output) => {
    if (!enabled()) return
    const state = stateFor(input?.sessionID, worktree || directory)
    const current = workspaceFingerprint(state.root)
    const changed = current !== state.baselineHash || state.priorUnverified
    const verified = Boolean(state.verifiedHash && state.verifiedHash === current && state.token)
    if (changed && !verified) {
      output.text = [
        "BLACK VERIFY: UNVERIFIED",
        "現在のworkspace状態に束縛されたfinal verification tokenがありません。完成回答は破棄しました。",
        "変更内容を実環境で検証し、最後に `black-code-verify` を成功させてから完了を報告してください。",
      ].join("\n")
    }
    persist(state)
  },

  event: async ({ event } = {}) => {
    if (!enabled() || event?.type !== "session.idle") return
    const id = event?.properties?.info?.id ?? event?.properties?.sessionID ?? event?.sessionID
    if (id && sessions.has(id)) persist(sessions.get(id))
  },
})
