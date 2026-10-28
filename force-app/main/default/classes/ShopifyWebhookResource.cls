/**
 * Public endpoint for Shopify webhooks, exposed to Shopify through a Salesforce Site.
 *
 * Runs `without sharing` because the caller is the Site guest user, who has no
 * access to Sync_Log__c records. Every request is authenticated by its HMAC
 * signature before any payload is stored.
 */
@RestResource(urlMapping='/shopify/webhooks')
global without sharing class ShopifyWebhookResource {
    @TestVisible
    private static final String HMAC_HEADER = 'X-Shopify-Hmac-Sha256';
    @TestVisible
    private static final String TOPIC_HEADER = 'X-Shopify-Topic';

    private static final Integer PAYLOAD_MAX_LENGTH = Sync_Log__c.Payload__c.getDescribe().getLength();

    @HttpPost
    global static void receive() {
        RestResponse response = RestContext.response;
        try {
            handle(RestContext.request, response);
        } catch (Exception e) {
            // An unhandled exception would return the Apex error and stack trace to a public caller
            response.statusCode = 500;
            response.responseBody = null;
            logUnexpectedError(e);
        }
    }

    private static void handle(RestRequest request, RestResponse response) {
        String topic = header(request, TOPIC_HEADER);

        ShopifyWebhookVerifier verifier;
        try {
            verifier = new ShopifyWebhookVerifier();
        } catch (ShopifyWebhookVerifier.NotConfiguredException e) {
            // 500 makes Shopify retry, so no events are lost while the secret is being configured
            response.statusCode = 500;
            insertLog(topic, null, 'Error', response.statusCode, null, e.getMessage());
            return;
        }

        if (!verifier.isValid(request.requestBody, header(request, HMAC_HEADER))) {
            // The payload of an unauthenticated request is not stored
            response.statusCode = 401;
            insertLog(topic, null, 'Error', response.statusCode, null, 'Invalid or missing HMAC signature.');
            return;
        }

        String body = request.requestBody.toString();
        response.statusCode = 200;
        insertLog(topic, extractShopifyId(body), 'Success', response.statusCode, body.left(PAYLOAD_MAX_LENGTH), null);
    }

    // Logs only the error: the request data that caused it could make this insert fail as well
    private static void logUnexpectedError(Exception e) {
        try {
            insertLog(null, null, 'Error', 500, null, e.getTypeName() + ': ' + e.getMessage());
        } catch (Exception logFailure) {
            System.debug(LoggingLevel.ERROR, 'Could not log webhook error: ' + logFailure.getMessage());
        }
    }

    // Header names are case-insensitive, and HTTP/2 proxies deliver them in lower case
    private static String header(RestRequest request, String name) {
        for (String key : request.headers.keySet()) {
            if (key.equalsIgnoreCase(name)) {
                return request.headers.get(key);
            }
        }
        return null;
    }

    private static String extractShopifyId(String body) {
        try {
            Object id = ((Map<String, Object>) JSON.deserializeUntyped(body)).get('id');
            return id == null ? null : String.valueOf(id);
        } catch (JSONException e) {
            return null;
        } catch (TypeException e) {
            return null;
        }
    }

    private static void insertLog(
        String topic,
        String shopifyReference,
        String status,
        Integer httpStatusCode,
        String payload,
        String errorMessage
    ) {
        insert new Sync_Log__c(
            Direction__c = 'Inbound',
            Event_Topic__c = topic,
            Shopify_Reference__c = shopifyReference,
            Status__c = status,
            HTTP_Status_Code__c = httpStatusCode,
            Payload__c = payload,
            Error_Message__c = errorMessage
        );
    }
}
