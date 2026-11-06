/**
 * Creates or updates Salesforce records from Shopify orders: the customer's
 * Account and Contact, the Order, and through ShopifyOrderLineSync its lines
 * with their products.
 *
 * Every step is idempotent (keyed by Shopify IDs) and bulkified: the DML and
 * SOQL count does not grow with the number of orders. A version older than the
 * stored one is ignored.
 *
 * Runs `without sharing`: customers must be matched against all Contacts, not
 * just those the running integration user can see, or duplicates are created.
 */
public without sharing class ShopifyOrderService {
    private static final String UNFULFILLED = 'unfulfilled';
    private static final String NEW_ORDER_STATUS = 'Draft';

    private final Id pricebookId = standardPricebookId();

    /**
     * Upserts the given orders and returns, by Shopify order ID, the Order as Salesforce now
     * holds it (Id, Shopify_Updated_At__c, Lines_Out_Of_Sync__c), including orders whose given
     * version was too old.
     */
    public Map<String, Order> upsertOrders(List<ShopifyOrder> shopifyOrders) {
        List<ShopifyOrder> latest = latestVersions(shopifyOrders);
        Map<String, Order> storedByShopifyId = storedOrders(latest);

        List<ShopifyOrder> orders = new List<ShopifyOrder>();
        for (ShopifyOrder order : latest) {
            Order stored = storedByShopifyId.get(order.shopifyId());
            if (stored == null || !order.isOlderThan(stored.Shopify_Updated_At__c)) {
                orders.add(order);
            }
        }

        ShopifyOrderLineSync lines = new ShopifyOrderLineSync(orders, storedByShopifyId, pricebookId);
        Map<String, Contact> contactsByCustomerKey = upsertCustomers(orders, storedByShopifyId);
        Map<String, Order> ordersByShopifyId = orderHeaders(orders, storedByShopifyId, contactsByCustomerKey);
        lines.markOutOfSync(ordersByShopifyId.values());
        upsert ordersByShopifyId.values() Order.Shopify_Order_Id__c;
        lines.apply(ordersByShopifyId);

        storedByShopifyId.putAll(ordersByShopifyId);
        return storedByShopifyId;
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

    private static Map<String, Order> storedOrders(List<ShopifyOrder> orders) {
        Set<String> shopifyIds = new Set<String>();
        for (ShopifyOrder order : orders) {
            shopifyIds.add(order.shopifyId());
        }
        Map<String, Order> storedByShopifyId = new Map<String, Order>();
        for (Order stored : [
            SELECT
                Id,
                StatusCode,
                AccountId,
                BillToContactId,
                Shopify_Order_Id__c,
                Shopify_Updated_At__c,
                Lines_Out_Of_Sync__c
            FROM Order
            WHERE Shopify_Order_Id__c IN :shopifyIds
        ]) {
            storedByShopifyId.put(stored.Shopify_Order_Id__c, stored);
        }
        return storedByShopifyId;
    }

    // Customers are matched by email; an order without one gets its own Account and Contact when it is created
    private static String customerKey(ShopifyOrder order) {
        return order.customerEmail() ?? 'order:' + order.shopifyId();
    }

    private Map<String, Contact> upsertCustomers(List<ShopifyOrder> orders, Map<String, Order> storedByShopifyId) {
        Map<String, ShopifyOrder> ordersByCustomerKey = new Map<String, ShopifyOrder>();
        Map<String, Contact> contactsByCustomerKey = new Map<String, Contact>();
        for (ShopifyOrder order : orders) {
            if (!ordersByCustomerKey.containsKey(customerKey(order))) {
                ordersByCustomerKey.put(customerKey(order), order);
            }
            // Without an email there is nothing to match by, so a stored order keeps the customer it has
            Order stored = storedByShopifyId.get(order.shopifyId());
            if (order.customerEmail() == null && stored?.BillToContactId != null) {
                contactsByCustomerKey.put(
                    customerKey(order),
                    new Contact(Id = stored.BillToContactId, AccountId = stored.AccountId)
                );
            }
        }

        // Oldest Contact wins when an email already has duplicates
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

    // The Order records to upsert; lines are written separately by ShopifyOrderLineSync
    private Map<String, Order> orderHeaders(
        List<ShopifyOrder> orders,
        Map<String, Order> storedByShopifyId,
        Map<String, Contact> contactsByCustomerKey
    ) {
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
                Shopify_Order_Status__c = order.orderStatus(),
                Cancelled_At__c = order.cancelledAt(),
                Cancel_Reason__c = order.cancel_reason,
                Shopify_Total_Price__c = order.currentTotal(),
                Shopify_Updated_At__c = order.updatedAt()
            );
            setAddress(record, 'Billing', order.billing_address);
            setAddress(record, 'Shipping', order.shipping_address);
            // Status and price book are set on creation only; they are managed in Salesforce afterwards
            if (!storedByShopifyId.containsKey(order.shopifyId())) {
                record.Status = NEW_ORDER_STATUS;
                record.Pricebook2Id = pricebookId;
            }
            ordersByShopifyId.put(order.shopifyId(), record);
        }
        return ordersByShopifyId;
    }

    /**
     * Sets the Billing or Shipping address fields. Shopify is the system of record, so a missing
     * address clears them. A country or state code the org's picklists do not know is left out
     * rather than failing the order.
     */
    private static void setAddress(Order record, String prefix, ShopifyOrder.Address address) {
        String countryCode = CountryStateCodes.isValidCountry(address?.country_code) ? address.country_code : null;
        String stateCode = CountryStateCodes.isValidState(countryCode, address?.province_code)
            ? address.province_code
            : null;
        record.put(prefix + 'Street', address?.street());
        record.put(prefix + 'City', address?.city);
        record.put(prefix + 'PostalCode', address?.zip);
        record.put(prefix + 'CountryCode', countryCode);
        record.put(prefix + 'StateCode', stateCode);
    }

    private static Id standardPricebookId() {
        // The standard price book is not visible to tests without SeeAllData
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1].Id;
    }
}
