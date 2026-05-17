const fs = require('fs');
const path = require('path');

const OUTPUT_DIR = '/logs-generated';

// Synthetic log data
const LOG_TYPES = ['hpcmlog', 'monitoring_service', 'syslog'];
const HOSTS = ['leader1', 'leader2', 'leader3', 'padma', 'worker1', 'worker2'];
const SERVICES = {
    hpcmlog: ['glusterd', 'cli', 'data-brick_ctdb', 'cmuserver-0', 'sensormon_v2'],
    monitoring_service: ['kafka', 'opensearch', 'prometheus', 'zookeeper'],
    syslog: ['systemd', 'sudo', 'cron', 'sshd', 'kernel']
};
const SEVERITIES = ['INFO', 'WARN', 'ERROR', 'DEBUG'];

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

let counters = {
    hpcmlog: 0,
    monitoring_service: 0,
    syslog: 0
};

console.log(`[${new Date().toISOString()}] Synthetic log generator started`);
console.log(`Output directory: ${OUTPUT_DIR}`);
console.log(`Generating logs for: ${LOG_TYPES.join(', ')}`);

function generateLogForType(logType) {
    const host = HOSTS[Math.floor(Math.random() * HOSTS.length)];
    const service = SERVICES[logType][Math.floor(Math.random() * SERVICES[logType].length)];
    const severity = SEVERITIES[Math.floor(Math.random() * SEVERITIES.length)];
    
    const logEntry = {
        "@timestamp": new Date().toISOString(),
        "Body": `[${new Date().toISOString()}] ${severity}: [${service}] Operation from ${host}`,
        "Severity": severity,
        "Resource": {
            "host.name": host,
            "service.name": service
        },
        "Attributes": {
            "pid": Math.floor(Math.random() * 10000),
            "counter": ++counters[logType]
        },
        "source_file": `/logs/${logType}.log`
    };
    
    const filePath = path.join(OUTPUT_DIR, `${logType}.jsonl`);
    fs.appendFileSync(filePath, JSON.stringify(logEntry) + '\n');
    return logEntry;
}

let totalGenerated = 0;

// Generate logs at 5 per second per type (15 total/sec)
setInterval(() => {
    for (const logType of LOG_TYPES) {
        generateLogForType(logType);
        totalGenerated++;
    }
    
    if (totalGenerated % 30 === 0) {
        console.log(`[${new Date().toISOString()}] Generated ${totalGenerated} total logs`);
    }
}, 200);

// Keep process alive
process.stdin.resume();