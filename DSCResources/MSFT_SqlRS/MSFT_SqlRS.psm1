$script:resourceModulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$script:modulesFolderPath = Join-Path -Path $script:resourceModulePath -ChildPath 'Modules'

$script:localizationModulePath = Join-Path -Path $script:modulesFolderPath -ChildPath 'DscResource.LocalizationHelper'
Import-Module -Name (Join-Path -Path $script:localizationModulePath -ChildPath 'DscResource.LocalizationHelper.psm1')

$script:resourceHelperModulePath = Join-Path -Path $script:modulesFolderPath -ChildPath 'DscResource.Common'
Import-Module -Name (Join-Path -Path $script:resourceHelperModulePath -ChildPath 'DscResource.Common.psm1')

$script:localizedData = Get-LocalizedData -ResourceName 'MSFT_SqlRS'

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'MSFT_ReportServiceSkuUtils.psm1')

enum ReportServiceInstance
{
    PBIRS
    SSRS
}

enum EmailAuthenticationType
{
    None
    Windows
    Service
}

enum ReportDatabaseLogonType
{
    Service
    SQL
    Windows
}

enum DatabaseConnectLogonType
{
    Integrated
    SQL
}

enum ReportServiceAccount
{
    Virtual
    Network
    System
    Local
    Windows
}

$databaseLogonType = @(
    [PSCustomObject]@{
        ShortName = [ReportDatabaseLogonType]::Service
        FullName = 'Service Credentials (Integrated)'
        Id = 0
    }
    [PSCustomObject]@{
        ShortName = [ReportDatabaseLogonType]::SQL
        FullName = 'SQL Service Credentials'
        Id = 1
    }
    [PSCustomObject] @{
        ShortName = [ReportDatabaseLogonType]::Windows
        FullName = 'Windows Credentials'
        Id = 2
    }
)

$smtpLogonType = @(
    [PSCustomObject]@{
        ShortName = [EmailAuthenticationType]::None
        FullName = 'No Authentication'
        Id = 0
    }
    [PSCustomObject]@{
        ShortName = [EmailAuthenticationType]::Windows
        FullName = 'Username and password (Basic)'
        Id = 1
    }
    [PSCustomObject] @{
        ShortName = [EmailAuthenticationType]::Service
        FullName = 'Report service service account (NTLM)'
        Id = 2
    }
)

