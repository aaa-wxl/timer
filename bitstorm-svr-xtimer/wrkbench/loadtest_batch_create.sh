#!/bin/bash
# Load test script for xtimer batch creation
# Usage: ./loadtest_batch_create.sh [timer_count] [cron_expression]

TIMER_COUNT=${1:-100}
CRON=${2:-"0 * * * * ?"}
BASE_URL="http://127.0.0.1:8082"
CALLBACK_URL="http://127.0.0.1:8082/xtimer/callback"

echo "=========================================="
echo "XTimer Load Test - Batch Create"
echo "=========================================="
echo "Timer Count: $TIMER_COUNT"
echo "Cron Expression: $CRON"
echo "Callback URL: $CALLBACK_URL"
echo "=========================================="

# Step 1: Reset callback stats
echo "[1/4] Resetting callback stats..."
curl -s -X POST "$BASE_URL/xtimer/callback/reset"
echo ""

# Step 2: Batch create timers
echo "[2/4] Creating $TIMER_COUNT timers..."
START_TIME=$(date +%s)
RESPONSE=$(curl -s -X POST "$BASE_URL/xtimer/batchCreateTimers?count=$TIMER_COUNT&cron=$CRON&callbackUrl=$CALLBACK_URL")
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "Response: $RESPONSE"
echo "Creation took: ${DURATION}s"

# Extract timer IDs
TIMER_IDS=$(echo $RESPONSE | grep -o '"timerIds":\[[0-9,]*\]' | grep -o '[0-9]*' | head -20)
echo "First 20 timer IDs: $TIMER_IDS"

# Step 3: Wait for next minute boundary
echo "[3/4] Waiting for next minute boundary..."
CURRENT_SECOND=$(date +%S)
WAIT_SECONDS=$((60 - CURRENT_SECOND))
echo "Waiting $WAIT_SECONDS seconds until next minute..."
sleep $WAIT_SECONDS

# Step 4: Monitor callbacks
echo "[4/4] Monitoring callbacks for 2 minutes..."
echo "Press Ctrl+C to stop monitoring"

# Monitor for 2 minutes
for i in $(seq 1 120); do
    STATS=$(curl -s "$BASE_URL/xtimer/callback/stats")
    echo "[$(date '+%H:%M:%S')] $STATS"
    sleep 1
done

echo ""
echo "=========================================="
echo "Load test completed!"
echo "=========================================="
echo "Check callback_timestamps.log for detailed timing analysis"
