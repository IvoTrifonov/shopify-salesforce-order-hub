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
    static void ignoresLogThatIsNoLongerPending() {
        Sync_Log__c log = ShopifyTestData.pendingLog(ShopifyTestData.orderPayload());
        log.Status__c = 'Success';
        update log;

        deliver(new List<Sync_Log__c>{ log });

        Assert.areEqual(0, [SELECT COUNT() FROM Order], 'A redelivered event must not process the log again');
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
