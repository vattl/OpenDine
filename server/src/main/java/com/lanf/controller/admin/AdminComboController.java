package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.lanf.entity.R;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.service.IComboMealService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;

/**
 * 结构化套餐 · 运营后台（维护定义，支持门店隔离与总部通用模板继承）。
 * 小程序只读请用 {@link com.lanf.controller.ComboController}（/combo/*）。
 */
@RestController
@RequestMapping("/admin/combo")
public class AdminComboController {

    @Autowired
    private IComboMealService comboMealService;

    @Autowired(required = false)
    private AdminShopScopeGuard adminShopScopeGuard;

    @Autowired
    private HttpServletRequest request;

    @GetMapping("/getByDishId")
    public R getByDishId(@RequestParam Integer dishId,
                         @RequestParam(required = false) Integer shopId) {
        if (dishId == null) {
            return R.error("dishId 不能为空");
        }
        Integer targetShopId = resolveTargetShop(shopId);
        com.lanf.entity.Combo c = comboMealService.getByDishId(dishId, targetShopId);
        if (c == null) {
            return R.ok().put("combo", null);
        }
        return R.ok()
                .put("combo", c)
                .put("definition", comboMealService.buildComboMenuPayload(c.getId()))
                .put("forAdmin", true);
    }

    @PostMapping("/save")
    @SuppressWarnings("unchecked")
    @AuditLog(module = "combo", action = "admin_combo_save")
    public R save(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Integer dishId = intVal(body.get("dishId"));
        if (dishId == null) {
            dishId = intVal(body.get("dish_id"));
        }
        if (dishId == null) {
            return R.error("dishId 不能为空");
        }
        Integer requestedShopId = intVal(body.get("shopId"));
        if (requestedShopId == null) {
            requestedShopId = intVal(body.get("shop_id"));
        }
        if (requestedShopId == null) {
            requestedShopId = AdminShopRequest.getResolvedShopId(request);
        }
        int[] holder = new int[1];
        if (adminShopScopeGuard != null) {
            R guardErr = adminShopScopeGuard.resolveTargetShopId(requestedShopId, holder);
            if (guardErr != null) {
                return guardErr;
            }
        } else {
            holder[0] = requestedShopId != null ? requestedShopId : 0;
        }
        int targetShopId = holder[0];

        String comboType = body.get("comboType") != null ? body.get("comboType").toString() : "groups";
        int status = 1;
        if (body.get("status") != null) {
            Integer st = intVal(body.get("status"));
            status = st != null ? st : 1;
        }
        List<Map<String, Object>> fixed = (List<Map<String, Object>>) body.get("fixedItems");
        if (fixed == null) {
            fixed = (List<Map<String, Object>>) body.get("fixed_items");
        }
        List<Map<String, Object>> groups = (List<Map<String, Object>>) body.get("groups");
        try {
            comboMealService.saveComboDefinition(dishId, targetShopId, comboType, status, fixed, groups, body);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        return R.ok();
    }

    private Integer resolveTargetShop(Integer requestedShopId) {
        if (requestedShopId == null) {
            requestedShopId = AdminShopRequest.getResolvedShopId(request);
        }
        if (adminShopScopeGuard != null) {
            int[] holder = new int[1];
            R err = adminShopScopeGuard.resolveTargetShopId(requestedShopId, holder);
            if (err == null) {
                return holder[0];
            }
        }
        return requestedShopId != null ? requestedShopId : 0;
    }

    private static Integer intVal(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Number) {
            return ((Number) o).intValue();
        }
        try {
            return Integer.parseInt(o.toString().trim());
        } catch (Exception e) {
            return null;
        }
    }
}
