# Layer Impact Matrix & Contract Delta — WI-078

## Layer Impact Matrix

| Layer | Impact Status | Affected Components / Endpoints | Action / Handoff Strategy | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Database (`MySQL`)** | `IMPACTED` | `V053__unified_realtime_notification_channel.sql` (`t_realtime_notification`, `t_shop_notification_config`, `t_api_permission`) | Flyway/SQL migration in same Work Item | `VERIFIED` |
| **Backend Server (`Spring Boot`)** | `IMPACTED` | `/ws/v1/notify`, `/cashier/notifications/sync`, `/cashier/notifications/ack`, `/api/v1/notifications/sync`, `/api/v1/notifications/ack`, `/admin/shop/notification-config`, `/config/subscribe-templates` | Direct implementation in `WI-078` + dual-publish bridges on `/ws/cashier-events` and `/ws/menu` | `VERIFIED` |
| **Cashier / POS Frontend** | `COMPATIBLE_WITH_HANDOFF` | Legacy `/ws/cashier-events` & `/ws/menu` preserved; new `/ws/v1/notify`, `/cashier/notifications/sync`, `/cashier/notifications/ack`, `/admin/shop/notification-config` ready for consumption | Non-breaking additive endpoints + explicit `API_CONSUMER_HANDOFF.md` | `VERIFIED` |
| **Mini Program Frontend** | `COMPATIBLE_WITH_HANDOFF` | Legacy `/ws/menu` preserved; `/config/subscribe-templates` adds `couponGranted` key while preserving `orderStatus`, `pickupNotice`, `tmplIds` | Non-breaking additive fields + explicit `API_CONSUMER_HANDOFF.md` | `VERIFIED` |
| **KDS Terminal** | `NOT_IMPACTED` | `/ws/kds`, `/ws/kds/v2` | Untouched | `VERIFIED` |

UNKNOWN count: 0

## Contract Delta Summary
- **Added WebSocket Endpoint**: `ws://<host>/ws/v1/notify`
- **Added REST Endpoints**:
  - `GET /admin/shop/notification-config`
  - `PUT /admin/shop/notification-config`
  - `GET /cashier/notifications/sync` (alias `GET /api/v1/notifications/sync`)
  - `POST /cashier/notifications/ack` (alias `POST /api/v1/notifications/ack`)
- **Extended REST Endpoint (Additive)**:
  - `GET /config/subscribe-templates`: added `templates.couponGranted` and `subscribeTemplateId3` when configured.
