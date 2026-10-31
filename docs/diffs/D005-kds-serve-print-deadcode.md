# D005 — KdsServePrintService 死代码清理

> 日期：2026-09-05 ｜ 级别：TRIVIAL（REMOVE） ｜ 状态：IMPLEMENTED

## 背景

D004 审计 KDS 划菜打印链路时发现：`KdsServePrintService.buildServeTicketContent`（旧版直连飞鹅组单逻辑）在改造走统一打印调度中心后无任何调用方，为遗留死代码；同时 `IFeieyunService` 等 import 已不再使用。

## Current → Target → Diff

| 元素 | 操作 | 说明 |
|---|---|---|
| `KdsServePrintService.buildServeTicketContent`（L297-325） | REMOVE | 全仓库无调用方（已核实）；旧版直连飞鹅组单逻辑，已由 `PrintDispatcherService` + 模板引擎取代 |
| `import com.lanf.service.IFeieyunService` | REMOVE | 未使用 |
| `import java.text.SimpleDateFormat` / `import java.util.Date` | REMOVE | 仅死方法使用 |
| `private static final String TIME_FORMAT` | REMOVE | 仅死方法使用 |

## 保留（UNCHANGED）

- `SPEC_MAPPER` / `JsonNode` / `Iterator`：仍被 `formatSpecInParens` / `collectSpecValues` 使用
- `StringUtils` / `PaymentDiningTypeUtil`：仍被 `tableLabel` / `modeLabel` / `isDineIn` 使用
- 鉴权、投递、重试、手动补打等全部活动路径不变

## 验证

- [x] 残留引用检查为空（buildServeTicketContent/IFeieyunService/SimpleDateFormat/TIME_FORMAT/Date）
- [x] `mvn compile` 通过（EXIT 0）
- [x] 无 API 端点增删改，openapi 无需变更
