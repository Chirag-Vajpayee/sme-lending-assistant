/**
 * Domain unit tests. No DML: trigger events are simulated with fflib's in-memory
 * MockDatabase, and Unit of Work interactions are verified with ApexMocks.
 */
@IsTest
private class LoanApplicationsTest {
    // ------------------------------------------------------------------ trigger behaviour

    @IsTest
    static void insertDefaultsStatusAndScoresRisk() {
        Loan_Application__c app = new Loan_Application__c(
            Requested_Amount__c = 100000,
            Annual_Revenue__c = 500000,
            Years_Trading__c = 12,
            Term_Months__c = 60
        );

        simulateInsert(app);

        Assert.areEqual(LoanApplications.STATUS_DRAFT, app.Status__c);
        Assert.areEqual(20, app.Risk_Score__c);
        Assert.areEqual(LoanRiskCalculator.RATING_LOW, app.Risk_Rating__c);
        Assert.areEqual(0, fflib_SObjectDomain.Errors.getAll().size());
    }

    @IsTest
    static void insertRejectsOutOfRangeAmountAndTerm() {
        Loan_Application__c app = new Loan_Application__c(Requested_Amount__c = 6000000, Term_Months__c = 3);

        simulateInsert(app);

        List<fflib_SObjectDomain.Error> errors = fflib_SObjectDomain.Errors.getAll();
        Assert.areEqual(2, errors.size(), 'Expected one error for amount and one for term');
        Assert.isTrue(errors[0].message.startsWith('Requested amount must be'), errors[0].message);
        Assert.isTrue(errors[1].message.startsWith('Term must be between'), errors[1].message);
    }

    @IsTest
    static void updateStampsSubmittedDateOnAllowedTransition() {
        Loan_Application__c existing = LendingTestDataFactory.draftApplication();
        Loan_Application__c changed = existing.clone(true, true);
        changed.Status__c = LoanApplications.STATUS_SUBMITTED;

        simulateUpdate(existing, changed);

        Assert.areEqual(0, fflib_SObjectDomain.Errors.getAll().size());
        Assert.isNotNull(changed.Submitted_Date__c);
        Assert.isNull(changed.Decision_Date__c);
    }

    @IsTest
    static void updateStampsDecisionDate() {
        Loan_Application__c existing = LendingTestDataFactory.draftApplication();
        existing.Status__c = LoanApplications.STATUS_IN_REVIEW;
        Loan_Application__c changed = existing.clone(true, true);
        changed.Status__c = LoanApplications.STATUS_DECLINED;

        simulateUpdate(existing, changed);

        Assert.areEqual(0, fflib_SObjectDomain.Errors.getAll().size());
        Assert.isNotNull(changed.Decision_Date__c);
    }

    @IsTest
    static void updateRejectsTransitionOutsideStateMachine() {
        Loan_Application__c existing = LendingTestDataFactory.draftApplication();
        Loan_Application__c changed = existing.clone(true, true);
        changed.Status__c = LoanApplications.STATUS_APPROVED;

        simulateUpdate(existing, changed);

        List<fflib_SObjectDomain.Error> errors = fflib_SObjectDomain.Errors.getAll();
        Assert.areEqual(1, errors.size());
        Assert.areEqual('Status cannot change from Draft to Approved.', errors[0].message);
    }

    @IsTest
    static void terminalStatusesCannotChange() {
        for (String terminal : new List<String>{
            LoanApplications.STATUS_APPROVED,
            LoanApplications.STATUS_DECLINED,
            LoanApplications.STATUS_WITHDRAWN
        }) {
            Assert.isTrue(
                LoanApplications.ALLOWED_TRANSITIONS.get(terminal).isEmpty(),
                terminal + ' should be terminal'
            );
        }
    }

    // ------------------------------------------------------------------ submit

