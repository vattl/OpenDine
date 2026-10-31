package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.lanf.config.StockPrepForecastProperties;
import com.lanf.dto.DishDowDemandStatDTO;
import com.lanf.entity.Shop;
import com.lanf.entity.StockPrepForecastDay;
import com.lanf.entity.StockPrepForecastDish;
import com.lanf.entity.StockPrepForecastRun;
import com.lanf.entity.StockPrepConfig;
import com.lanf.mapper.StockPrepConfigMapper;
import com.lanf.mapper.OrderMapper;
import com.lanf.mapper.StockPrepForecastDayMapper;
import com.lanf.mapper.StockPrepForecastDishMapper;
import com.lanf.mapper.StockPrepForecastRunMapper;
import com.lanf.service.IDishService;
import com.lanf.service.IShopService;
import com.lanf.service.StockPrepForecastService;
import com.lanf.util.ChinaPublicHolidayRegistry;
import com.lanf.util.StockPrepOnsaleCatalog;
import cn.hutool.http.HttpRequest;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Date;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 备货预测：历史「星期几」销量 × 节假日（国务院日历 JSON）× Open-Meteo 天气；可落库。
 */
@Slf4j
@Service
public class StockPrepForecastServiceImpl implements StockPrepForecastService {

    private static final ZoneId ZONE_SH = ZoneId.of("Asia/Shanghai");
    private static final DateTimeFormatter DT_SQL = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final DateTimeFormatter D_ISO = DateTimeFormatter.ISO_LOCAL_DATE;

    @Autowired
    private OrderMapper orderMapper;
    @Autowired
    private StockPrepForecastProperties properties;
    @Autowired
    private IDishService dishService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private ChinaPublicHolidayRegistry holidayRegistry;
    @Autowired
    private StockPrepForecastPersistFacade persistFacade;
    @Autowired
    private StockPrepForecastRunMapper runMapper;
    @Autowired
    private StockPrepForecastDayMapper dayMapper;
    @Autowired
    private StockPrepForecastDishMapper dishMapper;
    @Autowired
    private StockPrepConfigMapper stockPrepConfigMapper;

