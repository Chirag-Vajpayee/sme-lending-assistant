public interface ILoanApplicationsSelector extends fflib_ISObjectSelector {
    List<Loan_Application__c> selectById(Set<Id> applicationIds);

    /** Applications with their Required Documents and Verification Checks as child lists. */
    List<Loan_Application__c> selectByIdWithChildren(Set<Id> applicationIds);
}
