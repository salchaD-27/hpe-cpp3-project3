import json

input_file = "hpcmlog.json"
output_file = "cleaned_logs.json"

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