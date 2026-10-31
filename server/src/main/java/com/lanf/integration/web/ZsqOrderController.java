package com.lanf.integration.web;

import com.lanf.config.ZsqSystemSettings;
import com.lanf.integration.remote.dto.ZsqAddressTip;
import com.lanf.integration.remote.dto.ZsqCreateOrderResult;
import com.lanf.integration.remote.dto.ZsqShopAddress;
import com.lanf.integration.service.ZsqDeliveryService;
import com.lanf.integration.service.ZsqOrderService;
import com.lanf.integration.web.dto.ApiResult;
import com.lanf.integration.web.dto.CreateTakeawayDispatchRequest;
import com.lanf.integration.web.dto.CreateTakeawayOrderRequest;
import com.lanf.integration.web.dto.ZsqRiderTrackingResponse;
import com.lanf.integration.web.dto.ZsqTakeawayDispatchResult;
import javax.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * 你方服务器：外卖订单相关接口。
 */
@RestController
@RequestMapping("/api/zsq/orders")
public class ZsqOrderController {

    private final ZsqOrderService orderService;
    private final ZsqDeliveryService deliveryService;
    private final ZsqSystemSettings zsqSystemSettings;

    public ZsqOrderController(ZsqOrderService orderService, ZsqDeliveryService deliveryService,
                              ZsqSystemSettings zsqSystemSettings) {
        this.orderService = orderService;
        this.deliveryService = deliveryService;
        this.zsqSystemSettings = zsqSystemSettings;
    }

    /**
     * 发单店铺列表。
     */
    @GetMapping("/shops")
    public ApiResult<List<ZsqShopAddress>> shops(
            @RequestHeader("Authorization") String authorization) {
        return ApiResult.ok(orderService.listShops(authorization));
    }

    /**
     * 收货地址联想（高德 input-tips）。
     */
    @GetMapping("/address/tips")
    public ApiResult<List<ZsqAddressTip>> addressTips(
            @RequestHeader("Authorization") String authorization,
            @RequestParam String city,
            @RequestParam String keywords) {
        return ApiResult.ok(orderService.addressTips(authorization, city, keywords));
    }

    /**
     * 创建外卖订单（需 Header Authorization）。
     */
    @PostMapping("/takeaway")
    public ApiResult<ZsqCreateOrderResult> createTakeaway(
            @RequestHeader("Authorization") String authorization,
            @Valid @RequestBody CreateTakeawayOrderRequest request) {
        return ApiResult.ok(orderService.createTakeawayOrder(authorization, request));
    }

    /**
     * 使用 application.yml 配置的 zsq 账号创建订单（无需传 Authorization）。
     */
    @PostMapping("/takeaway/auto")
    public ApiResult<ZsqCreateOrderResult> createTakeawayAuto(
            @Valid @RequestBody CreateTakeawayOrderRequest request) {
        throw new org.springframework.web.server.ResponseStatusException(
                org.springframework.http.HttpStatus.GONE, "配置账号代理接口已停用，请使用管理端配送接口");
    }

    /**
     * 创建外卖订单并立即发起配送（保存并发单，需 Authorization）。
     */
    @PostMapping("/takeaway/dispatch")
    public ApiResult<ZsqTakeawayDispatchResult> createTakeawayAndDispatch(
            @RequestHeader("Authorization") String authorization,
            @Valid @RequestBody CreateTakeawayDispatchRequest request) {
        return ApiResult.ok(deliveryService.createTakeawayAndDispatch(authorization, request));
    }

    /**
     * 使用 yml 账号创建订单并发配送。
     */
    @PostMapping("/takeaway/dispatch/auto")
    public ApiResult<ZsqTakeawayDispatchResult> createTakeawayAndDispatchAuto(
            @Valid @RequestBody CreateTakeawayDispatchRequest request) {
        throw new org.springframework.web.server.ResponseStatusException(
                org.springframework.http.HttpStatus.GONE, "配置账号代理接口已停用，请使用管理端配送接口");
    }

    /**
     * 骑手实时定位与 ETA（距商家/距用户预计分钟数）。
     */
    @GetMapping("/{openOrderId}/tracking")
    public ApiResult<ZsqRiderTrackingResponse> riderTracking(
            @RequestHeader("Authorization") String authorization,
            @PathVariable long openOrderId) {
        return ApiResult.ok(deliveryService.getRiderTracking(authorization, openOrderId));
    }

    /**
     * 骑手追踪（yml 账号代登录）。
     */
    @GetMapping("/{openOrderId}/tracking/auto")
    public ApiResult<ZsqRiderTrackingResponse> riderTrackingAuto(@PathVariable long openOrderId) {
        throw new org.springframework.web.server.ResponseStatusException(
                org.springframework.http.HttpStatus.GONE, "配置账号代理接口已停用，请使用管理端配送接口");
    }
}
