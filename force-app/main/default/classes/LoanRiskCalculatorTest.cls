@IsTest
private class LoanRiskCalculatorTest {
    @IsTest
    static void establishedBusinessWithSmallLoanIsLowRisk() {
        // ratio 0.2 (-20), 12 years trading (-10), 60 months (0): 50 - 30 = 20
        Integer score = LoanRiskCalculator.score(100000, 500000, 12, 60);

        Assert.areEqual(20, score);
        Assert.areEqual(LoanRiskCalculator.RATING_LOW, LoanRiskCalculator.rating(score));
    }

    @IsTest
    static void startUpBorrowingMoreThanRevenueIsHighRisk() {
        // ratio 3 (+30), 1 year trading (+20), 180 months (+5): 50 + 55 = 105, clamped to 100
        Integer score = LoanRiskCalculator.score(300000, 100000, 1, 180);

        Assert.areEqual(100, score);
        Assert.areEqual(LoanRiskCalculator.RATING_HIGH, LoanRiskCalculator.rating(score));
    }

    @IsTest
    static void midRangeProfileIsMediumRisk() {
        // ratio 0.8 (0), 3 years trading (+5), 36 months (0): 55
        Integer score = LoanRiskCalculator.score(80000, 100000, 3, 36);

        Assert.areEqual(55, score);
        Assert.areEqual(LoanRiskCalculator.RATING_MEDIUM, LoanRiskCalculator.rating(score));
    }

    @IsTest
    static void unknownRevenueAndHistoryAreTreatedAsRisky() {
        Assert.areEqual(30, LoanRiskCalculator.loanToRevenueAdjustment(50000, null));
        Assert.areEqual(30, LoanRiskCalculator.loanToRevenueAdjustment(50000, 0));
        Assert.areEqual(20, LoanRiskCalculator.tradingHistoryAdjustment(null));
    }

    @IsTest
    static void loanToRevenueBandsAreApplied() {
        Assert.areEqual(-20, LoanRiskCalculator.loanToRevenueAdjustment(25, 100));
        Assert.areEqual(-10, LoanRiskCalculator.loanToRevenueAdjustment(50, 100));
        Assert.areEqual(0, LoanRiskCalculator.loanToRevenueAdjustment(100, 100));
        Assert.areEqual(15, LoanRiskCalculator.loanToRevenueAdjustment(200, 100));
        Assert.areEqual(30, LoanRiskCalculator.loanToRevenueAdjustment(201, 100));
    }

    @IsTest
    static void tradingHistoryAndTermBandsAreApplied() {
        Assert.areEqual(5, LoanRiskCalculator.tradingHistoryAdjustment(4));
        Assert.areEqual(0, LoanRiskCalculator.tradingHistoryAdjustment(9));
        Assert.areEqual(-10, LoanRiskCalculator.tradingHistoryAdjustment(10));
        Assert.areEqual(0, LoanRiskCalculator.termAdjustment(120));
        Assert.areEqual(5, LoanRiskCalculator.termAdjustment(121));
        Assert.areEqual(0, LoanRiskCalculator.termAdjustment(null));
    }

    @IsTest
    static void noAmountMeansNoScore() {
        Assert.isNull(LoanRiskCalculator.score(null, 100000, 5, 60));
        Assert.isNull(LoanRiskCalculator.score(0, 100000, 5, 60));
        Assert.isNull(LoanRiskCalculator.rating(null));
    }

    @IsTest
    static void ratingBoundaries() {
        Assert.areEqual(LoanRiskCalculator.RATING_LOW, LoanRiskCalculator.rating(35));
        Assert.areEqual(LoanRiskCalculator.RATING_MEDIUM, LoanRiskCalculator.rating(36));
        Assert.areEqual(LoanRiskCalculator.RATING_MEDIUM, LoanRiskCalculator.rating(65));
        Assert.areEqual(LoanRiskCalculator.RATING_HIGH, LoanRiskCalculator.rating(66));
    }
}
