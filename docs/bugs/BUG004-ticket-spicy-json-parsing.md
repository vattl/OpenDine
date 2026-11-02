# Bug Report BUG004 — 小票模板辣度 JSON 解析与菜名关联展示

## Status
- **Bug ID**: BUG004
- **Status**: FIXED
- **Severity**: HIGH
- **Found**: 2026-08-31
- **Root Cause**: `PrintTemplateEngineImpl` 中的 `formatPrintSpecInParens` 原先仅识别 `{"name":"..."}` 格式 JSON，对数据库及前端传入的 `{"辣度":"不辣"}` 等格式未正确提取值，导致直接输出原始 JSON 字符串 `({"辣度": "不辣"})`，且在结账单中多输出了单独一行。

---

## 1. 现象 (Symptom)
小票打印输出中，菜品规格辣度输出了原始 JSON 字符，如：
```
油 边 王        15       1
({"辣度":               "不辣"})
```

---

## 2. 修复方案 (Fix Plan)
1. 增强 `PrintTemplateEngineImpl.getSpicyText` 与 `formatPrintSpecInParens`：
   - 深度解析各类 JSON 结构（`{"辣度":"微辣"}`、`{"口味":"微辣"}`、`{"name":"微辣"}`、数组及复合键值对）；
   - 提取出纯文本规格内容（如 `不辣`、`微辣`）。
2. 将解析后的规格紧跟在菜品名称后展示：`油边王(不辣)`、`炭烤羊肉串(微辣)`。
3. 移除多余的换行独立打印规格行。
4. 单元测试全量覆盖各种 JSON 格式与纯文本输入。
