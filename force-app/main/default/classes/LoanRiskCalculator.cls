/**
 * Deterministic, explainable risk scoring for SME loan applications.
 *
 * Kept as a pure class (no SOQL, no DML, no SObjects) so the rules are trivial to unit test
 * and so the same logic can later be exposed to an Agentforce action that explains a score.
 *
 * Score is 0-100; higher means riskier.
 */
public inherited sharing class LoanRiskCalculator {
    public static final Integer BASE_SCORE = 50;
    public static final Integer LOW_MAX = 35;
    public static final Integer MEDIUM_MAX = 65;

    public static final String RATING_LOW = 'Low';
    public static final String RATING_MEDIUM = 'Medium';
    public static final String RATING_HIGH = 'High';

    /**
     * @param requestedAmount loan amount requested
     * @param annualRevenue   applicant's annual revenue (null or zero treated as unknown = high risk)
     * @param yearsTrading    years the business has traded (null treated as start-up)
     * @param termMonths      requested term in months
     * @return score clamped to 0-100, or null when there is no amount to score yet
     */
    public static Integer score(Decimal requestedAmount, Decimal annualRevenue, Integer yearsTrading, Integer termMonths) {
        if (requestedAmount == null || requestedAmount <= 0) {
            return null;
        }

        Integer score = BASE_SCORE;
        score += loanToRevenueAdjustment(requestedAmount, annualRevenue);
        score += tradingHistoryAdjustment(yearsTrading);
        score += termAdjustment(termMonths);

        return Math.max(0, Math.min(100, score));
    }

    public static String rating(Integer score) {
        if (score == null) {
            return null;
        }
        if (score <= LOW_MAX) {
            return RATING_LOW;
        }
        return score <= MEDIUM_MAX ? RATING_MEDIUM : RATING_HIGH;
    }

    @TestVisible
    private static Integer loanToRevenueAdjustment(Decimal requestedAmount, Decimal annualRevenue) {
        if (annualRevenue == null || annualRevenue <= 0) {
            return 30;
        }
        Decimal ratio = requestedAmount / annualRevenue;
        if (ratio <= 0.25) {
            return -20;
        }
        if (ratio <= 0.5) {
            return -10;
        }
        if (ratio <= 1) {
            return 0;
        }
        return ratio <= 2 ? 15 : 30;
    }

    @TestVisible
    private static Integer tradingHistoryAdjustment(Integer yearsTrading) {
        if (yearsTrading == null || yearsTrading < 2) {
            return 20;
        }
        if (yearsTrading < 5) {
            return 5;
        }
        return yearsTrading >= 10 ? -10 : 0;
    }

    @TestVisible
    private static Integer termAdjustment(Integer termMonths) {
        return termMonths != null && termMonths > 120 ? 5 : 0;
    }
}
