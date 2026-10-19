/**
 * Service unit tests: selector, domain and Unit of Work are all ApexMocks stubs injected
 * through the Application factory, so these tests prove orchestration only (load -> domain -> commit).
 */
@IsTest
private class LoanApplicationServiceTest {
    private static fflib_ApexMocks mocks;
    private static fflib_ISObjectUnitOfWork uowMock;
    private static ILoanApplicationsSelector selectorMock;
    private static ILoanApplications domainMock;
    private static Id applicationId;

    private static void setUpMocks(List<Loan_Application__c> selectorResult) {
        mocks = new fflib_ApexMocks();
        uowMock = (fflib_ISObjectUnitOfWork) mocks.mock(fflib_ISObjectUnitOfWork.class);
        selectorMock = (ILoanApplicationsSelector) mocks.mock(ILoanApplicationsSelector.class);
        domainMock = (ILoanApplications) mocks.mock(ILoanApplications.class);

        mocks.startStubbing();
        mocks.when(selectorMock.selectByIdWithChildren(new Set<Id>{ applicationId })).thenReturn(selectorResult);
        mocks.when(domainMock.getApprovalBlockers())
            .thenReturn(new Map<Id, List<String>>{ applicationId => new List<String>{ 'AML check is Pending' } });
        mocks.stopStubbing();

        Application.UnitOfWork.setMock(uowMock);
        Application.Selector.setMock(Loan_Application__c.SObjectType, selectorMock);
        Application.Domain.setMock(Loan_Application__c.SObjectType, domainMock);
    }

    private static List<Loan_Application__c> oneApplication() {
        applicationId = fflib_IDGenerator.generate(Loan_Application__c.SObjectType);
        return new List<Loan_Application__c>{ new Loan_Application__c(Id = applicationId) };
    }

    @IsTest
    static void submitDelegatesToDomainAndCommitsOnce() {
        setUpMocks(oneApplication());

        LoanApplicationService.submit(new Set<Id>{ applicationId });

        ((ILoanApplications) mocks.verify(domainMock)).submit(uowMock);
        ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, 1)).commitWork();
    }

    @IsTest
    static void startReviewDelegatesToDomainAndCommitsOnce() {
        setUpMocks(oneApplication());

        LoanApplicationService.startReview(new Set<Id>{ applicationId });

        ((ILoanApplications) mocks.verify(domainMock)).startReview(uowMock);
        ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, 1)).commitWork();
    }

    @IsTest
    static void recordDecisionPassesDecisionThrough() {
        setUpMocks(oneApplication());

        LoanApplicationService.recordDecision(applicationId, false, 'Insufficient revenue');

        ((ILoanApplications) mocks.verify(domainMock)).recordDecision(false, 'Insufficient revenue', uowMock);
        ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, 1)).commitWork();
    }

    @IsTest
    static void approvalBlockersAreReturnedForTheApplication() {
        setUpMocks(oneApplication());

        List<String> blockers = LoanApplicationService.getApprovalBlockers(applicationId);

        Assert.areEqual(new List<String>{ 'AML check is Pending' }, blockers);
        ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, 0)).commitWork();
    }

    @IsTest
    static void missingOrInaccessibleRecordsFailBeforeAnyWork() {
        applicationId = fflib_IDGenerator.generate(Loan_Application__c.SObjectType);
        setUpMocks(new List<Loan_Application__c>());

        try {
            LoanApplicationService.submit(new Set<Id>{ applicationId });
            Assert.fail('Expected LoanApplicationException');
        } catch (LoanApplicationException e) {
            Assert.isTrue(e.getMessage().contains('not found'), e.getMessage());
        }
        ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, 0)).commitWork();
    }

    @IsTest
    static void emptyOrNullIdsAreRejected() {
        for (Set<Id> ids : new List<Set<Id>>{ null, new Set<Id>(), new Set<Id>{ null } }) {
            try {
                LoanApplicationService.submit(ids);
                Assert.fail('Expected LoanApplicationException for ' + ids);
            } catch (LoanApplicationException e) {
                Assert.isTrue(e.getMessage().contains('required'), e.getMessage());
            }
        }
    }
}
