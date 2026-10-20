/**
 * Contract for any external verification service (KYC, AML, credit bureau).
 * Callers depend on this interface, never on a concrete provider, so the provider can be
 * swapped (HTTP, a different vendor, a test double) through the Application factory.
 */
public interface IVerificationProvider {
    /**
     * @throws VerificationException with isRetryable() = true for transient failures (5xx, 429, timeouts)
     *         and false for permanent ones (4xx, malformed responses)
     */
    VerificationResult verify(Loan_Application__c application, Verification_Check__c check);
}