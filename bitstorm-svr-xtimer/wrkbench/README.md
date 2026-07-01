# XTimer Load Testing Suite

## Overview

This suite tests the timing accuracy of the XTimer system under load. It verifies that timers fire at the expected times with sub-second precision, even when hundreds of timers are scheduled simultaneously.

## Test Scenario

The test validates the claim: **"单秒几百任务，单分片上千任务能保证秒级误差"**

Translation: "Hundreds of tasks per second, thousands of tasks per minute slice can guarantee second-level accuracy"

### How It Works

1. **Create N timers** with cron expression `0 * * * * ?` (fires every minute at second 0)
2. **Each timer** calls back to a logging endpoint that records the exact timestamp (millisecond precision)
3. **Analyze** the callback timestamps to measure timing accuracy

## Prerequisites

- XTimer application running on `http://127.0.0.1:8082`
- MySQL, Redis, and Nacos services available
- Python 3.x (for analysis)
- curl (for API calls)

## Quick Start

### Option 1: Full Automated Test

```bash
# Run with default settings (200 timers, 3 minutes)
./loadtest_full.sh

# Run with custom settings
./loadtest_full.sh -n 500 -d 300  # 500 timers, 5 minutes
```

### Option 2: Manual Steps

```bash
# Step 1: Create timers
curl -X POST "http://127.0.0.1:8082/xtimer/batchCreateTimers?count=200&cron=0+*+*+*+*+?&callbackUrl=http://127.0.0.1:8082/xtimer/callback"

# Step 2: Wait for next minute boundary
sleep 60

# Step 3: Monitor callbacks
watch -n 1 'curl -s http://127.0.0.1:8082/xtimer/callback/stats'

# Step 4: Analyze results
python3 analyze_timing.py callback_timestamps.log
```

## Files

| File | Description |
|------|-------------|
| `loadtest_full.sh` | Complete automated test script |
| `loadtest_batch_create.sh` | Batch creation with monitoring |
| `analyze_timing.py` | Timing accuracy analysis |
| `create_timer.lua` | wrk script for single timer creation |
| `wrk_batch_create.lua` | wrk script for batch creation |

## API Endpoints

### Batch Create Timers
```
POST /xtimer/batchCreateTimers?count={count}&cron={cron}&callbackUrl={url}
```

### Callback Stats
```
GET /xtimer/callback/stats
```

### Reset Stats
```
POST /xtimer/callback/reset
```

## Expected Results

The analysis script will output:

- **Per-minute statistics**: Average, min, max, and standard deviation of delays
- **Percentiles**: P50, P90, P95, P99
- **Accuracy assessment**: Percentage of callbacks within ±100ms, ±500ms, ±1000ms

### Example Output

```
Total callbacks analyzed: 1200
Average delay: 45.23 ms
Median delay: 42.00 ms
Min delay: 12 ms
Max delay: 189 ms
Std deviation: 28.45 ms

Percentiles:
  P50: 42 ms
  P90: 78 ms
  P95: 95 ms
  P99: 156 ms

Within ±100ms:  1156/1200 (96.3%)
Within ±500ms:  1200/1200 (100.0%)
Within ±1000ms: 1200/1200 (100.0%)

✅ EXCELLENT: Average delay < 100ms - meets sub-second accuracy requirement
```

## Interpreting Results

- **< 100ms average**: Excellent - sub-second accuracy achieved
- **100-500ms average**: Good - acceptable for most use cases
- **> 500ms average**: Poor - may need optimization

## Advanced Testing

### Test with Different Cron Expressions

```bash
# Every 30 seconds
./loadtest_full.sh -c "*/30 * * * * ?"

# Every 10 seconds
./loadtest_full.sh -c "*/10 * * * * ?"

# Specific second (e.g., at second 15)
./loadtest_full.sh -c "15 * * * * ?"
```

### Stress Testing

```bash
# High load test
./loadtest_full.sh -n 1000 -d 600  # 1000 timers, 10 minutes
```

## Troubleshooting

### No callbacks received

1. Check if the application is running: `curl http://127.0.0.1:8082/xtimer/callback/stats`
2. Verify timers were created: Check MySQL `xtimer` table
3. Check application logs for errors

### High latency

1. Check Redis connection latency
2. Monitor MySQL query performance
3. Check system resources (CPU, memory, network)

## Notes

- The callback endpoint writes to `callback_timestamps.log` for analysis
- Each callback records: count, timestamp_ms, timestamp_ns, datetime, and body
- The analysis script groups callbacks by minute and calculates per-minute statistics