    @Override
    public Map<String, Object> buildForecast(Integer shopId, Integer historyDaysParam, Integer forecastDaysParam, boolean persist) {
        int historyDays = historyDaysParam != null && historyDaysParam > 0 ? historyDaysParam : properties.getHistoryDays();
        int forecastDays = forecastDaysParam != null && forecastDaysParam > 0 ? forecastDaysParam : properties.getForecastDays();
        double memberBizFactor = 1.0;
        if (shopId != null) {
            StockPrepConfig cfg = stockPrepConfigMapper.selectOne(new QueryWrapper<StockPrepConfig>().eq("shop_id", shopId).last("LIMIT 1"));
            if (cfg != null && (cfg.getIs_enabled() == null || cfg.getIs_enabled() == 1)) {
                if (historyDaysParam == null || historyDaysParam <= 0) {
                    if (cfg.getHistory_days() != null && cfg.getHistory_days() > 0) {
                        historyDays = cfg.getHistory_days();
                    }
                }
                if (forecastDaysParam == null || forecastDaysParam <= 0) {
                    if (cfg.getForecast_days() != null && cfg.getForecast_days() > 0) {
                        forecastDays = cfg.getForecast_days();
                    }
                }
                if (cfg.getMember_factor() != null && cfg.getMember_factor().compareTo(BigDecimal.ZERO) > 0) {
                    memberBizFactor = cfg.getMember_factor().doubleValue();
                }
            }
        }
        int maxDishes = Math.max(5, properties.getMaxDishesPerDay());

        LocalDateTime now = LocalDateTime.now(ZONE_SH);
        LocalDate today = now.toLocalDate();
        LocalDate historyStartDate = today.minusDays(historyDays);
        String startTime = historyStartDate.atStartOfDay().format(DT_SQL);
        String endTime = now.format(DT_SQL);

        Map<String, Object> q = new HashMap<>();
        q.put("startTime", startTime);
        q.put("endTime", endTime);
        if (shopId != null) {
            q.put("shopId", shopId);
        }

        StockPrepOnsaleCatalog.Index onsaleCatalog = StockPrepOnsaleCatalog.load(dishService, shopId);

        List<DishDowDemandStatDTO> stats = orderMapper.listDishDowDemandStats(q);
        long calendarDaysInWindow = Math.max(1, ChronoUnit.DAYS.between(historyStartDate, today) + 1);

        Map<String, Long> totalQtyByDish = new HashMap<>();
        for (DishDowDemandStatDTO s : stats) {
            if (s == null || !StringUtils.hasText(s.getDishName())) {
                continue;
            }
            String dishName = s.getDishName().trim();
            if (!onsaleCatalog.containsName(dishName)) {
                continue;
            }
            long v = s.getTotalQty() == null ? 0L : s.getTotalQty();
            totalQtyByDish.merge(dishName, v, Long::sum);
        }

        List<String> topDishes = totalQtyByDish.entrySet().stream()
                .sorted((a, b) -> Long.compare(b.getValue(), a.getValue()))
                .limit(maxDishes)
                .map(Map.Entry::getKey)
                .collect(Collectors.toList());

        Set<LocalDate> extraHolidayDates = parseExtraHolidayDates(properties.getExtraHolidayDates());
        Map<String, Integer> dishNameToId = onsaleCatalog.getNameToId();

        Map<LocalDate, WeatherDay> weatherByDate = Collections.emptyMap();
        if (properties.isWeatherEnabled() && shopId != null) {
            Shop shop = shopService.getById(shopId);
            if (shop != null && shop.getLatitude() != null && shop.getLongitude() != null) {
                weatherByDate = fetchOpenMeteoDaily(shop.getLatitude().doubleValue(), shop.getLongitude().doubleValue(), forecastDays);
            }
        }

        String modelNotes = "按历史区间内各「星期几」的日均销量为基线；仅预测当前已上架菜品（onsale=true，连锁门店按 t_dish_shop 有效上架态）；"
                + "节假日依据 resources/holidays/cn-public-holidays.json（国务院办公厅公布的放假调休）；天气为 Open-Meteo 启发式乘数。"
                + " 会员充值不计入销量统计；若存在 t_stock_prep_config.member_factor 则在预测份数上施加客流热度系数。";

        Map<String, Object> root = new LinkedHashMap<>();
        root.put("timezone", "Asia/Shanghai");
        root.put("historyStartDate", historyStartDate.format(D_ISO));
        root.put("historyEndAt", endTime);
        root.put("historyDaysRequested", historyDays);
        root.put("forecastDays", forecastDays);
        root.put("shopId", shopId);
        if (shopId != null) {
            Shop shop = shopService.getById(shopId);
            if (shop != null) {
                root.put("shopName", shop.getName());
            }
        }
        root.put("modelNotes", modelNotes);
        root.put("topDishCount", topDishes.size());
        root.put("onsaleDishCount", onsaleCatalog.getNames().size());
        root.put("persisted", false);

        List<Map<String, Object>> dayList = new ArrayList<>();
        List<StockPrepForecastDay> dayEntities = new ArrayList<>();
        List<StockPrepForecastDish> dishEntities = new ArrayList<>();

        for (int i = 0; i < forecastDays; i++) {
            LocalDate d = today.plusDays(i);
            int isoDow = d.getDayOfWeek().getValue();
            int dowCount = countIsoDowOccurrences(historyStartDate, today, isoDow);

            DayResolution dr = resolveDay(d, extraHolidayDates);
            double holidayFactor = dr.holidayFactor;
            WeatherDay wd = weatherByDate.get(d);
            double weatherFactor = weatherDemandFactor(wd);
            double composite = Math.min(properties.getMaxCompositeFactor(), holidayFactor * weatherFactor);

            Map<String, Object> factors = new LinkedHashMap<>();
            factors.put("holiday", round4(holidayFactor));
            factors.put("weather", round4(weatherFactor));
            factors.put("composite", round4(composite));
            factors.put("memberBusiness", round4(memberBizFactor));

            List<Map<String, Object>> dishLines = new ArrayList<>();
            for (String dishName : topDishes) {
                double baseline = baselineAvgForDow(stats, dishName, isoDow, dowCount, totalQtyByDish.getOrDefault(dishName, 0L), calendarDaysInWindow);
                int predicted = (int) Math.round(Math.max(0, baseline * composite * memberBizFactor));
                Map<String, Object> line = new LinkedHashMap<>();
                line.put("dishId", dishNameToId.get(dishName));
                line.put("dishName", dishName);
                line.put("baselineAvgForDow", round2(baseline));
                line.put("predictedServings", predicted);
                dishLines.add(line);

                if (persist) {
                    StockPrepForecastDish de = new StockPrepForecastDish();
                    de.setStat_date(Date.valueOf(d));
                    de.setDish_id(dishNameToId.get(dishName));
                    de.setDish_name(dishName);
                    de.setBaseline_avg(BigDecimal.valueOf(baseline).setScale(4, RoundingMode.HALF_UP));
                    de.setPredicted_servings(predicted);
                    dishEntities.add(de);
                }
            }

            Map<String, Object> day = new LinkedHashMap<>();
            day.put("date", d.format(D_ISO));
            day.put("isoDayOfWeek", isoDow);
            day.put("dayKind", dr.dayKind);
            day.put("isHoliday", dr.holidayDemand);
            day.put("holidayName", dr.holidayName);
            day.put("weather", weatherToMap(wd));
            day.put("factors", factors);
            day.put("dishes", dishLines);
            dayList.add(day);

            if (persist) {
                StockPrepForecastDay dayRow = new StockPrepForecastDay();
                dayRow.setStat_date(Date.valueOf(d));
                dayRow.setIso_day_of_week(isoDow);
                dayRow.setDay_kind(dr.dayKind);
                dayRow.setIs_holiday(dr.holidayDemand ? 1 : 0);
                dayRow.setHoliday_name(dr.holidayName);
                dayRow.setFactor_holiday(BigDecimal.valueOf(holidayFactor).setScale(4, RoundingMode.HALF_UP));
                dayRow.setFactor_weather(BigDecimal.valueOf(weatherFactor).setScale(4, RoundingMode.HALF_UP));
                dayRow.setFactor_composite(BigDecimal.valueOf(composite).setScale(4, RoundingMode.HALF_UP));
                dayRow.setWeather_available(wd != null ? 1 : 0);
                if (wd != null) {
                    dayRow.setWeather_summary(wd.summary());
                    dayRow.setWeather_code(wd.weatherCode);
                    dayRow.setWeather_precip_prob(wd.precipProbMax);
                    if (wd.tempMaxC != null) {
                        dayRow.setWeather_temp_max(BigDecimal.valueOf(wd.tempMaxC).setScale(1, RoundingMode.HALF_UP));
                    }
                }
                dayEntities.add(dayRow);
            }
        }
        root.put("days", dayList);

        if (persist) {
            StockPrepForecastRun run = new StockPrepForecastRun();
            run.setShop_id(shopId);
            run.setHistory_days(historyDays);
            run.setForecast_days(forecastDays);
            run.setHistory_start_date(Date.valueOf(historyStartDate));
            run.setHistory_end_at(java.sql.Timestamp.valueOf(now));
            run.setModel_notes(modelNotes);
            Long runId = persistFacade.saveRunWithDetails(run, dayEntities, dishEntities);
            root.put("persisted", true);
            root.put("runId", runId);
        }

        return root;
    }

