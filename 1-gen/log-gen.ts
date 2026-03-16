// | Method                                       | Typical max logs/sec |
// | -------------------------------------------- | -------------------- |
// | appendFileSync (older implementation)        | ~2k                  |
// | write stream batching                        | 50k+                 |
// | write stream + worker threads                | 200k+                |

import fs from "fs"
import path from "path"

const LOG_DIR = "../logs"
const LOG_FILE = path.join(LOG_DIR, "hpc-cluster.log")

fs.mkdirSync(LOG_DIR, { recursive: true })

// high-throughput stream writer
const stream = fs.createWriteStream(LOG_FILE, { flags: "a" })

const NODES = Array.from({ length: 24 }, (_, i) =>
  `compute-node-${String(i + 1).padStart(3, "0")}`
)

const SERVICES = [
  "slurmd",
  "sshd",
  "kernel",
  "mpi",
  "lustre",
  "ib_core",
  "nfs",
  "systemd"
]

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
  { level: "ERROR", service: "kernel", tmpl: "CPU {cpu_id} machine check error detected" }
]

function rand(min: number, max: number) {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

function pick<T>(arr: T[]): T {
  return arr[rand(0, arr.length - 1)]
}

function format(template: string, values: Record<string, any>) {
  return template.replace(/\{(\w+)\}/g, (_, k) => values[k])
}

function generate() {
  const t = pick(TEMPLATES)
  const node = pick(NODES)

  const values = {
    job: pick(JOBS),
    node,
    cpu: rand(1, 128),
    gpu: rand(0, 8),
    dur: rand(60, 86400),
    code: pick([1, 2, 127, 139]),
    pid: rand(1000, 65535),
    cpu_id: rand(0, 127)
  }

  return {
    _msg: format(t.tmpl, values),
    _time: new Date().toISOString(),
    node,
    service: t.service,
    level: t.level,
    job_id: pick(JOBS),
    cluster: "hpc-cluster-01"
  }
}

/*
Logs per second.
You can safely increase this to:
1000+
5000+
*/
const RATE = 200

let count = 0

console.log(`Simulator running at ${RATE} logs/sec`)
console.log("Press Ctrl+C to stop")

setInterval(() => {

  let batch = ""

  for (let i = 0; i < RATE; i++) {
    const log = generate()
    batch += JSON.stringify(log) + "\n"
    count++
  }

  stream.write(batch)

  if (count % 1000 === 0) {
    console.log(`Generated ${count} logs`)
  }

}, 1000)

// graceful shutdown
process.on("SIGINT", () => {
  console.log(`\nStopped. Total logs generated: ${count}`)
  stream.end()
  process.exit()
})