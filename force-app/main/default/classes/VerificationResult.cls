/**
 * Result of a successful verification call, plus the HTTP details needed for the Integration Log.
 */
public inherited sharing class VerificationResult {
    public String status;      // Passed or Failed
    public Integer score;
    public String summary;
    public String reference;   // provider's own Id, stored in Provider_Reference__c

    public String endpoint;
    public Integer statusCode;
    public String requestBody;
    public String responseBody;
    public Long durationMs;
}