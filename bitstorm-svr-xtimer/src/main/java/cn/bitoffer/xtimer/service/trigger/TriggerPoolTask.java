package cn.bitoffer.xtimer.service.trigger;

import cn.bitoffer.xtimer.model.TaskModel;
import cn.bitoffer.common.redis.ReentrantDistributeLock;
import cn.bitoffer.xtimer.service.executor.ExecutorWorker;
import cn.bitoffer.xtimer.utils.TimerUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class TriggerPoolTask {

    @Autowired
    ReentrantDistributeLock reentrantDistributeLock;

    @Autowired
    ExecutorWorker executorWorker;

    @Async("triggerPool")
    public void runExecutor(TaskModel task) {
        if(task == null){
            return;
        }
        long submitTime = System.currentTimeMillis();
        long runTimer = task.getRunTimer();
        long queueDelay = submitTime - runTimer;

        executorWorker.work(TimerUtils.UnionTimerIDUnix(task.getTimerId(),task.getRunTimer()));

        log.info("BENCH_QUEUE timerId={} runTimer={} submitAt={} queueDelay={}ms",
                task.getTimerId(), runTimer, submitTime, queueDelay);
    }
}
