/// <summary>
/// Test codeunit for ALP Work Log Service.
/// Validates work log entry creation, closure, idempotency, and disruption tracking.
/// </summary>
codeunit 50094 "ALP Work Log Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit Assert;
        LibraryRandom: Codeunit "Library - Random";
        LibraryManufacturing: Codeunit "Library - Manufacturing";
        LibraryInventory: Codeunit "Library - Inventory";
        IsInitialized: Boolean;

    local procedure Initialize()
    begin
        if IsInitialized then
            exit;

        IsInitialized := true;
        Commit();
    end;

    local procedure CreateReleasedProductionOrderWithRouting(var ProductionOrder: Record "Production Order"; var OperationNo: Code[10])
    var
        Item: Record Item;
        RoutingHeader: Record "Routing Header";
        RoutingLine: Record "Routing Line";
        WorkCenter: Record "Work Center";
    begin
        // Create Work Center
        LibraryManufacturing.CreateWorkCenter(WorkCenter);

        // Create Routing with one operation
        LibraryManufacturing.CreateRoutingHeader(RoutingHeader, RoutingHeader.Type::Serial);
        LibraryManufacturing.CreateRoutingLine(RoutingHeader, RoutingLine, '', '10', RoutingLine.Type::"Work Center", WorkCenter."No.");
        RoutingHeader.Validate(Status, RoutingHeader.Status::Certified);
        RoutingHeader.Modify(true);

        OperationNo := RoutingLine."Operation No.";

        // Create Item with routing
        LibraryInventory.CreateItem(Item);
        Item.Validate("Routing No.", RoutingHeader."No.");
        Item.Modify(true);

        // Create Released Production Order (will copy routing lines)
        LibraryManufacturing.CreateProductionOrder(
            ProductionOrder,
            ProductionOrder.Status::Released,
            ProductionOrder."Source Type"::Item,
            Item."No.",
            LibraryRandom.RandIntInRange(10, 100));

        // Refresh to create routing lines
        LibraryManufacturing.RefreshProdOrder(ProductionOrder, false, true, true, true, false);
    end;

    local procedure CreateExecutionRecord(OrderNo: Code[20]; OperationNo: Code[10]; Parts: Integer; Rejected: Integer; Availability: Decimal; Productivity: Decimal; SourceTimestamp: DateTime): Record "ALP Operation Execution"
    var
        Exec: Record "ALP Operation Execution";
    begin
        Exec.Init();
        Exec."Order No." := OrderNo;
        Exec."Operation No." := OperationNo;
        Exec."Work Center No." := '';
        Exec."Qty. Produced" := Parts;
        Exec."Qty. Rejected" := Rejected;
        Exec."Runtime Sec" := 3600;
        Exec."Downtime Sec" := 600;
        Exec.Availability := Availability;
        Exec.Productivity := Productivity;
        Exec."Source Timestamp" := SourceTimestamp;
        Exec.Source := 'TEST';
        exit(Exec);
    end;

    local procedure CleanupTestData(MessageId: Guid; OrderNo: Code[20]; OperationNo: Code[10])
    var
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        ALPOperationExecution: Record "ALP Operation Execution";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
    begin
        if ALPIntegrationInbox.Get(MessageId) then
            ALPIntegrationInbox.Delete(true);

        if ALPOperationExecution.Get(OrderNo, OperationNo) then
            ALPOperationExecution.Delete(true);

        ALPWorkLogEntry.SetRange("Order No.", OrderNo);
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        ALPWorkLogEntry.DeleteAll(true);
    end;

    // ==================== START EVENT TESTS ====================

    [Test]
    procedure StartEvent_CreatesWorkLogEntry()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        StartTime: DateTime;
        Result: Boolean;
    begin
        // [SCENARIO] Start event creates a work log entry with Status=Open
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] A start execution event
        MessageId := CreateGuid();
        StartTime := CurrentDateTime;
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, StartTime);

        // [WHEN] The ingestion codeunit is called with eventType=Start
        Result := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId, 'Start', 'OP-001', 'F');

        // [THEN] Function returns true (success)
        Assert.IsTrue(Result, 'ProcessExecutionEvent should return true for Start event');

        // [THEN] A work log entry exists with correct values
        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        Assert.RecordCount(ALPWorkLogEntry, 1);

        ALPWorkLogEntry.FindFirst();
        Assert.AreEqual(Format(MessageId), ALPWorkLogEntry."Message Id", 'Message Id should match');
        Assert.AreEqual('OP-001', ALPWorkLogEntry."Operator Id", 'Operator Id should match');
        Assert.AreEqual('F', ALPWorkLogEntry."Shift Code", 'Shift Code should match');
        Assert.AreEqual(ALPWorkLogEntry."Event Type"::Execution, ALPWorkLogEntry."Event Type", 'Event Type should be Execution');
        Assert.AreEqual(ALPWorkLogEntry.Status::Open, ALPWorkLogEntry.Status, 'Status should be Open');
        Assert.AreEqual(StartTime, ALPWorkLogEntry."Start Time", 'Start Time should match source timestamp');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure StartEvent_SetsStartedAtOnExecution()
    var
        ProductionOrder: Record "Production Order";
        ALPOperationExecution: Record "ALP Operation Execution";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        StartTime: DateTime;
    begin
        // [SCENARIO] Start event sets Started At and Operator Id on the execution record
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] A start execution event
        MessageId := CreateGuid();
        StartTime := CurrentDateTime;
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, StartTime);

        // [WHEN] The ingestion codeunit is called with eventType=Start
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId, 'Start', 'OP-002', 'S');

        // [THEN] Execution record has Started At and Operator Id set
        ALPOperationExecution.Get(ProductionOrder."No.", OperationNo);
        Assert.AreEqual(StartTime, ALPOperationExecution."Started At", 'Started At should match source timestamp');
        Assert.AreEqual('OP-002', ALPOperationExecution."Operator Id", 'Operator Id should match');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    // ==================== END EVENT TESTS ====================

    [Test]
    procedure EndEvent_ClosesWorkLogEntry()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        ExecStart: Record "ALP Operation Execution";
        ExecEnd: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        StartMessageId: Guid;
        EndMessageId: Guid;
        OperationNo: Code[10];
        StartTime: DateTime;
        EndTime: DateTime;
    begin
        // [SCENARIO] End event closes the open work log entry and computes duration
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] A start event has been processed
        StartMessageId := CreateGuid();
        StartTime := CurrentDateTime - 3600000; // 1 hour ago
        ExecStart := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, StartTime);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(ExecStart, StartMessageId, 'Start', 'OP-001', 'F');

        // [WHEN] An end event is processed
        EndMessageId := CreateGuid();
        EndTime := CurrentDateTime;
        ExecEnd := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 5, 0.85, 0.90, EndTime);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(ExecEnd, EndMessageId, 'End', 'OP-001', 'F');

        // [THEN] Work log entry is closed
        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        ALPWorkLogEntry.SetRange(Status, ALPWorkLogEntry.Status::Closed);
        Assert.RecordCount(ALPWorkLogEntry, 1);

        ALPWorkLogEntry.FindFirst();
        Assert.AreEqual(EndTime, ALPWorkLogEntry."End Time", 'End Time should match');
        Assert.IsTrue(ALPWorkLogEntry."Duration Sec" > 0, 'Duration should be positive');

        // Cleanup
        CleanupTestData(StartMessageId, ProductionOrder."No.", OperationNo);
        CleanupTestData(EndMessageId, ProductionOrder."No.", OperationNo);
    end;

    // ==================== IDEMPOTENCY TESTS ====================

    [Test]
    procedure Idempotency_DuplicateStartMessage_CreatesOnlyOneWorkLog()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        Exec1: Record "ALP Operation Execution";
        Exec2: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        StartTime: DateTime;
    begin
        // [SCENARIO] Same start event with same MessageId creates only one work log entry
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Same MessageId for both calls
        MessageId := CreateGuid();
        StartTime := CurrentDateTime;

        // [WHEN] Start event is ingested twice with same MessageId
        Exec1 := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, StartTime);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec1, MessageId, 'Start', 'OP-001', 'F');

        Exec2 := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, StartTime);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec2, MessageId, 'Start', 'OP-001', 'F');

        // [THEN] Only one work log entry exists
        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        Assert.RecordCount(ALPWorkLogEntry, 1);

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    // ==================== DISRUPTION TESTS ====================

    [Test]
    procedure Disruption_CreateWorkLogEntry_WithDisruptionType()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        WorkLogSvc: Codeunit "ALP Work Log Svc";
        WorkLogEventType: Enum "ALP Work Log Event Type";
        OperationNo: Code[10];
        StartTime: DateTime;
        DisruptionMessageId: Text[50];
    begin
        // [SCENARIO] Disruption work log entry is created with EventType=Disruption
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [WHEN] A disruption work log entry is created directly via the service
        DisruptionMessageId := Format(CreateGuid());
        StartTime := CurrentDateTime;
        WorkLogSvc.CreateWorkLogEntry(
            DisruptionMessageId,
            ProductionOrder."No.",
            OperationNo,
            '',
            'OP-001',
            '',
            'F',
            WorkLogEventType::Disruption,
            'MECH-FAIL',
            StartTime,
            'TEST');

        // [THEN] Work log entry exists with Disruption event type
        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        Assert.RecordCount(ALPWorkLogEntry, 1);

        ALPWorkLogEntry.FindFirst();
        Assert.AreEqual(ALPWorkLogEntry."Event Type"::Disruption, ALPWorkLogEntry."Event Type", 'Event Type should be Disruption');
        Assert.AreEqual('MECH-FAIL', ALPWorkLogEntry."Disruption Code", 'Disruption Code should match');
        Assert.AreEqual(ALPWorkLogEntry.Status::Open, ALPWorkLogEntry.Status, 'Status should be Open');

        // Cleanup
        ALPWorkLogEntry.DeleteAll(true);
    end;

    [Test]
    procedure Disruption_CloseWorkLogEntry_ComputesDuration()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        WorkLogSvc: Codeunit "ALP Work Log Svc";
        WorkLogEventType: Enum "ALP Work Log Event Type";
        OperationNo: Code[10];
        StartTime: DateTime;
        EndTime: DateTime;
        DisruptionMessageId: Text[50];
    begin
        // [SCENARIO] Closing a disruption work log entry computes duration
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] An open disruption work log entry
        DisruptionMessageId := Format(CreateGuid());
        StartTime := CurrentDateTime - 1800000; // 30 minutes ago
        WorkLogSvc.CreateWorkLogEntry(
            DisruptionMessageId,
            ProductionOrder."No.",
            OperationNo,
            '',
            'OP-001',
            '',
            'F',
            WorkLogEventType::Disruption,
            'MECH-FAIL',
            StartTime,
            'TEST');

        // [WHEN] The disruption work log entry is closed
        EndTime := CurrentDateTime;
        WorkLogSvc.CloseWorkLogEntry(ProductionOrder."No.", OperationNo, WorkLogEventType::Disruption, EndTime);

        // [THEN] Work log entry is closed with computed duration
        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        ALPWorkLogEntry.FindFirst();

        Assert.AreEqual(ALPWorkLogEntry.Status::Closed, ALPWorkLogEntry.Status, 'Status should be Closed');
        Assert.AreEqual(EndTime, ALPWorkLogEntry."End Time", 'End Time should match');
        Assert.IsTrue(ALPWorkLogEntry."Duration Sec" > 0, 'Duration should be positive');

        // Cleanup
        ALPWorkLogEntry.DeleteAll(true);
    end;

    [Test]
    procedure DisruptionEndEvent_ClosesOpenDisruptionWorkLog()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        StartMessageId: Guid;
        EndMessageId: Guid;
        OperationNo: Code[10];
        StartTime: DateTime;
        EndTime: DateTime;
    begin
        // [SCENARIO] DisruptionEnd routed through ingestion closes the open disruption work log
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] A disruption start event has opened a disruption work log
        StartMessageId := CreateGuid();
        StartTime := CurrentDateTime - 1800000; // 30 minutes ago
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, StartTime);
        Exec."Source Timestamp" := StartTime;
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, StartMessageId, 'DisruptionStart', 'OP-001', 'F');

        // [WHEN] A disruption end event is ingested for the same order/operation
        EndMessageId := CreateGuid();
        EndTime := CurrentDateTime;
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, EndTime);
        Exec."Source Timestamp" := EndTime;
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, EndMessageId, 'DisruptionEnd', 'OP-001', 'F');

        // [THEN] The disruption work log is closed with a duration
        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        ALPWorkLogEntry.SetRange("Event Type", ALPWorkLogEntry."Event Type"::Disruption);
        Assert.RecordCount(ALPWorkLogEntry, 1);

        ALPWorkLogEntry.FindFirst();
        Assert.AreEqual(ALPWorkLogEntry.Status::Closed, ALPWorkLogEntry.Status, 'Status should be Closed');
        Assert.AreEqual(EndTime, ALPWorkLogEntry."End Time", 'End Time should match');
        Assert.IsTrue(ALPWorkLogEntry."Duration Sec" > 0, 'Duration should be positive');

        // Cleanup
        ALPWorkLogEntry.DeleteAll(true);
    end;

    [Test]
    procedure CorrectionService_ReplaceInterval_UpdatesDisruptionWorkLog()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        Correction: Record "ALP Execution Correction";
        WorkLogSvc: Codeunit "ALP Work Log Svc";
        CorrectionSvc: Codeunit "ALP Execution Correction Svc";
        WorkLogEventType: Enum "ALP Work Log Event Type";
        OperationNo: Code[10];
        StartTime: DateTime;
        EndTime: DateTime;
        NewStartTime: DateTime;
        NewEndTime: DateTime;
        MessageId: Text[50];
    begin
        Initialize();
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        StartTime := CurrentDateTime - 3600000;
        EndTime := CurrentDateTime - 1800000;
        MessageId := Format(CreateGuid());
        WorkLogSvc.CreateWorkLogEntry(
            MessageId,
            ProductionOrder."No.",
            OperationNo,
            '',
            'OP-001',
            '',
            'F',
            WorkLogEventType::Disruption,
            'MECH-FAIL',
            StartTime,
            'TEST');
        WorkLogSvc.CloseWorkLogEntry(ProductionOrder."No.", OperationNo, WorkLogEventType::Disruption, EndTime);

        NewStartTime := CurrentDateTime - 3000000;
        NewEndTime := CurrentDateTime - 1200000;

        Correction.Init();
        Correction."Correction Id" := Format(CreateGuid());
        Correction.Action := 'replace_interval';
        Correction."Requested By" := 'alice.admin';
        Correction."Requested At" := CurrentDateTime;
        Correction."Order No." := ProductionOrder."No.";
        Correction."Operation No." := OperationNo;
        Correction."Event Type" := 'Disruption';
        Correction."Replacement Start Time" := NewStartTime;
        Correction."Replacement End Time" := NewEndTime;
        Correction."Operator Id" := 'OP-999';
        Correction."Shift Code" := 'S';

        Assert.IsTrue(CorrectionSvc.ProcessCorrection(Correction), 'Correction should succeed');

        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        ALPWorkLogEntry.SetRange("Event Type", ALPWorkLogEntry."Event Type"::Disruption);
        ALPWorkLogEntry.FindLast();

        Assert.AreEqual(NewStartTime, ALPWorkLogEntry."Start Time", 'Start Time should be replaced');
        Assert.AreEqual(NewEndTime, ALPWorkLogEntry."End Time", 'End Time should be replaced');
        Assert.AreEqual('OP-999', ALPWorkLogEntry."Operator Id", 'Operator Id should be replaced');
        Assert.AreEqual('S', ALPWorkLogEntry."Shift Code", 'Shift Code should be replaced');
    end;

    // ==================== OPERATOR AND SHIFT PERSISTENCE TESTS ====================

    [Test]
    procedure OperatorAndShift_PersistedOnWorkLogEntry()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
    begin
        // [SCENARIO] Operator Id and Shift Code are persisted on work log entries
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] A start event with operator and shift
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, CurrentDateTime);

        // [WHEN] Start event is processed with operator and shift
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId, 'Start', 'OP-SHIFT-1', 'T');

        // [THEN] Work log entry has operator and shift
        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        ALPWorkLogEntry.FindFirst();

        Assert.AreEqual('OP-SHIFT-1', ALPWorkLogEntry."Operator Id", 'Operator Id should be persisted');
        Assert.AreEqual('T', ALPWorkLogEntry."Shift Code", 'Shift Code should be persisted');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure DefaultEventType_BackwardCompatible()
    var
        ProductionOrder: Record "Production Order";
        ALPOperationExecution: Record "ALP Operation Execution";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        Result: Boolean;
    begin
        // [SCENARIO] Default (empty) eventType behaves as End event for backward compatibility
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] A valid execution payload with no eventType (backward compat)
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 5, 0.85, 0.90, CurrentDateTime);

        // [WHEN] The old-style single-parameter overload is called
        Result := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Function returns true (success)
        Assert.IsTrue(Result, 'ProcessExecutionEvent should return true');

        // [THEN] Execution record exists with KPI values
        ALPOperationExecution.Get(ProductionOrder."No.", OperationNo);
        Assert.AreEqual(100, ALPOperationExecution."Qty. Produced", 'Qty. Produced should match');
        Assert.AreEqual(5, ALPOperationExecution."Qty. Rejected", 'Qty. Rejected should match');

        // [THEN] Inbox is processed
        Assert.IsTrue(ALPIntegrationInbox.Get(MessageId), 'Inbox entry should exist');
        Assert.AreEqual(
            ALPIntegrationInbox.Status::Processed,
            ALPIntegrationInbox.Status,
            'Inbox status should be Processed');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure StartEvent_SkipsKPIAggregation()
    var
        ProductionOrder: Record "Production Order";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
    begin
        // [SCENARIO] Start event does not trigger KPI aggregation on the production order
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] A start execution event
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, CurrentDateTime);

        // [WHEN] Start event is processed
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId, 'Start', 'OP-001', 'F');

        // [THEN] Production Order aggregate KPIs remain at zero
        ProductionOrder.Get(ProductionOrder.Status, ProductionOrder."No.");
        Assert.AreEqual(0, ProductionOrder."ALP Exec Qty. Produced", 'Aggregate Qty. Produced should remain 0 after Start');
        Assert.AreEqual(0, ProductionOrder."ALP Exec Qty. Rejected", 'Aggregate Qty. Rejected should remain 0 after Start');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;
}
