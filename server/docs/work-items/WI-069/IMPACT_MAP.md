# Impact Map — WI-069

## Authoritative Owner

- Mapper 注册入口：`com.lanf.Application` 的 `@MapperScan`。
- 受影响包：`com.lanf.ai.mapper`。

## Layer Coverage

| Layer | Impact | Evidence |
|---|---|---|
| Bootstrap/config | AFFECTED | 显式扫描清单遗漏 AI 包 |
| AI services | AFFECTED | 多个服务依赖 AI Mapper |
| API contract | VERIFIED_UNAFFECTED | 无端点或请求响应变化 |
| Database schema | VERIFIED_UNAFFECTED | 无迁移 |
| UI | VERIFIED_UNAFFECTED | 后端启动修复 |
| Security | VERIFIED_UNAFFECTED | 不改变权限或数据范围 |
| Tests/build | AFFECTED | 新增配置回归测试、打包和启动冒烟 |

UNKNOWN count: 0
