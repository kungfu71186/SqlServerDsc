ConvertFrom-StringData -StringData @'
    Restart                 = Restarting Reporting Services.
    SuppressRestart         = Suppressing restart of Reporting Services.
    TestFailedAfterSet      = Test-TargetResource function returned false when Set-TargetResource function verified the desired state. This indicates that the Set-TargetResource did not correctly set set the desired state, or that the function Test-TargetResource does not correctly evaluates the desired state.
    NotDesiredPropertyState = Reporting Services setting '{0}' is not correct. Expected '{1}', actual '{2}'
    RSInDesiredState        = Reporting Services '{0}' is in the desired state.
    RSNotInDesiredState     = Reporting Services '{0}' is NOT in the desired state.


    IssueRetrievingCIMInstance = There was an issue when trying to retrieve the CIM instance. This shouldn't have happened. For further diganostics, please ensure that the following command can run `{0}`. (SRS0001)
    IssueRetrievingRSInstance = There was an issue when trying to retrieve the Reporting Services instance name. This is probably due to the fact that Reporting Services may not be installed.  (SRS0002)



    RSSkuTypeNotInitialized       = It appears that the Reporting Services sku type hasn't been defined yet or not found. This should be set to one of the following types: {0}.
    RSSkuTypeIsHigherEdition      = The Reporting services sku type: '{0}' was found to be a HIGHER edition than that of the '{1} Edition'.
    RSSkuTypeIsNotHigherEdition   = The Reporting services sku type: '{0}' was found to be a LOWER edition than that of the '{1} Edition'.
    RSSkuTypeFullNameNotFound     = Could not identify the reporting services edition of '{0}'. This could be that the edition is new and needs to be added to the resource.
    RSandSQLEditionsNotValid      = The database installation of reporting services with the sku type of '{0}' is restricted on the SQL sku type of '{1}'
    RSandSQLEditionsNotValidLocal = The database installation of reporting services with the sku type of '{0}' requires that the SQL instance be installed on the same node. It appears that you are trying to install reporting services on a remote node.

    # Get-TargetResource
    GetRSState = Attempting to get the Reporting Service state

    # Get-RsCimInstance
    RetrievingRSInstanceNameAuto           = Attempting to retrieve the Reporting Service instance name automatically.
    SetRSInstanceName                      = Reporting Service instance name was set to '{0}'.
    RetrievingRSInstanceVersion            = Attempting to retrieve the Reporting Service instance version.
    SetRSInstanceVersion                   = Reporting Service instance version was set to '{0}'.
    RetrievingRSInstanceObject             = Attempting to retrieve the Reporting Service instance object.
    RetrievingRSInstanceObjectSuccess      = The Reporting Services instance object was successfully retrieved.
    RetrievingRSConfigurationObject        = Attempting to retrieve the Reporting Service configuration object.
    RetrievingRSConfigurationObjectSuccess = The Reporting Services configuration object was successfully retrieved.
'@

