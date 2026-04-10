function format_error(tag, timestamp, record)
    local new_record = {}
    new_record["_msg"] = record["log"] or "Empty error log"
    new_record["level"] = "ERROR"
    new_record["vl_stream"] = "parse_error"
    new_record["host_name"] = "unknown"
    new_record["service_name"] = "unknown"
    new_record["ingest_stage"] = "fluentbit"
    new_record["source_file"] = record["source_file"] or "unknown"
    return 1, timestamp, new_record
end