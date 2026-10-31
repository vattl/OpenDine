# Impact Map — WI-079

## Audit Routing Inputs

Risk Level: MEDIUM
UI Impact: NONE
Contract Impact: CONSUMER_ACTION
Security Impact: YES
Data / Migration Impact: NO
Reliability / Performance Impact: YES

## Affected Surfaces

- **Configuration & Interceptors**:
  - `src/main/java/com/lanf/config/WebAppConfigurer.java`
  - `src/main/java/com/lanf/config/ApiPermissionMapping.java`
- **Controllers**:
  - `src/main/java/com/lanf/controller/NotificationChannelController.java`
  - `src/main/java/com/lanf/controller/AppConfigController.java`
  - `src/main/java/com/lanf/controller/OrderController.java`
- **Realtime & Notification Services**:
  - `src/main/java/com/lanf/realtime/UnifiedNotificationWebSocketHandler.java`
  - `src/main/java/com/lanf/notify/service/UnifiedNotificationService.java`
  - `src/main/java/com/lanf/notify/service/WechatCouponSubscribePushService.java`
  - `src/main/java/com/lanf/notify/service/CouponExpiringWatchdogScheduler.java`
  - `src/main/java/com/lanf/kds/service/KdsCustomerPickupNoticeService.java`
- **API Documentation & Handoff**:
  - `docs/openapi.yaml`
  - `docs/API.md`
  - `docs/work-items/WI-079/prototypes/miniprogram_unified_notify_prototype.html`
- **Tests**:
  - `src/test/java/com/lanf/realtime/UnifiedNotificationPhase2Test.java`

## Invariants Preserved

- **KDS Cloud Authority (`docs/KDS_ARCHITECTURE.md`)**: KDS WebSocket (`/ws/kds`, `/ws/kds/v2`) and KDS authority are untouched.
- **C-Side Identity Isolation**: Mini Program users authenticating via `X-User-Token` can only sync/ack or subscribe to their own `openid` notifications; cross-user `openid` spoofing is rejected with `403`.
- **Backward Compatibility**: `/ws/menu` and `/ws/cashier-events` remain fully operational during and after Phase 2 migration.
