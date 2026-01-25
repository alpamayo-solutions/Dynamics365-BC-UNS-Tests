# UNS Bridge Connector Test Suite

Automated tests for the [UNS Bridge Connector](https://github.com/alpamayo-solutions/Dynamics365-BC-UNS) Business Central extension.

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
- UNS Topic Mapping CRUD operations work correctly
- All API pages and reference data endpoints exist

## Test Categories

### 1. Installation Tests (`ALPInstallTests.Codeunit.al`) - ID 50092
- Tables, enums, codeunits, pages exist after installation
- Extension fields added to Production Order and Routing Line
- Permission sets exist
- Clean uninstall pattern (no cascading relationships)
- Primary keys are stable for upgrade compatibility
- All API pages exist (Execution Events, Work Centers, Production Orders, Routings, Items, etc.)
- Report exists (Daily Exec Performance)

### 2. Permission Tests (`ALPPermissionsTests.Codeunit.al`) - ID 50091
- Permission sets exist in metadata
- Tables are accessible with proper permissions
- Codeunits are accessible
- UNS Topic Mapping table is accessible

### 3. Ingestion Tests (`ALPExecutionIngestionTests.Codeunit.al`) - ID 50090
- **Happy path**: Valid execution creates records, updates routing lines and production orders
- **Idempotency**: Duplicate MessageId does not create duplicate records
- **Out-of-order**: Older timestamps don't overwrite newer data
- **Validation**: Invalid input (rejected > produced, availability/productivity out of range) is rejected
- **Atomicity**: Failed ingestion leaves no partial data
- **Aggregation**: Sums and weighted averages calculated correctly

### 4. UNS Topic Mapping Tests (`ALPUNSTopicMappingTests.Codeunit.al`) - ID 50093
- **CRUD**: Create, Read, Update, Delete operations work correctly
- **Validation**: Empty topic fails, duplicate topics fail
- **Auto-discovery**: Work Center is optional for discovered-but-unmapped topics
- **Validity dates**: Valid From/To dates are respected, open-ended mappings allowed
- **Audit fields**: Created At, Modified At timestamps are set automatically
- **Table stability**: All required fields exist

## Running the Tests

### Option 1: Using Test Tool in Business Central

1. **Publish the main app first** (if not already):
   ```
   VS Code → Cmd+Shift+P → AL: Publish without Debugging
   ```

2. **Open the test project** in VS Code:
   ```bash
   code /path/to/d365_uns_app_test
   ```

3. **Download symbols**: `Cmd+Shift+P` → `AL: Download Symbols`

4. **Publish the test app**: `Cmd+Shift+P` → `AL: Publish without Debugging`

5. **Run tests in BC**:
   - Open Business Central
   - Search for **Test Tool**
   - Select the test codeunits (50090, 50091, 50092, 50093)
   - Click **Run Selected**

### Option 2: Using BCContainerHelper (PowerShell)

```powershell
# Run all test codeunits
Run-TestsInBcContainer -containerName mybc -credential $cred -testCodeunit 50090  # Ingestion
Run-TestsInBcContainer -containerName mybc -credential $cred -testCodeunit 50091  # Permissions
Run-TestsInBcContainer -containerName mybc -credential $cred -testCodeunit 50092  # Install
Run-TestsInBcContainer -containerName mybc -credential $cred -testCodeunit 50093  # UNS Mapping
```

### Option 3: Run with Debugger (for troubleshooting)

1. Open the test project in VS Code
2. Set breakpoints in test methods
3. Press `F5` to start debugging
4. In BC, open Test Tool and run the test - debugger will attach

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

- UNS Bridge Connector extension (main app)
- Microsoft Library Assert
- Microsoft Tests-TestLibraries (Library - Random, Library - Manufacturing, Library - Inventory)

## Test Data

All tests:
- Create their own test data (no reliance on demo data)
- Clean up after themselves
- Are deterministic and repeatable
- Run on a clean BC Premium sandbox

## Object Coverage

| Object Type | ID | Name | Tested |
|-------------|-----|------|--------|
| Table | 50001 | ALP Integration Inbox | Yes |
| Table | 50002 | ALP Operation Execution | Yes |
| Table | 50005 | ALP UNS Topic Mapping | Yes |
| Enum | 50000 | ALP Integration Status | Yes |
| Enum | 50001 | ALP UNS Mapping Status | Yes |
| Codeunit | 50010 | ALP Execution Ingestion Svc | Yes |
| Codeunit | 50012 | ALP Execution Calc Svc | Yes |
| Page | 50020 | ALP Integration Inbox List | Yes |
| Page | 50023 | ALP UNS Topic Mapping List | Yes |
| Page | 50030 | ALP Execution Events API | Yes |
| Page | 50031 | ALP Work Centers API | Yes |
| Page | 50032 | ALP Production Orders API | Yes |
| Page | 50033 | ALP Prod Order Routing API | Yes |
| Page | 50034 | ALP Prod Order Components API | Yes |
| Page | 50036 | ALP Integration Inbox API | Yes |
| Page | 50037 | ALP Routings API | Yes |
| Page | 50038 | ALP Items API | Yes |
| Page | 50039 | ALP UNS Topic Mapping API | Yes |
| PermissionSet | 50040 | ALP Shopfloor View | Yes |
| PermissionSet | 50041 | ALP Shopfloor Exec | Yes |
| Report | 50051 | ALP Daily Exec Performance | Yes |

## AppSource Compliance

An AppSource reviewer can understand from these tests:
- What is being tested (safety, idempotency, resilience)
- Why it matters (app doesn't break the system, data is consistent)
- What risks are mitigated (duplicates, out-of-order, partial writes)

## Related Repositories

| Repository | Description |
|------------|-------------|
| [Dynamics365-BC-UNS](https://github.com/alpamayo-solutions/Dynamics365-BC-UNS) | Main UNS Bridge Connector extension (app under test) |
