/**
 * Public entry point for loan application use cases. Callers (LWC controllers, Flows,
 * Agentforce actions, REST resources) use these static methods; the implementation is
 * resolved through the Application factory so it can be mocked in tests.
 */
public inherited sharing class LoanApplicationService {
    public static void submit(Set<Id> applicationIds) {
        service().submit(applicationIds);
    }

    public static void startReview(Set<Id> applicationIds) {
        service().startReview(applicationIds);
    }

    public static void recordDecision(Id applicationId, Boolean approve, String notes) {
        service().recordDecision(applicationId, approve, notes);
    }

    public static List<String> getApprovalBlockers(Id applicationId) {
        return service().getApprovalBlockers(applicationId);
    }

    private static ILoanApplicationService service() {
        return (ILoanApplicationService) Application.Service.newInstance(ILoanApplicationService.class);
    }
}
