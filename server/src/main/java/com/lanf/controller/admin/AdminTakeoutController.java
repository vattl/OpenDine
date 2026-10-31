package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.entity.ShopTakeoutConfig;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.IShopTakeoutConfigService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.event.TakeoutOrderAcceptedEvent;
import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.exception.ZsqRemoteOrderMissingException;
import com.lanf.integration.web.dto.ZsqRiderTrackingResponse;
import com.lanf.service.ITakeoutZsqIntegrationService;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.OrderListTimeRangeResolver;
import com.lanf.util.ShopBusinessWindowResolver;
import com.lanf.util.TakeoutZsqDispatchRecovery;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.Date;
import java.util.Map;

/**
 * 运营端外卖：门店开关与费用、配送单列表、履约状态。
 */
@RestController
@RequestMapping("/admin/takeout")
public class AdminTakeoutController {

    @Autowired
    private IShopTakeoutConfigService shopTakeoutConfigService;
    @Autowired
    private ITakeoutDeliveryService takeoutDeliveryService;
    @Autowired
    private IOrderService orderService;
    @Autowired(required = false)
    private IShopService shopService;
    @Autowired
    private HttpServletRequest httpServletRequest;
    @Autowired
    private ApplicationEventPublisher eventPublisher;
    @Autowired
    private ITakeoutZsqIntegrationService takeoutZsqIntegrationService;

    private static final ZoneId ASIA_SHANGHAI = ZoneId.of("Asia/Shanghai");

