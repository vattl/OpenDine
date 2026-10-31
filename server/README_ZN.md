# AI Development OS v4.0 — 统一工程工作流版（Unified Engineering Workflow）

面向 AI 编码代理（Claude Code、Codex、Cursor 等）的「仓库自有操作系统」。本文件为 v4.0 中文使用说明。

---

## 一、核心理念

> **一个工作项（Work Item）、一个生命周期、一条证据链。**

v4.0 是**工作流整合版**：完整保留 v3.6 的全部工程能力，但把编排方式从"多条平行命令流"重组为**一条贴近真实产品/软件团队的骨干生命周期**。专业能力（UI 设计、API 契约、数据库迁移、性能、可靠性、安全、工作树隔离、视觉保真）不再是并列的独立流程，而是这条生命周期内部的**轨道（track）/检查（check）**。

## 二、主生命周期（12 阶段）

```text
REQUEST（请求）
  ↓
UNDERSTAND（理解）
  ↓
DISCOVER（发现）
  ↓
DESIGN（设计）
  ↓
PLAN（计划）
  ↓
IMPLEMENT（实现）
  ↓
SELF_VERIFY（自验证）
  ↓
REVIEW（评审）
  ↓
ACCEPT（验收）
  ↓
INTEGRATE（集成）
  ↓
RELEASE（发布）
  ↓
MONITOR（监控）
```

这条生命周期是**权威的**。专业命令与规则插入其中运行，不再制造互不相干的平行流程。

## 三、版本演进一览

| 版本 | 主题 |
|---|---|
| v1 / v2 | 基础命令与规则框架 |
| v2.1 | 自适应轻量工作流（四档分级 + 5 条硬不变量） |
| v2.3 | 事务安全 Git 版（Interruption-Safe + Task Commit Gate） |
| v2.4 | 原型优先 UI（/ui、UI_RULES、DESIGN_SYSTEM_RULES） |
| v2.5 | 视觉保真（PROTOTYPE_TO_CODE_RULES、±容差体系） |
| v3.0 | 工程治理（/merge、/cleanup、/incident、validate.py） |
| v3.1 | 自动工作流隔离（/workstream、AUTO_ISOLATION_RULES） |
| v3.2 | 截图视觉验证（/ui-verify、SCREENSHOT_VISUAL_DIFF_RULES） |
| v3.4 | 能力感知修复与证据验证（/capability、/repair、/verify） |
| v3.5 | 跨层一致性守卫（/contract-verify、跨层链、Layer Impact Matrix） |
| v3.6 | 设计推理 + 重构优先 UI（REFINE/REFACTOR/REDESIGN、/ui-lock、/ui-implement、/ui-critique） |
| **v4.0** | **统一工程工作流（/work、Work Item 生命周期、Impact Map、纵向切片）** |

## 四、v4.0 解决的主要问题（v3.x 碎片化）

### 4.1 统一发现（Unified Discovery）

能力发现、消费者覆盖、跨层分析、API 契约差异、UI 语义影响、依赖影响、运行时风险——全部合并进**一张 Impact Map（影响地图）**，取代过去多张矩阵并立。

### 4.2 统一设计（Unified Design）

不再产出多份互相独立的计划，而是写**一份 Implementation Design（实现设计）**，内含后端、前端、UI、契约、数据、兼容性、迁移、运行时关注点与验证策略等分节。

### 4.3 纵向切片（Vertical Slicing）

计划应优先采用**端到端可验证的纵向切片**，而不是按层拆任务：

```text
推荐
T1: 配送方式从 UI → 请求 → 后端创建流程
T2: 编辑 + 重放 + 响应映射
T3: 列表/详情显示 + 回归

不推荐
T1: 控制器
T2: 服务层
T3: 前端
T4: UI
```

### 4.4 接口变更必须消费者交接（API Consumer Handoff）

任何影响消费者的后端 API 变更，要么在**同一工作项内**同步更新消费方，要么产出明确的 `API_CONSUMER_HANDOFF`（消费者交接文档），写明前端/其他消费方必须如何迁移。

> 后端单独完成 ≠ 整体完成；当必要消费方仍处于待办时，工作项不得标记完成。

### 4.5 UI 是设计轨道，不是独立宇宙

UI 受影响时，DESIGN 阶段打开既有 v3.6 UI 轨道：

```text
项目上下文 → 用户目标 → 信息架构 → 设计方法论 → 组件能力审计
→ 原型 → 批评 → 批准 → UI 锁定 → 生产翻译 → 视觉验证
```

