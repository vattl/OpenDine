# Test Report — WI-079

## Test Summary

- **Work Item**: `WI-079` (Unified Realtime Notification Channel Phase 2)
- **Status**: `PASS`
- **Test Classes**: `com.lanf.realtime.UnifiedNotificationPhase2Test`, `com.lanf.realtime.UnifiedNotificationChannelTest`
- **Tests Run**: 8, Failures: 0, Errors: 0, Skipped: 0

## Scenario Matrix Verification

| Scenario ID | Test Method | Result | Evidence |
|---|---|---|---|
| `S2-01` | `cSideUserTokenAuthAndAntiSpoofingShouldBeEnforcedOnRestAndWebSocket` | PASS | Verifies `X-User-Token` auto-binds `openid`, rejects spoofed `openid` with `403`, and rejects expired/invalid `X-User-Token` with `401` on `/user/notifications/*` and `/api/v1/notifications/*`. |
| `S2-02` | `cSideUserTokenAuthAndAntiSpoofingShouldBeEnforcedOnRestAndWebSocket` | PASS | Verifies `/ws/v1/notify` binds `openid = claims.getId()` from `token=<user-jwt>` and closes spoofed `openid` handshakes with `CloseStatus.POLICY_VIOLATION` (`1008`). |
| `S2-03` | `expiringCouponWatchdogShouldPushRealtimeAndFallbackToSubscribeWhenOffline` | PASS | Verifies `CouponExpiringWatchdogScheduler` emits `COUPON_EXPIRING_SOON` (`P2`, `BOTTOM_SNACKBAR`) over WebSocket when online, falls back to `WechatCouponSubscribePushService.sendCouponExpiringSubscribeMessage` when offline, and deduplicates on subsequent scans. |
| `S2-04` | `customerPickupReadyAndRefundRequestedShouldRouteToTargetRecipients` | PASS | Verifies `KdsCustomerPickupNoticeService.notifyCustomerPickup` emits `ORDER_READY_FOR_PICKUP` (`P0`, `target.scope = USER`, `openid`) to the ordering customer's Mini Program session. |
| `S2-05` | `customerPickupReadyAndRefundRequestedShouldRouteToTargetRecipients` | PASS | Verifies `UnifiedNotificationService.publishRefundRequested` emits `REFUND_REQUESTED` (`P0`, `PERSISTENT_ALERT_BANNER`) exclusively to the shop's `CASHIER` terminals. |
