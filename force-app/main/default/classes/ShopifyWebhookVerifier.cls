/**
 * Verifies the X-Shopify-Hmac-Sha256 signature of an incoming Shopify webhook.
 * See https://shopify.dev/docs/apps/build/webhooks/subscribe/https#step-5-verify-the-webhook
 */
public with sharing class ShopifyWebhookVerifier {
    @TestVisible
    private static final String ALGORITHM = 'hmacSHA256';

    public class NotConfiguredException extends Exception {
    }

    private final String secret;

    public ShopifyWebhookVerifier() {
        this(Shopify_Settings__c.getOrgDefaults().Webhook_Secret__c);
    }

    @TestVisible
    private ShopifyWebhookVerifier(String secret) {
        if (String.isBlank(secret)) {
            throw new NotConfiguredException('Shopify webhook secret is not configured in Shopify Settings.');
        }
        this.secret = secret;
    }

    /**
     * Returns true when the signature matches the HMAC-SHA256 of the raw body.
     */
    public Boolean isValid(Blob body, String signature) {
        if (body == null || String.isBlank(signature)) {
            return false;
        }
        return constantTimeEquals(sign(body), signature);
    }

    @TestVisible
    private String sign(Blob body) {
        return EncodingUtil.base64Encode(Crypto.generateMac(ALGORITHM, body, Blob.valueOf(secret)));
    }

    // Compares every character so response time does not reveal how much of a forged signature matched
    private static Boolean constantTimeEquals(String expected, String actual) {
        if (expected.length() != actual.length()) {
            return false;
        }
        Integer diff = 0;
        for (Integer i = 0; i < expected.length(); i++) {
            diff |= expected.charAt(i) ^ actual.charAt(i);
        }
        return diff == 0;
    }
}