    @Override
    public Map<String, Object> getLatestSavedForecast(Integer shopId) {
        QueryWrapper<StockPrepForecastRun> qw = new QueryWrapper<>();
        if (shopId != null) {
            qw.eq("shop_id", shopId);
        } else {
            qw.isNull("shop_id");
        }
        qw.orderByDesc("id").last("LIMIT 1");
        StockPrepForecastRun run = runMapper.selectOne(qw);
        if (run == null) {
            return null;
        }
        return assembleForecastFromRun(run);
    }

    @Override
    public Map<String, Object> getSavedForecastByRunId(Long runId, Integer shopId) {
        if (runId == null) {
            return null;
        }
        StockPrepForecastRun run = runMapper.selectById(runId);
        if (run == null) {
            return null;
        }
        if (shopId != null && run.getShop_id() != null && !run.getShop_id().equals(shopId)) {
            throw new RuntimeException("无权查看该预测批次");
        }
        return assembleForecastFromRun(run);
    }

    private Map<String, Object> assembleForecastFromRun(StockPrepForecastRun run) {
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("runId", run.getId());
        root.put("persisted", true);
        root.put("createdAt", run.getCreated_at());
        root.put("lastValidatedAt", run.getLast_validated_at());
        root.put("shopId", run.getShop_id());
        if (run.getShop_id() != null) {
            Shop shop = shopService.getById(run.getShop_id());
            if (shop != null) {
                root.put("shopName", shop.getName());
            }
        }
        root.put("timezone", "Asia/Shanghai");
        root.put("historyDaysRequested", run.getHistory_days());
        root.put("forecastDays", run.getForecast_days());
        root.put("historyStartDate", toLocalDate(run.getHistory_start_date()).format(D_ISO));
        root.put("historyEndAt", run.getHistory_end_at().toInstant().atZone(ZONE_SH).toLocalDateTime().format(DT_SQL));
        root.put("modelNotes", run.getModel_notes());
        StockPrepOnsaleCatalog.Index onsaleCatalog = StockPrepOnsaleCatalog.load(dishService, run.getShop_id());

        List<StockPrepForecastDay> dayRows = dayMapper.selectList(new QueryWrapper<StockPrepForecastDay>()
                .eq("run_id", run.getId())
                .orderByAsc("stat_date"));
        List<StockPrepForecastDish> allDishes = dishMapper.selectList(new QueryWrapper<StockPrepForecastDish>()
                .eq("run_id", run.getId())
                .orderByAsc("stat_date", "dish_name"));

        Map<LocalDate, List<StockPrepForecastDish>> dishesByDate = new LinkedHashMap<>();
        for (StockPrepForecastDish di : allDishes) {
            LocalDate ld = toLocalDate(di.getStat_date());
            dishesByDate.computeIfAbsent(ld, k -> new ArrayList<>()).add(di);
        }

        List<Map<String, Object>> dayList = new ArrayList<>();
        for (StockPrepForecastDay dd : dayRows) {
            LocalDate ld = toLocalDate(dd.getStat_date());
            Map<String, Object> weather = new LinkedHashMap<>();
            boolean wOk = dd.getWeather_available() != null && dd.getWeather_available() == 1;
            weather.put("available", wOk);
            if (wOk) {
                weather.put("source", "open-meteo");
                weather.put("weatherCode", dd.getWeather_code());
                weather.put("precipitationProbabilityMax", dd.getWeather_precip_prob());
                weather.put("temperatureMaxC", dd.getWeather_temp_max() != null ? dd.getWeather_temp_max().doubleValue() : null);
                weather.put("summary", dd.getWeather_summary());
            }

            Map<String, Object> factors = new LinkedHashMap<>();
            factors.put("holiday", dd.getFactor_holiday() != null ? dd.getFactor_holiday().doubleValue() : 1.0);
            factors.put("weather", dd.getFactor_weather() != null ? dd.getFactor_weather().doubleValue() : 1.0);
            factors.put("composite", dd.getFactor_composite() != null ? dd.getFactor_composite().doubleValue() : 1.0);

            List<Map<String, Object>> dishLines = new ArrayList<>();
            List<StockPrepForecastDish> lines = dishesByDate.getOrDefault(ld, Collections.emptyList());
            for (StockPrepForecastDish di : lines) {
                if (di == null) {
                    continue;
                }
                if (StringUtils.hasText(di.getDish_name()) && !onsaleCatalog.containsName(di.getDish_name())) {
                    continue;
                }
                Map<String, Object> line = new LinkedHashMap<>();
                line.put("dishId", di.getDish_id());
                line.put("dishName", di.getDish_name());
                line.put("baselineAvgForDow", di.getBaseline_avg() != null ? di.getBaseline_avg().doubleValue() : 0);
                line.put("predictedServings", di.getPredicted_servings());
                line.put("actualQuantity", di.getActual_quantity());
                line.put("validatedAt", di.getValidated_at());
                dishLines.add(line);
            }

            Map<String, Object> day = new LinkedHashMap<>();
            day.put("date", ld.format(D_ISO));
            day.put("isoDayOfWeek", dd.getIso_day_of_week());
            day.put("dayKind", dd.getDay_kind());
            day.put("isHoliday", dd.getIs_holiday() != null && dd.getIs_holiday() == 1);
            day.put("holidayName", dd.getHoliday_name());
            day.put("weather", weather);
            day.put("factors", factors);
            day.put("validation", buildDayValidationSummary(dd));
            day.put("dishes", dishLines);
            dayList.add(day);
        }
        root.put("topDishCount", dayList.isEmpty() ? 0 : (dayList.get(0).get("dishes") instanceof List ? ((List<?>) dayList.get(0).get("dishes")).size() : 0));
        root.put("onsaleDishCount", onsaleCatalog.getNames().size());
        root.put("days", dayList);
        return root;
    }

