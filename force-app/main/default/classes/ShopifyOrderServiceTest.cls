@IsTest
private class ShopifyOrderServiceTest {
    @TestSetup
    static void setup() {
        ShopifyTestData.activateStandardPricebook();
    }

    @IsTest
    static void createsOrderWithCustomerProductsAndLines() {
        Map<String, Id> orderIds = upsertOrders(new List<ShopifyOrder>{ ShopifyOrder.parse(ShopifyTestData.orderPayload()) });

        Order order = [
            SELECT
                Name,
                Status,
                EffectiveDate,
                TotalAmount,
                Pricebook2Id,
                AccountId,
                Account.Name,
                BillToContact.Email,
                BillToContact.AccountId,
                Shopify_Order_Name__c,
                Customer_Email__c,
                Financial_Status__c,
                Shopify_Fulfillment_Status__c,
                Shopify_Total_Price__c,
                Shopify_Updated_At__c
            FROM Order
            WHERE Id = :orderIds.get(ShopifyTestData.FIXTURE_ORDER_ID)
        ];
        Assert.areEqual('#1002', order.Name);
        Assert.areEqual('#1002', order.Shopify_Order_Name__c);
        Assert.areEqual('Draft', order.Status);
        Assert.areEqual(Date.newInstance(2026, 10, 28), order.EffectiveDate);
        Assert.areEqual(Test.getStandardPricebookId(), order.Pricebook2Id);
        Assert.areEqual('Jane Doe', order.Account.Name);
        Assert.areEqual(ShopifyTestData.FIXTURE_EMAIL, order.BillToContact.Email);
        Assert.areEqual(order.AccountId, order.BillToContact.AccountId);
        Assert.areEqual(ShopifyTestData.FIXTURE_EMAIL, order.Customer_Email__c);
        Assert.areEqual('paid', order.Financial_Status__c);
        Assert.areEqual('unfulfilled', order.Shopify_Fulfillment_Status__c);
        Assert.areEqual(ShopifyTestData.FIXTURE_TOTAL, order.Shopify_Total_Price__c);
        Assert.areEqual(order.Shopify_Total_Price__c, order.TotalAmount, 'Line items must add up to the Shopify total');
        // 2026-10-28T12:56:52-04:00
        Assert.areEqual(Datetime.newInstanceGmt(2026, 10, 28, 16, 56, 52), order.Shopify_Updated_At__c);

        List<OrderItem> items = [
            SELECT Quantity, UnitPrice, Variant_Title__c, Description, Product2.Name, Product2.Shopify_Variant_Id__c
            FROM OrderItem
            WHERE OrderId = :order.Id
            ORDER BY UnitPrice DESC
        ];
        Assert.areEqual(2, items.size());
        Assert.areEqual(19.99, items[0].UnitPrice);
        Assert.areEqual(1, items[0].Quantity);
        Assert.areEqual('Small / green', items[0].Variant_Title__c);
        Assert.areEqual('59824585736273', items[0].Product2.Shopify_Variant_Id__c);
        Assert.areEqual(8.00, items[1].UnitPrice);
        Assert.areEqual(ShopifyOrderService.SHIPPING_PRODUCT_KEY, items[1].Product2.Shopify_Variant_Id__c);
        Assert.areEqual('Shipping: Standard', items[1].Description);
    }

    @IsTest
    static void isIdempotentWhenTheSameOrderArrivesAgain() {
        ShopifyOrder order = ShopifyOrder.parse(ShopifyTestData.orderPayload());
        upsertOrders(new List<ShopifyOrder>{ order });

        upsertOrders(new List<ShopifyOrder>{ ShopifyOrder.parse(ShopifyTestData.orderPayload()) });

        Assert.areEqual(1, [SELECT COUNT() FROM Order]);
        Assert.areEqual(2, [SELECT COUNT() FROM OrderItem]);
        Assert.areEqual(1, [SELECT COUNT() FROM Account]);
        Assert.areEqual(1, [SELECT COUNT() FROM Contact]);
        Assert.areEqual(2, [SELECT COUNT() FROM Product2]);
        Assert.areEqual(2, [SELECT COUNT() FROM PricebookEntry]);
    }

