# Implementation Design — WI-065

## Root Fix / Owner
针对传统大模型配餐「胡乱捏造价格、数学加法错误、忽略忌口与过敏、擅自下单」的顽疾，在 Spring Boot 2.3 体系内引入**确定性约束规划引擎**（`LexicographicalMealSolver`），解耦大模型（意图识别与文案生成）与业务中枢（约束求解、分级校验、金额核算）。以云端 MySQL 结构化会话与草稿为状态权威，以整型「分」为金额基准。

## Core Components
1. **实体与 Mapper（`com.lanf.ai.entity`, `com.lanf.ai.mapper`）**：
   - 映射 V044 增量表，包含菜品食材画像、用餐会话、成员卡片、配餐方案、订单草稿。
2. **菜单适配器（`AiMenuAdapterService`）**：
   - 联查 `t_dish`, `t_dish_shop`, `t_dish_food_profile`，过滤售罄（`sold_out=1`）与下架（`onsale=0`）商品。
   - 提取真实售价（分）、规格变体、辣度选项、过敏原标记及可食克重。
   - 生成当前门店菜单的 SHA-256 版本哈希 `menu_version`。无数据时返回 `REQUIRES_MENU_DATA`。
3. **两阶段约束求解引擎（`LexicographicalMealSolver`）**：
   - **阶段一（硬约束满足性搜索）**：
     - 总价：$\sum (P_{i,v} \times x_{i,v}) + \text{Fees} \le \text{Budget}_{\text{fen}}$。
     - 库存：$x_{i,v} \le \text{Stock}_{i,v}$。
     - 忌辣：声明免辣成员所分得的菜品必须支持免辣制作（`non_spicy_available=1`），辣味分配量严格为 0。
     - 过敏原：排除含该过敏原或存在交叉接触风险的菜品。
   - **阶段二（多目标效用打分与排序）**：
     - 公平性（30%）、营养契合度（25%）、份量覆盖（20%）、品类多样性（15%）、预算效率（10%）。
     - 支持生成均衡优先、预算优先、吃饱优先候选解。
   - **阶段三（不可行协商与差额计算）**：
     - 若硬约束无解，计算满足保底份量所需的最小预算 $\text{MinFeasibleBudget}$，返回确切差额与可执行结构化放宽建议。
4. **会话与草稿服务（`DiningSessionService`, `OrderDraftService`）**：
   - 会话支持 `revision` 乐观锁并发保护，支持自然语言/结构化约束补丁增量应用。
   - 草稿支持 5 分钟 TTL，提交前执行 `validate`（核验 `menu_version` 一致性与实时库存）。
   - 最终确认下单时支持 `Idempotency-Key` 幂等防重，成功后转换为 `Order` 写入 `t_order` 并分发出餐工单。
5. **接口层与协议适配（`AiSmartDiningController`, `AiMcpController`）**：
   - REST 接口：`/api/v1/ai/*` 遵循统一的 `R.ok()` / `R.error()` 及细分错误码规范。
   - MCP 协议：支持 7 大标准工具，实现只读查询、状态机流转与安全写控制。

## KDS & Inventory Boundary
AI 配餐在方案与草稿阶段不预扣真实库存，避免恶意刷单导致锁库死锁。仅在用户明确确认调用正式落单（`/api/v1/ai/orders`）时，复用现有订单核心逻辑执行原子扣库与 `PaymentSuccessHandler` / KDS 厨房出餐流程，保持云端 KDS 唯一业务权威。

## Compatibility & Rollback
- 所有增量表为独立新建，不破坏现有表结构与字段。
- 外部小程序可选择性接入新 API 或继续沿用现有 `add_ai_cart` Tag。
- 遇紧急情况可随时下线 `/api/v1/ai/*` 入口，现有 POS 收银与扫码点餐完全不受影响。

## Verification Strategy
- 编写专项测试套件 `AiSmartDiningTestSuite`，覆盖 PRD 规定的 TC01~TC14：
  - TC01：6人/150元/2人不辣/健身/均衡基线求解；
  - TC02：动态追加「不吃牛肉」补丁与差额对比；
  - TC03：预算降为130元；
  - TC04：不支持免辣变体拦截；
  - TC05：缺少营养数据时降级标注；
  - TC06：过敏原安全排除；
  - TC07：售罄与调价拦截；
  - TC08：幂等下单防重；
  - TC10：不可行协商与最小预算计算。
- 执行 `python .ai/scripts/gate.py work --work-item docs/work-items/WI-065 --phase ready`；
- 执行 `mvnw.cmd clean package -DskipTests` 生成完整 runnable JAR。