UI 重构时**保留产品能力，不保留旧外观**。

### 4.6 基于证据的完成（Evidence-Based Completion）

测试通过 ≠ 验收通过。只有**重读原始需求契约、每条验收标准都有证据支撑**时，工作项才算验收通过。

### 4.7 状态简化（State Simplification）

活跃工作的权威真相应能从以下恢复：

1. **工作项工件（Work Item artifact）**
2. **`.ai-runtime` 注册表/日志**（实时中断状态）
3. **Git 状态/差异/提交**（实现事实）

旧的 `PROJECT_STATE`、`SESSION_CHECKPOINT`、`EXECUTION_CURSOR` 仅为兼容保留，不得成为竞争性真相源。

## 五、v4.0 新增内容

### 5.1 新默认入口：`/work`

`/work` 是统一工作项入口，12 阶段一条龙：

| 阶段 | 要点 |
|---|---|
| 1. REQUEST | 创建/复用工作项 ID，记录原始请求 |
| 2. UNDERSTAND | 定义 目标/当前/目标态/必须保留/验收标准/开放问题 |
| 3. DISCOVER | 探查仓库现实，构建一张 Impact Map（归属者/消费者/跨层传播/契约/风险） |
| 4. DESIGN | 产出一份 Implementation Design，必要时打开专业轨道 |
| 5. PLAN | 拆成带完成定义（DoD）的端到端纵向切片 |
| 6. IMPLEMENT | 逐切片执行，检查点保存进度，保持任务级 Git 纪律 |
| 7. SELF_VERIFY | 依据 Impact Map 自动选择检查 |
| 8. REVIEW | 独立工程评审（遗漏/回归/捷径） |
| 9. ACCEPT | 重读原始验收标准并要求证据 |
| 10-12. INTEGRATE / RELEASE / MONITOR | 仅在适当且项目政策允许时推进 |

**关键路由规则：**
- 反复局部补丁暴露共享能力问题时 → **自动升级为能力修复**
- API 契约变更 → 更新消费方或产出 API_CONSUMER_HANDOFF
- UI 受实质影响 → 走 UI 设计轨道，不得事后补 UI
- 存在重叠的活动工作项 → 自动隔离

### 5.2 命令体系变化

| 变化 | 说明 |
|---|---|
| `/feature` `/change` `/bug` `/repair` | 成为 `/work` 的**类型化别名**（文件头部新增 v4.0 路由段，原内容完整保留） |
| `/test` `/verify` `/contract-verify` `/ui-verify` `/perf` `/reliability` `/policy-check` | 成为 SELF_VERIFY / REVIEW / ACCEPT 阶段内的**自动选择检查**，不再强制作为独立用户流程 |
| `/workstream` | 执行基础设施，通常应自动运行 |
| `/work` | **新默认入口** |

### 5.3 新增文件（22 个）

- **命令（1）**：`work.md`
- **规则（8）**：WORK_ITEM_RULES（工作项规则）、WORKFLOW_CORE（统一工作流核心）、IMPACT_DISCOVERY_RULES（影响发现）、SELF_VERIFICATION_RULES（自验证）、ACCEPTANCE_RULES（验收）、STATE_CONSOLIDATION_RULES（状态整合）、API_CONSUMER_HANDOFF_RULES（消费者交接）、UI_DESIGN_TRACK_RULES（UI 设计轨道）
- **脚本（2）**：`validate_work_item.py`（工作项校验）、`validate_v4_package.py`（包完整性校验）
- **模板（6）**：WORK_ITEM、IMPACT_MAP、IMPLEMENTATION_DESIGN、VERTICAL_SLICE、ACCEPTANCE_REPORT、API_CONSUMER_HANDOFF
- **顶层（1）**：`MANIFEST.json`（包清单）
- **文档（4）**：docs/MIGRATION_TO_V4.md（官方迁移指引）、docs/WORKFLOW_CORE.md、docs/API_CONSUMER_HANDOFF.md、docs/work-items/（工作项归档目录）

### 5.4 核心机制亮点

- **Impact Map 三态分类**：DISCOVER 阶段每个相关面必须归类为 AFFECTED（受影响）/ VERIFIED_UNAFFECTED（已核实不受影响）/ NOT_APPLICABLE（不适用）；**UNKNOWN（未知）在验收时不允许存在**。
- **反伪造**：绝不用假成功、静默 mock、无边界捷径、未记录的契约替换来冒充完成。
- **事故快车道**：生产事故用 DETECT → TRIAGE → MITIGATE → STABILIZE → ROOT_CAUSE → PERMANENT_FIX → POSTMORTEM；临时降级仪式恢复服务可以，**永久修复必须回到正常生命周期**。

