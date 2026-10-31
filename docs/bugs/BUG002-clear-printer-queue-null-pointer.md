# BUG002 — 清空云打印机队列抛出 NPE (清空待打印队列失败: null)

## 状态
- **Status**: FIXED
- **Severity**: HIGH
- **Component**: `PrintingService`, `IFeieyunServiceImpl`, `AdminPrintingController`
- **Discovered**: 2026-08-31
- **Resolved**: 2026-08-31

---

## 1. 现象 (Symptom)
- **触发请求**: `POST /admin/printing/devices/1/clear-queue`
- **响应状态**: `500 PRINTING_CLEAR_QUEUE_FAILED`
- **错误报文**: `"清空待打印队列失败: null"`

---

## 2. 根本原因 (Root Cause)
1. **全局凭据回退缺陷**：
   `IFeieyunServiceImpl.clearPrintQueue(sn)` 内部直接调用 `resolveCredential(null)`，仅尝试从全局 `feieyunConfig` 中获取账号 `user` 和 `ukey`。
2. **设备级凭据未透传**：
   当用户在 `t_printing_device.connection_json` 中单独配置了 `user: "feie_printer@example.com"` 和 `ukey`，而全局 `application.yml` 中未配置 `feieyun.user`/`feieyun.ukey` 时，`resolveCredential(null)` 返回了 null 的 `user` 和 `ukey`。
3. **NPE 与异常信息缺失**：
   `sendRequest` 在构造 `new BasicNameValuePair("user", credential.user)` 或计算签名时，由于 `credential.user` 为 null 抛出 `NullPointerException`（`e.getMessage() == null`），导致上层捕获后拼接出 `"清空待打印队列失败: null"`。

---

## 3. 修复方案 (Fix Strategy)
1. **完善 IFeieyunService 独立凭据重载**：
   - 增加 `clearPrintQueueWithCredential(apiUrl, user, ukey, sn)`
   - 增加 `deletePrinterWithCredential(apiUrl, user, ukey, snList)`
   - 增加 `addPrinterWithCredential(apiUrl, user, ukey, snList)`
2. **强化 IFeieyunServiceImpl 参数校验**：
   - 在 `sendRequest` 中校验 `credential.user` 和 `credential.ukey`，为空时抛出明确的 `IOException("飞鹅云凭据缺失(user/ukey为空)，请检查设备连接配置")`，彻底杜绝 NPE。
3. **重构 PrintingService 设备级参数提取**：
   - 在 `clearDeviceQueue`、`deleteDevice`、`createDevice` 中全面提取 `device.connection_json` 中的 `user`、`ukey`、`apiUrl`，优先使用设备独立凭据。
   - 异常捕获中完善消息格式化，防止返回 `"null"`。
