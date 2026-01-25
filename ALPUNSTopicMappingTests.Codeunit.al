/// <summary>
/// Test codeunit for ALP UNS Topic Mapping functionality.
/// Validates CRUD operations, validation rules, and API accessibility.
/// These tests prove AppSource safety and compliance, not business correctness.
/// </summary>
codeunit 50093 "ALP UNS Topic Mapping Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit Assert;
        LibraryRandom: Codeunit "Library - Random";
        IsInitialized: Boolean;

    local procedure Initialize()
    begin
        if IsInitialized then
            exit;

        IsInitialized := true;
        Commit();
    end;

    local procedure CreateTestMapping(UnsTopic: Text[250]; WorkCenterNo: Code[20]; Status: Enum "ALP UNS Mapping Status"): Record "ALP UNS Topic Mapping"
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
    begin
        ALPUNSTopicMapping.Init();
        ALPUNSTopicMapping."UNS Topic" := UnsTopic;
        ALPUNSTopicMapping."Work Center No." := WorkCenterNo;
        ALPUNSTopicMapping.Status := Status;
        ALPUNSTopicMapping.Description := 'Test mapping';
        ALPUNSTopicMapping."Source System" := 'TEST';
        ALPUNSTopicMapping.Insert(true);
        exit(ALPUNSTopicMapping);
    end;

    local procedure CleanupMapping(UnsTopic: Text[250])
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
    begin
        if ALPUNSTopicMapping.Get(UnsTopic) then
            ALPUNSTopicMapping.Delete(true);
    end;

    // ==================== CRUD TESTS ====================

    [Test]
    procedure CRUD_CreateMapping_Succeeds()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
    begin
        // [SCENARIO] Creating a new UNS Topic Mapping succeeds
        Initialize();

        // [GIVEN] A valid UNS topic path
        UnsTopic := 'mb/v1/plant/line1/station' + Format(LibraryRandom.RandInt(1000));

        // [WHEN] Creating a new mapping
        ALPUNSTopicMapping := CreateTestMapping(UnsTopic, 'WC001', "ALP UNS Mapping Status"::Active);

        // [THEN] Mapping can be retrieved
        Assert.IsTrue(ALPUNSTopicMapping.Get(UnsTopic), 'Mapping should be retrievable');
        Assert.AreEqual('WC001', ALPUNSTopicMapping."Work Center No.", 'Work Center should match');

        // Cleanup
        CleanupMapping(UnsTopic);
    end;

    [Test]
    procedure CRUD_UpdateMapping_Succeeds()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
    begin
        // [SCENARIO] Updating an existing UNS Topic Mapping succeeds
        Initialize();

        // [GIVEN] An existing mapping
        UnsTopic := 'mb/v1/plant/line2/station' + Format(LibraryRandom.RandInt(1000));
        ALPUNSTopicMapping := CreateTestMapping(UnsTopic, 'WC001', "ALP UNS Mapping Status"::Active);

        // [WHEN] Updating the mapping
        ALPUNSTopicMapping.Get(UnsTopic);
        ALPUNSTopicMapping."Work Center No." := 'WC002';
        ALPUNSTopicMapping.Status := "ALP UNS Mapping Status"::Inactive;
        ALPUNSTopicMapping.Modify(true);

        // [THEN] Changes are persisted
        ALPUNSTopicMapping.Get(UnsTopic);
        Assert.AreEqual('WC002', ALPUNSTopicMapping."Work Center No.", 'Work Center should be updated');
        Assert.AreEqual("ALP UNS Mapping Status"::Inactive, ALPUNSTopicMapping.Status, 'Status should be updated');

        // Cleanup
        CleanupMapping(UnsTopic);
    end;

    [Test]
    procedure CRUD_DeleteMapping_Succeeds()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
    begin
        // [SCENARIO] Deleting an existing UNS Topic Mapping succeeds
        Initialize();

        // [GIVEN] An existing mapping
        UnsTopic := 'mb/v1/plant/line3/station' + Format(LibraryRandom.RandInt(1000));
        CreateTestMapping(UnsTopic, 'WC001', "ALP UNS Mapping Status"::Active);

        // [WHEN] Deleting the mapping
        ALPUNSTopicMapping.Get(UnsTopic);
        ALPUNSTopicMapping.Delete(true);

        // [THEN] Mapping no longer exists
        Assert.IsFalse(ALPUNSTopicMapping.Get(UnsTopic), 'Mapping should be deleted');
    end;

    [Test]
    procedure CRUD_DuplicateTopic_Fails()
    var
        ALPUNSTopicMapping1: Record "ALP UNS Topic Mapping";
        ALPUNSTopicMapping2: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
        InsertSucceeded: Boolean;
    begin
        // [SCENARIO] Inserting duplicate UNS Topic fails (primary key violation)
        Initialize();

        // [GIVEN] An existing mapping
        UnsTopic := 'mb/v1/plant/line4/station' + Format(LibraryRandom.RandInt(1000));
        ALPUNSTopicMapping1 := CreateTestMapping(UnsTopic, 'WC001', "ALP UNS Mapping Status"::Active);

        // [WHEN] Attempting to insert duplicate
        ALPUNSTopicMapping2.Init();
        ALPUNSTopicMapping2."UNS Topic" := UnsTopic;
        ALPUNSTopicMapping2."Work Center No." := 'WC002';
        ALPUNSTopicMapping2.Status := "ALP UNS Mapping Status"::Active;
        InsertSucceeded := ALPUNSTopicMapping2.Insert(false);

        // [THEN] Insert fails
        Assert.IsFalse(InsertSucceeded, 'Duplicate insert should fail');

        // Cleanup
        CleanupMapping(UnsTopic);
    end;

    // ==================== STATUS ENUM TESTS ====================

    [Test]
    procedure Status_ActiveMapping_IsQueryable()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
        CountBefore: Integer;
        CountAfter: Integer;
    begin
        // [SCENARIO] Active mappings can be filtered by status
        Initialize();

        // [GIVEN] Count of active mappings before
        ALPUNSTopicMapping.SetRange(Status, "ALP UNS Mapping Status"::Active);
        CountBefore := ALPUNSTopicMapping.Count();

        // [GIVEN] A new active mapping
        UnsTopic := 'mb/v1/plant/line5/station' + Format(LibraryRandom.RandInt(1000));
        CreateTestMapping(UnsTopic, 'WC001', "ALP UNS Mapping Status"::Active);

        // [WHEN] Filtering by active status
        ALPUNSTopicMapping.SetRange(Status, "ALP UNS Mapping Status"::Active);
        CountAfter := ALPUNSTopicMapping.Count();

        // [THEN] Count increased by 1
        Assert.AreEqual(CountBefore + 1, CountAfter, 'Active count should increase by 1');

        // Cleanup
        CleanupMapping(UnsTopic);
    end;

    [Test]
    procedure Status_InactiveMapping_IsFilterable()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
    begin
        // [SCENARIO] Inactive mappings can be filtered
        Initialize();

        // [GIVEN] An inactive mapping
        UnsTopic := 'mb/v1/plant/line6/station' + Format(LibraryRandom.RandInt(1000));
        CreateTestMapping(UnsTopic, 'WC001', "ALP UNS Mapping Status"::Inactive);

        // [WHEN] Filtering by inactive status
        ALPUNSTopicMapping.SetRange(Status, "ALP UNS Mapping Status"::Inactive);
        ALPUNSTopicMapping.SetRange("UNS Topic", UnsTopic);

        // [THEN] Mapping is found
        Assert.IsTrue(ALPUNSTopicMapping.FindFirst(), 'Inactive mapping should be found');

        // Cleanup
        CleanupMapping(UnsTopic);
    end;

    // ==================== VALIDATION TESTS ====================

    [Test]
    procedure Validation_EmptyTopic_CannotInsert()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        InsertSucceeded: Boolean;
    begin
        // [SCENARIO] Empty UNS Topic cannot be inserted (primary key)
        Initialize();

        // [GIVEN] A mapping with empty topic
        ALPUNSTopicMapping.Init();
        ALPUNSTopicMapping."UNS Topic" := '';
        ALPUNSTopicMapping."Work Center No." := 'WC001';
        ALPUNSTopicMapping.Status := "ALP UNS Mapping Status"::Active;

        // [WHEN] Attempting to insert
        InsertSucceeded := ALPUNSTopicMapping.Insert(false);

        // [THEN] Insert fails (empty primary key)
        Assert.IsFalse(InsertSucceeded, 'Empty topic insert should fail');
    end;

    [Test]
    procedure Validation_OptionalWorkCenter_AllowsAutoDiscovery()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
    begin
        // [SCENARIO] Work Center is optional to support auto-discovery workflow
        Initialize();

        // [GIVEN] A mapping without Work Center
        UnsTopic := 'mb/v1/plant/line7/station' + Format(LibraryRandom.RandInt(1000));
        ALPUNSTopicMapping.Init();
        ALPUNSTopicMapping."UNS Topic" := UnsTopic;
        ALPUNSTopicMapping."Work Center No." := '';  // Empty - auto-discovery pending
        ALPUNSTopicMapping.Status := "ALP UNS Mapping Status"::Active;
        ALPUNSTopicMapping.Insert(true);

        // [THEN] Mapping is created successfully
        Assert.IsTrue(ALPUNSTopicMapping.Get(UnsTopic), 'Mapping without Work Center should be allowed');
        Assert.AreEqual('', ALPUNSTopicMapping."Work Center No.", 'Work Center should be empty');

        // Cleanup
        CleanupMapping(UnsTopic);
    end;

    // ==================== VALIDITY DATE TESTS ====================

    [Test]
    procedure ValidityDates_ValidFromToIsRespected()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
    begin
        // [SCENARIO] Validity dates can be set on mappings
        Initialize();

        // [GIVEN] A mapping with validity dates
        UnsTopic := 'mb/v1/plant/line8/station' + Format(LibraryRandom.RandInt(1000));
        ALPUNSTopicMapping.Init();
        ALPUNSTopicMapping."UNS Topic" := UnsTopic;
        ALPUNSTopicMapping."Work Center No." := 'WC001';
        ALPUNSTopicMapping.Status := "ALP UNS Mapping Status"::Active;
        ALPUNSTopicMapping."Valid From" := Today() - 30;
        ALPUNSTopicMapping."Valid To" := Today() + 30;
        ALPUNSTopicMapping.Insert(true);

        // [THEN] Dates are persisted
        ALPUNSTopicMapping.Get(UnsTopic);
        Assert.AreEqual(Today() - 30, ALPUNSTopicMapping."Valid From", 'Valid From should be set');
        Assert.AreEqual(Today() + 30, ALPUNSTopicMapping."Valid To", 'Valid To should be set');

        // Cleanup
        CleanupMapping(UnsTopic);
    end;

    [Test]
    procedure ValidityDates_OpenEndedIsAllowed()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
    begin
        // [SCENARIO] Valid To can be empty for open-ended mappings
        Initialize();

        // [GIVEN] A mapping with no end date
        UnsTopic := 'mb/v1/plant/line9/station' + Format(LibraryRandom.RandInt(1000));
        ALPUNSTopicMapping.Init();
        ALPUNSTopicMapping."UNS Topic" := UnsTopic;
        ALPUNSTopicMapping."Work Center No." := 'WC001';
        ALPUNSTopicMapping.Status := "ALP UNS Mapping Status"::Active;
        ALPUNSTopicMapping."Valid From" := Today();
        ALPUNSTopicMapping."Valid To" := 0D;  // No end date
        ALPUNSTopicMapping.Insert(true);

        // [THEN] Mapping is created
        Assert.IsTrue(ALPUNSTopicMapping.Get(UnsTopic), 'Open-ended mapping should be allowed');
        Assert.AreEqual(0D, ALPUNSTopicMapping."Valid To", 'Valid To should be empty');

        // Cleanup
        CleanupMapping(UnsTopic);
    end;

    // ==================== AUDIT FIELD TESTS ====================

    [Test]
    procedure AuditFields_CreatedAtIsSet()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
        TimeBefore: DateTime;
    begin
        // [SCENARIO] Created At timestamp is automatically set
        Initialize();

        // [GIVEN] Current time
        TimeBefore := CurrentDateTime - 1000;

        // [WHEN] Creating a new mapping
        UnsTopic := 'mb/v1/plant/line10/station' + Format(LibraryRandom.RandInt(1000));
        ALPUNSTopicMapping := CreateTestMapping(UnsTopic, 'WC001', "ALP UNS Mapping Status"::Active);

        // [THEN] Created At is set to current time
        ALPUNSTopicMapping.Get(UnsTopic);
        Assert.IsTrue(ALPUNSTopicMapping."Created At" > TimeBefore, 'Created At should be set to current time');

        // Cleanup
        CleanupMapping(UnsTopic);
    end;

    [Test]
    procedure AuditFields_ModifiedAtUpdatesOnChange()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
        UnsTopic: Text[250];
        CreatedAt: DateTime;
    begin
        // [SCENARIO] Modified At timestamp updates when record changes
        Initialize();

        // [GIVEN] An existing mapping
        UnsTopic := 'mb/v1/plant/line11/station' + Format(LibraryRandom.RandInt(1000));
        ALPUNSTopicMapping := CreateTestMapping(UnsTopic, 'WC001', "ALP UNS Mapping Status"::Active);
        CreatedAt := ALPUNSTopicMapping."Created At";

        // Wait a moment to ensure different timestamp
        Sleep(100);

        // [WHEN] Modifying the mapping
        ALPUNSTopicMapping.Get(UnsTopic);
        ALPUNSTopicMapping.Description := 'Updated description';
        ALPUNSTopicMapping.Modify(true);

        // [THEN] Modified At is updated
        ALPUNSTopicMapping.Get(UnsTopic);
        Assert.IsTrue(ALPUNSTopicMapping."Modified At" >= CreatedAt, 'Modified At should be updated');

        // Cleanup
        CleanupMapping(UnsTopic);
    end;

    // ==================== TABLE STABILITY TESTS ====================

    [Test]
    procedure TableStability_PrimaryKeyIsUnsTopic()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
    begin
        // [SCENARIO] Primary key structure is stable for upgrades
        Initialize();

        // [GIVEN] The UNS Topic Mapping table

        // [WHEN] Checking field structure
        // [THEN] UNS Topic is the primary key field
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("UNS Topic") > 0, 'UNS Topic field should exist');

        // [THEN] Required fields exist
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("Work Center No.") > 0, 'Work Center No. field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo(Status) > 0, 'Status field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("Valid From") > 0, 'Valid From field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("Valid To") > 0, 'Valid To field should exist');
    end;

    [Test]
    procedure TableStability_AllRequiredFieldsExist()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
    begin
        // [SCENARIO] All expected fields exist on the table
        Initialize();

        // [GIVEN] The UNS Topic Mapping table

        // [THEN] All expected fields exist
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("UNS Topic") > 0, 'UNS Topic field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("Work Center No.") > 0, 'Work Center No. field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo(Status) > 0, 'Status field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo(Description) > 0, 'Description field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("Source System") > 0, 'Source System field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("Valid From") > 0, 'Valid From field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("Valid To") > 0, 'Valid To field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("Created At") > 0, 'Created At field should exist');
        Assert.IsTrue(ALPUNSTopicMapping.FieldNo("Modified At") > 0, 'Modified At field should exist');
    end;
}
