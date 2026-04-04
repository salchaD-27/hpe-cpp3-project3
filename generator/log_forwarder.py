import json
import time
import os

INPUT_FILE = "cleaned_logs.json"   # JSONL or JSON array
OUTPUT_FILE = "/logs/hpc_logs.json"
DELAY = 0.1   # seconds between logs (tune for throughput)

def stream_logs():
    # Ensure output directory exists
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)

    # Detect format (JSON array vs JSONL)
    with open(INPUT_FILE, "r") as f:
        first_char = f.read(1)

    # JSON ARRAY MODE
    if first_char == "[":
        with open(INPUT_FILE, "r") as f:
            data = json.load(f)

        logs = data

    # JSONL MODE (preferred)
    else:
        with open(INPUT_FILE, "r") as f:
            logs = [json.loads(line) for line in f if line.strip()]

    print(f"Streaming {len(logs)} logs...")

    # Append logs continuously
    with open(OUTPUT_FILE, "a") as out:
        for log in logs:
            out.write(json.dumps(log) + "\n")
            out.flush()  # important for real-time ingestion

            print(f"Sent log: {log.get('SeverityText', '')}")

            time.sleep(DELAY)


if __name__ == "__main__":
    stream_logs()