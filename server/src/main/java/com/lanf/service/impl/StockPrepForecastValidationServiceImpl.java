package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.dto.DishDayActualDTO;
import com.lanf.entity.DailyStat;
import com.lanf.entity.StockPrepForecastDay;
import com.lanf.entity.StockPrepForecastDish;
import com.lanf.entity.StockPrepForecastRun;
import com.lanf.mapper.OrderMapper;
import com.lanf.mapper.StockPrepForecastDayMapper;
import com.lanf.mapper.StockPrepForecastDishMapper;
import com.lanf.mapper.StockPrepForecastRunMapper;
import com.lanf.service.IDailyStatService;
import com.lanf.service.StockPrepForecastValidationService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 预测 vs 实际：订单明细销量、订单量、日结 t_daily_stat；结果写回预测表供训练导出。
 */
@Service
public class StockPrepForecastValidationServiceImpl implements StockPrepForecastValidationService {

    private static final ZoneId ZONE_SH = ZoneId.of("Asia/Shanghai");

    @Autowired
    private StockPrepForecastRunMapper runMapper;
    @Autowired
    private StockPrepForecastDayMapper dayMapper;
    @Autowired
    private StockPrepForecastDishMapper dishMapper;
    @Autowired
    private OrderMapper orderMapper;
    @Autowired
    private IDailyStatService dailyStatService;

    @Override
    public Map<String, Object> validateRun(Long runId, Integer shopId, boolean force) {
        if (runId == null) {
            throw new RuntimeException("runId 不能为空");
        }
        StockPrepForecastRun run = runMapper.selectById(runId);
        if (run == null) {
            throw new RuntimeException("预测批次不存在");
        }
        assertShopScope(run, shopId);

        LocalDate lastComplete = LocalDate.now(ZONE_SH).minusDays(1);

        List<StockPrepForecastDay> days = dayMapper.selectList(new QueryWrapper<StockPrepForecastDay>()
                .eq("run_id", runId)
                .orderByAsc("stat_date"));

        int updatedDays = 0;
        int skippedFuture = 0;
        int skippedCached = 0;
        int updatedDishes = 0;

        Integer sid = run.getShop_id();

        for (StockPrepForecastDay dayRow : days) {
            LocalDate statDate = toLocalDate(dayRow.getStat_date());
            if (statDate == null) {
                continue;
            }
            if (statDate.isAfter(lastComplete)) {
                skippedFuture++;
                continue;
            }
            if (!force && dayRow.getDay_validated_at() != null) {
                skippedCached++;
                continue;
            }

            String startTime = statDate + " 00:00:00";
            String endTime = statDate + " 23:59:59";
            Map<String, Object> p = new HashMap<>();
            p.put("startTime", startTime);
            p.put("endTime", endTime);
            if (sid != null) {
                p.put("shopId", sid);
            }

            List<DishDayActualDTO> actualList = orderMapper.listDishActualQtyForShopDay(p);
            Map<String, Long> actualByName = new HashMap<>();
            for (DishDayActualDTO dto : actualList) {
                if (dto == null || !StringUtils.hasText(dto.getDish_name())) {
                    continue;
                }
                long q = dto.getTotal_qty() == null ? 0L : dto.getTotal_qty();
                actualByName.put(dto.getDish_name().trim(), q);
            }

            List<StockPrepForecastDish> dishes = dishMapper.selectList(new QueryWrapper<StockPrepForecastDish>()
                    .eq("run_id", runId)
                    .eq("stat_date", dayRow.getStat_date())
                    .orderByAsc("dish_name"));

            int predSum = 0;
            int actScopeSum = 0;
            Date now = new Date();
            for (StockPrepForecastDish di : dishes) {
                if (di == null || !StringUtils.hasText(di.getDish_name())) {
                    continue;
                }
                int pred = di.getPredicted_servings() == null ? 0 : di.getPredicted_servings();
                predSum += pred;
                long act = actualByName.getOrDefault(di.getDish_name().trim(), 0L);
                int actInt = (int) Math.min(Integer.MAX_VALUE, act);
                actScopeSum += actInt;
                di.setActual_quantity(actInt);
                di.setValidated_at(now);
                dishMapper.updateById(di);
                updatedDishes++;
            }

            Long allQty = orderMapper.sumAllDishQtyForShopDay(p);
            Long ordCnt = orderMapper.countSuccessOrdersForShopDay(p);

            dayRow.setPredicted_servings_sum(predSum);
            dayRow.setActual_servings_forecast_dishes(actScopeSum);
            dayRow.setActual_servings_all_dishes(allQty != null ? allQty.intValue() : null);
            dayRow.setActual_order_count(ordCnt != null ? ordCnt.intValue() : null);

            DailyStat ds = loadDailyStat(statDate, sid);
            if (ds != null) {
                dayRow.setDaily_stat_total_amount(ds.getTotal_amount());
                dayRow.setDaily_stat_discount_amount(ds.getDiscount_amount());
                dayRow.setDaily_stat_refund_amount(ds.getRefund_amount());
                dayRow.setDaily_stat_material_cost(ds.getMaterial_cost());
                dayRow.setDaily_stat_settled(ds.getSettled_at() != null ? 1 : 0);
            } else {
                dayRow.setDaily_stat_total_amount(null);
                dayRow.setDaily_stat_discount_amount(null);
                dayRow.setDaily_stat_refund_amount(null);
                dayRow.setDaily_stat_material_cost(null);
                dayRow.setDaily_stat_settled(null);
            }
            dayRow.setDay_validated_at(now);
            dayMapper.updateById(dayRow);
            updatedDays++;
        }

        runMapper.update(null, new UpdateWrapper<StockPrepForecastRun>()
                .set("last_validated_at", new Date())
                .eq("id", runId));

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("runId", runId);
        out.put("lastCompleteDate", lastComplete.toString());
        out.put("updatedDays", updatedDays);
        out.put("updatedDishRows", updatedDishes);
        out.put("skippedFutureDays", skippedFuture);
        out.put("skippedAlreadyValidatedDays", skippedCached);
        return out;
    }