    private static Map<String, Object> buildDayValidationSummary(StockPrepForecastDay dd) {
        Map<String, Object> v = new LinkedHashMap<>();
        if (dd == null) {
            v.put("validated", false);
            return v;
        }
        v.put("validated", dd.getDay_validated_at() != null);
        v.put("dayValidatedAt", dd.getDay_validated_at());
        v.put("predictedServingsSum", dd.getPredicted_servings_sum());
        v.put("actualServingsForecastDishes", dd.getActual_servings_forecast_dishes());
        v.put("actualServingsAllDishes", dd.getActual_servings_all_dishes());
        v.put("actualOrderCount", dd.getActual_order_count());
        v.put("dailyStatTotalAmount", dd.getDaily_stat_total_amount() != null ? dd.getDaily_stat_total_amount().doubleValue() : null);
        v.put("dailyStatDiscountAmount", dd.getDaily_stat_discount_amount() != null ? dd.getDaily_stat_discount_amount().doubleValue() : null);
        v.put("dailyStatRefundAmount", dd.getDaily_stat_refund_amount() != null ? dd.getDaily_stat_refund_amount().doubleValue() : null);
        v.put("dailyStatMaterialCost", dd.getDaily_stat_material_cost() != null ? dd.getDaily_stat_material_cost().doubleValue() : null);
        v.put("dailyStatSettled", dd.getDaily_stat_settled());
        return v;
    }