    @GetMapping("/config")
    public R getConfig() {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error(400, "请指定门店（X-Shop-Id）");
        }
        return R.ok().put("config", shopTakeoutConfigService.resolveForShop(sid));
    }

    @PostMapping("/config/save")
    @AuditLog(module = "takeout", action = "admin_takeout_config_save")
    public R saveConfig(@RequestBody Map<String, Object> body) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error(400, "请指定门店（X-Shop-Id）");
        }
        ShopTakeoutConfig saved = shopTakeoutConfigService.upsertForShopFromMap(sid, body != null ? body : java.util.Collections.emptyMap());
        return R.ok().put("config", saved);
    }

    /**
     * 配送扩展列表（当前门店，分页，支持自定义时间筛选，默认当前营业日）。
     * 请求体：
     * - pageNum（默认1）
     * - pageSize（默认20，最大100）
     * - dispatch_status（可选，all 或不传表示全部）
     * - startTime / start_time（可选，格式 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd）
     * - endTime / end_time（可选，格式同上）
     */
    @PostMapping("/delivery/list")
    public R deliveryList(@RequestBody(required = false) Map<String, Object> body) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null) {
            return R.error(400, "请指定门店（X-Shop-Id）");
        }
        int page = 1;
        int size = 20;
        String st = null;
        String startTimeStr = null;
        String endTimeStr = null;
        if (body != null) {
            if (body.get("pageNum") instanceof Number) {
                page = Math.max(1, ((Number) body.get("pageNum")).intValue());
            }
            if (body.get("pageSize") instanceof Number) {
                size = Math.min(100, Math.max(1, ((Number) body.get("pageSize")).intValue()));
            }
            if (body.get("dispatch_status") != null) {
                st = body.get("dispatch_status").toString().trim();
            }
            if (body.get("startTime") != null) {
                startTimeStr = body.get("startTime").toString().trim();
            } else if (body.get("start_time") != null) {
                startTimeStr = body.get("start_time").toString().trim();
            }
            if (body.get("endTime") != null) {
                endTimeStr = body.get("endTime").toString().trim();
            } else if (body.get("end_time") != null) {
                endTimeStr = body.get("end_time").toString().trim();
            }
        }

        Shop shop = shopService != null ? shopService.getById(sid) : null;
        LocalTime settleTime = ShopBusinessWindowResolver.resolveSettleTimeOrDefault(shop);
        OrderListTimeRangeResolver.Range range;
        try {
            range = OrderListTimeRangeResolver.resolve(LocalDateTime.now(), startTimeStr, endTimeStr, settleTime);
        } catch (IllegalArgumentException e) {
            return R.error(400, e.getMessage());
        }

        Date startDate = Date.from(range.getStart().atZone(ASIA_SHANGHAI).toInstant());
        Date endDate = Date.from(range.getEnd().atZone(ASIA_SHANGHAI).toInstant());

        IPage<TakeoutDelivery> pg = takeoutDeliveryService.pageByShop(sid, page, size, st, startDate, endDate);
        return R.ok()
                .put("list", pg.getRecords())
                .put("total", pg.getTotal())
                .put("pageNum", pg.getCurrent())
                .put("pageSize", pg.getSize())
                .put("startTime", OrderListTimeRangeResolver.format(range.getStart()))
                .put("endTime", OrderListTimeRangeResolver.format(range.getEnd()));
    }

    /**
     * 单条详情：订单主表 + 配送扩展。
     */
    @GetMapping("/delivery/detail")
    public R deliveryDetail(@RequestParam Integer orderId) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Order o = orderService.getById(orderId);
        if (o == null) {
            return R.error("订单不存在");
        }
        if (sid != null && o.getShop_id() != null && !sid.equals(o.getShop_id())) {
            return R.error(4003, "订单不属于当前门店");
        }
        if (!"外卖".equals(o.getDineInOrTakeOut())) {
            return R.error("非外卖订单");
        }
        TakeoutDelivery d = takeoutDeliveryService.getByOrderId(orderId);
        takeoutDeliveryService.enrichOrder(o);
        return R.ok().put("order", o).put("delivery", d);
    }

    /**
     * 骑手实时定位与 ETA（真省钱）；远端订单失效时返回可重发提示。
     */
    @GetMapping("/delivery/tracking")
    public R deliveryTracking(@RequestParam Integer orderId) {
        if (orderId == null) {
            return R.error("orderId 不能为空");
        }
        try {
            Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
            requireWaimaiOrder(orderId, sid);
            ZsqRiderTrackingResponse tracking = takeoutZsqIntegrationService.getTrackingForOrder(orderId);
            Order o = orderService.getById(orderId);
            TakeoutDelivery d = takeoutDeliveryService.getByOrderId(orderId);
            if (o != null) {
                takeoutDeliveryService.enrichOrder(o);
            }
            return R.ok().put("tracking", tracking).put("order", o).put("delivery", d);
        } catch (ZsqRemoteOrderMissingException e) {
            Order o = orderService.getById(orderId);
            TakeoutDelivery d = takeoutDeliveryService.getByOrderId(orderId);
            if (o != null) {
                takeoutDeliveryService.enrichOrder(o);
            }
            return R.error(4091, e.getMessage())
                    .put("canRedispatch", true)
                    .put("redispatchUrl", "/admin/takeout/delivery/zsq/redispatch")
                    .put("missingOpenOrderId", e.getMissingOpenOrderId())
                    .put("order", o)
                    .put("delivery", d);
        } catch (IllegalArgumentException | IllegalStateException e) {
            return R.error(e.getMessage());
        } catch (Exception e) {
            return R.error("获取配送追踪失败：" + e.getMessage());
        }
    }

    /**
     * 更新履约状态：accepted / delivering / completed（或 cancelled，由运营慎用）。
     */
    @PostMapping("/delivery/status")
    @AuditLog(module = "takeout", action = "admin_takeout_delivery_status")
    public R updateStatus(@RequestBody Map<String, Object> body) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (body == null || body.get("orderId") == null) {
            return R.error("orderId 不能为空");
        }
        int orderId;
        try {
            orderId = Integer.parseInt(body.get("orderId").toString().trim());
        } catch (Exception e) {
            return R.error("orderId 无效");
        }
        String status = body.get("dispatch_status") != null ? body.get("dispatch_status").toString().trim() : null;
        if (!StringUtils.hasText(status)) {
            return R.error("dispatch_status 不能为空");
        }
        String statusNorm = status.toLowerCase();
        if ("cancelled".equals(statusNorm)) {
            if (!takeoutDeliveryService.markDeliveryCancelled(orderId, sid, "运营取消配送")) {
                return R.error("更新失败（订单不存在、非外卖或门店不一致）");
            }
            try {
                takeoutZsqIntegrationService.cancelZsqForOrder(orderId, "运营取消配送", false);
            } catch (Exception ex) {
                // 本地已取消，真省钱远端失败不阻断
            }
            TakeoutDelivery d = takeoutDeliveryService.getByOrderId(orderId);
            if (d != null) {
                TakeoutZsqDispatchRecovery.finalizeOperatorCancel(d);
                takeoutDeliveryService.updateById(d);
            }
            return okWithOrderAndDelivery(orderId, d);
        }
        if (!takeoutDeliveryService.updateDispatchStatus(orderId, status, sid)) {
            return R.error("更新失败（订单不存在、非外卖或门店不一致）");
        }
        if ("accepted".equals(statusNorm)) {
            eventPublisher.publishEvent(new TakeoutOrderAcceptedEvent(orderId));
        }
        return okWithOrderAndDelivery(orderId);
    }

    /**
     * 向真省钱发起配送（手动）。
     */
    @PostMapping("/delivery/zsq/dispatch")
    @AuditLog(module = "takeout", action = "admin_takeout_zsq_dispatch")
    public R zsqDispatch(@RequestBody Map<String, Object> body) {
        try {
            Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
            int orderId = parseOrderId(body);
            Order o = requireWaimaiOrder(orderId, sid);
            TakeoutDelivery d = takeoutZsqIntegrationService.dispatchToZsq(o.getId(), false);
            return okWithOrderAndDelivery(o.getId(), d);
        } catch (ZsqApiException e) {
            return R.error(e.getMessage());
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 真省钱配送异常后在原 open 订单上重叫骑手；仅远端订单不存在时重新创单。
     */
    @PostMapping("/delivery/zsq/redispatch")
    @AuditLog(module = "takeout", action = "admin_takeout_zsq_redispatch")
    public R zsqRedispatch(@RequestBody Map<String, Object> body) {
        try {
            Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
            int orderId = parseOrderId(body);
            Order o = requireWaimaiOrder(orderId, sid);
            TakeoutDelivery d = takeoutZsqIntegrationService.dispatchToZsq(o.getId(), true);
            return okWithOrderAndDelivery(o.getId(), d);
        } catch (ZsqApiException e) {
            return R.error(e.getMessage());
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 从真省钱同步骑手定位与履约状态。
     */
    @PostMapping("/delivery/zsq/sync")
    @AuditLog(module = "takeout", action = "admin_takeout_zsq_sync")
    public R zsqSync(@RequestBody Map<String, Object> body) {
        try {
            Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
            int orderId = parseOrderId(body);
            requireWaimaiOrder(orderId, sid);
            TakeoutDelivery d = takeoutZsqIntegrationService.syncFromZsq(orderId);
            return okWithOrderAndDelivery(orderId, d);
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    private static int parseOrderId(Map<String, Object> body) {
        if (body == null || body.get("orderId") == null) {
            throw new IllegalArgumentException("orderId 不能为空");
        }
        return Integer.parseInt(body.get("orderId").toString().trim());
    }

    private Order requireWaimaiOrder(int orderId, Integer sid) {
        Order o = orderService.getById(orderId);
        if (o == null) {
            throw new IllegalArgumentException("订单不存在");
        }
        if (sid != null && o.getShop_id() != null && !sid.equals(o.getShop_id())) {
            throw new IllegalArgumentException("订单不属于当前门店");
        }
        if (!"外卖".equals(o.getDineInOrTakeOut())) {
            throw new IllegalArgumentException("非外卖订单");
        }
        return o;
    }

    /** 返回带 takeout_dispatch_status 的 order 与最新 delivery，避免前端仍显示旧状态 */
    private R okWithOrderAndDelivery(int orderId) {
        TakeoutDelivery d = takeoutDeliveryService.getByOrderId(orderId);
        return okWithOrderAndDelivery(orderId, d);
    }

    private R okWithOrderAndDelivery(int orderId, TakeoutDelivery delivery) {
        Order o = orderService.getById(orderId);
        if (o != null) {
            takeoutDeliveryService.enrichOrder(o);
        }
        if (delivery == null) {
            delivery = takeoutDeliveryService.getByOrderId(orderId);
        }
        return R.ok().put("order", o).put("delivery", delivery);
    }
}
