# Security Audit — WI-010

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Findings

- 外卖分支唯一剩余树差异包含本机 MySQL 数据、PID、证书私钥与 root-password，已通过 `ours` 内容策略全部排除。
- 集成树禁止路径检查计数为 0。
- 当前基线新增行的凭据模式检查未发现疑似密钥。
- KDS 冲突按 KDS-CA-1.3 云端唯一权威裁决，未恢复本地双权威或 replication watermark 写路径。
