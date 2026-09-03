import fs from "node:fs"
import path from "node:path"

const starts = new Map()

function nowMs() { return Date.now() }
function keyOf(input) {
  const session = input?.sessionID ?? input?.sessionId ?? input?.session_id ?? "session"
  const call = input?.callID ?? input?.callId ?? input?.call_id ?? input?.id ?? `${input?.tool ?? "tool"}:${nowMs()}:${Math.random()}`
  return `${session}:${call}`
}
function classify(tool, args) {
  if (tool !== "bash") return "tool"
  const command = String(args?.command ?? "")
  return /(^|[;&|\s])(test|pytest|jest|vitest|mocha|cargo\s+test|go\s+test|pnpm\s+(run\s+)?(test|lint|typecheck|build|verify)|npm\s+(run\s+)?(test|lint|typecheck|build|verify)|yarn\s+(test|lint|typecheck|build|verify)|tsc\b|eslint\b|ruff\b|mypy\b)/i.test(command) ? "verify" : "tool"
}
function append(record) {
  const target = process.env.BLACK_CODE_TELEMETRY_PATH
  if (!target) return
  try {
    fs.mkdirSync(path.dirname(target), { recursive: true })
    fs.appendFileSync(target, JSON.stringify(record) + "\n", "utf8")
  } catch {}
}

export const BlackCodeTelemetry = async () => ({
  "tool.execute.before": async (input, output) => {
    if (!process.env.BLACK_CODE_TELEMETRY_PATH) return
    const key = keyOf(input)
    starts.set(key, { started_at_ms: nowMs(), tool: input?.tool ?? "unknown", kind: classify(input?.tool, output?.args), command: input?.tool === "bash" ? String(output?.args?.command ?? "").slice(0, 500) : null })
    try { Object.defineProperty(output, "__blackCodeTelemetryKey", { value: key, enumerable: false, configurable: true }) } catch {}
  },
  "tool.execute.after": async (input, output) => {
    if (!process.env.BLACK_CODE_TELEMETRY_PATH) return
    const hinted = output?.__blackCodeTelemetryKey
    let key = hinted && starts.has(hinted) ? hinted : null
    if (!key) {
      const prefix = `${input?.sessionID ?? input?.sessionId ?? input?.session_id ?? "session"}:`
      for (const candidate of starts.keys()) { if (candidate.startsWith(prefix)) { key = candidate; break } }
    }
    const start = key ? starts.get(key) : null
    if (key) starts.delete(key)
    const ended = nowMs()
    append({ schema_version: "1.0", type: "tool_timing", recorded_at: new Date(ended).toISOString(), tool: start?.tool ?? input?.tool ?? "unknown", kind: start?.kind ?? "tool", duration_ms: start ? Math.max(0, ended - start.started_at_ms) : null, command: start?.command ?? null, measured: Boolean(start) })
  },
})
