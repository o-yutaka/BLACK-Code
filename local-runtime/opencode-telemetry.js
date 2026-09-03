import fs from "node:fs"
import path from "node:path"

const starts = new Map()

function nowMs() { return Date.now() }
function sessionOf(input) { return input?.sessionID ?? input?.sessionId ?? input?.session_id ?? "session" }
function explicitCallOf(input) { return input?.callID ?? input?.callId ?? input?.call_id ?? input?.id ?? null }
function classify(tool, args) {
  if (tool !== "bash") return "tool"
  const command = String(args?.command ?? "")
  return /(^|[;&|\s])(test|pytest|jest|vitest|mocha|cargo\s+test|go\s+test|pnpm\b[^;&|]*(test|lint|typecheck|build|verify)|npm\b[^;&|]*(test|lint|typecheck|build|verify)|yarn\b[^;&|]*(test|lint|typecheck|build|verify)|tsc\b|eslint\b|ruff\b|mypy\b)/i.test(command) ? "verify" : "tool"
}
function append(record) {
  const target = process.env.BLACK_CODE_TELEMETRY_PATH
  if (!target) return
  try {
    fs.mkdirSync(path.dirname(target), { recursive: true })
    fs.appendFileSync(target, JSON.stringify(record) + "\n", "utf8")
  } catch {}
}
function findFallback(input) {
  const session = sessionOf(input)
  const tool = input?.tool ?? "unknown"
  for (const [key, value] of starts.entries()) {
    if (value.session === session && value.tool === tool) return key
  }
  for (const [key, value] of starts.entries()) {
    if (value.session === session) return key
  }
  return null
}

export const BlackCodeTelemetry = async () => ({
  "tool.execute.before": async (input, output) => {
    if (!process.env.BLACK_CODE_TELEMETRY_PATH) return
    const call = explicitCallOf(input)
    const key = call ? `${sessionOf(input)}:${call}` : `${sessionOf(input)}:${input?.tool ?? "tool"}:${nowMs()}:${Math.random()}`
    starts.set(key, {
      session: sessionOf(input),
      started_at_ms: nowMs(),
      tool: input?.tool ?? "unknown",
      kind: classify(input?.tool, output?.args),
    })
  },
  "tool.execute.after": async (input) => {
    if (!process.env.BLACK_CODE_TELEMETRY_PATH) return
    const call = explicitCallOf(input)
    let key = call ? `${sessionOf(input)}:${call}` : null
    if (!key || !starts.has(key)) key = findFallback(input)
    const start = key ? starts.get(key) : null
    if (key) starts.delete(key)
    const ended = nowMs()
    append({
      schema_version: "1.0",
      type: "tool_timing",
      recorded_at: new Date(ended).toISOString(),
      tool: start?.tool ?? input?.tool ?? "unknown",
      kind: start?.kind ?? "tool",
      duration_ms: start ? Math.max(0, ended - start.started_at_ms) : null,
      measured: Boolean(start),
    })
  },
})
