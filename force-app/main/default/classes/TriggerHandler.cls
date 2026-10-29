/**
 * Base class for trigger handlers. Each object has one logic-free trigger that
 * delegates to a handler, which overrides only the events it needs:
 *
 *     trigger OrderTrigger on Order (before insert, before update, ...) {
 *         new OrderTriggerHandler().run();
 *     }
 *
 * Handlers can be switched off for the rest of the transaction with
 * TriggerHandler.bypass(OrderTriggerHandler.class), e.g. during data loads.
 */
public abstract inherited sharing class TriggerHandler {
    private static final Set<String> BYPASSED_HANDLERS = new Set<String>();

    public class TriggerHandlerException extends Exception {
    }

    private final String handlerName;

    @TestVisible
    protected TriggerOperation operation = Trigger.operationType;
    protected List<SObject> newRecords = Trigger.new;
    protected List<SObject> oldRecords = Trigger.old;
    protected Map<Id, SObject> newMap = Trigger.newMap;
    protected Map<Id, SObject> oldMap = Trigger.oldMap;

    // Apex has no getClass(), so each handler passes its own type for bypassing
    protected TriggerHandler(Type handlerType) {
        this.handlerName = handlerType.getName();
    }

    public void run() {
        if (operation == null) {
            throw new TriggerHandlerException('TriggerHandler.run() must be called from a trigger.');
        }
        if (BYPASSED_HANDLERS.contains(handlerName)) {
            return;
        }
        switch on operation {
            when BEFORE_INSERT {
                beforeInsert();
            }
            when BEFORE_UPDATE {
                beforeUpdate();
            }
            when BEFORE_DELETE {
                beforeDelete();
            }
            when AFTER_INSERT {
                afterInsert();
            }
            when AFTER_UPDATE {
                afterUpdate();
            }
            when AFTER_DELETE {
                afterDelete();
            }
            when AFTER_UNDELETE {
                afterUndelete();
            }
        }
    }

    protected virtual void beforeInsert() {
    }

    protected virtual void beforeUpdate() {
    }

    protected virtual void beforeDelete() {
    }

    protected virtual void afterInsert() {
    }

    protected virtual void afterUpdate() {
    }

    protected virtual void afterDelete() {
    }

    protected virtual void afterUndelete() {
    }

    public static void bypass(Type handlerType) {
        BYPASSED_HANDLERS.add(handlerType.getName());
    }

    public static void clearBypass(Type handlerType) {
        BYPASSED_HANDLERS.remove(handlerType.getName());
    }

    public static Boolean isBypassed(Type handlerType) {
        return BYPASSED_HANDLERS.contains(handlerType.getName());
    }
}
