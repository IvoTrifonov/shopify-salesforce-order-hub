@IsTest
private class TriggerHandlerTest {
    private class RecordingHandler extends TriggerHandler {
        private final List<String> calls = new List<String>();

        RecordingHandler(TriggerOperation operation) {
            super(RecordingHandler.class);
            this.operation = operation;
        }

        protected override void beforeInsert() {
            calls.add('beforeInsert');
        }
        protected override void beforeUpdate() {
            calls.add('beforeUpdate');
        }
        protected override void beforeDelete() {
            calls.add('beforeDelete');
        }
        protected override void afterInsert() {
            calls.add('afterInsert');
        }
        protected override void afterUpdate() {
            calls.add('afterUpdate');
        }
        protected override void afterDelete() {
            calls.add('afterDelete');
        }
        protected override void afterUndelete() {
            calls.add('afterUndelete');
        }
    }

    @IsTest
    static void dispatchesEachOperationToItsMethodOnly() {
        Map<TriggerOperation, String> expected = new Map<TriggerOperation, String>{
            TriggerOperation.BEFORE_INSERT => 'beforeInsert',
            TriggerOperation.BEFORE_UPDATE => 'beforeUpdate',
            TriggerOperation.BEFORE_DELETE => 'beforeDelete',
            TriggerOperation.AFTER_INSERT => 'afterInsert',
            TriggerOperation.AFTER_UPDATE => 'afterUpdate',
            TriggerOperation.AFTER_DELETE => 'afterDelete',
            TriggerOperation.AFTER_UNDELETE => 'afterUndelete'
        };
        for (TriggerOperation operation : TriggerOperation.values()) {
            RecordingHandler handler = new RecordingHandler(operation);

            handler.run();

            Assert.areEqual(new List<String>{ expected.get(operation) }, handler.calls, String.valueOf(operation));
        }
    }

    private class EmptyHandler extends TriggerHandler {
        EmptyHandler(TriggerOperation operation) {
            super(EmptyHandler.class);
            this.operation = operation;
        }
    }

    @IsTest
    static void allowsHandlersToOverrideOnlySomeEvents() {
        for (TriggerOperation operation : TriggerOperation.values()) {
            new EmptyHandler(operation).run();
        }
        Assert.isFalse(TriggerHandler.isBypassed(EmptyHandler.class), 'Events without an override are no-ops');
    }

    @IsTest
    static void skipsBypassedHandlerUntilBypassIsCleared() {
        RecordingHandler handler = new RecordingHandler(TriggerOperation.AFTER_INSERT);

        TriggerHandler.bypass(RecordingHandler.class);
        handler.run();
        Assert.isTrue(TriggerHandler.isBypassed(RecordingHandler.class));
        Assert.isTrue(handler.calls.isEmpty());

        TriggerHandler.clearBypass(RecordingHandler.class);
        handler.run();
        Assert.isFalse(TriggerHandler.isBypassed(RecordingHandler.class));
        Assert.areEqual(new List<String>{ 'afterInsert' }, handler.calls);
    }

    @IsTest
    static void bypassesOnlyTheGivenHandler() {
        TriggerHandler.bypass(OrderTriggerHandler.class);
        RecordingHandler handler = new RecordingHandler(TriggerOperation.AFTER_INSERT);

        handler.run();

        Assert.areEqual(new List<String>{ 'afterInsert' }, handler.calls);
    }

    @IsTest
    static void failsOutsideTriggerContext() {
        try {
            new RecordingHandler(null).run();
            Assert.fail('Expected TriggerHandlerException');
        } catch (TriggerHandler.TriggerHandlerException e) {
            Assert.isTrue(e.getMessage().contains('trigger'));
        }
    }
}