Function Get-TargetResource #Complete
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory)]
        [ReportServiceInstance]
        $ReportServiceInstanceName
    )

    Write-Verbose -Message ($script:localizedData.RetrievingRSState)
    $reportingServicesCIMObjects = Get-ReportingServicesCIM -ReportServiceInstanceName $ReportServiceInstanceName

    # Instance object is the actual SSRS/PBIRS Instance. Some information in here that is useful
    $instanceCIMObject      = $reportingServicesCIMObjects.InstanceCIM
    # Most of the configuration settings are retrieved from here
    $configurationCIMObject = $reportingServicesCIMObjects.ConfigurationCIM

    $getTargetResourceResult = [ordered]@{
        ReportServiceInstanceName         = $ReportServiceInstanceName

        # Service Account
        ServiceAccount           = $null
        ServiceAccountLogonType  = $null
        ServiceAccountConfigured = $configurationCIMObject.WindowsServiceIdentityConfigured
        ServiceAccountActual     = $configurationCIMObject.WindowsServiceIdentityActual

        # Report Server manager
        ReportManagerVirtualDirectory     = $configurationCIMObject.VirtualDirectoryReportManager
        ReportManagerUrls                 = @()
        ReportServerInstanceURLs          = @()

        # Report Server Web portal
        ReportWebPortalVirtualDirectory   = $configurationCIMObject.VirtualDirectoryReportServer
        ReportWebPortalUrls               = @()
        ReportServerInstanceWebPortalURLs = @()

        # Report Server Database information
        DatabaseServerInstance   = $configurationCIMObject.DatabaseServerName
        DatabaseName             = $configurationCIMObject.DatabaseName
        ReportDatabaseCredential = $configurationCIMObject.DatabaseLogonAccount
        ReportDatabaseLogonType  = $null

        # Email Settings
        EmailSender         = $configurationCIMObject.SenderEmailAddress
        EmailSMTP           = $configurationCIMObject.SMTPServer
        EmailAuthentication = $null
        EmailSMTPCredential = $configurationCIMObject.SendUserName
        EmailSMTPSSL        = $configurationCIMObject.SMTPUseSSL

        # Execution and FileShare account
        ExecutionAccount = $configurationCIMObject.UnattendedExecutionAccount
        FileShareAccount = $configurationCIMObject.FileShareAccount

        # Additional information
        EditionName            = $instanceCIMObject.EditionName
        ScaleOutServers        = @()
        IsInitialized          = $configurationCIMObject.IsInitialized
        Version                = $instanceCIMObject.Version
        InstallationID         = $configurationCIMObject.InstallationID
        ReportServerConfigPath = $configurationCIMObject.PathName
        ServiceName            = $configurationCIMObject.ServiceName
    }

    #region Convert Report Database Logon Type from int to shortname
    $reportDatabaseLogonType = $databaseLogonType | Where-Object -Filter {
        $_.Id -eq $configurationCIMObject.DatabaseLogonType
    }

    $getTargetResourceResult['ReportDatabaseLogonType'] = $reportDatabaseLogonType.ShortName
    #endregion Convert Report Database Logon Type from int to shortname

    #region Convert SMTP Authentication from int to shortname
    $reportSMTPLoginType = $smtpLogonType | Where-Object -Filter {
        $_.Id -eq $configurationCIMObject.SMTPAuthenticate
    }

    $getTargetResourceResult['EmailAuthentication'] = $reportSMTPLoginType.ShortName
    #endregion Convert SMTP Authentication from int to shortname

    #region Convert service account to the keyword this resource uses
    $possibleBuiltinAccounts = @{
        [ReportServiceAccount]::Virtual = 'NT Service\{0}' -f $configurationCIMObject.ServiceName
        [ReportServiceAccount]::Network = 'NT AUTHORITY\NetworkService'
        [ReportServiceAccount]::System  = 'NT AUTHORITY\SYSTEM'
        [ReportServiceAccount]::Local   = 'NT AUTHORITY\LocalService'
    }

    $serviceAccountResult = $possibleBuiltinAccounts.GetEnumerator() | Where-Object -Filter {
        $_.Value -eq $configurationCIMObject.WindowsServiceIdentityConfigured
    }

    # If we don't find the account, then we just set it to a windows account
    # This should be fine, since we are just trying to make it easier when
    # assigning an account instead. All other accounts are windows accounts
    # unless we later define it in [ReportServiceAccount]
    if (-not $serviceAccountResult)
    {
        $getTargetResourceResult['ServiceAccount'] = $configurationCIMObject.WindowsServiceIdentityConfigured
        $getTargetResourceResult['ServiceAccountLogonType'] = [ReportServiceAccount]::Windows
        Write-Verbose -Message (
            $script:localizedData.RetrivedServiceAccount -f
                $configurationCIMObject.WindowsServiceIdentityConfigured,
                [ReportServiceAccount]::Windows
        )
    }
    else
    {
        $getTargetResourceResult['ServiceAccount'] = $configurationCIMObject.WindowsServiceIdentityConfigured
        $getTargetResourceResult['ServiceAccountLogonType'] = $serviceAccountResult.Name
        Write-Verbose -Message (
            $script:localizedData.RetrivedServiceAccount -f
                $serviceAccountResult.Value,
                $serviceAccountResult.Name
        )
    }

    #endregion Convert service account to the keyword this resource uses

    #region Get Report Server Manager and Web Portal Urls
    # This will retrieve the readable urls which can be used to browse to
    $invokeRsCimMethodParameters = @{
        CimInstance = $instanceCIMObject
        MethodName = 'GetReportServerUrls'
    }

    Write-Verbose -Message ($script:localizedData.RetrievingInstanceUrls)
    $reportServerUrlsResult = Invoke-RsCimMethod @invokeRsCimMethodParameters
    if ($reportServerUrlsResult.Error)
    {
        $arguments = Convert-HashtableToArguments $cimReportServicesParameters
        $errorMessage = $script:localizedData.IssueRetrievingCIMInstance -f ("Get-CimInstance $arguments", 1)
        New-InvalidResultException -Message $errorMessage -ErrorRecord ($instanceNameResult.Result)
    }
    else
    {
        Write-Verbose -Message ($script:localizedData.RetrievingInstanceUrlsSuccess)

        $reportServerUrls = $reportServerUrlsResult.Result
        # Because GetReportServerUrls returns all urls for all web services, we need to match up
        # which urls belong to ReportServerWebService and ReportServerWebApp
        $reportServeUrlList = @{}

        for ( $i = 0; $i -lt $reportServerUrls.ApplicationName.Count; ++$i )
        {
            $application = ($reportServerUrls.ApplicationName)[$i]
            $url = ($reportServerUrls.URLS)[$i]
            $reportServeUrlList[$application] += @($url)
        }

        $getTargetResourceResult['ReportServerInstanceURLs'] = $reportServeUrlList.ReportServerWebService
        $getTargetResourceResult['ReportServerInstanceWebPortalURLs'] = $reportServeUrlList.ReportServerWebApp
    }
    #endregion Get Report Server Manager Urls

    #region Get Report Server Manager and Web Portal Urls that are modifiable
    $invokeRsCimMethodParameters = @{
        CimInstance = $configurationCIMObject
        MethodName = 'ListReservedURLs'
    }

    Write-Verbose -Message ($script:localizedData.RetrievingModifiableUrls)
    $reportServerUrlsResult = Invoke-RsCimMethod @invokeRsCimMethodParameters
    if ($reportServerUrlsResult.Error)
    {
        $arguments = Convert-HashtableToArguments $cimReportServicesParameters
        $errorMessage = $script:localizedData.IssueRetrievingCIMInstance -f ("Get-CimInstance $arguments", 1)
        New-InvalidResultException -Message $errorMessage -ErrorRecord ($instanceNameResult.Result)
    }
    else
    {
        Write-Verbose -Message ($script:localizedData.RetrievingModifiableUrlsSuccess)

        $reportServerUrls = $reportServerUrlsResult.Result
        # Because GetReportServerUrls returns all urls for all web services, we need to match up
        # which urls belong to ReportServerWebService and ReportServerWebApp
        $reportServeUrlList = @{}

        for ( $i = 0; $i -lt $reportServerUrls.Application.Count; ++$i )
        {
            $application = ($reportServerUrls.Application)[$i]
            $url = ($reportServerUrls.UrlString)[$i]
            $reportServeUrlList[$application] += @($url)
        }

        $getTargetResourceResult['ReportManagerUrls'] = $reportServeUrlList.ReportServerWebService
        $getTargetResourceResult['ReportWebPortalUrls'] = $reportServeUrlList.ReportServerWebApp
    }
    #endregion Get Report Server Manager and Web Portal Urls that are modifiable

    #region Get list of servers in cluster
    $scaleOutServersParameters = @{
        CimInstance = $configurationCIMObject
        MethodName = 'ListReportServersInDatabase'
    }

    Write-Verbose -Message ($script:localizedData.RetrievingScaleOutServers)
    $reportServerUrlsResult = Invoke-RsCimMethod @scaleOutServersParameters
    if ($reportServerUrlsResult.Error)
    {
        $arguments = Convert-HashtableToArguments $cimReportServicesParameters
        $errorMessage = $script:localizedData.IssueRetrievingCIMInstance -f (
            "Get-CimInstance $arguments", 1
        )
        New-InvalidResultException -Message $errorMessage -ErrorRecord ($instanceNameResult.Result)
    }
    else
    {
        Write-Verbose -Message ($script:localizedData.RetrievingScaleOutServersSuccess)
        $getTargetResourceResult['ScaleOutServers'] =  $scaleOutServersResult.Result.MachineNames
    }
    #endregion Get list of servers in cluster

    return $getTargetResourceResult
}

