# Work Item — WI-079: Unified Realtime Notification Channel (Phase 2: C-Side Mini Program Capabilities, User Token Auth, Expiring Coupon Watchdog, Targeted Pickup & Refund Alerts)

## Summary
Complete Phase 2 of the Unified Realtime Message Channel (`/ws/v1/notify`), enabling C-side Mini Program `X-User-Token` authentication and anti-spoofing isolation on REST (`/user/notifications/*`, `/api/v1/notifications/*`) and WebSocket (`/ws/v1/notify`), adding the expiring coupon watchdog (`COUPON_EXPIRING_SOON`, `P2`) with offline WeChat Subscribe Message fallback, adding customer-targeted pickup ready notifications (`ORDER_READY_FOR_PICKUP`, `P0`) and B-side refund request alerts (`REFUND_REQUESTED`, `P0`), and delivering the Mini Program HTML review prototype and `UnifiedMessageCenter` SDK.

## Type
FEATURE

## Risk Tier
STANDARD

## Scope
1. **C-Side Mini Program Authentication & User Isolation (`WebAppConfigurer.java`, `NotificationChannelController.java`, `UnifiedNotificationWebSocketHandler.java`)**:
   - Exclude `/api/v1/notifications/**` from `SysInterceptor` in `WebAppConfigurer`.
   - Expose `/user/notifications/sync` (`GET`) and `/user/notifications/ack` (`POST`) aliases alongside `/api/v1/notifications/sync` and `/api/v1/notifications/ack`.
   - Enforce C-side `X-User-Token` (`subject = "user"`, `id = openid`) validation and anti-spoofing (`403` on mismatched `openid`, `401` on invalid token, auto-binding `openid` when omitted).
2. **Expiring Coupon Watchdog & Subscribe Push Fallback (`CouponExpiringWatchdogScheduler.java`, `UnifiedNotificationService.java`, `WechatCouponSubscribePushService.java`, `AppConfigController.java`)**:
   - Add `publishCouponExpiringSoon(UserCoupon, Coupon, long)` (`P2`, `BOTTOM_SNACKBAR`, `ntf_coupon_exp_{userCouponId}`).
   - Add `sendCouponExpiringSubscribeMessage` to `WechatCouponSubscribePushService` and `couponExpiring` template ID to `GET /config/subscribe-templates`.
   - Implement `CouponExpiringWatchdogScheduler` scanning unused coupons expiring within 2 hours with idempotent deduplication.
3. **Customer-Targeted Pickup Ready (`ORDER_READY_FOR_PICKUP`, `P0`) & Refund Request Alert (`REFUND_REQUESTED`, `P0`)**:
   - Add `publishCustomerOrderPickupReady(Order, String)` (`target.scope = USER`, `openid = order.getOpenid()`, `priority = P0`) and wire into `KdsCustomerPickupNoticeService.notifyCustomerPickup` and `OrderController.notice`.
   - Add `publishRefundRequested(Order, Double, String)` (`target.scope = SHOP`, `client_type = CASHIER`, `priority = P0`).
4. **Documentation, Prototype & Packaging**:
   - Synchronize `docs/openapi.yaml` and `docs/API.md`.
   - Deliver interactive HTML prototype (`docs/work-items/WI-079/prototypes/miniprogram_unified_notify_prototype.html`) and Mini Program `UnifiedMessageCenter` SDK.
   - Build runnable JAR via `.\mvnw.cmd clean package -DskipTests`.

## Out of Scope
- Modifying `/ws/kds` or `/ws/kds/v2` KDS business authority protocols.

## Tasks / Vertical Slices
- [ ] T01 Implement Phase 2 C-side notification capabilities, user token auth, expiring coupon watchdog, customer pickup & refund producers, and OpenAPI sync
