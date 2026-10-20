Loan_Application__c app = [SELECT Id, Applicant__c, Requested_Amount__c, Annual_Revenue__c FROM Loan_Application__c LIMIT 1];
VerificationResult r = new HttpVerificationProvider().verify(app, new Verification_Check__c(Check_Type__c = 'KYC'));
System.debug('RESULT: ' + r.status + ' | score ' + r.score + ' | ' + r.durationMs + 'ms | ref ' + r.reference);
