/// <summary>
/// Business-correctness tests for execution time attribution.
/// These tests validate machine union time and operator split/additive semantics.
/// </summary>
codeunit 50095 "ALP Execution Attribution Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit Assert;

    [Test]
    procedure SameTaskTwoOperators_MachineUnionOperatorAdditive()
    var
        Attribution: Record "ALP Execution Time Attribution";
        AttributionSvc: Codeunit "ALP Execution Attribution Svc";
        OrderNo: Code[20];
    begin
        OrderNo := CopyStr('WO1-' + Format(CreateGuid()), 1, MaxStrLen(OrderNo));

        CreateClosedExecutionInterval(OrderNo, '10', 'WC-A', 'OP-A', CreateDateTime(20260501D, 080000T), CreateDateTime(20260501D, 080010T), 'a-start', 'a-end');
        CreateClosedExecutionInterval(OrderNo, '10', 'WC-A', 'OP-B', CreateDateTime(20260501D, 080002T), CreateDateTime(20260501D, 080008T), 'b-start', 'b-end');

        AttributionSvc.RefreshAll();

        FindAttribution(Attribution, Attribution."Attribution Type"::Machine, OrderNo, '10', 'WC-A', '');
        Assert.AreEqual(10.0, Attribution."Attributed Seconds", 'Machine union must count overlap once');
        Assert.AreEqual(2, Attribution."Interval Count", 'Machine attribution should count both participant intervals');

        FindAttribution(Attribution, Attribution."Attribution Type"::Operator, OrderNo, '10', 'WC-A', 'OP-A');
        Assert.AreEqual(10.0, Attribution."Attributed Seconds", 'OP-A receives full own interval');
        Assert.AreEqual(1, Attribution."Interval Count", 'OP-A should have one interval');

        FindAttribution(Attribution, Attribution."Attribution Type"::Operator, OrderNo, '10', 'WC-A', 'OP-B');
        Assert.AreEqual(6.0, Attribution."Attributed Seconds", 'OP-B receives full own interval');
        Assert.AreEqual(1, Attribution."Interval Count", 'OP-B should have one interval');
    end;

    [Test]
    procedure SameOperatorTwoOrders_OperatorTimeSplitsAcrossConcurrentOrders()
    var
        Attribution: Record "ALP Execution Time Attribution";
        AttributionSvc: Codeunit "ALP Execution Attribution Svc";
        OrderNo1: Code[20];
        OrderNo2: Code[20];
    begin
        OrderNo1 := CopyStr('WO1-' + Format(CreateGuid()), 1, MaxStrLen(OrderNo1));
        OrderNo2 := CopyStr('WO2-' + Format(CreateGuid()), 1, MaxStrLen(OrderNo2));

        CreateClosedExecutionInterval(OrderNo1, '10', 'WC-A', 'OP-A', CreateDateTime(20260501D, 080000T), CreateDateTime(20260501D, 080010T), 'wo1-start', 'wo1-end');
        CreateClosedExecutionInterval(OrderNo2, '20', 'WC-A', 'OP-A', CreateDateTime(20260501D, 080004T), CreateDateTime(20260501D, 080008T), 'wo2-start', 'wo2-end');

        AttributionSvc.RefreshAll();

        FindAttribution(Attribution, Attribution."Attribution Type"::Operator, OrderNo1, '10', 'WC-A', 'OP-A');
        Assert.AreEqual(8.0, Attribution."Attributed Seconds", 'WO-1 receives 4s solo + 2s overlap + 2s solo');
        Assert.AreEqual(1, Attribution."Interval Count", 'WO-1 should have one operator interval');

        FindAttribution(Attribution, Attribution."Attribution Type"::Operator, OrderNo2, '20', 'WC-A', 'OP-A');
        Assert.AreEqual(2.0, Attribution."Attributed Seconds", 'WO-2 receives half of 4s overlap');
        Assert.AreEqual(1, Attribution."Interval Count", 'WO-2 should have one operator interval');
    end;

    local procedure CreateClosedExecutionInterval(OrderNo: Code[20]; OperationNo: Code[10]; WorkCenterNo: Code[20]; OperatorId: Code[20]; StartTime: DateTime; EndTime: DateTime; StartMessageId: Text[50]; EndMessageId: Text[50])
    var
        WorkLogSvc: Codeunit "ALP Work Log Svc";
    begin
        WorkLogSvc.CreateClosedExecutionWorkLogEntry(
            CopyStr(StartMessageId + '-' + Format(CreateGuid()), 1, MaxStrLen(StartMessageId)),
            CopyStr(EndMessageId + '-' + Format(CreateGuid()), 1, MaxStrLen(EndMessageId)),
            OrderNo,
            OperationNo,
            WorkCenterNo,
            OperatorId,
            '',
            '',
            StartTime,
            EndTime,
            'TEST');
    end;

    local procedure FindAttribution(var Attribution: Record "ALP Execution Time Attribution"; AttributionType: Enum "ALP Time Attribution Type"; OrderNo: Code[20]; OperationNo: Code[10]; WorkCenterNo: Code[20]; OperatorId: Code[20])
    begin
        Attribution.Reset();
        Attribution.SetRange("Attribution Type", AttributionType);
        Attribution.SetRange("Order No.", OrderNo);
        Attribution.SetRange("Operation No.", OperationNo);
        Attribution.SetRange("Work Center No.", WorkCenterNo);
        Attribution.SetRange("Operator Id", OperatorId);
        Attribution.FindFirst();
    end;
}
