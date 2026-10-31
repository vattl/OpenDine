package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.config.StockPrepForecastProperties;
import com.lanf.entity.*;
import com.lanf.mapper.DishMaterialBomMapper;
import com.lanf.mapper.StockPrepForecastDishMapper;
import com.lanf.mapper.StockPrepForecastRunMapper;
import com.lanf.mapper.StockPreparePlanMapper;
import com.lanf.service.IDishService;
import com.lanf.service.IMaterialService;
import com.lanf.service.IStockInService;
import com.lanf.service.IStockPreparePlanService;
import com.lanf.service.IStockPrepConfigService;
import com.lanf.util.StockPrepOnsaleCatalog;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * 预测批次 × BOM → t_stock_prepare_plan；建议量 = 预测消耗 − 当前库存 + 安全库存。
 */
@Service
public class StockPreparePlanServiceImpl implements IStockPreparePlanService {

    private static final ZoneId ZONE_SH = ZoneId.of("Asia/Shanghai");
    private static final DateTimeFormatter D_ISO = DateTimeFormatter.ISO_LOCAL_DATE;

    @Autowired
    private StockPreparePlanMapper planMapper;
    @Autowired
    private DishMaterialBomMapper bomMapper;
    @Autowired
    private StockPrepForecastRunMapper runMapper;
    @Autowired
    private StockPrepForecastDishMapper forecastDishMapper;
    @Autowired
    private IMaterialService materialService;
    @Autowired
    private IStockPrepConfigService stockPrepConfigService;
    @Autowired
    private IDishService dishService;
    @Autowired
    private IStockInService stockInService;
    @Autowired
    private StockPrepForecastProperties forecastProps;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> generateFromForecastRun(Long runId) {
        if (runId == null) {
            throw new RuntimeException("runId 不能为空");
        }
        StockPrepForecastRun run = runMapper.selectById(runId);
        if (run == null) {
            throw new RuntimeException("预测批次不存在");
        }
        if (run.getShop_id() == null) {
            throw new RuntimeException("该批次无门店，无法按店生成备货计划");
        }
        Integer shopId = run.getShop_id();
        StockPrepConfig cfg = stockPrepConfigService.getOrCreateForShop(shopId);
        BigDecimal safeRate = nvl(cfg.getSafe_stock_rate(), new BigDecimal("0.10"));
        BigDecimal defaultLoss = nvl(cfg.getDefault_loss_rate(), new BigDecimal("0.05"));

        List<StockPrepForecastDish> lines = forecastDishMapper.selectList(new QueryWrapper<StockPrepForecastDish>()
                .eq("run_id", runId));
        StockPrepOnsaleCatalog.Index onsaleCatalog = StockPrepOnsaleCatalog.load(dishService, shopId);
        Map<String, Integer> nameToId = onsaleCatalog.getNameToId();

        Map<String, BigDecimal> consume = new LinkedHashMap<>();
        int skippedOffsale = 0;
        for (StockPrepForecastDish line : lines) {
            if (line == null || line.getStat_date() == null) {
                continue;
            }
            if (StringUtils.hasText(line.getDish_name()) && !onsaleCatalog.containsName(line.getDish_name())) {
                skippedOffsale++;
                continue;
            }
            int dishId = resolveDishId(line, nameToId);
            if (dishId <= 0) {
                continue;
            }
            int pred = line.getPredicted_servings() == null ? 0 : line.getPredicted_servings();
            if (pred <= 0) {
                continue;
            }
            List<DishMaterialBom> boms = bomMapper.selectList(new QueryWrapper<DishMaterialBom>()
                    .eq("shop_id", shopId)
                    .eq("dish_id", dishId)
                    .eq("is_enabled", 1));
            if (boms == null || boms.isEmpty()) {
                continue;
            }
            String dateKey = toLocalDate(line.getStat_date()).format(D_ISO);
            for (DishMaterialBom bom : boms) {
                if (bom == null || bom.getMaterial_id() == null) {
                    continue;
                }
                BigDecimal dosage = nvl(bom.getDosage(), BigDecimal.ZERO);
                BigDecimal loss = bom.getLoss_rate() != null ? bom.getLoss_rate() : defaultLoss;
                BigDecimal mult = BigDecimal.ONE.add(loss);
                BigDecimal part = BigDecimal.valueOf(pred).multiply(dosage).multiply(mult);
                String k = dateKey + "|" + bom.getMaterial_id();
                consume.merge(k, part, BigDecimal::add);
            }
        }

        planMapper.delete(new QueryWrapper<StockPreparePlan>().eq("run_id", runId));

        int inserted = 0;
        for (Map.Entry<String, BigDecimal> e : consume.entrySet()) {
            String[] parts = e.getKey().split("\\|");
            LocalDate ld = LocalDate.parse(parts[0], D_ISO);
            int materialId = Integer.parseInt(parts[1]);
            BigDecimal forecastConsume = e.getValue().setScale(3, RoundingMode.HALF_UP);

            Material m = materialService.getById(materialId);
            BigDecimal current = BigDecimal.ZERO;
            if (m != null && m.getStock() != null) {
                if (m.getShop_id() == null || m.getShop_id().equals(shopId)) {
                    current = m.getStock();
                }
            }
            BigDecimal safeStock = forecastConsume.multiply(safeRate).setScale(3, RoundingMode.HALF_UP);
            BigDecimal suggest = forecastConsume.subtract(current).add(safeStock);
            if (suggest.compareTo(BigDecimal.ZERO) < 0) {
                suggest = BigDecimal.ZERO;
            }
            suggest = suggest.setScale(3, RoundingMode.HALF_UP);

            StockPreparePlan p = new StockPreparePlan();
            p.setShop_id(shopId);
            p.setRun_id(runId);
            p.setPrepare_date(java.sql.Date.valueOf(ld));
            p.setMaterial_id(materialId);
            p.setCurrent_stock(current.setScale(3, RoundingMode.HALF_UP));
            p.setForecast_consume(forecastConsume);
            p.setSafe_stock(safeStock);
            p.setSuggest_qty(suggest);
            p.setManual_adjust(BigDecimal.ZERO.setScale(3, RoundingMode.HALF_UP));
            p.setFinal_qty(suggest);
            p.setStatus(0);
            planMapper.insert(p);
            inserted++;
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("runId", runId);
        out.put("planRowsInserted", inserted);
        out.put("aggregateKeys", consume.size());
        out.put("skippedOffsaleForecastLines", skippedOffsale);
        return out;
    }

    @Override
    public List<StockPreparePlan> listPlans(Integer shopId, String prepareDate, Long runId) {
        QueryWrapper<StockPreparePlan> q = new QueryWrapper<>();
        if (shopId != null) {
            q.eq("shop_id", shopId);
        }
        if (StringUtils.hasText(prepareDate)) {
            q.eq("prepare_date", prepareDate.trim());
        }
        if (runId != null) {
            q.eq("run_id", runId);
        }
        q.orderByAsc("prepare_date", "material_id");
        return planMapper.selectList(q);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void updatePlan(Long id, BigDecimal manualAdjust, BigDecimal finalQty, Integer status, Integer operatorId, Integer requestShopId, boolean skipAdjustRatioCheck) {
        if (id == null) {
            throw new RuntimeException("id 不能为空");
        }
        StockPreparePlan p = planMapper.selectById(id);
        if (p == null) {
            throw new RuntimeException("备货计划不存在");
        }
        if (requestShopId != null && p.getShop_id() != null && !p.getShop_id().equals(requestShopId)) {
            throw new RuntimeException("无权修改其它门店的备货计划");
        }
        Integer oldStatus = p.getStatus();
        BigDecimal suggest = nvl(p.getSuggest_qty(), BigDecimal.ZERO);

        if (manualAdjust != null) {
            p.setManual_adjust(manualAdjust.setScale(3, RoundingMode.HALF_UP));
        }
        if (finalQty != null) {
            p.setFinal_qty(finalQty.setScale(3, RoundingMode.HALF_UP));
        } else if (manualAdjust != null) {
            BigDecimal adj = nvl(p.getManual_adjust(), BigDecimal.ZERO);
            BigDecimal next = suggest.add(adj);
            if (next.compareTo(BigDecimal.ZERO) < 0) {
                next = BigDecimal.ZERO;
            }
            p.setFinal_qty(next.setScale(3, RoundingMode.HALF_UP));
        }

        boolean becomingWarehoused = status != null && status == 3 && (oldStatus == null || !oldStatus.equals(3));
        if (!skipAdjustRatioCheck && (manualAdjust != null || finalQty != null || becomingWarehoused)) {
            validateFinalAgainstSuggest(suggest, nvl(p.getFinal_qty(), BigDecimal.ZERO));
        }

        if (status != null) {
            p.setStatus(status);
        }
        if (operatorId != null) {
            p.setOperator_id(operatorId);
        }
        planMapper.updateById(p);

        if (becomingWarehoused) {
            applyInboundFromPlan(p, operatorId);
        }
    }

    @Override
    public Map<String, Object> updatePlanBatchStatus(List<Long> ids, Integer status, Integer operatorId, Integer requestShopId) {
        if (ids == null || ids.isEmpty()) {
            throw new RuntimeException("ids 不能为空");
        }
        if (status == null) {
            throw new RuntimeException("status 不能为空");
        }
        int ok = 0;
        List<String> errors = new ArrayList<>();
        for (Long id : ids) {
            if (id == null) {
                continue;
            }
            try {
                updatePlan(id, null, null, status, operatorId, requestShopId, false);
                ok++;
            } catch (RuntimeException ex) {
                errors.add(id + ": " + ex.getMessage());
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("successCount", ok);
        out.put("failureCount", errors.size());
        out.put("errors", errors);
        return out;
    }

    private void validateFinalAgainstSuggest(BigDecimal suggest, BigDecimal finalQty) {
        if (suggest.compareTo(BigDecimal.ZERO) <= 0) {
            return;
        }
        if (finalQty == null) {
            return;
        }
        double ratio = forecastProps.getPlanMaxAdjustRatio();
        if (ratio < 0 || ratio > 1) {
            ratio = 0.30;
        }
        BigDecimal r = BigDecimal.valueOf(ratio);
        BigDecimal low = suggest.multiply(BigDecimal.ONE.subtract(r)).setScale(3, RoundingMode.HALF_UP);
        BigDecimal high = suggest.multiply(BigDecimal.ONE.add(r)).setScale(3, RoundingMode.HALF_UP);
        if (finalQty.compareTo(low) < 0 || finalQty.compareTo(high) > 0) {
            int pct = (int) Math.round(ratio * 100);
            throw new RuntimeException("最终备货量相对建议量超出允许范围(±" + pct + "%)，或传 skip_adjust_ratio_check=true 跳过校验");
        }
    }

    private void applyInboundFromPlan(StockPreparePlan p, Integer operatorId) {
        Integer shopId = p.getShop_id();
        Integer materialId = p.getMaterial_id();
        if (shopId == null || materialId == null) {
            throw new RuntimeException("备货计划缺少门店或原料");
        }
        Material m = materialService.getById(materialId);
        if (m == null) {
            throw new RuntimeException("原材料不存在");
        }
        if (m.getShop_id() != null && !m.getShop_id().equals(shopId)) {
            throw new RuntimeException("原料不属于该备货计划门店");
        }
        BigDecimal qty = nvl(p.getFinal_qty(), BigDecimal.ZERO);
        if (qty.compareTo(BigDecimal.ZERO) <= 0) {
            qty = nvl(p.getSuggest_qty(), BigDecimal.ZERO);
        }
        if (qty.compareTo(BigDecimal.ZERO) <= 0) {
            throw new RuntimeException("已入库数量须大于0（请填写 final_qty 或确保建议量>0）");
        }
        qty = qty.setScale(3, RoundingMode.HALF_UP);
        StockIn in = new StockIn();
        in.setShop_id(shopId);
        in.setMaterial_id(materialId);
        in.setQuantity(qty);
        in.setRemark("STOCK_PREP_PLAN:" + p.getId());
        in.setOperator_id(operatorId);
        stockInService.save(in);
        m.setStock(m.getStock() != null ? m.getStock().add(qty) : qty);
        materialService.updateById(m);
    }

    private static int resolveDishId(StockPrepForecastDish line, Map<String, Integer> nameToId) {
        if (line.getDish_id() != null && line.getDish_id() > 0) {
            return line.getDish_id();
        }
        if (!StringUtils.hasText(line.getDish_name())) {
            return -1;
        }
        Integer id = nameToId.get(line.getDish_name().trim());
        return id == null ? -1 : id;
    }

    private static LocalDate toLocalDate(java.util.Date d) {
        return d.toInstant().atZone(ZONE_SH).toLocalDate();
    }

    private static BigDecimal nvl(BigDecimal v, BigDecimal dft) {
        return v != null ? v : dft;
    }
}
