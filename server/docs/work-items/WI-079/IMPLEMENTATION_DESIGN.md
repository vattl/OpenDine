# Implementation Design — WI-079

## 1. C-Side User Authentication & Isolation

- **`WebAppConfigurer`**:
  - Add `"/api/v1/notifications/**"` to `EXCLUDE_PATHS` so `SysInterceptor` does not block C-side Mini Program requests that authenticate via `X-User-Token` rather than Admin `Authorization: Bearer`.
- **`NotificationChannelController`**:
  - Add `@GetMapping("/user/notifications/sync")` and `@PostMapping("/user/notifications/ack")` aliases.
  - Add `resolveAuthenticatedCUserOpenid(HttpServletRequest request, String suppliedOpenid)`:
    - Checks `UserIdentityInterceptor.ATTR_USER_OPENID` attribute and `X-User-Token` header (`JwtTokenService.parseToken` with `subject == "user"`).
    - If `X-User-Token` is present and invalid, throws `SecurityException` (`401`).
    - If `X-User-Token` is valid and `suppliedOpenid` is non-empty and differs from `authenticatedOpenid`, throws `AccessControlException` (`403`).
    - Returns `authenticatedOpenid` when present, or falls back to `suppliedOpenid` for legacy compatibility.
- **`UnifiedNotificationWebSocketHandler`**:
  - For `client_type = MINI_PROGRAM`, if `token` query parameter or `X-User-Token` header is present:
    - Parse token via `jwtTokenService.parseToken(token)`.
    - Require `"user".equals(claims.getSubject())` and non-empty `claims.getId()`.
    - If query param `openid` was also passed and does not match `claims.getId()`, reject handshake with `CloseStatus.POLICY_VIOLATION` (`1008`).
    - Bind session `openid = claims.getId().trim()`.

## 2. Expiring Coupon Watchdog (`COUPON_EXPIRING_SOON`, `P2`)

- **`UnifiedNotificationService.publishCouponExpiringSoon(UserCoupon userCoupon, Coupon coupon, long remainingMinutes)`**:
  - Deterministic `message_id = "ntf_coupon_exp_" + userCoupon.getId()`.
  - `target`: `scope = "USER"`, `openid = userCoupon.getUser_openid()`, `client_type = "MINI_PROGRAM"`.
  - `business_type = "COUPON"`, `event_type = "COUPON_EXPIRING_SOON"`, `priority = "P2"`, `require_ack = true`.
  - `display_strategy`: `ui_type = "BOTTOM_SNACKBAR"`, `sound = "NONE"`, `duration_ms = 6000L`, `action_text = "去使用"`, `action_route = "/pages/index/index"`.
  - Dispatches via `sessionRegistry.sendToUser(openid, null, envelope)`; if `sent <= 0`, triggers `wechatCouponSubscribePushService.sendCouponExpiringSubscribeMessage(...)`.
- **`CouponExpiringWatchdogScheduler`**:
  - `@Scheduled(fixedDelayString = "${notify.watchdog.coupon-expiring-interval-ms:300000}")`
  - Scans `t_user_coupon` with `status = 0` and `expire_time` between `(now, now + windowMinutes]`, deduplicates via `notificationService.existsByMessageId("ntf_coupon_exp_" + uc.getId())`, and publishes `COUPON_EXPIRING_SOON`.

## 3. Customer-Targeted Pickup Ready (`ORDER_READY_FOR_PICKUP`, `P0`) & Refund Alert (`REFUND_REQUESTED`, `P0`)

- **`UnifiedNotificationService.publishCustomerOrderPickupReady(Order order, String pickupCode)`**:
  - Deterministic `message_id = "ntf_user_pickup_" + order.getOrder_no()`.
  - `target`: `scope = "USER"`, `openid = order.getOpenid()`, `shop_id = order.getShop_id()`, `client_type = "MINI_PROGRAM"`.
  - `business_type = "ORDER"`, `event_type = "ORDER_READY_FOR_PICKUP"`, `priority = "P0"`, `require_ack = true`.
  - `display_strategy`: `ui_type = "TOP_BANNER_AND_VIBRATE"`, `sound = "VOICE_PICKUP_READY"`, `duration_ms = 10000L`, `action_text = "查看取餐码"`, `action_route = "/packageOther/order-details/details?order_no=" + order.getOrder_no()`.
  - Called from `KdsCustomerPickupNoticeService.notifyCustomerPickup` and `OrderController.notice` when `notice == 1`.
- **`UnifiedNotificationService.publishRefundRequested(Order order, Double refundAmount, String reason)`**:
  - `message_id = "ntf_refund_req_" + order.getOrder_no()`.
  - `target`: `scope = "SHOP"`, `shop_id = order.getShop_id()`, `client_type = "CASHIER"`.
  - `business_type = "ORDER"`, `event_type = "REFUND_REQUESTED"`, `priority = "P0"`, `require_ack = true`.
