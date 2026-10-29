trigger ShopifyWebhookEventTrigger on Shopify_Webhook__e(after insert) {
    ShopifyWebhookProcessor.process(Trigger.new);
}
