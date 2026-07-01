#!/usr/bin/env python3
"""
XTimer Timing Accuracy Analysis Script
Analyzes callback_timestamps.log to measure timing precision.

Usage: python analyze_timing.py [logfile]
"""

import sys
import re
from collections import defaultdict
from datetime import datetime, timedelta
import statistics

def parse_log_line(line):
    """Parse a log line and extract timing information."""
    # Format: count=X, time_ms=Y, time_ns=Z, datetime=YYYY-MM-DD HH:MM:SS.SSS, body=...
    pattern = r'count=(\d+), time_ms=(\d+), time_ns=(\d+), datetime=([\d\-\. :]+), body=(.+)'
    match = re.match(pattern, line.strip())
    if match:
        return {
            'count': int(match.group(1)),
            'time_ms': int(match.group(2)),
            'time_ns': int(match.group(3)),
            'datetime': match.group(4),
            'body': match.group(5)
        }
    return None

def analyze_timing_accuracy(logfile):
    """Analyze timing accuracy from callback logs."""
    print(f"Analyzing log file: {logfile}")
    print("=" * 60)

    # Parse all entries
    entries = []
    with open(logfile, 'r') as f:
        for line in f:
            entry = parse_log_line(line)
            if entry:
                entries.append(entry)

    if not entries:
        print("No valid entries found in log file!")
        return

    print(f"Total callbacks: {len(entries)}")
    print()

    # Group by minute (expected fire time)
    minute_groups = defaultdict(list)
    for entry in entries:
        dt = datetime.strptime(entry['datetime'], '%Y-%m-%H %M:%S.%f' if '.' in entry['datetime'] else '%Y-%m-%d %H:%M:%S')
        # Round down to minute
        minute_key = dt.replace(second=0, microsecond=0)
        minute_groups[minute_key].append(entry)

    print("Timing Analysis by Minute:")
    print("-" * 60)

    all_delays = []

    for minute, group in sorted(minute_groups.items()):
        expected_time = minute + timedelta(minutes=1)  # Expected to fire at next minute
        expected_ms = int(expected_time.timestamp() * 1000)

        delays = []
        for entry in group:
            delay_ms = entry['time_ms'] - expected_ms
            delays.append(delay_ms)
            all_delays.append(delay_ms)

        if delays:
            avg_delay = statistics.mean(delays)
            min_delay = min(delays)
            max_delay = max(delays)
            std_delay = statistics.stdev(delays) if len(delays) > 1 else 0

            print(f"Minute: {minute.strftime('%H:%M')}")
            print(f"  Callbacks: {len(delays)}")
            print(f"  Avg delay: {avg_delay:.2f} ms")
            print(f"  Min delay: {min_delay} ms")
            print(f"  Max delay: {max_delay} ms")
            print(f"  Std dev:   {std_delay:.2f} ms")
            print()

    # Overall statistics
    if all_delays:
        print("=" * 60)
        print("Overall Statistics:")
        print("-" * 60)
        print(f"Total callbacks analyzed: {len(all_delays)}")
        print(f"Average delay: {statistics.mean(all_delays):.2f} ms")
        print(f"Median delay: {statistics.median(all_delays):.2f} ms")
        print(f"Min delay: {min(all_delays)} ms")
        print(f"Max delay: {max(all_delays)} ms")
        print(f"Std deviation: {statistics.stdev(all_delays):.2f} ms")

        # Percentiles
        sorted_delays = sorted(all_delays)
        p50 = sorted_delays[int(len(sorted_delays) * 0.5)]
        p90 = sorted_delays[int(len(sorted_delays) * 0.9)]
        p95 = sorted_delays[int(len(sorted_delays) * 0.95)]
        p99 = sorted_delays[int(len(sorted_delays) * 0.99)]

        print()
        print("Percentiles:")
        print(f"  P50: {p50} ms")
        print(f"  P90: {p90} ms")
        print(f"  P95: {p95} ms")
        print(f"  P99: {p99} ms")

        # Timing accuracy assessment
        print()
        print("=" * 60)
        print("Timing Accuracy Assessment:")
        print("-" * 60)

        within_100ms = sum(1 for d in all_delays if abs(d) <= 100)
        within_500ms = sum(1 for d in all_delays if abs(d) <= 500)
        within_1000ms = sum(1 for d in all_delays if abs(d) <= 1000)

        print(f"Within ±100ms:  {within_100ms}/{len(all_delays)} ({within_100ms/len(all_delays)*100:.1f}%)")
        print(f"Within ±500ms:  {within_500ms}/{len(all_delays)} ({within_500ms/len(all_delays)*100:.1f}%)")
        print(f"Within ±1000ms: {within_1000ms}/{len(all_delays)} ({within_1000ms/len(all_delays)*100:.1f}%)")

        if statistics.mean(all_delays) < 100:
            print("\n✅ EXCELLENT: Average delay < 100ms - meets sub-second accuracy requirement")
        elif statistics.mean(all_delays) < 500:
            print("\n⚠️  GOOD: Average delay < 500ms - acceptable for most use cases")
        else:
            print("\n❌ POOR: Average delay >= 500ms - may need optimization")

def main():
    logfile = sys.argv[1] if len(sys.argv) > 1 else "callback_timestamps.log"
    try:
        analyze_timing_accuracy(logfile)
    except FileNotFoundError:
        print(f"Error: Log file '{logfile}' not found!")
        print("Please run the load test first to generate callback timestamps.")
        sys.exit(1)
    except Exception as e:
        print(f"Error analyzing log file: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
