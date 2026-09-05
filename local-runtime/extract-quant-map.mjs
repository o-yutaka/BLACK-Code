import fs from "node:fs"

const [, , url, outputPath, localGgufPath] = process.argv
if (!url || !outputPath) {
  console.error("usage: node extract-quant-map.mjs <remote-gguf-url> <output-tensor-types.txt> [local-gguf-to-compare]")
  process.exit(2)
}

const TYPE = new Map([
  [0, "f32"], [1, "f16"], [2, "q4_0"], [3, "q4_1"], [6, "q5_0"], [7, "q5_1"],
  [8, "q8_0"], [9, "q8_1"], [10, "q2_k"], [11, "q3_k"], [12, "q4_k"], [13, "q5_k"],
  [14, "q6_k"], [15, "q8_k"], [16, "iq2_xxs"], [17, "iq2_xs"], [18, "iq3_xxs"],
  [19, "iq1_s"], [20, "iq4_nl"], [21, "iq3_s"], [22, "iq2_s"], [23, "iq4_xs"],
  [24, "i8"], [25, "i16"], [26, "i32"], [27, "i64"], [28, "f64"], [29, "iq1_m"],
  [30, "bf16"], [34, "tq1_0"], [35, "tq2_0"], [39, "mxfp4"], [40, "nvfp4"],
  [41, "q1_0"], [42, "q2_0"],
])

class NeedMore extends Error {}

function makeReader(buffer) {
  let p = 0
  const need = (n) => { if (p + n > buffer.length) throw new NeedMore() }
  const u8 = () => { need(1); return buffer[p++] }
  const i8 = () => { need(1); return buffer.readInt8(p++) }
  const u16 = () => { need(2); const v = buffer.readUInt16LE(p); p += 2; return v }
  const i16 = () => { need(2); const v = buffer.readInt16LE(p); p += 2; return v }
  const u32 = () => { need(4); const v = buffer.readUInt32LE(p); p += 4; return v }
  const i32 = () => { need(4); const v = buffer.readInt32LE(p); p += 4; return v }
  const f32 = () => { need(4); const v = buffer.readFloatLE(p); p += 4; return v }
  const u64 = () => { need(8); const v = buffer.readBigUInt64LE(p); p += 8; if (v > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("GGUF integer exceeds JS safe range"); return Number(v) }
  const i64 = () => { need(8); const v = buffer.readBigInt64LE(p); p += 8; if (v > BigInt(Number.MAX_SAFE_INTEGER) || v < BigInt(Number.MIN_SAFE_INTEGER)) throw new Error("GGUF integer exceeds JS safe range"); return Number(v) }
  const f64 = () => { need(8); const v = buffer.readDoubleLE(p); p += 8; return v }
  const str = () => { const n = u64(); need(n); const v = buffer.toString("utf8", p, p + n); p += n; return v }
  const skip = (n) => { need(n); p += n }
  const value = (type) => {
    switch (type) {
      case 0: return u8()
      case 1: return i8()
      case 2: return u16()
      case 3: return i16()
      case 4: return u32()
      case 5: return i32()
      case 6: return f32()
      case 7: return u8()
      case 8: return str()
      case 9: {
        const itemType = u32(); const count = u64()
        for (let i = 0; i < count; i++) value(itemType)
        return null
      }
      case 10: return u64()
      case 11: return i64()
      case 12: return f64()
      default: throw new Error(`unsupported GGUF metadata value type ${type}`)
    }
  }
  return { u32, u64, str, value, skip, position: () => p }
}

function parse(buffer, sourceLabel) {
  if (buffer.length < 4 || buffer.subarray(0, 4).toString("ascii") !== "GGUF") throw new Error(`${sourceLabel} is not GGUF`)
  const r = makeReader(buffer)
  r.skip(4)
  const version = r.u32()
  if (version < 2 || version > 3) throw new Error(`unsupported GGUF version ${version}`)
  const tensorCount = r.u64()
  const kvCount = r.u64()
  for (let i = 0; i < kvCount; i++) { r.str(); r.value(r.u32()) }
  const tensors = []
  for (let i = 0; i < tensorCount; i++) {
    const name = r.str()
    const dims = r.u32()
    for (let d = 0; d < dims; d++) r.u64()
    const dtypeNumber = r.u32()
    r.u64()
    if (!TYPE.has(dtypeNumber)) throw new Error(`unsupported GGML dtype ${dtypeNumber} on tensor ${name}`)
    tensors.push({ name, dtype: TYPE.get(dtypeNumber) })
  }
  return { version, tensorCount, tensors, parsedBytes: r.position() }
}

async function fetchRemotePrefix(bytes) {
  const response = await fetch(url, { headers: { Range: `bytes=0-${bytes - 1}` }, redirect: "follow" })
  if (response.status !== 206) {
    try { await response.body?.cancel() } catch {}
    throw new Error(`remote GGUF must support byte ranges; expected HTTP 206, got ${response.status}`)
  }
  const contentRange = response.headers.get("content-range") || ""
  if (!contentRange.toLowerCase().startsWith("bytes 0-")) throw new Error(`invalid Content-Range: ${contentRange}`)
  return Buffer.from(await response.arrayBuffer())
}

function readLocalPrefix(filePath, bytes) {
  const fd = fs.openSync(filePath, "r")
  try {
    const length = Math.min(bytes, fs.fstatSync(fd).size)
    const buffer = Buffer.allocUnsafe(length)
    fs.readSync(fd, buffer, 0, length, 0)
    return buffer
  } finally { fs.closeSync(fd) }
}

async function parseWithGrowth(readPrefix, label) {
  for (let bytes = 1024 * 1024; bytes <= 64 * 1024 * 1024; bytes *= 2) {
    const buffer = await readPrefix(bytes)
    try { return parse(buffer, label) }
    catch (error) {
      if (error instanceof NeedMore) continue
      throw error
    }
  }
  throw new Error(`${label} tensor directory exceeded 64 MiB`)
}

const reference = await parseWithGrowth(fetchRemotePrefix, "remote reference")
if (new Set(reference.tensors.map((t) => t.name)).size !== reference.tensorCount) throw new Error("duplicate tensor names in GGUF reference")

if (localGgufPath) {
  if (!fs.existsSync(localGgufPath)) throw new Error(`local GGUF missing: ${localGgufPath}`)
  const local = await parseWithGrowth((bytes) => Promise.resolve(readLocalPrefix(localGgufPath, bytes)), "local F16 GGUF")
  const referenceNames = reference.tensors.map((t) => t.name).sort()
  const localNames = local.tensors.map((t) => t.name).sort()
  const missing = referenceNames.filter((name) => !localNames.includes(name))
  const extra = localNames.filter((name) => !referenceNames.includes(name))
  if (missing.length || extra.length) {
    throw new Error(`tensor inventory mismatch: reference=${referenceNames.length} local=${localNames.length} missing=${missing.slice(0, 8).join(",")} extra=${extra.slice(0, 8).join(",")}`)
  }
}

const escapeRegex = (name) => name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
const lines = reference.tensors.map(({ name, dtype }) => `^${escapeRegex(name)}$=${dtype}`)
fs.writeFileSync(outputPath, lines.join("\n") + "\n", "utf8")
console.log(JSON.stringify({ status: "PASS", version: reference.version, tensors: reference.tensorCount, parsed_bytes: reference.parsedBytes, output: outputPath, local_inventory_checked: Boolean(localGgufPath) }))
