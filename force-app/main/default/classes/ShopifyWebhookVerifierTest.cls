@IsTest
private class ShopifyWebhookVerifierTest {
    private static final String SECRET = 'test-secret';
    private static final Blob BODY = Blob.valueOf('{"id":820982911946154508}');

    @IsTest
    static void acceptsMatchingSignature() {
        ShopifyWebhookVerifier verifier = new ShopifyWebhookVerifier(SECRET);
        String signature = EncodingUtil.base64Encode(Crypto.generateMac('hmacSHA256', BODY, Blob.valueOf(SECRET)));

        Assert.isTrue(verifier.isValid(BODY, signature));
    }

    @IsTest
    static void rejectsSignatureFromDifferentSecret() {
        String forged = new ShopifyWebhookVerifier('other-secret').sign(BODY);

        Assert.isFalse(new ShopifyWebhookVerifier(SECRET).isValid(BODY, forged));
    }

    @IsTest
    static void rejectsTamperedBody() {
        ShopifyWebhookVerifier verifier = new ShopifyWebhookVerifier(SECRET);
        String signature = verifier.sign(BODY);

        Assert.isFalse(verifier.isValid(Blob.valueOf('{"id":1}'), signature));
    }

    @IsTest
    static void rejectsMissingSignatureOrBody() {
        ShopifyWebhookVerifier verifier = new ShopifyWebhookVerifier(SECRET);

        Assert.isFalse(verifier.isValid(BODY, null));
        Assert.isFalse(verifier.isValid(BODY, ''));
        Assert.isFalse(verifier.isValid(null, verifier.sign(BODY)));
    }

    @IsTest
    static void rejectsSignatureOfDifferentLength() {
        Assert.isFalse(new ShopifyWebhookVerifier(SECRET).isValid(BODY, 'short'));
    }

    @IsTest
    static void readsSecretFromShopifySettings() {
        insert new Shopify_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Webhook_Secret__c = SECRET);

        String signature = new ShopifyWebhookVerifier(SECRET).sign(BODY);

        Assert.isTrue(new ShopifyWebhookVerifier().isValid(BODY, signature));
    }

    @IsTest
    static void throwsWhenSecretIsNotConfigured() {
        try {
            new ShopifyWebhookVerifier();
            Assert.fail('Expected NotConfiguredException');
        } catch (ShopifyWebhookVerifier.NotConfiguredException e) {
            Assert.isTrue(e.getMessage().contains('not configured'));
        }
    }
}
