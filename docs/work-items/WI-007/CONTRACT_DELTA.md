# Contract Delta — WI-007

## Before

- 分类排序写全局 `t_category.sorting`。
- 菜品排序的 `targetIndex` 实际位于当前店全部菜品的混合排序空间。

## After

- 两个接口均以拦截器解析的当前门店为唯一数据范围。
- 分类 `targetIndex` 是当前门店分类列表的 1-based 位置。
- 菜品 `targetIndex` 是当前门店、菜品生效分类内列表的 1-based 位置。
- 请求/响应字段、路径和 HTTP 方法不变。

## Compatibility

兼容字段层面；修正旧有未定义/错误排序语义。前端继续按当前展示数组下标 + 1 提交。

## Consumer Action

NONE。消费者本就必须携带门店上下文；不得传跨分类的全店绝对下标。