    @IsTest
    static void submitRegistersChecklistChecksAndStatusChange() {
        Loan_Application__c app = LendingTestDataFactory.draftApplication(); // Equipment
        fflib_ApexMocks mocks = new fflib_ApexMocks();
        fflib_ISObjectUnitOfWork uow = (fflib_ISObjectUnitOfWork) mocks.mock(fflib_ISObjectUnitOfWork.class);

        new LoanApplications(new List<Loan_Application__c>{ app }).submit(uow);

        // 3 base documents + Equipment Quote + 3 verification checks
        fflib_ArgumentCaptor captor = fflib_ArgumentCaptor.forClass(SObject.class);
        ((fflib_ISObjectUnitOfWork) mocks.verify(uow, 7))
            .registerNew((SObject) captor.capture(), fflib_Match.anySObjectField(), fflib_Match.anySObject());

        Set<String> documentTypes = new Set<String>();
        Set<String> checkTypes = new Set<String>();
        for (Object registered : captor.getAllValues()) {
            if (registered instanceof Required_Document__c) {
                documentTypes.add(((Required_Document__c) registered).Document_Type__c);
            } else {
                Verification_Check__c check = (Verification_Check__c) registered;
                Assert.areEqual(LoanApplications.CHECK_STATUS_PENDING, check.Status__c);
                checkTypes.add(check.Check_Type__c);
            }
        }
        Assert.areEqual(
            new Set<String>{ 'Financial Statements', 'Bank Statements', 'Proof of Identity', 'Equipment Quote' },
            documentTypes
        );
        Assert.areEqual(new Set<String>{ 'KYC', 'AML', 'Credit Bureau' }, checkTypes);

        ((fflib_ISObjectUnitOfWork) mocks.verify(uow))
            .registerDirty(
                fflib_Match.sObjectWith(
                    new Map<SObjectField, Object>{
                        Loan_Application__c.Id => app.Id,
                        Loan_Application__c.Status__c => LoanApplications.STATUS_SUBMITTED
                    }
                )
            );

         ((fflib_ISObjectUnitOfWork) mocks.verify(uow, 1))
            .registerPublishAfterSuccessTransaction(
                fflib_Match.sObjectWith(
                    new Map<SObjectField, Object>{
                        Loan_Application_Submitted__e.Application_Id__c => String.valueOf(app.Id)
                    }
                )
            );
    }

    @IsTest
    static void submitDoesNotDuplicateExistingChildren() {
        Loan_Application__c app = LendingTestDataFactory.withChildren(
            LendingTestDataFactory.draftApplication(),
            new List<Required_Document__c>{ LendingTestDataFactory.document('Bank Statements', 'Received') },
            new List<Verification_Check__c>{ LendingTestDataFactory.check('KYC', 'Passed') }
        );
        fflib_ApexMocks mocks = new fflib_ApexMocks();
        fflib_ISObjectUnitOfWork uow = (fflib_ISObjectUnitOfWork) mocks.mock(fflib_ISObjectUnitOfWork.class);

        new LoanApplications(new List<Loan_Application__c>{ app }).submit(uow);

        // 4 documents - 1 existing + 3 checks - 1 existing
        ((fflib_ISObjectUnitOfWork) mocks.verify(uow, 5))
            .registerNew(fflib_Match.anySObject(), fflib_Match.anySObjectField(), fflib_Match.anySObject());
    }

    @IsTest
    static void submitListsEveryMissingField() {
        Loan_Application__c app = new Loan_Application__c(
            Id = fflib_IDGenerator.generate(Loan_Application__c.SObjectType),
            Status__c = LoanApplications.STATUS_DRAFT
        );
        fflib_ApexMocks mocks = new fflib_ApexMocks();
        fflib_ISObjectUnitOfWork uow = (fflib_ISObjectUnitOfWork) mocks.mock(fflib_ISObjectUnitOfWork.class);

        try {
            new LoanApplications(new List<Loan_Application__c>{ app }).submit(uow);
            Assert.fail('Expected LoanApplicationException');
        } catch (LoanApplicationException e) {
            for (String expected : new List<String>{ 'applicant', 'requested amount', 'term', 'purpose', 'annual revenue' }) {
                Assert.isTrue(e.getMessage().contains(expected + ' is missing'), e.getMessage());
            }
        }
        ((fflib_ISObjectUnitOfWork) mocks.verify(uow, 0)).registerDirty(fflib_Match.anySObject());
    }

