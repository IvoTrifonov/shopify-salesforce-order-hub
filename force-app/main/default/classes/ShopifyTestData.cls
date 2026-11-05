/**
 * Test data built from the anonymized webhook payloads in the Shopify*Fixture
 * static resources. ShopifyOrderCreateFixture is the default order.
 *
 * The orders/updated fixtures are real deliveries from the dev store:
 * - Fulfilled: order #1005 (paid at checkout) after it was fulfilled, and with it closed
 * - Paid and Edited: order #1006 marked as paid, then edited to quantity 2 (now partially paid)
 * - Cancelled: order #1007 (payment pending) after it was cancelled by the customer
 */
@IsTest
public class ShopifyTestData {
    // From the fixture: one T-shirt line of 19.99 plus 8.00 shipping
    public static final Decimal FIXTURE_TOTAL = 27.99;
    public static final String FIXTURE_ORDER_ID = '17345318027345';
    public static final String FIXTURE_EMAIL = 'jane.doe@example.com';

    public static final String UPDATED_FULFILLED = 'ShopifyOrderUpdatedFulfilledFixture';
    public static final String UPDATED_PAID = 'ShopifyOrderUpdatedPaidFixture';
    public static final String UPDATED_EDITED = 'ShopifyOrderUpdatedEditedFixture';
    public static final String UPDATED_CANCELLED = 'ShopifyOrderUpdatedCancelledFixture';

    private static Map<String, String> fixtures = new Map<String, String>();

    public static String orderPayload() {
        return payload('ShopifyOrderCreateFixture');
    }

    public static String payload(String fixtureName) {
        if (!fixtures.containsKey(fixtureName)) {
            fixtures.put(fixtureName, [SELECT Body FROM StaticResource WHERE Name = :fixtureName].Body.toString());
        }
        return fixtures.get(fixtureName);
    }

    public static Map<String, Object> orderMap(String fixtureName) {
        return (Map<String, Object>) JSON.deserializeUntyped(payload(fixtureName));
    }

    /**
     * The order of the given fixture as it was before: open, not cancelled and with an earlier updated_at.
     */
    public static Map<String, Object> earlierVersion(String fixtureName) {
        Map<String, Object> order = orderMap(fixtureName);
        order.put('updated_at', '2026-11-01T08:00:00-05:00');
        order.put('closed_at', null);
        order.put('cancelled_at', null);
        order.put('cancel_reason', null);
        order.put('fulfillment_status', null);
        order.put('current_total_price', order.get('total_price'));
        return order;
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

    /**
     * A user whose only access comes from the given permission set, to run code as the
     * integration or guest user would (Minimum Access profile).
     */
    public static User restrictedUser(String permissionSetName) {
        User user = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce']
            .Id,
            LastName = 'Restricted',
            Alias = 'restrict',
            Email = 'restricted@example.com',
            Username = 'restricted.' + Crypto.getRandomInteger() + '@orderhub.test',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        // Setup objects (User, PermissionSetAssignment) can't share a transaction with other DML
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert user;
            insert new PermissionSetAssignment(
                AssigneeId = user.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName]
                .Id
            );
        }
        return user;
    }

    public static Sync_Log__c pendingLog(String payload) {
        return pendingLog(payload, 'orders/create');
    }

    public static Sync_Log__c pendingLog(String payload, String topic) {
        Sync_Log__c log = new Sync_Log__c(
            Direction__c = 'Inbound',
            Status__c = 'Pending',
            Event_Topic__c = topic,
            Payload__c = payload
        );
        insert log;
        return log;
    }
}
