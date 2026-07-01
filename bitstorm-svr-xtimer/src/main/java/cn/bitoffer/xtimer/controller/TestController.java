package cn.bitoffer.xtimer.controller;

import cn.bitoffer.common.model.ResponseEntity;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;

import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.atomic.AtomicLong;

@RestController
@RequestMapping("/xtimer")
@Slf4j
public class TestController {

    private static final AtomicLong callbackCount = new AtomicLong(0);
    private static final String TIMESTAMP_LOG_FILE = "callback_timestamps.log";
    private static final DateTimeFormatter FORMATTER = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS");

    @PostMapping("/callback")
    public ResponseEntity<String> callback(@RequestBody String callbackInfo) {
        long count = callbackCount.incrementAndGet();
        long receivedTimeMs = System.currentTimeMillis();
        long receivedTimeNs = System.nanoTime();

        LocalDateTime dateTime = LocalDateTime.ofInstant(
                Instant.ofEpochMilli(receivedTimeMs), ZoneId.systemDefault());

        String logEntry = String.format("count=%d, time_ms=%d, time_ns=%d, datetime=%s, body=%s",
                count, receivedTimeMs, receivedTimeNs, dateTime.format(FORMATTER), callbackInfo);

        log.info("CALLBACK_TIMESTAMP: {}", logEntry);

        // 异步写入文件，避免影响性能
        writeTimestampToFile(logEntry);

        return ResponseEntity.ok("ok");
    }

    @GetMapping("/callback/stats")
    public ResponseEntity<String> getStats() {
        return ResponseEntity.ok("Total callbacks: " + callbackCount.get());
    }

    @PostMapping("/callback/reset")
    public ResponseEntity<String> resetStats() {
        callbackCount.set(0);
        return ResponseEntity.ok("Stats reset");
    }

    private void writeTimestampToFile(String logEntry) {
        try (PrintWriter writer = new PrintWriter(new FileWriter(TIMESTAMP_LOG_FILE, true))) {
            writer.println(logEntry);
        } catch (IOException e) {
            log.error("Failed to write timestamp log", e);
        }
    }
}

