# ShopfloorExecutionBridge Test Suite

Automated tests for the ShopfloorExecutionBridge Business Central extension.

## Purpose

**These tests prove AppSource safety and compliance, not business correctness.**

The test suite validates:
- App installs/uninstalls safely without leaving orphan data
- Schema is stable across upgrades (primary keys don't change)
- Ingestion is idempotent (same message processed twice has no side effects)
- Out-of-order messages are handled correctly
- Invalid input is rejected with clear error messages
- Failed operations leave no partial data (atomicity)
- Aggregations are structurally correct (not semantically validated)

## Test Categories

### 1. Installation Tests (`ALPInstallTests.Codeunit.al`)
- Tables, enums, codeunits, pages exist after installation
- Extension fields added to Production Order and Routing Line
- Permission sets exist
- Clean uninstall pattern (no cascading relationships)
- Primary keys are stable for upgrade compatibility

### 2. Permission Tests (`ALPPermissionsTests.Codeunit.al`)
- Permission sets exist in metadata
- Tables are accessible with proper permissions
- Codeunits are accessible

### 3. Ingestion Tests (`ALPExecutionIngestionTests.Codeunit.al`)
- **Happy path**: Valid execution creates records, updates routing lines and production orders
- **Idempotency**: Duplicate MessageId does not create duplicate records
- **Out-of-order**: Older timestamps don't overwrite newer data
- **Validation**: Invalid input (rejected > produced, availability/productivity out of range) is rejected
- **Atomicity**: Failed ingestion leaves no partial data
- **Aggregation**: Sums and weighted averages calculated correctly

## Running the Tests

1. **Download symbols**: In VS Code, run `AL: Download Symbols`
2. **Compile**: Build the test app (should have no errors)
3. **Deploy**: Publish the test app to a BC Premium sandbox
4. **Run**: Use Test Tool page or BCContainerHelper to run tests

```powershell
# Using BCContainerHelper
Run-TestsInBcContainer -containerName mybc -credential $cred -testCodeunit 50090
Run-TestsInBcContainer -containerName mybc -credential $cred -testCodeunit 50091
Run-TestsInBcContainer -containerName mybc -credential $cred -testCodeunit 50092
```

## What is NOT Tested

Per the testing philosophy, these tests intentionally do NOT:
- Test ERP posting logic
- Test financial correctness
- Benchmark performance
- Validate business meaning of KPIs
- Test "is this KPI good" (only "is aggregation consistent")
- Rely on undocumented system behavior
- Bypass validation logic for convenience

## Dependencies

- ShopfloorExecutionBridge extension (main app)
- Microsoft Library Assert
- Microsoft Tests-TestLibraries (Library - Random, Library - Manufacturing, Library - Inventory)

## Test Data

All tests:
- Create their own test data (no reliance on demo data)
- Clean up after themselves
- Are deterministic and repeatable
- Run on a clean BC Premium sandbox

## AppSource Compliance

An AppSource reviewer can understand from these tests:
- What is being tested (safety, idempotency, resilience)
- Why it matters (app doesn't break the system, data is consistent)
- What risks are mitigated (duplicates, out-of-order, partial writes)