    @Override
    public Map<String, Object> exportTrainingRows(Long runId, Integer shopId) {
        if (runId == null) {
            throw new RuntimeException("runId 不能为空");
        }
        StockPrepForecastRun run = runMapper.selectById(runId);
        if (run == null) {
            throw new RuntimeException("预测批次不存在");
        }
        assertShopScope(run, shopId);

        List<StockPrepForecastDay> days = dayMapper.selectList(new QueryWrapper<StockPrepForecastDay>()
                .eq("run_id", runId)
                .orderByAsc("stat_date"));
        Map<LocalDate, StockPrepForecastDay> dayMap = days.stream()
                .filter(d -> d != null && d.getStat_date() != null)
                .collect(Collectors.toMap(d -> toLocalDate(d.getStat_date()), d -> d, (a, b) -> a, LinkedHashMap::new));

        List<StockPrepForecastDish> dishes = dishMapper.selectList(new QueryWrapper<StockPrepForecastDish>()
                .eq("run_id", runId)
                .orderByAsc("stat_date")
                .orderByAsc("dish_name"));

        List<Map<String, Object>> rows = new ArrayList<>();
        for (StockPrepForecastDish di : dishes) {
            if (di == null) {
                continue;
            }
            LocalDate sd = toLocalDate(di.getStat_date());
            StockPrepForecastDay day = sd != null ? dayMap.get(sd) : null;

            Map<String, Object> row = new LinkedHashMap<>();
            row.put("feature_schema_version", "stock_prep_v1");
            row.put("run_id", run.getId());
            row.put("shop_id", run.getShop_id());
            row.put("run_created_at", run.getCreated_at());
            row.put("stat_date", sd != null ? sd.toString() : null);
            row.put("dish_id", di.getDish_id());
            row.put("dish_name", di.getDish_name());

            if (day != null) {
                row.put("iso_day_of_week", day.getIso_day_of_week());
                row.put("day_kind", day.getDay_kind());
                row.put("is_holiday", day.getIs_holiday() != null && day.getIs_holiday() == 1);
                row.put("holiday_name", day.getHoliday_name());
                row.put("factor_holiday", toDouble(day.getFactor_holiday()));
                row.put("factor_weather", toDouble(day.getFactor_weather()));
                row.put("factor_composite", toDouble(day.getFactor_composite()));
                row.put("weather_available", day.getWeather_available() != null && day.getWeather_available() == 1);
                row.put("weather_code", day.getWeather_code());
                row.put("weather_precip_prob_max", day.getWeather_precip_prob());
                row.put("weather_temp_max_c", day.getWeather_temp_max() != null ? day.getWeather_temp_max().doubleValue() : null);
                row.put("predicted_servings_sum_day", day.getPredicted_servings_sum());
                row.put("actual_servings_forecast_dishes_day", day.getActual_servings_forecast_dishes());
                row.put("actual_servings_all_dishes_day", day.getActual_servings_all_dishes());
                row.put("actual_order_count_day", day.getActual_order_count());
                row.put("daily_stat_total_amount", toDouble(day.getDaily_stat_total_amount()));
                row.put("daily_stat_discount_amount", toDouble(day.getDaily_stat_discount_amount()));
                row.put("daily_stat_refund_amount", toDouble(day.getDaily_stat_refund_amount()));
                row.put("daily_stat_material_cost", toDouble(day.getDaily_stat_material_cost()));
                row.put("daily_stat_settled", day.getDaily_stat_settled());
                row.put("day_validated_at", day.getDay_validated_at());
            }

            int pred = di.getPredicted_servings() == null ? 0 : di.getPredicted_servings();
            double baseline = di.getBaseline_avg() != null ? di.getBaseline_avg().doubleValue() : 0.0;
            Integer act = di.getActual_quantity();

            row.put("baseline_avg_for_dow", baseline);
            row.put("predicted_servings", pred);
            row.put("label_actual_quantity", act);
            if (act != null) {
                row.put("error_abs", act - pred);
                row.put("error_ape", pred > 0 ? (act - pred) / (double) pred : null);
            } else {
                row.put("error_abs", null);
                row.put("error_ape", null);
            }
            row.put("dish_row_validated_at", di.getValidated_at());
            rows.add(row);
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("runId", runId);
        out.put("rowCount", rows.size());
        out.put("description", "扁平特征+label_actual_quantity；请先对过去自然日调用 validate 接口写入实际值与日汇总。");
        out.put("rows", rows);
        return out;
    }

    private static void assertShopScope(StockPrepForecastRun run, Integer shopId) {
        if (shopId != null && run.getShop_id() != null && !run.getShop_id().equals(shopId)) {
            throw new RuntimeException("无权操作该预测批次");
        }
    }

    private DailyStat loadDailyStat(LocalDate statDate, Integer shopId) {
        java.sql.Date sqlD = java.sql.Date.valueOf(statDate);
        QueryWrapper<DailyStat> q = new QueryWrapper<DailyStat>().eq("stat_date", sqlD);
        if (shopId != null) {
            q.eq("shop_id", shopId);
            DailyStat one = dailyStatService.getOne(q);
            if (one != null) {
                return one;
            }
        }
        return dailyStatService.getOne(new QueryWrapper<DailyStat>().eq("stat_date", sqlD).isNull("shop_id"));
    }

    private static LocalDate toLocalDate(Date d) {
        if (d == null) {
            return null;
        }
        return d.toInstant().atZone(ZONE_SH).toLocalDate();
    }

    private static Double toDouble(BigDecimal b) {
        return b == null ? null : b.doubleValue();
    }
}
