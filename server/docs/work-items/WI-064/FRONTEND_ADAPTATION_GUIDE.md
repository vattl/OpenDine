# Frontend Adaptation Guide — WI-064

## Affected Actions
- 加菜：`POST /order/addDishes`、`POST /cashier/order/addDishes`
- 退菜：`POST /cashier/order/refundDish`
- 改价/赠送：`POST /cashier/order/updatePrice`
- 优惠：`POST /cashier/order/discount`

## Required Client Changes
1. 订单模型增加可空整数 `revision`，从订单详情/列表和每次成功写响应更新。
2. 发起上述动作时发送 `expectedVersion: order.revision`；统一使用 camelCase，不同时发送别名。
3. 成功后立即用响应 `revision` 覆盖内存、缓存和当前页面订单版本。
4. HTTP 409 且 `error_code == ORDER_VERSION_CONFLICT` 时：停止重试，关闭提交 loading，刷新订单与桌台快照，提示“订单已被其他终端修改，请确认后重试”。
5. 不得把最新 revision 自动套入原退菜数量、原改价、原优惠或原审批动作并静默重放。

## Flutter-style Flow
```dart
final response = await api.post(path, body: {
  ...payload,
  if (order.revision != null) 'expectedVersion': order.revision,
});
order = order.copyWith(revision: response.data['revision']);
```

冲突分支：
```dart
if (e.statusCode == 409 && e.data['error_code'] == 'ORDER_VERSION_CONFLICT') {
  await refreshOrderAndTable();
  showOrderChangedDialog();
  return; // 禁止自动重放旧动作
}
```

## Rollout
- 后端字段可选，因此可先部署后端，再灰度前端。
- 监控 409 数量与涉及动作；确认主要客户端均携带版本后，后续 Work Item 再评估是否转为强制字段。