    @IsTest
    static void submitRejectsNonDraft() {
        Loan_Application__c app = LendingTestDataFactory.draftApplication();
        app.Status__c = LoanApplications.STATUS_SUBMITTED;

        try {
            new LoanApplications(new List<Loan_Application__c>{ app }).submit(mockUnitOfWork());
            Assert.fail('Expected LoanApplicationException');
        } catch (LoanApplicationException e) {
            Assert.isTrue(e.getMessage().contains('it is Submitted, not Draft'), e.getMessage());
        }
    }

    // ------------------------------------------------------------------ review and decision

    @IsTest
    static void startReviewRequiresSubmitted() {
        Loan_Application__c app = LendingTestDataFactory.draftApplication();
        try {
            new LoanApplications(new List<Loan_Application__c>{ app }).startReview(mockUnitOfWork());
            Assert.fail('Expected LoanApplicationException');
        } catch (LoanApplicationException e) {
            Assert.isTrue(e.getMessage().contains('expected Submitted'), e.getMessage());
        }
    }

    @IsTest
    static void startReviewRegistersInReview() {
        Loan_Application__c app = LendingTestDataFactory.draftApplication();
        app.Status__c = LoanApplications.STATUS_SUBMITTED;
        fflib_ApexMocks mocks = new fflib_ApexMocks();
        fflib_ISObjectUnitOfWork uow = (fflib_ISObjectUnitOfWork) mocks.mock(fflib_ISObjectUnitOfWork.class);

        new LoanApplications(new List<Loan_Application__c>{ app }).startReview(uow);

        ((fflib_ISObjectUnitOfWork) mocks.verify(uow))
            .registerDirty(
                fflib_Match.sObjectWith(
                    new Map<SObjectField, Object>{ Loan_Application__c.Status__c => LoanApplications.STATUS_IN_REVIEW }
                )
            );
    }

    @IsTest
    static void approvalBlockersListOutstandingWork() {
        Loan_Application__c app = LendingTestDataFactory.withChildren(
            LendingTestDataFactory.draftApplication(),
            new List<Required_Document__c>{
                LendingTestDataFactory.document('Bank Statements', 'Verified'),
                LendingTestDataFactory.document('Tax Return', 'Requested')
            },
            new List<Verification_Check__c>{
                LendingTestDataFactory.check('KYC', 'Passed'),
                LendingTestDataFactory.check('AML', 'Failed')
            }
        );

        List<String> blockers = new LoanApplications(new List<Loan_Application__c>{ app })
            .getApprovalBlockers()
            .get(app.Id);

        Assert.areEqual(
            new List<String>{
                'Tax Return is Requested',
                'Financial Statements has not been requested',
                'Proof of Identity has not been requested',
                'Equipment Quote has not been requested',
                'AML check is Failed',
                'Credit Bureau check has not been run'
            },
            blockers,
            'Every unverified, missing or failed item should be listed in a stable order'
        );
    }

    @IsTest
    static void approveWhenEverythingIsVerified() {
        Loan_Application__c app = LendingTestDataFactory.readyForApproval(LoanApplications.STATUS_IN_REVIEW);
        fflib_ApexMocks mocks = new fflib_ApexMocks();
        fflib_ISObjectUnitOfWork uow = (fflib_ISObjectUnitOfWork) mocks.mock(fflib_ISObjectUnitOfWork.class);

        new LoanApplications(new List<Loan_Application__c>{ app }).recordDecision(true, 'Strong cash flow.', uow);

        ((fflib_ISObjectUnitOfWork) mocks.verify(uow))
            .registerDirty(
                fflib_Match.sObjectWith(
                    new Map<SObjectField, Object>{
                        Loan_Application__c.Status__c => LoanApplications.STATUS_APPROVED,
                        Loan_Application__c.Decision_Notes__c => 'Strong cash flow.'
                    }
                )
            );
    }

