package cn.bitoffer.xtimer.service.trigger;

import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;

class TriggerTimerTaskTest {

    @Test
    void collectsDueScanStartsByWallClock() {
        assertEquals(
                Arrays.asList(0L, 1000L, 2000L, 3000L),
                TriggerTimerTask.collectDueScanStarts(0L, 3200L, 60000L, 1000L));
        assertEquals(
                Arrays.asList(59000L),
                TriggerTimerTask.collectDueScanStarts(59000L, 62000L, 60000L, 1000L));
    }
}
