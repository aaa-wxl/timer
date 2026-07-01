-- wrk script to batch create timers
-- Usage: wrk -t4 -c100 -d60s --script=create_timer.lua --latency "http://127.0.0.1:8082/xtimer/createTimer"

wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"

-- Counter for unique timer names
local counter = 0
local thread_id = 0

function setup(thread)
    thread_id = thread_id + 1
    thread:set("tid", thread_id)
end

function request()
    counter = counter + 1
    local timer_name = "load_test_timer_" .. thread_id .. "_" .. counter

    -- Create timer with cron that fires every minute at second 0
    -- Cron format: second minute hour day month weekday
    local body = string.format([[
    {
        "app": "loadtest",
        "name": "%s",
        "status": 1,
        "cron": "0 * * * * ?",
        "notifyHTTPParam": {
            "method": "POST",
            "url": "http://127.0.0.1:8082/xtimer/callback",
            "header": {"Content-Type": "application/json"},
            "body": "{\"timerName\":\"%s\",\"expectedMinute\":\"*\"}"
        }
    }
    ]], timer_name, timer_name)

    return wrk.format(nil, nil, nil, body)
end

function response(status, headers, body)
    if status ~= 200 then
        io.stderr:write(string.format("ERROR: status=%d, body=%s\n", status, body))
    end
end

done function(summary, latency, requests)
    io.write("------------------------------\n")
    io.write(string.format("Total requests: %d\n", summary.requests))
    io.write(string.format("Successful: %d\n", summary.requests - summary.errors.connect - summary.errors.read - summary.errors.write - summary.errors.timeout))
    io.write(string.format("Errors: %d\n", summary.errors.connect + summary.errors.read + summary.errors.write + summary.errors.timeout))
    io.write(string.format("Requests/sec: %.2f\n", summary.requests / (summary.duration / 1000000)))
    io.write("------------------------------\n")
end
