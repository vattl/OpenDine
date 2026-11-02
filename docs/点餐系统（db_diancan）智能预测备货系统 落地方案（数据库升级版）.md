# 点餐系统（db_diancan）智能预测备货系统 落地方案（数据库升级版）

**适用版本**：MySQL 8.0.42 | **侵入性**：0修改原有表 | **场景**：烧烤/餐饮多门店、小程序点餐、会员储值合规预测

---

## 一、文档说明

本文档基于你最新的 `db_diancan` 全量库结构定制：

- 保留你已有的 3 张预测表：`t_stock_prep_forecast_run`/`day`/`dish` 不动
- **仅新增 3 张核心业务表**，无删改、无冗余、无冲突
- 完美适配：多门店隔离、食材损耗、会员储值不计营业额、小程序端使用

---

## 二、方案总览

### 核心目标

1. 历史订单 → 精准菜品销量预测
2. 菜品销量 → 自动换算原材料备货量
3. 店长小程序 → 一键确认/调整/生成采购单
4. 财务合规：**会员充值不计入预测，仅真实消费参与计算**

### 设计原则

- 零侵入：不改动任何原有业务表
- 可落地：一线餐饮通用流程，无需算法专家
- 可追溯：预测→备货→入库全链路留痕
- 多门店：按 `shop_id` 完全隔离

---

## 三、数据库升级脚本（直接执行）

```SQL

SET FOREIGN_KEY_CHECKS=0;

-- ======================
-- 1. 菜品-原材料配比表(BOM)【核心：销量→原料消耗量】
-- ======================
DROP TABLE IF EXISTS t_dish_material_bom;
CREATE TABLE t_dish_material_bom (
  id bigint NOT NULL AUTO_INCREMENT COMMENT '配比ID',
  shop_id int NOT NULL COMMENT '门店ID(t_shop.id)',
  dish_id int NOT NULL COMMENT '菜品ID(t_dish.id)',
  material_id int NOT NULL COMMENT '原材料ID(t_material.id)',
  dosage decimal(10,3) NOT NULL DEFAULT 0.000 COMMENT '单份菜品消耗原材料数量',
  unit varchar(16) NOT NULL DEFAULT '斤' COMMENT '单位：斤/克/袋/瓶',
  loss_rate decimal(5,2) NOT NULL DEFAULT 0.05 COMMENT '烧烤损耗率：肉类0.03，蔬菜0.08',
  is_enabled tinyint NOT NULL DEFAULT 1 COMMENT '1启用 0禁用',
  created_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_shop_dish_material (shop_id, dish_id, material_id),
  KEY idx_dish (dish_id),
  KEY idx_material (material_id),
  KEY idx_shop (shop_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='菜品-原材料配比表(BOM)';

-- ======================
-- 2. 原材料备货计划表【核心：预测→备货→采购】
-- ======================
DROP TABLE IF EXISTS t_stock_prepare_plan;
CREATE TABLE t_stock_prepare_plan (
  id bigint NOT NULL AUTO_INCREMENT COMMENT '备货计划ID',
  shop_id int NOT NULL COMMENT '门店ID',
  run_id bigint NOT NULL COMMENT '预测批次ID(t_stock_prep_forecast_run.id)',
  prepare_date date NOT NULL COMMENT '备货日期',
  material_id int NOT NULL COMMENT '原材料ID',
  current_stock decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '当前库存(t_material.stock)',
  forecast_consume decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '预测消耗总量',
  safe_stock decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '安全库存',
  suggest_qty decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '系统建议备货量',
  manual_adjust decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '人工调整量(±)',
  final_qty decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT '最终确认备货量',
  status tinyint NOT NULL DEFAULT 0 COMMENT '0待确认 1已确认 2已采购 3已入库',
  operator_id int NULL DEFAULT NULL COMMENT '操作员t_admin.id',
  created_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_shop_material_date (shop_id, material_id, prepare_date),
  KEY idx_run_id (run_id),
  KEY idx_prepare_date (prepare_date),
  KEY idx_status (status),
  CONSTRAINT fk_prepare_run FOREIGN KEY (run_id) REFERENCES t_stock_prep_forecast_run(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='原材料备货计划表';

-- ======================
-- 3. 备货规则配置表【灵活适配烧烤店】
-- ======================
DROP TABLE IF EXISTS t_stock_prep_config;
CREATE TABLE t_stock_prep_config (
  id bigint NOT NULL AUTO_INCREMENT,
  shop_id int NOT NULL COMMENT '门店ID',
  safe_stock_rate decimal(5,2) NOT NULL DEFAULT 0.10 COMMENT '安全库存系数',
  default_loss_rate decimal(5,2) NOT NULL DEFAULT 0.05 COMMENT '默认损耗率',
  forecast_days int NOT NULL DEFAULT 3 COMMENT '预测天数',
  history_days int NOT NULL DEFAULT 30 COMMENT '历史回溯天数',
  weather_factor decimal(5,2) NOT NULL DEFAULT 1.00 COMMENT '天气系数',
  holiday_factor decimal(5,2) NOT NULL DEFAULT 1.20 COMMENT '节假日系数',
  member_factor decimal(5,2) NOT NULL DEFAULT 1.10 COMMENT '会员储值系数',
  is_enabled tinyint NOT NULL DEFAULT 1,
  updated_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_shop (shop_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='备货规则配置表';

SET FOREIGN_KEY_CHECKS=1;
```

