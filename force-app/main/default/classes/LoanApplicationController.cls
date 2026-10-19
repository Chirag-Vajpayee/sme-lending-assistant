/**
 * Thin @AuraEnabled boundary for Lightning components and quick actions.
 * Converts business exceptions into AuraHandledException so the UI shows the real message.
 */
public with sharing class LoanApplicationController {
    @AuraEnabled
    public static void submitApplication(Id applicationId) {
        try {
            LoanApplicationService.submit(new Set<Id>{ applicationId });
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void startReview(Id applicationId) {
        try {
            LoanApplicationService.startReview(new Set<Id>{ applicationId });
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void recordDecision(Id applicationId, Boolean approve, String notes) {
        try {
            LoanApplicationService.recordDecision(applicationId, approve, notes);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getApprovalBlockers(Id applicationId) {
        try {
            return LoanApplicationService.getApprovalBlockers(applicationId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @TestVisible
    private static AuraHandledException toAuraException(Exception e) {
        String message = e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage();
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}
