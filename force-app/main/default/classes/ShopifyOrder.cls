/**
 * The parts of a Shopify order webhook payload that the integration uses.
 * Property names mirror Shopify's JSON keys; unknown keys are ignored.
 * See https://shopify.dev/docs/api/admin-rest/latest/resources/order
 */
public class ShopifyOrder {
    public Long id;
    public String name;
    public String email;
    public String processed_at;
    public String updated_at;
    public String financial_status;
    public String fulfillment_status;
    public String closed_at;
    public String cancelled_at;
    public String cancel_reason;
    public String total_price;
    public String current_total_price;
    public Customer customer;
    public Address billing_address;
    public Address shipping_address;
    public List<LineItem> line_items;
    public List<ShippingLine> shipping_lines;

    public class Customer {
        public Long id;
        public String email;
        public String first_name;
        public String last_name;
    }

    public class Address {
        public String address1;
        public String address2;
        public String city;
        public String zip;
        public String province_code;
        public String country_code;

        /**
         * address1 and address2 as separate lines, or null when both are blank.
         */
        public String street() {
            List<String> lines = new List<String>();
            for (String line : new List<String>{ address1, address2 }) {
                if (String.isNotBlank(line)) {
                    lines.add(line.trim());
                }
            }
            return lines.isEmpty() ? null : String.join(lines, '\n');
        }
    }

    public class LineItem {
        public Long id;
        public Long product_id;
        public Long variant_id;
        public String name;
        public String variant_title;
        public String sku;
        public Integer quantity;
        public String price;
    }

    public class ShippingLine {
        public Long id;
        public String title;
        public String price;
    }

    public static ShopifyOrder parse(String payload) {
        ShopifyOrder order = (ShopifyOrder) JSON.deserialize(payload, ShopifyOrder.class);
        if (order?.id == null) {
            throw new JSONException('Payload is not a Shopify order: missing id.');
        }
        // JSON.deserialize skips field initializers, so absent arrays would otherwise stay null
        order.line_items = order.line_items ?? new List<LineItem>();
        order.shipping_lines = order.shipping_lines ?? new List<ShippingLine>();
        return order;
    }

    public String shopifyId() {
        return String.valueOf(id);
    }

    /**
     * The email that identifies the customer, lower-cased, or null for orders without one.
     */
    public String customerEmail() {
        String value = String.isNotBlank(email) ? email : customer?.email;
        return String.isBlank(value) ? null : value.trim().toLowerCase();
    }

    public String customerName() {
        String fullName = String.join(new List<String>{ customer?.first_name ?? '', customer?.last_name ?? '' }, ' ')
            .trim();
        return String.isNotBlank(fullName) ? fullName : (customerEmail() ?? 'Shopify Customer ' + shopifyId());
    }

    public String customerLastName() {
        return String.isNotBlank(customer?.last_name) ? customer.last_name : customerName();
    }

    public Datetime updatedAt() {
        return toDatetime(updated_at);
    }

    public Datetime cancelledAt() {
        return toDatetime(cancelled_at);
    }

    /**
     * Whether this version is older than the one Salesforce already holds. Shopify does not
     * guarantee the delivery order of webhooks; a version with the same timestamp is not older.
     */
    public Boolean isOlderThan(Datetime syncedUpdatedAt) {
        Datetime updated = updatedAt();
        return updated != null && syncedUpdatedAt != null && updated < syncedUpdatedAt;
    }

    /**
     * open, closed or cancelled. Shopify closes (archives) an order when it is fulfilled or
     * cancelled, so a cancelled order is also closed.
     */
    public String orderStatus() {
        if (cancelled_at != null) {
            return 'cancelled';
        }
        return closed_at == null ? 'open' : 'closed';
    }

    /**
     * The total after order edits, refunds and cancellations. total_price keeps the checkout amount.
     */
    public Decimal currentTotal() {
        return toAmount(current_total_price ?? total_price);
    }

    // Shopify timestamps carry the shop's UTC offset, e.g. 2026-10-28T12:56:51-04:00
    private static Datetime toDatetime(String value) {
        return value == null ? null : (Datetime) JSON.deserialize('"' + value + '"', Datetime.class);
    }

    // The order date as the shop saw it, independent of the running user's time zone
    public Date processedDate() {
        return Date.valueOf((processed_at ?? updated_at).left(10));
    }

    public static Decimal toAmount(String value) {
        return String.isBlank(value) ? 0 : Decimal.valueOf(value);
    }
}
