@IsTest
private class LoanApplicationControllerTest {
    @TestSetup
    static void setUp() {
        LendingTestDataFactory.createLendingUser();
        insert new Account(Name = 'Galway Surf Supplies');
    }

    @IsTest
    static void submitAndReviewThroughTheController() {
        Id accountId = [SELECT Id FROM Account LIMIT 1].Id;
        System.runAs(LendingTestDataFactory.getLendingUser()) {
            Loan_Application__c app = LendingTestDataFactory.newApplication(accountId, 'Equipment');
            insert app;

            LoanApplicationController.submitApplication(app.Id);
            LoanApplicationController.startReview(app.Id);

            Assert.areEqual(
                LoanApplications.STATUS_IN_REVIEW,
                [SELECT Status__c FROM Loan_Application__c WHERE Id = :app.Id].Status__c
            );
            Assert.areEqual(4 + 3, LoanApplicationController.getApprovalBlockers(app.Id).size());

            LoanApplicationController.recordDecision(app.Id, false, 'Outside appetite.');
            Assert.areEqual(
                LoanApplications.STATUS_DECLINED,
                [SELECT Status__c FROM Loan_Application__c WHERE Id = :app.Id].Status__c
            );
        }
    }

    @IsTest
    static void businessErrorsReachTheUiReadably() {
        Id accountId = [SELECT Id FROM Account LIMIT 1].Id;
        System.runAs(LendingTestDataFactory.getLendingUser()) {
            Loan_Application__c app = new Loan_Application__c(Applicant__c = accountId);
            insert app;

            try {
                LoanApplicationController.submitApplication(app.Id);
                Assert.fail('Expected AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('requested amount is missing'), e.getMessage());
            }
        }
    }

    @IsTest
    static void everyEndpointWrapsFailures() {
        Id missingId = fflib_IDGenerator.generate(Loan_Application__c.SObjectType);
        System.runAs(LendingTestDataFactory.getLendingUser()) {
            Integer failures = 0;
            try {
                LoanApplicationController.startReview(missingId);
            } catch (AuraHandledException e) {
                failures++;
            }
            try {
                LoanApplicationController.recordDecision(missingId, true, 'x');
            } catch (AuraHandledException e) {
                failures++;
            }
            try {
                LoanApplicationController.getApprovalBlockers(missingId);
            } catch (AuraHandledException e) {
                failures++;
            }
            Assert.areEqual(3, failures);
        }
    }

    @IsTest
    static void dmlErrorsUseTheFirstDmlMessage() {
        DmlException dmlError;
        try {
            insert new Loan_Application__c(Requested_Amount__c = -1);
        } catch (DmlException e) {
            dmlError = e;
        }
        Assert.isNotNull(dmlError);

        AuraHandledException converted = LoanApplicationController.toAuraException(dmlError);

        Assert.isTrue(converted.getMessage().startsWith('Requested amount must be'), converted.getMessage());
    }
}
