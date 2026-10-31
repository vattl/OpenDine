package com.lanf.util;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Generates dining order numbers in the canonical ORD + timestamp + sequence format.
 *
 * <p>The JVM-local sequence prevents duplicate values within one process. The database
 * unique index remains the final cross-process guard.</p>
 */
public final class OrderNumberGenerator {

    private static final DateTimeFormatter TIME_FORMAT =
            DateTimeFormatter.ofPattern("yyyyMMddHHmmss");
    private static long sequenceSecond = -1L;
    private static int sequenceOffset;
    private static int sequenceCount;

    private OrderNumberGenerator() {
    }

    public static synchronized String next() {
        while (true) {
            long currentSecond = System.currentTimeMillis() / 1000L;
            if (currentSecond != sequenceSecond) {
                sequenceSecond = currentSecond;
                sequenceOffset = ThreadLocalRandom.current().nextInt(1000);
                sequenceCount = 0;
            }
            if (sequenceCount < 1000) {
                int suffix = (sequenceOffset + sequenceCount++) % 1000;
                LocalDateTime orderTime = LocalDateTime.ofInstant(
                        Instant.ofEpochSecond(sequenceSecond),
                        ZoneId.systemDefault());
                return "ORD" + orderTime.format(TIME_FORMAT)
                        + String.format(Locale.ROOT, "%03d", suffix);
            }
            try {
                Thread.sleep(2L);
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("订单号生成被中断", interrupted);
            }
        }
    }
}