Function Test-TargetResource #Complete
{
    [CmdletBinding()]
    param
    (
         [Parameter(Mandatory = $true)]
        [ReportServiceInstance]
        $ReportServiceInstanceName,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ServiceAccount,

        [Parameter()]
        [ReportServiceAccount]
        $ServiceAccountLogonType = [ReportServiceAccount]::Virtual,

        [Parameter()]
        [System.String]
        $ReportManagerVirtualDirectory = 'ReportServer',

        [Parameter()]
        [System.String[]]
        $ReportManagerUrls = @('http://+:80'),

        [Parameter()]
        [System.String]
        $ReportWebPortalVirtualDirectory = 'Reports',

        [Parameter()]
        [System.String[]]
        $ReportWebPortalUrls = @('http://+:80'),

        [Parameter()]
        [System.String]
        $DatabaseServerInstance = $env:Computername,

        [Parameter()]
        [System.String]
        $DatabaseName = 'ReportServer',

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ReportDatabaseCredential,

        [Parameter()]
        [ReportDatabaseLogonType]
        $ReportDatabaseLogonType = [ReportDatabaseLogonType]::Service,

        [Parameter()]
        [System.String]
        $EmailSender,

        [Parameter()]
        [System.String]
        $EmailSMTP,

        [Parameter()]
        [EmailAuthenticationType]
        $EmailAuthentication = [EmailAuthenticationType]::None,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $EmailSMTPCredential,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ExecutionAccount,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $FileShareAccount,

        [Parameter()]
        [DatabaseConnectLogonType]
        $DatabaseConnectLogonType = [DatabaseConnectLogonType]::Integrated,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $DatabaseConnectCredential,

        [Parameter()]
        [System.Boolean]
        $UseServiceWithRemoteDatabase = $false
    )

    Write-Verbose -Message ($LocalizedData.TestingDesiredState -f $ReportServiceInstanceName)

    $compareParameters = @{} + $PSBoundParameters
    # Need to set these parameters to compare if users are using the default parameter values
    $compareParameters['ServiceAccountLogonType']         = $ServiceAccountLogonType
    $compareParameters['ReportManagerVirtualDirectory']   = $ReportManagerVirtualDirectory
    $compareParameters['ReportManagerUrls']               = $ReportManagerUrls
    $compareParameters['ReportWebPortalVirtualDirectory'] = $ReportWebPortalVirtualDirectory
    $compareParameters['ReportWebPortalUrls']             = $ReportWebPortalUrls
    $compareParameters['DatabaseServerInstance']          = $DatabaseServerInstance
    $compareParameters['DatabaseName']                    = $DatabaseName
    $compareParameters['ReportDatabaseLogonType']         = $ReportDatabaseLogonType

    # Don't need to compare these parameters
    $compareParameters.Remove('DatabaseConnectLogonType')
    $compareParameters.Remove('DatabaseConnectCredential')
    $compareParameters.Remove('UseServiceWithRemoteDatabase')

    $compareTargetResourceNonCompliant = Compare-TargetResourceState @compareParameters | Where-Object {
        $_.Pass -eq $false
    }

    if ($compareTargetResourceNonCompliant)
    {
        Write-Verbose -Message ($LocalizedData.RSNotInDesiredState -f $ReportServiceInstanceName)
        return $false
    }
    else
    {
        Write-Verbose -Message ($LocalizedData.RSInDesiredState -f $ReportServiceInstanceName)
        return $true
    }
}

Function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ReportServiceInstance]
        $ReportServiceInstanceName,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ServiceAccount,

        [Parameter()]
        [ReportServiceAccount]
        $ServiceAccountLogonType = [ReportServiceAccount]::Virtual,

        [Parameter()]
        [System.String]
        $ReportManagerVirtualDirectory = 'ReportServer',

        [Parameter()]
        [System.String[]]
        $ReportManagerUrls = @('http://+:80'),

        [Parameter()]
        [System.String]
        $ReportWebPortalVirtualDirectory = 'Reports',

        [Parameter()]
        [System.String[]]
        $ReportWebPortalUrls = @('http://+:80'),

        [Parameter()]
        [System.String]
        $DatabaseServerInstance = $env:Computername,

        [Parameter()]
        [System.String]
        $DatabaseName = 'ReportServer',

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ReportDatabaseCredential,

        [Parameter()]
        [ReportDatabaseLogonType]
        $ReportDatabaseLogonType = [ReportDatabaseLogonType]::Service,

        [Parameter()]
        [System.String]
        $EmailSender,

        [Parameter()]
        [System.String]
        $EmailSMTP,

        [Parameter()]
        [EmailAuthenticationType]
        $EmailAuthentication = [EmailAuthenticationType]::None,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $EmailSMTPCredential,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ExecutionAccount,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $FileShareAccount,

        [Parameter()]
        [DatabaseConnectLogonType]
        $DatabaseConnectLogonType = [DatabaseConnectLogonType]::Integrated,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $DatabaseConnectCredential,

        [Parameter()]
        [System.Boolean]
        $UseServiceWithRemoteDatabase = $false
    )

    $compareParameters = @{} + $PSBoundParameters
    # Need to set these parameters to compare if users are using the default parameter values
    $compareParameters['ServiceAccountLogonType']         = $ServiceAccountLogonType
    $compareParameters['ReportManagerVirtualDirectory']   = $ReportManagerVirtualDirectory
    $compareParameters['ReportManagerUrls']               = $ReportManagerUrls
    $compareParameters['ReportWebPortalVirtualDirectory'] = $ReportWebPortalVirtualDirectory
    $compareParameters['ReportWebPortalUrls']             = $ReportWebPortalUrls
    $compareParameters['DatabaseServerInstance']          = $DatabaseServerInstance
    $compareParameters['DatabaseName']                    = $DatabaseName
    $compareParameters['ReportDatabaseLogonType']         = $ReportDatabaseLogonType

    # Don't need to compare these parameters
    $compareParameters.Remove('DatabaseConnectLogonType')
    $compareParameters.Remove('DatabaseConnectCredential')
    $compareParameters.Remove('UseServiceWithRemoteDatabase')

    # Compare what parameters are not in desired state
    $compareTargetResource = Compare-TargetResourceState @compareParameters
    $compareTargetResourceNonCompliant = @($compareTargetResource | Where-Object {$_.Pass -eq $false})

    # Get the CIM Configuration instance to update configuration when needed
    $rsConfigurationCIMInstance = (
        Get-ReportingServicesCIM -ReportServiceInstanceName $ReportServiceInstanceName
    ).ConfigurationCIM

    Write-Verbose -Message ($LocalizedData.SettingNonDesiredStateParameters -f $ReportServiceInstanceName)
    $lcid = (Get-Culture).LCID

    <#
      This script follows the same process the SSRS/PBIRS GUI installation uses
      ========== Required ===========
      1. Configure a service account used to run the SSRS/PBIRS service
      2. Create the Web Service Manager - This is used for backend management and isn't the front-end interface
      3. Create the Database
         - Verify Database SKU (What does this do?)
         - Generate Database script
         - Run Database script
         - Generate User rights script
         - Run User rights script
         - Set DSN (What does this do?)
      4. Create the Web Portal (Front-end)
      ========== Optional ===========
      5. Configure email settings
      6. Configure Execution Account
      7. Encryption Keys - Nothing
      8. Subscription Settings
      9. Scale-out Deployment
      10. PowerBI Cloud
    #>

    #region Check if service account is in compliance
    <#
    TODO: Follow up with this
     If we change the account, we may need to backup and restore the encryption keys,
     Grant access user rights to the database
          ServiceController rsService = new ServiceController(this.ServerAdmin.RsServiceName, this.ConfigurationInstance.MachineName);
      if (!this.m_skipBackupKey && (!this.StartWindowsServicePreChangeWindowsServiceIdentity(rsService) || this.ServerAdmin.IsInitialized && !this.BackupEncryptionKey()))
        return;
      this.m_skipBackupKey = true;
      if (!this.StopWindowsService(rsService) || !this.ChangeWindowsServiceIdentity(rsService.ServiceName, this.rdoWindowsAccount, this.txtAccount, this.txtPassword, this.cmbBuiltinAccounts) || !this.GrantRights(rsService.ServiceName, this.cmbBuiltinAccounts, this.ServerAdmin.WindowsServiceIdentityActual))
        return;
      this.StartWindowsServicePostChangeWindowsServiceIdentity(rsService);
      if (!this.UpdateUrls() || this.m_keyFile != null && !this.RestoreEncryptionKey())
        return;
      this.RestartServiceAndEnableUI();
      this.RefreshUIWithErrorHandling();
    #>
    $serviceAccountTypeNonCompliantObject = $compareTargetResourceNonCompliant |
        Where-Object -Filter {$_.Parameter -eq 'ServiceAccountLogonType'}
    $serviceAccountNonCompliantObject = $compareTargetResourceNonCompliant |
        Where-Object -Filter {$_.Parameter -eq 'ServiceAccount'}

    <#
     The service account is not compliant and we not have the correct
     service name it set.
    #>
    if ($serviceAccountNonCompliantObject -or $serviceAccountTypeNonCompliantObject)
    {
        $setServiceAccountParameters = @{
            ReportServiceInstanceName = $ReportServiceInstanceName
            ServiceAccount            = $ServiceAccount
            ServiceAccountLogonType   = $ServiceAccountLogonType
        }

        Invoke-ChangeServiceAccount @setServiceAccountParameters
    }
    #endregion Check if service account is in compliance


