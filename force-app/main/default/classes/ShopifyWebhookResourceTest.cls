@IsTest
private class ShopifyWebhookResourceTest {
    private static final String SECRET = 'test-secret';
    private static final String ORDER_PAYLOAD = '{"id":820982911946154508,"name":"#1001","email":"jane@example.com"}';

    @TestSetup
    static void setup() {
        insert new Shopify_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Webhook_Secret__c = SECRET);
    }

    @IsTest
    static void logsPayloadOfValidWebhook() {
        RestResponse response = post(ORDER_PAYLOAD, sign(ORDER_PAYLOAD));

        Assert.areEqual(200, response.statusCode);
        Sync_Log__c log = getOnlyLog();
        Assert.areEqual('Inbound', log.Direction__c);
        Assert.areEqual('Success', log.Status__c);
        Assert.areEqual('orders/create', log.Event_Topic__c);
        Assert.areEqual('820982911946154508', log.Shopify_Reference__c);
        Assert.areEqual(200, log.HTTP_Status_Code__c);
        Assert.areEqual(ORDER_PAYLOAD, log.Payload__c);
        Assert.isNull(log.Error_Message__c);
    }

    @IsTest
    static void rejectsInvalidSignatureWithoutStoringPayload() {
        RestResponse response = post(ORDER_PAYLOAD, sign('{"id":1}'));

        Assert.areEqual(401, response.statusCode);
        Sync_Log__c log = getOnlyLog();
        Assert.areEqual('Error', log.Status__c);
        Assert.areEqual(401, log.HTTP_Status_Code__c);
        Assert.isNull(log.Payload__c);
        Assert.isNull(log.Shopify_Reference__c);
        Assert.isNotNull(log.Error_Message__c);
    }

    @IsTest
    static void rejectsMissingSignature() {
        RestResponse response = post(ORDER_PAYLOAD, null);

        Assert.areEqual(401, response.statusCode);
        Assert.areEqual('Error', getOnlyLog().Status__c);
    }

    @IsTest
    static void readsHeadersCaseInsensitively() {
        RestContext.request = newRequest(ORDER_PAYLOAD);
        RestContext.request.headers.put(ShopifyWebhookResource.HMAC_HEADER.toLowerCase(), sign(ORDER_PAYLOAD));
        RestContext.request.headers.put(ShopifyWebhookResource.TOPIC_HEADER.toLowerCase(), 'orders/create');
        RestContext.response = new RestResponse();

        ShopifyWebhookResource.receive();

        Assert.areEqual(200, RestContext.response.statusCode);
        Assert.areEqual('orders/create', getOnlyLog().Event_Topic__c);
    }

    @IsTest
    static void acceptsValidWebhookWithUnparseableBody() {
        String body = '[1, 2, 3]';

        RestResponse response = post(body, sign(body));

        Assert.areEqual(200, response.statusCode);
        Sync_Log__c log = getOnlyLog();
        Assert.areEqual('Success', log.Status__c);
        Assert.isNull(log.Shopify_Reference__c);
        Assert.areEqual(body, log.Payload__c);
    }

    @IsTest
    static void acceptsValidWebhookWithMalformedJson() {
        String body = 'not json';

        RestResponse response = post(body, sign(body));

        Assert.areEqual(200, response.statusCode);
        Assert.isNull(getOnlyLog().Shopify_Reference__c);
    }

    @IsTest
    static void returnsServerErrorWhenSecretIsNotConfigured() {
        delete [SELECT Id FROM Shopify_Settings__c];

        RestResponse response = post(ORDER_PAYLOAD, sign(ORDER_PAYLOAD));

        Assert.areEqual(500, response.statusCode);
        Sync_Log__c log = getOnlyLog();
        Assert.areEqual('Error', log.Status__c);
        Assert.isNull(log.Payload__c);
    }

    @IsTest
    static void hidesUnexpectedErrorDetailsFromCaller() {
        // A topic longer than Event_Topic__c makes the log insert fail
        String topic = 'x'.repeat(Sync_Log__c.Event_Topic__c.getDescribe().getLength() + 1);

        RestResponse response = post(ORDER_PAYLOAD, sign(ORDER_PAYLOAD), topic);

        Assert.areEqual(500, response.statusCode);
        Assert.isNull(response.responseBody);
        Sync_Log__c log = getOnlyLog();
        Assert.areEqual('Error', log.Status__c);
        Assert.isNull(log.Event_Topic__c);
        Assert.isNull(log.Payload__c);
        Assert.isTrue(log.Error_Message__c.contains('DmlException'), log.Error_Message__c);
    }

    private static RestResponse post(String body, String signature) {
        return post(body, signature, 'orders/create');
    }

    private static RestResponse post(String body, String signature, String topic) {
        RestContext.request = newRequest(body);
        RestContext.request.headers.put(ShopifyWebhookResource.TOPIC_HEADER, topic);
        if (signature != null) {
            RestContext.request.headers.put(ShopifyWebhookResource.HMAC_HEADER, signature);
        }
        RestContext.response = new RestResponse();

        Test.startTest();
        ShopifyWebhookResource.receive();
        Test.stopTest();

        return RestContext.response;
    }

    private static RestRequest newRequest(String body) {
        RestRequest request = new RestRequest();
        request.httpMethod = 'POST';
        request.requestURI = '/services/apexrest/shopify/webhooks';
        request.requestBody = Blob.valueOf(body);
        return request;
    }

    private static String sign(String body) {
        return EncodingUtil.base64Encode(
            Crypto.generateMac(ShopifyWebhookVerifier.ALGORITHM, Blob.valueOf(body), Blob.valueOf(SECRET))
        );
    }

    private static Sync_Log__c getOnlyLog() {
        List<Sync_Log__c> logs = [
            SELECT
                Direction__c,
                Status__c,
                Event_Topic__c,
                Shopify_Reference__c,
                HTTP_Status_Code__c,
                Payload__c,
                Error_Message__c
            FROM Sync_Log__c
        ];
        Assert.areEqual(1, logs.size(), 'Expected exactly one sync log');
        return logs[0];
    }
}