    private static LocalDate toLocalDate(java.util.Date d) {
        if (d == null) {
            return null;
        }
        return d.toInstant().atZone(ZONE_SH).toLocalDate();
    }

    private static final class DayResolution {
        final String dayKind;
        final boolean holidayDemand;
        final String holidayName;
        final double holidayFactor;

        DayResolution(String dayKind, boolean holidayDemand, String holidayName, double holidayFactor) {
            this.dayKind = dayKind;
            this.holidayDemand = holidayDemand;
            this.holidayName = holidayName;
            this.holidayFactor = holidayFactor;
        }
    }

    private DayResolution resolveDay(LocalDate d, Set<LocalDate> extras) {
        Optional<String> makeup = holidayRegistry.makeupWorkName(d);
        if (makeup.isPresent()) {
            return new DayResolution("调休工作日(" + makeup.get() + ")", false, null, 1.0);
        }
        if (extras.contains(d)) {
            return new DayResolution("法定节假日(自定义)", true, "自定义节假日", properties.getHolidayUplift());
        }
        if (holidayRegistry.statutoryRestName(d).isPresent()) {
            return new DayResolution("法定节假日", true, holidayRegistry.statutoryRestName(d).get(), properties.getHolidayUplift());
        }
        if (!holidayRegistry.hasYearData(d.getYear()) && d.getMonthValue() == 1 && d.getDayOfMonth() == 1) {
            return new DayResolution("法定节假日", true, "元旦", properties.getHolidayUplift());
        }
        int iso = d.getDayOfWeek().getValue();
        if (iso >= 6) {
            return new DayResolution("周末", false, null, 1.0);
        }
        return new DayResolution("工作日", false, null, 1.0);
    }

