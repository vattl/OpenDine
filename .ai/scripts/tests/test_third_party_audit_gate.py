from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / ".ai" / "scripts" / "validate_third_party_audit.py"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contract_digest(criteria: list[str]) -> str:
    canonical = "\n".join(
        f"AC-{index:02d}|{criterion}" for index, criterion in enumerate(criteria, 1)
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def create_complete_audit(root: Path) -> Path:
    work = root / "docs" / "work-items" / "WI-TEST"
    write(
        work / "WORK_ITEM.md",
        "# WORK ITEM — WI-TEST\n\n"
        "## Requirement Contract\n\n"
        "### Acceptance criteria\n\n"
        "- [x] Criterion one.\n"
        "- [x] Criterion two.\n\n"
        "## Acceptance Decision\n",
    )
    evidence = {
        "IMPLEMENTATION_DESIGN.md": "implementation design evidence\n",
        "TEST_REPORT.md": "test evidence\n",
        "SECURITY_AUDIT.md": "security evidence\n",
    }
    for name, content in evidence.items():
        write(work / name, content)

    inventory_rows = []
    for index, name in enumerate(evidence, 1):
        inventory_rows.append(
            f"| E{index:02d} | {name} | {digest(work / name)} | reviewed evidence |"
        )
    write(
        work / "AUDIT_PACKET.md",
        "# Third-Party Audit Packet\n\n"
        "Packet Status: SEALED\n"
        "Work Item: WI-TEST\n"
        "Implementer Agent: implementer-session-1\n"
        "Prepared At: 2026-10-27T10:00:00+08:00\n"
        "Reviewed Snapshot: snapshot-abc123\n"
        "Acceptance Criteria: 2\n"
        f"Acceptance Contract SHA256: {contract_digest(['Criterion one.', 'Criterion two.'])}\n"
        "Evidence Files: 3\n"
        "Material Unknowns: 0\n\n"
        "## Evidence Inventory\n\n"
        "| Evidence ID | Path | SHA256 | Purpose |\n"
        "|---|---|---|---|\n"
        + "\n".join(inventory_rows)
        + "\n\n## Acceptance Contract\n\n"
        "| Criterion ID | Requirement | Claimed Evidence |\n"
        "|---|---|---|\n"
        "| AC-01 | Criterion one. | E02 |\n"
        "| AC-02 | Criterion two. | E02 |\n",
    )
    write(
        work / "AUDIT_RECEIPT.md",
        "# Third-Party Audit Receipt — WI-TEST\n\n"
        "Audit Session ID: reviewer-session-9\n"
        "Auditor Agent: independent-reviewer-9\n"
        "Auditor Provider / Model: independent-agent/default-model\n"
        "Started At: 2026-10-27T10:00:00+08:00\n"
        "Completed At: 2026-10-27T10:01:00+08:00\n"
        "Context Mode: FRESH\n"
        "Mutation Permission: AUDIT_ARTIFACTS_ONLY\n"
        "Reviewed Packet: AUDIT_PACKET.md\n\n"
        "## Invocation Record\n\n"
        "Agent independent-reviewer-9 was started with assigned scope to review the sealed packet read-only.\n",
    )
    packet_hash = digest(work / "AUDIT_PACKET.md")
    receipt_hash = digest(work / "AUDIT_RECEIPT.md")
    write(
        work / "THIRD_PARTY_AUDIT.md",
        "# Third-Party Agent Audit\n\n"
        "Audit Decision: APPROVED\n"
        "Independence Status: VERIFIED\n"
        "Fresh Context: YES\n"
        "Read-Only Audit: YES\n"
        "Implementer Agent: implementer-session-1\n"
        "Auditor Agent: independent-reviewer-9\n"
        "Auditor Provider / Model: independent-agent/default-model\n"
        "Audit Mode: INDEPENDENT_AGENT\n"
        "Audit Session ID: reviewer-session-9\n"
        "Audit Receipt: AUDIT_RECEIPT.md\n"
        f"Audit Receipt SHA256: {receipt_hash}\n"
        "Audit Packet: AUDIT_PACKET.md\n"
        f"Audit Packet SHA256: {packet_hash}\n"
        "Reviewed Work Item: WI-TEST\n"
        "Reviewed Snapshot: snapshot-abc123\n"
        "Critical Open: 0\n"
        "High Open: 0\n"
        "Required Findings Resolved: YES\n"
        "Acceptance Coverage: COMPLETE\n"
        "Evidence Integrity: VERIFIED\n"
        "Acceptance Criteria Reviewed: 2\n\n"
        "## Review Coverage\n\n"
        "| Axis | Scope | Evidence | Verdict |\n"
        "|---|---|---|---|\n"
        "| REQUIREMENT | requirement contract | E01 | PASS |\n"
        "| CORRECTNESS | implementation behavior | E01, E02 | PASS |\n"
        "| ARCHITECTURE | boundaries and ownership | E01 | PASS |\n"
        "| SECURITY | threats and scans | E03 | PASS |\n"
        "| TEST_EVIDENCE | executed checks | E02 | PASS |\n"
        "| FALSE_COMPLETION | mocks/placeholders/missing proof | E01, E02, E03 | PASS |\n"
        "| ACCEPTANCE | original criteria and outcome | E01, E02 | PASS |\n\n"
        "## Acceptance Criterion Audit\n\n"
        "| Criterion ID | Evidence Reviewed | Auditor Verdict | Notes |\n"
        "|---|---|---|---|\n"
        "| AC-01 | E02 | PASS | proven |\n"
        "| AC-02 | E02 | PASS | proven |\n\n"
        "## Findings\n\n"
        "| Finding ID | Severity | Finding | Required Action | Status | Reverification |\n"
        "|---|---|---|---|---|---|\n"
        "| AUDIT-NONE | NONE | No blocking finding | NONE | CLOSED | packet review |\n",
    )
    return work


def run_gate(root: Path, work: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--root",
            str(root),
            "--work-item",
            work.relative_to(root).as_posix(),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


class ThirdPartyAuditGateTests(unittest.TestCase):
    def test_missing_audit_artifacts_block(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = root / "docs" / "work-items" / "WI-TEST"
            work.mkdir(parents=True)

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("AUDIT_PACKET.md", result.stdout)
            self.assertIn("THIRD_PARTY_AUDIT.md", result.stdout)

    def test_complete_independent_audit_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)

            result = run_gate(root, work)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("THIRD-PARTY AUDIT GATE: PASS", result.stdout)

    def test_same_implementer_and_auditor_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    "Auditor Agent: independent-reviewer-9",
                    "Auditor Agent: implementer-session-1",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must differ", result.stdout)

    def test_non_fresh_or_mutating_audit_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8")
                .replace("Fresh Context: YES", "Fresh Context: NO")
                .replace("Read-Only Audit: YES", "Read-Only Audit: NO"),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Fresh Context", result.stdout)
            self.assertIn("Read-Only Audit", result.stdout)

    def test_evidence_drift_after_sealing_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            write(work / "TEST_REPORT.md", "changed after audit\n")

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("TEST_REPORT.md", result.stdout)
            self.assertIn("SHA256", result.stdout)

    def test_stale_packet_or_receipt_hash_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    f"Audit Packet SHA256: {digest(work / 'AUDIT_PACKET.md')}",
                    "Audit Packet SHA256: " + "0" * 64,
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Audit Packet SHA256 mismatch", result.stdout)

    def test_packet_prepared_after_audit_start_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            packet = work / "AUDIT_PACKET.md"
            packet.write_text(
                packet.read_text(encoding="utf-8").replace(
                    "Prepared At: 2026-10-27T10:00:00+08:00",
                    "Prepared At: 2026-10-27T11:00:00+08:00",
                ),
                encoding="utf-8",
            )
            report = work / "THIRD_PARTY_AUDIT.md"
            text = report.read_text(encoding="utf-8")
            text = text.replace(field_value(text, "Audit Packet SHA256"), digest(packet))
            report.write_text(text, encoding="utf-8")

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Prepared At must not follow audit Started At", result.stdout)

    def test_missing_or_failed_required_axis_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    "| FALSE_COMPLETION | mocks/placeholders/missing proof | E01, E02, E03 | PASS |\n",
                    "",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("FALSE_COMPLETION", result.stdout)

    def test_incomplete_acceptance_criterion_audit_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    "| AC-02 | E02 | PASS | proven |\n", ""
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Acceptance Criterion Audit", result.stdout)
            self.assertIn("expected 2", result.stdout)

    def test_open_high_finding_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    "High Open: 0", "High Open: 1"
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("High Open", result.stdout)

    def test_same_count_requirement_drift_after_sealing_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            item = work / "WORK_ITEM.md"
            item.write_text(
                item.read_text(encoding="utf-8").replace(
                    "Criterion one.", "Entirely different requirement."
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Acceptance Contract SHA256 mismatch", result.stdout)

    def test_packet_requirement_text_must_equal_work_item(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            packet = work / "AUDIT_PACKET.md"
            old_hash = digest(packet)
            packet.write_text(
                packet.read_text(encoding="utf-8").replace(
                    "| AC-01 | Criterion one. | E02 |",
                    "| AC-01 | Invented requirement. | E02 |",
                ),
                encoding="utf-8",
            )
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    f"Audit Packet SHA256: {old_hash}",
                    f"Audit Packet SHA256: {digest(packet)}",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Requirement must exactly match WORK_ITEM.md", result.stdout)

    def test_nonexistent_acceptance_evidence_reference_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            packet = work / "AUDIT_PACKET.md"
            packet.write_text(
                packet.read_text(encoding="utf-8").replace(
                    "| AC-01 | Criterion one. | E02 |",
                    "| AC-01 | Criterion one. | DOES-NOT-EXIST |",
                ),
                encoding="utf-8",
            )
            report = work / "THIRD_PARTY_AUDIT.md"
            old_hash = field_value(report.read_text(encoding="utf-8"), "Audit Packet SHA256")
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    f"Audit Packet SHA256: {old_hash}",
                    f"Audit Packet SHA256: {digest(packet)}",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unknown evidence reference DOES-NOT-EXIST", result.stdout)

    def test_renamed_receipt_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            receipt = work / "AUDIT_RECEIPT.md"
            renamed = work / "anything.md"
            receipt.rename(renamed)
            report = work / "THIRD_PARTY_AUDIT.md"
            text = report.read_text(encoding="utf-8")
            text = text.replace("Audit Receipt: AUDIT_RECEIPT.md", "Audit Receipt: anything.md")
            text = text.replace(
                field_value(text, "Audit Receipt SHA256"), digest(renamed)
            )
            report.write_text(text, encoding="utf-8")

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("AUDIT_RECEIPT.md", result.stdout)

    def test_truncated_or_mismatched_receipt_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            receipt = work / "AUDIT_RECEIPT.md"
            receipt.write_text(
                "Audit Session ID: reviewer-session-9\n"
                "Auditor Agent: independent-reviewer-9\n"
                "Context Mode: FRESH\n"
                "Mutation Permission: AUDIT_ARTIFACTS_ONLY\n",
                encoding="utf-8",
            )
            report = work / "THIRD_PARTY_AUDIT.md"
            text = report.read_text(encoding="utf-8")
            text = text.replace(
                field_value(text, "Audit Receipt SHA256"), digest(receipt)
            )
            report.write_text(text, encoding="utf-8")

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Auditor Provider / Model must be resolved", result.stdout)
            self.assertIn("Invocation Record", result.stdout)

    def test_mixed_valid_and_invented_evidence_reference_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            packet = work / "AUDIT_PACKET.md"
            old_hash = digest(packet)
            packet.write_text(
                packet.read_text(encoding="utf-8").replace(
                    "| AC-01 | Criterion one. | E02 |",
                    "| AC-01 | Criterion one. | E02, GHOST-EVIDENCE |",
                ),
                encoding="utf-8",
            )
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(old_hash, digest(packet)),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unknown evidence reference GHOST-EVIDENCE", result.stdout)

    def test_review_axis_evidence_must_resolve_to_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    "| REQUIREMENT | requirement contract | E01 | PASS |",
                    "| REQUIREMENT | requirement contract | GHOST-EVIDENCE | PASS |",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("REQUIREMENT Evidence", result.stdout)

    def test_template_identity_and_session_placeholders_block(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            receipt = work / "AUDIT_RECEIPT.md"
            receipt_text = receipt.read_text(encoding="utf-8")
            receipt_text = receipt_text.replace("reviewer-session-9", "SESSION-ID")
            receipt_text = receipt_text.replace("independent-reviewer-9", "AUDITOR-ID")
            receipt_text = receipt_text.replace(
                "independent-agent/default-model", "PROVIDER / MODEL"
            )
            receipt_text = receipt_text.replace(
                "Agent independent-reviewer-9 was started with assigned scope to review the sealed packet read-only.",
                "AUDITOR-ID was started with assigned scope for independent audit.",
            )
            receipt.write_text(receipt_text, encoding="utf-8")
            report = work / "THIRD_PARTY_AUDIT.md"
            text = report.read_text(encoding="utf-8")
            text = text.replace("implementer-session-1", "AGENT-ID")
            text = text.replace("reviewer-session-9", "SESSION-ID")
            text = text.replace("independent-reviewer-9", "AUDITOR-ID")
            text = text.replace("independent-agent/default-model", "PROVIDER / MODEL")
            text = text.replace(field_value(text, "Audit Receipt SHA256"), digest(receipt))
            report.write_text(text, encoding="utf-8")

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must be a concrete identity", result.stdout)

    def test_template_invocation_boilerplate_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            receipt = work / "AUDIT_RECEIPT.md"
            receipt.write_text(
                receipt.read_text(encoding="utf-8").replace(
                    "Agent independent-reviewer-9 was started with assigned scope to review the sealed packet read-only.",
                    "Record how the independent Agent was started and the exact scope it was given. Do not include hidden reasoning or secrets.",
                ),
                encoding="utf-8",
            )
            report = work / "THIRD_PARTY_AUDIT.md"
            text = report.read_text(encoding="utf-8")
            text = text.replace(field_value(text, "Audit Receipt SHA256"), digest(receipt))
            report.write_text(text, encoding="utf-8")

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Invocation Record must describe the actual dispatch", result.stdout)

    def test_none_severity_cannot_hide_open_finding(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    "| AUDIT-NONE | NONE | No blocking finding | NONE | CLOSED | packet review |",
                    "| AUDIT-003 | NONE | Real unresolved issue | Fix it | OPEN | missing |",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Severity NONE is reserved for the sole AUDIT-NONE row", result.stdout)

    def test_external_provider_requires_live_readiness_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            report = work / "THIRD_PARTY_AUDIT.md"
            report.write_text(
                report.read_text(encoding="utf-8").replace(
                    "Audit Mode: INDEPENDENT_AGENT",
                    "Audit Mode: EXTERNAL_PROVIDER",
                ),
                encoding="utf-8",
            )

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("AGENT_PROVIDER_READINESS.md", result.stdout)

    def test_external_provider_nonready_or_unprobed_evidence_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            readiness = work / "AGENT_PROVIDER_READINESS.md"
            write(
                readiness,
                "Provider: claude\n"
                "Provider Mode: EXTERNAL_CLI\n"
                "Provider State: LIVE_CHECK_REQUIRED\n"
                "Ready: NO\n"
                "Live Probe: NOT_RUN\n"
                "Secret Values Recorded: NO\n",
            )
            receipt = work / "AUDIT_RECEIPT.md"
            receipt.write_text(
                receipt.read_text(encoding="utf-8")
                + f"\nProvider Readiness: AGENT_PROVIDER_READINESS.md\n"
                + f"Provider Readiness SHA256: {digest(readiness)}\n",
                encoding="utf-8",
            )
            report = work / "THIRD_PARTY_AUDIT.md"
            text = report.read_text(encoding="utf-8")
            text = text.replace("Audit Mode: INDEPENDENT_AGENT", "Audit Mode: EXTERNAL_PROVIDER")
            text = text.replace(field_value(text, "Audit Receipt SHA256"), digest(receipt))
            text = text.replace(
                "Critical Open: 0",
                f"Provider Readiness: AGENT_PROVIDER_READINESS.md\n"
                f"Provider Readiness SHA256: {digest(readiness)}\n"
                "Critical Open: 0",
            )
            report.write_text(text, encoding="utf-8")

            result = run_gate(root, work)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Provider State must be READY", result.stdout)
            self.assertIn("Live Probe must be PASS", result.stdout)

    def test_external_provider_ready_live_evidence_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            work = create_complete_audit(root)
            readiness = work / "AGENT_PROVIDER_READINESS.md"
            write(
                readiness,
                "Provider: claude\n"
                "Provider Mode: EXTERNAL_CLI\n"
                "Provider State: READY\n"
                "Ready: YES\n"
                "Live Probe: PASS\n"
                "Secret Values Recorded: NO\n",
            )
            receipt = work / "AUDIT_RECEIPT.md"
            receipt.write_text(
                receipt.read_text(encoding="utf-8")
                + f"\nProvider Readiness: AGENT_PROVIDER_READINESS.md\n"
                + f"Provider Readiness SHA256: {digest(readiness)}\n",
                encoding="utf-8",
            )
            report = work / "THIRD_PARTY_AUDIT.md"
            text = report.read_text(encoding="utf-8")
            text = text.replace("Audit Mode: INDEPENDENT_AGENT", "Audit Mode: EXTERNAL_PROVIDER")
            text = text.replace(field_value(text, "Audit Receipt SHA256"), digest(receipt))
            text = text.replace(
                "Critical Open: 0",
                f"Provider Readiness: AGENT_PROVIDER_READINESS.md\n"
                f"Provider Readiness SHA256: {digest(readiness)}\n"
                "Critical Open: 0",
            )
            report.write_text(text, encoding="utf-8")

            result = run_gate(root, work)

            self.assertEqual(result.returncode, 0, result.stdout)


def field_value(text: str, name: str) -> str:
    prefix = f"{name}: "
    return next(line[len(prefix):] for line in text.splitlines() if line.startswith(prefix))


if __name__ == "__main__":
    unittest.main()
