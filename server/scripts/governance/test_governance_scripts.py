import importlib.util
from pathlib import Path
import unittest


HERE = Path(__file__).resolve().parent


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


rules = load("validate_business_rules")
inventory = load("generate_backend_contract_inventory")


class BusinessRulesValidationTest(unittest.TestCase):
    def test_rejects_duplicate_and_incomplete_rules(self):
        payload = {
            "invariants": [
                {"id": "INV-ORDER-001", "status": "ENFORCED", "capability": "orders", "owner": "OrderService", "rule": "x", "verification": "test"},
                {"id": "INV-ORDER-001", "status": "TARGET", "capability": "", "owner": "OrderService", "rule": "y", "verification": "test"},
            ]
        }
        errors = rules.validate_payload(payload)
        self.assertTrue(any("duplicate invariant id" in error for error in errors))
        self.assertTrue(any("missing non-empty capability" in error for error in errors))

    def test_markdown_requires_exact_id_set(self):
        payload = {"invariants": [{"id": "INV-ORDER-001"}]}
        errors = rules.validate_markdown(payload, "### INV-PRICE-001\n")
        self.assertEqual(2, len(errors))

    def test_rejects_unknown_enforcement_status(self):
        payload = {
            "invariants": [
                {"id": "INV-ORDER-001", "status": "MAYBE", "capability": "orders", "owner": "OrderService", "rule": "x", "verification": "test"}
            ]
        }
        self.assertTrue(any("status must be one of" in error for error in rules.validate_payload(payload)))


class ContractInventoryTest(unittest.TestCase):
    def test_extracts_openapi_paths(self):
        self.assertEqual(["/a", "/b/{id}"], inventory.openapi_paths("  /b/{id}:\n  /a:\n"))

    def test_extracts_permission_mapping(self):
        text = 'add(METHOD_POST, "/cashier/order/refund", "cashier:operate");'
        self.assertEqual(
            [("POST", "/cashier/order/refund", "cashier:operate")],
            inventory.permission_mappings(text),
        )


if __name__ == "__main__":
    unittest.main()