<#
    # #region Check if web service manager is in compliance
    # $webServiceManagerNonCompliantState = $compareTargetResourceNonCompliant | Where-Object -Filter {
    #     $_.Parameter -eq 'ReportServerVirtualDirectory' -or $_.Parameter -eq 'ReportServerReservedUrl'
    # }

    # $webServiceUrlNonCompliantState  = $compareTargetResourceNonCompliant | Where-Object -Filter {
    #     $_.Parameter -eq 'ReportServerReservedUrl'
    # }

    # #TODO: Need to update this as well if service account is changed
    # #URL reservations are created for the current windows service account.
    # #Changing the windows service account requires updating all the URL reservations manually.

    # <#
    #   Is the Virtual Directory or the reservations urls out of compliance

    #   if Virtual Directory is out of compliance, we need to remove the urls first
    #   and then set the virtual directory

    #   if urls are out of compliance, we need to remove the urls first and then set them
    #   so no matter what we need to remove the urls
    # #>
    # if($webServiceManagerNonCompliantState -or $webServiceUrlNonCompliantState)
    # {
    #     $webServiceCommonArguments = @{
    #         Lcid = $LCID
    #         Application = 'ReportServerWebService'
    #     }

    #     #region Remove URL Strings
    #     $webServiceUrlState = $compareTargetResource | Where-Object -Filter {
    #         $_.Parameter -eq 'ReportServerReservedUrl'
    #     }

    #     if (-not [String]::IsNullOrEmpty($webServiceUrlState.Actual))
    #     {
    #         $invokeRsCimMethodParameters = @{
    #             CimInstance = $rsConfigurationCIMInstance
    #             MethodName = 'RemoveURL'
    #             Arguments = $webServiceCommonArguments + @{UrlString = ''}
    #         }

    #         $webServiceUrlState.Actual | ForEach-Object {
    #             write-host "urlstring" $_
    #             $invokeRsCimMethodParameters.Arguments.UrlString = $_
    #             Invoke-RsCimMethod @invokeRsCimMethodParameters
    #         }
    #     }
    #     #endregion Remove URL Strings

    #     if ($webServiceManagerNonCompliantState)
    #     {
    #         # Set Virtual Directory on the Web Service (Manager)
    #         $invokeRsCimMethodParameters = @{
    #             CimInstance = $rsConfigurationCIMInstance
    #             MethodName = 'SetVirtualDirectory'
    #             Arguments = $webServiceCommonArguments + @{VirtualDirectory = $ReportServerVirtualDirectory}
    #         }

    #         Invoke-RsCimMethod @invokeRsCimMethodParameters
    #     }

    #     # Set the URLS for the Web Service (Manager)
    #     $invokeRsCimMethodParameters = @{
    #         CimInstance = $rsConfigurationCIMInstance
    #         MethodName = 'ReserveURL'
    #         Arguments = $webServiceCommonArguments + @{UrlString = ''}
    #     }

    #     $ReportServerReservedUrl | ForEach-Object -Process {
    #         $invokeRsCimMethodParameters.Arguments.UrlString = $_
    #         Invoke-RsCimMethod @invokeRsCimMethodParameters
    #     }
    # }
    # #endregion Check if web service manager is in compliance

    # #region Check if database is in compliance
    # <#
    #   You can use an existing database or create a new one
    #   Probably set a new parameter, useExisting

    #   Check if database exists first and then if it does use existing to join
    #   the server as a scale-out server to the database

    #   Otherwise we need to create the database first
    # #>

    # Import-SQLPSModule

    # $sqlConnectParameters = @{
    #     DatabaseServerName = $DatabaseServerName
    #     DatabaseInstanceName = $DatabaseInstanceName
    #     DatabaseAuthentication = $DatabaseAuthentication
    # }

    # if ($PSBoundParameters.ContainsKey('DatabaseSQLCredential'))
    # {
    #     $sqlConnectParameters.DatabaseSQLCredential = $DatabaseSQLCredential
    # }

    # # New-SQLServerConnection will check if we can connect to database
    # $databaseServerSQLInstance = New-SQLServerConnection @sqlConnectParameters

    # if ($databaseServerSQLInstance.Databases[$DatabaseName])
    # {
    #     # Database exists, so we don't create, but possibly add the node
    # }
    # else
    # {
    #     <#
    #         Database does not exist, so we need to create it
    #         Create the ReportServer and ReportServerTempDB databases
    #     #>
    #     $getReportServiceFullName = $getTargetResource.EditionName

    #     #TODO: Need new parameter to specify report services database user
    #     $newDatabaseCreationParameters = @{
    #         ReportingServicesFullName = $getReportServiceFullName
    #         DatabaseName = $DatabaseName
    #         LCID = $LCID

    #     }

    #     $databaseServerSQLInstance | New-CreateNewDatabase @newDatabaseCreationParameters

    # }
    # #endregion Check if database is in compliance #>
}

