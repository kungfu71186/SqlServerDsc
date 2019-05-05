ConvertFrom-StringData @'
    Restart                 = Restarting Reporting Services.
    SuppressRestart         = Suppressing restart of Reporting Services.
    TestFailedAfterSet      = Test-TargetResource function returned false when Set-TargetResource function verified the desired state. This indicates that the Set-TargetResource did not correctly set set the desired state, or that the function Test-TargetResource does not correctly evaluates the desired state.
    NotDesiredPropertyState = Reporting Services setting '{0}' is not correct. Expected '{1}', actual '{2}'
    RSInDesiredState        = Reporting Services '{0}' is in the desired state.
    RSNotInDesiredState     = Reporting Services '{0}' is NOT in the desired state.

    RSSkuTypeNotInitialized = It appears that the Reporting Services sku type hasn't been defined yet or not found. This should be set to one of the following types: {0}.
    RSSkuTypeIsHigherEdition  = The Reporting services sku type: '{0}' was found to be a HIGHER edition than that of the '{1} Edition'.
    RSSkuTypeIsNotHigherEdition  = The Reporting services sku type: '{0}' was found to be a LOWER edition than that of the '{1} Edition'.
    RSSkuTypeFullNameNotFound  = Could not identify the reporting services edition of '{0}'. This could be that the edition is new and needs to be added to the resource.
    RSandSQLEditionsNotValid  = The database installation of reporting services with the sku type of '{0}' is restricted on the SQL sku type of '{1}'
    RSandSQLEditionsNotValidLocal  = The database installation of reporting services with the sku type of '{0}' requires that the SQL instance be installed on the same node. It appears that you are trying to install reporting services on a remote node.
'@
