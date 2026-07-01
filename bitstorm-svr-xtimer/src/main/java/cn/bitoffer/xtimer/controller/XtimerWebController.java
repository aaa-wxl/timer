package cn.bitoffer.xtimer.controller;

import cn.bitoffer.api.dto.xtimer.NotifyHTTPParam;
import cn.bitoffer.api.dto.xtimer.TimerDTO;
import cn.bitoffer.common.model.ResponseEntity;
import cn.bitoffer.xtimer.service.XTimerService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;


@RestController
@RequestMapping("/xtimer")
@Slf4j
public class XtimerWebController {

    @Resource
    private XTimerService xTimerService;

    @PostMapping(value = "/createTimer")
    public ResponseEntity<Long> createTimer(@RequestBody TimerDTO timerDTO){
        Long timerId = xTimerService.CreateTimer(timerDTO);
        return ResponseEntity.ok(timerId);
    }

    @GetMapping(value = "/enableTimer")
    public ResponseEntity<String> enableTimer(@RequestParam(value = "app") String app,
                            @RequestParam(value = "timerId") Long timerId,
                            @RequestHeader MultiValueMap<String, String> headers){
        xTimerService.EnableTimer(app,timerId);
        return ResponseEntity.ok("ok");
    }

    @PostMapping(value = "/batchCreateTimers")
    public ResponseEntity<Map<String, Object>> batchCreateTimers(@RequestParam(value = "count") int count,
                                                                  @RequestParam(value = "cron") String cron,
                                                                  @RequestParam(value = "callbackUrl") String callbackUrl) {
        List<Long> timerIds = new ArrayList<>();
        int successCount = 0;
        int failCount = 0;

        for (int i = 0; i < count; i++) {
            try {
                TimerDTO timerDTO = new TimerDTO();
                timerDTO.setApp("loadtest");
                timerDTO.setName("batch_timer_" + System.currentTimeMillis() + "_" + i);
                timerDTO.setStatus(1); // Enable immediately
                timerDTO.setCron(cron);

                NotifyHTTPParam notifyParam = new NotifyHTTPParam();
                notifyParam.setMethod("POST");
                notifyParam.setUrl(callbackUrl);
                notifyParam.setHeader(Map.of("Content-Type", "application/json"));
                notifyParam.setBody("{\"timerName\":\"" + timerDTO.getName() + "\"}");
                timerDTO.setNotifyHTTPParam(notifyParam);

                Long timerId = xTimerService.CreateTimer(timerDTO);
                timerIds.add(timerId);
                successCount++;
            } catch (Exception e) {
                failCount++;
                log.error("Failed to create timer {}: {}", i, e.getMessage());
            }
        }

        Map<String, Object> result = new HashMap<>();
        result.put("total", count);
        result.put("success", successCount);
        result.put("failed", failCount);
        result.put("timerIds", timerIds);

        return ResponseEntity.ok(result);
    }
}
