package com.lanf.controller;

import com.lanf.entity.R;
import com.lanf.service.IComboMealService;
import com.lanf.service.IShopService;
import com.lanf.util.ShopChainSupport;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 结构化套餐 · 小程序/C 端（只读：详情、算价）。维护请使用 {@link com.lanf.controller.admin.AdminComboController}。
 */
@RestController
@RequestMapping("/combo")
public class ComboController {

    private static final int DEFAULT_C_SHOP_ID = 1;

    @Autowired
    private IComboMealService comboMealService;
    @Autowired
    private IShopService shopService;

    /**
     * 套餐详情（选规格页）：含子菜名称、门店价、上下架/售罄态。
     */
    @GetMapping("/detail")
    public R detail(@RequestParam Integer dishId,
                    @RequestParam(name = "shop_id", required = false) Integer shopId,
                    @RequestParam(name = "shop_code", required = false) String shopCode,
                    HttpServletRequest request) {
        if (dishId == null) {
            return R.error("dishId 不能为空");
        }
        Integer resolved = resolveShopId(request, shopId, shopCode);
        try {
            Map<String, Object> data = comboMealService.getCustomerComboDetail(dishId, resolved);
            if (data == null) {
                return R.ok().put("configured", false).put("message", "该菜品未配置套餐或套餐已停用");
            }
            data.put("configured", true);
            return R.ok(data);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 下单前试算套餐金额（与落库校验口径一致）。
     */
    @PostMapping("/calcPrice")
    @SuppressWarnings("unchecked")
    public R calcPrice(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Long comboId = longVal(body.get("comboId"));
        if (comboId == null) {
            comboId = longVal(body.get("combo_id"));
        }
        if (comboId == null) {
            return R.error("comboId 不能为空");
        }
        int qty = 1;
        if (body.get("quantity") != null) {
            qty = intVal(body.get("quantity")) != null ? intVal(body.get("quantity")) : 1;
        }
        Integer shopId = intVal(body.get("shop_id"));
        if (shopId == null) {
            shopId = resolveShopId(request, null, body.get("shop_code") != null ? body.get("shop_code").toString() : null);
        } else {
            shopId = resolveShopId(request, shopId, body.get("shop_code") != null ? body.get("shop_code").toString() : null);
        }
        Map<String, List<Integer>> selections = new LinkedHashMap<>();
        Object selObj = body.get("combo_selections");
        if (selObj == null) {
            selObj = body.get("comboSelections");
        }
        if (selObj instanceof Map) {
            for (Map.Entry<?, ?> e : ((Map<?, ?>) selObj).entrySet()) {
                String k = e.getKey().toString();
                Object v = e.getValue();
                if (v instanceof List<?>) {
                    List<Integer> ids = new java.util.ArrayList<>();
                    for (Object o : (List<?>) v) {
                        Integer id = intVal(o);
                        if (id != null) {
                            ids.add(id);
                        }
                    }
                    selections.put(k, ids);
                }
            }
        }
        try {
            double total = comboMealService.calcComboTotalYuan(comboId, shopId, qty, selections);
            return R.ok().put("total_price", total).put("comboId", comboId).put("quantity", qty);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    private Integer resolveShopId(HttpServletRequest request, Integer shopId, String shopCode) {
        try {
            Integer resolved = ShopChainSupport.resolveShopChain(request, shopId,
                    shopCode != null ? shopCode.trim() : null,
                    shopService::requireActiveShopIdByCode);
            return resolved != null ? resolved : DEFAULT_C_SHOP_ID;
        } catch (RuntimeException e) {
            throw e;
        }
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

    private static Long longVal(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Number) {
            return ((Number) o).longValue();
        }
        try {
            return Long.parseLong(o.toString().trim());
        } catch (Exception e) {
            return null;
        }
    }
}
