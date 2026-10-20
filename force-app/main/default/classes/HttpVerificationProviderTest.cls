@IsTest
private class HttpVerificationProviderTest {
    private class MockResponse implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        private Boolean throwTimeout = false;

        MockResponse(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            if (throwTimeout) {
                throw new CalloutException('Read timed out');
            }
            Assert.areEqual('POST', request.getMethod(), 'Provider should POST');
            Assert.isTrue(request.getBody().contains('"checkType":"KYC"'), 'Body should name the check type');
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    private static Loan_Application__c application() {
        return new Loan_Application__c(
            Id = fflib_IDGenerator.generate(Loan_Application__c.SObjectType),
            Applicant__c = fflib_IDGenerator.generate(Account.SObjectType),
            Requested_Amount__c = 100000,
            Annual_Revenue__c = 500000
        );
    }

    private static Verification_Check__c kycCheck() {
        return new Verification_Check__c(Check_Type__c = 'KYC', Status__c = 'Pending');
    }

    private static VerificationException verifyExpectingFailure() {
        try {
            new HttpVerificationProvider().verify(application(), kycCheck());
        } catch (VerificationException e) {
            return e;
        }
        Assert.fail('Expected a VerificationException');
        return null;
    }

    @IsTest
    static void successfulResponseIsParsed() {
        Test.setMock(
            HttpCalloutMock.class,
            new MockResponse(200, '{"status":"Passed","score":720,"summary":"Identity confirmed","reference":"KYC-1"}')
        );

        VerificationResult result = new HttpVerificationProvider().verify(application(), kycCheck());

        Assert.areEqual('Passed', result.status, 'Status should be parsed');
        Assert.areEqual(720, result.score, 'Score should be parsed');
        Assert.areEqual('Identity confirmed', result.summary, 'Summary should be parsed');
        Assert.areEqual('KYC-1', result.reference, 'Reference should be parsed');
        Assert.areEqual(200, result.statusCode, 'HTTP status should be kept for the log');
        Assert.isNotNull(result.durationMs, 'Duration should be measured');
    }

    @IsTest
    static void serverErrorsAreRetryable() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(503, 'Service Unavailable'));

        VerificationException e = verifyExpectingFailure();

        Assert.isTrue(e.isRetryable(), '5xx should be retryable');
        Assert.areEqual(503, e.statusCode, 'Status code should be carried');
    }

    @IsTest
    static void rateLimitIsRetryable() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(429, 'Too Many Requests'));

        Assert.isTrue(verifyExpectingFailure().isRetryable(), '429 should be retryable');
    }

    @IsTest
    static void timeoutsAreRetryable() {
        MockResponse mock = new MockResponse(200, '');
        mock.throwTimeout = true;
        Test.setMock(HttpCalloutMock.class, mock);

        VerificationException e = verifyExpectingFailure();

        Assert.isTrue(e.isRetryable(), 'Timeouts should be retryable');
        Assert.isTrue(e.getMessage().contains('Read timed out'), e.getMessage());
    }

    @IsTest
    static void clientErrorsArePermanent() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(400, '{"error":"bad request"}'));

        VerificationException e = verifyExpectingFailure();

        Assert.isFalse(e.isRetryable(), '4xx should not be retried');
        Assert.areEqual('{"error":"bad request"}', e.responseBody, 'Body should be kept for the log');
    }

    @IsTest
    static void malformedJsonIsPermanent() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, 'not json'));

        Assert.isFalse(verifyExpectingFailure().isRetryable(), 'Bad JSON should not be retried');
    }

    @IsTest
    static void unknownStatusIsPermanent() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, '{"status":"Maybe"}'));

        VerificationException e = verifyExpectingFailure();

        Assert.isFalse(e.isRetryable(), 'Unknown status should not be retried');
        Assert.isTrue(e.getMessage().contains('Maybe'), e.getMessage());
    }
}