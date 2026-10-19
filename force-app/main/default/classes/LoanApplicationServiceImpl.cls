/**
 * Orchestrates each use case: load with the selector, apply rules with the domain,
 * commit once with the Unit of Work. No business rules live here.
 */
public inherited sharing class LoanApplicationServiceImpl implements ILoanApplicationService {
    public void submit(Set<Id> applicationIds) {
        fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
        domainFor(applicationIds).submit(uow);
        uow.commitWork();
    }

    public void startReview(Set<Id> applicationIds) {
        fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
        domainFor(applicationIds).startReview(uow);
        uow.commitWork();
    }

    public void recordDecision(Id applicationId, Boolean approve, String notes) {
        fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
        domainFor(new Set<Id>{ applicationId }).recordDecision(approve, notes, uow);
        uow.commitWork();
    }

    public List<String> getApprovalBlockers(Id applicationId) {
        List<String> blockers = domainFor(new Set<Id>{ applicationId }).getApprovalBlockers().get(applicationId);
        return blockers == null ? new List<String>() : blockers;
    }

    private ILoanApplications domainFor(Set<Id> applicationIds) {
        if (applicationIds == null || applicationIds.isEmpty() || applicationIds.contains(null)) {
            throw new LoanApplicationException('At least one loan application Id is required.');
        }

        List<Loan_Application__c> applications = LoanApplicationsSelector.newInstance()
            .selectByIdWithChildren(applicationIds);

        if (applications.size() != applicationIds.size()) {
            throw new LoanApplicationException(
                'One or more loan applications were not found or you do not have access to them.'
            );
        }
        return LoanApplications.newInstance(applications);
    }
}
