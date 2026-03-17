import json, time, random, datetime, argparse

LEVELS   = ['INFO','INFO','INFO','WARN','ERROR']
HOSTS    = [f'node-{i:02d}' for i in range(1, 6)]
JOBS     = [f'job-{random.randint(1000,9999)}' for _ in range(10)]
MESSAGES = {
  'INFO':  ['Job submitted','Checkpoint saved','CPU usage normal','Task completed'],
  'WARN':  ['Memory above 80%','CPU throttling','Disk below 20%'],
  'ERROR': ['Node unreachable','Job failed: OOM','Disk write error','Kernel panic'],
}

def make_log():
    level = random.choice(LEVELS)
    return {
        '_time': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
        '_msg':  random.choice(MESSAGES[level]),
        'level': level, 'host': random.choice(HOSTS),
        'job':   random.choice(JOBS), 'pid': random.randint(1000, 99999),
    }

parser = argparse.ArgumentParser()
parser.add_argument('--rate',   type=int, default=10)
parser.add_argument('--output', default='/tmp/hpc-simulator.log')
args = parser.parse_args()
print(f'Simulator: {args.rate} logs/sec -> {args.output}')
with open(args.output, 'a') as f:
    while True:
        f.write(json.dumps(make_log()) + '\n')
        f.flush()
        time.sleep(1.0 / args.rate)
