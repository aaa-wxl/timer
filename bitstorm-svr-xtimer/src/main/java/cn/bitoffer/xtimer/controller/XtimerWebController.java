package cn.bitoffer.xtimer.controller;

import cn.bitoffer.api.dto.xtimer.NotifyHTTPParam;
import cn.bitoffer.api.dto.xtimer.TimerDTO;
import cn.bitoffer.common.model.ResponseEntity;
import cn.bitoffer.xtimer.mapper.TaskMapper;
import cn.bitoffer.xtimer.model.TaskModel;
import cn.bitoffer.xtimer.service.XTimerService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;


@RestController
@RequestMapping("/xtimer")
@Slf4j
public class XtimerWebController {

    @Resource
    private XTimerService xTimerService;

    @Resource
    private TaskMapper taskMapper;

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
                timerDTO.setStatus(2); // Enable immediately (status=2 is Enable)
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

    @GetMapping(value = "/bench/result")
    public ResponseEntity<Map<String, Object>> getBenchResult(
            @RequestParam(value = "app") String app,
            @RequestParam(value = "runTimer") Long runTimer) {

        List<TaskModel> tasks = taskMapper.getCompletedTasksByRunTimer(app, runTimer);

        if (tasks == null || tasks.isEmpty()) {
            Map<String, Object> empty = new HashMap<>();
            empty.put("count", 0);
            empty.put("message", "no completed tasks found for app=" + app + ", runTimer=" + runTimer);
            return ResponseEntity.ok(empty);
        }

        List<Integer> costTimes = tasks.stream()
                .map(TaskModel::getCostTime)
                .sorted()
                .collect(Collectors.toList());

        int count = costTimes.size();
        long sum = 0;
        for (int ct : costTimes) {
            sum += ct;
        }
        int avg = (int) (sum / count);
        int min = costTimes.get(0);
        int max = costTimes.get(count - 1);
        int p50 = costTimes.get((int) (count * 0.5));
        int p90 = costTimes.get((int) (count * 0.9));
        int p95 = costTimes.get((int) (count * 0.95));
        int p99 = costTimes.get(Math.min((int) (count * 0.99), count - 1));

        Map<String, Object> result = new HashMap<>();
        result.put("count", count);
        result.put("avg", avg);
        result.put("min", min);
        result.put("max", max);
        result.put("p50", p50);
        result.put("p90", p90);
        result.put("p95", p95);
        result.put("p99", p99);

        // 每个分片的 task 数量分布
        Map<Long, Long> bucketDist = tasks.stream()
                .collect(Collectors.groupingBy(TaskModel::getTimerId, Collectors.counting()));
        result.put("timerCount", bucketDist.size());

        return ResponseEntity.ok(result);
    }
}
