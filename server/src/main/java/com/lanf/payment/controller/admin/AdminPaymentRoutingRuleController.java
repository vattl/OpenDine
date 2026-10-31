package com.lanf.payment.controller.admin;

import com.lanf.entity.R;
import com.lanf.payment.config.PaymentConfigSync;
import com.lanf.payment.entity.PaymentRoutingRuleEntity;
import com.lanf.payment.service.PaymentRoutingRuleService;
import com.lanf.payment.support.PaymentAdminShopScope;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 门店商户分流路由规则管理端控制器（支持就餐方式、金额区间、指定菜品/品类等多条件规则链与试算模拟）。
 */
@RestController
@RequestMapping("/admin/payment/routing-rules")
public class AdminPaymentRoutingRuleController {

    @Autowired
    private PaymentRoutingRuleService routingRuleService;
    @Autowired
    private PaymentAdminShopScope shopScope;
    @Autowired
    private PaymentConfigSync paymentConfigSync;

    @GetMapping
    public R listRules(@RequestParam(required = false) Integer shopId,
                       @RequestParam(required = false, defaultValue = "wechat") String channel) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        return R.ok(routingRuleService.listForAdmin(holder[0], channel));
    }

    @GetMapping("/{id}")
    public R getRule(@PathVariable Long id) {
        PaymentRoutingRuleEntity rule = routingRuleService.getById(id);
        if (rule == null) {
            return R.error("路由规则不存在");
        }
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(rule.getShop_id(), holder);
        if (err != null) {
            return err;
        }
        return R.ok(routingRuleService.toRuleMap(rule));
    }

    @PostMapping
    public R createRule(@RequestParam(required = false) Integer shopId,
                        @RequestBody Map<String, Object> body) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        int sid = holder[0];
        R writeErr = shopScope.assertWritableShopId(sid);
        if (writeErr != null) {
            return writeErr;
        }
        try {
            PaymentRoutingRuleEntity created = routingRuleService.create(sid, body);
            paymentConfigSync.reloadShop(sid);
            return R.ok(routingRuleService.toRuleMap(created));
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        }
    }

    @PutMapping("/{id}")
    public R updateRule(@PathVariable Long id,
                        @RequestParam(required = false) Integer shopId,
                        @RequestBody Map<String, Object> body) {
        PaymentRoutingRuleEntity existing = routingRuleService.getById(id);
        if (existing == null) {
            return R.error("路由规则不存在");
        }
        int rowShop = existing.getShop_id() != null ? existing.getShop_id() : PaymentAdminShopScope.GLOBAL_SHOP_ID;
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId != null ? shopId : rowShop, holder);
        if (err != null) {
            return err;
        }
        int sid = holder[0];
        R writeErr = shopScope.assertWritableShopId(sid);
        if (writeErr != null) {
            return writeErr;
        }
        try {
            PaymentRoutingRuleEntity updated = routingRuleService.update(id, sid, body);
            paymentConfigSync.reloadShop(sid);
            return R.ok(routingRuleService.toRuleMap(updated));
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        }
    }

    @DeleteMapping("/{id}")
    public R deleteRule(@PathVariable Long id,
                        @RequestParam(required = false) Integer shopId) {
        PaymentRoutingRuleEntity existing = routingRuleService.getById(id);
        if (existing == null) {
            return R.error("路由规则不存在");
        }
        int rowShop = existing.getShop_id() != null ? existing.getShop_id() : PaymentAdminShopScope.GLOBAL_SHOP_ID;
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId != null ? shopId : rowShop, holder);
        if (err != null) {
            return err;
        }
        int sid = holder[0];
        R writeErr = shopScope.assertWritableShopId(sid);
        if (writeErr != null) {
            return writeErr;
        }
        boolean ok = routingRuleService.delete(id, sid);
        if (!ok) {
            return R.error("删除失败");
        }
        paymentConfigSync.reloadShop(sid);
        return R.ok().put("deleted", true);
    }

    @PutMapping("/sort")
    public R sortRules(@RequestParam(required = false) Integer shopId,
                       @RequestParam(required = false, defaultValue = "wechat") String channel,
                       @RequestBody Map<String, Object> body) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        int sid = holder[0];
        R writeErr = shopScope.assertWritableShopId(sid);
        if (writeErr != null) {
            return writeErr;
        }

        List<Long> ids = new ArrayList<>();
        Object rawIds = body.get("ruleIds");
        if (rawIds instanceof List) {
            for (Object item : (List<?>) rawIds) {
                if (item instanceof Number) {
                    ids.add(((Number) item).longValue());
                } else if (item != null) {
                    try { ids.add(Long.parseLong(item.toString().trim())); } catch (NumberFormatException ignored) {}
                }
            }
        }
        routingRuleService.sort(sid, channel, ids);
        paymentConfigSync.reloadShop(sid);
        return R.ok().put("sorted", true);
    }

    @PostMapping("/simulate")
    public R simulate(@RequestParam(required = false) Integer shopId,
                      @RequestBody Map<String, Object> body) {
        int[] holder = new int[1];
        R err = shopScope.resolveTargetShopId(shopId, holder);
        if (err != null) {
            return err;
        }
        return R.ok(routingRuleService.simulate(holder[0], body));
    }
}
