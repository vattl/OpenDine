package com.lanf.schedule;

import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.FileTime;
import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ReportExportFileCleanupTaskTest {
    @Test
    void managesOnlyReportCsvArtifacts() {
        assertTrue(ReportExportFileCleanupTask.isManagedReportArtifact(Paths.get("report_daily_shop1.csv")));
        assertTrue(ReportExportFileCleanupTask.isManagedReportArtifact(Paths.get("report_daily_shop1.csv.part")));
        assertFalse(ReportExportFileCleanupTask.isManagedReportArtifact(Paths.get("log_export.csv")));
        assertFalse(ReportExportFileCleanupTask.isManagedReportArtifact(Paths.get("report_daily_shop1.xlsx")));
    }

    @Test
    void removesExpiredArtifactsWithoutTouchingOtherFiles() throws Exception {
        Path directory = Files.createTempDirectory("report-export-cleanup-");
        Path expired = Files.createFile(directory.resolve("report_daily_shop1.csv"));
        Path current = Files.createFile(directory.resolve("report_daily_shop2.csv"));
        Path unrelated = Files.createFile(directory.resolve("log_export.csv"));
        Files.setLastModifiedTime(expired, FileTime.from(Instant.now().minusSeconds(2 * 3600)));
        ReportExportFileCleanupTask task = new ReportExportFileCleanupTask();
        ReflectionTestUtils.setField(task, "exportDir", directory.toString());
        ReflectionTestUtils.setField(task, "retentionHours", 1L);

        task.cleanup();

        assertFalse(Files.exists(expired));
        assertTrue(Files.exists(current));
        assertTrue(Files.exists(unrelated));
        Files.delete(current);
        Files.delete(unrelated);
        Files.delete(directory);
    }
}
