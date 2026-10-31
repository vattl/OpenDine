# WORK ITEM — WI-004

## Request

解决kds删除设备接口，目前只是删除token值，没有真正删除设备

## Type

BUGFIX / ENHANCEMENT / BACKEND

## State

DONE

## Requirement Contract

### Goal

1. 管理端删除 KDS 设备接口彻底物理删除 `t_kds_device` 数据库行，不再仅清空 token / 设为 enabled=0。
2. 级联清理设备关联表（`t_kds_device_workflow`、`t_kds_device_screen`、`t_kds_device_pairing_ticket`）。
3. 删除后立即发布凭据失效事件（`KdsDeviceCredentialChangedEvent`），确保多端（WebSocket、Token 缓存）即刻作废。
4. 接口兼容：现存前端 `admin_panel_flutter` 调用的 `POST /admin/kds/device/unbind` 保持兼容并实现真正物理删除；同时支持 `/admin/kds/device/delete` 别名，入参支持 `deviceCode`/`device_code` 与 `id`/`deviceId`。
5. 列表查询 `listByShop` 过滤 `enabled = 1`，防止历史软解绑残留数据回显。

### Current behavior

- `AdminKdsController.deviceUnbind` 调用 `deviceService.unbind(shopId, deviceCode)`。
- `KdsDeviceService.unbind` 仅将 `enabled` 设为 0、将 `device_token` 与 `token_hash` 设为 null，并未从 `t_kds_device` 表物理删除。
- `KdsDeviceService.listByShop` 查询 `t_kds_device` 时未过滤 `enabled = 1`，导致前端列表刷新后依然能查出已解绑设备，造成“无法删除设备”的现象。
- 未消费的 `t_kds_device_pairing_ticket` 记录未被级联清理。

### Target behavior

- `KdsDeviceService` 引入 `deleteDevice(int shopId, String deviceCode)` 与 `deleteDeviceById(int shopId, Long deviceId)`，从 `t_kds_device` 中物理删除记录。
- 级联删除 `t_kds_device_workflow`、`t_kds_device_screen` 以及未消费的 `t_kds_device_pairing_ticket`。
- 发布 `KdsDeviceCredentialChangedEvent`。
- `deviceService.unbind` 统一委托为物理删除逻辑。
- `deviceService.listByShop` 增加 `.eq("enabled", 1)` 过滤，确保老旧脏数据不回显。
- `AdminKdsController` 支持 `POST /admin/kds/device/unbind` 与 `POST/GET/DELETE /admin/kds/device/delete`，灵活支持各种入参格式。
- `ApiPermissionMapping` 增加对应权限配置。

### Acceptance criteria

- [x] `KdsDeviceService` 真正执行 `deviceMapper.deleteById` 物理删除设备记录。
- [x] 级联删除 `screenStore`、`workflowStore` 与配对票据。
- [x] 发布 `KdsDeviceCredentialChangedEvent`。
- [x] `AdminKdsController` 支持通过 `unbind` 或 `delete` 路由完成删除。
- [x] 单元测试验证物理删除及级联清理逻辑（全部通过）。
- [x] `docs/openapi.yaml`、`docs/API.md` 同步更新。
- [x] Maven 全量编译打包通过（`mvn clean package -DskipTests`）。
