# WI-001 Checklist

- [x] REQUEST / UNDERSTAND：确认需求为超过 5 秒后的长期手动回撤
- [x] DISCOVER：定位云端拒绝、客户端已有长期入口及代理边界
- [x] DESIGN：确定云端批次状态机为根修复点
- [x] RED：云端完成态回撤测试在原实现稳定失败
- [x] GREEN：实现 `done → ready_serve`
- [x] 文档：同步 `docs/openapi.yaml` 与 `docs/API.md`
- [x] 前端：长期入口定向 widget 测试通过
- [x] 后端：工作流、批次层与 bootstrap 定向测试共 11 项通过
- [x] 发布证据：`mvn clean package -DskipTests` 成功并生成 JAR
- [x] REVIEW / ACCEPT：复核差异、消费者、订单头恢复与验收项

