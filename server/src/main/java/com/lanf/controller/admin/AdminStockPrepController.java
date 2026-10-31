package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.lanf.entity.DishMaterialBom;
import com.lanf.entity.R;
import com.lanf.entity.StockPrepConfig;
import com.lanf.entity.StockPrepForecastRun;
import com.lanf.entity.StockPreparePlan;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.StockPrepForecastRunMapper;
import com.lanf.service.IDishMaterialBomService;
import com.lanf.service.IStockPreparePlanService;
import com.lanf.service.IStockPrepConfigService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 智能备货升级：BOM、门店规则、备货计划（与预测批次联动）。
 * 门店上下文依赖 X-Shop-Id（与现有报表一致）。
 */
@RestController
@RequestMapping("/admin/stock-prep")
public class AdminStockPrepController {

    @Autowired
    private IDishMaterialBomService dishMaterialBomService;
    @Autowired
    private IStockPrepConfigService stockPrepConfigService;
    @Autowired
    private IStockPreparePlanService stockPreparePlanService;
    @Autowired
    private StockPrepForecastRunMapper stockPrepForecastRunMapper;
    @Autowired
    private HttpServletRequest httpServletRequest;

    @GetMapping("/bom/list")
    public R bomList() {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error("请先指定门店 X-Shop-Id");
        }
        return R.ok().put("list", dishMaterialBomService.listByShop(sid));
    }

    @PostMapping("/bom/save")
    @AuditLog(module = "stockprep", action = "admin_stockprep_bom_save", target = "#p0.id")
    public R bomSave(@RequestBody DishMaterialBom bom) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error("请先指定门店 X-Shop-Id");
        }
        bom.setShop_id(sid);
        dishMaterialBomService.saveOrUpdate(bom);
        return R.ok();
    }

    @PostMapping("/bom/delete")
    @AuditLog(module = "stockprep", action = "admin_stockprep_bom_delete", target = "#p0")
    public R bomDelete(@RequestParam Long id) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error("请先指定门店 X-Shop-Id");
        }
        try {
            dishMaterialBomService.deleteById(id, sid);
            return R.ok();
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    @GetMapping("/config")
    public R configGet() {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error("请先指定门店 X-Shop-Id");
        }
        StockPrepConfig c = stockPrepConfigService.getByShopId(sid);
        return R.ok().put("config", c);
    }

    @PostMapping("/config/save")
    @AuditLog(module = "stockprep", action = "admin_stockprep_config_save")
    public R configSave(@RequestBody StockPrepConfig body) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error("请先指定门店 X-Shop-Id");
        }
        body.setShop_id(sid);
        stockPrepConfigService.saveConfig(body);
        return R.ok();
    }

    @PostMapping("/plan/generate")
    @AuditLog(module = "stockprep", action = "admin_stockprep_plan_generate", target = "#p0")
    public R planGenerate(@RequestParam Long runId) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        try {
            if (sid != null) {
                StockPrepForecastRun run = stockPrepForecastRunMapper.selectById(runId);
                if (run != null && run.getShop_id() != null && !run.getShop_id().equals(sid)) {
                    return R.error("预测批次不属于当前门店");
                }
            }
            Map<String, Object> result = stockPreparePlanService.generateFromForecastRun(runId);
            return R.ok().put("result", result);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    @GetMapping("/plan/list")
    public R planList(@RequestParam(required = false) String prepareDate, @RequestParam(required = false) Long runId) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error("请先指定门店 X-Shop-Id");
        }
        List<StockPreparePlan> list = stockPreparePlanService.listPlans(sid, prepareDate, runId);
        return R.ok().put("list", list);
    }

    @PostMapping("/plan/update")
    @AuditLog(module = "stockprep", action = "admin_stockprep_plan_update")
    public R planUpdate(@RequestBody Map<String, Object> body) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error("请先指定门店 X-Shop-Id");
        }
        if (body == null || body.get("id") == null) {
            return R.error("id 不能为空");
        }
        Long id = ((Number) body.get("id")).longValue();
        BigDecimal manual = body.get("manual_adjust") != null ? new BigDecimal(body.get("manual_adjust").toString()) : null;
        BigDecimal finalQty = body.get("final_qty") != null ? new BigDecimal(body.get("final_qty").toString()) : null;
        Integer status = body.get("status") != null ? ((Number) body.get("status")).intValue() : null;
        Integer operatorId = body.get("operator_id") != null ? ((Number) body.get("operator_id")).intValue() : null;
        if (operatorId == null) {
            operatorId = (Integer) httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        }
        Object skipObj = body.get("skip_adjust_ratio_check");
        boolean skipRatio = Boolean.TRUE.equals(skipObj)
                || "true".equalsIgnoreCase(String.valueOf(skipObj));
        try {
            stockPreparePlanService.updatePlan(id, manual, finalQty, status, operatorId, sid, skipRatio);
            return R.ok();
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    @PostMapping("/plan/batchStatus")
    @AuditLog(module = "stockprep", action = "admin_stockprep_plan_batch_status")
    public R planBatchStatus(@RequestBody Map<String, Object> body) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error("请先指定门店 X-Shop-Id");
        }
        if (body == null || body.get("ids") == null || body.get("status") == null) {
            return R.error("ids 与 status 不能为空");
        }
        Object idsObj = body.get("ids");
        if (!(idsObj instanceof List)) {
            return R.error("ids 须为数组");
        }
        List<Long> ids = new ArrayList<>();
        for (Object o : (List<?>) idsObj) {
            if (o instanceof Number) {
                ids.add(((Number) o).longValue());
            }
        }
        if (ids.isEmpty()) {
            return R.error("ids 不能为空");
        }
        Integer status = ((Number) body.get("status")).intValue();
        Integer operatorId = body.get("operator_id") != null ? ((Number) body.get("operator_id")).intValue() : null;
        if (operatorId == null) {
            operatorId = (Integer) httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        }
        try {
            Map<String, Object> result = stockPreparePlanService.updatePlanBatchStatus(ids, status, operatorId, sid);
            return R.ok().put("result", result);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }
}
