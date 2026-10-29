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
    public static final Set<String> HANDLED_TOPICS = new Set<String>{ 'orders/create' };

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
            markSuccess(logs, ordersByLogId, service.upsertOrders(ordersByLogId.values()));
        } catch (Exception bulkFailure) {
            Database.rollback(beforeBulk);
            // Batch size is capped by ShopifyWebhookEventTriggerConfig, which keeps this loop within limits
            for (Id logId : ordersByLogId.keySet()) {
                Map<Id, ShopifyOrder> single = new Map<Id, ShopifyOrder>{ logId => ordersByLogId.get(logId) };
                Savepoint beforeOrder = Database.setSavepoint();
                try {
                    markSuccess(logs, single, service.upsertOrders(single.values()));
                } catch (Exception e) {
                    Database.rollback(beforeOrder);
                    markError(logs.get(logId), e);
                }
            }
        }
        update logs.values();
    }

    private static void markSuccess(
        Map<Id, Sync_Log__c> logs,
        Map<Id, ShopifyOrder> ordersByLogId,
        Map<String, Id> orderIdsByShopifyId
    ) {
        for (Id logId : ordersByLogId.keySet()) {
            Sync_Log__c log = logs.get(logId);
            log.Status__c = 'Success';
            log.Order__c = orderIdsByShopifyId.get(ordersByLogId.get(logId).shopifyId());
            log.Error_Message__c = null;
        }
    }

    private static void markError(Sync_Log__c log, Exception e) {
        log.Status__c = 'Error';
        log.Error_Message__c = (e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString())
            .left(Sync_Log__c.Error_Message__c.getDescribe().getLength());
    }
}
