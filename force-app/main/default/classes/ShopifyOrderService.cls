/**
 * Creates or updates Salesforce records from Shopify orders: the customer's
 * Account and Contact, a Product2 and standard PricebookEntry per variant, the
 * Order and its OrderItems. Shipping is stored as an OrderItem on a dedicated
 * product, so Order.TotalAmount equals Shopify's total_price.
 *
 * Every step is idempotent (keyed by Shopify IDs) and bulkified: the DML and
 * SOQL count does not grow with the number of orders.
 *
 * Runs `without sharing`: customers must be matched against all Contacts, not
 * just those the running integration user can see, or duplicates are created.
 */
public without sharing class ShopifyOrderService {
    @TestVisible
    private static final String SHIPPING_PRODUCT_KEY = 'SHIPPING';
    @TestVisible
    private static final String CUSTOM_ITEM_PRODUCT_KEY = 'CUSTOM_ITEM';
    @TestVisible
    private static final String SHIPPING_LINE_PREFIX = 'shipping:';
    private static final String UNFULFILLED = 'unfulfilled';
    private static final String NEW_ORDER_STATUS = 'Draft';

    private final Id pricebookId = standardPricebookId();

    /**
     * Upserts the given orders and returns the Salesforce Order Id by Shopify order ID.
     */
    public Map<String, Id> upsertOrders(List<ShopifyOrder> shopifyOrders) {
        List<ShopifyOrder> orders = latestVersions(shopifyOrders);
        Map<String, Contact> contactsByCustomerKey = upsertCustomers(orders);
        Map<String, Id> entryIdsByProductKey = upsertProducts(orders);
        Map<String, Order> ordersByShopifyId = upsertOrderHeaders(orders, contactsByCustomerKey);
        upsertOrderItems(orders, ordersByShopifyId, entryIdsByProductKey);

        Map<String, Id> orderIds = new Map<String, Id>();
        for (String shopifyId : ordersByShopifyId.keySet()) {
            orderIds.put(shopifyId, ordersByShopifyId.get(shopifyId).Id);
        }
        return orderIds;
    }

    // The same order can arrive more than once in a batch; upserting duplicate external IDs fails
    private static List<ShopifyOrder> latestVersions(List<ShopifyOrder> orders) {
        Map<Long, ShopifyOrder> latestById = new Map<Long, ShopifyOrder>();
        for (ShopifyOrder order : orders) {
            ShopifyOrder current = latestById.get(order.id);
            if (current == null || current.updatedAt() == null || order.updatedAt() >= current.updatedAt()) {
                latestById.put(order.id, order);
            }
        }
        return latestById.values();
    }

    // Customers are matched by email; orders without one get their own Account and Contact
    private static String customerKey(ShopifyOrder order) {
        return order.customerEmail() ?? 'order:' + order.shopifyId();
    }

    private Map<String, Contact> upsertCustomers(List<ShopifyOrder> orders) {
        Map<String, ShopifyOrder> ordersByCustomerKey = new Map<String, ShopifyOrder>();
        for (ShopifyOrder order : orders) {
            if (!ordersByCustomerKey.containsKey(customerKey(order))) {
                ordersByCustomerKey.put(customerKey(order), order);
            }
        }

        // Oldest Contact wins when an email already has duplicates
        Map<String, Contact> contactsByCustomerKey = new Map<String, Contact>();
        for (Contact existing : [
            SELECT Id, AccountId, Email
            FROM Contact
            WHERE Email IN :ordersByCustomerKey.keySet()
            ORDER BY CreatedDate
        ]) {
            String key = existing.Email.toLowerCase();
            if (!contactsByCustomerKey.containsKey(key)) {
                contactsByCustomerKey.put(key, existing);
            }
        }

        Map<String, Account> newAccounts = new Map<String, Account>();
        for (String key : ordersByCustomerKey.keySet()) {
            if (!contactsByCustomerKey.containsKey(key)) {
                newAccounts.put(key, new Account(Name = ordersByCustomerKey.get(key).customerName()));
            }
        }
        if (newAccounts.isEmpty()) {
            return contactsByCustomerKey;
        }
        insert newAccounts.values();

        Map<String, Contact> newContacts = new Map<String, Contact>();
        for (String key : newAccounts.keySet()) {
            ShopifyOrder order = ordersByCustomerKey.get(key);
            newContacts.put(
                key,
                new Contact(
                    AccountId = newAccounts.get(key).Id,
                    FirstName = order.customer?.first_name,
                    LastName = order.customerLastName(),
                    Email = order.customerEmail()
                )
            );
        }
        insert newContacts.values();
        contactsByCustomerKey.putAll(newContacts);
        return contactsByCustomerKey;
    }

    private static String productKey(ShopifyOrder.LineItem line) {
        // Custom line items and deleted products have no variant
        return line.variant_id == null ? CUSTOM_ITEM_PRODUCT_KEY : String.valueOf(line.variant_id);
    }

    private Map<String, Id> upsertProducts(List<ShopifyOrder> orders) {
        Map<String, Product2> productsByKey = new Map<String, Product2>();
        Map<String, Decimal> listPricesByKey = new Map<String, Decimal>();
        for (ShopifyOrder order : orders) {
            for (ShopifyOrder.LineItem line : order.line_items) {
                String key = productKey(line);
                listPricesByKey.put(key, ShopifyOrder.toAmount(line.price));
                productsByKey.put(
                    key,
                    key == CUSTOM_ITEM_PRODUCT_KEY
                        ? syntheticProduct(key, 'Shopify Custom Item')
                        : new Product2(
                              Name = line.name.left(Product2.Name.getDescribe().getLength()),
                              ProductCode = line.sku,
                              Shopify_Product_Id__c = String.valueOf(line.product_id),
                              Shopify_Variant_Id__c = key,
                              IsActive = true
                          )
                );
            }
            if (!order.shipping_lines.isEmpty()) {
                productsByKey.put(SHIPPING_PRODUCT_KEY, syntheticProduct(SHIPPING_PRODUCT_KEY, 'Shipping'));
                listPricesByKey.put(SHIPPING_PRODUCT_KEY, 0);
            }
        }
        if (productsByKey.isEmpty()) {
            return new Map<String, Id>();
        }
        upsert productsByKey.values() Product2.Shopify_Variant_Id__c;

        Map<Id, String> keysByProductId = new Map<Id, String>();
        for (String key : productsByKey.keySet()) {
            keysByProductId.put(productsByKey.get(key).Id, key);
        }
        Map<String, Id> entryIdsByKey = new Map<String, Id>();
        for (PricebookEntry entry : [
            SELECT Id, Product2Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId AND Product2Id IN :keysByProductId.keySet()
        ]) {
            entryIdsByKey.put(keysByProductId.get(entry.Product2Id), entry.Id);
        }

        List<PricebookEntry> newEntries = new List<PricebookEntry>();
        for (String key : productsByKey.keySet()) {
            if (!entryIdsByKey.containsKey(key)) {
                newEntries.add(
                    new PricebookEntry(
                        Pricebook2Id = pricebookId,
                        Product2Id = productsByKey.get(key).Id,
                        UnitPrice = listPricesByKey.get(key),
                        IsActive = true
                    )
                );
            }
        }
        insert newEntries;
        for (PricebookEntry entry : newEntries) {
            entryIdsByKey.put(keysByProductId.get(entry.Product2Id), entry.Id);
        }
        return entryIdsByKey;
    }

    private static Product2 syntheticProduct(String key, String name) {
        return new Product2(Name = name, ProductCode = key, Shopify_Variant_Id__c = key, IsActive = true);
    }

    private Map<String, Order> upsertOrderHeaders(List<ShopifyOrder> orders, Map<String, Contact> contactsByCustomerKey) {
        Set<String> shopifyIds = new Set<String>();
        for (ShopifyOrder order : orders) {
            shopifyIds.add(order.shopifyId());
        }
        Set<String> existingIds = new Set<String>();
        for (Order existing : [SELECT Shopify_Order_Id__c FROM Order WHERE Shopify_Order_Id__c IN :shopifyIds]) {
            existingIds.add(existing.Shopify_Order_Id__c);
        }

        Map<String, Order> ordersByShopifyId = new Map<String, Order>();
        for (ShopifyOrder order : orders) {
            Contact customer = contactsByCustomerKey.get(customerKey(order));
            Order record = new Order(
                Shopify_Order_Id__c = order.shopifyId(),
                Name = order.name,
                Shopify_Order_Name__c = order.name,
                AccountId = customer.AccountId,
                BillToContactId = customer.Id,
                Customer_Email__c = order.customerEmail(),
                EffectiveDate = order.processedDate(),
                Financial_Status__c = order.financial_status,
                Shopify_Fulfillment_Status__c = order.fulfillment_status ?? UNFULFILLED,
                Shopify_Total_Price__c = ShopifyOrder.toAmount(order.total_price),
                Shopify_Updated_At__c = order.updatedAt()
            );
            // Status and price book are set on creation only; they are managed in Salesforce afterwards
            if (!existingIds.contains(order.shopifyId())) {
                record.Status = NEW_ORDER_STATUS;
                record.Pricebook2Id = pricebookId;
            }
            ordersByShopifyId.put(order.shopifyId(), record);
        }
        upsert ordersByShopifyId.values() Order.Shopify_Order_Id__c;
        return ordersByShopifyId;
    }

    private void upsertOrderItems(
        List<ShopifyOrder> orders,
        Map<String, Order> ordersByShopifyId,
        Map<String, Id> entryIdsByProductKey
    ) {
        Map<String, OrderItem> itemsByLineId = new Map<String, OrderItem>();
        for (ShopifyOrder order : orders) {
            Id orderId = ordersByShopifyId.get(order.shopifyId()).Id;
            for (ShopifyOrder.LineItem line : order.line_items) {
                itemsByLineId.put(
                    String.valueOf(line.id),
                    new OrderItem(
                        OrderId = orderId,
                        PricebookEntryId = entryIdsByProductKey.get(productKey(line)),
                        Shopify_Line_Item_Id__c = String.valueOf(line.id),
                        Variant_Title__c = line.variant_title,
                        Quantity = line.quantity,
                        UnitPrice = ShopifyOrder.toAmount(line.price)
                    )
                );
            }
            for (ShopifyOrder.ShippingLine shipping : order.shipping_lines) {
                itemsByLineId.put(
                    SHIPPING_LINE_PREFIX + shipping.id,
                    new OrderItem(
                        OrderId = orderId,
                        PricebookEntryId = entryIdsByProductKey.get(SHIPPING_PRODUCT_KEY),
                        Shopify_Line_Item_Id__c = SHIPPING_LINE_PREFIX + shipping.id,
                        Description = 'Shipping: ' + shipping.title,
                        Quantity = 1,
                        UnitPrice = ShopifyOrder.toAmount(shipping.price)
                    )
                );
            }
        }
        if (itemsByLineId.isEmpty()) {
            return;
        }

        // OrderId and PricebookEntryId cannot be updated, so they are only sent for new lines
        for (OrderItem existing : [
            SELECT Shopify_Line_Item_Id__c
            FROM OrderItem
            WHERE Shopify_Line_Item_Id__c IN :itemsByLineId.keySet()
        ]) {
            OrderItem item = itemsByLineId.get(existing.Shopify_Line_Item_Id__c);
            itemsByLineId.put(
                existing.Shopify_Line_Item_Id__c,
                new OrderItem(
                    Shopify_Line_Item_Id__c = item.Shopify_Line_Item_Id__c,
                    Variant_Title__c = item.Variant_Title__c,
                    Description = item.Description,
                    Quantity = item.Quantity,
                    UnitPrice = item.UnitPrice
                )
            );
        }
        upsert itemsByLineId.values() OrderItem.Shopify_Line_Item_Id__c;
    }

    private static Id standardPricebookId() {
        // The standard price book is not visible to tests without SeeAllData
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1].Id;
    }
}