Function Compare-TargetResourceState #Complete
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ReportServiceInstance]
        $ReportServiceInstanceName,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ServiceAccount,

        [Parameter()]
        [ReportServiceAccount]
        $ServiceAccountLogonType,

        [Parameter()]
        [System.String]
        $ReportManagerVirtualDirectory,

        [Parameter()]
        [System.String[]]
        $ReportManagerUrls,

        [Parameter()]
        [System.String]
        $ReportWebPortalVirtualDirectory,

        [Parameter()]
        [System.String[]]
        $ReportWebPortalUrls,

        [Parameter()]
        [System.String]
        $DatabaseServerInstance,

        [Parameter()]
        [System.String]
        $DatabaseName,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ReportDatabaseCredential,

        [Parameter()]
        [ReportDatabaseLogonType]
        $ReportDatabaseLogonType,

        [Parameter()]
        [System.String]
        $EmailSender,

        [Parameter()]
        [System.String]
        $EmailSMTP,

        [Parameter()]
        [EmailAuthenticationType]
        $EmailAuthentication,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $EmailSMTPCredential,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ExecutionAccount,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $FileShareAccount,

        [Parameter()]
        [DatabaseConnectLogonType]
        $DatabaseConnectLogonType,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $DatabaseConnectCredential,

        [Parameter()]
        [System.Boolean]
        $UseServiceWithRemoteDatabase
    )

    Write-Verbose -Message ($LocalizedData.ComparingSpecifiedParameters -f $ReportServiceInstanceName)

    $getTargetResourceResult = Get-TargetResource -ReportServiceInstanceName $ReportServiceInstanceName
    $compareTargetResource = @()

    # Only check parameters that we passed in explicitly
    foreach ($parameter in $PSBoundParameters.Keys)
    {
        $expectedValue = $PSBoundParameters.$parameter
        $actualValue   = $getTargetResourceResult.$parameter

        # We only need the username from credentials to compare
        if ($expectedValue -is [PSCredential])
        {
            $expectedValue = $PSBoundParameters.$parameter.UserName
        }

        # Need to check if parameter is part of schema, otherwise ignore all other parameters like verbose
        if ($getTargetResourceResult.Contains($parameter))
        {
            Write-Verbose -Message ($script:localizedData.CheckingParameterState -f $parameter)

            $isOutOfCompliance = $false
            # Check if any of the values are null since compare-object can't compare null values
            if ([String]::IsNullOrEmpty($expectedValue) -or [String]::IsNullOrEmpty($actualValue))
            {
                # If one of the values are null, but the other isn't, it's out of compliance
                if (-not [String]::IsNullOrEmpty($expectedValue) -or -not [String]::IsNullOrEmpty($actualValue))
                {
                    $isOutOfCompliance = $true
                }
            }
            else
            {
                $difference = Compare-Object -ReferenceObject $expectedValue -DifferenceObject $actualValue
                if ($difference)
                {
                    $isOutOfCompliance = $true
                }
            }


            $expectedValueToString = $expectedValue
            $actualValueToString = $actualValue
            if($expectedValueToString -is [System.String[]])
            {
                $expectedValueToString = '[{0}]' -f ($expectedValue -join ', ')
                $actualValueToString = '[{0}]' -f ($actualValue -join ', ')
            }

            if($isOutOfCompliance)
            {
                Write-Verbose -Message (
                    $script:localizedData.ParameterNotInDesiredState -f
                        $parameter,
                        $expectedValueToString,
                        $actualValueToString
                )

                $compareTargetResource += [pscustomobject] @{
                    Parameter = $parameter
                    Expected  = $expectedValue
                    Actual    = $actualValue
                    Pass      = $false
                }
            }
            else
            {
                Write-Verbose -Message (
                    $script:localizedData.ParameterInDesiredState -f
                        $parameter,
                        $expectedValueToString,
                        $actualValueToString
                )

                $compareTargetResource += [pscustomobject] @{
                    Parameter = $parameter
                    Expected  = $expectedValue
                    Actual    = $actualValue
                    Pass      = $true
                }
            }
        }
    } #end foreach PSBoundParameter

    return $compareTargetResource
}

Function Convert-HashtableToArguments #Complete
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]
        $Hashtable
    )

    $arguments = @()
    $Hashtable.GetEnumerator() | Foreach-Object {
        $arguments += "-{0} '{1}'" -f $_.Name, $_.Value
    }

    return $arguments -join ' '
}

<#
    .SYNOPSIS
        Returns SQL Reporting Services data: configuration object used to initialize and configure
        SQL Reporting Services and the name of the Reports Web application name (changed in SQL 2016)

    .NOTES
        We can use WMI to get and set all values for Reporting services instead of relying on the registry
        There are 2 classes that we can use to get most of the information we need. The only thing we cannot
        retrieve is the Product Key, which i believe is in the checksum within the registry and it's encrypted.

        WMI Classes:
            Namespace: root\Microsoft\SqlServer\ReportServer\<InstanceName>\v<Version>, Class: MSReportServer_Instance
            Namespace: root\Microsoft\SqlServer\ReportServer\<InstanceName>\v<Version>\Admin, Class: MSReportServer_ConfigurationSetting
