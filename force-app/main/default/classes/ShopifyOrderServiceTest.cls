@IsTest
private class ShopifyOrderServiceTest {
    @TestSetup
    static void setup() {
        ShopifyTestData.activateStandardPricebook();
    }

    @IsTest
    static void createsOrderWithCustomerProductsAndLines() {
        Map<String, Order> orders = upsertOrders(
            new List<ShopifyOrder>{ ShopifyOrder.parse(ShopifyTestData.orderPayload()) }
        );

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
                Shopify_Updated_At__c,
                Shopify_Order_Status__c,
                Cancelled_At__c,
                Cancel_Reason__c
            FROM Order
            WHERE Id = :orders.get(ShopifyTestData.FIXTURE_ORDER_ID).Id
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
        Assert.areEqual('open', order.Shopify_Order_Status__c);
        Assert.isNull(order.Cancelled_At__c);
        Assert.isNull(order.Cancel_Reason__c);

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
        Assert.areEqual(ShopifyOrderLineSync.SHIPPING_PRODUCT_KEY, items[1].Product2.Shopify_Variant_Id__c);
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
    static void appliesShopifyChangesToActivatedOrderWithoutTouchingLines() {
        upsertOrders(new List<ShopifyOrder>{ fixtureOrder(ShopifyTestData.UPDATED_PAID) });
        Order existing = [SELECT Id FROM Order];
        existing.Status = 'Activated';
        update existing;

        upsertOrders(new List<ShopifyOrder>{ fixtureOrder(ShopifyTestData.UPDATED_EDITED) });

        Order order = [
            SELECT
                Status,
                Financial_Status__c,
                Shopify_Order_Status__c,
                Shopify_Total_Price__c,
                TotalAmount,
                Lines_Out_Of_Sync__c,
                (SELECT Quantity FROM OrderItems)
            FROM Order
        ];
        Assert.areEqual('Activated', order.Status, 'Order.Status is owned by Salesforce');
        Assert.areEqual('partially_paid', order.Financial_Status__c);
        Assert.areEqual('open', order.Shopify_Order_Status__c);
        Assert.areEqual(149.98, order.Shopify_Total_Price__c);
        Assert.areEqual(1, order.OrderItems.size());
        Assert.areEqual(1, order.OrderItems[0].Quantity, 'An activated order locks its lines');
        Assert.areEqual(74.99, order.TotalAmount);
        Assert.isTrue(order.Lines_Out_Of_Sync__c);
    }

    @IsTest
    static void recordsCancellationFromShopify() {
        upsertOrders(
            new List<ShopifyOrder>{
                ShopifyTestData.order(ShopifyTestData.earlierVersion(ShopifyTestData.UPDATED_CANCELLED))
            }
        );

        upsertOrders(new List<ShopifyOrder>{ fixtureOrder(ShopifyTestData.UPDATED_CANCELLED) });

        Order order = [
            SELECT
                Status,
                Shopify_Order_Status__c,
                Cancelled_At__c,
                Cancel_Reason__c,
                Shopify_Total_Price__c,
                TotalAmount,
                (SELECT Id FROM OrderItems)
            FROM Order
        ];
        Assert.areEqual('Draft', order.Status);
        Assert.areEqual('cancelled', order.Shopify_Order_Status__c);
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 1, 17, 19, 12), order.Cancelled_At__c);
        Assert.areEqual('customer', order.Cancel_Reason__c);
        Assert.areEqual(0, order.Shopify_Total_Price__c);
        Assert.areEqual(0, order.OrderItems.size(), 'Cancelled lines are deleted');
        Assert.areEqual(0, order.TotalAmount);
    }

    @IsTest
    static void createsOrderFromUpdateThatArrivesBeforeTheCreate() {
        upsertOrders(new List<ShopifyOrder>{ fixtureOrder(ShopifyTestData.UPDATED_FULFILLED) });

        Order order = [
            SELECT Status, Shopify_Order_Status__c, Shopify_Fulfillment_Status__c, TotalAmount, Shopify_Total_Price__c
            FROM Order
        ];
        Assert.areEqual('Draft', order.Status);
        Assert.areEqual('closed', order.Shopify_Order_Status__c);
        Assert.areEqual('fulfilled', order.Shopify_Fulfillment_Status__c);
        Assert.areEqual(34.99, order.Shopify_Total_Price__c);
        Assert.areEqual(order.Shopify_Total_Price__c, order.TotalAmount);
    }

    @IsTest
    static void ignoresVersionOlderThanTheStoredOne() {
        ShopifyOrder fulfilled = fixtureOrder(ShopifyTestData.UPDATED_FULFILLED);
        upsertOrders(new List<ShopifyOrder>{ fulfilled });

        Map<String, Order> result = upsertOrders(
            new List<ShopifyOrder>{
                ShopifyTestData.order(ShopifyTestData.earlierVersion(ShopifyTestData.UPDATED_FULFILLED))
            }
        );

        Order order = [
            SELECT Id, Shopify_Fulfillment_Status__c, Shopify_Order_Status__c, Shopify_Updated_At__c
            FROM Order
        ];
        Assert.areEqual('fulfilled', order.Shopify_Fulfillment_Status__c);
        Assert.areEqual('closed', order.Shopify_Order_Status__c);
        // 2026-11-01T12:01:57-05:00
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 1, 17, 1, 57), order.Shopify_Updated_At__c);
        Order returned = result.get(fulfilled.shopifyId());
        Assert.areEqual(order.Id, returned.Id, 'The stored order is returned for an outdated version');
        Assert.areEqual(order.Shopify_Updated_At__c, returned.Shopify_Updated_At__c);
    }

    @IsTest
    static void reusesAccountOfContactWithSameEmail() {
        Account account = new Account(Name = 'Existing Customer');
        insert account;
        insert new Contact(
            AccountId = account.Id,
            LastName = 'Doe',
            Email = ShopifyTestData.FIXTURE_EMAIL.toUpperCase()
        );

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

    // Like a draft order created in the Shopify admin without a customer
    @IsTest
    static void keepsCustomerOfStoredOrderWithoutEmail() {
        Map<String, Object> noCustomer = ShopifyTestData.orderMap();
        noCustomer.put('email', '');
        noCustomer.put('customer', null);
        upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(noCustomer) });
        Order created = [SELECT AccountId, BillToContactId FROM Order];

        noCustomer.put('updated_at', '2026-10-29T09:00:00-04:00');
        upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(noCustomer) });
        upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(noCustomer) });

        Order order = [SELECT AccountId, BillToContactId, Account.Name FROM Order];
        Assert.areEqual(created.AccountId, order.AccountId);
        Assert.areEqual(created.BillToContactId, order.BillToContactId);
        Assert.areEqual('Shopify Customer ' + ShopifyTestData.FIXTURE_ORDER_ID, order.Account.Name);
        Assert.areEqual(1, [SELECT COUNT() FROM Account], 'Updates must not create another customer');
        Assert.areEqual(1, [SELECT COUNT() FROM Contact]);
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
                WHERE Product2.Shopify_Variant_Id__c = :ShopifyOrderLineSync.CUSTOM_ITEM_PRODUCT_KEY
            ]
        );
    }

    @IsTest
    static void mapsBillingAndShippingAddresses() {
        Map<String, Object> payload = ShopifyTestData.orderMap();
        Map<String, Object> shipping = (Map<String, Object>) payload.get('shipping_address');
        shipping.put('address1', '1 Warehouse Rd');
        shipping.put('address2', 'Dock 3');
        shipping.put('city', 'Toronto');
        shipping.put('zip', 'M5V 2T6');
        shipping.put('country_code', 'CA');
        shipping.put('province_code', 'ON');

        upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(payload) });

        Order order = [
            SELECT
                BillingStreet,
                BillingCity,
                BillingPostalCode,
                BillingStateCode,
                BillingCountryCode,
                ShippingStreet,
                ShippingCity,
                ShippingPostalCode,
                ShippingStateCode,
                ShippingCountryCode
            FROM Order
        ];
        Assert.areEqual('123 Main St', order.BillingStreet);
        Assert.areEqual('Springfield', order.BillingCity);
        Assert.areEqual('62701', order.BillingPostalCode);
        Assert.areEqual('IL', order.BillingStateCode);
        Assert.areEqual('US', order.BillingCountryCode);
        Assert.areEqual('1 Warehouse Rd\nDock 3', order.ShippingStreet);
        Assert.areEqual('Toronto', order.ShippingCity);
        Assert.areEqual('M5V 2T6', order.ShippingPostalCode);
        Assert.areEqual('ON', order.ShippingStateCode);
        Assert.areEqual('CA', order.ShippingCountryCode);
    }

    @IsTest
    static void leavesOutAddressCodesTheOrgDoesNotKnow() {
        Map<String, Object> payload = ShopifyTestData.orderMap();
        ((Map<String, Object>) payload.get('billing_address')).put('country_code', 'XX');
        ((Map<String, Object>) payload.get('shipping_address')).put('province_code', 'ON');

        upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(payload) });

        Order order = [
            SELECT BillingStreet, BillingStateCode, BillingCountryCode, ShippingStateCode, ShippingCountryCode
            FROM Order
        ];
        Assert.areEqual('123 Main St', order.BillingStreet, 'The rest of the address is kept');
        Assert.isNull(order.BillingCountryCode);
        Assert.isNull(order.BillingStateCode, 'A state needs a valid country');
        Assert.areEqual('US', order.ShippingCountryCode);
        Assert.isNull(order.ShippingStateCode, 'Ontario is not a US state');
    }

    @IsTest
    static void clearsAddressesThatAreNoLongerInThePayload() {
        upsertOrders(new List<ShopifyOrder>{ ShopifyOrder.parse(ShopifyTestData.orderPayload()) });

        Map<String, Object> withoutAddresses = ShopifyTestData.orderMap();
        withoutAddresses.put('billing_address', null);
        withoutAddresses.remove('shipping_address');
        upsertOrders(new List<ShopifyOrder>{ ShopifyTestData.order(withoutAddresses) });

        Order order = [SELECT BillingStreet, BillingCountryCode, ShippingCity, ShippingStateCode FROM Order];
        Assert.isNull(order.BillingStreet);
        Assert.isNull(order.BillingCountryCode);
        Assert.isNull(order.ShippingCity);
        Assert.isNull(order.ShippingStateCode);
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

    @IsTest
    static void updates200OrdersWithConstantDmlAndQueries() {
        List<ShopifyOrder> created = new List<ShopifyOrder>();
        List<ShopifyOrder> cancelled = new List<ShopifyOrder>();
        for (Integer i = 0; i < 200; i++) {
            created.add(ShopifyTestData.order(ShopifyTestData.orderMap(i)));
            Map<String, Object> cancellation = ShopifyTestData.orderMap(i);
            cancellation.put('updated_at', '2026-10-29T09:00:00-04:00');
            cancellation.put('cancelled_at', '2026-10-29T09:00:00-04:00');
            cancellation.put('cancel_reason', 'inventory');
            cancelled.add(ShopifyTestData.order(cancellation));
        }
        new ShopifyOrderService().upsertOrders(created);

        Test.startTest();
        new ShopifyOrderService().upsertOrders(cancelled);
        Integer dmlStatements = Limits.getDmlStatements();
        Integer queries = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Order WHERE Shopify_Order_Status__c = 'cancelled']);
        Assert.areEqual(400, [SELECT COUNT() FROM OrderItem], 'Lines are unchanged');
        Assert.isTrue(dmlStatements <= 3, 'DML statements: ' + dmlStatements);
        Assert.isTrue(queries <= 5, 'SOQL queries: ' + queries);
    }

    private static ShopifyOrder fixtureOrder(String fixtureName) {
        return ShopifyOrder.parse(ShopifyTestData.payload(fixtureName));
    }

    private static Map<String, Order> upsertOrders(List<ShopifyOrder> orders) {
        return new ShopifyOrderService().upsertOrders(orders);
    }
}
