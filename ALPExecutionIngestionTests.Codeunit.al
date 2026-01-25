/// <summary>
/// Test codeunit for ALP Execution Ingestion Service.
/// Validates safety, idempotency, and resilience of execution event processing.
/// These tests prove AppSource safety and compliance, not business correctness.
/// </summary>
codeunit 50090 "ALP Execution Ingestion Tests"
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
    begin
        if ALPIntegrationInbox.Get(MessageId) then
            ALPIntegrationInbox.Delete(true);

        if ALPOperationExecution.Get(OrderNo, OperationNo) then
            ALPOperationExecution.Delete(true);
    end;

    // ==================== HAPPY PATH TESTS ====================

    [Test]
    procedure HappyPath_ValidExecution_CreatesOneRecord()
    var
        ProductionOrder: Record "Production Order";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        ALPOperationExecution: Record "ALP Operation Execution";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        Result: Boolean;
    begin
        // [SCENARIO] Valid execution payload creates exactly one execution record
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] A valid execution payload
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 5, 0.85, 0.90, CurrentDateTime);

        // [WHEN] The ingestion codeunit is called
        Result := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Function returns true (success)
        Assert.IsTrue(Result, 'ProcessExecutionEvent should return true');

        // [THEN] One execution record exists
        ALPOperationExecution.SetRange("Order No.", ProductionOrder."No.");
        ALPOperationExecution.SetRange("Operation No.", OperationNo);
        Assert.RecordCount(ALPOperationExecution, 1);

        // [THEN] Inbox entry is marked Processed
        Assert.IsTrue(ALPIntegrationInbox.Get(MessageId), 'Inbox entry should exist');
        Assert.AreEqual(
            ALPIntegrationInbox.Status::Processed,
            ALPIntegrationInbox.Status,
            'Inbox status should be Processed');

        // [THEN] Execution record has correct values
        ALPOperationExecution.Get(ProductionOrder."No.", OperationNo);
        Assert.AreEqual(100, ALPOperationExecution."Qty. Produced", 'Qty. Produced mismatch');
        Assert.AreEqual(5, ALPOperationExecution."Qty. Rejected", 'Qty. Rejected mismatch');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure HappyPath_RoutingLineUpdated()
    var
        ProductionOrder: Record "Production Order";
        ProdOrderRoutingLine: Record "Prod. Order Routing Line";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
    begin
        // [SCENARIO] Valid ingestion updates the routing line extension fields
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] A valid execution payload
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 10, 0.92, 0.88, CurrentDateTime);

        // [WHEN] The ingestion codeunit is called
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Routing line extension fields are updated
        ProdOrderRoutingLine.SetRange(Status, ProdOrderRoutingLine.Status::Released);
        ProdOrderRoutingLine.SetRange("Prod. Order No.", ProductionOrder."No.");
        ProdOrderRoutingLine.SetRange("Operation No.", OperationNo);
        ProdOrderRoutingLine.FindFirst();

        Assert.AreEqual(100, ProdOrderRoutingLine."ALP Qty. Produced", 'Routing line Qty. Produced should be updated');
        Assert.AreEqual(10, ProdOrderRoutingLine."ALP Qty. Rejected", 'Routing line Qty. Rejected should be updated');
        Assert.AreEqual(0.92, ProdOrderRoutingLine."ALP Actual Availability", 'Routing line Availability should be updated');
        Assert.AreEqual(0.88, ProdOrderRoutingLine."ALP Actual Productivity", 'Routing line Productivity should be updated');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure HappyPath_ProductionOrderUpdated()
    var
        ProductionOrder: Record "Production Order";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        TimeBefore: DateTime;
    begin
        // [SCENARIO] Valid ingestion updates Production Order extension fields
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);
        TimeBefore := CurrentDateTime - 1000;

        // [GIVEN] A valid execution payload
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 50, 2, 0.95, 0.91, CurrentDateTime);

        // [WHEN] The ingestion codeunit is called
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Production Order extension fields are updated
        ProductionOrder.Get(ProductionOrder.Status, ProductionOrder."No.");

        Assert.IsTrue(ProductionOrder."ALP Last Exec Update At" > TimeBefore, 'Last update timestamp should be set');
        Assert.AreEqual('TEST', ProductionOrder."ALP Execution Source", 'Execution source should be set');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    // ==================== IDEMPOTENCY TESTS ====================

    [Test]
    procedure Idempotency_DuplicateMessageId_CreatesOnlyOneRecord()
    var
        ProductionOrder: Record "Production Order";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        ALPOperationExecution: Record "ALP Operation Execution";
        Exec1: Record "ALP Operation Execution";
        Exec2: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        Result1: Boolean;
        Result2: Boolean;
    begin
        // [SCENARIO] Same payload with same MessageId ingested twice creates only one record
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Same MessageId for both calls
        MessageId := CreateGuid();

        // [WHEN] Ingestion is called first time
        Exec1 := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 5, 0.85, 0.90, CurrentDateTime);
        Result1 := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec1, MessageId);

        // [WHEN] Ingestion is called second time with same MessageId
        Exec2 := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 200, 10, 0.75, 0.80, CurrentDateTime);
        Result2 := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec2, MessageId);

        // [THEN] Both calls return true (no exception thrown)
        Assert.IsTrue(Result1, 'First call should succeed');
        Assert.IsTrue(Result2, 'Second call should succeed (idempotent)');

        // [THEN] Only one execution record exists
        ALPOperationExecution.SetRange("Order No.", ProductionOrder."No.");
        ALPOperationExecution.SetRange("Operation No.", OperationNo);
        Assert.RecordCount(ALPOperationExecution, 1);

        // [THEN] Inbox contains only one entry
        ALPIntegrationInbox.SetRange("Message Id", MessageId);
        Assert.RecordCount(ALPIntegrationInbox, 1);

        // [THEN] Values from first call are preserved (not overwritten by duplicate)
        ALPOperationExecution.Get(ProductionOrder."No.", OperationNo);
        Assert.AreEqual(100, ALPOperationExecution."Qty. Produced", 'Original Qty. Produced should be preserved');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    // ==================== OUT-OF-ORDER TESTS ====================

    [Test]
    procedure OutOfOrder_OlderTimestamp_IsIgnored()
    var
        ProductionOrder: Record "Production Order";
        ALPOperationExecution: Record "ALP Operation Execution";
        Exec1: Record "ALP Operation Execution";
        Exec2: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId1: Guid;
        MessageId2: Guid;
        NewerTimestamp: DateTime;
        OlderTimestamp: DateTime;
        OperationNo: Code[10];
    begin
        // [SCENARIO] Execution event with older timestamp does not overwrite newer data
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Execution event with newer timestamp
        MessageId1 := CreateGuid();
        NewerTimestamp := CurrentDateTime;

        // [GIVEN] Execution event with older timestamp
        MessageId2 := CreateGuid();
        OlderTimestamp := NewerTimestamp - 3600000;  // 1 hour earlier

        // [WHEN] Newer event is ingested first
        Exec1 := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 200, 10, 0.90, 0.95, NewerTimestamp);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec1, MessageId1);

        // [WHEN] Older event is ingested second (out of order)
        Exec2 := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 5, 0.80, 0.85, OlderTimestamp);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec2, MessageId2);

        // [THEN] Stored execution reflects the newer event only
        ALPOperationExecution.Get(ProductionOrder."No.", OperationNo);
        Assert.AreEqual(NewerTimestamp, ALPOperationExecution."Source Timestamp", 'Source timestamp should be unchanged');
        Assert.AreEqual(200, ALPOperationExecution."Qty. Produced", 'Newer Qty. Produced should be preserved');
        Assert.AreEqual(0.90, ALPOperationExecution.Availability, 'Newer availability should be preserved');

        // Cleanup
        CleanupTestData(MessageId1, ProductionOrder."No.", OperationNo);
        CleanupTestData(MessageId2, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure OutOfOrder_NewerTimestamp_UpdatesRecord()
    var
        ProductionOrder: Record "Production Order";
        ALPOperationExecution: Record "ALP Operation Execution";
        Exec1: Record "ALP Operation Execution";
        Exec2: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId1: Guid;
        MessageId2: Guid;
        OlderTimestamp: DateTime;
        NewerTimestamp: DateTime;
        OperationNo: Code[10];
    begin
        // [SCENARIO] Execution event with newer timestamp updates existing record
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Two timestamps
        OlderTimestamp := CurrentDateTime - 3600000;  // 1 hour earlier
        NewerTimestamp := CurrentDateTime;
        MessageId1 := CreateGuid();
        MessageId2 := CreateGuid();

        // [WHEN] Older event is ingested first
        Exec1 := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 5, 0.80, 0.85, OlderTimestamp);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec1, MessageId1);

        // [WHEN] Newer event is ingested second
        Exec2 := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 200, 10, 0.90, 0.95, NewerTimestamp);
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec2, MessageId2);

        // [THEN] Stored execution reflects the newer event
        ALPOperationExecution.Get(ProductionOrder."No.", OperationNo);
        Assert.AreEqual(NewerTimestamp, ALPOperationExecution."Source Timestamp", 'Should have newer timestamp');
        Assert.AreEqual(200, ALPOperationExecution."Qty. Produced", 'Should have newer Qty. Produced');
        Assert.AreEqual(0.90, ALPOperationExecution.Availability, 'Should have newer availability');

        // Cleanup
        CleanupTestData(MessageId1, ProductionOrder."No.", OperationNo);
        CleanupTestData(MessageId2, ProductionOrder."No.", OperationNo);
    end;

    // ==================== VALIDATION FAILURE TESTS ====================

    [Test]
    procedure Validation_RejectedGreaterThanProduced_ReturnsFalse()
    var
        ProductionOrder: Record "Production Order";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        ALPOperationExecution: Record "ALP Operation Execution";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        Result: Boolean;
    begin
        // [SCENARIO] Ingestion fails when Qty. Rejected > Qty. Produced
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Qty. Rejected > Qty. Produced (invalid)
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 150, 0.85, 0.90, CurrentDateTime);

        // [WHEN] Ingestion is attempted
        Result := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Function returns false
        Assert.IsFalse(Result, 'ProcessExecutionEvent should return false for invalid input');

        // [THEN] No execution record created
        ALPOperationExecution.SetRange("Order No.", ProductionOrder."No.");
        ALPOperationExecution.SetRange("Operation No.", OperationNo);
        Assert.RecordIsEmpty(ALPOperationExecution);

        // [THEN] Inbox entry is marked Failed
        Assert.IsTrue(ALPIntegrationInbox.Get(MessageId), 'Inbox entry should exist');
        Assert.AreEqual(
            ALPIntegrationInbox.Status::Failed,
            ALPIntegrationInbox.Status,
            'Inbox status should be Failed');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure Validation_AvailabilityAboveOne_ReturnsFalse()
    var
        ProductionOrder: Record "Production Order";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        Result: Boolean;
    begin
        // [SCENARIO] Ingestion fails when availability > 1
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Availability > 1 (invalid)
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 5, 1.5, 0.90, CurrentDateTime);

        // [WHEN] Ingestion is attempted
        Result := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Function returns false
        Assert.IsFalse(Result, 'ProcessExecutionEvent should return false for availability > 1');

        // [THEN] Inbox entry is marked Failed
        Assert.IsTrue(ALPIntegrationInbox.Get(MessageId), 'Inbox entry should exist');
        Assert.AreEqual(ALPIntegrationInbox.Status::Failed, ALPIntegrationInbox.Status, 'Inbox status should be Failed');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure Validation_AvailabilityBelowZero_ReturnsFalse()
    var
        ProductionOrder: Record "Production Order";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        Result: Boolean;
    begin
        // [SCENARIO] Ingestion fails when availability < 0
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Availability < 0 (invalid)
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 5, -0.1, 0.90, CurrentDateTime);

        // [WHEN] Ingestion is attempted
        Result := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Function returns false
        Assert.IsFalse(Result, 'ProcessExecutionEvent should return false for availability < 0');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure Validation_ProductivityAboveOne_ReturnsFalse()
    var
        ProductionOrder: Record "Production Order";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        Result: Boolean;
    begin
        // [SCENARIO] Ingestion fails when productivity > 1
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Productivity > 1 (invalid)
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 5, 0.85, 1.2, CurrentDateTime);

        // [WHEN] Ingestion is attempted
        Result := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Function returns false
        Assert.IsFalse(Result, 'ProcessExecutionEvent should return false for productivity > 1');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure Validation_ProductivityBelowZero_ReturnsFalse()
    var
        ProductionOrder: Record "Production Order";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        Result: Boolean;
    begin
        // [SCENARIO] Ingestion fails when productivity < 0
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Productivity < 0 (invalid)
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 5, 0.85, -0.1, CurrentDateTime);

        // [WHEN] Ingestion is attempted
        Result := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Function returns false
        Assert.IsFalse(Result, 'ProcessExecutionEvent should return false for productivity < 0');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure Validation_NonExistentProductionOrder_ReturnsFalse()
    var
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        ALPOperationExecution: Record "ALP Operation Execution";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        FakeOrderNo: Code[20];
        OperationNo: Code[10];
        Result: Boolean;
    begin
        // [SCENARIO] Ingestion fails when Production Order does not exist
        Initialize();

        // [GIVEN] A non-existent Production Order
        FakeOrderNo := 'FAKE-ORDER-999';
        OperationNo := '10';
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(FakeOrderNo, OperationNo, 100, 5, 0.85, 0.90, CurrentDateTime);

        // [WHEN] Ingestion is attempted
        Result := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Function returns false
        Assert.IsFalse(Result, 'ProcessExecutionEvent should return false for non-existent order');

        // [THEN] No execution record created
        ALPOperationExecution.SetRange("Order No.", FakeOrderNo);
        Assert.RecordIsEmpty(ALPOperationExecution);

        // [THEN] Inbox entry is marked Failed
        Assert.IsTrue(ALPIntegrationInbox.Get(MessageId), 'Inbox entry should exist');
        Assert.AreEqual(ALPIntegrationInbox.Status::Failed, ALPIntegrationInbox.Status, 'Inbox status should be Failed');

        // Cleanup
        CleanupTestData(MessageId, FakeOrderNo, OperationNo);
    end;

    [Test]
    procedure Validation_NonExistentRoutingLine_ReturnsFalse()
    var
        ProductionOrder: Record "Production Order";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        ALPOperationExecution: Record "ALP Operation Execution";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        FakeOperationNo: Code[10];
        Result: Boolean;
    begin
        // [SCENARIO] Ingestion fails when routing line does not exist for the operation
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] A non-existent operation number
        FakeOperationNo := '99';
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", FakeOperationNo, 100, 5, 0.85, 0.90, CurrentDateTime);

        // [WHEN] Ingestion is attempted
        Result := ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Function returns false
        Assert.IsFalse(Result, 'ProcessExecutionEvent should return false for non-existent routing line');

        // [THEN] No execution record created
        ALPOperationExecution.SetRange("Order No.", ProductionOrder."No.");
        ALPOperationExecution.SetRange("Operation No.", FakeOperationNo);
        Assert.RecordIsEmpty(ALPOperationExecution);

        // [THEN] Inbox entry is marked Failed
        Assert.IsTrue(ALPIntegrationInbox.Get(MessageId), 'Inbox entry should exist');
        Assert.AreEqual(ALPIntegrationInbox.Status::Failed, ALPIntegrationInbox.Status, 'Inbox status should be Failed');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", FakeOperationNo);
    end;

    // ==================== FAILURE ATOMICITY TESTS ====================

    [Test]
    procedure FailureAtomicity_ValidationFailed_NoPartialData()
    var
        ProductionOrder: Record "Production Order";
        ALPOperationExecution: Record "ALP Operation Execution";
        ProdOrderRoutingLine: Record "Prod. Order Routing Line";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
        OriginalLastExecUpdate: DateTime;
    begin
        // [SCENARIO] Failed validation leaves no partial data
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);
        OriginalLastExecUpdate := ProductionOrder."ALP Last Exec Update At";

        // [GIVEN] Invalid payload (Rejected > Produced)
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 150, 0.85, 0.90, CurrentDateTime);

        // [WHEN] Ingestion fails
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] No execution record exists
        ALPOperationExecution.SetRange("Order No.", ProductionOrder."No.");
        ALPOperationExecution.SetRange("Operation No.", OperationNo);
        Assert.RecordIsEmpty(ALPOperationExecution);

        // [THEN] Production Order was not modified
        ProductionOrder.Get(ProductionOrder.Status, ProductionOrder."No.");
        Assert.AreEqual(OriginalLastExecUpdate, ProductionOrder."ALP Last Exec Update At", 'Production Order should not be modified on failure');

        // [THEN] Routing Line was not modified
        ProdOrderRoutingLine.SetRange(Status, ProdOrderRoutingLine.Status::Released);
        ProdOrderRoutingLine.SetRange("Prod. Order No.", ProductionOrder."No.");
        ProdOrderRoutingLine.SetRange("Operation No.", OperationNo);
        ProdOrderRoutingLine.FindFirst();
        Assert.AreEqual(0, ProdOrderRoutingLine."ALP Qty. Produced", 'Routing line should not be modified on failure');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure FailureAtomicity_InboxRecordsReason()
    var
        ProductionOrder: Record "Production Order";
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
    begin
        // [SCENARIO] Failed ingestion records the failure reason in inbox
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Invalid payload
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 150, 0.85, 0.90, CurrentDateTime);

        // [WHEN] Ingestion fails
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Inbox contains error text
        ALPIntegrationInbox.Get(MessageId);
        Assert.IsTrue(StrLen(ALPIntegrationInbox.Error) > 0, 'Error field should contain failure reason');
        Assert.IsTrue(ALPIntegrationInbox.Error.Contains('150'), 'Error should mention the rejected count');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    // ==================== AGGREGATION TESTS ====================

    [Test]
    procedure Aggregation_SingleOperation_SumsCorrectly()
    var
        ProductionOrder: Record "Production Order";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
    begin
        // [SCENARIO] Single operation aggregates are summed to Production Order level
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Valid execution payload
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 100, 10, 0.90, 0.85, CurrentDateTime);

        // [WHEN] Ingestion is called
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Production Order aggregates equal the operation values
        ProductionOrder.Get(ProductionOrder.Status, ProductionOrder."No.");
        Assert.AreEqual(100, ProductionOrder."ALP Exec Qty. Produced", 'Aggregate Qty. Produced should match');
        Assert.AreEqual(10, ProductionOrder."ALP Exec Qty. Rejected", 'Aggregate Qty. Rejected should match');
        Assert.AreEqual(0.90, ProductionOrder."ALP Exec Weighted Avail", 'Weighted availability should match');
        Assert.AreEqual(0.85, ProductionOrder."ALP Exec Weighted Prod", 'Weighted productivity should match');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;

    [Test]
    procedure Aggregation_ZeroQuantity_HandlesGracefully()
    var
        ProductionOrder: Record "Production Order";
        Exec: Record "ALP Operation Execution";
        ALPExecutionIngestionSvc: Codeunit "ALP Execution Ingestion Svc";
        MessageId: Guid;
        OperationNo: Code[10];
    begin
        // [SCENARIO] Zero quantity does not cause division by zero
        Initialize();

        // [GIVEN] A released Production Order with routing
        CreateReleasedProductionOrderWithRouting(ProductionOrder, OperationNo);

        // [GIVEN] Zero quantity execution
        MessageId := CreateGuid();
        Exec := CreateExecutionRecord(ProductionOrder."No.", OperationNo, 0, 0, 0.90, 0.85, CurrentDateTime);

        // [WHEN] Ingestion is called
        ALPExecutionIngestionSvc.ProcessExecutionEvent(Exec, MessageId);

        // [THEN] Aggregation handles zero gracefully (no error)
        ProductionOrder.Get(ProductionOrder.Status, ProductionOrder."No.");
        Assert.AreEqual(0, ProductionOrder."ALP Exec Qty. Produced", 'Qty. Produced should be zero');
        Assert.AreEqual(0, ProductionOrder."ALP Exec Weighted Avail", 'Weighted availability should be zero when no parts');
        Assert.AreEqual(0, ProductionOrder."ALP Exec Weighted Prod", 'Weighted productivity should be zero when no parts');

        // Cleanup
        CleanupTestData(MessageId, ProductionOrder."No.", OperationNo);
    end;
}
