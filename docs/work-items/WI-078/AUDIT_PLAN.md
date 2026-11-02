# Audit Plan — WI-078

Audit Plan Status: COMPLETE
Work Type: FEATURE
Risk Level: MEDIUM
UI Impact: NONE
Contract Impact: CONSUMER_ACTION
Security Impact: YES
Data / Migration Impact: YES
Reliability / Performance Impact: YES
Required Audit Tracks: CORE, THIRD_PARTY, ARCHITECTURE, CONTRACT, SECURITY, DATA_MIGRATION, RELIABILITY_PERFORMANCE
Audit Execution Status: PLANNED
Remediation Cycle: CLEAR
Open Findings: 0
Final Audit Decision: PENDING

## Rationale

Phase 1 of the Unified Realtime Message Channel (`/ws/v1/notify`) introduces:
1. New database tables (`t_realtime_notification`, `t_shop_notification_config`) and API permissions in `V053__unified_realtime_notification_channel.sql`.
2. New WebSocket endpoint `/ws/v1/notify` and REST endpoints (`/admin/shop/notification-config`, `/cashier/notifications/sync`, `/cashier/notifications/ack`, `/api/v1/notifications/sync`, `/api/v1/notifications/ack`).
3. Dynamic per-shop order preparation timeout watchdog (`OrderTimeoutWatchdogScheduler`), coupon grant real-time push + offline WeChat Subscribe Message fallback (`ICouponServiceImpl`, `WechatCouponSubscribePushService`), new order payment push (`PaymentSuccessHandler`), and dual-publish compatibility bridges (`CashierEventWebSocketHub`, `DishMenuPushService`).
Therefore, the mandatory audit tracks include `CORE`, `THIRD_PARTY`, `ARCHITECTURE`, `CONTRACT`, `SECURITY`, `DATA_MIGRATION`, and `RELIABILITY_PERFORMANCE`.