#>
function Get-ReportingServicesCIM #Complete
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter()]
        [ReportServiceInstance]
        $ReportServiceInstanceName
    )

    $rootReportServerNameSpace = 'ROOT\Microsoft\SqlServer\ReportServer'
    if (-not $PSBoundParameters.ContainsKey('ReportServiceInstanceName'))
    {
        Write-Verbose -Message ($script:localizedData.RetrievingRSInstanceNameAuto)

        $cimReportServicesParameters = @{
            Namespace   = $rootReportServerNameSpace
            Class       = '__NameSpace'
        }

        $instanceNameResult = Get-RsCimInstance @cimReportServicesParameters

        if ($instanceNameResult.Error)
        {
            $arguments = Convert-HashtableToArguments $cimReportServicesParameters
            $errorMessage = $script:localizedData.IssueRetrievingCIMInstance -f ("Get-CimInstance $arguments", 9)
            New-InvalidResultException -Message $errorMessage -ErrorRecord ($instanceNameResult.Result)
        }
        else
        {
            $instanceName = ($instanceNameResult.Result).Name
            Write-Verbose -Message ($script:localizedData.SetRSInstanceName -f $instanceName)
        }
    }
    else
    {
        $instanceName = 'RS_{0}' -f $ReportServiceInstanceName
        Write-Verbose -Message ($script:localizedData.SetRSInstanceName -f $instanceName)
    }

    <#
     We try and get the instanceName automatically, it will return an empty string
     if it doesn't exist
    #>

    if ([String]::IsNullOrEmpty($instanceName) -and -not $PSBoundParameters.ContainsKey('ReportServiceInstanceName'))
    {
        # Reporting Services is probably not installed
        New-InvalidResultException -Message ($script:localizedData.IssueRetrievingRSInstance)
    }
    else
    {
        Write-Verbose -Message ($script:localizedData.RetrievingRSInstanceVersion)

        $cimReportServicesParameters = @{
            Namespace   = '{0}\{1}' -f $rootReportServerNameSpace, $instanceName
            Class       = '__NameSpace'
        }

        $instanceVersionResult = Get-RsCimInstance @cimReportServicesParameters
        if ($instanceNameResult.Error)
        {
            $arguments = Convert-HashtableToArguments $cimReportServicesParameters
            $errorMessage = $script:localizedData.IssueRetrievingCIMInstance -f ("Get-CimInstance $arguments", 9)
            New-InvalidResultException -Message $errorMessage -ErrorRecord ($instanceNameResult.Result)
        }
        else
        {
            $instanceVersion = ($instanceVersionResult.Result).Name
            Write-Verbose -Message ($script:localizedData.SetRSInstanceVersion -f $instanceVersion)
        }
    }

    if ([String]::IsNullOrEmpty($instanceVersion))
    {
        # Reporting Services is probably installe, but it's the wrong instance
        New-InvalidResultException -Message (
            $script:localizedData.IssueRetrievingRSVersion -f $ReportServiceInstanceName, 9
        )
    }

    Write-Verbose -Message ($script:localizedData.RetrievingRSInstanceObject)
    $cimMSReportServerInstance = @{
        Namespace   = '{0}\{1}\{2}' -f $rootReportServerNameSpace, $instanceName, $instanceVersion
        Class       = 'MSReportServer_Instance'
    }
    write-host $cimMSReportServerInstance.Values

    $cimReportServerInstanceResults = Get-RsCimInstance @cimMSReportServerInstance

    if ($cimReportServerInstanceResults.Error)
    {
        $arguments = Convert-HashtableToArguments $cimMSReportServerInstance
        $errorMessage = $script:localizedData.IssueRetrievingCIMInstance -f ("Get-CimInstance $arguments", 9)
        New-InvalidResultException -Message $errorMessage -ErrorRecord ($cimReportServerInstanceResults.Result)
    }
    else
    {
        $cimReportServerInstanceObject = $cimReportServerInstanceResults.Result
        Write-Verbose -Message ($script:localizedData.RetrievingRSInstanceObjectSuccess)
    }

    Write-Verbose -Message ($script:localizedData.RetrievingRSConfigurationObject)
    $cimMSReportServerConfigurationSetting = @{
        Namespace   = '{0}\Admin' -f $cimMSReportServerInstance.Namespace
        Class       = 'MSReportServer_ConfigurationSetting'
    }

    $cimReportServerConfigurationResults = Get-RsCimInstance @cimMSReportServerConfigurationSetting
    if ($cimReportServerConfigurationResults.Error)
    {
        $arguments = Convert-HashtableToArguments $cimMSReportServerConfigurationSetting
        $errorMessage = $script:localizedData.IssueRetrievingCIMInstance -f ("Get-CimInstance $arguments", 9)
        New-InvalidResultException -Message $errorMessage -ErrorRecord ($cimReportServerConfigurationResults.Result)
    }
    else
    {
        $cimReportServerConfigurationObject = $cimReportServerConfigurationResults.Result
        Write-Verbose -Message ($script:localizedData.RetrievingRSConfigurationObjectSuccess)
    }

    return @{
        InstanceCIM      = $cimReportServerInstanceObject
        ConfigurationCIM = $cimReportServerConfigurationObject
    }
}

Function Invoke-RsCimMethod #Complete
{
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimMethodResult])]
    param
    (

        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance]
        $CimInstance,

        [Parameter(Mandatory = $true)]
        [System.String]
        $MethodName,

        [Parameter()]
        [System.Collections.Hashtable]
        $Arguments
    )

    $invokeCimMethodParameters = @{
        MethodName = $MethodName
        ErrorAction = 'Stop'
    }

    $errorResult = $false

    if ($PSBoundParameters.ContainsKey('Arguments'))
    {
        $invokeCimMethodParameters['Arguments'] = $Arguments
    }

    try
    {
        $invokeCimMethodResult = $CimInstance | Invoke-CimMethod @invokeCimMethodParameters
    }
    catch
    {
        $errorResult = $true
        $invokeCimMethodResult = $_
    }

    return @{
        Result = $invokeCimMethodResult
        Error = $errorResult
    }
}

Function Get-RsCimInstance #Complete
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter()]
        [System.String]
        $Namespace,

        [Parameter(Mandatory)]
        [System.String]
        $Class
    )

    $getCimInstanceParameters = @{
        Class = $Class
        ErrorAction = 'Stop'
    }

    $errorResult = $false

    if ($PSBoundParameters.ContainsKey('Namespace'))
    {
        $getCimInstanceParameters['Namespace'] = $Namespace
    }

    try
    {
        $getCimInstanceResult = Get-CimInstance @getCimInstanceParameters
    }
    catch
    {
        $errorResult = $true
        $getCimInstanceResult = $_
    }

    return @{
        Result = $getCimInstanceResult
        Error = $errorResult
    }
}