## 六、命令速查（共 27 个）

| 命令 | 用途 |
|---|---|
| `/work` | **统一工作项入口（v4.0 默认）** |
| `/init` | 初始化项目状态 |
| `/bug` | 修复行为与预期不符（= /work 的 BUG 类型） |
| `/change` | 有意的行为变更（= /work 的 CHANGE 类型） |
| `/feature` | 新增能力（= /work 的 FEATURE 类型） |
| `/repair` | 能力级修复（= /work 的 REPAIR 类型） |
| `/capability` | 探查业务能力表面（只读） |
| `/verify` | 基于证据的完成验证 |
| `/contract-verify` | 契约一致性验证 |
| `/continue` | 恢复中断工作项（先查注册表/脏工作） |
| `/workstream` | 工作流隔离管理 |
| `/ui` | UI 设计轨道入口（REFINE/REFACTOR/REDESIGN 分类） |
| `/ui-lock` | 锁定已批准设计（v3.6） |
| `/ui-implement` | 把批准设计翻译为生产实现（v3.6） |
| `/ui-critique` | 独立设计批评（v3.6） |
| `/ui-verify` | 截图对截图的 UI 验收门禁 |
| `/test` | 代码行为验证 |
| `/review` | 独立评审（工作项阶段） |
| `/release` | 发布就绪/发布流程 |
| `/incident` | 生产事故快车道 |
| `/sync` | 全局文档/状态同步 |
| `/merge` | 合并治理 |
| `/cleanup` | 清理治理 |
| `/perf` | 性能治理 |
| `/reliability` | 可靠性治理 |
| `/policy-check` | 规则符合性检查 |
| `/context` | 上下文管理 |

## 七、规则体系（.ai/rules/，共 59 套）

### 7.1 v4.0 核心（8 套，新增）

- **WORKFLOW_CORE** — 统一工作流核心（权威 12 阶段生命周期）
- **WORK_ITEM_RULES** — 工作项规则（一个工作项一份证据链）
- **IMPACT_DISCOVERY_RULES** — 影响发现（UNKNOWN 不得验收）
- **SELF_VERIFICATION_RULES** — 自验证（验证是实现的一部分）
- **ACCEPTANCE_RULES** — 验收规则（重读原始契约 + 证据）
- **STATE_CONSOLIDATION_RULES** — 状态整合（工作项/运行时/Git 为真相）
- **API_CONSUMER_HANDOFF_RULES** — API 消费者交接
- **UI_DESIGN_TRACK_RULES** — UI 设计轨道（UI 是轨道不是独立宇宙）

### 7.2 UI 视觉体系（v2.4/v2.5/v3.2/v3.6 保留）

UI_RULES、DESIGN_SYSTEM_RULES、PROTOTYPE_RULES、PROTOTYPE_TO_CODE_RULES、VISUAL_FIDELITY_RULES、RESPONSIVE_FIDELITY_RULES、SCREENSHOT_VISUAL_DIFF_RULES、CONTENT_STRESS_RULES、UI_IMPLEMENTATION_RULES、UI_DESIGN_METHODOLOGY、UI_REFACTOR_RULES、UI_FIDELITY_CONTRACT_RULES、IMPLEMENTATION_AWARE_UI_RULES、ACCESSIBILITY_RULES

### 7.3 能力与证据（v3.4/v3.5 保留）

CAPABILITY_REPAIR_RULES、CONSUMER_COVERAGE_RULES、REQUIREMENT_TRACEABILITY_RULES、EVIDENCE_INTEGRITY_RULES、CRASH_SAFE_RECOVERY_RULES、RECOVERY_RULES、CROSS_LAYER_CONSISTENCY_RULES、CONTRACT_RULES

### 7.4 工程治理与通用（历版保留）

GOVERNANCE_RULES、RELEASE_GOVERNANCE_RULES、RELIABILITY_RULES、PERFORMANCE_RULES、OBSERVABILITY_RULES、GIT_RULES、WORKFLOW_RULES、WORKSTREAM_RULES、AUTO_ISOLATION_RULES、RESOURCE_LIFECYCLE_RULES、STATE_MACHINE、DECISION_POLICY、CODING_RULES、CHANGE_RULES、DIFF_RULES、API_RULES、DATABASE_RULES、CONFIGURATION_RULES、DEPENDENCY_RULES、BOUNDARY_RULES、COMPLEXITY_RULES、CONCURRENCY_RULES、TEST_RULES、DOCUMENTATION_RULES、HANDOFF_RULES、INTERRUPTION_SAFETY、UNCERTAINTY_RULES、ADAPTIVE_WORKFLOW、RULE_PRIORITY 等

