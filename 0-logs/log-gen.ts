// Simulator running at 20 logs/sec — Ctrl+C to stop
// ------------------------------------------------------------
// {"level":"ERROR","timestamp":"2026-03-16T17:56:28.806Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"localhost:9092","clientId":"hpc-simulator","error":"This server does not host this topic-partition","correlationId":1,"size":82}
// {"level":"ERROR","timestamp":"2026-03-16T17:56:28.808Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"localhost:9092","clientId":"hpc-simulator","error":"This server does not host this topic-partition","correlationId":2,"size":82}
// {"level":"ERROR","timestamp":"2026-03-16T17:56:28.809Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"localhost:9092","clientId":"hpc-simulator","error":"This server does not host this topic-partition","correlationId":3,"size":82}
// {"level":"ERROR","timestamp":"2026-03-16T17:56:28.811Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"localhost:9092","clientId":"hpc-simulator","error":"This server does not host this topic-partition","correlationId":4,"size":82}
// {"level":"ERROR","timestamp":"2026-03-16T17:56:28.851Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"localhost:9092","clientId":"hpc-simulator","error":"This server does not host this topic-partition","correlationId":5,"size":82}
// [   100] [INFO ] compute-node-005 | Login accepted for alice from 10.0.8.21
// [   200] [WARN ] compute-node-007 | MPI rank 265 communication timeout after 4723ms
// [   300] [WARN ] compute-node-007 | Job job_48868 exceeded walltime limit, terminating
// [   400] [WARN ] compute-node-010 | OOM killer invoked, killed PID 64644 on compute-node-01
// [   500] [INFO ] compute-node-014 | Job job_82001 completed successfully in 49055s
// [   600] [ERROR] compute-node-024 | InfiniBand port 0 link down unexpectedly
// ...
// ------------------------------------------------------------
// Stopped. Total logs sent: 659


import { Kafka } from "kafkajs"
import fs from "fs"
import path from "path"

const LOG_DIR = "./logs"
const LOG_FILE = path.join(LOG_DIR, "hpc-cluster.log")

fs.mkdirSync(LOG_DIR, { recursive: true })

const NODES = Array.from({ length: 24 }, (_, i) => `compute-node-${String(i + 1).padStart(3, "0")}`)

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
  { level: "ERROR", service: "kernel", tmpl: "CPU {cpu_id} machine check error detected" },
  { level: "INFO", service: "kernel", tmpl: "NUMA node {numa} memory at {pct}%" },

  { level: "INFO", service: "ib_core", tmpl: "InfiniBand ib{port} link up at {speed}Gb/s" },
  { level: "ERROR", service: "ib_core", tmpl: "InfiniBand port {port} link down unexpectedly" },
  { level: "WARN", service: "mpi", tmpl: "MPI rank {rank} communication timeout after {ms}ms" },

  { level: "WARN", service: "lustre", tmpl: "Filesystem /scratch at {pct}% capacity" },
  { level: "ERROR", service: "lustre", tmpl: "Lustre OST {ost} I/O error detected" },
  { level: "INFO", service: "nfs", tmpl: "NFS /home response time {ms}ms" },

  { level: "INFO", service: "sshd", tmpl: "Login accepted for {user} from {ip}" },
  { level: "WARN", service: "sshd", tmpl: "Failed authentication attempt from {ip}" },
  { level: "ERROR", service: "sshd", tmpl: "Too many auth failures from {ip}, blocking" }
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
    cpu_id: rand(0, 127),
    numa: rand(0, 3),
    pct: rand(60, 99),
    port: rand(0, 3),
    speed: pick([100, 200, 400]),
    rank: rand(0, 511),
    ms: rand(100, 5000),
    ost: rand(0, 15),
    user: pick(["alice", "bob", "carol", "research01", "admin"]),
    ip: `10.0.${rand(1, 10)}.${rand(1, 254)}`
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

const kafka = new Kafka({
  clientId: "hpc-simulator",
  brokers: ["localhost:9092"]
})

const producer = kafka.producer()

const RATE = 20
let count = 0

async function start() {
  console.log("Connecting to Kafka...")

  await producer.connect()

  console.log("Connected to Kafka OK")
  console.log(`Simulator running at ${RATE} logs/sec — Ctrl+C to stop`)
  console.log("-".repeat(60))

  setInterval(async () => {
    try {
      const log = generate()

      await producer.send({
        topic: "hpc-logs",
        messages: [{ value: JSON.stringify(log) }]
      })

      fs.appendFileSync(LOG_FILE, JSON.stringify(log) + "\n")

      count++

      if (count % 100 === 0) {
        console.log(
          `[${count.toString().padStart(6)}] [${log.level.padEnd(5)}] ${log.node} | ${log._msg.slice(0, 55)}`
        )
      }
    } catch (err) {
      console.error("Error:", err)
    }
  }, 1000 / RATE)
}

start()

process.on("SIGINT", async () => {
  console.log(`\nStopped. Total logs sent: ${count}`)
  await producer.disconnect()
  process.exit(0)
})