    private static Map<String, Object> weatherToMap(WeatherDay wd) {
        Map<String, Object> m = new LinkedHashMap<>();
        if (wd == null) {
            m.put("available", false);
            return m;
        }
        m.put("available", true);
        m.put("source", "open-meteo");
        m.put("weatherCode", wd.weatherCode);
        m.put("precipitationProbabilityMax", wd.precipProbMax);
        m.put("temperatureMaxC", wd.tempMaxC);
        m.put("summary", wd.summary());
        return m;
    }

    private static Set<LocalDate> parseExtraHolidayDates(List<String> raw) {
        if (raw == null || raw.isEmpty()) {
            return Collections.emptySet();
        }
        Set<LocalDate> set = new HashSet<>();
        for (String s : raw) {
            if (!StringUtils.hasText(s)) {
                continue;
            }
            try {
                set.add(LocalDate.parse(s.trim(), D_ISO));
            } catch (Exception ignored) {
                // skip
            }
        }
        return set;
    }

    private static int countIsoDowOccurrences(LocalDate fromInclusive, LocalDate toInclusive, int isoDow) {
        int c = 0;
        for (LocalDate x = fromInclusive; !x.isAfter(toInclusive); x = x.plusDays(1)) {
            if (x.getDayOfWeek().getValue() == isoDow) {
                c++;
            }
        }
        return Math.max(0, c);
    }

    private static double baselineAvgForDow(List<DishDowDemandStatDTO> stats, String dishName, int isoDow, int dowCountInWindow,
                                            long dishTotalQtyInWindow, long calendarDaysInWindow) {
        long sumForDow = 0;
        for (DishDowDemandStatDTO s : stats) {
            if (s == null || !dishName.equals(s.getDishName())) {
                continue;
            }
            if (s.getIsoDow() != null && s.getIsoDow() == isoDow) {
                sumForDow += s.getTotalQty() == null ? 0L : s.getTotalQty();
            }
        }
        if (dowCountInWindow > 0 && sumForDow > 0) {
            return (double) sumForDow / dowCountInWindow;
        }
        if (calendarDaysInWindow > 0 && dishTotalQtyInWindow > 0) {
            return (double) dishTotalQtyInWindow / calendarDaysInWindow;
        }
        return 0;
    }

    private double weatherDemandFactor(WeatherDay wd) {
        if (wd == null) {
            return 1.0;
        }
        double f = 1.0;
        Integer p = wd.precipProbMax;
        if (p != null) {
            if (p >= 75) {
                f += 0.09;
            } else if (p >= 50) {
                f += 0.06;
            } else if (p >= 30) {
                f += 0.03;
            }
        }
        Integer code = wd.weatherCode;
        if (code != null && code >= 51 && code <= 67) {
            f += 0.03;
        }
        if (code != null && (code == 95 || code == 96 || code == 99)) {
            f += 0.04;
        }
        if (wd.tempMaxC != null) {
            if (wd.tempMaxC >= 35) {
                f += 0.04;
            } else if (wd.tempMaxC <= 3) {
                f += 0.03;
            }
        }
        return Math.min(f, 1.18);
    }

