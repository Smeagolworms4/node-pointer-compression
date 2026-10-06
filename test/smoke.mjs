// Smoke test of a built image: run inside the container, `node /test/smoke.mjs <expected version>`.
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import v8 from 'node:v8'
import { gzipSync, gunzipSync } from 'node:zlib'

const expected = process.argv[2]
if (expected) assert.equal(process.version, `v${expected}`)

// the point of the image
assert.equal(process.config.variables.v8_enable_pointer_compression, 1, 'pointer compression is not enabled')
// a compressed heap cannot exceed 4 GB
assert.ok(v8.getHeapStatistics().heap_size_limit <= 4 * 1024 ** 3, 'heap limit above 4 GB')

// tagged pointers are 4 bytes: a million small objects stay well under what 8-byte pointers would need
const before = process.memoryUsage().heapUsed
const objects = Array.from({ length: 1_000_000 }, (_, i) => ({ a: i, b: null, c: null, d: null }))
const perObject = (process.memoryUsage().heapUsed - before) / objects.length
assert.ok(perObject < 40, `objects take ${perObject.toFixed(1)} bytes each, expected under 40 with compressed pointers`)

// the rest of the runtime still works
assert.equal(createHash('sha256').update('node').digest('hex').length, 64)
assert.equal(gunzipSync(gzipSync('pointer compression')).toString(), 'pointer compression')
assert.equal(new Intl.NumberFormat('fr-FR').format(1234.5), '1 234,5', 'full ICU data is missing')
const wasm = new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from([0, 97, 115, 109, 1, 0, 0, 0, 1, 7, 1, 96, 2, 127, 127, 1, 127, 3, 2, 1, 0, 7, 7, 1, 3, 97, 100, 100, 0, 0, 10, 9, 1, 7, 0, 32, 0, 32, 1, 106, 11])))
assert.equal(wasm.exports.add(2, 3), 5)

console.log(`ok ${process.version} ${process.arch} musl, pointer compression on, ${perObject.toFixed(1)} bytes per small object, heap limit ${Math.round(v8.getHeapStatistics().heap_size_limit / 1024 ** 2)} MB`)
