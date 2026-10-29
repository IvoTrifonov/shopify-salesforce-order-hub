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
    public String total_price;
    public Customer customer;
    public List<LineItem> line_items = new List<LineItem>();
    public List<ShippingLine> shipping_lines = new List<ShippingLine>();

    public class Customer {
        public Long id;
        public String email;
        public String first_name;
        public String last_name;
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
        String fullName = String.join(new List<String>{ customer?.first_name ?? '', customer?.last_name ?? '' }, ' ').trim();
        return String.isNotBlank(fullName) ? fullName : (customerEmail() ?? 'Shopify Customer ' + shopifyId());
    }

    public String customerLastName() {
        return String.isNotBlank(customer?.last_name) ? customer.last_name : customerName();
    }

    // Shopify timestamps carry the shop's UTC offset, e.g. 2026-10-28T12:56:51-04:00
    public Datetime updatedAt() {
        return updated_at == null ? null : (Datetime) JSON.deserialize('"' + updated_at + '"', Datetime.class);
    }

    // The order date as the shop saw it, independent of the running user's time zone
    public Date processedDate() {
        return Date.valueOf((processed_at ?? updated_at).left(10));
    }

    public static Decimal toAmount(String value) {
        return String.isBlank(value) ? 0 : Decimal.valueOf(value);
    }
}
