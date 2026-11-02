# Contract Delta — WI-013

- `POST /cashier/order/checkout`: 请求体支持可选 `force: boolean`（默认为 false）与现场授权字段。
- `POST /cashier/order/force-checkout`: 明确强制结账专用端点，要求具备 `admin:manage` 权限。
- `POST /admin/order/checkout`: 请求体支持可选 `force: boolean`。
- `POST /admin/order/force-checkout`: 管理后台强制结账端点，要求具备 `admin:manage` 权限。
