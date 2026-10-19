/**
 * Shared test data. In-memory builders for fast unit tests, plus a persisted lending user
 * for integration tests (selectors run in USER_MODE, so tests must run as a user who
 * actually holds the Lending Officer permission set rather than as the admin).
 */
@IsTest
public class LendingTestDataFactory {
    public static final String LENDING_USER_EMAIL_PREFIX = 'lending.officer@';

    /** A complete, submittable Draft application held in memory with a fake Id. */
    public static Loan_Application__c draftApplication() {
        return new Loan_Application__c(
            Id = fflib_IDGenerator.generate(Loan_Application__c.SObjectType),
            Applicant__c = fflib_IDGenerator.generate(Account.SObjectType),
            Status__c = LoanApplications.STATUS_DRAFT,
            Purpose__c = 'Equipment',
            Requested_Amount__c = 150000,
            Term_Months__c = 60,
            Annual_Revenue__c = 900000,
            Years_Trading__c = 8
        );
    }

    /** A complete Draft application ready to insert (no Id). */
    public static Loan_Application__c newApplication(Id accountId, String purpose) {
        return new Loan_Application__c(
            Applicant__c = accountId,
            Purpose__c = purpose,
            Requested_Amount__c = 150000,
            Term_Months__c = 60,
            Annual_Revenue__c = 900000,
            Years_Trading__c = 8
        );
    }

    public static Required_Document__c document(String documentType, String status) {
        return new Required_Document__c(
            Id = fflib_IDGenerator.generate(Required_Document__c.SObjectType),
            Document_Type__c = documentType,
            Status__c = status
        );
    }

    public static Verification_Check__c check(String checkType, String status) {
        return new Verification_Check__c(
            Id = fflib_IDGenerator.generate(Verification_Check__c.SObjectType),
            Check_Type__c = checkType,
            Status__c = status
        );
    }

    /**
     * Child relationship lists are read-only in Apex, so attach them by round-tripping through JSON,
     * the same shape SOQL returns for a parent-to-child subquery.
     */
    public static Loan_Application__c withChildren(
        Loan_Application__c app,
        List<Required_Document__c> documents,
        List<Verification_Check__c> checks
    ) {
        Map<String, Object> fields = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(app));
        fields.put('Required_Documents__r', relationship(documents));
        fields.put('Verification_Checks__r', relationship(checks));
        return (Loan_Application__c) JSON.deserialize(JSON.serialize(fields), Loan_Application__c.class);
    }

    /** All documents Verified and all checks Passed for the given purpose. */
    public static Loan_Application__c readyForApproval(String status) {
        Loan_Application__c app = draftApplication();
        app.Status__c = status;
        List<Required_Document__c> documents = new List<Required_Document__c>();
        for (String documentType : LoanApplications.requiredDocumentTypes(app.Purpose__c)) {
            documents.add(document(documentType, LoanApplications.DOC_STATUS_VERIFIED));
        }
        List<Verification_Check__c> checks = new List<Verification_Check__c>();
        for (String checkType : LoanApplications.VERIFICATION_CHECK_TYPES) {
            checks.add(check(checkType, LoanApplications.CHECK_STATUS_PASSED));
        }
        return withChildren(app, documents, checks);
    }

    /** Creates a Standard User with the Lending Officer permission set. Call from @TestSetup. */
    public static User createLendingUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User lendingUser = new User(
            ProfileId = standardProfile.Id,
            LastName = 'Officer',
            FirstName = 'Lending',
            Alias = 'lofficer',
            Email = LENDING_USER_EMAIL_PREFIX + unique + '.test',
            Username = LENDING_USER_EMAIL_PREFIX + unique + '.sme-lending.test',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_IE',
            TimeZoneSidKey = 'Europe/Dublin'
        );

        // Setup objects (User, PermissionSetAssignment) need their own DML context to avoid MIXED_DML_OPERATION.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert lendingUser;
            PermissionSet lendingOfficer = [SELECT Id FROM PermissionSet WHERE Name = 'Lending_Officer' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = lendingUser.Id, PermissionSetId = lendingOfficer.Id);
        }
        return lendingUser;
    }

    public static User getLendingUser() {
        String emailPattern = LENDING_USER_EMAIL_PREFIX + '%';
        return [
            SELECT Id
            FROM User
            WHERE Email LIKE :emailPattern
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    private static Map<String, Object> relationship(List<SObject> records) {
        return new Map<String, Object>{ 'totalSize' => records.size(), 'done' => true, 'records' => records };
    }
}
