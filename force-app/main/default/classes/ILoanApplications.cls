public interface ILoanApplications extends fflib_ISObjectDomain {
    List<Loan_Application__c> getLoanApplications();

    /** Moves Draft applications to Submitted and registers their document checklist and verification checks. */
    void submit(fflib_ISObjectUnitOfWork uow);

    /** Moves Submitted applications to In Review. */
    void startReview(fflib_ISObjectUnitOfWork uow);

    /** Approves or declines In Review applications. Approval is blocked while getApprovalBlockers() is non-empty. */
    void recordDecision(Boolean approve, String notes, fflib_ISObjectUnitOfWork uow);

    /** Human-readable reasons an application cannot be approved yet, keyed by application Id. */
    Map<Id, List<String>> getApprovalBlockers();
}
