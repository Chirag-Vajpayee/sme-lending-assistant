public interface ILoanApplicationService {
    void submit(Set<Id> applicationIds);
    void startReview(Set<Id> applicationIds);
    void recordDecision(Id applicationId, Boolean approve, String notes);
    List<String> getApprovalBlockers(Id applicationId);
}