---

## 四、新增表结构详解

### 1. t_dish_material_bom（菜品-原料配比）

- 作用：定义 1 份菜用多少原料，支持按门店、损耗率单独配置
- 关键字段：`shop_id`/`dish_id`/`material_id`/`dosage`/`loss_rate`

### 2. t_stock_prepare_plan（备货计划）

- 作用：连接「预测结果」与「实际采购」，支持店长调整
- 关键字段：`run_id`（关联预测批次）/`suggest_qty`/`final_qty`/`status`

### 3. t_stock_prep_config（备货规则）

- 作用：按店配置预测参数，不用改代码
- 关键字段：`safe_stock_rate`/`holiday_factor`/`member_factor`

---

## 五、与现有数据库联动清单


| 原有表名                     | 备货系统使用方式                            |
| ------------------------ | ----------------------------------- |
| t_order / t_order_detail | 按 shop_id+dish_id+date 统计真实销量，回填准确率 |
| t_dish / t_dish_shop     | 读取在售菜品，参与预测                         |
| t_material               | 读取库存、单位、预警阈值                        |
| t_stock_in / t_stock_out | 备货入库自动生成记录                          |
| t_member_recharge        | 仅做客流修正，**不计入销量**                    |
| t_shop                   | 多门店隔离                               |
| t_daily_stat             | 日营业额联动修正整体规模                        |
| 已有3张预测表                  | 直接作为备货数据来源                          |


---

## 六、一线落地业务流程

### 步骤 1：每日凌晨自动预测

1. 从 `t_order_detail` 拉取近 30 天销量
2. 按门店/菜品/日期统计
3. 写入已有预测表：`t_stock_prep_forecast_run/day/dish`

### 步骤 2：自动计算原料需求

1. 按 `t_dish_material_bom` 换算：

预测原料消耗 = 预测销量 × 单份耗量 × (1+损耗率)

1. 扣减当前库存 + 加安全库存
2. 生成 `t_stock_prepare_plan` 建议备货量

### 步骤 3：店长小程序操作

1. 查看建议量
2. 手动调整（±）
3. 确认 → 生成采购单
4. 入库后自动更新 `t_material.stock` 与 `t_stock_in`

### 步骤 4：准确率复盘

- 闭店后从 `t_order_detail` 回填实际销量
- 系统自动优化系数

---

## 七、核心计算公式（烧烤店专用）

1. **菜品预测销量**
  ```Plain Text

    预测销量 = 历史基线销量 × 星期 × 假日 × 天气 × 会员修正系数
  ```
2. **原料预测消耗**
  ```Plain Text

    预测消耗 = Σ(预测销量 × 单份耗量) × (1 + 损耗率)
  ```
3. **建议备货量**
  ```Plain Text

    建议备货 = 预测消耗 − 当前库存 + 安全库存
    安全库存 = 预测消耗 × 安全库存系数
  ```

---

## 八、技术栈（直接对接现有系统）

- 后端：Java(SpringBoot) / Node.js
- 预测计算：Python + FastAPI
- 调度：Spring Schedule（每日凌晨执行）
- 前端：小程序 / Vue3 管理后台
- 数据库：MySQL 8.0（你现有版本）
- 缓存：Redis（库存/预测结果）

---

## 九、快速上线步骤（1天完成）

1. 执行本文档 SQL 新增 3 张表
2. 后台录入菜品-原料配比（BOM）
3. 按店配置备货规则（损耗率、安全库存等）
4. 上线定时预测任务
5. 小程序端开通备货看板
6. 试运行：自动预测+人工调整

---

## 十、会员充值合规说明（关键）

- 预测销量**只统计真实消费**（来自 `t_order` 实际出餐）
- `t_member_recharge` 充值金额**不进入销量计算**
- 会员余额仅作为「客流热度系数」小幅修正预测，不产生虚高备货

---

## 十一、注意事项

1. 必须按 `shop_id` 隔离数据，禁止跨门店混用
2. 损耗率建议：肉类 3%、蔬菜 8%、调料 2%
3. 预测建议每日凌晨 2-4 点运行，避开高峰期
4. 店长调整幅度建议限制 ±30%，避免过度偏离
5. 新品前 7 天用同类菜品基线预测

---

## 十二、交付物清单

1. 可直接执行的数据库升级 SQL
2. 与现有库完整联动方案
3. 一线可落地流程与公式
4. 小程序/后台对接标准
5. 会员财务合规口径

