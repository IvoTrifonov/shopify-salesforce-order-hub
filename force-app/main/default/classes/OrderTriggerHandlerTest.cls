@IsTest
private class OrderTriggerHandlerTest {
    @TestSetup
    static void setup() {
        insert new Account(Name = 'Customer');
    }

    @IsTest
    static void invoicesOrderCreatedAsPaid() {
        Order order = newOrder('paid', 27.99);

        insert order;

        Invoice__c invoice = [SELECT Order__c, Status__c, Invoice_Date__c, Due_Date__c, Total_Amount__c FROM Invoice__c];
        Assert.areEqual(order.Id, invoice.Order__c);
        Assert.areEqual(InvoiceService.PAID, invoice.Status__c);
        Assert.areEqual(Date.today(), invoice.Invoice_Date__c);
        Assert.areEqual(Date.today(), invoice.Due_Date__c);
        Assert.areEqual(27.99, invoice.Total_Amount__c);
    }

    @IsTest
    static void doesNotInvoiceUnpaidOrder() {
        insert newOrder('pending', 10);

        Assert.areEqual(0, [SELECT COUNT() FROM Invoice__c]);
    }

    @IsTest
    static void invoicesOrderWhenItBecomesPaid() {
        Order order = newOrder('pending', 10);
        insert order;

        order.Financial_Status__c = 'paid';
        update order;

        Assert.areEqual(1, [SELECT COUNT() FROM Invoice__c WHERE Order__c = :order.Id]);
    }

    @IsTest
    static void doesNotInvoicePaidOrderAgainOnUpdate() {
        Order order = newOrder('paid', 10);
        insert order;

        order.Description = 'Changed';
        update order;

        Assert.areEqual(1, [SELECT COUNT() FROM Invoice__c]);
    }

    @IsTest
    static void doesNotDuplicateOpenInvoiceWhenOrderIsPaidAgain() {
        Order order = newOrder('paid', 10);
        insert order;

        order.Financial_Status__c = 'pending';
        update order;
        order.Financial_Status__c = 'paid';
        update order;

        Assert.areEqual(1, [SELECT COUNT() FROM Invoice__c]);
    }

    @IsTest
    static void invoicesAgainAfterPreviousInvoiceWasVoided() {
        Order order = newOrder('paid', 10);
        insert order;
        update new Invoice__c(Id = [SELECT Id FROM Invoice__c].Id, Status__c = InvoiceService.VOIDED);

        order.Financial_Status__c = 'pending';
        update order;
        order.Financial_Status__c = 'paid';
        update order;

        Assert.areEqual(1, [SELECT COUNT() FROM Invoice__c WHERE Status__c = :InvoiceService.PAID]);
        Assert.areEqual(1, [SELECT COUNT() FROM Invoice__c WHERE Status__c = :InvoiceService.VOIDED]);
    }

    @IsTest
    static void doesNotInvoiceWhenHandlerIsBypassed() {
        TriggerHandler.bypass(OrderTriggerHandler.class);

        insert newOrder('paid', 10);

        Assert.areEqual(0, [SELECT COUNT() FROM Invoice__c]);
    }

    @IsTest
    static void invoices200PaidOrdersInOneDml() {
        List<Order> orders = new List<Order>();
        for (Integer i = 0; i < 200; i++) {
            orders.add(newOrder(Math.mod(i, 2) == 0 ? 'paid' : 'pending', i));
        }

        Test.startTest();
        insert orders;
        Test.stopTest();

        Assert.areEqual(100, [SELECT COUNT() FROM Invoice__c]);
    }

    private static Id accountId;

    private static Order newOrder(String financialStatus, Decimal shopifyTotal) {
        accountId = accountId ?? [SELECT Id FROM Account LIMIT 1].Id;
        return new Order(
            AccountId = accountId,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Financial_Status__c = financialStatus,
            Shopify_Total_Price__c = shopifyTotal
        );
    }
}
