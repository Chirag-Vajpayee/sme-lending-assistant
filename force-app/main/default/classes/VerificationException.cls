/**
 * Raised by a provider when verification could not be completed.
 * The retryable flag lets the caller decide between retry-with-backoff and dead-lettering.
 */
public inherited sharing class VerificationException extends Exception {
    private Boolean retryable = false;
    public Integer statusCode;
    public String responseBody;

    public Boolean isRetryable() {
        return retryable;
    }

    public static VerificationException retryable(String message, Integer statusCode, String responseBody) {
        return build(message, true, statusCode, responseBody);
    }

    public static VerificationException permanent(String message, Integer statusCode, String responseBody) {
        return build(message, false, statusCode, responseBody);
    }

    private static VerificationException build(String message, Boolean retryable, Integer statusCode, String responseBody) {
        VerificationException e = new VerificationException(message);
        e.retryable = retryable;
        e.statusCode = statusCode;
        e.responseBody = responseBody;
        return e;
    }
}