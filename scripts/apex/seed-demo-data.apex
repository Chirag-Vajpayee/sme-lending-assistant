// Demo data: three Irish SMEs with applications at different lifecycle stages.
// Run with: sf apex run --file scripts/apex/seed-demo-data.apex

List<Account> applicants = new List<Account>{
    new Account(Name = 'Harbour Bikes Ltd', Industry = 'Retail', BillingCity = 'Cork', BillingCountry = 'Ireland'),
    new Account(Name = 'Liffey Joinery', Industry = 'Manufacturing', BillingCity = 'Dublin', BillingCountry = 'Ireland'),
    new Account(Name = 'Atlantic Seafood Co', Industry = 'Food & Beverage', BillingCity = 'Galway', BillingCountry = 'Ireland')
};
insert applicants;

List<Loan_Application__c> apps = new List<Loan_Application__c>{
    // Low risk, will be submitted and moved to review
    new Loan_Application__c(Applicant__c = applicants[0].Id, Purpose__c = 'Equipment',
        Requested_Amount__c = 85000, Term_Months__c = 48, Annual_Revenue__c = 1200000, Years_Trading__c = 14),
    // Medium risk, will be submitted
    new Loan_Application__c(Applicant__c = applicants[1].Id, Purpose__c = 'Working Capital',
        Requested_Amount__c = 250000, Term_Months__c = 36, Annual_Revenue__c = 400000, Years_Trading__c = 4),
    // High risk, left in Draft
    new Loan_Application__c(Applicant__c = applicants[2].Id, Purpose__c = 'Commercial Property',
        Requested_Amount__c = 1500000, Term_Months__c = 240, Annual_Revenue__c = 600000, Years_Trading__c = 1)
};
insert apps;

LoanApplicationService.submit(new Set<Id>{ apps[0].Id, apps[1].Id });
LoanApplicationService.startReview(new Set<Id>{ apps[0].Id });

// Simulate partial progress on the first application so approval blockers are visible.
List<Required_Document__c> docs = [
    SELECT Id, Status__c FROM Required_Document__c WHERE Loan_Application__c = :apps[0].Id ORDER BY Name LIMIT 2
];
for (Required_Document__c doc : docs) {
    doc.Status__c = 'Verified';
}
update docs;

Verification_Check__c kyc = [
    SELECT Id FROM Verification_Check__c WHERE Loan_Application__c = :apps[0].Id AND Check_Type__c = 'KYC' LIMIT 1
];
kyc.Status__c = 'Passed';
kyc.Response_Summary__c = 'Identity and directors confirmed';
update kyc;

System.debug('Approval blockers for ' + apps[0].Id + ': ' + LoanApplicationService.getApprovalBlockers(apps[0].Id));
