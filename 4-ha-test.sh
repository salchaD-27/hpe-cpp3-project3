# ── PHASE 1: Kill vlstorage-1, send log A ──────────────────────────

echo "=== Stopping vlstorage-1 ==="
cd node-5-vlstorage-1 && docker compose stop && cd ..

sleep 2

echo "=== Sending Log A (node 1 is DOWN) ==="
curl -X POST http://localhost:9429/insert/jsonline \
  -H "Content-Type: application/json" \
  -d '{"_msg":"ha_test_log_A","level":"ERROR","_time":"2026-06-14T15:00:00Z","ha_phase":"1_node1_down"}'

sleep 10

echo "=== Query state while node 1 is still DOWN ==="
echo "--- vlstorage-1 (DOWN — expect error or empty) ---"
curl -s "http://localhost:8002/select/logsql/query?query=ha_test_log_A" 2>&1

echo "--- vlstorage-2 (UP — expect result) ---"
curl -s "http://localhost:8003/select/logsql/query?query=ha_test_log_A"

echo "--- vlstorage-3 (UP — expect result) ---"
curl -s "http://localhost:8004/select/logsql/query?query=ha_test_log_A"

echo "--- vlselect fan-out (partial results from nodes 2+3) ---"
curl -s "http://localhost:8005/select/logsql/query?query=ha_test_log_A%20%7C%20uniq%20by%20(_time%2C_msg)"


# Check if partial responses are enabled
PARTIAL_CHECK=$(docker exec node-8-vlselect ps aux | grep -c "allowPartialResponse" || echo "0")
if [ "$PARTIAL_CHECK" -eq 0 ]; then
    echo "⚠️ WARNING: -search.allowPartialResponse not enabled in vlselect"
    echo "   Queries will fail when any storage node is down!"
fi

# ── RESTORE node 1, verify vlagent replays ──────────────────────────

echo ""
echo "=== Restoring vlstorage-1 ==="
cd node-5-vlstorage-1 && docker compose start && cd ..

echo "Waiting 20s for vlagent to replay buffered log A to node 1..."
sleep 20

echo "=== Node 1 after restore — should now have log A ==="
curl -s "http://localhost:8002/select/logsql/query?query=ha_test_log_A"

# ── PHASE 2: Kill nodes 2 and 3, send log B ─────────────────────────

echo ""
echo "=== Stopping vlstorage-2 and vlstorage-3 ==="
cd node-6-vlstorage-2 && docker compose stop && cd ..
cd node-7-vlstorage-3 && docker compose stop && cd ..

sleep 2

echo "=== Sending Log B (nodes 2 and 3 are DOWN) ==="
curl -X POST http://localhost:9429/insert/jsonline \
  -H "Content-Type: application/json" \
  -d '{"_msg":"ha_test_log_B","level":"CRITICAL","_time":"2026-06-14T15:05:00Z","ha_phase":"2_nodes23_down"}'

sleep 10

echo "=== Query state while nodes 2+3 are DOWN ==="
echo "--- vlstorage-1 (UP — expect log B) ---"
curl -s "http://localhost:8002/select/logsql/query?query=ha_test_log_B"

echo "--- vlstorage-2 (DOWN — expect error) ---"
curl -s "http://localhost:8003/select/logsql/query?query=ha_test_log_B" 2>&1

echo "--- vlstorage-3 (DOWN — expect error) ---"
curl -s "http://localhost:8004/select/logsql/query?query=ha_test_log_B" 2>&1

echo "--- vlselect (partial — only node 1 responds) ---"
curl -s "http://localhost:8005/select/logsql/query?query=ha_test_log_B%20%7C%20uniq%20by%20(_time%2C_msg)"

# ── RESTORE nodes 2 and 3, verify replay ────────────────────────────

echo ""
echo "=== Restoring vlstorage-2 and vlstorage-3 ==="
cd node-6-vlstorage-2 && docker compose start && cd ..
cd node-7-vlstorage-3 && docker compose start && cd ..

echo "Waiting 20s for vlagent to replay buffered log B to nodes 2 and 3..."
sleep 20

echo "=== Final verification — ALL nodes should have BOTH logs ==="
for port in 8002 8003 8004; do
  echo "--- Storage $port ---"
  echo -n "  Log A: "; curl -s "http://localhost:$port/select/logsql/query?query=ha_test_log_A" | grep -c "ha_test_log_A" || echo "0"
  echo -n "  Log B: "; curl -s "http://localhost:$port/select/logsql/query?query=ha_test_log_B" | grep -c "ha_test_log_B" || echo "0"
done

echo ""
echo "=== vlselect deduped final count ==="
curl -s "http://localhost:8005/select/logsql/query?query=ha_test_log_A%20OR%20ha_test_log_B%20%7C%20uniq%20by%20(_time%2C_msg)"