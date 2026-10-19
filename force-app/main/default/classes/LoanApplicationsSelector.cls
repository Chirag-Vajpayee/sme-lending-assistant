/**
 * All SOQL for Loan_Application__c lives here.
 *
 * Runs in USER_MODE, so the platform enforces the running user's object, field and
 * sharing access (the query factory appends WITH USER_MODE) instead of hand-written checks.
 */
public inherited sharing class LoanApplicationsSelector extends fflib_SObjectSelector implements ILoanApplicationsSelector {
    public static ILoanApplicationsSelector newInstance() {
        return (ILoanApplicationsSelector) Application.Selector.newInstance(Loan_Application__c.SObjectType);
    }

    public LoanApplicationsSelector() {
        super(false, fflib_SObjectSelector.DataAccess.USER_MODE);
    }

    public Schema.SObjectType getSObjectType() {
        return Loan_Application__c.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
            Loan_Application__c.Id,
            Loan_Application__c.Name,
            Loan_Application__c.Applicant__c,
            Loan_Application__c.Requested_Amount__c,
            Loan_Application__c.Term_Months__c,
            Loan_Application__c.Purpose__c,
            Loan_Application__c.Status__c,
            Loan_Application__c.Annual_Revenue__c,
            Loan_Application__c.Years_Trading__c,
            Loan_Application__c.Risk_Score__c,
            Loan_Application__c.Risk_Rating__c,
            Loan_Application__c.Submitted_Date__c,
            Loan_Application__c.Decision_Date__c,
            Loan_Application__c.Decision_Notes__c
        };
    }

    public override String getOrderBy() {
        return 'Name';
    }

    public List<Loan_Application__c> selectById(Set<Id> applicationIds) {
        return (List<Loan_Application__c>) selectSObjectsById(applicationIds);
    }

    public List<Loan_Application__c> selectByIdWithChildren(Set<Id> applicationIds) {
        fflib_QueryFactory query = newQueryFactory().setCondition('Id IN :applicationIds');

        query.subselectQuery('Required_Documents__r')
            .selectFields(
                new List<Schema.SObjectField>{
                    Required_Document__c.Id,
                    Required_Document__c.Name,
                    Required_Document__c.Document_Type__c,
                    Required_Document__c.Status__c
                }
            );

        query.subselectQuery('Verification_Checks__r')
            .selectFields(
                new List<Schema.SObjectField>{
                    Verification_Check__c.Id,
                    Verification_Check__c.Name,
                    Verification_Check__c.Check_Type__c,
                    Verification_Check__c.Status__c,
                    Verification_Check__c.Score__c,
                    Verification_Check__c.Response_Summary__c
                }
            );

        return (List<Loan_Application__c>) Database.query(query.toSOQL());
    }
}