> 规则优先级冲突时遵循 `RULE_PRIORITY.md`。

## 八、模板与文档体系

### 8.1 模板（.ai/templates/，共 57 个）

- **v4.0 新增（6）**：WORK_ITEM、IMPACT_MAP、IMPLEMENTATION_DESIGN、VERTICAL_SLICE、ACCEPTANCE_REPORT、API_CONSUMER_HANDOFF
- **v3.6 新增（10）**：UI_DESIGN_STRATEGY、PRODUCT_CONTEXT_AUDIT、LEGACY_UI_DECOMPOSITION、COMPONENT_CAPABILITY_AUDIT、PROTOTYPE_TECHNICAL_PLAN、DESIGN_CRITIQUE、UI_LOCK_MANIFEST、UI_ELEMENT_CONTRACT、UI_CONTENT_CONTRACT、UI_COMPATIBILITY_MATRIX
- **v3.5 新增（5）**：LAYER_IMPACT_MATRIX、CONTRACT_DELTA、END_TO_END_DATA_FLOW、REQUIREMENT_COVERAGE_MATRIX、SEMANTIC_UI_IMPACT
- **v3.4 新增（6）**：CAPABILITY_MAP、REPAIR_PLAN、CONSUMER_COVERAGE、COMPLETION_EVIDENCE、EXECUTION_CONFIDENCE、REQUIREMENT_TRACEABILITY
- **更早版本（30）**：v3.2 的 SCREENSHOT_VISUAL_DIFF_REPORT、v3.0 的 10 个、v2.5 的 3 个、v2.4 的 5 个、v2.3 的 3 个、v2 的 STRUCTURAL_DIFF、v1 的 7 个

### 8.2 文档样板（docs/，含归档目录共 36 个文件）

- **v4.0 新增**：MIGRATION_TO_V4（官方迁移指引）、WORKFLOW_CORE、API_CONSUMER_HANDOFF、work-items/（工作项归档）
- 状态类：PROJECT_STATE、EXECUTION_CURSOR、SESSION_CHECKPOINT、CHANGELOG
- 架构类：ARCHITECTURE、API、INTERFACE_CONTRACTS、DATABASE、CONFIGURATION
- 需求类：PRD、NON_FUNCTIONAL_REQUIREMENTS、PERFORMANCE_BUDGET、COMPLEXITY_BUDGET、SLO
- 治理类：RELEASE_STRATEGY、VERIFICATION_POLICY、CAPABILITY_INDEX、CROSS_LAYER_CONSISTENCY、UI_ACCEPTANCE_STANDARD、UI_DESIGN_METHODOLOGY、UI_REFACTOR_WORKFLOW
- 记录目录：bugs/、changes/、features/、incidents/、diffs/、contracts/、config/、history/、work-items/（各含 .gitkeep）

## 九、安装（INSTALL.md）

1. 将本包复制到仓库根目录（保持 .ai/、design/、docs/、tasks/、workstreams/、.ai-runtime/ 结构）
2. 建议先运行：`python .ai/scripts/validate_v4_package.py --help`（包完整性校验）
3. 让编码代理先读：`AGENTS.md`、`.ai/SKILL.md`、`.ai/rules/WORKFLOW_CORE.md`、`.ai/commands/work.md`、`docs/MIGRATION_TO_V4.md`

**迁移注意**：从 v3.x 升级到 v4.0 是架构性调整（编排方式改变，能力保留）。对已有项目，不要盲目覆盖项目专属硬规则，采用「备份 → v4.0 骨架 → 恢复/合并定制」方式（标准内容在前、项目定制在后），官方指引见 `docs/MIGRATION_TO_V4.md`。

## 十、日常使用指南（USAGE.md 场景）

| 场景 | 命令示例 | 要点 |
|---|---|---|
| 新功能 | `/work 给结算页增加配送方式选择` | 一个工作项跑完 12 阶段：理解→影响地图→实现设计→纵向切片→自验证→评审→验收 |
| 变更 | `/work 把营业日语义改为当前运营班次` | 必须构建 Impact Map，覆盖所有已知消费者与语义 UI 效果 |
| 修复 | `/bug 营业时间显示错误` | 先根因后改动；反复局部补丁自动升级为能力修复 |
| 恢复中断 | `/continue` | 优先查工作项 + `.ai-runtime` 注册表 + Git，不信任陈旧摘要 |
| 完成验证 | `/verify` | 需求覆盖 + 影响面分类（UNKNOWN=0）+ 证据全部通过才 VERIFIED_DONE |

