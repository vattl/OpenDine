package com.lanf.controller.cashier;

import com.lanf.entity.R;
import com.lanf.kds.delivery.*;
import com.lanf.util.AdminShopRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

@RestController
@RequestMapping({"/cashier/kds", "/admin/cashier/kds", "/api/admin/cashier/kds"})
public class CashierKdsDeliveryController {
    private final CashierKdsLeaseService leaseService;
    private final CashierKdsDeliveryService deliveryService;

    public CashierKdsDeliveryController(CashierKdsLeaseService leaseService, CashierKdsDeliveryService deliveryService) {
        this.leaseService = leaseService; this.deliveryService = deliveryService;
    }

    @PostMapping({"/authority/lease", "/delivery/lease"})
    public ResponseEntity<R> lease(@RequestHeader("X-Cashier-Device-Code") String device,
                                   @RequestBody Map<String, Object> body, HttpServletRequest request) {
        return execute(() -> leaseService.lease(shop(request), device, body));
    }

    @GetMapping({"/delivery/bootstrap", "/bootstrap"})
    public ResponseEntity<R> bootstrap(@RequestHeader("X-Cashier-Device-Code") String device,
                                       @RequestHeader("X-Cashier-Authority-Epoch") long epoch,
                                       @RequestHeader("X-Cashier-Lease-Token") String token,
                                       @RequestParam(value="nextPageToken", required=false) String nextPageToken,
                                       @RequestParam(value="limit", defaultValue="100") int limit,
                                       HttpServletRequest request) {
        return execute(() -> deliveryService.bootstrap(shop(request), device, epoch, token, nextPageToken, limit));
    }

    @GetMapping({"/delivery/business-day/orders", "/business-day/orders"})
    public ResponseEntity<R> businessDayOrders(@RequestHeader("X-Cashier-Device-Code") String device,
                                                @RequestHeader("X-Cashier-Authority-Epoch") long epoch,
                                                @RequestHeader("X-Cashier-Lease-Token") String token,
                                                @RequestParam(value="cursor", required=false) String cursor,
                                                @RequestParam(value="limit", defaultValue="200") int limit,
                                                HttpServletRequest request) {
        return execute(() -> deliveryService.businessDayOrders(shop(request), device, epoch, token, cursor, limit));
    }

    @GetMapping("/delivery/business-day/orders/detail")
    public ResponseEntity<R> businessDayOrderDetails(@RequestHeader("X-Cashier-Device-Code") String device,
                                                     @RequestHeader("X-Cashier-Authority-Epoch") long epoch,
                                                     @RequestHeader("X-Cashier-Lease-Token") String token,
                                                     @RequestParam(value="cursor", required=false) String cursor,
                                                     @RequestParam(value="limit", defaultValue="200") int limit,
                                                     HttpServletRequest request) {
        return execute(() -> deliveryService.businessDayOrderDetails(shop(request), device, epoch, token, cursor, limit));
    }

    @GetMapping({"/delivery/events", "/events"})
    public ResponseEntity<R> events(@RequestHeader("X-Cashier-Device-Code") String device,
                                    @RequestHeader("X-Cashier-Authority-Epoch") long epoch,
                                    @RequestHeader("X-Cashier-Lease-Token") String token,
                                    @RequestParam(value="afterCursor", defaultValue="0") long afterCursor,
                                    @RequestParam(value="limit", defaultValue="200") int limit,
                                    HttpServletRequest request) {
        return execute(() -> deliveryService.events(shop(request), device, epoch, token, afterCursor, limit));
    }

    @GetMapping({"/orders/{orderId}/projection", "/delivery/orders/{orderId}/projection"})
    public ResponseEntity<R> projection(@PathVariable int orderId,
                                        @RequestHeader("X-Cashier-Device-Code") String device,
                                        @RequestHeader("X-Cashier-Authority-Epoch") long epoch,
                                        @RequestHeader("X-Cashier-Lease-Token") String token,
                                        HttpServletRequest request) {
        return execute(() -> deliveryService.projection(shop(request), orderId, device, epoch, token));
    }

    @PostMapping({"/delivery/ack", "/ack"})
    public ResponseEntity<R> ack(@RequestHeader("X-Cashier-Device-Code") String device,
                                 @RequestHeader("X-Cashier-Authority-Epoch") long epoch,
                                 @RequestHeader("X-Cashier-Lease-Token") String token,
                                 @RequestBody Map<String, Object> body, HttpServletRequest request) {
        Object raw = body == null ? null : body.get("throughCursor");
        long cursor;
        try { cursor = raw instanceof Number ? ((Number) raw).longValue() : Long.parseLong(String.valueOf(raw)); }
        catch (Exception ex) { return ResponseEntity.badRequest().body(R.error(4000, "throughCursor is required")); }
        final long through = cursor;
        return execute(() -> deliveryService.ack(shop(request), device, epoch, token, through));
    }

    @GetMapping({"/delivery/status", "/status"})
    public ResponseEntity<R> status(HttpServletRequest request) {
        return execute(() -> deliveryService.status(shop(request)));
    }

    private int shop(HttpServletRequest request) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) throw new CashierKdsDeliveryException(400, 4000, "X-Shop-Id is required");
        return shopId;
    }
    private ResponseEntity<R> execute(Action action) {
        try { return ResponseEntity.ok(R.ok().put("data", action.run())); }
        catch (CashierKdsDeliveryException ex) {
            return ResponseEntity.status(ex.getHttpStatus()).body(R.error(ex.getCode(), ex.getMessage()));
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(R.error(4000, ex.getMessage()));
        }
    }
    private interface Action { Map<String, Object> run(); }
}
