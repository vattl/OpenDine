# KDS 营业日历史回填

采用请求的备选方案：新增 GET /cashier/kds/delivery/business-day/orders/detail。

Current → Target → Diff：bootstrap 只投递 READY 厨房投影，历史完成单无法通过此通道回填；新增独立分页历史读取，保持 bootstrap/events/ack 语义不变。复用营业时间范围、门店及租约校验，补充真实厨房进度、完成标记；取消优先于完成。禁止用结账状态推导厨房完成。

兼容性：旧 business-day/orders 返回订单/明细，不是仅返回时间窗口。新接口保留其响应字段，交易状态移至 transactionStatus，orderStatus 使用 active/completed/cancelled。尚未上传云端的行进度为 null；完成时间没有 off_time 时为 null。

修正：营业日分页统一按 ID 排序以匹配 ID 游标；当天闭店后保留当天营业窗口。

验证：CashierKdsDeliveryServiceTest 8 项通过，覆盖历史完成单、部分传菜进度、租约错误、门店隔离、窗口外订单排除、分页，以及无新增投递事件。H2 数据库测试，未进行线上部署或真实 MySQL 验证。

构建：执行 mvnw.cmd clean package -DskipTests，发布产物 target/diancan-0.0.1-SNAPSHOT.jar。

前端调用和合并约束见 docs/API.md 的 KDS 营业时段历史回填段落。
