/**
 * Calls the external verification API through the Verification_API Named Credential.
 * Classifies failures so the caller can retry transient ones and dead-letter permanent ones.
 */
public inherited sharing class HttpVerificationProvider implements IVerificationProvider {
    @TestVisible
    private static final String ENDPOINT = 'callout:Verification_API/verify';
    private static final Integer TIMEOUT_MS = 20000;
    private static final Set<String> VALID_STATUSES = new Set<String>{ 'Passed', 'Failed' };

    public VerificationResult verify(Loan_Application__c application, Verification_Check__c check) {
        VerificationResult result = new VerificationResult();
        result.endpoint = ENDPOINT;
        result.requestBody = JSON.serialize(
            new Map<String, Object>{
                'checkType' => check.Check_Type__c,
                'applicationId' => application.Id,
                'applicantId' => application.Applicant__c,
                'requestedAmount' => application.Requested_Amount__c,
                'annualRevenue' => application.Annual_Revenue__c
            }
        );

        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(TIMEOUT_MS);
        request.setBody(result.requestBody);

        Long started = System.currentTimeMillis();
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (CalloutException e) {
            // Timeouts and connection failures are transient.
            throw VerificationException.retryable('Callout failed: ' + e.getMessage(), null, null);
        }
        result.durationMs = System.currentTimeMillis() - started;
        result.statusCode = response.getStatusCode();
        result.responseBody = response.getBody();

        if (result.statusCode == 429 || result.statusCode >= 500) {
            throw VerificationException.retryable(
                'Provider unavailable (HTTP ' + result.statusCode + ')',
                result.statusCode,
                result.responseBody
            );
        }
        if (result.statusCode >= 400) {
            throw VerificationException.permanent(
                'Provider rejected the request (HTTP ' + result.statusCode + ')',
                result.statusCode,
                result.responseBody
            );
        }

        parseBody(result);
        return result;
    }

    private static void parseBody(VerificationResult result) {
        Map<String, Object> body;
        try {
            body = (Map<String, Object>) JSON.deserializeUntyped(result.responseBody);
        } catch (Exception e) {
            throw VerificationException.permanent('Response was not valid JSON', result.statusCode, result.responseBody);
        }

        result.status = (String) body.get('status');
        if (!VALID_STATUSES.contains(result.status)) {
            throw VerificationException.permanent(
                'Unexpected status "' + result.status + '" from provider',
                result.statusCode,
                result.responseBody
            );
        }
        result.score = body.get('score') == null ? null : Integer.valueOf(body.get('score'));
        result.summary = (String) body.get('summary');
        result.reference = (String) body.get('reference');
    }
}