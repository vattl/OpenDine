# API Consumer Handoff — WI-002

## Interface

- `GET /kds/settings`
- `POST /kds/v2/commands`
- `POST /kds/v2/config`
- `POST /kds/device/login`（后续 PIN 安全迁移）

## Compatibility

ACTION_REQUIRED

## Before

- settings 可使用 query `shop_id`，响应含原始 `config` 和 `kds_pin`。
- KDS 设备命令入口接受 POS 加菜/整行退菜别名。
- KDS 设备可直接修改门店级 workflow 配置。
- 客户端可能预填和展示默认 PIN `123456`。

## After

- settings 必须使用设备 Token，只返回当前设备门店的非敏感字段。
- KDS 设备入口拒绝 POS 财务命令；POS 使用 `/cashier/order/*` 或受控 `/admin/order/commands`。
- `/kds/v2/config` 对设备身份固定返回 403；门店级配置改用 `/admin/kds/config/save`。
- 默认 PIN/自动绑定本轮尚未移除；其迁移必须先完成消费者兼容与门店 PIN 轮换。

## Consumer Impact

- `KDS_front/kds_app`：登录页移除 `123456` 预填；403 作为稳定权限拒绝处理。
- `KDS_front/kds_app`：不再从设备端提交门店级配置；相关入口迁往管理端或改为只读。
- `admin_panel_flutter`：设备页不再从 KDS settings 响应读取 PIN；改用管理员配置接口；支持未配置态。
- LAN proxy：继续原样转发状态码和 body，不生成本地替代结果。

## Required Frontend / Consumer Changes

1. 移除默认 PIN 展示和复制。
2. 管理员 PIN 读取/保存只走管理员 JWT 接口。
3. KDS 不再调用裸 `/kds/settings?shop_id=`。
4. POS 加菜/退菜只走正式 cashier/admin API。
5. 门店 KDS workflow 配置仅由管理端 JWT 流程修改。

## Type / Model Changes

KDS settings 响应不再承诺 `config.kds_pin`；消费者使用 `settings` 白名单。

## Request Construction

所有 settings 请求携带 `X-Kds-Device-Token`，不传其它门店 shop_id。

## Response Mapping / Display

401 提示重新登录；403 提示设备无操作权限；不得把二者加入业务命令 UNKNOWN 重试。

## Defaults / Fallbacks

不存在 PIN 默认值；未配置时明确阻止 PIN 登录并引导管理员设置。

## Rollout / Migration Order

1. 立即同步客户端 settings 响应映射、命令 403 和配置只读行为。
2. 验证直连云端与 LAN 代理一致。
3. 另立 PIN 迁移切片：先发布未配置态支持，再轮换默认 PIN，最后移除默认共享值。

## Verification Checklist

- [ ] consumer request updated
- [ ] consumer response mapping updated
- [ ] UI/state semantics updated if applicable
- [ ] old contract references removed or intentionally supported
- [ ] end-to-end flow verified

## Owner / Status

WI-002 / CONSUMER_PENDING

