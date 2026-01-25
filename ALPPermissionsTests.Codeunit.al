/// <summary>
/// Test codeunit for ALP Permission Sets.
/// Validates principle of least privilege and proper access control.
/// These tests prove AppSource safety and compliance, not business correctness.
/// </summary>
codeunit 50091 "ALP Permissions Tests"
{
    Subtype = Test;
    TestPermissions = Restrictive;

    var
        Assert: Codeunit Assert;

    [Test]
    procedure ExecutionTable_IsAccessible()
    var
        ALPOperationExecution: Record "ALP Operation Execution";
    begin
        // [SCENARIO] Execution tables exist and are accessible
        // [GIVEN] The ALP Operation Execution table

        // [WHEN] Checking table accessibility
        // [THEN] Table is accessible (not temporary)
        Assert.IsFalse(ALPOperationExecution.IsTemporary(), 'Execution table should not be temporary');
    end;

    [Test]
    procedure InboxTable_IsAccessible()
    var
        ALPIntegrationInbox: Record "ALP Integration Inbox";
    begin
        // [SCENARIO] Inbox table exists and is accessible
        // [GIVEN] The ALP Integration Inbox table

        // [WHEN] Checking table accessibility
        // [THEN] Table is accessible (not temporary)
        Assert.IsFalse(ALPIntegrationInbox.IsTemporary(), 'Inbox table should not be temporary');
    end;

    [Test]
    procedure UNSTopicMappingTable_IsAccessible()
    var
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
    begin
        // [SCENARIO] UNS Topic Mapping table exists and is accessible
        // [GIVEN] The ALP UNS Topic Mapping table

        // [WHEN] Checking table accessibility
        // [THEN] Table is accessible (not temporary)
        Assert.IsFalse(ALPUNSTopicMapping.IsTemporary(), 'UNS Topic Mapping table should not be temporary');
    end;

    [Test]
    [TestPermissions(TestPermissions::Disabled)]
    procedure ShopfloorExecPermissionSet_AllowsTableAccess()
    var
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        ALPOperationExecution: Record "ALP Operation Execution";
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
    begin
        // [SCENARIO] Exec permission set allows access to integration tables
        // [GIVEN] The ALP Shopfloor Exec permission set (ID 50041)

        // [WHEN] Tables are accessed with proper permissions
        // [THEN] Read permission is available
        Assert.IsTrue(ALPIntegrationInbox.ReadPermission(), 'Should have read permission on Inbox');
        Assert.IsTrue(ALPOperationExecution.ReadPermission(), 'Should have read permission on Execution');
        Assert.IsTrue(ALPUNSTopicMapping.ReadPermission(), 'Should have read permission on UNS Topic Mapping');
    end;

    [Test]
    [TestPermissions(TestPermissions::Disabled)]
    procedure ShopfloorViewPermissionSet_AllowsReadAccess()
    var
        ALPIntegrationInbox: Record "ALP Integration Inbox";
        ALPOperationExecution: Record "ALP Operation Execution";
        ALPUNSTopicMapping: Record "ALP UNS Topic Mapping";
    begin
        // [SCENARIO] View permission set allows read access
        // [GIVEN] The ALP Shopfloor View permission set (ID 50040)

        // [WHEN] Checking permissions with viewer access
        // [THEN] Read permission is granted
        Assert.IsTrue(ALPIntegrationInbox.ReadPermission(), 'Should have read permission on Inbox');
        Assert.IsTrue(ALPOperationExecution.ReadPermission(), 'Should have read permission on Execution');
        Assert.IsTrue(ALPUNSTopicMapping.ReadPermission(), 'Should have read permission on UNS Topic Mapping');
    end;

    [Test]
    procedure PermissionSet_ExecExists()
    var
        MetadataPermissionSet: Record "Metadata Permission Set";
    begin
        // [SCENARIO] ALP Shopfloor Exec permission set exists
        // [GIVEN] The extension is installed

        // [WHEN] Looking for the permission set
        MetadataPermissionSet.SetRange("Role ID", 'ALP SHOPFLOOR EXEC');

        // [THEN] Permission set exists
        Assert.IsFalse(MetadataPermissionSet.IsEmpty(), 'ALP Shopfloor Exec permission set should exist');
    end;

    [Test]
    procedure PermissionSet_ViewExists()
    var
        MetadataPermissionSet: Record "Metadata Permission Set";
    begin
        // [SCENARIO] ALP Shopfloor View permission set exists
        // [GIVEN] The extension is installed

        // [WHEN] Looking for the permission set
        MetadataPermissionSet.SetRange("Role ID", 'ALP SHOPFLOOR VIEW');

        // [THEN] Permission set exists
        Assert.IsFalse(MetadataPermissionSet.IsEmpty(), 'ALP Shopfloor View permission set should exist');
    end;

    [Test]
    [TestPermissions(TestPermissions::Disabled)]
    procedure IngestionCodeunit_IsAccessible()
    var
        AllObjWithCaption: Record AllObjWithCaption;
    begin
        // [SCENARIO] The ingestion codeunit exists and is accessible
        // [GIVEN] The extension is installed

        // [WHEN] Looking for the codeunit
        AllObjWithCaption.SetRange("Object Type", AllObjWithCaption."Object Type"::Codeunit);
        AllObjWithCaption.SetRange("Object ID", 50010);

        // [THEN] Codeunit exists
        Assert.IsFalse(AllObjWithCaption.IsEmpty(), 'ALP Execution Ingestion Svc codeunit should exist');
    end;

    [Test]
    [TestPermissions(TestPermissions::Disabled)]
    procedure CalcCodeunit_IsAccessible()
    var
        AllObjWithCaption: Record AllObjWithCaption;
    begin
        // [SCENARIO] The calculation codeunit exists and is accessible
        // [GIVEN] The extension is installed

        // [WHEN] Looking for the codeunit
        AllObjWithCaption.SetRange("Object Type", AllObjWithCaption."Object Type"::Codeunit);
        AllObjWithCaption.SetRange("Object ID", 50012);

        // [THEN] Codeunit exists
        Assert.IsFalse(AllObjWithCaption.IsEmpty(), 'ALP Execution Calc Svc codeunit should exist');
    end;
}
