ConvertFrom-StringData @'
    Restart                 = Restarting Reporting Services.
    SuppressRestart         = Suppressing restart of Reporting Services.
    TestFailedAfterSet      = Test-TargetResource function returned false when Set-TargetResource function verified the desired state. This indicates that the Set-TargetResource did not correctly set set the desired state, or that the function Test-TargetResource does not correctly evaluates the desired state.
    NotDesiredPropertyState = Reporting Services setting '{0}' is not correct. Expected '{1}', actual '{2}'
    RSInDesiredState        = Reporting Services '{0}' is in the desired state.
    RSNotInDesiredState     = Reporting Services '{0}' is NOT in the desired state.
'@