Function Invoke-ChangeServiceAccount
{
    param
    (
        [Parameter(Mandatory = $true)]
        [ReportServiceInstance]
        $ReportServiceInstanceName,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ServiceAccount,

        [Parameter(Mandatory = $true)]
        [ReportServiceAccount]
        $ServiceAccountLogonType,

        [Parameter(Mandatory = $true)]
        [DatabaseConnectLogonType]
        $DatabaseConnectLogonType,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $DatabaseConnectCredential
    )

    # We need to get read-only values
    $rsConfigurationCIMInstance = (
        Get-ReportingServicesCIM -ReportServiceInstanceName $ReportServiceInstanceName
    ).ConfigurationCIM

    <#
     1. Make sure Service is running
     2. Check if database is initialized
     3. If database is initialized - backup encryption keys
     4. Stop service
     5. Invoke-SetServiceAccount
     6. Grant user rights
     7. Start service
     8. Update URLs
     9. Restore Encryption key if database was initialized and we have a backup
    #>

    $serviceName = $rsConfigurationCIMInstance.ServiceName
    if ((Get-Service -Name $serviceName).Status -ne 'Running' -and $rsConfigurationCIMInstance.IsInitialized)
    {
        #TODO:
        # THe issue i think here is we need to be able to connect to the database
        # to get the keys if database is created and back them up. If the service is not
        # running we cant do that. If we update the service account without doing this
        # will it break?
        # Start the windows service
        try
        {
            Start-Service $serviceName -ErrorAction Stop
        }
        catch
        {
            #TODO: throw error can't stop service
            throw
        }
    }

    $backupEncryptionKey = $false
    if ($rsConfigurationCIMInstance.IsInitialized)
    {
        # Need to backup key
        #TODO: add new parameter for password?
        # $backupStatus = Invoke-BackupEncryptionKey

        if($backupStatus)
        {
            $backupEncryptionKey = $true
        }
        else
        {
            #TODO: throw error, backup failed
            throw
        }
    }

    # Stop the windows service
    try
    {
        Stop-Service $serviceName -ErrorAction Stop
    }
    catch
    {
        #TODO: throw error can't stop service
        throw
    }

    #region Update the service account
    # Will throw errors within the function if it fails
    $setServiceAccountParameters = @{
        ReportServiceInstanceName = $ReportServiceInstanceName
        ServiceAccount            = $ServiceAccount
        ServiceAccountLogonType  = $ServiceAccountLogonType
    }

    Invoke-SetServiceAccount @setServiceAccountParameters
    #endregion Update the service account

    #region Update the user permissions on the database
    # Refresh the CIM Configuration instance
    $rsConfigurationCIMInstance = (
        Get-ReportingServicesCIM -ReportServiceInstanceName $ReportServiceInstanceName
    ).ConfigurationCIM

    $rsDatabaseLogonTypeInt = $rsConfigurationCIMInstance.DatabaseLogonType
    $rsDatabaseLogonTypeEnum = [Reportdatabaselogontype].GetEnumNames() | Where-Object -Filter{
        [Reportdatabaselogontype]::$_.value__ -eq $rsDatabaseLogonType
    }

    if ($rsDatabaseLogonTypeEnum -eq [Reportdatabaselogontype]::Service -and
            -not [String]::IsNullOrEmpty($rsConfigurationCIMInstance.DatabaseName))
    {
        <#
         Database does exist and we are using the service account
         as the reporting services database user, so we need to update
         permissions. We are using is a service account which is a windows
         account and not a sql account, so IsWindowsUser is false, but then
         IsRemote is automatically false. The cim method call will return an
         error otherwise
        #>
        $grantUserRightsParameters = @{
            UserName      = $rsConfigurationCIMInstance.WindowsServiceIdentityActual
            DatabaseName  = $rsConfigurationCIMInstance.DatabaseName
            IsRemote      = $false
            IsWindowsUser = $true
        }

        $databasUserPermissionsScript = Invoke-GrantUserRights @grantUserRightsParameters
    }
    #endregion Update the user permissions on the database

    Write-host start server
    # Start the windows service
    try
    {
        Start-Service $serviceName -ErrorAction Stop
    }
    catch
    {
        #TODO: throw error can't stop service
        throw
    }

    #TODO: implement Invoke-UpdateUrls, use listreservedurls to remove and update
    # Will throw errors within the function if it fails
    #Invoke-UpdateUrls -ReportServiceInstance $ReportServiceInstanceName

    if ($backupEncryptionKey)
    {
        #TODO: Invoke-RestoreEncryptionKeys
        # restore keys
        # Need file name and password, should be same parameters an encrypt
        #Invoke-RestoreEncryptionKeys
    }

    #Complete
}

Function Invoke-SetServiceAccount #TODO: Add verbose logging
{
    param
    (
        [Parameter(Mandatory = $true)]
        [ReportServiceInstance]
        $ReportServiceInstanceName,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ServiceAccount,

        [Parameter(Mandatory = $true)]
        [ReportServiceAccount]
        $ServiceAccountLogonType
    )

    $rsConfigurationCIMInstance = (
        Get-ReportingServicesCIM -ReportServiceInstanceName $ReportServiceInstanceName
    ).ConfigurationCIM


    if ($ServiceAccountLogonType -eq [ReportServiceAccount]::Windows -and -not $ServiceAccount)
    {
        <#
         The service account type is windows, but we don't have
         a credential set. Throw error
        #>
        throw
    }
    elseif ($ServiceAccountLogonType -eq [ReportServiceAccount]::Windows)
    {
        $useBuiltinServiceAccount = $false
        $userDomain =  $ServiceAccount.GetNetworkCredential().Domain
        if ([String]::IsNullOrEmpty($userDomain))
        {
            # TODO: message - There needs to be a domain name with a windows account
            throw
        }
        $serviceAccountToSet = '{0}\{1}' -f
            $userDomain, $ServiceAccount.GetNetworkCredential().Username

        $serviceAccountPasswordToSet = $serviceAccount.GetNetworkCredential().Password
    }
    else
    {
        # It's not a windows account, but's a builtin service account instead
        $builtinAccountsConversion = @{
            [ReportServiceAccount]::Virtual = 'NT Service\{0}' -f $rsConfigurationCIMInstance.ServiceName
            [ReportServiceAccount]::Network = 'Builtin\NetworkService'
            [ReportServiceAccount]::System  = 'Builtin\System'
            [ReportServiceAccount]::Local   = 'Builtin\LocalService'
        }

        $useBuiltinServiceAccount = $true
        $serviceAccountToSet = $builtinAccountsConversion[$ServiceAccountLogonType]
        $serviceAccountPasswordToSet = ''
    }

    Write-Verbose -Message ($LocalizedData.AttemptingToSetServiceAccount -f $serviceAccountToSet, $ServiceAccountLogonType)

    $invokeRsCimMethodParameters = @{
        CimInstance = $rsConfigurationCIMInstance
        MethodName = 'SetWindowsServiceIdentity'
        Arguments = @{
            UseBuiltInAccount = $useBuiltinServiceAccount
            Account           = $serviceAccountToSet
            Password          = $serviceAccountPasswordToSet
        }
    }

    $invokeRsCimMethodResult = Invoke-RsCimMethod @invokeRsCimMethodParameters

    if ($invokeRsCimMethodResult.Error)
    {
        $errorMessage = $script:localizedData.IssueCallingCIMMethod -f ('SetWindowsServiceIdentity', 9)
        New-InvalidResultException -Message $errorMessage -ErrorRecord ($invokeRsCimMethodResult.Result)
    }
    else
    {
        Write-Verbose -Message ($script:localizedData.SetServiceAccountSuccessful)
    }
}

