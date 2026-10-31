package com.lanf.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * 备货预测（菜品份数）可调参数，对应 application.yml 前缀 {@code stock-prep-forecast}。
 */
@Data
@Component
@ConfigurationProperties(prefix = "stock-prep-forecast")
public class StockPrepForecastProperties {

    /** 回溯自然日数（含至昨天为止的完整历史区间边界由服务层计算） */
    private int historyDays = 56;
    /** 向前预测天数（从今天起算） */
    private int forecastDays = 7;
    /** 每日返回的菜品条数上限（按历史总销量排序截断） */
    private int maxDishesPerDay = 45;
    /** 命中公休/长假时的需求乘数 */
    private double holidayUplift = 1.16;
    /** 合成乘数上限，避免极端值 */
    private double maxCompositeFactor = 1.48;
    /** 是否请求 Open-Meteo（无门店经纬度时自动跳过） */
    private boolean weatherEnabled = true;
    /** 节假日 JSON 路径（支持 classpath: 或 file:）；休息日/补班以文件为准 */
    private String holidayCalendarPath = "classpath:holidays/cn-public-holidays.json";
    /** 额外视为节假日的日期（yyyy-MM-dd），与 JSON 休息日叠加 */
    private List<String> extraHolidayDates = new ArrayList<>();
    /** 备货计划 final_qty 相对 suggest_qty 允许偏离比例上限，如 0.30 即 ±30% */
    private double planMaxAdjustRatio = 0.30;
}

