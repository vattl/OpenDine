import os
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
WI_DIR = Path(__file__).resolve().parents[1]


class TestWI073Remediation(unittest.TestCase):
    def test_aud_073_01_wechatpay_skill_three_part_review(self):
        """Verify that WeChat Pay quality review contains common checks, e-invoice guidance, and flow rules."""
        report = (WI_DIR / "INVOICE_AUDIT_REPORT.md").read_text(encoding="utf-8")
        test_report = (WI_DIR / "TEST_REPORT.md").read_text(encoding="utf-8")

        # 1. Common checks from 接入质量检查清单
        self.assertIn("通用质量检查清单", report)
        self.assertIn("编码风格", report)
        self.assertIn("安全", report)
        self.assertIn("幂等", report)
        self.assertIn("接入链路稳定性", report)
        self.assertIn("API规范", report)
        self.assertIn("打印日志", report)

        # 2. Electronic invoice business guidance
        self.assertIn("电子发票单业务注意事项", report)
        self.assertIn("support_fapiao", report)

        # 3. Flow rules from 流程规则与测试用例
        self.assertIn("流程规则核对", report)
        self.assertIn("通用-付款按钮防抖避免连续调起两次支付", report)
        self.assertIn("通用-没收到回调或回调出错须查单", report)
        self.assertIn("付款码支付-状态不明须查单并撤销", report)
        self.assertIn("退款-非成功须查单并原单重试", report)

        # Test report reflects the rule coverage
        self.assertIn("流程规则核对汇总", test_report)

    def test_aud_073_02_apiv3_response_signature_check(self):
        """Verify APIv3 response signature omission is audited with exact line numbers and official doc reference."""
        report = (WI_DIR / "INVOICE_AUDIT_REPORT.md").read_text(encoding="utf-8")
        security = (WI_DIR / "SECURITY_AUDIT.md").read_text(encoding="utf-8")

        # Finding F-10 or classified finding for response verification
        self.assertIn("F-10", report)
        self.assertIn("OrderInvoiceServiceImpl.java:94-109", report)
        self.assertIn("Wechatpay-Signature", report)
        self.assertIn("4012365870", report)

        self.assertIn("OrderInvoiceServiceImpl.java:94-109", security)
        self.assertIn("应答验签", security)

    def test_aud_073_03_customer_invoice_ui_audit(self):
        """Verify consumer customer invoice HTML UI is audited as affected surface."""
        impact = (WI_DIR / "IMPACT_MAP.md").read_text(encoding="utf-8")
        report = (WI_DIR / "INVOICE_AUDIT_REPORT.md").read_text(encoding="utf-8")

        # UI is tracked as affected audit surface
        self.assertIn("invoice-apply.html", impact)
        self.assertIn("F-11", report)
        self.assertIn("invoice-apply.html", report)
        self.assertIn("国家税务总局全国统一规范电子发票开具服务", report)
        self.assertIn("虚假完成", report)
        self.assertIn("隐私泄露", report)
        self.assertIn("downloadBox", report)

    def test_aud_073_04_acceptance_state_reconciliation(self):
        """Verify Work Item, Delivery Gate, Audit Plan, and Acceptance Report states are internally consistent."""
        work_item = (WI_DIR / "WORK_ITEM.md").read_text(encoding="utf-8")
        gate = (WI_DIR / "DELIVERY_GATE.md").read_text(encoding="utf-8")
        plan = (WI_DIR / "AUDIT_PLAN.md").read_text(encoding="utf-8")
        acceptance = (WI_DIR / "ACCEPTANCE_REPORT.md").read_text(encoding="utf-8")

        # T05 slice marked complete
        self.assertIn("- [x] T05 输出审计报告并完成独立复核", work_item)

        # Audit Plan fields match completion
        self.assertIn("Audit Execution Status: PASS", plan)
        self.assertIn("Remediation Cycle: CLEAR", plan)
        self.assertIn("Open Findings: 0", plan)
        self.assertIn("Final Audit Decision: APPROVED", plan)

        # Acceptance report clearly distinguishes delivery acceptance from product release blocked
        self.assertIn("Decision: ACCEPTED", acceptance)
        self.assertIn("Product Release Decision: BLOCKED", acceptance)

    def test_aud_073_05_external_call_isolation_evidence(self):
        """Verify execution record confirms 0 calls to external WeChat endpoints."""
        exec_record = (WI_DIR / "EXECUTION_RECORD.md").read_text(encoding="utf-8")
        self.assertIn("Network Calls to api.mch.weixin.qq.com: 0", exec_record)
        self.assertIn("Real Invoicing Calls: 0", exec_record)
        self.assertIn("Local Inspection Only: YES", exec_record)


if __name__ == "__main__":
    unittest.main()
