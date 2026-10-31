package com.lanf.util;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.lanf.config.StockPrepForecastProperties;
import cn.hutool.core.io.IoUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import javax.annotation.PostConstruct;
import java.time.LocalDate;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * 中国法定节假日「休息日」与「调休补班」日历，数据来自 classpath JSON（国务院办公厅公布的年度安排）。
 */
@Slf4j
@Component
public class ChinaPublicHolidayRegistry {

    @Autowired
    private StockPrepForecastProperties properties;
    @Autowired
    private ResourceLoader resourceLoader;

    /** year -> (date -> 节假日名称) */
    private Map<Integer, Map<LocalDate, String>> restByYear = Collections.emptyMap();
    /** year -> (date -> 说明，如调休补班) */
    private Map<Integer, Map<LocalDate, String>> workByYear = Collections.emptyMap();
    private Set<Integer> yearsLoaded = Collections.emptySet();

    @PostConstruct
    public void reload() {
        String path = properties.getHolidayCalendarPath();
        if (!StringUtils.hasText(path)) {
            path = "classpath:holidays/cn-public-holidays.json";
        }
        Map<Integer, Map<LocalDate, String>> rest = new HashMap<>();
        Map<Integer, Map<LocalDate, String>> work = new HashMap<>();
        Set<Integer> years = new HashSet<>();
        try {
            Resource res = resourceLoader.getResource(path.trim());
            if (!res.exists()) {
                log.warn("节假日数据文件不存在: {}", path);
                restByYear = Collections.emptyMap();
                workByYear = Collections.emptyMap();
                yearsLoaded = Collections.emptySet();
                return;
            }
            String json = IoUtil.readUtf8(res.getInputStream());
            JsonObject root = new JsonParser().parse(json).getAsJsonObject();
            if (!root.has("years") || !root.get("years").isJsonObject()) {
                log.warn("节假日 JSON 缺少 years 节点: {}", path);
            } else {
                JsonObject yearsObj = root.getAsJsonObject("years");
                for (Map.Entry<String, JsonElement> ye : yearsObj.entrySet()) {
                    int year = Integer.parseInt(ye.getKey());
                    years.add(year);
                    JsonObject y = ye.getValue().getAsJsonObject();
                    Map<LocalDate, String> rmap = new HashMap<>();
                    Map<LocalDate, String> wmap = new HashMap<>();
                    readDayArray(y.get("rest"), rmap);
                    readDayArray(y.get("work"), wmap);
                    for (LocalDate d : wmap.keySet()) {
                        rmap.remove(d);
                    }
                    rest.put(year, rmap);
                    work.put(year, wmap);
                }
            }
        } catch (Exception e) {
            log.error("加载节假日数据失败: {}", path, e);
            rest = Collections.emptyMap();
            work = Collections.emptyMap();
            years = Collections.emptySet();
        }
        this.restByYear = rest;
        this.workByYear = work;
        this.yearsLoaded = years;
        log.info("节假日日历已加载: {} 个年份", yearsLoaded.size());
    }

    private static void readDayArray(JsonElement arrEl, Map<LocalDate, String> out) {
        if (arrEl == null || !arrEl.isJsonArray()) {
            return;
        }
        JsonArray arr = arrEl.getAsJsonArray();
        for (JsonElement el : arr) {
            if (el == null || !el.isJsonObject()) {
                continue;
            }
            JsonObject o = el.getAsJsonObject();
            if (!o.has("date")) {
                continue;
            }
            LocalDate d = LocalDate.parse(o.get("date").getAsString());
            String name = o.has("name") ? o.get("name").getAsString() : "";
            out.put(d, StringUtils.hasText(name) ? name : "节假日");
        }
    }

    public boolean hasYearData(int year) {
        return yearsLoaded.contains(year);
    }

    /** 国务院公布的调休补班日（当日按工作日上班，不施加节假日需求系数）。 */
    public Optional<String> makeupWorkName(LocalDate d) {
        Map<LocalDate, String> m = workByYear.get(d.getYear());
        if (m == null) {
            return Optional.empty();
        }
        String n = m.get(d);
        return StringUtils.hasText(n) ? Optional.of(n) : Optional.empty();
    }

    /** 休息日（法定节假日连休），不含补班日。 */
    public Optional<String> statutoryRestName(LocalDate d) {
        Map<LocalDate, String> m = restByYear.get(d.getYear());
        if (m == null) {
            return Optional.empty();
        }
        String n = m.get(d);
        return StringUtils.hasText(n) ? Optional.of(n) : Optional.empty();
    }
}
