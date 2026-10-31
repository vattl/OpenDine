# C002: 飞鹅云打印模块完善与统一调度系统接入

- **Mode**: EXTEND & RESTRUCTURE
- **Date**: 2026-08-30
- **Status**: COMPLETED

## 概述

完善飞鹅云打印（Feieyun）开放平台 API 接入，补齐打印机生命周期与队列管理接口，并将飞鹅云打印无缝接入统一打印调度系统（`PrintDispatcherService`），支持设备独立凭据认证与多级凭据回退。

## 主要变更

### 1. IFeieyunService 接口扩展与实现
- 新增 `deletePrinter(String snList)`：调用 `Open_printerDelList` 接口从开发者账户批量解绑打印机。
- 新增 `editPrinter(String sn, String name)`：调用 `Open_printerEdit` 接口修改打印机备注名称。
- 新增 `clearPrintQueue(String sn)`：调用 `Open_delPrinterSqs` 接口清空指定打印机待打印队列。
- 新增 `printWithCredential(...)` / `queryPrinterStatusWithCredential(...)`：支持传入设备级独立凭据（`apiUrl`, `user`, `ukey`）直接调用飞鹅平台，摆脱对全局或单一门店配置的强绑定。

### 2. 统一调度系统集成 (PrintDispatcherServiceImpl)
- 调度器与重打逻辑中统一通过 `executeCloudPrint` 分发云打印任务。
- 凭据解析优先级：`t_printing_device.connection_json` 中的设备级凭据优先 -> 门店历史配置 -> 全局配置兜底。

### 3. 设备管理与生命周期同步 (PrintingService)
- 新增云打印机时自动异步调用 `addPrinter` 绑定至飞鹅开放平台。
- 删除云打印机时自动异步调用 `deletePrinter` 从飞鹅开放平台解绑。
- 状态探活 `probeDeviceStatus` 与打印测试 `createTestJob` 全面支持设备级独立凭据。
- 新增 `clearDeviceQueue` 清空云打印机待打印队列能力。

### 4. 管理后台接口与 OpenAPI 文档
- 新增 `POST /admin/printing/devices/{id}/clear-queue` 接口，支持后台运维一键清空云打印机排队小票。
- OpenAPI (`docs/openapi.yaml`) 同步补充新端点规范。

## 验证与测试

- **单元测试**:
  - `IFeieyunServiceImplTest`: 验证新增接口响应合法性解析
  - `PrintDispatcherServiceTest`: 验证设备级凭据调度分发与重打
  - `PrintingServiceTest`: 验证设备自动绑定/解绑与清空队列逻辑
  - 全量测试: 576 tests, 0 failures, 0 errors, 1 skipped.
- **构建输出**: `target/diancan-0.0.1-SNAPSHOT.jar` 构建成功。
