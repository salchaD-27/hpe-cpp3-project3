import json
import os

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# hpcmlog.json
input_file = os.path.join(BASE_DIR, "sample/hpcmlog.json")
output_file = os.path.join(BASE_DIR, "data/cleaned_logs_hpcm.json")

# monitoring_service.json
#input_file = os.path.join(BASE_DIR, "sample/monitoring_service.json")
#output_file = os.path.join(BASE_DIR, "data/cleaned_logs1.json")

# syslog.json
#input_file = os.path.join(BASE_DIR, "sample/syslog.json")
#output_file = os.path.join(BASE_DIR, "data/cleaned_logs2.json")s

def extract_required_fields(log_data):
    extracted_logs = []

    hits = log_data.get("hits", {}).get("hits", [])

    for entry in hits:
        source = entry.get("_source", {})

        filtered_entry = {
            "Resource": source.get("Resource", {}),
            "Attributes": source.get("Attributes", {}),
            "Body": source.get("Body", ""),
            "SeverityText": source.get("SeverityText", "")
        }

        extracted_logs.append(filtered_entry)

    return extracted_logs


def main():
    with open(input_file, "r") as f:
        data = json.load(f)

    cleaned_logs = extract_required_fields(data)

    # Write as JSON array
    with open(output_file, "w") as f:
        json.dump(cleaned_logs, f, indent=2)

    print(f"Extracted {len(cleaned_logs)} logs to {output_file}")


if __name__ == "__main__":
    main()