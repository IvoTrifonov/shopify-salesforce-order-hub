trigger OrderTrigger on Order(
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new OrderTriggerHandler().run();
}
