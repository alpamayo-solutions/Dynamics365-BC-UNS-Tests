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
        Assert.AreEqual(Format(EndMessageId), ALPWorkLogEntry."End Message Id", 'End Message Id should match end event');
        Assert.IsTrue(ALPWorkLogEntry."Duration Sec" > 0, 'Duration should be positive');

        // Cleanup
        CleanupTestData(StartMessageId, ProductionOrder."No.", OperationNo);
        CleanupTestData(EndMessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure ExecutionEvents_UseSourceEventIdsForWorkLogStartAndEnd()
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
        SourceStartEventId: Text[50];
        SourceEndEventId: Text[50];
    begin
        Initialize();
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        StartMessageId := CreateGuid();
        EndMessageId := CreateGuid();
        SourceStartEventId := CopyStr('start-' + Format(StartMessageId), 1, MaxStrLen(SourceStartEventId));
        SourceEndEventId := CopyStr('end-' + Format(EndMessageId), 1, MaxStrLen(SourceEndEventId));
        StartTime := CurrentDateTime - 3600000;
        EndTime := CurrentDateTime - 1800000;

        ExecStart := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, StartTime);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(ExecStart, StartMessageId, 'Start', 'OP-001', 'F', SourceStartEventId);

        ExecEnd := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 10, 0, 0.9, 0.8, EndTime);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(ExecEnd, EndMessageId, 'End', 'OP-001', 'F', SourceEndEventId);

        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        Assert.RecordCount(ALPWorkLogEntry, 1);
        ALPWorkLogEntry.FindFirst();
        Assert.AreEqual(SourceStartEventId, ALPWorkLogEntry."Message Id", 'Start source event id should be stored as work-log Message Id');
        Assert.AreEqual(SourceEndEventId, ALPWorkLogEntry."End Message Id", 'End source event id should be stored as work-log End Message Id');

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

    [Test]
    procedure Idempotency_DuplicateSourceStartEvent_CreatesOneInboxAndOneWorkLog()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId1: Guid;
        MessageId2: Guid;
        OperationNo: Code[10];
        SourceEventId: Text[50];
    begin
        Initialize();
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        MessageId1 := CreateGuid();
        MessageId2 := CreateGuid();
        SourceEventId := CopyStr('start-' + Format(MessageId1), 1, MaxStrLen(SourceEventId));
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, CurrentDateTime);

        Assert.IsTrue(ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId1, 'Start', 'OP-001', 'F', SourceEventId), 'First source event should process');
        Assert.IsTrue(ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId2, 'Start', 'OP-001', 'F', SourceEventId), 'Duplicate source event should be idempotent');

        ALPWorkLogEntry.SetRange("Message Id", SourceEventId);
        Assert.RecordCount(ALPWorkLogEntry, 1);

        ALPIntegrationInbox.SetRange("Source Event Id", SourceEventId);
        Assert.RecordCount(ALPIntegrationInbox, 1);

        CleanupTestData(MessageId1, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure PostHocEnd_ClosesHistoricalWorkLogWhenCurrentStateIsNewer()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        ALPOperationExecution: Record "ALP Operation Execution";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        OperationNo: Code[10];
        CurrentStart: DateTime;
        CurrentEnd: DateTime;
        HistoricalStart: DateTime;
        HistoricalEnd: DateTime;
        CurrentStartId: Text[50];
        CurrentEndId: Text[50];
        HistoricalStartId: Text[50];
        HistoricalEndId: Text[50];
    begin
        Initialize();
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        CurrentStart := CurrentDateTime - 3600000;
        CurrentEnd := CurrentDateTime - 1800000;
        HistoricalStart := CurrentDateTime - 7200000;
        HistoricalEnd := CurrentDateTime - 5400000;
        CurrentStartId := CopyStr('current-start-' + Format(CreateGuid()), 1, MaxStrLen(CurrentStartId));
        CurrentEndId := CopyStr('current-end-' + Format(CreateGuid()), 1, MaxStrLen(CurrentEndId));
        HistoricalStartId := CopyStr('history-start-' + Format(CreateGuid()), 1, MaxStrLen(HistoricalStartId));
        HistoricalEndId := CopyStr('history-end-' + Format(CreateGuid()), 1, MaxStrLen(HistoricalEndId));

        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, CurrentStart);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, CreateGuid(), 'Start', 'OP-001', 'F', CurrentStartId);
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 10, 0, 0.9, 0.8, CurrentEnd);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, CreateGuid(), 'End', 'OP-001', 'F', CurrentEndId);

        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, HistoricalStart);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, CreateGuid(), 'Start', 'OP-001', 'F', HistoricalStartId);
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 5, 0, 0.9, 0.8, HistoricalEnd);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, CreateGuid(), 'End', 'OP-001', 'F', HistoricalEndId);

        ALPWorkLogEntry.SetRange("Message Id", HistoricalStartId);
        ALPWorkLogEntry.FindFirst();
        Assert.AreEqual(ALPWorkLogEntry.Status::Closed, ALPWorkLogEntry.Status, 'Historical interval should close even when current-state timestamp is newer');
        Assert.AreEqual(HistoricalEndId, ALPWorkLogEntry."End Message Id", 'Historical end source event id should be stored');

        ALPOperationExecution.Get(ProductionOrder."No.", OperationNo);
        Assert.AreEqual(CurrentEnd, ALPOperationExecution."Source Timestamp", 'Current-state execution timestamp must not regress');

        ALPWorkLogEntry.Reset();
        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        ALPWorkLogEntry.DeleteAll(true);
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
        WorkLogSvc.CloseWorkLogEntryWithEndMessageId(ProductionOrder."No.", OperationNo, WorkLogEventType::Disruption, EndTime, 'disruption-end-msg');

        // [THEN] Work log entry is closed with computed duration
        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        ALPWorkLogEntry.FindFirst();

        Assert.AreEqual(ALPWorkLogEntry.Status::Closed, ALPWorkLogEntry.Status, 'Status should be Closed');
        Assert.AreEqual(EndTime, ALPWorkLogEntry."End Time", 'End Time should match');
        Assert.AreEqual('disruption-end-msg', ALPWorkLogEntry."End Message Id", 'End Message Id should match');
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
        Assert.AreEqual(Format(EndMessageId), ALPWorkLogEntry."End Message Id", 'End Message Id should match');
        Assert.IsTrue(ALPWorkLogEntry."Duration Sec" > 0, 'Duration should be positive');

        // Cleanup
        ALPWorkLogEntry.DeleteAll(true);
    end;

    [Test]
    procedure CorrectionService_ReplaceInterval_SupersedesOriginalAndCreatesReplacement()
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
        EndMessageId: Text[50];
        OriginalEntryNo: Integer;
    begin
        Initialize();
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        StartTime := CurrentDateTime - 3600000;
        EndTime := CurrentDateTime - 1800000;
        MessageId := Format(CreateGuid());
        EndMessageId := Format(CreateGuid());
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
        WorkLogSvc.CloseWorkLogEntryWithEndMessageId(ProductionOrder."No.", OperationNo, WorkLogEventType::Disruption, EndTime, EndMessageId);

        ALPWorkLogEntry.SetRange("Message Id", MessageId);
        ALPWorkLogEntry.FindFirst();
        OriginalEntryNo := ALPWorkLogEntry."Entry No.";

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
        Correction."Target Event Ids" := MessageId;
        Correction."Replacement Start Time" := NewStartTime;
        Correction."Replacement End Time" := NewEndTime;
        Correction."Operator Id" := 'OP-999';
        Correction."Shift Code" := 'S';

        Assert.IsTrue(CorrectionSvc.ProcessCorrection(Correction), 'Correction should succeed');

        ALPWorkLogEntry.Reset();
        ALPWorkLogEntry.Get(OriginalEntryNo);
        Assert.AreEqual(ALPWorkLogEntry.Status::Superseded, ALPWorkLogEntry.Status, 'Original should be superseded');
        Assert.AreEqual(Correction."Correction Id", ALPWorkLogEntry."Invalidated By Correction Id", 'Original should link to correction');

        ALPWorkLogEntry.Reset();
        ALPWorkLogEntry.SetRange("Order No.", ProductionOrder."No.");
        ALPWorkLogEntry.SetRange("Operation No.", OperationNo);
        ALPWorkLogEntry.SetRange("Event Type", ALPWorkLogEntry."Event Type"::Disruption);
        ALPWorkLogEntry.SetRange("Correction Id", Correction."Correction Id");
        ALPWorkLogEntry.FindLast();

        Assert.AreEqual(NewStartTime, ALPWorkLogEntry."Start Time", 'Start Time should be replaced');
        Assert.AreEqual(NewEndTime, ALPWorkLogEntry."End Time", 'End Time should be replaced');
        Assert.AreEqual('OP-999', ALPWorkLogEntry."Operator Id", 'Operator Id should be replaced');
        Assert.AreEqual('S', ALPWorkLogEntry."Shift Code", 'Shift Code should be replaced');
        Assert.AreEqual(OriginalEntryNo, ALPWorkLogEntry."Replaces Entry No.", 'Replacement should link to original');
        Assert.AreEqual(ALPWorkLogEntry.Status::Closed, ALPWorkLogEntry.Status, 'Replacement should be closed');
    end;

    [Test]
    procedure CorrectionService_CancelEvent_MarksTargetCancelled()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        Correction: Record "ALP Execution Correction";
        WorkLogSvc: Codeunit "ALP Work Log Svc";
        CorrectionSvc: Codeunit "ALP Execution Correction Svc";
        WorkLogEventType: Enum "ALP Work Log Event Type";
        OperationNo: Code[10];
        MessageId: Text[50];
        EndMessageId: Text[50];
        OriginalEntryNo: Integer;
    begin
        Initialize();
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        MessageId := Format(CreateGuid());
        EndMessageId := Format(CreateGuid());
        WorkLogSvc.CreateWorkLogEntry(
            MessageId,
            ProductionOrder."No.",
            OperationNo,
            '',
            'OP-001',
            '',
            'F',
            WorkLogEventType::Execution,
            '',
            CurrentDateTime - 3600000,
            'TEST');
        WorkLogSvc.CloseWorkLogEntryWithEndMessageId(ProductionOrder."No.", OperationNo, WorkLogEventType::Execution, CurrentDateTime - 1800000, EndMessageId);

        ALPWorkLogEntry.SetRange("Message Id", MessageId);
        ALPWorkLogEntry.FindFirst();
        OriginalEntryNo := ALPWorkLogEntry."Entry No.";

        Correction.Init();
        Correction."Correction Id" := Format(CreateGuid());
        Correction.Action := 'cancel_event';
        Correction."Target Event Ids" := EndMessageId;
        Correction."Requested By" := 'alice.admin';
        Correction."Requested At" := CurrentDateTime;
        Correction."Order No." := ProductionOrder."No.";
        Correction."Operation No." := OperationNo;
        Correction."Event Type" := 'Execution';

        Assert.IsTrue(CorrectionSvc.ProcessCorrection(Correction), 'Correction should succeed');

        ALPWorkLogEntry.Reset();
        ALPWorkLogEntry.Get(OriginalEntryNo);
        Assert.AreEqual(ALPWorkLogEntry.Status::Cancelled, ALPWorkLogEntry.Status, 'Original should be cancelled');
        Assert.AreEqual(Correction."Correction Id", ALPWorkLogEntry."Invalidated By Correction Id", 'Original should link to correction');
    end;

    [Test]
    procedure CorrectionService_ChangeMetadata_PreservesOriginalInterval()
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
        MessageId: Text[50];
        OriginalEntryNo: Integer;
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
            WorkLogEventType::Execution,
            '',
            StartTime,
            'TEST');
        WorkLogSvc.CloseWorkLogEntryWithEndMessageId(ProductionOrder."No.", OperationNo, WorkLogEventType::Execution, EndTime, Format(CreateGuid()));

        ALPWorkLogEntry.SetRange("Message Id", MessageId);
        ALPWorkLogEntry.FindFirst();
        OriginalEntryNo := ALPWorkLogEntry."Entry No.";

        Correction.Init();
        Correction."Correction Id" := Format(CreateGuid());
        Correction.Action := 'change_metadata';
        Correction."Target Event Ids" := MessageId;
        Correction."Requested By" := 'alice.admin';
        Correction."Requested At" := CurrentDateTime;
        Correction."Order No." := ProductionOrder."No.";
        Correction."Operation No." := OperationNo;
        Correction."Event Type" := 'Execution';
        Correction."Replacement Start Time" := CurrentDateTime - 7200000;
        Correction."Replacement End Time" := CurrentDateTime - 5400000;
        Correction."Operator Id" := 'OP-222';
        Correction."Shift Code" := 'N';

        Assert.IsTrue(CorrectionSvc.ProcessCorrection(Correction), 'Correction should succeed');

        ALPWorkLogEntry.Reset();
        ALPWorkLogEntry.Get(OriginalEntryNo);
        Assert.AreEqual(ALPWorkLogEntry.Status::Superseded, ALPWorkLogEntry.Status, 'Original should be superseded');

        ALPWorkLogEntry.Reset();
        ALPWorkLogEntry.SetRange("Correction Id", Correction."Correction Id");
        ALPWorkLogEntry.FindFirst();
        Assert.AreEqual(StartTime, ALPWorkLogEntry."Start Time", 'Start Time should be preserved');
        Assert.AreEqual(EndTime, ALPWorkLogEntry."End Time", 'End Time should be preserved');
        Assert.AreEqual('OP-222', ALPWorkLogEntry."Operator Id", 'Operator should be corrected');
        Assert.AreEqual('N', ALPWorkLogEntry."Shift Code", 'Shift should be corrected');
    end;

    [Test]
    procedure CorrectionService_InsertMissingEvent_CreatesCorrectionBackedWorkLog()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        Correction: Record "ALP Execution Correction";
        CorrectionSvc: Codeunit "ALP Execution Correction Svc";
        OperationNo: Code[10];
        NewStartTime: DateTime;
        NewEndTime: DateTime;
    begin
        Initialize();
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        NewStartTime := CurrentDateTime - 3600000;
        NewEndTime := CurrentDateTime - 1800000;

        Correction.Init();
        Correction."Correction Id" := Format(CreateGuid());
        Correction.Action := 'insert_missing_event';
        Correction."Requested By" := 'alice.admin';
        Correction."Requested At" := CurrentDateTime;
        Correction."Order No." := ProductionOrder."No.";
        Correction."Operation No." := OperationNo;
        Correction."Event Type" := 'Execution';
        Correction."Replacement Start Time" := NewStartTime;
        Correction."Replacement End Time" := NewEndTime;
        Correction."Operator Id" := 'OP-999';
        Correction."Shift Code" := 'S';

        Assert.IsTrue(CorrectionSvc.ProcessCorrection(Correction), 'Correction should succeed');

        ALPWorkLogEntry.SetRange("Correction Id", Correction."Correction Id");
        Assert.RecordCount(ALPWorkLogEntry, 1);
        ALPWorkLogEntry.FindFirst();
        Assert.AreEqual(Correction."Correction Id", ALPWorkLogEntry."Message Id", 'Correction id should act as synthetic message id');
        Assert.AreEqual(0, ALPWorkLogEntry."Replaces Entry No.", 'Inserted event should not replace an original');
        Assert.AreEqual(ALPWorkLogEntry.Status::Closed, ALPWorkLogEntry.Status, 'Inserted event should be closed');
        Assert.AreEqual('OP-999', ALPWorkLogEntry."Operator Id", 'Operator should match');
        Assert.IsTrue(ALPWorkLogEntry."Item No." <> '', 'Item No. should be derived from the production order');
    end;

    [Test]
    procedure CorrectionService_TargetsExecutionEventSourceIds()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        Correction: Record "ALP Execution Correction";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        CorrectionSvc: Codeunit "ALP Execution Correction Svc";
        OperationNo: Code[10];
        OriginalEntryNo: Integer;
        SourceStartEventId: Text[50];
        SourceEndEventId: Text[50];
        CorrectionId: Text[50];
    begin
        Initialize();
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        SourceStartEventId := CopyStr('start-' + Format(CreateGuid()), 1, MaxStrLen(SourceStartEventId));
        SourceEndEventId := CopyStr('end-' + Format(CreateGuid()), 1, MaxStrLen(SourceEndEventId));
        CorrectionId := CopyStr('corr-' + Format(CreateGuid()), 1, MaxStrLen(CorrectionId));

        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0, 0, CurrentDateTime - 3600000);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, CreateGuid(), 'Start', 'OP-001', 'F', SourceStartEventId);
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 10, 0, 0.9, 0.8, CurrentDateTime - 1800000);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, CreateGuid(), 'End', 'OP-001', 'F', SourceEndEventId);

        ALPWorkLogEntry.SetRange("Message Id", SourceStartEventId);
        ALPWorkLogEntry.FindFirst();
        OriginalEntryNo := ALPWorkLogEntry."Entry No.";

        Correction.Init();
        Correction."Correction Id" := CorrectionId;
        Correction.Action := 'cancel_event';
        Correction."Target Event Ids" := SourceEndEventId;
        Correction."Requested By" := 'alice.admin';
        Correction."Requested At" := CurrentDateTime;
        Correction."Order No." := ProductionOrder."No.";
        Correction."Operation No." := OperationNo;
        Correction."Event Type" := 'Execution';

        Assert.IsTrue(CorrectionSvc.ProcessCorrection(Correction), 'Correction should resolve executionEvents-created source IDs');

        ALPWorkLogEntry.Reset();
        ALPWorkLogEntry.Get(OriginalEntryNo);
        Assert.AreEqual(ALPWorkLogEntry.Status::Cancelled, ALPWorkLogEntry.Status, 'Original should be cancelled');
        Assert.AreEqual(CorrectionId, ALPWorkLogEntry."Invalidated By Correction Id", 'Correction id should be linked');
    end;

    [Test]
    procedure CorrectionService_DuplicateCorrectionId_IsIdempotent()
    var
        ProductionOrder: Record "Production Order";
        ALPWorkLogEntry: Record "ALP Work Log Entry";
        ALPExecutionCorrection: Record "ALP Execution Correction";
        Correction: Record "ALP Execution Correction";
        WorkLogSvc: Codeunit "ALP Work Log Svc";
        CorrectionSvc: Codeunit "ALP Execution Correction Svc";
        WorkLogEventType: Enum "ALP Work Log Event Type";
        OperationNo: Code[10];
        MessageId: Text[50];
        CorrectionId: Text[50];
    begin
        Initialize();
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        MessageId := CopyStr('start-' + Format(CreateGuid()), 1, MaxStrLen(MessageId));
        CorrectionId := CopyStr('corr-' + Format(CreateGuid()), 1, MaxStrLen(CorrectionId));
        WorkLogSvc.CreateWorkLogEntry(
            MessageId,
            ProductionOrder."No.",
            OperationNo,
            '',
            'OP-001',
            '',
            'F',
            WorkLogEventType::Execution,
            '',
            CurrentDateTime - 3600000,
            'TEST');

        Correction.Init();
        Correction."Correction Id" := CorrectionId;
        Correction.Action := 'cancel_event';
        Correction."Target Event Ids" := MessageId;
        Correction."Requested By" := 'alice.admin';
        Correction."Requested At" := CurrentDateTime;
        Correction."Order No." := ProductionOrder."No.";
        Correction."Operation No." := OperationNo;
        Correction."Event Type" := 'Execution';

        Assert.IsTrue(CorrectionSvc.ProcessCorrection(Correction), 'First correction should succeed');
        Assert.IsTrue(CorrectionSvc.ProcessCorrection(Correction), 'Duplicate correction should be idempotent');

        ALPExecutionCorrection.SetRange("Correction Id", CorrectionId);
        Assert.RecordCount(ALPExecutionCorrection, 1);

        ALPWorkLogEntry.SetRange("Message Id", MessageId);
        ALPWorkLogEntry.FindFirst();
        Assert.AreEqual(ALPWorkLogEntry.Status::Cancelled, ALPWorkLogEntry.Status, 'Target should remain cancelled');
        Assert.AreEqual(CorrectionId, ALPWorkLogEntry."Invalidated By Correction Id", 'Target should link to the correction once');
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
