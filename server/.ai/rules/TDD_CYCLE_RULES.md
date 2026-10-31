# Strict RED-GREEN Cycle Rules

Behavior-changing implementation follows an observed `RED → GREEN → REFACTOR → REGRESSION` sequence for every implementation task.

## RED

- Write or select the smallest test that expresses the missing behavior before production implementation.
- Run it through `.ai/scripts/execution_journal.py` and observe a non-zero exit classified exactly as `EXPECTED_ASSERTION_FAILURE`.
- Syntax, import, collection, dependency, environment, timeout and infrastructure failures are not RED.
- A test that passes on its first run proves no missing behavior and blocks implementation until the test is corrected.

## GREEN and REFACTOR

- GREEN must run the same selector as RED and pass after the minimum production change.
- REFACTOR occurs only while the selector remains green.
- REGRESSION runs the risk-appropriate required suite and must pass.
- The hash-chained journal and log SHA-256 values are acceptance evidence; replacing, reordering or editing them invalidates the cycle. Events also bind the test-source hash, production paths, RED baseline Git commit and later production snapshot; duplicate stages and post-hoc RED recreation are rejected.

## Applicability

Behavior changes are `REQUIRED`. Only `DOCS_ONLY`, `DECLARATIVE_CONFIG`, `GENERATED`, and `THROWAWAY_PROTOTYPE` may be classified not applicable, with a task-specific rationale. A classification is not a general waiver.

`validate_execution_discipline.py --phase ready` validates the plan. `--phase accept` validates observed execution. Final test PASS cannot repair a missing RED.
