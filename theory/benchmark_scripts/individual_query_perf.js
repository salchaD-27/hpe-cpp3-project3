import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    stages: [
        { duration: '2m', target: 50 },  // Ramp up to 50 concurrent analytical consumers
        { duration: '10m', target: 50 }, // Sustain heavy read stress concurrent to ingestion
        { duration: '1m', target: 0 },   // Ramp down
    ],
};

export default function () {
    // Array of heavy analytical LogsQL queries to cycle through
    const queries = [
        'log.level:error | stats count(*) by service.name',
        '_time:15m AND status:500 | fields _time, message, trace_id',
        '"exception" | stats count(*) by k8s.pod.name | sort by count(*) desc'
    ];
    
    const randomQuery = queries[Math.floor(Math.random() * queries.length)];
    const url = 'http://localhost:9428/select/logsql/query';
    
    const payload = `query=${encodeURIComponent(randomQuery)}`;
    const params = {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    };

    let res = http.post(url, payload, params);
    check(res, { 'status is 200': (r) => r.status === 200 });
    sleep(0.5); // 500ms delay between consecutive dashboard refreshes per user
}