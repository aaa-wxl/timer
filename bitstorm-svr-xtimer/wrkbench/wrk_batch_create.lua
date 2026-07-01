-- wrk script for batch timer creation
-- Usage: wrk -t4 -c100 -d30s --script=wrk_batch_create.lua --latency "http://127.0.0.1:8082/xtimer/batchCreateTimers?count=10&cron=0+*+*+*+*+?&callbackUrl=http://127.0.0.1:8082/xtimer/callback"

wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"

function response(status, headers, body)
    if status ~= 200 then
        io.stderr:write(string.format("ERROR: status=%d, body=%s\n", status, body))
    else
        -- Parse response to check success count
        local success = body:match('"success":(%d+)')
        local failed = body:match('"failed":(%d+)')
        if success then
            io.write(string.format("Created: %s timers, Failed: %s\n", success, failed or "0"))
        end
    end
end

done function(summary, latency, requests)
    io.write("\n")
    io.write("==============================\n")
    io.write("Batch Create Load Test Results\n")
    io.write("==============================\n")
    io.write(string.format("Total requests: %d\n", summary.requests))
    io.write(string.format("Duration: %.2f sec\n", summary.duration / 1000000))
    io.write(string.format("Requests/sec: %.2f\n", summary.requests / (summary.duration / 1000000)))
    io.write(string.format("Transfer/sec: %.2f KB\n", (summary.bytes / (summary.duration / 1000000)) / 1024))
    io.write("\n")
    io.write("Latency Distribution:\n")
    io.write(string.format("  50%%: %.2f ms\n", latency:percentile(50) / 1000))
    io.write(string.format("  90%%: %.2f ms\n", latency:percentile(90) / 1000))
    io.write(string.format("  95%%: %.2f ms\n", latency:percentile(95) / 1000))
    io.write(string.format("  99%%: %.2f ms\n", latency:percentile(99) / 1000))
    io.write("\n")
    io.write("Errors:\n")
    io.write(string.format("  Connect: %d\n", summary.errors.connect))
    io.write(string.format("  Read: %d\n", summary.errors.read))
    io.write(string.format("  Write: %d\n", summary.errors.write))
    io.write(string.format("  Timeout: %d\n", summary.errors.timeout))
    io.write("==============================\n")
end
