/**
 * One trigger per object, no logic: everything is delegated to the LoanApplications domain class.
 */
trigger LoanApplications on Loan_Application__c(
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    fflib_SObjectDomain.triggerHandler(LoanApplications.class);
}
