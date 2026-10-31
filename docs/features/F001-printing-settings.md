# Feature Spec: F001-printing-settings

## 1. Metadata
- **Feature ID**: F001-printing-settings
- **Status**: COMPLETED
- **Created Date**: 2026-08-30
- **Author**: Antigravity

---

## 2. Background & Problem
根据系统设置后端协调文档 `backend_coordination_system_settings.md`（§2 及 §3 打印服务与设备管理接口详细规范），前端 Flutter 后台管理面板需要对打印设备进行全生命周期管理（设备列表、设备详情、新增设备、编辑设备、删除设备、出票测试、状态实时探活、打印规则与打印流水）。目前后端已有基础的 devices/rules/jobs 骨架，但缺少设备详情接口 `GET /admin/printing/devices/{id}`、设备删除接口 `DELETE /admin/printing/devices/{id}`（含规则引用拦截校验）、实时探活接口 `GET /admin/printing/devices/{id}/status`，以及新增/编辑时的 SN 唯一性校验与掩码密钥保留等细节。

---

## 3. Goals & User Stories
1. **设备卡片与详情**：支持管理员查看打印设备列表（含在线状态、商户、门店、连接方式），并能点击进入设备详情，查看脱敏后的凭据。
2. **设备创建与编辑**：支持输入名称、厂商、连接方式（CLOUD/LAN/USB/BLUETOOTH）、SN、IP、端口、纸张规格等；创建时校验 SN 唯一性；编辑时具备 `version` 乐观锁，且当传入掩码或空密钥时保留历史密文。
3. **安全删除**：删除设备前校验是否被生效中的出票规则（`t_printing_rule`）引用，若被引用则返回 400 `PRINT_DEVICE_IN_USE_BY_RULE` 并列出关联规则名称，阻止误删。
4. **测试出票与探活**：支持多种出票测试类型（标准小票、后厨单、切刀测试或自定义内容）；支持实时探活检测云端飞鹅或局域网打印机的健康状态（在线、缺纸、开盖等）。
5. **OpenAPI 文档同步**：完整同步更新 `docs/openapi.yaml`。

---

## 4. In Scope & Out of Scope
- **In Scope**:
  - `GET /admin/printing/devices`
  - `GET /admin/printing/devices/{id}`
  - `POST /admin/printing/devices`
  - `PUT /admin/printing/devices/{id}`
  - `DELETE /admin/printing/devices/{id}`
  - `POST /admin/printing/devices/{id}/test`
  - `GET /admin/printing/devices/{id}/status`
  - `GET/PUT /admin/printing/rules`
  - `GET /admin/printing/jobs`
  - OpenAPI 文档更新与单元测试
- **Out of Scope**:
  - 其它非打印设置模块（支付/库存/营销等在此次任务中忽略）

---

## 5. Technical Design & Acceptance Criteria
1. **Controller Layer (`AdminPrintingController`)**:
   - `GET /admin/printing/devices/{id}`: 返回单个设备详情（权限 `printing:view`）
   - `DELETE /admin/printing/devices/{id}`: 删除设备（权限 `printing:manage`）
   - `GET /admin/printing/devices/{id}/status`: 设备探活（权限 `printing:view`）
   - 保证响应中 `data` 与顶层字段的双重兼容性。
2. **Service Layer (`PrintingService`)**:
   - `getDeviceDetail(int shopId, long deviceId)`: 读取详情并脱敏。
   - `createDevice`: 支持扁平入参和 connection 对象，SN 重复校验（400 `PRINT_DEVICE_DUPLICATE_SN`）。
   - `updateDevice`: 乐观锁（409 `PRINTING_VERSION_CONFLICT`），`ukey` 掩码保留机制。
   - `deleteDevice(int shopId, long deviceId)`: 校验 `t_printing_rule` 引用（400 `PRINT_DEVICE_IN_USE_BY_RULE`）。
   - `probeDeviceStatus(int shopId, long deviceId)`: 探活云打印与网口设备。
   - `createTestJob`: 支持 `STANDARD_RECEIPT`, `KITCHEN_TICKET`, `CUTTER_TEST` 及自定义内容。
3. **Acceptance Criteria**:
   - 所有单测全部通过。
   - `docs/openapi.yaml` 完整记录所有打印接口。
