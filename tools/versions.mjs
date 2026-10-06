#!/usr/bin/env node
// Lists the Node.js versions to build: the latest release of every maintained line (Node.js release schedule),
// minus the ones already published on Docker Hub.
//
// Usage: node tools/versions.mjs            prints the build matrix as JSON
// Environment:
//   IMAGE       Docker Hub repository checked for existing tags (owner/name); empty: nothing is considered published
//   MIN_MAJOR   oldest line built (default 24, the oldest line with an upstream pointer-compression binary)
//   ONLY        build this version (24.21.0) or this line (24) only, published or not
//   FORCE       "true": rebuild the versions already published
//   TODAY       date used to read the schedule (default: today, YYYY-MM-DD)
const IMAGE = process.env.IMAGE ?? ''
const MIN_MAJOR = Number(process.env.MIN_MAJOR || 24)
const ONLY = (process.env.ONLY ?? '').replace(/^v/, '')
const FORCE = process.env.FORCE === 'true'
const today = process.env.TODAY || new Date().toISOString().slice(0, 10)

const json = async (url) => {
  const r = await fetch(url)
  if (!r.ok) throw new Error(`${r.status} ${url}`)
  return r.json()
}

const [schedule, releases] = await Promise.all([
  json('https://raw.githubusercontent.com/nodejs/Release/main/schedule.json'),
  json('https://nodejs.org/dist/index.json'),
])

// maintained lines: started, not past their end of life
const lines = Object.entries(schedule)
  .map(([name, s]) => ({ major: Number(name.replace(/^v/, '')), ...s }))
  .filter((l) => Number.isInteger(l.major) && l.major >= MIN_MAJOR && l.start <= today && l.end > today)
  .sort((a, b) => b.major - a.major)

// index.json lists releases newest first
const latestOf = (major) => releases.find((r) => r.version.startsWith(`v${major}.`))?.version.slice(1)

const newest = lines[0]?.major
const lts = lines.find((l) => l.lts && l.lts <= today)?.major

const published = async (tag) => {
  if (!IMAGE) return false
  const r = await fetch(`https://hub.docker.com/v2/repositories/${IMAGE}/tags/${tag}`)
  if (r.status === 200) return true
  if (r.status === 404) return false
  throw new Error(`${r.status} Docker Hub ${IMAGE}:${tag}`)
}

const include = []
for (const line of lines) {
  let version = latestOf(line.major)
  if (!version) continue
  if (ONLY) {
    if (ONLY.includes('.')) {
      if (!ONLY.startsWith(`${line.major}.`)) continue
      if (!releases.some((r) => r.version === `v${ONLY}`)) throw new Error(`unknown Node.js version ${ONLY}`)
      version = ONLY
    } else if (Number(ONLY) !== line.major) continue
  }
  if (!ONLY && !FORCE && (await published(`${version}-alpine`))) continue
  // moving tags only follow the latest release of a line
  const aliases = version === latestOf(line.major) ? [String(line.major), ...(line.major === lts ? ['lts'] : []), ...(line.major === newest ? ['current'] : [])] : []
  include.push({
    version,
    major: line.major,
    // tag prefixes: "<prefix>-alpine" and "<prefix>-alpine-slim"
    tags: [version, ...aliases].join(' '),
    // the newest LTS line (the newest line while none is LTS) also gets the bare tags: "alpine" / "latest", "alpine-slim" / "slim"
    latest: version === latestOf(line.major) && line.major === (lts ?? newest),
  })
}

console.log(JSON.stringify({ include }))
