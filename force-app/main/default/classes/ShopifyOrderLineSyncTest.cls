/**
 * The line sync is exercised through ShopifyOrderService.upsertOrders, which supplies the stored
 * orders and creates the Orders that new lines belong to.
 */
@IsTest
private class ShopifyOrderLineSyncTest {
    // A later version of the default fixture order (#1002: one 19.99 T-shirt plus 8.00 shipping)
    private static final String EDITED_AT = '2026-10-29T09:00:00-04:00';
    private static final Long ADDED_LINE_ID = 46479812369999L;
    private static final Long ADDED_VARIANT_ID = 59824585769041L;

    @TestSetup
    static void setup() {
        ShopifyTestData.activateStandardPricebook();
    }

    @IsTest
    static void updatesQuantityChangedByOrderEdit() {
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_PAID));

        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_EDITED));

        Order order = onlyOrder();
        Assert.areEqual(1, order.OrderItems.size());
        Assert.areEqual(2, order.OrderItems[0].Quantity);
        Assert.areEqual(149.98, order.TotalAmount);
        Assert.areEqual(order.Shopify_Total_Price__c, order.TotalAmount, 'Lines add up to the current total');
        Assert.isFalse(order.Lines_Out_Of_Sync__c);
    }

    @IsTest
    static void addsLineAddedByOrderEdit() {
        upsertOrder(ShopifyTestData.orderMap());
        Map<String, Object> edited = editedVersion();
        ShopifyTestData.addLine(edited, ADDED_LINE_ID, ADDED_VARIANT_ID, '21.00');

        upsertOrder(edited);

        Order order = onlyOrder();
        Assert.areEqual(3, order.OrderItems.size());
        Assert.areEqual(27.99 + 21.00, order.TotalAmount);
        OrderItem added = [
            SELECT Quantity, UnitPrice, Product2.Name, Product2.Shopify_Variant_Id__c
            FROM OrderItem
            WHERE Shopify_Line_Item_Id__c = :String.valueOf(ADDED_LINE_ID)
        ];
        Assert.areEqual(1, added.Quantity);
        Assert.areEqual(21.00, added.UnitPrice);
        Assert.areEqual('Added Product', added.Product2.Name);
        Assert.areEqual(String.valueOf(ADDED_VARIANT_ID), added.Product2.Shopify_Variant_Id__c);
    }

    @IsTest
    static void deletesLineRemovedByOrderEdit() {
        upsertOrder(ShopifyTestData.orderMap());
        Map<String, Object> edited = editedVersion();
        ShopifyTestData.lineItem(edited, 0).put('current_quantity', 0);

        upsertOrder(edited);

        Order order = onlyOrder();
        Assert.areEqual(1, order.OrderItems.size(), 'Only the shipping line is left');
        Assert.areEqual(8.00, order.TotalAmount);
    }

    @IsTest
    static void deletesShippingLineRemovedByOrderEdit() {
        upsertOrder(ShopifyTestData.orderMap());
        Map<String, Object> edited = editedVersion();
        ShopifyTestData.shippingLine(edited, 0).put('is_removed', true);

        upsertOrder(edited);

        Order order = onlyOrder();
        Assert.areEqual(1, order.OrderItems.size(), 'Only the T-shirt is left');
        Assert.areEqual(19.99, order.TotalAmount);
    }

    @IsTest
    static void updatesShippingPriceChangedByOrderEdit() {
        upsertOrder(ShopifyTestData.orderMap());
        Map<String, Object> edited = editedVersion();
        ShopifyTestData.shippingLine(edited, 0).put('price', '5.00');

        upsertOrder(edited);

        Assert.areEqual(19.99 + 5.00, onlyOrder().TotalAmount);
    }

    @IsTest
    static void createsCurrentLinesForOrderFirstSeenAfterItChanged() {
        // orders/updated can arrive before orders/create, so the first version may already be edited or cancelled
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_EDITED));
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_CANCELLED));

        Order edited = [SELECT TotalAmount, (SELECT Quantity FROM OrderItems) FROM Order WHERE Name = '#1006'];
        Assert.areEqual(1, edited.OrderItems.size());
        Assert.areEqual(2, edited.OrderItems[0].Quantity);
        Order cancelled = [
            SELECT TotalAmount, Shopify_Total_Price__c, (SELECT Id FROM OrderItems)
            FROM Order
            WHERE Name = '#1007'
        ];
        Assert.areEqual(0, cancelled.OrderItems.size(), 'Cancelled lines are not created');
        Assert.areEqual(0, cancelled.TotalAmount);
        Assert.areEqual(cancelled.Shopify_Total_Price__c, cancelled.TotalAmount);
    }

    @IsTest
    static void leavesLinesAddedInSalesforceAlone() {
        upsertOrder(ShopifyTestData.orderMap());
        insert new OrderItem(
            OrderId = [SELECT Id FROM Order]
            .Id,
            PricebookEntryId = [
                SELECT Id
                FROM PricebookEntry
                WHERE Product2.Shopify_Variant_Id__c = :ShopifyOrderLineSync.SHIPPING_PRODUCT_KEY
            ]
            .Id,
            Description = 'Gift wrapping',
            Quantity = 1,
            UnitPrice = 3.00
        );
        Map<String, Object> edited = editedVersion();
        ShopifyTestData.lineItem(edited, 0).put('current_quantity', 0);
        ShopifyTestData.shippingLine(edited, 0).put('is_removed', true);

        upsertOrder(edited);

        List<OrderItem> items = [SELECT Description FROM OrderItem];
        Assert.areEqual(1, items.size());
        Assert.areEqual('Gift wrapping', items[0].Description);
    }

    @IsTest
    static void writesNoLinesWhenTheyAlreadyMatch() {
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_EDITED));

        Test.startTest();
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_EDITED));
        Integer dmlStatements = Limits.getDmlStatements();
        Test.stopTest();

        Assert.areEqual(1, dmlStatements, 'Only the order header is upserted');
    }

    @IsTest
    static void marksActivatedOrderAsOutOfSyncInsteadOfChangingItsLines() {
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_PAID));
        setStatus('Activated');

        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_EDITED));

        Order order = onlyOrder();
        Assert.isTrue(order.Lines_Out_Of_Sync__c);
        Assert.areEqual(1, order.OrderItems[0].Quantity, 'An activated order locks its lines');
        Assert.areEqual(149.98, order.Shopify_Total_Price__c, 'The header is still updated');
    }

    @IsTest
    static void doesNotMarkActivatedOrderWhoseLinesStillMatch() {
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_PAID));
        setStatus('Activated');
        Map<String, Object> fulfilled = ShopifyTestData.orderMap(ShopifyTestData.UPDATED_PAID);
        fulfilled.put('fulfillment_status', 'fulfilled');

        upsertOrder(fulfilled);

        Order order = onlyOrder();
        Assert.isFalse(order.Lines_Out_Of_Sync__c);
        Assert.areEqual('fulfilled', order.Shopify_Fulfillment_Status__c);
    }

    @IsTest
    static void updatesLinesAndClearsMarkOnceOrderIsBackInDraft() {
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_PAID));
        setStatus('Activated');
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_EDITED));
        setStatus('Draft');

        // Replaying the latest log applies the same version again
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_EDITED));

        Order order = onlyOrder();
        Assert.isFalse(order.Lines_Out_Of_Sync__c);
        Assert.areEqual(2, order.OrderItems[0].Quantity);
        Assert.areEqual(149.98, order.TotalAmount);
    }

    @IsTest
    static void ignoresLinesOfOutdatedVersion() {
        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_EDITED));

        upsertOrder(ShopifyTestData.payload(ShopifyTestData.UPDATED_PAID));

        Assert.areEqual(2, onlyOrder().OrderItems[0].Quantity, 'The older quantity is not applied');
    }

    @IsTest
    static void edits200OrdersWithConstantDmlAndQueries() {
        List<ShopifyOrder> created = new List<ShopifyOrder>();
        List<ShopifyOrder> edited = new List<ShopifyOrder>();
        for (Integer i = 0; i < 200; i++) {
            created.add(ShopifyTestData.order(ShopifyTestData.orderMap(i)));
            Map<String, Object> edit = ShopifyTestData.orderMap(i);
            edit.put('updated_at', EDITED_AT);
            ShopifyTestData.lineItem(edit, 0).put('current_quantity', 2);
            ShopifyTestData.shippingLine(edit, 0).put('is_removed', true);
            ShopifyTestData.addLine(edit, ADDED_LINE_ID + i, ADDED_VARIANT_ID, '21.00');
            edited.add(ShopifyTestData.order(edit));
        }
        new ShopifyOrderService().upsertOrders(created);

        Test.startTest();
        new ShopifyOrderService().upsertOrders(edited);
        Integer dmlStatements = Limits.getDmlStatements();
        Integer queries = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(400, [SELECT COUNT() FROM OrderItem], 'Shipping lines replaced by added lines');
        Assert.areEqual(200, [SELECT COUNT() FROM OrderItem WHERE Quantity = 2]);
        Assert.areEqual(0, [SELECT COUNT() FROM OrderItem WHERE Shopify_Line_Item_Id__c LIKE 'shipping:%']);
        // Order upsert; line delete, update and insert; product upsert and price book entry insert
        Assert.isTrue(dmlStatements <= 6, 'DML statements: ' + dmlStatements);
        Assert.isTrue(queries <= 4, 'SOQL queries: ' + queries);
    }

    private static Map<String, Object> editedVersion() {
        Map<String, Object> order = ShopifyTestData.orderMap();
        order.put('updated_at', EDITED_AT);
        return order;
    }

    private static void upsertOrder(Map<String, Object> orderMap) {
        new ShopifyOrderService().upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(orderMap) });
    }

    private static void upsertOrder(String payload) {
        new ShopifyOrderService().upsertOrders(new List<ShopifyOrder>{ ShopifyOrder.parse(payload) });
    }

    private static void setStatus(String status) {
        update new Order(Id = [SELECT Id FROM Order].Id, Status = status);
    }

    private static Order onlyOrder() {
        return [
            SELECT
                TotalAmount,
                Shopify_Total_Price__c,
                Shopify_Fulfillment_Status__c,
                Lines_Out_Of_Sync__c,
                (SELECT Quantity, UnitPrice FROM OrderItems ORDER BY UnitPrice DESC)
            FROM Order
        ];
    }
}
