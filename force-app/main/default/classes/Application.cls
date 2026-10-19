/**
 * Application factory: the single place that wires interfaces to implementations.
 *
 * Every layer asks this class for its collaborators instead of using `new`, which is
 * what lets unit tests swap in ApexMocks stubs via setMock() without touching the database.
 */
public inherited sharing class Application {
    /** Unit of Work, with SObject types in dependency (insert) order. */
    public static final fflib_Application.UnitOfWorkFactory UnitOfWork = new fflib_Application.UnitOfWorkFactory(
        new List<SObjectType>{
            Account.SObjectType,
            Loan_Application__c.SObjectType,
            Required_Document__c.SObjectType,
            Verification_Check__c.SObjectType
        }
    );

    /** Service interface -> implementation. */
    public static final fflib_Application.ServiceFactory Service = new fflib_Application.ServiceFactory(
        new Map<Type, Type>{ ILoanApplicationService.class => LoanApplicationServiceImpl.class }
    );

    /** SObject -> Selector. */
    public static final fflib_Application.SelectorFactory Selector = new fflib_Application.SelectorFactory(
        new Map<SObjectType, Type>{ Loan_Application__c.SObjectType => LoanApplicationsSelector.class }
    );

    /** SObject -> Domain constructor. */
    public static final fflib_Application.DomainFactory Domain = new fflib_Application.DomainFactory(
        Application.Selector,
        new Map<SObjectType, Type>{ Loan_Application__c.SObjectType => LoanApplications.Constructor.class }
    );
}
