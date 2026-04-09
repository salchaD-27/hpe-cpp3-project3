# Simulator

Generates structured JSON log events to `/tmp/hpc-simulator.log`.

## Run
```bash
python3 simulator.py --rate 5
```
Each log contains: `_time`, `_msg`, `level`, `host`, `job`, `pid`
