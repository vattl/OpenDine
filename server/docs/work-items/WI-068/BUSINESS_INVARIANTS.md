# Business Invariants — WI-068

| ID | Invariant | Verification |
|---|---|---|
| INV-CLOSE-SEQ-001 | 门店只能结算权威最早未结营业日 | 列表仅该日 `can_close=true`；写接口现有 409 守卫保持不变 |
| INV-CLOSE-SEQ-002 | 首张快照之前不追溯为待结历史 | 列表下限裁剪到首张有效快照营业日 |
| INV-CLOSE-LIST-001 | 同一页营业日连续且无重复 | 日期游标单元测试 |
| INV-TENANT-001 | 快照不可跨门店泄露 | 查询始终绑定已授权 shop_id |
