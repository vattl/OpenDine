# Contract Delta — WI-017

`POST /cashier/payment/wechat/native/orders` 的字段、鉴权和状态码集合不变。并发创建同一订单时，后到请求会在短暂等待窗口内复用胜出请求的 `codeUrl` 并返回成功；只有胜出请求仍未产生可复用二维码时才返回 `40931`。
