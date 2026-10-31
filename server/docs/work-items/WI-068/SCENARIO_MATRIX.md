# Scenario Matrix — WI-068

| ID | Scenario | Expected | Status |
|---|---|---|---|
| S01 | 10-23 CLOSED，10-24 缺失，当前 10-25 | 返回 25 PENDING、24 PENDING、23 CLOSED | VERIFIED |
| S02 | 10-24 REOPENED，当前 10-25 | 24 为 REOPENED 且为唯一 can_close | VERIFIED |
| S03 | 多个 PENDING | 仅最早待结日 can_close | VERIFIED |
| S04 | limit=2 后翻页 | 日期连续、无重复，next_cursor 可继续 | VERIFIED |
| S05 | 旧 snapshot id cursor | 从该快照前一营业日继续 | VERIFIED |
| S06 | date_from/date_to 含未来或锚点前日期 | 分别裁剪到当前日和首快照日 | VERIFIED（边界计算及既有日期范围测试） |
