@IsTest
private class LoanApplicationsSelectorTest {
    @TestSetup
    static void setUp() {
        LendingTestDataFactory.createLendingUser();
    }

    @IsTest
    static void selectByIdWithChildrenReturnsDocumentsAndChecks() {
        Account applicant = new Account(Name = 'Harbour Bikes Ltd');
        insert applicant;

        System.runAs(LendingTestDataFactory.getLendingUser()) {
            Loan_Application__c app = LendingTestDataFactory.newApplication(applicant.Id, 'Working Capital');
            insert app;
            insert new Required_Document__c(Loan_Application__c = app.Id, Document_Type__c = 'Tax Return', Status__c = 'Received');
            insert new Verification_Check__c(Loan_Application__c = app.Id, Check_Type__c = 'KYC', Status__c = 'Pending');

            List<Loan_Application__c> results = LoanApplicationsSelector.newInstance()
                .selectByIdWithChildren(new Set<Id>{ app.Id });

            Assert.areEqual(1, results.size());
            Assert.areEqual('Working Capital', results[0].Purpose__c);
            Assert.areEqual(1, results[0].Required_Documents__r.size());
            Assert.areEqual('Received', results[0].Required_Documents__r[0].Status__c);
            Assert.areEqual(1, results[0].Verification_Checks__r.size());
            Assert.areEqual('KYC', results[0].Verification_Checks__r[0].Check_Type__c);
        }
    }

    @IsTest
    static void selectByIdReturnsOnlyRequestedRecords() {
        Account applicant = new Account(Name = 'Liffey Joinery');
        insert applicant;

        System.runAs(LendingTestDataFactory.getLendingUser()) {
            Loan_Application__c first = LendingTestDataFactory.newApplication(applicant.Id, 'Equipment');
            Loan_Application__c second = LendingTestDataFactory.newApplication(applicant.Id, 'Refinance');
            insert new List<Loan_Application__c>{ first, second };

            List<Loan_Application__c> results = LoanApplicationsSelector.newInstance()
                .selectById(new Set<Id>{ second.Id });

            Assert.areEqual(1, results.size());
            Assert.areEqual(second.Id, results[0].Id);
            Assert.isNotNull(results[0].Risk_Score__c, 'Risk score calculated on insert');
        }
    }

    @IsTest
    static void userModeHidesRecordsTheUserCannotSee() {
        Account applicant = new Account(Name = 'Private Holdings');
        insert applicant;
        // Created by the admin; org-wide default for Loan Application is Private.
        Loan_Application__c adminsApplication = LendingTestDataFactory.newApplication(applicant.Id, 'Equipment');
        insert adminsApplication;

        System.runAs(LendingTestDataFactory.getLendingUser()) {
            List<Loan_Application__c> results = LoanApplicationsSelector.newInstance()
                .selectById(new Set<Id>{ adminsApplication.Id });

            Assert.areEqual(0, results.size(), 'Sharing is enforced by USER_MODE');
        }
    }
}
