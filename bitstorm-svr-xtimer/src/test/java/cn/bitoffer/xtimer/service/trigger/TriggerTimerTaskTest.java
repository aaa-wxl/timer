package cn.bitoffer.xtimer.service.trigger;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;

class TriggerTimerTaskTest {

    @Test
    void collectsDueSecondScanRangesByWallClock() {
        List<long[]> ranges = TriggerTimerTask.collectDueScanRanges(0L, 3200L, 60000L, 1000L);

        assertEquals(4, ranges.size());
        assertArrayEquals(new long[]{0L, 1000L}, ranges.get(0));
        assertArrayEquals(new long[]{1000L, 2000L}, ranges.get(1));
        assertArrayEquals(new long[]{2000L, 3000L}, ranges.get(2));
        assertArrayEquals(new long[]{3000L, 4000L}, ranges.get(3));

        List<long[]> lastMinuteRanges = TriggerTimerTask.collectDueScanRanges(59000L, 62000L, 60000L, 1000L);
        assertEquals(1, lastMinuteRanges.size());
        assertArrayEquals(new long[]{59000L, 60000L}, lastMinuteRanges.get(0));

        List<long[]> wideGapRanges = TriggerTimerTask.collectDueScanRanges(0L, 0L, 60000L, 2000L);
        assertEquals(1, wideGapRanges.size());
        assertArrayEquals(new long[]{0L, 1000L}, wideGapRanges.get(0));
    }
}
