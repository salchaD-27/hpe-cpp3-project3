import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const LOG_FILES = [
    ["syslog.json", "syslog.jsonl"],
    ["hpcmlog.json", "hpcmlog.jsonl"],
    ["monitoring_service.json", "monitoring_service.jsonl"],
];
const INPUT_DIR = path.join(__dirname, "logs-original");
const OUTPUT_DIR = "/logs-generated";
const RATE = 5;
// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}
function loadLogs(filename) {
    const filePath = path.join(INPUT_DIR, filename);
    if (!fs.existsSync(filePath)) {
        console.error(`File not found: ${filePath}`);
        return [];
    }
    const raw = fs.readFileSync(filePath, "utf-8");
    // Fixed typo: ElasticasticsearchResponse → ElasticsearchResponse
    const data = JSON.parse(raw);
    const hits = data.hits?.hits ?? [];
    // Added explicit type for 'hit' parameter
    return hits.map((hit) => {
        const src = hit._source ?? {};
        return {
            Resource: src.Resource ?? {},
            Body: src.Body ?? "",
            Severity: (src.Severity ?? src.SeverityText ?? "info").toUpperCase(),
            Attributes: src.Attributes ?? {},
        };
    });
}
console.log("Loading logs...");
const allLogs = {};
for (const [inputFile, outputFile] of LOG_FILES) {
    const logs = loadLogs(inputFile);
    allLogs[outputFile] = logs;
    console.log(`  Loaded ${logs.length} entries from ${inputFile}`);
}
console.log(`Starting simulation at ${RATE} logs/sec per file...`);
console.log("Press Ctrl+C to stop.");
// Remove existing output files
for (const [, outputFile] of LOG_FILES) {
    const filePath = path.join(OUTPUT_DIR, outputFile);
    if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
    }
}
// Open file handles
const handles = {};
for (const [, outputFile] of LOG_FILES) {
    const filePath = path.join(OUTPUT_DIR, outputFile);
    handles[outputFile] = fs.createWriteStream(filePath, { flags: "a" });
}
const positions = {};
for (const [, outputFile] of LOG_FILES) {
    positions[outputFile] = 0;
}
const interval = setInterval(() => {
    for (const [, outputFile] of LOG_FILES) {
        const logs = allLogs[outputFile];
        if (!logs || logs.length === 0)
            continue;
        const pos = positions[outputFile];
        const entry = { ...logs[pos % logs.length] };
        // Add timestamp
        entry.Body = `[${new Date().toISOString()}] ${entry.Body}`;
        handles[outputFile].write(JSON.stringify(entry) + "\n");
        positions[outputFile] = (pos + 1) % logs.length;
    }
}, 1000 / RATE);
process.on("SIGINT", () => {
    console.log("\nStopping simulator.");
    clearInterval(interval);
    for (const handle of Object.values(handles)) {
        handle.end();
    }
    process.exit(0);
});
