# 独立打包单打印任务

- [x] 后端 RED：`PACKING` 场景归一化、内置识别、显示名测试失败
- [x] 后端 RED：默认打包单 DSL 与模板元数据测试失败
- [x] 后端 RED：普通打印/KDS 附加打印仅为打包订单派发 `PACKING`
- [x] 后端 GREEN：完成场景、模板初始化、元数据与业务触发
- [x] 前端 RED：打包单模型、规则选项、模板筛选与设计器选项测试失败
- [x] 前端 GREEN：完成最小 UI 与 fallback DSL 适配
- [x] 文档：同步 OpenAPI 与 API.md 的 11 场景契约，并通过 YAML 解析
- [x] 验证：后端 65 个定向测试通过
- [x] 验证：Flutter 契约测试与模板页回归通过；定向 analyze 无编译错误（保留页面既有 warning/info）
- [x] 验证：`mvn clean package -DskipTests` 生成 JAR
- [x] 完成 Layer Impact Matrix 复核，所有层无 UNKNOWN
