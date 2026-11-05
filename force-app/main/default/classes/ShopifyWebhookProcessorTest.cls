@IsTest
private class ShopifyWebhookProcessorTest {
    @TestSetup
    static void setup() {
        ShopifyTestData.activateStandardPricebook();
    }

    @IsTest
    static void createsOrderAndMarksLogSuccessful() {
        Sync_Log__c log = ShopifyTestData.pendingLog(ShopifyTestData.orderPayload());

        deliver(new List<Sync_Log__c>{ log });

        Sync_Log__c processed = [SELECT Status__c, Order__c, Order__r.Shopify_Order_Id__c FROM Sync_Log__c];
        Assert.areEqual('Success', processed.Status__c);
        Assert.areEqual(ShopifyTestData.FIXTURE_ORDER_ID, processed.Order__r.Shopify_Order_Id__c);
    }

    @IsTest
    static void isolatesFailingOrderFromTheRestOfTheBatch() {
        Map<String, Object> invalid = ShopifyTestData.orderMap(1);
        invalid.put('financial_status', 'not_a_shopify_status');
        Sync_Log__c failing = ShopifyTestData.pendingLog(JSON.serialize(invalid));
        Sync_Log__c valid = ShopifyTestData.pendingLog(JSON.serialize(ShopifyTestData.orderMap(2)));

        deliver(new List<Sync_Log__c>{ failing, valid });

        Sync_Log__c failed = [SELECT Status__c, Order__c, Error_Message__c FROM Sync_Log__c WHERE Id = :failing.Id];
        Assert.areEqual('Error', failed.Status__c);
        Assert.isNull(failed.Order__c);
        Assert.isTrue(failed.Error_Message__c.contains('Financial Status'), failed.Error_Message__c);

        Assert.areEqual('Success', [SELECT Status__c FROM Sync_Log__c WHERE Id = :valid.Id].Status__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Order], 'Only the valid order is created');
        Assert.areEqual(1, [SELECT COUNT() FROM Account], 'Records of the failed order are rolled back');
    }

    @IsTest
    static void marksUnparseablePayloadAsError() {
        Sync_Log__c log = ShopifyTestData.pendingLog('[1, 2, 3]');

        deliver(new List<Sync_Log__c>{ log });

        Sync_Log__c processed = [SELECT Status__c, Error_Message__c FROM Sync_Log__c];
        Assert.areEqual('Error', processed.Status__c);
        Assert.isNotNull(processed.Error_Message__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Order]);
    }

    @IsTest
    static void marksOutdatedUpdateAsSkipped() {
        new ShopifyOrderService()
            .upsertOrders(
                new List<ShopifyOrder>{ ShopifyOrder.parse(ShopifyTestData.payload(ShopifyTestData.UPDATED_FULFILLED)) }
            );
        Sync_Log__c log = ShopifyTestData.pendingLog(
            JSON.serialize(ShopifyTestData.earlierVersion(ShopifyTestData.UPDATED_FULFILLED)),
            'orders/updated'
        );

        deliver(new List<Sync_Log__c>{ log });

        Sync_Log__c processed = [SELECT Status__c, Order__c, Error_Message__c FROM Sync_Log__c];
        Assert.areEqual('Skipped', processed.Status__c);
        Assert.areEqual(ShopifyWebhookProcessor.OUTDATED_MESSAGE, processed.Error_Message__c);
        Order order = [SELECT Id, Shopify_Fulfillment_Status__c FROM Order];
        Assert.areEqual(order.Id, processed.Order__c, 'A skipped log still points at its order');
        Assert.areEqual('fulfilled', order.Shopify_Fulfillment_Status__c);
    }

    @IsTest
    static void appliesNewestOfTwoUpdatesInOneBatch() {
        Sync_Log__c edited = ShopifyTestData.pendingLog(
            ShopifyTestData.payload(ShopifyTestData.UPDATED_EDITED),
            'orders/updated'
        );
        Sync_Log__c paid = ShopifyTestData.pendingLog(
            ShopifyTestData.payload(ShopifyTestData.UPDATED_PAID),
            'orders/updated'
        );

        deliver(new List<Sync_Log__c>{ edited, paid });

        Order order = [SELECT Id, Financial_Status__c FROM Order];
        Assert.areEqual('partially_paid', order.Financial_Status__c);
        Sync_Log__c editedLog = [SELECT Status__c, Order__c FROM Sync_Log__c WHERE Id = :edited.Id];
        Sync_Log__c paidLog = [SELECT Status__c, Order__c FROM Sync_Log__c WHERE Id = :paid.Id];
        Assert.areEqual('Success', editedLog.Status__c);
        Assert.areEqual('Skipped', paidLog.Status__c, 'The older delivery arrived in the same batch');
        Assert.areEqual(order.Id, paidLog.Order__c);
    }

    @IsTest
    static void ignoresLogThatIsNoLongerPending() {
        Sync_Log__c log = ShopifyTestData.pendingLog(ShopifyTestData.orderPayload());
        log.Status__c = 'Success';
        update log;

        deliver(new List<Sync_Log__c>{ log });

        Assert.areEqual(0, [SELECT COUNT() FROM Order], 'A redelivered event must not process the log again');
    }

    // On API 67.0 queries and DML run in user mode, so the processor needs exactly what Order_Hub_Integration grants
    @IsTest
    static void processesOrderWithOnlyTheIntegrationPermissionSet() {
        User integrationUser = ShopifyTestData.restrictedUser('Order_Hub_Integration');
        Sync_Log__c log = ShopifyTestData.pendingLog(ShopifyTestData.orderPayload());

        Test.startTest();
        System.runAs(integrationUser) {
            ShopifyWebhookProcessor.process(
                new List<Shopify_Webhook__e>{
                    new Shopify_Webhook__e(Sync_Log_Id__c = log.Id, Topic__c = 'orders/create')
                }
            );
        }
        Test.stopTest();

        Sync_Log__c processed = [SELECT Status__c, Error_Message__c FROM Sync_Log__c];
        Assert.areEqual('Success', processed.Status__c, processed.Error_Message__c ?? 'no error message');
        Order order = [SELECT CreatedById, BillingStateCode, (SELECT Status__c FROM Invoices__r) FROM Order];
        Assert.areEqual(integrationUser.Id, order.CreatedById);
        Assert.areEqual('IL', order.BillingStateCode);
        Assert.areEqual(1, order.Invoices__r.size(), 'The paid order is invoiced');
    }

    @IsTest
    static void processesCancellationWithOnlyTheIntegrationPermissionSet() {
        User integrationUser = ShopifyTestData.restrictedUser('Order_Hub_Integration');
        Sync_Log__c open = ShopifyTestData.pendingLog(
            JSON.serialize(ShopifyTestData.earlierVersion(ShopifyTestData.UPDATED_CANCELLED))
        );
        Sync_Log__c cancelled = ShopifyTestData.pendingLog(
            ShopifyTestData.payload(ShopifyTestData.UPDATED_CANCELLED),
            'orders/updated'
        );

        Test.startTest();
        System.runAs(integrationUser) {
            for (Sync_Log__c log : new List<Sync_Log__c>{ open, cancelled }) {
                ShopifyWebhookProcessor.process(
                    new List<Shopify_Webhook__e>{
                        new Shopify_Webhook__e(Sync_Log_Id__c = log.Id, Topic__c = 'orders/updated')
                    }
                );
            }
        }
        Test.stopTest();

        for (Sync_Log__c processed : [SELECT Status__c, Error_Message__c FROM Sync_Log__c]) {
            Assert.areEqual('Success', processed.Status__c, processed.Error_Message__c ?? 'no error message');
        }
        Order order = [SELECT Shopify_Order_Status__c, Cancel_Reason__c, Cancelled_At__c FROM Order];
        Assert.areEqual('cancelled', order.Shopify_Order_Status__c);
        Assert.areEqual('customer', order.Cancel_Reason__c);
        Assert.isNotNull(order.Cancelled_At__c);
    }

    private static void deliver(List<Sync_Log__c> logs) {
        List<Shopify_Webhook__e> events = new List<Shopify_Webhook__e>();
        for (Sync_Log__c log : logs) {
            events.add(new Shopify_Webhook__e(Sync_Log_Id__c = log.Id, Topic__c = 'orders/create'));
        }
        Test.startTest();
        EventBus.publish(events);
        Test.stopTest();
    }
}
