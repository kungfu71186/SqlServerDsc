ConvertFrom-StringData -StringData @'
    # Multiple (SRS{n}000) - These messages can be used for all areas in the script.
    # The 1000's decimal will say where the error came from [get (1),set (2),test (3), compare (4)]
    IssueRetrievingCIMInstance = There was an issue when trying to retrieve the CIM instance. This shouldn't have happened. For further diganostics, please ensure that the following command can run `{0}`. (SRS{1}001)
    IssueRetrievingRSInstance  = There was an issue when trying to retrieve the Reporting Services instance name. This is probably due to the fact that Reporting Services may not be installed. (SRS{1}002)
    IssueRetrievingRSVersion   = There was an issue when trying to retrieve the Reporting Services version. This is probably due to the fact that the 'ReportServiceInstanceName' name of '{0}' is incorrect. (SRS{1}003)

    # Get-TargetResource (SRS0100)
    RetrievingRSState                = Attempting to get the current Reporting Service state. (SRS0100)
    RetrievingInstanceUrls           = Attempting to get the Reporting Service Instance Url list. (SRS0101)
    RetrievingInstanceUrlsSuccess    = Successfully retrieved the Reporting Service Instance Url list. (SRS0102)
    RetrievingModifiableUrls         = Attempting to get the Reporting Service Modifiable Url list. (SRS0103)
    RetrievingModifiableUrlsSuccess  = Successfully retrieved the Reporting Service Modifiable Url list. (SRS0104)
    RetrievingScaleOutServers        = Attempting to get a list of the Reporting Service Scale-Out servers. (SRS0104)
    RetrievingScaleOutServersSuccess = Successfully retrieved the list of Reporting Service Scale-Out servers. (SRS0105)
    RetrivedServiceAccount           = Retrieved the service account of '{0}', which is a '{1}' logon type. (SRS0106)

    # Test-TargetResource (SRS0200)
    TestingDesiredState = Testing if the Reporting Services instance of '{0}' is in desired state (SRS0200)
    RSInDesiredState    = Reporting Services '{0}' is in the desired state. (SRS0201)
    RSNotInDesiredState = Reporting Services '{0}' is NOT in the desired state. (SRS0202)

    # Set-TargetResource (SRS0300)
    SettingNonDesiredStateParameters = Attempting to set all parameters that are not in desired state for the instance '{0}'. (SRS0300)

    # Compare-TargetResourceState (SRS0400)
    ComparingSpecifiedParameters = Comparing all the parameters specified for the instance '{0}'. (SRS0400)
    CheckingParameterState       = Checking if the parameter '{0}' is in desired state. (SRS0401)
    ParameterNotInDesiredState   = The parameter '{0}' was found to NOT be in the correct desired state. Expected: '{1}', Actual '{2}'. (SRS0402)
    ParameterInDesiredState      = The parameter '{0}' was found to be the correct desired state. Expected: '{1}',        Actual '{2}'. (SRS0403)

    # (SRS9000) will be used for anything else
    # Get-RsCimInstance
    RetrievingRSInstanceNameAuto           = Attempting to retrieve the Reporting Service instance name automatically. (SRS9000)
    SetRSInstanceName                      = Reporting Service instance name was set to '{0}'. (SRS9001)
    RetrievingRSInstanceVersion            = Attempting to retrieve the Reporting Service instance version. (SRS9002)
    SetRSInstanceVersion                   = Reporting Service instance version was set to '{0}'. (SRS9003)
    RetrievingRSInstanceObject             = Attempting to retrieve the Reporting Service instance object. (SRS9004)
    RetrievingRSInstanceObjectSuccess      = The Reporting Services instance object was successfully retrieved. (SRS9005)
    RetrievingRSConfigurationObject        = Attempting to retrieve the Reporting Service configuration object. (SRS9006)
    RetrievingRSConfigurationObjectSuccess = The Reporting Services configuration object was successfully retrieved. (SRS9007)

    # MSFT_ReportServiceSkuUtils (SRS0600)
    RSSkuTypeNotInitialized       = It appears that the Reporting Services sku type hasn't been defined yet or not found. This should be set to one of the following types: {0}. (SRS0600)
    RSSkuTypeIsHigherEdition      = The Reporting services sku type: '{0}' was found to be a HIGHER edition than that of the '{1} Edition'. (SRS0601)
    RSSkuTypeIsNotHigherEdition   = The Reporting services sku type: '{0}' was found to be a LOWER edition than that of the '{1} Edition'. (SRS0602)
    RSSkuTypeFullNameNotFound     = Could not identify the reporting services edition of '{0}'. This could be that the edition is new and needs to be added to the resource. (SRS0603)
    RSandSQLEditionsNotValid      = The database installation of reporting services with the sku type of '{0}' is restricted on the SQL sku type of '{1}' (SRS0604)
    RSandSQLEditionsNotValidLocal = The database installation of reporting services with the sku type of '{0}' requires that the SQL instance be installed on the same node. It appears that you are trying to install reporting services on a remote node. (SRS0605)

'@

