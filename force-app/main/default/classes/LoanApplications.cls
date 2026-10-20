/**
 * Domain layer for Loan_Application__c: all business rules about a loan application live here,
 * whether they run from the trigger (validation, defaults, risk scoring, status stamping) or
 * are invoked by the service layer (submit, review, decision).
 *
 * Nothing in this class runs SOQL or DML directly; changes are registered on the Unit of Work
 * the caller passes in, so the service controls the transaction boundary.
 */
public with sharing class LoanApplications extends fflib_SObjectDomain implements ILoanApplications {
    public static final Decimal MAX_REQUESTED_AMOUNT = 5000000;
    public static final Integer MIN_TERM_MONTHS = 6;
    public static final Integer MAX_TERM_MONTHS = 360;

    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_IN_REVIEW = 'In Review';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_DECLINED = 'Declined';
    public static final String STATUS_WITHDRAWN = 'Withdrawn';

    public static final String DOC_STATUS_REQUESTED = 'Requested';
    public static final String DOC_STATUS_VERIFIED = 'Verified';
    public static final String CHECK_STATUS_PENDING = 'Pending';
    public static final String CHECK_STATUS_PASSED = 'Passed';

    /** The lifecycle state machine. Anything not listed here is rejected on update. */
    @TestVisible
    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        STATUS_DRAFT => new Set<String>{ STATUS_SUBMITTED, STATUS_WITHDRAWN },
        STATUS_SUBMITTED => new Set<String>{ STATUS_IN_REVIEW, STATUS_WITHDRAWN },
        STATUS_IN_REVIEW => new Set<String>{ STATUS_APPROVED, STATUS_DECLINED, STATUS_WITHDRAWN },
        STATUS_APPROVED => new Set<String>(),
        STATUS_DECLINED => new Set<String>(),
        STATUS_WITHDRAWN => new Set<String>()
    };

    /** Documents every applicant supplies, plus extras driven by the loan purpose. */
    @TestVisible
    private static final List<String> BASE_DOCUMENTS = new List<String>{
        'Financial Statements',
        'Bank Statements',
        'Proof of Identity'
    };

    @TestVisible
    private static final Map<String, List<String>> DOCUMENTS_BY_PURPOSE = new Map<String, List<String>>{
        'Working Capital' => new List<String>{ 'Tax Return' },
        'Equipment' => new List<String>{ 'Equipment Quote' },
        'Commercial Property' => new List<String>{ 'Property Valuation', 'Business Plan' },
        'Refinance' => new List<String>{ 'Existing Loan Statement' }
    };

    @TestVisible
    private static final List<String> VERIFICATION_CHECK_TYPES = new List<String>{ 'KYC', 'AML', 'Credit Bureau' };

    public static ILoanApplications newInstance(List<Loan_Application__c> records) {
        return (ILoanApplications) Application.Domain.newInstance(records);
    }

    public LoanApplications(List<Loan_Application__c> records) {
        super(records);
    }

    public List<Loan_Application__c> getLoanApplications() {
        return (List<Loan_Application__c>) Records;
    }

    // ------------------------------------------------------------------ trigger events

    public override void onApplyDefaults() {
        for (Loan_Application__c app : getLoanApplications()) {
            if (String.isBlank(app.Status__c)) {
                app.Status__c = STATUS_DRAFT;
            }
        }
    }

    public override void onBeforeInsert() {
        applyRiskScores(getLoanApplications());
    }

    public override void onBeforeUpdate(Map<Id, SObject> existingRecords) {
        applyRiskScores(getLoanApplications());
        stampStatusDates(existingRecords);
    }

    public override void onValidate() {
        for (Loan_Application__c app : getLoanApplications()) {
            validateAmountAndTerm(app);
        }
    }

    public override void onValidate(Map<Id, SObject> existingRecords) {
        for (Loan_Application__c app : getLoanApplications()) {
            validateAmountAndTerm(app);
            validateStatusTransition(app, (Loan_Application__c) existingRecords.get(app.Id));
        }
    }

    public override void onBeforeDelete() {
        for (Loan_Application__c app : getLoanApplications()) {
            if (app.Status__c != STATUS_DRAFT) {
                app.addError(error('Only Draft applications can be deleted. Withdraw it instead.', app));
            }
        }
    }

    // ------------------------------------------------------------------ behaviour used by the service layer

    public void submit(fflib_ISObjectUnitOfWork uow) {
        // Validate the whole batch first so a bulk submit is all-or-nothing with every problem reported.
        List<String> failures = new List<String>();
        for (Loan_Application__c app : getLoanApplications()) {
            List<String> problems = submissionProblems(app);
            if (!problems.isEmpty()) {
                failures.add(label(app) + ' cannot be submitted: ' + String.join(problems, '; '));
            }
        }
        if (!failures.isEmpty()) {
            throw new LoanApplicationException(String.join(failures, '\n'));
        }

        for (Loan_Application__c app : getLoanApplications()) {
            registerMissingDocuments(app, uow);
            registerMissingChecks(app, uow);
            uow.registerDirty(new Loan_Application__c(Id = app.Id, Status__c = STATUS_SUBMITTED));
            uow.registerPublishAfterSuccessTransaction(new Loan_Application_Submitted__e(Application_Id__c = app.Id));
        }
    }

    public void startReview(fflib_ISObjectUnitOfWork uow) {
        for (Loan_Application__c app : getLoanApplications()) {
            requireStatus(app, STATUS_SUBMITTED, 'start review on');
            uow.registerDirty(new Loan_Application__c(Id = app.Id, Status__c = STATUS_IN_REVIEW));
        }
    }

    public void recordDecision(Boolean approve, String notes, fflib_ISObjectUnitOfWork uow) {
        if (approve == null) {
            throw new LoanApplicationException('A decision (approve or decline) is required.');
        }
        if (String.isBlank(notes)) {
            throw new LoanApplicationException('Decision notes are required for the audit trail.');
        }

        Map<Id, List<String>> blockersById = approve ? getApprovalBlockers() : new Map<Id, List<String>>();
        for (Loan_Application__c app : getLoanApplications()) {
            requireStatus(app, STATUS_IN_REVIEW, approve ? 'approve' : 'decline');

            List<String> blockers = blockersById.get(app.Id);
            if (blockers != null && !blockers.isEmpty()) {
                throw new LoanApplicationException(label(app) + ' cannot be approved: ' + String.join(blockers, '; '));
            }

            uow.registerDirty(
                new Loan_Application__c(
                    Id = app.Id,
                    Status__c = approve ? STATUS_APPROVED : STATUS_DECLINED,
                    Decision_Notes__c = notes
                )
            );
        }
    }

    public Map<Id, List<String>> getApprovalBlockers() {
        Map<Id, List<String>> blockersById = new Map<Id, List<String>>();
        for (Loan_Application__c app : getLoanApplications()) {
            List<String> blockers = new List<String>();

            Set<String> requestedDocuments = new Set<String>();
            for (Required_Document__c doc : documentsOf(app)) {
                requestedDocuments.add(doc.Document_Type__c);
                if (doc.Status__c != DOC_STATUS_VERIFIED) {
                    blockers.add(doc.Document_Type__c + ' is ' + doc.Status__c);
                }
            }
            for (String documentType : requiredDocumentTypes(app.Purpose__c)) {
                if (!requestedDocuments.contains(documentType)) {
                    blockers.add(documentType + ' has not been requested');
                }
            }

            Set<String> reportedChecks = new Set<String>();
            for (Verification_Check__c check : checksOf(app)) {
                reportedChecks.add(check.Check_Type__c);
                if (check.Status__c != CHECK_STATUS_PASSED) {
                    blockers.add(check.Check_Type__c + ' check is ' + check.Status__c);
                }
            }
            for (String checkType : VERIFICATION_CHECK_TYPES) {
                if (!reportedChecks.contains(checkType)) {
                    blockers.add(checkType + ' check has not been run');
                }
            }

            blockersById.put(app.Id, blockers);
        }
        return blockersById;
    }

    // ------------------------------------------------------------------ rules

    @TestVisible
    private static List<String> requiredDocumentTypes(String purpose) {
        List<String> types = new List<String>(BASE_DOCUMENTS);
        if (DOCUMENTS_BY_PURPOSE.containsKey(purpose)) {
            types.addAll(DOCUMENTS_BY_PURPOSE.get(purpose));
        }
        return types;
    }

    @TestVisible
    private static List<String> submissionProblems(Loan_Application__c app) {
        List<String> problems = new List<String>();
        if (app.Status__c != STATUS_DRAFT) {
            problems.add('it is ' + app.Status__c + ', not ' + STATUS_DRAFT);
        }
        if (app.Applicant__c == null) {
            problems.add('applicant is missing');
        }
        if (app.Requested_Amount__c == null) {
            problems.add('requested amount is missing');
        }
        if (app.Term_Months__c == null) {
            problems.add('term is missing');
        }
        if (String.isBlank(app.Purpose__c)) {
            problems.add('purpose is missing');
        }
        if (app.Annual_Revenue__c == null) {
            problems.add('annual revenue is missing');
        }
        return problems;
    }

    private void validateAmountAndTerm(Loan_Application__c app) {
        if (app.Requested_Amount__c != null &&
            (app.Requested_Amount__c <= 0 || app.Requested_Amount__c > MAX_REQUESTED_AMOUNT)) {
            app.Requested_Amount__c.addError(
                error(
                    'Requested amount must be greater than 0 and no more than ' + MAX_REQUESTED_AMOUNT.format() + '.',
                    app,
                    Loan_Application__c.Requested_Amount__c
                )
            );
        }
        if (app.Term_Months__c != null &&
            (app.Term_Months__c < MIN_TERM_MONTHS || app.Term_Months__c > MAX_TERM_MONTHS)) {
            app.Term_Months__c.addError(
                error(
                    'Term must be between ' + MIN_TERM_MONTHS + ' and ' + MAX_TERM_MONTHS + ' months.',
                    app,
                    Loan_Application__c.Term_Months__c
                )
            );
        }
    }

    private void validateStatusTransition(Loan_Application__c app, Loan_Application__c existing) {
        if (existing == null || app.Status__c == existing.Status__c) {
            return;
        }
        Set<String> allowed = ALLOWED_TRANSITIONS.get(existing.Status__c);
        if (allowed == null || !allowed.contains(app.Status__c)) {
            app.Status__c.addError(
                error(
                    'Status cannot change from ' + existing.Status__c + ' to ' + app.Status__c + '.',
                    app,
                    Loan_Application__c.Status__c
                )
            );
        }
    }

    private static void applyRiskScores(List<Loan_Application__c> apps) {
        for (Loan_Application__c app : apps) {
            Integer score = LoanRiskCalculator.score(
                app.Requested_Amount__c,
                app.Annual_Revenue__c,
                app.Years_Trading__c == null ? null : app.Years_Trading__c.intValue(),
                app.Term_Months__c == null ? null : app.Term_Months__c.intValue()
            );
            app.Risk_Score__c = score;
            app.Risk_Rating__c = LoanRiskCalculator.rating(score);
        }
    }

    private void stampStatusDates(Map<Id, SObject> existingRecords) {
        Datetime now = System.now();
        for (Loan_Application__c app : getLoanApplications()) {
            Loan_Application__c existing = (Loan_Application__c) existingRecords.get(app.Id);
            if (existing == null || app.Status__c == existing.Status__c) {
                continue;
            }
            if (app.Status__c == STATUS_SUBMITTED) {
                app.Submitted_Date__c = now;
            } else if (app.Status__c == STATUS_APPROVED || app.Status__c == STATUS_DECLINED) {
                app.Decision_Date__c = now;
            }
        }
    }

    private static void requireStatus(Loan_Application__c app, String expected, String action) {
        if (app.Status__c != expected) {
            throw new LoanApplicationException(
                'Cannot ' + action + ' ' + label(app) + ' while it is ' + app.Status__c + ' (expected ' + expected + ').'
            );
        }
    }

    private static void registerMissingDocuments(Loan_Application__c app, fflib_ISObjectUnitOfWork uow) {
        Set<String> existing = new Set<String>();
        for (Required_Document__c doc : documentsOf(app)) {
            existing.add(doc.Document_Type__c);
        }
        for (String documentType : requiredDocumentTypes(app.Purpose__c)) {
            if (!existing.contains(documentType)) {
                uow.registerNew(
                    new Required_Document__c(Document_Type__c = documentType, Status__c = DOC_STATUS_REQUESTED),
                    Required_Document__c.Loan_Application__c,
                    app
                );
            }
        }
    }

    private static void registerMissingChecks(Loan_Application__c app, fflib_ISObjectUnitOfWork uow) {
        Set<String> existing = new Set<String>();
        for (Verification_Check__c check : checksOf(app)) {
            existing.add(check.Check_Type__c);
        }
        for (String checkType : VERIFICATION_CHECK_TYPES) {
            if (!existing.contains(checkType)) {
                uow.registerNew(
                    new Verification_Check__c(Check_Type__c = checkType, Status__c = CHECK_STATUS_PENDING),
                    Verification_Check__c.Loan_Application__c,
                    app
                );
            }
        }
    }

    private static String label(Loan_Application__c app) {
        return String.isNotBlank(app.Name) ? app.Name : 'Loan application ' + app.Id;
    }

    private static List<Required_Document__c> documentsOf(Loan_Application__c app) {
        return app.Required_Documents__r == null ? new List<Required_Document__c>() : app.Required_Documents__r;
    }

    private static List<Verification_Check__c> checksOf(Loan_Application__c app) {
        return app.Verification_Checks__r == null ? new List<Verification_Check__c>() : app.Verification_Checks__r;
    }

    public class Constructor implements fflib_SObjectDomain.IConstructable {
        public fflib_SObjectDomain construct(List<SObject> records) {
            return new LoanApplications((List<Loan_Application__c>) records);
        }
    }
}
