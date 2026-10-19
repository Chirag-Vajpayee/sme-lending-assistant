/**
 * End-to-end tests against the real database: trigger -> domain -> service -> selector -> Unit of Work,
 * running as a Lending Officer so object, field and sharing access are exercised for real.
 */
@IsTest
private class LoanApplicationLifecycleTest {
    @TestSetup
    static void setUp() {
        LendingTestDataFactory.createLendingUser();
        insert new Account(Name = 'Dublin Bay Coffee Roasters');
    }

    private static Id applicantId() {
        return [SELECT Id FROM Account WHERE Name = 'Dublin Bay Coffee Roasters' LIMIT 1].Id;
    }

    private static Loan_Application__c reload(Id applicationId) {
        return [
            SELECT
                Status__c,
                Risk_Score__c,
                Risk_Rating__c,
                Submitted_Date__c,
                Decision_Date__c,
                Decision_Notes__c,
                (SELECT Document_Type__c, Status__c FROM Required_Documents__r),
                (SELECT Check_Type__c, Status__c FROM Verification_Checks__r)
            FROM Loan_Application__c
            WHERE Id = :applicationId
        ];
    }

    @IsTest
    static void fullLifecycleFromDraftToApproved() {
        Id accountId = applicantId();
        System.runAs(LendingTestDataFactory.getLendingUser()) {
            Loan_Application__c app = LendingTestDataFactory.newApplication(accountId, 'Commercial Property');
            insert app;

            Test.startTest();
            LoanApplicationService.submit(new Set<Id>{ app.Id });

            Loan_Application__c submitted = reload(app.Id);
            Assert.areEqual(LoanApplications.STATUS_SUBMITTED, submitted.Status__c);
            Assert.isNotNull(submitted.Submitted_Date__c);
            Assert.areEqual(5, submitted.Required_Documents__r.size(), '3 base + valuation + business plan');
            Assert.areEqual(3, submitted.Verification_Checks__r.size());

            LoanApplicationService.startReview(new Set<Id>{ app.Id });
            Assert.areEqual(5 + 3, LoanApplicationService.getApprovalBlockers(app.Id).size());

            for (Required_Document__c doc : submitted.Required_Documents__r) {
                doc.Status__c = LoanApplications.DOC_STATUS_VERIFIED;
            }
            for (Verification_Check__c check : submitted.Verification_Checks__r) {
                check.Status__c = LoanApplications.CHECK_STATUS_PASSED;
            }
            update submitted.Required_Documents__r;
            update submitted.Verification_Checks__r;

            LoanApplicationService.recordDecision(app.Id, true, 'Valuation supports the loan.');
            Test.stopTest();

            Loan_Application__c approved = reload(app.Id);
            Assert.areEqual(LoanApplications.STATUS_APPROVED, approved.Status__c);
            Assert.isNotNull(approved.Decision_Date__c);
            Assert.areEqual('Valuation supports the loan.', approved.Decision_Notes__c);
        }
    }

    @IsTest
    static void approvalIsBlockedUntilChecksPass() {
        Id accountId = applicantId();
        System.runAs(LendingTestDataFactory.getLendingUser()) {
            Loan_Application__c app = LendingTestDataFactory.newApplication(accountId, 'Equipment');
            insert app;
            LoanApplicationService.submit(new Set<Id>{ app.Id });
            LoanApplicationService.startReview(new Set<Id>{ app.Id });

            try {
                LoanApplicationService.recordDecision(app.Id, true, 'Approve');
                Assert.fail('Expected LoanApplicationException');
            } catch (LoanApplicationException e) {
                Assert.isTrue(e.getMessage().contains('KYC check is Pending'), e.getMessage());
            }
            Assert.areEqual(LoanApplications.STATUS_IN_REVIEW, reload(app.Id).Status__c);
        }
    }

    @IsTest
    static void triggerBlocksSkippingTheStateMachine() {
        Id accountId = applicantId();
        System.runAs(LendingTestDataFactory.getLendingUser()) {
            Loan_Application__c app = LendingTestDataFactory.newApplication(accountId, 'Refinance');
            insert app;

            app.Status__c = LoanApplications.STATUS_APPROVED;
            try {
                update app;
                Assert.fail('Expected DmlException');
            } catch (DmlException e) {
                Assert.areEqual('Status cannot change from Draft to Approved.', e.getDmlMessage(0));
            }
        }
    }

    @IsTest
    static void triggerScoresRiskAndValidatesOnInsert() {
        Id accountId = applicantId();
        System.runAs(LendingTestDataFactory.getLendingUser()) {
            Loan_Application__c app = LendingTestDataFactory.newApplication(accountId, 'Working Capital');
            insert app;
            Loan_Application__c saved = reload(app.Id);
            Assert.areEqual(LoanApplications.STATUS_DRAFT, saved.Status__c);
            Assert.isNotNull(saved.Risk_Score__c);
            Assert.isNotNull(saved.Risk_Rating__c);

            Loan_Application__c tooLarge = LendingTestDataFactory.newApplication(accountId, 'Working Capital');
            tooLarge.Requested_Amount__c = LoanApplications.MAX_REQUESTED_AMOUNT + 1;
            Database.SaveResult result = Database.insert(tooLarge, false);
            Assert.isFalse(result.isSuccess());
            Assert.isTrue(result.getErrors()[0].getMessage().startsWith('Requested amount must be'));
        }
    }

    @IsTest
    static void onlyDraftApplicationsCanBeDeleted() {
        Id accountId = applicantId();
        System.runAs(LendingTestDataFactory.getLendingUser()) {
            Loan_Application__c app = LendingTestDataFactory.newApplication(accountId, 'Equipment');
            insert app;
            LoanApplicationService.submit(new Set<Id>{ app.Id });

            Database.DeleteResult result = Database.delete(app.Id, false);

            Assert.isFalse(result.isSuccess());
            Assert.isTrue(result.getErrors()[0].getMessage().contains('Only Draft applications can be deleted'));
        }
    }

    @IsTest
    static void bulkSubmitStaysWithinLimits() {
        Id accountId = applicantId();
        System.runAs(LendingTestDataFactory.getLendingUser()) {
            List<Loan_Application__c> apps = new List<Loan_Application__c>();
            for (Integer i = 0; i < 200; i++) {
                apps.add(LendingTestDataFactory.newApplication(accountId, 'Working Capital'));
            }
            insert apps;

            Test.startTest();
            LoanApplicationService.submit(new Map<Id, Loan_Application__c>(apps).keySet());
            Integer queriesUsed = Limits.getQueries();
            Test.stopTest();

            Assert.areEqual(200 * 4, [SELECT COUNT() FROM Required_Document__c]);
            Assert.areEqual(200 * 3, [SELECT COUNT() FROM Verification_Check__c]);
            Assert.isTrue(queriesUsed < 10, 'Submit should use a constant number of queries, used ' + queriesUsed);
        }
    }
}
