/**
 * Processes verified Shopify webhooks published as Shopify_Webhook__e events.
 *
 * The payload is read from the Sync_Log__c the endpoint stored, and the log is
 * updated with the outcome. Orders are upserted in one bulk call; if that fails,
 * each order is retried on its own so one bad payload cannot block the rest.
 *
 * Runs `without sharing` as the platform event subscriber: it must update the
 * Sync_Log__c records created by the Site guest user.
 */
public without sharing class ShopifyWebhookProcessor {
    public static final Set<String> HANDLED_TOPICS = new Set<String>{ 'orders/create', 'orders/updated' };
    @TestVisible
    private static final String OUTDATED_MESSAGE = 'Salesforce already holds a newer version of this order.';
    @TestVisible
    private static final String LINES_OUT_OF_SYNC_MESSAGE = 'Order lines were not updated because the order is activated; the order is marked Lines Out of Sync.';

    public static void process(List<Shopify_Webhook__e> events) {
        Set<Id> logIds = new Set<Id>();
        for (Shopify_Webhook__e event : events) {
            logIds.add(event.Sync_Log_Id__c);
        }
        Map<Id, Sync_Log__c> logs = new Map<Id, Sync_Log__c>(
            [SELECT Id, Payload__c FROM Sync_Log__c WHERE Id IN :logIds AND Status__c = 'Pending']
        );

        Map<Id, ShopifyOrder> ordersByLogId = new Map<Id, ShopifyOrder>();
        for (Sync_Log__c log : logs.values()) {
            try {
                ordersByLogId.put(log.Id, ShopifyOrder.parse(log.Payload__c));
            } catch (Exception e) {
                markError(log, e);
            }
        }

        ShopifyOrderService service = new ShopifyOrderService();
        Savepoint beforeBulk = Database.setSavepoint();
        try {
            markProcessed(logs, ordersByLogId, service.upsertOrders(ordersByLogId.values()));
        } catch (Exception bulkFailure) {
            Database.rollback(beforeBulk);
            // Batch size is capped by ShopifyWebhookEventTriggerConfig, which keeps this loop within limits
            for (Id logId : ordersByLogId.keySet()) {
                Map<Id, ShopifyOrder> single = new Map<Id, ShopifyOrder>{ logId => ordersByLogId.get(logId) };
                Savepoint beforeOrder = Database.setSavepoint();
                try {
                    markProcessed(logs, single, service.upsertOrders(single.values()));
                } catch (Exception e) {
                    Database.rollback(beforeOrder);
                    markError(logs.get(logId), e);
                }
            }
        }
        update logs.values();
    }

    // A version older than the stored order was not applied, whether it lost to the database or to a newer event in the batch
    private static void markProcessed(
        Map<Id, Sync_Log__c> logs,
        Map<Id, ShopifyOrder> ordersByLogId,
        Map<String, Order> storedByShopifyId
    ) {
        for (Id logId : ordersByLogId.keySet()) {
            ShopifyOrder order = ordersByLogId.get(logId);
            Order stored = storedByShopifyId.get(order.shopifyId());
            Boolean outdated = order.isOlderThan(stored.Shopify_Updated_At__c);
            Sync_Log__c log = logs.get(logId);
            log.Status__c = outdated ? 'Skipped' : 'Success';
            log.Order__c = stored.Id;
            log.Error_Message__c = null;
            if (outdated) {
                log.Error_Message__c = OUTDATED_MESSAGE;
            } else if (stored.Lines_Out_Of_Sync__c) {
                log.Error_Message__c = LINES_OUT_OF_SYNC_MESSAGE;
            }
        }
    }

    private static void markError(Sync_Log__c log, Exception e) {
        log.Status__c = 'Error';
        log.Error_Message__c = (e.getTypeName() +
            ': ' +
            e.getMessage() +
            '\n' +
            e.getStackTraceString())
            .left(Sync_Log__c.Error_Message__c.getDescribe().getLength());
    }
}