Function Invoke-GrantUserRights #TODO: Add verbose logging
{
    param
    (
        [Parameter(Mandatory = $true)]
        [ReportServiceInstance]
        $ReportServiceInstanceName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $UserName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DatabaseName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $IsRemote,

        [Parameter(Mandatory = $true)]
        [System.String]
        $IsWindowsUser
    )

    $rsConfigurationCIMInstance = (
        Get-ReportingServicesCIM -ReportServiceInstanceName $ReportServiceInstanceName
    ).ConfigurationCIM

    # Generate user rights script
    $invokeRsCimMethodParameters = @{
        CimInstance = $rsConfigurationCIMInstance
        MethodName = 'GenerateDatabaseRightsScript'
        Arguments = @{
            UserName      = $UserName
            DatabaseName  = $DatabaseName
            IsRemote      = $IsRemote
            IsWindowsUser = $IsWindowsUser
        }
    }

    $invokeRsCimMethodResult = Invoke-RsCimMethod @invokeRsCimMethodParameters

    if ($invokeRsCimMethodResult.Error)
    {
        $errorMessage = $script:localizedData.IssueCallingCIMMethod -f ('SetWindowsServiceIdentity', 9)
        New-InvalidResultException -Message $errorMessage -ErrorRecord ($invokeRsCimMethodResult.Result)
    }
    else
    {
        Write-Verbose -Message ($script:localizedData.SetServiceAccountSuccessful)
    }

    return $invokeRsCimMethodResult.Result.Script
}

<#
    .NOTES
        Reporting Services can used the built-in account for connecting
        to the database. When running DSC, it will run under the System
        user context. For this reason, we should only specify a windows
        account or sql account. This account will need to be able to
        create new databases for initial install. For this reason, it
        may be possible use the Reporting Services account and then remove
        those privileages after the fact.
#>
Function New-SQLServerConnection
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [System.String]
        $DatabaseServerName = $env:COMPUTERNAME,

        [Parameter()]
        [System.String]
        $DatabaseInstanceName = 'MSSQLSERVER',

        [Parameter()]
        [ValidateSet('Integrated', 'Windows', 'SQL')]
        [System.String]
        $DatabaseAuthentication = 'Integrated',

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $DatabaseSQLCredential
    )

    $loginTypes = @{
        Windows = 'WindowsUser'
        SQL = 'SqlLogin'
    }

    $connectSQLParameters = @{
        ServerName = $DatabaseServerName
        InstanceName = $DatabaseInstanceName
    }

    $databaseServerSQLInstance = $null

    if (-not $DatabaseAuthentication -eq 'Integrated')
    {
        $connectSQLParameters.SetupCredential = $DatabaseSQLCredential
        $connectSQLParameters.LoginType = $loginTypes.DatabaseAuthentication
    }

    try
    {
        $databaseServerSQLInstance = Connect-SQL @connectSQLParameters
    }
    catch
    {
        #TODO: Issues connecting, throw error
    }

    return $databaseServerSQLInstance
}

Function Get-SQLServerEdition
{
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline, Mandatory)]
        [ValidateNotNull()]
        [Microsoft.SqlServer.Management.Smo.Server]
        $SqlManagementObject
    )

    $sqlQuery = "SELECT SERVERPROPERTY('Edition')"

    try
    {
        $sqlQueryResults = $SqlManagementObject | Invoke-Query -Query $sqlQuery -WithResults
        $sqlVersion = $sqlQueryResults.Tables[0].Column1
    }
    catch
    {
        # Invoke-Query failed
    }

    return $sqlVersion
}

Function New-CreateNewDatabase
{
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline, Mandatory)]
        [ValidateNotNull()]
        [Microsoft.SqlServer.Management.Smo.Server]
        $SqlManagementObject,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.String]
        $ReportingServicesFullName,

        [Parameter(Mandatory)]
        [System.String]
        $DatabaseName,

        [Parameter(ValidateNotNull)]
        [System.Int]
        $LCID = (Get-Culture).LCID


    )

    #TODO: Check if the reporting services and database are being installed on the same server
    #TODO: Write-verbose to include check for local server
    #Get-IsLocalServer

    #TODO: Write-verbose to include set sku type
    $reportingServiceSkuUtil =  Get-ReportServiceSkuUtils
    $reportingServiceSkuUtil.SetRSSkuFromString($ReportingServicesFullName)

    #TODO: Write-verbose to include sql edition
    $sqlEdition = $SqlManagementObject | Get-SQLServerEdition

    #TODO: Write-verbose to include comparison
    $correctEditionComparison = $reportingServiceSkuUtil.EnsureCorrectEdition($sqlEdition)

    #TODO: Should we leave error checking in utils or do it here?
    #If we do it here, I need to know which error to return
    if (-not $correctEditionComparison)
    {

    }

    # Everything checks out ok, now we can create the database script
    $invokeRsCimMethodParameters = @{
        CimInstance = $rsConfigurationCIMInstance
        MethodName = 'GenerateDatabaseCreationScript'
        Arguments = @{
            DatabaseName = $DatabaseName
            IsSharePointMode = $false # ALWAYS FALSE
            Lcid = $LCID
        }
    }

    #TODO: Write-verbose to include starting database script
    [string]$reportServerGeneratedSQLScript = (Invoke-RsCimMethod @invokeRsCimMethodParameters).Script

    # Invoke-Query will throw errors
    #TODO: Write-verbose to include starting database creation
    $SqlManagementObject | Invoke-Query -Query $reportServerGeneratedSQLScript -Database 'master'

    #TODO: Write-verbose to include creation of user script

    #TODO: Write-verbose to include setting user database permissions

    #TODO: Write-verbose to include set DSN
}

Function Test-NewSQLInstanceSku
{
    param
    (
        [Parameter(Mandatory)]
        [System.String] $ReportServicesSku
    )

    $sqlVersion = Get-SQLServerEdition
    try
    {
        $reportServicesSkuUtils = [ReportServiceSkuUtils]::new()
        if (-not $reportServicesSkuUtils.SetRSSkuFromString($ReportServicesSku))
        {
            #TODO: Issue setting sku
        }

        $sqlSku = $reportServicesSkuUtils.GetSQLSkuFromSQLEdition($sqlVersion)
        if ($sqlSku -eq [SqlServerSku]::None)
        {
            #TODO: Issue getting sql sku
        }

        return $reportServicesSkuUtils.EnsureCorrectEdition($sqlSku)
    }
    catch
    {
        #TODO: some other kind of error
    }
}

Export-ModuleMember -Function *
