# API Consumer Handoff — WI-017

## Consumer Impact

- 收银端无需修改请求或响应模型。
- 同一订单重复提交可能获得 `code=0`、`reused=true` 和相同 `codeUrl`；应按正常二维码展示。
- 超过服务端等待窗口仍可能收到 `40931`，此时应查询支付状态，不能新建另一笔收款。
- 客户端仍应在请求进行中禁用支付按钮，避免无意义的并发流量。

## Compatibility

BACKWARD_COMPATIBLE behavior repair; no required consumer release.
