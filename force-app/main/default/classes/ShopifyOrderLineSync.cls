/**
 * Keeps the lines of Shopify orders in step with Shopify's current lines: one OrderItem per
 * line item and per shipping line, on a Product2 and standard PricebookEntry per variant.
 * Shipping and custom items (lines without a variant) use dedicated products, so
 * Order.TotalAmount matches Shopify's current total as long as an order has no discounts or
 * taxes, which are not stored on lines.
 *
 * Shopify keeps removed lines in its payload, with current_quantity 0 or is_removed. Salesforce
 * does not allow order products with quantity 0, so their OrderItems are deleted. OrderItems
 * without a Shopify line ID were added in Salesforce and are left alone.
 *
 * The changes are planned when the sync is created and written by apply(), once the Orders of
 * new Shopify orders exist. An activated order locks its OrderItems: its changes are not
 * written, and markOutOfSync() flags the order instead.
 *
 * Runs with the sharing of its caller, ShopifyOrderService, as part of the same upsert.
 */
public inherited sharing class ShopifyOrderLineSync {
    @TestVisible
    private static final String SHIPPING_PRODUCT_KEY = 'SHIPPING';
    @TestVisible
    private static final String CUSTOM_ITEM_PRODUCT_KEY = 'CUSTOM_ITEM';
    @TestVisible
    private static final String SHIPPING_LINE_PREFIX = 'shipping:';
    private static final String DRAFT = 'Draft';

    private final Id pricebookId;
    private final List<WantedItem> newItems = new List<WantedItem>();
    private final List<OrderItem> changedItems = new List<OrderItem>();
    private final List<OrderItem> removedItems = new List<OrderItem>();
    private final Set<String> outOfSyncOrderIds = new Set<String>();

    /**
     * Plans the line changes for the given order versions.
     *
     * @param orders the Shopify orders being applied
     * @param storedByShopifyId the Orders Salesforce already holds (Id and StatusCode), by Shopify order ID
     * @param pricebookId the price book of the orders' lines
     */
    public ShopifyOrderLineSync(List<ShopifyOrder> orders, Map<String, Order> storedByShopifyId, Id pricebookId) {
        this.pricebookId = pricebookId;
        Map<String, OrderItem> storedItems = storedItemsByLineKey(orders, storedByShopifyId);
        for (ShopifyOrder order : orders) {
            Changes changes = new Changes(order, storedItems);
            Order stored = storedByShopifyId.get(order.shopifyId());
            if (stored == null || stored.StatusCode == DRAFT) {
                newItems.addAll(changes.added);
                changedItems.addAll(changes.changed);
                removedItems.addAll(changes.removed);
            } else if (!changes.isEmpty()) {
                outOfSyncOrderIds.add(order.shopifyId());
            }
        }
    }

    /**
     * Sets Lines_Out_Of_Sync__c on the given order headers: true for an activated order whose
     * lines differ from Shopify's, false once they match again.
     */
    public void markOutOfSync(List<Order> headers) {
        for (Order header : headers) {
            header.Lines_Out_Of_Sync__c = outOfSyncOrderIds.contains(header.Shopify_Order_Id__c);
        }
    }

    /**
     * Writes the planned changes. New lines are added to the given Orders, which must exist by now.
     */
    public void apply(Map<String, Order> ordersByShopifyId) {
        if (!removedItems.isEmpty()) {
            delete removedItems;
        }
        if (!changedItems.isEmpty()) {
            update changedItems;
        }
        if (newItems.isEmpty()) {
            return;
        }
        Map<String, Id> entryIdsByProductKey = upsertProducts();
        List<OrderItem> inserts = new List<OrderItem>();
        for (WantedItem wanted : newItems) {
            wanted.item.OrderId = ordersByShopifyId.get(wanted.shopifyOrderId).Id;
            wanted.item.PricebookEntryId = entryIdsByProductKey.get(wanted.productKey);
            inserts.add(wanted.item);
        }
        insert inserts;
    }

    private static String lineKey(ShopifyOrder.LineItem line) {
        return String.valueOf(line.id);
    }

    private static String lineKey(ShopifyOrder.ShippingLine shipping) {
        return SHIPPING_LINE_PREFIX + shipping.id;
    }

    private static Map<String, OrderItem> storedItemsByLineKey(
        List<ShopifyOrder> orders,
        Map<String, Order> storedByShopifyId
    ) {
        Set<Id> orderIds = new Set<Id>();
        for (ShopifyOrder order : orders) {
            Order stored = storedByShopifyId.get(order.shopifyId());
            if (stored != null) {
                orderIds.add(stored.Id);
            }
        }
        Map<String, OrderItem> itemsByLineKey = new Map<String, OrderItem>();
        if (orderIds.isEmpty()) {
            return itemsByLineKey;
        }
        for (OrderItem item : [
            SELECT Id, Shopify_Line_Item_Id__c, Quantity, UnitPrice
            FROM OrderItem
            WHERE OrderId IN :orderIds AND Shopify_Line_Item_Id__c != NULL
        ]) {
            itemsByLineKey.put(item.Shopify_Line_Item_Id__c, item);
        }
        return itemsByLineKey;
    }

    private Map<String, Id> upsertProducts() {
        Map<String, Product2> productsByKey = new Map<String, Product2>();
        Map<String, Decimal> listPricesByKey = new Map<String, Decimal>();
        for (WantedItem wanted : newItems) {
            productsByKey.put(wanted.productKey, wanted.product());
            listPricesByKey.put(wanted.productKey, wanted.listPrice());
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
        if (!newEntries.isEmpty()) {
            insert newEntries;
        }
        for (PricebookEntry entry : newEntries) {
            entryIdsByKey.put(keysByProductId.get(entry.Product2Id), entry.Id);
        }
        return entryIdsByKey;
    }

    private static Product2 syntheticProduct(String key, String name) {
        return new Product2(Name = name, ProductCode = key, Shopify_Variant_Id__c = key, IsActive = true);
    }

    // What one order's OrderItems need to match its Shopify lines
    private class Changes {
        public final List<WantedItem> added = new List<WantedItem>();
        public final List<OrderItem> changed = new List<OrderItem>();
        public final List<OrderItem> removed = new List<OrderItem>();

        public Changes(ShopifyOrder order, Map<String, OrderItem> storedItems) {
            for (ShopifyOrder.LineItem line : order.line_items) {
                compare(
                    line.currentQuantity() > 0 ? new WantedItem(order, line) : null,
                    storedItems.get(lineKey(line))
                );
            }
            for (ShopifyOrder.ShippingLine shipping : order.shipping_lines) {
                compare(
                    shipping.isRemoved() ? null : new WantedItem(order, shipping),
                    storedItems.get(lineKey(shipping))
                );
            }
        }

        public Boolean isEmpty() {
            return added.isEmpty() && changed.isEmpty() && removed.isEmpty();
        }

        // wanted is null for a line Shopify removed
        private void compare(WantedItem wanted, OrderItem stored) {
            if (stored == null) {
                if (wanted != null) {
                    added.add(wanted);
                }
            } else if (wanted == null) {
                removed.add(stored);
            } else if (wanted.item.Quantity != stored.Quantity || wanted.item.UnitPrice != stored.UnitPrice) {
                changed.add(
                    new OrderItem(Id = stored.Id, Quantity = wanted.item.Quantity, UnitPrice = wanted.item.UnitPrice)
                );
            }
        }
    }

    // The OrderItem a current Shopify line calls for; OrderId and PricebookEntryId are set by apply()
    private class WantedItem {
        public final String shopifyOrderId;
        public final ShopifyOrder.LineItem line;
        public final String productKey;
        public final OrderItem item;

        public WantedItem(ShopifyOrder order, ShopifyOrder.LineItem line) {
            this.shopifyOrderId = order.shopifyId();
            this.line = line;
            // Custom line items and deleted products have no variant
            this.productKey = line.variant_id == null ? CUSTOM_ITEM_PRODUCT_KEY : String.valueOf(line.variant_id);
            this.item = new OrderItem(
                Shopify_Line_Item_Id__c = lineKey(line),
                Variant_Title__c = line.variant_title,
                Quantity = line.currentQuantity(),
                UnitPrice = ShopifyOrder.toAmount(line.price)
            );
        }

        public WantedItem(ShopifyOrder order, ShopifyOrder.ShippingLine shipping) {
            this.shopifyOrderId = order.shopifyId();
            this.line = null;
            this.productKey = SHIPPING_PRODUCT_KEY;
            this.item = new OrderItem(
                Shopify_Line_Item_Id__c = lineKey(shipping),
                Description = 'Shipping: ' + shipping.title,
                Quantity = 1,
                UnitPrice = ShopifyOrder.toAmount(shipping.price)
            );
        }

        public Product2 product() {
            if (line == null) {
                return syntheticProduct(SHIPPING_PRODUCT_KEY, 'Shipping');
            }
            if (productKey == CUSTOM_ITEM_PRODUCT_KEY) {
                return syntheticProduct(CUSTOM_ITEM_PRODUCT_KEY, 'Shopify Custom Item');
            }
            return new Product2(
                Name = line.name.left(Product2.Name.getDescribe().getLength()),
                ProductCode = line.sku,
                Shopify_Product_Id__c = String.valueOf(line.product_id),
                Shopify_Variant_Id__c = productKey,
                IsActive = true
            );
        }

        // Shipping has no list price; each shipping line carries its own
        public Decimal listPrice() {
            return line == null ? 0 : item.UnitPrice;
        }
    }
}
