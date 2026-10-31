# D023 getUserInfo 数据返回重构：默认轻量，聚合按需

* 日期：2026-09-08
* 状态：**IMPLEMENTED（代码）**
* 类型：接口契约优化（响应重构）
* 关联：D020（预聚合 JOIN+索引）、D022（合并 pay/lt）

## 0. 决策（用户原话）

> 按 A 方案执行。

## 1. 方案要点

默认请求（只分页/基础过滤）**不再做任何聚合计算**：只查 t_user 基础字段 + 分页，毫秒级返回；统计字段按需开启。

### 1.1 请求契约
- 新增 `includeStats`（默认 **false**）
- **隐式升级**：请求携带 `minAmount` / `maxAmount` / `amountSort` 任一参数 → 自动按 `includeStats=true` 处理（功能依赖消费聚合，不报错不忽略）

### 1.2 响应契约（字段名不变，防前端失效）
- `includeStats=false`：`user` = 14 个 t_user 基础字段；4 个聚合字段**保留 key、值为 null**
- `includeStats=true`：现状不变（含 4 个聚合字段，D022 合并后的 SQL）

### 1.3 实现
- `UserMapper.xml` 新增 `pageUserListLight`（SELECT t_user 字段 + `NULL AS` 四统计字段）+ `countUserListLight`（纯 t_user COUNT）+ `userListLightWhere`（query/phone/userType/注册时间，无金额过滤）
- `UserMapper.java`：新增两方法声明
- `IUserServiceImpl.pageUserListWithStats`：按 `params.includeStats` 分流（true→全量，false→轻量）
- `AdminOrderController.getUserInfo`：解析 `includeStats`（兼容 `withStats` 别名），隐式升级后写入 params

## 2. 行为对照

| 请求 | 返回 | 耗时 |
|---|---|---|
| 不传 includeStats（默认） | 14 基础字段 + 4 个 null 统计字段 | **几十 ms**（无聚合） |
| includeStats=true | 全部 18 字段（聚合） | 取决于索引（D020 索引未建则慢） |
| 带 minAmount/maxAmount/amountSort | 自动全量（同 includeStats=true） | 同上 |

## 3. 校验

- XML well-formed 校验通过；`mvnw compile` 通过（MyBatis XML 启动期解析，需联调以真实请求验证）
- 未跑单测（该接口无既有测试）；建议联调时分别验证轻量/全量/隐式升级三条路径

## 4. 风险与说明

- 前端若**不带** includeStats 直接读聚合字段，会拿到 null（此前为真实值）——需前端在「会员详情/看板」等场景显式传 `includeStats=true`；首屏列表不受影响
- openapi 已同步（v1.2.235 未打，随工作区并行线）
- D020 索引迁移 `db_migration_user_list_perf.sql` 仍建议执行（全量分支收益）