    private Map<LocalDate, WeatherDay> fetchOpenMeteoDaily(double lat, double lon, int forecastDays) {
        int days = Math.min(16, Math.max(1, forecastDays));
        String url = "https://api.open-meteo.com/v1/forecast"
                + "?latitude=" + lat
                + "&longitude=" + lon
                + "&daily=weathercode,precipitation_probability_max,temperature_2m_max"
                + "&timezone=Asia%2FShanghai"
                + "&forecast_days=" + days;
        try {
            String body = HttpRequest.get(url).timeout(10_000).execute().body();
            JsonObject root = new JsonParser().parse(body).getAsJsonObject();
            if (!root.has("daily")) {
                return Collections.emptyMap();
            }
            JsonObject daily = root.getAsJsonObject("daily");
            JsonArray times = daily.getAsJsonArray("time");
            JsonArray codes = daily.has("weathercode") ? daily.getAsJsonArray("weathercode") : null;
            JsonArray probs = daily.has("precipitation_probability_max") ? daily.getAsJsonArray("precipitation_probability_max") : null;
            JsonArray temps = daily.has("temperature_2m_max") ? daily.getAsJsonArray("temperature_2m_max") : null;
            Map<LocalDate, WeatherDay> map = new LinkedHashMap<>();
            for (int i = 0; i < times.size(); i++) {
                LocalDate d = LocalDate.parse(times.get(i).getAsString(), D_ISO);
                Integer code = getIntAt(codes, i);
                Integer prob = getIntAt(probs, i);
                Double tmax = getDoubleAt(temps, i);
                map.put(d, new WeatherDay(code, prob, tmax));
            }
            return map;
        } catch (Exception e) {
            log.warn("Open-Meteo 请求失败，跳过天气系数: {}", e.toString());
            return Collections.emptyMap();
        }
    }

    private static Integer getIntAt(JsonArray arr, int i) {
        if (arr == null || i >= arr.size()) {
            return null;
        }
        JsonElement e = arr.get(i);
        if (e == null || e.isJsonNull()) {
            return null;
        }
        try {
            return e.getAsInt();
        } catch (Exception ex) {
            return null;
        }
    }

    private static Double getDoubleAt(JsonArray arr, int i) {
        if (arr == null || i >= arr.size()) {
            return null;
        }
        JsonElement e = arr.get(i);
        if (e == null || e.isJsonNull()) {
            return null;
        }
        try {
            return e.getAsDouble();
        } catch (Exception ex) {
            return null;
        }
    }

    private static double round2(double v) {
        return BigDecimal.valueOf(v).setScale(2, RoundingMode.HALF_UP).doubleValue();
    }

    private static double round4(double v) {
        return BigDecimal.valueOf(v).setScale(4, RoundingMode.HALF_UP).doubleValue();
    }

    private static final class WeatherDay {
        final Integer weatherCode;
        final Integer precipProbMax;
        final Double tempMaxC;

        WeatherDay(Integer weatherCode, Integer precipProbMax, Double tempMaxC) {
            this.weatherCode = weatherCode;
            this.precipProbMax = precipProbMax;
            this.tempMaxC = tempMaxC;
        }

        String summary() {
            StringBuilder sb = new StringBuilder();
            if (weatherCode != null) {
                sb.append("code=").append(weatherCode);
            }
            if (precipProbMax != null) {
                if (sb.length() > 0) {
                    sb.append(", ");
                }
                sb.append("降水概率max=").append(precipProbMax).append("%");
            }
            if (tempMaxC != null) {
                if (sb.length() > 0) {
                    sb.append(", ");
                }
                sb.append("最高温≈").append(Math.round(tempMaxC)).append("℃");
            }
            return sb.length() == 0 ? "无详情" : sb.toString();
        }
    }
}
