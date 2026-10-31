package com.lanf.schedule;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Duration;
import java.time.Instant;
import java.util.stream.Stream;

/** Deletes expired report artifacts; completed report downloads are valid for only 15 minutes. */
@Component
public class ReportExportFileCleanupTask {
    private static final Logger log = LoggerFactory.getLogger(ReportExportFileCleanupTask.class);

    @Value("${report.export.dir:./data/exports}") private String exportDir;
    @Value("${report.export-retention-hours:24}") private long retentionHours;

    @Scheduled(cron = "${report.export-cleanup-cron:0 45 3 * * ?}")
    public void cleanup() {
        Path directory = Paths.get(exportDir).toAbsolutePath().normalize();
        if (!Files.isDirectory(directory)) return;
        Instant cutoff = Instant.now().minus(Duration.ofHours(Math.max(1, retentionHours)));
        try (Stream<Path> files = Files.list(directory)) {
            files.filter(Files::isRegularFile).filter(ReportExportFileCleanupTask::isManagedReportArtifact)
                    .filter(path -> isOlderThan(path, cutoff)).forEach(this::deleteQuietly);
        } catch (IOException e) {
            log.warn("report export file cleanup could not list {}: {}", directory, e.getMessage());
        }
    }

    static boolean isManagedReportArtifact(Path path) {
        String name = path.getFileName().toString();
        return name.startsWith("report_") && (name.endsWith(".csv") || name.endsWith(".csv.part"));
    }

    private static boolean isOlderThan(Path path, Instant cutoff) {
        try { return Files.getLastModifiedTime(path).toInstant().isBefore(cutoff); }
        catch (IOException e) { return false; }
    }

    private void deleteQuietly(Path path) {
        try { Files.deleteIfExists(path); }
        catch (IOException e) { log.warn("report export file cleanup could not delete {}: {}", path, e.getMessage()); }
    }
}
