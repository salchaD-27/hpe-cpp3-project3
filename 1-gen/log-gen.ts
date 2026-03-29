// High-throughput HPC log generator with streams + multi-file output
// Typical max logs/sec: 50k+ with batching

import fs from "fs"
import path from "path"

const LOG_DIR = "../logs"
fs.mkdirSync(LOG_DIR, { recursive: true })

// File mapping by service (5 files)
const FILE_MAP: Record<string, string> = {
  "slurmd": "slurm.log",
  "kernel": "kernel.log",
  "sshd": "sshd.log",
  "systemd": "system.log",
  "mpi": "system.log",
  "lustre": "storage.log",
  "nfs": "storage.log",
  "ib_core": "storage.log"
}

// Lazy stream writers
const writers: Record<string, fs.WriteStream> = {}

function getWriter(service: string): fs.WriteStream {
  const file = path.join(LOG_DIR, FILE_MAP[service] || "unknown.log")
  if (!writers[file]) {
    writers[file] = fs.createWriteStream(file, { flags: "a" })
  }
  return writers[file]
}

const NODES = Array.from({ length: 24 }, (_, i) =>
  `compute-node-${String(i + 1).padStart(3, "0")}`
)

const JOBS = Array.from({ length: 30 }, () =>
  `job_${Math.floor(Math.random() * 90000 + 10000)}`
)

type Template = {
  level: string
  service: string
  tmpl: string
}

const TEMPLATES: Template[] = [
  { level: "INFO", service: "slurmd", tmpl: "Job {job} started on {node}, CPUs={cpu}, GPUs={gpu}" },
  { level: "INFO", service: "slurmd", tmpl: "Job {job} completed successfully in {dur}s" },
  { level: "WARN", service: "slurmd", tmpl: "Job {job} exceeded walltime limit, terminating" },
  { level: "ERROR", service: "slurmd", tmpl: "Job {job} failed with exit code {code}" },
  { level: "WARN", service: "kernel", tmpl: "OOM killer invoked, killed PID {pid} on {node}" },
  { level: "ERROR", service: "kernel", tmpl: "CPU {cpu_id} machine check error detected" },
  { level: "INFO", service: "sshd", tmpl: "Accepted publickey for user from {node} port {port}" },
  { level: "WARN", service: "systemd", tmpl: "Unit {service} entered failed state" }
]

function rand(min: number, max: number) {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

function pick<T>(arr: T[]): T {
  return arr[rand(0, arr.length - 1)]
}

function format(template: string, values: Record<string, any>) {
  return template.replace(/\{(\w+)\}/g, (_, k) => String(values[k] || ''))
}

function generate() {
  const t = pick(TEMPLATES)
  const node = pick(NODES)

  const stream = t.service === 'slurmd' ? 'slurm' :
                 t.service === 'kernel' ? 'system' :
                 t.service === 'sshd' ? 'access' :
                 t.service === 'systemd' ? 'system' : 'hpc'

  const values = {
    job: pick(JOBS),
    node,
    cpu: rand(1, 128),
    gpu: rand(0, 8),
    dur: rand(60, 86400),
    code: pick([1, 2, 127, 139]),
    pid: rand(1000, 65535),
    cpu_id: rand(0, 127),
    port: rand(20000, 65000),
    service: pick(['mpi-rank-0.service', 'lustre-client.service']),
    stream
  }

  return {
    _msg: format(t.tmpl, values),
    _time: new Date().toISOString(),
    node,
    service: t.service,
    level: t.level,
    job_id: pick(JOBS),
    cluster: "hpc-cluster-01",
    stream
  }
}

const RATE = 200
let count = 0

console.log(`Simulator running at ${RATE} logs/sec across 5 files`)
console.log("Press Ctrl+C to stop")

setInterval(() => {
  for (let i = 0; i < RATE; i++) {
    const log = generate()
    const writer = getWriter(log.service)
    writer.write(JSON.stringify(log) + "\n")
    count++
  }

  if (count % 1000 === 0) {
    console.log(`Generated ${count} logs across ${Object.keys(writers).length} files: ${Object.keys(writers).join(', ')}`)
  }
}, 1000)

process.on("SIGINT", () => {
  console.log(`\nStopped. Total logs generated: ${count} across ${Object.keys(writers).length} files`)
  Object.values(writers).forEach(w => w.end())
  process.exit()
})