## 十一、Policy as Code（.ai/scripts/，共 11 个脚本 + 2 个说明）

| 脚本 | 用途 |
|---|---|
| `validate.py` | 工程治理规则校验（v3.0） |
| `workstream.py` | 工作流隔离（status/ensure，v3.1） |
| `capture_ui.mjs` | 截图捕获辅助（Playwright，v3.2，可选） |
| `visual_diff.py` | 视觉差异对比（Pillow，v3.2） |
| `runtime_registry.py` | 崩溃安全运行时注册表（v3.4） |
| `evidence_scan.py` | 启发式反伪造扫描（v3.4） |
| `validate_cross_layer.py` | 跨层一致性校验（v3.5） |
| `suspicious_completion_scan.py` | 可疑完成扫描（v3.5） |
| `validate_ui_design.py` | UI 设计校验（v3.6） |
| `validate_work_item.py` | **工作项校验（v4.0 新增）** |
| `validate_v4_package.py` | **v4.0 包完整性校验（v4.0 新增）** |

## 十二、目录结构

```
仓库根/
├── AGENTS.md            # 代理必读（v4.0：一个工作项一个生命周期）
├── README.md            # 项目介绍（v4.0 版本说明）
├── README_ZN.md         # 本中文使用说明
├── INSTALL.md           # 安装说明
├── USAGE.md             # 用法示例
├── VERSION.md           # 版本说明
├── MANIFEST.json        # v4.0 包清单（新增）
├── .ai/                 # 系统本体
│   ├── commands/        # 27 个命令定义
│   ├── rules/           # 59 套规则
│   ├── templates/       # 57 个模板
│   ├── scripts/         # 13 个文件（11 脚本 + 2 说明）
│   └── SKILL.md         # 技能入口（v4.0 精简版 + 各版本能力段）
├── .ai-runtime/         # 崩溃安全运行时元数据
│   ├── registry.json    # 全局注册表
│   ├── journal/         # 写前日志
│   └── locks/           # 锁
├── design/              # 设计资产（approved/、prototypes/、visual-verification/）
├── docs/                # 文档样板（含 work-items/ 归档）
├── tasks/               # 任务状态（active/、completed/）
└── workstreams/         # 工作流状态（REGISTRY.md）
```

## 十三、自定义与扩展

- **项目专属硬规则**：可追加自己的段落到 AGENTS.md（如 `## Project-Specific Hard Rules (server project)`）、SKILL.md（如 `## Project-Specific Hard Requirements (server project)`）或命令文件（如 `## Documentation & API Sync`），与标准流程并存、互不覆盖
- **升级模式**：历次升级均采用「备份 → 新版本骨架 → 恢复/合并定制」模式，标准内容在前、项目定制在后；v4.0 对用户定制的 bug/change/feature 采用「v4.0 路由头 + 原内容 + 用户段」三路合并
- **脚本扩展**：可在 v4.0 校验脚本基础上按项目补充规则

## 十四、设计原则

1. **一个工作项一条证据链**：每个有意义的请求只有一个工作项身份（如 WI-042），需求契约、影响地图、实现设计、任务切片、验证证据、评审发现、验收决定、集成/发布状态全部归它所有
2. **影响面先于编辑**：非平凡工作禁止"先改后查"，必须先构建 Impact Map，每个相关面分类，UNKNOWN 不得验收
3. **证据优先于声明**：模型自己的"完成"声明不是证据；测试通过 ≠ 验收通过，必须重读原始契约逐条对照证据
4. **纵向切片优于按层**：优先端到端可验证切片，避免"控制器→服务→前端→UI"的层式长链
5. **API 变更必须交接**：后端接口变更要么同步消费方，要么产出 API_CONSUMER_HANDOFF；后端单独完成不算完成
6. **UI 是轨道不是宇宙**：UI 受影响必须走设计轨道；重构保留能力不保外观
7. **修能力不修症状**：反复局部修补 = 共享能力问题，自动升级能力修复
8. **反伪造**：绝不用 fake/mock/硬编码/占位数据让不完整的需求看起来完成
9. **崩溃安全**：非平凡工作先注册再动手，`/continue` 优先恢复中断状态，禁止重复创建
10. **状态单一真相**：工作项 → 运行时注册表 → Git；兼容性摘要不得成为竞争真相源
