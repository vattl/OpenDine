# API Consumer Handoff — WI-079 (Phase 2: Mini Program UnifiedMessageCenter SDK & UI Integration)

## 1. WebSocket Endpoint & C-Side Authentication

- **Endpoint**: `wss://<host>/ws/v1/notify?client_type=MINI_PROGRAM&shop_id=<shopId>&token=<X-User-Token>&openid=<openid>`
- **Dynamic Context Rebinding (on shop switch or login)**:
  ```json
  {
    "frame_type": "BIND_CONTEXT",
    "shop_id": 12,
    "openid": "oX9_user_openid",
    "user_token": "<X-User-Token>"
  }
  ```
- **Heartbeat**: Send `{"frame_type":"PING"}` every 25s; server replies `{"frame_type":"PONG","seq_id":108,"payload":{"server_head_seq_id":108}}`.

## 2. REST Incremental Sync & Read Acknowledgment

1. **`GET /user/notifications/sync`** (alias `GET /api/v1/notifications/sync`)
   - **Headers**: `X-User-Token: <user-jwt>`
   - **Query**: `last_seq_id=<localCursor>&shop_id=<shopId>&limit=50`
   - **Behavior**: Server verifies `X-User-Token`, automatically binds `openid` from the token (rejecting mismatched `openid` with `403`), and returns unread, non-expired `UnifiedMessageEnvelope` items (`COUPON_GRANTED`, `COUPON_EXPIRING_SOON`, `ORDER_READY_FOR_PICKUP`).
2. **`POST /user/notifications/ack`** (alias `POST /api/v1/notifications/ack`)
   - **Headers**: `X-User-Token: <user-jwt>`
   - **Body**: `{"message_ids": ["ntf_coupon_9001", "ntf_user_pickup_ORD123"]}`

## 3. Drop-In Mini Program `utils/unifiedMessageCenter.js` SDK

Replace `startMenuCatalogSocket` in `utils/menuCatalogSocket.js` (or wrap it) with `UnifiedMessageCenter`:
- Connects to `/ws/v1/notify?client_type=MINI_PROGRAM&shop_id=...&token=...`.
- Persists `last_seq_id` in `uni.getStorageSync('unified_notify_last_seq_id')`.
- Deduplicates via an LRU `seenMessageIds` set (`capacity = 200`).
- **800ms Aggregation Window (`aggregation_key = "COUPON_GRANTED"`)**: Buffers consecutive `COUPON_GRANTED` events arriving within `800ms` and merges them into a single batch modal (`grant_count = N`).
- **Context Suppression on Checkout Page**: Checks `getCurrentPages()` — when the active route is `packageOther/confirm-order/confirm-order`, downgrades `COUPON_GRANTED` modal into the top non-blocking capsule banner (`"🎉 新到账 N 张优惠券可用，点击重选优惠"`).
- **Backward-Compatible Menu/Business Bridge**: Routes `DISH_CATALOG_CHANGED` and `SHOP_BUSINESS_CHANGED` directly to existing `onRefetchMenu` and `onBusinessChanged` callbacks so all existing pages work without modification.
