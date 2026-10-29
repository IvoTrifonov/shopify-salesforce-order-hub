/**
 * Test data built from the anonymized orders/create payload in the
 * ShopifyOrderCreateFixture static resource.
 */
@IsTest
public class ShopifyTestData {
    // From the fixture: one T-shirt line of 19.99 plus 8.00 shipping
    public static final Decimal FIXTURE_TOTAL = 27.99;
    public static final String FIXTURE_ORDER_ID = '17345318027345';
    public static final String FIXTURE_EMAIL = 'jane.doe@example.com';

    private static String fixture;

    public static String orderPayload() {
        if (fixture == null) {
            fixture = [SELECT Body FROM StaticResource WHERE Name = 'ShopifyOrderCreateFixture'].Body.toString();
        }
        return fixture;
    }

    public static Map<String, Object> orderMap() {
        return (Map<String, Object>) JSON.deserializeUntyped(orderPayload());
    }

    /**
     * A distinct copy of the fixture order: unique order, line and shipping IDs and customer email.
     */
    public static Map<String, Object> orderMap(Integer index) {
        Map<String, Object> order = orderMap();
        order.put('id', (Long) order.get('id') + index);
        order.put('name', '#T' + index);
        order.put('email', 'customer' + index + '@example.com');
        ((Map<String, Object>) order.get('customer')).put('email', 'customer' + index + '@example.com');
        for (Object line : (List<Object>) order.get('line_items')) {
            ((Map<String, Object>) line).put('id', (Long) ((Map<String, Object>) line).get('id') + index);
        }
        for (Object line : (List<Object>) order.get('shipping_lines')) {
            ((Map<String, Object>) line).put('id', (Long) ((Map<String, Object>) line).get('id') + index);
        }
        return order;
    }

    public static ShopifyOrder order(Map<String, Object> orderMap) {
        return ShopifyOrder.parse(JSON.serialize(orderMap));
    }

    public static void activateStandardPricebook() {
        update new Pricebook2(Id = Test.getStandardPricebookId(), IsActive = true);
    }

    public static Sync_Log__c pendingLog(String payload) {
        Sync_Log__c log = new Sync_Log__c(
            Direction__c = 'Inbound',
            Status__c = 'Pending',
            Event_Topic__c = 'orders/create',
            Payload__c = payload
        );
        insert log;
        return log;
    }
}
