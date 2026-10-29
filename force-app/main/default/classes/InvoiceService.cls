public with sharing class InvoiceService {
    @TestVisible
    private static final String PAID = 'Paid';
    @TestVisible
    private static final String VOIDED = 'Voided';

    /**
     * Creates a Paid invoice for each order that has no open (non-voided) invoice yet.
     * The amount is Shopify's order total, which is known before the order lines
     * are inserted; orders created in Salesforce fall back to TotalAmount.
     */
    public static List<Invoice__c> createForPaidOrders(List<Order> orders) {
        List<Invoice__c> invoices = new List<Invoice__c>();
        if (orders.isEmpty()) {
            return invoices;
        }

        Set<Id> invoicedOrderIds = new Set<Id>();
        for (Invoice__c existing : [SELECT Order__c FROM Invoice__c WHERE Order__c IN :orders AND Status__c != :VOIDED]) {
            invoicedOrderIds.add(existing.Order__c);
        }

        for (Order order : orders) {
            if (!invoicedOrderIds.contains(order.Id)) {
                invoices.add(
                    new Invoice__c(
                        Order__c = order.Id,
                        Status__c = PAID,
                        Invoice_Date__c = Date.today(),
                        Due_Date__c = Date.today(),
                        Total_Amount__c = order.Shopify_Total_Price__c ?? order.TotalAmount
                    )
                );
            }
        }
        insert invoices;
        return invoices;
    }
}
