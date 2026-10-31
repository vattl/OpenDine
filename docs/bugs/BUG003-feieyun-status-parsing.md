# BUG003 — 飞鹅云打印机状态解析未适配原生状态码 0/1/2

## 状态
- **Status**: FIXED
- **Severity**: MEDIUM
- **Component**: `PrintingService`
- **Discovered**: 2026-08-31
- **Resolved**: 2026-08-31

---

## 1. 现象 (Symptom)
- **探活端点**: `GET /admin/printing/devices/{id}/status`
- **问题现象**: 打印机实际处于离线状态时，接口仍返回 `ONLINE`，状态探活与真实设备状态不一致。

---

## 2. 根本原因 (Root Cause)
飞鹅云开放平台 `Open_queryPrinterStatus` 原生接口返回的状态数据可能为数字状态码（如 `{"data":"0"}` 代表离线、`{"data":"1"}` 代表正常在线、`{"data":"2"}` 代表异常在线），也可能为描述文本。此前代码：
1. 仅通过 `res.contains("离线")` 等中文字符串匹配，当接口返回 `"0"` 时无法命中离线分支；
2. 中文包含判定时，未先区分 `"在线，工作状态不正常"`，导致包含 `"在线"` 的异常设备被误判为 `ONLINE`。
3. 探活获得最新设备状态后，未同步刷新数据库 `t_printing_device.status`，导致列表接口仍显示旧状态。

---

## 3. 修复方案 (Fix Strategy)
1. **新增状态解析器 `parseFeieyunPrinterStatus`**：
   - 提取 JSON 中的 `data` 节点；
   - 严格映射飞鹅原生状态码：
     - `0` 或包含 `离线` → `online=false`, `status="OFFLINE"`, `paperStatus="UNKNOWN"`, `coverStatus="UNKNOWN"`；
     - `2` 或包含 `不正常`/`异常` → `online=true`, `status="ERROR"`, 根据细分文本判定 `OUT_OF_PAPER`/`OPEN`；
     - `缺纸` → `online=true`, `status="ERROR"`, `paperStatus="OUT_OF_PAPER"`；
     - `开盖` → `online=true`, `status="ERROR"`, `coverStatus="OPEN"`；
     - `1` 或包含 `正常`/`在线` → `online=true`, `status="ONLINE"`, `paperStatus="NORMAL"`, `coverStatus="CLOSED"`。
2. **状态自动同步持久化**：
   - 探活发现状态发生变化时，自动更新 `t_printing_device.status`。
3. **补充全面单测**：覆盖 `"0"`, `"1"`, `"2"`, `{"data":"0"}`, `{"data":"1"}`, `{"data":"2"}`, `缺纸`, `开盖` 等各类返回格式。
