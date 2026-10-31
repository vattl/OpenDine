package com.lanf.util;

import org.springframework.util.StringUtils;

import java.text.ParsePosition;
import java.text.SimpleDateFormat;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Date;

/**
 * 公告接口日期字符串解析（宽松，避免前端格式差异导致 400）。
 */
public final class AnnouncementDateParser {

    private AnnouncementDateParser() {}

    public static Date parse(String raw) {
        if (!StringUtils.hasText(raw)) {
            return null;
        }
        String s = raw.trim();
        try {
            return Date.from(Instant.parse(s));
        } catch (Exception ignored) {
            // fall through
        }
        // 前端常见：2026-04-15T08:58:20、带毫秒（无 Z，非 Instant）
        try {
            LocalDateTime ldt = LocalDateTime.parse(s, DateTimeFormatter.ISO_LOCAL_DATE_TIME);
            return Date.from(ldt.atZone(ZoneId.of("Asia/Shanghai")).toInstant());
        } catch (DateTimeParseException ignored) {
            // fall through
        }
        String[] patterns = {
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd",
                "yyyy/MM/dd HH:mm:ss",
                "yyyy/MM/dd"
        };
        for (String p : patterns) {
            SimpleDateFormat sdf = new SimpleDateFormat(p);
            sdf.setLenient(false);
            ParsePosition pos = new ParsePosition(0);
            Date d = sdf.parse(s, pos);
            if (d != null && pos.getIndex() == s.length()) {
                return d;
            }
        }
        throw new RuntimeException("无法解析日期时间：" + s);
    }
}
