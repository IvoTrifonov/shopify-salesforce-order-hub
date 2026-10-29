public with sharing class OrderTriggerHandler extends TriggerHandler {
    private static final String PAID = 'paid';

    public OrderTriggerHandler() {
        super(OrderTriggerHandler.class);
    }

    protected override void afterInsert() {
        InvoiceService.createForPaidOrders(newlyPaidOrders());
    }

    protected override void afterUpdate() {
        InvoiceService.createForPaidOrders(newlyPaidOrders());
    }

    // Orders that are paid now and were not before this DML
    private List<Order> newlyPaidOrders() {
        List<Order> paidOrders = new List<Order>();
        for (Order order : (List<Order>) newRecords) {
            Order previous = (Order) oldMap?.get(order.Id);
            if (order.Financial_Status__c == PAID && previous?.Financial_Status__c != PAID) {
                paidOrders.add(order);
            }
        }
        return paidOrders;
    }
}
