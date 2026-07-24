package cn.bitoffer.xtimer.service.trigger;

import cn.bitoffer.xtimer.common.conf.TriggerAppConf;
import cn.bitoffer.xtimer.enums.TaskStatus;
import cn.bitoffer.xtimer.mapper.TaskMapper;
import cn.bitoffer.xtimer.model.TaskModel;
import cn.bitoffer.xtimer.redis.TaskCache;
import lombok.extern.slf4j.Slf4j;
import org.springframework.util.CollectionUtils;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.TimerTask;
import java.util.concurrent.CountDownLatch;

@Slf4j
public class TriggerTimerTask extends TimerTask {

    TriggerAppConf triggerAppConf;

    TriggerPoolTask triggerPoolTask;

    TaskCache taskCache;

    TaskMapper taskMapper;

    private CountDownLatch latch;
    private long nextScanMs;

    private Date startTime;

    private Date endTime;

    private String minuteBucketKey;

    public TriggerTimerTask(TriggerAppConf triggerAppConf, TriggerPoolTask triggerPoolTask,
                            TaskCache taskCache, TaskMapper taskMapper, CountDownLatch latch,
                            Date startTime, Date endTime, String minuteBucketKey) {
        this.triggerAppConf = triggerAppConf;
        this.triggerPoolTask = triggerPoolTask;
        this.taskCache = taskCache;
        this.taskMapper = taskMapper;
        this.latch = latch;
        this.startTime = startTime;
        this.endTime = endTime;
        this.minuteBucketKey = minuteBucketKey;
        this.nextScanMs = startTime.getTime();
    }

    @Override
    public void run() {
        long gapMs = triggerAppConf.getZrangeGapSeconds() * 1000L;
        List<long[]> scanRanges = collectDueScanRanges(nextScanMs, System.currentTimeMillis(), endTime.getTime(), gapMs);
        if (CollectionUtils.isEmpty(scanRanges)) {
            if (nextScanMs >= endTime.getTime()) {
                latch.countDown();
            }
            return;
        }

        // Catch up due scores by wall clock; never scan beyond now.
        for (long[] scanRange : scanRanges) {
            try {
                handleBatch(new Date(scanRange[0]), new Date(scanRange[1]));
            } catch (Exception e) {
                log.error("handleBatch Error. minuteBucketKey" + minuteBucketKey + ",tStartTime:" + startTime + ",e:", e);
            }
            nextScanMs = scanRange[1];
        }

        if (nextScanMs >= endTime.getTime()) {
            latch.countDown();
        }
    }

    static List<long[]> collectDueScanRanges(long nextScanMs, long nowMs, long endMs, long gapMs) {
        if (gapMs <= 0) {
            throw new IllegalArgumentException("gapMs must be positive");
        }

        List<long[]> scanRanges = new ArrayList<>();
        if (nextScanMs >= endMs || nowMs < nextScanMs) {
            return scanRanges;
        }

        long dueEndMs = Math.min(nowMs + 1, endMs);
        for (long scanStart = nextScanMs; scanStart < dueEndMs; scanStart += gapMs) {
            long scanEnd = Math.min(scanStart + gapMs, dueEndMs);
            scanRanges.add(new long[]{scanStart, scanEnd});
        }
        return scanRanges;
    }

    private void handleBatch(Date start, Date end) {
        long t1 = System.currentTimeMillis();
        List<TaskModel> tasks = getTasksByTime(start, end);
        long t2 = System.currentTimeMillis();
        if (CollectionUtils.isEmpty(tasks)) {
            return;
        }
        log.info("BENCH_ZRANGE key={} count={} zrangeMs={}", minuteBucketKey, tasks.size(), t2 - t1);
        for (TaskModel task : tasks) {
            try {
                if (task == null) {
                    continue;
                }
                triggerPoolTask.runExecutor(task);
            } catch (Exception e) {
                log.error("executor run task error,task" + task.toString());
            }
        }
        long t3 = System.currentTimeMillis();
        log.info("BENCH_SUBMIT key={} count={} submitMs={}", minuteBucketKey, tasks.size(), t3 - t2);
    }

    private List<TaskModel> getTasksByTime(Date start, Date end) {
        List<TaskModel> tasks = new ArrayList<>();

        try {
            tasks = taskCache.getTasksFromCache(minuteBucketKey, start.getTime(), end.getTime());
        } catch (Exception e) {
            log.error("getTasksFromCache error: ", e);
            try {
                tasks = taskMapper.getTasksByTimeRange(start.getTime(), end.getTime() - 1, TaskStatus.NotRun.getStatus());
            } catch (Exception e1) {
                log.error("getTasksByConditions error: ", e1);
            }
        }
        return tasks;
    }
}