    @IsTest
    static void updatesExistingOrderWithoutResettingStatus() {
        upsertOrders(new List<ShopifyOrder>{ ShopifyOrder.parse(ShopifyTestData.orderPayload()) });
        Order existing = [SELECT Id FROM Order];
        existing.Status = 'Activated';
        update existing;

        Map<String, Object> changed = ShopifyTestData.orderMap();
        changed.put('financial_status', 'refunded');
        upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(changed) });

        Order order = [SELECT Status, Financial_Status__c FROM Order];
        Assert.areEqual('Activated', order.Status);
        Assert.areEqual('refunded', order.Financial_Status__c);
    }

    @IsTest
    static void reusesAccountOfContactWithSameEmail() {
        Account account = new Account(Name = 'Existing Customer');
        insert account;
        insert new Contact(AccountId = account.Id, LastName = 'Doe', Email = ShopifyTestData.FIXTURE_EMAIL.toUpperCase());

        upsertOrders(new List<ShopifyOrder>{ ShopifyOrder.parse(ShopifyTestData.orderPayload()) });

        Assert.areEqual(account.Id, [SELECT AccountId FROM Order].AccountId);
        Assert.areEqual(1, [SELECT COUNT() FROM Account]);
        Assert.areEqual(1, [SELECT COUNT() FROM Contact]);
    }

    @IsTest
    static void createsSeparateCustomerForOrderWithoutEmail() {
        Map<String, Object> noEmail = ShopifyTestData.orderMap();
        noEmail.put('email', null);
        ((Map<String, Object>) noEmail.get('customer')).put('email', null);

        upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(noEmail) });

        Order order = [SELECT Customer_Email__c, BillToContact.LastName FROM Order];
        Assert.isNull(order.Customer_Email__c);
        Assert.areEqual('Doe', order.BillToContact.LastName);
    }

    @IsTest
    static void mapsLineWithoutVariantToCustomItemProduct() {
        Map<String, Object> custom = ShopifyTestData.orderMap();
        ((Map<String, Object>) ((List<Object>) custom.get('line_items'))[0]).put('variant_id', null);

        upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(custom) });

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM OrderItem
                WHERE Product2.Shopify_Variant_Id__c = :ShopifyOrderService.CUSTOM_ITEM_PRODUCT_KEY
            ]
        );
    }

    @IsTest
    static void keepsLatestVersionWhenOrderAppearsTwiceInOneBatch() {
        Map<String, Object> older = ShopifyTestData.orderMap();
        Map<String, Object> newer = ShopifyTestData.orderMap();
        newer.put('updated_at', '2026-10-29T09:00:00-04:00');
        newer.put('financial_status', 'refunded');

        upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(newer), ShopifyTestData.order(older) });

        Assert.areEqual('refunded', [SELECT Financial_Status__c FROM Order].Financial_Status__c);
    }

    @IsTest
    static void processes200OrdersWithConstantDmlAndQueries() {
        List<ShopifyOrder> orders = new List<ShopifyOrder>();
        for (Integer i = 0; i < 200; i++) {
            orders.add(ShopifyTestData.order(ShopifyTestData.orderMap(i)));
        }

        Test.startTest();
        new ShopifyOrderService().upsertOrders(orders);
        Integer dmlStatements = Limits.getDmlStatements();
        Integer queries = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Order]);
        Assert.areEqual(400, [SELECT COUNT() FROM OrderItem]);
        Assert.areEqual(200, [SELECT COUNT() FROM Contact]);
        Assert.areEqual(2, [SELECT COUNT() FROM Product2], 'Orders share the T-shirt and shipping products');
        Assert.isTrue(dmlStatements <= 7, 'DML statements: ' + dmlStatements);
        Assert.isTrue(queries <= 5, 'SOQL queries: ' + queries);
    }

    private static Map<String, Id> upsertOrders(List<ShopifyOrder> orders) {
        return new ShopifyOrderService().upsertOrders(orders);
    }
}
