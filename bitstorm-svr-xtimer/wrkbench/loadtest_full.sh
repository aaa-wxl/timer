#!/bin/bash
# Full Load Test Script for XTimer
# Tests timing accuracy with hundreds of timers firing simultaneously
#
# Usage: ./loadtest_full.sh [options]
# Options:
#   -n, --num-timers     Number of timers to create (default: 200)
#   -c, --cron           Cron expression (default: "0 * * * * ?" = every minute)
#   -u, --url            Base URL (default: http://127.0.0.1:8082)
#   -d, --duration       Test duration in seconds (default: 180)
#   -h, --help           Show this help

set -e

# Default values
NUM_TIMERS=200
CRON="0 * * * * ?"
BASE_URL="http://127.0.0.1:8082"
CALLBACK_URL="http://127.0.0.1:8082/xtimer/callback"
DURATION=180
LOG_DIR="loadtest_results"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--num-timers)
            NUM_TIMERS="$2"
            shift 2
            ;;
        -c|--cron)
            CRON="$2"
            shift 2
            ;;
        -u|--url)
            BASE_URL="$2"
            CALLBACK_URL="$2/xtimer/callback"
            shift 2
            ;;
        -d|--duration)
            DURATION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -n, --num-timers     Number of timers to create (default: 200)"
            echo "  -c, --cron           Cron expression (default: '0 * * * * ?')"
            echo "  -u, --url            Base URL (default: http://127.0.0.1:8082)"
            echo "  -d, --duration       Test duration in seconds (default: 180)"
            echo "  -h, --help           Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create log directory
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEST_LOG="$LOG_DIR/loadtest_$TIMESTAMP.log"

echo "==========================================" | tee "$TEST_LOG"
echo "XTimer Load Test - Timing Accuracy" | tee -a "$TEST_LOG"
echo "==========================================" | tee -a "$TEST_LOG"
echo "Date: $(date)" | tee -a "$TEST_LOG"
echo "Timers: $NUM_TIMERS" | tee -a "$TEST_LOG"
echo "Cron: $CRON" | tee -a "$TEST_LOG"
echo "Base URL: $BASE_URL" | tee -a "$TEST_LOG"
echo "Duration: ${DURATION}s" | tee -a "$TEST_LOG"
echo "==========================================" | tee -a "$TEST_LOG"

# Step 1: Health check
echo "" | tee -a "$TEST_LOG"
echo "[1/6] Health check..." | tee -a "$TEST_LOG"
if ! curl -s "$BASE_URL/xtimer/callback/stats" > /dev/null 2>&1; then
    echo "ERROR: Application is not running at $BASE_URL" | tee -a "$TEST_LOG"
    exit 1
fi
echo "✓ Application is running" | tee -a "$TEST_LOG"

# Step 2: Reset stats
echo "" | tee -a "$TEST_LOG"
echo "[2/6] Resetting callback stats..." | tee -a "$TEST_LOG"
curl -s -X POST "$BASE_URL/xtimer/callback/reset" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Step 3: Clean up old timestamp log
TIMESTAMP_LOG="callback_timestamps.log"
if [ -f "$TIMESTAMP_LOG" ]; then
    mv "$TIMESTAMP_LOG" "$LOG_DIR/timestamps_$TIMESTAMP.log.bak"
fi

# Step 4: Batch create timers
echo "" | tee -a "$TEST_LOG"
echo "[3/6] Creating $NUM_TIMERS timers..." | tee -a "$TEST_LOG"
CREATE_START=$(date +%s%N)
RESPONSE=$(curl -s -X POST "$BASE_URL/xtimer/batchCreateTimers?count=$NUM_TIMERS&cron=$CRON&callbackUrl=$CALLBACK_URL")
CREATE_END=$(date +%s%N)
CREATE_DURATION=$(( (CREATE_END - CREATE_START) / 1000000 ))

echo "Response: $RESPONSE" | tee -a "$TEST_LOG"
echo "Creation time: ${CREATE_DURATION}ms" | tee -a "$TEST_LOG"

# Extract success count
SUCCESS_COUNT=$(echo "$RESPONSE" | grep -o '"success":[0-9]*' | grep -o '[0-9]*')
echo "Successfully created: $SUCCESS_COUNT timers" | tee -a "$TEST_LOG"

if [ "$SUCCESS_COUNT" -eq 0 ]; then
    echo "ERROR: No timers were created!" | tee -a "$TEST_LOG"
    exit 1
fi

# Step 5: Wait for next minute boundary
echo "" | tee -a "$TEST_LOG"
echo "[4/6] Waiting for next minute boundary..." | tee -a "$TEST_LOG"
CURRENT_SECOND=$(date +%S)
WAIT_SECONDS=$((60 - CURRENT_SECOND))
echo "Current second: $CURRENT_SECOND" | tee -a "$TEST_LOG"
echo "Waiting $WAIT_SECONDS seconds..." | tee -a "$TEST_LOG"
sleep "$WAIT_SECONDS"
echo "✓ Reached minute boundary" | tee -a "$TEST_LOG"

# Step 6: Monitor callbacks
echo "" | tee -a "$TEST_LOG"
echo "[5/6] Monitoring callbacks for $DURATION seconds..." | tee -a "$TEST_LOG"
echo "Expected callbacks per minute: $SUCCESS_COUNT" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

MONITOR_START=$(date +%s)
CALLBACK_COUNT=0

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - MONITOR_START))

    if [ $ELAPSED -ge $DURATION ]; then
        break
    fi

    STATS=$(curl -s "$BASE_URL/xtimer/callback/stats" 2>/dev/null || echo "error")
    CURRENT_COUNT=$(echo "$STATS" | grep -o '[0-9]*' | head -1)

    if [ -n "$CURRENT_COUNT" ] && [ "$CURRENT_COUNT" -gt "$CALLBACK_COUNT" ]; then
        NEW_CALLBACKS=$((CURRENT_COUNT - CALLBACK_COUNT))
        echo "[$(date '+%H:%M:%S')] +$NEW_CALLBACKS callbacks (total: $CURRENT_COUNT, elapsed: ${ELAPSED}s)" | tee -a "$TEST_LOG"
        CALLBACK_COUNT=$CURRENT_COUNT
    fi

    sleep 1
done

# Step 7: Analyze results
echo "" | tee -a "$TEST_LOG"
echo "[6/6] Analyzing timing accuracy..." | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

if [ -f "$TIMESTAMP_LOG" ]; then
    python3 analyze_timing.py "$TIMESTAMP_LOG" 2>&1 | tee -a "$TEST_LOG"
else
    echo "WARNING: No timestamp log found. Analysis skipped." | tee -a "$TEST_LOG"
fi

echo "" | tee -a "$TEST_LOG"
echo "==========================================" | tee -a "$TEST_LOG"
echo "Load test completed!" | tee -a "$TEST_LOG"
echo "Results saved to: $TEST_LOG" | tee -a "$TEST_LOG"
echo "==========================================" | tee -a "$TEST_LOG"