    @IsTest
    static void approvalBlockedByOutstandingWork() {
        Loan_Application__c app = LendingTestDataFactory.withChildren(
            LendingTestDataFactory.draftApplication(),
            new List<Required_Document__c>(),
            new List<Verification_Check__c>()
        );
        app.Status__c = LoanApplications.STATUS_IN_REVIEW;

        try {
            new LoanApplications(new List<Loan_Application__c>{ app }).recordDecision(true, 'Looks fine', mockUnitOfWork());
            Assert.fail('Expected LoanApplicationException');
        } catch (LoanApplicationException e) {
            Assert.isTrue(e.getMessage().contains('KYC check has not been run'), e.getMessage());
        }
    }

    @IsTest
    static void declineIsAllowedWithOutstandingWork() {
        Loan_Application__c app = LendingTestDataFactory.draftApplication();
        app.Status__c = LoanApplications.STATUS_IN_REVIEW;
        fflib_ApexMocks mocks = new fflib_ApexMocks();
        fflib_ISObjectUnitOfWork uow = (fflib_ISObjectUnitOfWork) mocks.mock(fflib_ISObjectUnitOfWork.class);

        new LoanApplications(new List<Loan_Application__c>{ app }).recordDecision(false, 'AML concerns.', uow);

        ((fflib_ISObjectUnitOfWork) mocks.verify(uow))
            .registerDirty(
                fflib_Match.sObjectWith(
                    new Map<SObjectField, Object>{ Loan_Application__c.Status__c => LoanApplications.STATUS_DECLINED }
                )
            );
    }

    @IsTest
    static void decisionRequiresNotesAndAnAnswer() {
        ILoanApplications domain = new LoanApplications(
            new List<Loan_Application__c>{ LendingTestDataFactory.readyForApproval(LoanApplications.STATUS_IN_REVIEW) }
        );

        try {
            domain.recordDecision(true, '  ', mockUnitOfWork());
            Assert.fail('Expected LoanApplicationException for blank notes');
        } catch (LoanApplicationException e) {
            Assert.isTrue(e.getMessage().contains('notes are required'), e.getMessage());
        }

        try {
            domain.recordDecision(null, 'Notes', mockUnitOfWork());
            Assert.fail('Expected LoanApplicationException for missing decision');
        } catch (LoanApplicationException e) {
            Assert.isTrue(e.getMessage().contains('decision'), e.getMessage());
        }
    }

    @IsTest
    static void documentChecklistFollowsPurpose() {
        Assert.areEqual(5, LoanApplications.requiredDocumentTypes('Commercial Property').size());
        Assert.isTrue(LoanApplications.requiredDocumentTypes('Refinance').contains('Existing Loan Statement'));
        Assert.areEqual(3, LoanApplications.requiredDocumentTypes(null).size());
    }

    // ------------------------------------------------------------------ helpers

    private static void simulateInsert(Loan_Application__c app) {
        fflib_SObjectDomain.Test.Database.onInsert(new List<Loan_Application__c>{ app });
        fflib_SObjectDomain.triggerHandler(LoanApplications.class);
    }

    private static void simulateUpdate(Loan_Application__c existing, Loan_Application__c changed) {
        fflib_SObjectDomain.Test.Database.onUpdate(
            new List<Loan_Application__c>{ changed },
            new Map<Id, SObject>{ existing.Id => existing }
        );
        fflib_SObjectDomain.triggerHandler(LoanApplications.class);
    }

    private static fflib_ISObjectUnitOfWork mockUnitOfWork() {
        return (fflib_ISObjectUnitOfWork) new fflib_ApexMocks().mock(fflib_ISObjectUnitOfWork.class);
    }
}
