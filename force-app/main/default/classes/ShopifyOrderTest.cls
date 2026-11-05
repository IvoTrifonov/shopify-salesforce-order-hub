@IsTest
private class ShopifyOrderTest {
    @IsTest
    static void parsesFixtureOrder() {
        ShopifyOrder order = ShopifyOrder.parse(ShopifyTestData.orderPayload());

        Assert.areEqual(ShopifyTestData.FIXTURE_ORDER_ID, order.shopifyId());
        Assert.areEqual('123 Main St', order.billing_address.street());
        Assert.areEqual('US', order.billing_address.country_code);
        Assert.areEqual('IL', order.shipping_address.province_code);
        Assert.areEqual(1, order.line_items.size());
        Assert.areEqual(1, order.shipping_lines.size());
    }

    @IsTest
    static void rejectsPayloadWithoutId() {
        for (String payload : new List<String>{ '{"name": "#1"}', 'null' }) {
            try {
                ShopifyOrder.parse(payload);
                Assert.fail('Expected a JSONException for ' + payload);
            } catch (JSONException e) {
                Assert.isTrue(e.getMessage().contains('missing id'), e.getMessage());
            }
        }
    }

    @IsTest
    static void defaultsMissingArraysToEmptyLists() {
        ShopifyOrder order = parse('{"id": 1}');

        Assert.areEqual(0, order.line_items.size());
        Assert.areEqual(0, order.shipping_lines.size());
    }

    @IsTest
    static void prefersOrderEmailAndNormalizesIt() {
        ShopifyOrder order = parse(
            '{"id": 1, "email": " Jane@Example.COM ", "customer": {"email": "other@example.com"}}'
        );

        Assert.areEqual('jane@example.com', order.customerEmail());
    }

    @IsTest
    static void fallsBackToCustomerEmail() {
        ShopifyOrder order = parse('{"id": 1, "email": "", "customer": {"email": "Jane@Example.com"}}');

        Assert.areEqual('jane@example.com', order.customerEmail());
    }

    @IsTest
    static void hasNoEmailWhenNoneIsGiven() {
        Assert.isNull(parse('{"id": 1}').customerEmail());
    }

    @IsTest
    static void namesCustomerFromFirstAndLastName() {
        ShopifyOrder order = parse('{"id": 1, "customer": {"first_name": "Jane", "last_name": "Doe"}}');

        Assert.areEqual('Jane Doe', order.customerName());
        Assert.areEqual('Doe', order.customerLastName());
    }

    @IsTest
    static void namesCustomerWithoutNameByEmail() {
        ShopifyOrder order = parse('{"id": 1, "email": "jane@example.com", "customer": {}}');

        Assert.areEqual('jane@example.com', order.customerName());
        Assert.areEqual('jane@example.com', order.customerLastName(), 'Contact.LastName is required');
    }

    @IsTest
    static void namesAnonymousCustomerByOrderId() {
        ShopifyOrder order = parse('{"id": 42}');

        Assert.areEqual('Shopify Customer 42', order.customerName());
        Assert.areEqual('Shopify Customer 42', order.customerLastName());
    }

    @IsTest
    static void usesShopDateOfProcessedAt() {
        ShopifyOrder order = parse(
            '{"id": 1, "processed_at": "2026-10-28T23:30:00-04:00", "updated_at": "2026-10-29T01:00:00-04:00"}'
        );

        Assert.areEqual(Date.newInstance(2026, 10, 28), order.processedDate(), 'Not shifted to UTC');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 10, 29, 5, 0, 0), order.updatedAt());
    }

    @IsTest
    static void fallsBackToUpdatedAtForOrderDate() {
        ShopifyOrder order = parse('{"id": 1, "updated_at": "2026-10-29T01:00:00-04:00"}');

        Assert.areEqual(Date.newInstance(2026, 10, 29), order.processedDate());
    }

    @IsTest
    static void hasNoUpdatedAtWhenMissing() {
        Assert.isNull(parse('{"id": 1}').updatedAt());
    }

    @IsTest
    static void readsCancellationOfCancelledFixture() {
        ShopifyOrder order = ShopifyOrder.parse(ShopifyTestData.payload(ShopifyTestData.UPDATED_CANCELLED));

        Assert.areEqual('cancelled', order.orderStatus());
        Assert.areEqual('customer', order.cancel_reason);
        // 2026-11-01T12:19:12-05:00
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 1, 17, 19, 12), order.cancelledAt());
        Assert.areEqual(0, order.currentTotal(), 'Cancelling sets the current total to zero');
    }

    @IsTest
    static void isClosedButNotCancelledAfterFulfillment() {
        ShopifyOrder order = ShopifyOrder.parse(ShopifyTestData.payload(ShopifyTestData.UPDATED_FULFILLED));

        Assert.areEqual('closed', order.orderStatus());
        Assert.isNull(order.cancelledAt());
    }

    @IsTest
    static void isOpenWithoutClosedOrCancelledDate() {
        Assert.areEqual('open', parse('{"id": 1}').orderStatus());
    }

    @IsTest
    static void prefersCurrentTotalOverCheckoutTotal() {
        Assert.areEqual(10, parse('{"id": 1, "total_price": "25.00", "current_total_price": "10.00"}').currentTotal());
        Assert.areEqual(25, parse('{"id": 1, "total_price": "25.00"}').currentTotal());
    }

    @IsTest
    static void comparesVersionsByUpdatedAt() {
        ShopifyOrder order = parse('{"id": 1, "updated_at": "2026-11-01T12:00:00-05:00"}');
        Datetime sameTime = Datetime.newInstanceGmt(2026, 11, 1, 17, 0, 0);

        Assert.isTrue(order.isOlderThan(sameTime.addSeconds(1)));
        Assert.isFalse(order.isOlderThan(sameTime), 'The same version is applied again');
        Assert.isFalse(order.isOlderThan(sameTime.addSeconds(-1)));
        Assert.isFalse(order.isOlderThan(null), 'An order without a stored version is never outdated');
        Assert.isFalse(parse('{"id": 1}').isOlderThan(sameTime), 'A payload without updated_at is applied');
    }

    @IsTest
    static void joinsAddressLinesIntoStreet() {
        ShopifyOrder.Address address = new ShopifyOrder.Address();
        address.address1 = '123 Main St ';
        address.address2 = 'Apt 4';

        Assert.areEqual('123 Main St\nApt 4', address.street());
    }

    @IsTest
    static void hasNoStreetWhenAddressLinesAreBlank() {
        ShopifyOrder.Address address = new ShopifyOrder.Address();
        address.address2 = ' ';

        Assert.isNull(address.street());
    }

    @IsTest
    static void convertsAmounts() {
        Assert.areEqual(19.99, ShopifyOrder.toAmount('19.99'));
        Assert.areEqual(0, ShopifyOrder.toAmount(''));
        Assert.areEqual(0, ShopifyOrder.toAmount(null));
    }

    private static ShopifyOrder parse(String payload) {
        return ShopifyOrder.parse(payload);
    }
}
