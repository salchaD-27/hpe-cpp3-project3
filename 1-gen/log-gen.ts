import fs from "fs"
import path from "path"

const LOG_DIR = "../logs"
const LOG_FILE = path.join(LOG_DIR, "hpc-cluster.log")

fs.mkdirSync(LOG_DIR, { recursive: true })

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

const RATE = 20
let count = 0

console.log(`Simulator running at ${RATE} logs/sec`)

setInterval(() => {
  const log = generate()

  fs.appendFileSync(LOG_FILE, JSON.stringify(log) + "\n")

  count++

  if (count % 100 === 0) {
    console.log(
      `[${count.toString().padStart(6)}] [${log.level.padEnd(5)}] ${log.node} | ${log._msg.slice(0, 55)}`
    )
  }
}, 1000 / RATE)