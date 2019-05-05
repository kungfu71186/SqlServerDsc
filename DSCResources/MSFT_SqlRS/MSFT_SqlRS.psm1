$script:resourceModulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$script:modulesFolderPath = Join-Path -Path $script:resourceModulePath -ChildPath 'Modules'

$script:localizationModulePath = Join-Path -Path $script:modulesFolderPath -ChildPath 'DscResource.LocalizationHelper'
Import-Module -Name (Join-Path -Path $script:localizationModulePath -ChildPath 'DscResource.LocalizationHelper.psm1')

$script:resourceHelperModulePath = Join-Path -Path $script:modulesFolderPath -ChildPath 'DscResource.Common'
Import-Module -Name (Join-Path -Path $script:resourceHelperModulePath -ChildPath 'DscResource.Common.psm1')

$script:localizedData = Get-LocalizedData -ResourceName 'MSFT_SqlRS'

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'MSFT_ReportServiceSkuUtils.psm1')

<#
    .SYNOPSIS
        Gets the SQL Reporting Services configuration.
#>
Function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
    )

    # Retrieve both CIM objects
    $reportingServicesCIMObjects = Get-ReportingServicesCIM

    # Instance object is the actual SSRS/PBIRS Instance. Some information in here that is useful
    $instanceCIMObject      = $reportingServicesCIMObjects.InstanceCIM
    # Most of the configuration settings are retrieved from here
    $configurationCIMObject = $reportingServicesCIMObjects.ConfigurationCIM

    # These are the logon types, this gets converted to something that is human readable instead of a number
    $databaseLogonTypes = @('Windows Login', 'SQL Server Account', 'Current User - Integrated Security')
    # SMTP authentication types, this gets converted to something that is human readable instead of a number
    $smtpAuthenticationTypes = @('No Authentication', 'Username and password (Basic)', 'Report service service account (NTLM)')

    #region Split the Database instance into server name and instance
    # Probably shouldn't be breaking it up like this
    $databaseServerName = ($configurationCIMObject.DatabaseServerName).Split('\')
    if($databaseServerName[1])
    {
        $databaseServerInstance = $databaseServerName[1]
        $databaseServerName = $databaseServerName[0]
    }
    else
    {
        $databaseServerInstance = 'MSSQLSERVER'
        $databaseServerName = $databaseServerName[0]
    }
    #endregion Split the Database instance into server name and instance

    #region Convert service account to the keyword this resource uses
    $possibleBuiltinAccounts = @{
        Virtual = 'NT Service\{0}' -f $configurationCIMObject.ServiceName
        Network = 'NT AUTHORITY\NetworkService'
        System  = 'NT AUTHORITY\SYSTEM'
        Local   = 'NT AUTHORITY\LocalService'
    }

    $serviceAccount = $configurationCIMObject.WindowsServiceIdentityConfigured
    $possibleBuiltinAccounts.GetEnumerator() | ForEach-Object {
        if ($serviceAccount -eq $_.Value)
        {
            $serviceAccount = $_.Key
        }
    }
    #endregion Convert service account to the keyword this resource uses

    #region Get and separate Report Server URLs in human readable format
    try
    {
        $invokeRsCimMethodParameters = @{
            CimInstance = $instanceCIMObject
            MethodName = 'GetReportServerUrls'
        }

        $reportServerUrls = Invoke-RsCimMethod @invokeRsCimMethodParameters

        # Because GetReportServerUrls returns all urls for all web services, we need to match up
        # which urls belong to ReportServerWebService and ReportServerWebApp
        $reportServeUrlList = @{}

        for ( $i = 0; $i -lt $reportServerUrls.ApplicationName.Count; ++$i )
        {
            $application = ($reportServerUrls.ApplicationName)[$i]
            $url = ($reportServerUrls.URLS)[$i]
            $reportServeUrlList[$application] += @($url)
        }
    }
    catch
    {
        # Report server (Managed not set yet)
    }

    #endregion Get and separate Report Server URLs in human readable format

    #region Get and separate Report Server URLs for editing
    try
    {
        $invokeRsCimMethodParameters = @{
            CimInstance = $configurationCIMObject
            MethodName = 'ListReservedURLs'
        }

        $reportServerUrlModifiable = Invoke-RsCimMethod @invokeRsCimMethodParameters

        # Because ListReservedURLs returns all urls for all web services, we need to match up
        # which urls belong to ReportServerWebService and ReportServerWebApp
        $reportServerUrlModifiableList = @{}

        for ( $i = 0; $i -lt $reportServerUrlModifiable.Application.Count; ++$i )
        {
            $application = ($reportServerUrlModifiable.Application)[$i]
            $urlString = ($reportServerUrlModifiable.UrlString)[$i]
            $reportServerUrlModifiableList[$application] += @($urlString)
        }
    }
    catch
    {
        # Report server front-end urls not set
    }

    #endregion Get and separate Report Server URLs for editing

    #region Get list of servers in cluster
    try
    {
        $scaleOutServersParameters = @{
            CimInstance = $configurationCIMObject
            MethodName = 'ListReportServersInDatabase'
        }

        $scaleOutServers = $(Invoke-RsCimMethod @scaleOutServersParameters).MachineNames
    }
    catch
    {
        # DB Hasn't been initilized yet
    }

    #endregion Get list of servers in cluster

    $getTargetResourceResult = [ordered]@{
        InstanceName           = $instanceCIMObject.InstanceName
        Version                = $instanceCIMObject.Version
        EditionName            = $instanceCIMObject.EditionName
        InstallationID         = $configurationCIMObject.InstallationID
        IsInitialized          = $configurationCIMObject.IsInitialized
        ReportServerConfigPath = $configurationCIMObject.PathName
        ServiceName            = $configurationCIMObject.ServiceName

        # Service Account
        ServiceAccount           = $serviceAccount
        ServiceAccountConfigured = $configurationCIMObject.WindowsServiceIdentityConfigured
        ServiceAccountActual     = $configurationCIMObject.WindowsServiceIdentityActual

        # Web Service URL
        ReportServerVirtualDirectory = $configurationCIMObject.VirtualDirectoryReportServer
        ReportServerManagerURLs      = $reportServeUrlList.ReportServerWebService
        ReportServerReservedUrl      = $reportServerUrlModifiableList.ReportServerWebService

        # Database
        DatabaseServerName   = $databaseServerName
        DatabaseInstanceName = $databaseServerInstance
        DatabaseName         = $configurationCIMObject.DatabaseName
        DatabaseLogonAccount = $configurationCIMObject.DatabaseLogonAccount
        DatabaseLogonType    = $databaseLogonTypes[$configurationCIMObject.DatabaseLogonType]

        # Web Portal URL Front-end for users
        ReportsVirtualDirectory = $configurationCIMObject.VirtualDirectoryReportManager
        ReportWebPortalURLs     = $reportServeUrlList.ReportServerWebApp
        ReportsReservedUrl      = $reportServerUrlModifiableList.ReportServerWebApp

        # Email Settings
        EmailSender         = $configurationCIMObject.SenderEmailAddress
        EmailSMTP           = $configurationCIMObject.SMTPServer
        EmailSMTPSSL        = $configurationCIMObject.SMTPUseSSL
        EmailAuthentication = $smtpAuthenticationTypes[$configurationCIMObject.SMTPAuthenticate]
        EmailSMTPUser       = $configurationCIMObject.SendUserName

        # Execution Account
        ExecutionAccount = $configurationCIMObject.UnattendedExecutionAccount # Service account unattended execution

        # Encryption Keys - Nothing to get from here

        # Subscription Settings
        FileShareAccount = $configurationCIMObject.FileShareAccount # Service account used for file shares

        # Scale-out Deployment
        ScaleOutServers  = $scaleOutServers
    }

    return $getTargetResourceResult
}

<#
    .SYNOPSIS
        Initializes SQL Reporting Services.

    .PARAMETER InstanceName
        Name of the SQL Server Reporting Services instance to be configured.

    .PARAMETER DatabaseServerName
        Name of the SQL Server to host the Reporting Service database.

    .PARAMETER DatabaseInstanceName
        Name of the SQL Server instance to host the Reporting Service database.

    .PARAMETER ReportServerVirtualDirectory
        Report Server Web Service virtual directory. Optional.

    .PARAMETER ReportsVirtualDirectory
        Report Manager/Report Web App virtual directory name. Optional.

    .PARAMETER ReportServerReservedUrl
        Report Server URL reservations. Optional. If not specified,
        'http://+:80' URL reservation will be used.

    .PARAMETER ReportsReservedUrl
        Report Manager/Report Web App URL reservations. Optional.
        If not specified, 'http://+:80' URL reservation will be used.

    .PARAMETER UseSsl
        If connections to the Reporting Services must use SSL. If this
        parameter is not assigned a value, the default is that Reporting
        Services does not use SSL.

    .PARAMETER SuppressRestart
        Reporting Services need to be restarted after initialization or
        settings change. If this parameter is set to $true, Reporting Services
        will not be restarted, even after initialisation.

    .NOTES
        To find out the parameter names for the methods in the class
        MSReportServer_ConfigurationSetting it's easy to list them using the
        following code. Example for listing

        ```
        $methodName = 'ReserveUrl'
        $instanceName = 'SQL2016'
        $sqlMajorVersion = '13'
        $getCimClassParameters = @{
            ClassName = 'MSReportServer_ConfigurationSetting'
            Namespace = "root\Microsoft\SQLServer\ReportServer\RS_$instanceName\v$sqlMajorVersion\Admin"
        }
        (Get-CimClass @getCimClassParameters).CimClassMethods[$methodName].Parameters
        ```

        Or run the following using the helper function in this code. Make sure
        to have the helper function loaded in the session.

        ```
        $methodName = 'ReserveUrl'
        $instanceName = 'SQL2016'
        $reportingServicesData = Get-ReportingServicesData -InstanceName $InstanceName
        $reportingServicesData.Configuration.CimClass.CimClassMethods[$methodName].Parameters
        ```

        SecureConnectionLevel (the parameter UseSsl):
        The SecureConnectionLevel value can be 0,1,2 or 3, but since
        SQL Server 2008 R2 this was changed. So we are just setting it to 0 (off)
        and 1 (on).

        "In SQL Server 2008 R2, SecureConnectionLevel is made an on/off
        switch, default value is 0. For any value greater than or equal
        to 1 passed through SetSecureConnectionLevel method API, SSL
        is considered on..."
        https://docs.microsoft.com/en-us/sql/reporting-services/wmi-provider-library-reference/configurationsetting-method-setsecureconnectionlevel
#>
Function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DatabaseServerName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DatabaseInstanceName,

        [Parameter()]
        [System.String]
        $DatabaseName = 'ReportServer',

        [Parameter()]
        [System.String]
        $DatabaseAuthentication,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $DatabaseSQLCredential,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ServiceAccount,

        [Parameter()]
        [System.String]
        $ReportServerVirtualDirectory = 'ReportServer',

        [Parameter()]
        [System.String[]]
        $ReportServerReservedUrl = 'http://+:80',

        [Parameter()]
        [System.String]
        $ReportsVirtualDirectory = 'Reports',

        [Parameter()]
        [System.String[]]
        $ReportsReservedUrl = 'http://+:80',

        [Parameter()]
        [System.String]
        $EmailSender,

        [Parameter()]
        [System.String]
        $EmailSMTP,

        [Parameter()]
        [ValidateSet('None','Basic','Integrated')]
        [System.String]
        $EmailAuthentication = 'None',

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $EmailSMTPUser,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ExecutionAccount,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $FileShareAccount,

        [Parameter()]
        [System.Boolean]
        $UseSsl,

        [Parameter()]
        [System.Boolean]
        $UseExistingDatabase
    )
<#
Connect to database user is different than the granted rights user
#>
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

    # Need to set these parameters to compare if users are using the default parameter values
    $PSBoundParameters['ReportServerVirtualDirectory'] = $ReportServerVirtualDirectory
    $PSBoundParameters['ReportServerReservedUrl']      = $ReportServerReservedUrl
    $PSBoundParameters['ReportsVirtualDirectory']      = $ReportsVirtualDirectory
    $PSBoundParameters['ReportsReservedUrl']           = $ReportsReservedUrl

    $compareTargetResource             = Compare-TargetResourceState @PSBoundParameters
    $compareTargetResourceNonCompliant = @($compareTargetResource | Where-Object {$_.Pass -eq $false})
    $rsConfigurationCIMInstance        = (Get-ReportingServicesCIM).ConfigurationCIM
    $lcid = (Get-Culture).LCID

    $compareTargetResource

    #region Check if service account is in compliance
    $serviceAccountNonCompliantState = $compareTargetResourceNonCompliant | Where-Object -Filter {$_.Parameter -eq 'ServiceAccount'}
    if ($serviceAccountNonCompliantState)
    {
        $useBuiltinServiceAccount = $false
        $serviceName = $compareTargetResource | Where-Object -Filter {$_.Parameter -eq 'ServiceName'}
        $builtinAccountsConversion = @{
            Virtual = 'NT Service\{0}' -f $ServiceName.Actual
            Network = 'Builtin\NetworkService'
            System  = 'Builtin\System'
            Local   = 'Builtin\LocalService'
        }

        $serviceAccountUserName = $serviceAccount.UserName
        if ($builtinAccountsConversion.ContainsKey($serviceAccountNonCompliantState.Expected))
        {
            $useBuiltinServiceAccount = $true
            $serviceAccountUserName = $builtinAccountsConversion[$serviceAccountNonCompliantState.Expected]
        }

        $invokeRsCimMethodParameters = @{
            CimInstance = $rsConfigurationCIMInstance
            MethodName = 'SetWindowsServiceIdentity'
            Arguments = @{
                UseBuiltInAccount = $useBuiltinServiceAccount
                Account           = $serviceAccountUserName
                Password          = $serviceAccount.GetNetworkCredential().Password
            }
        }

        Invoke-RsCimMethod @invokeRsCimMethodParameters
    }
    #endregion Check if service account is in compliance

    #region Check if web service manager is in compliance
    $webServiceManagerNonCompliantState = $compareTargetResourceNonCompliant | Where-Object -Filter {
        $_.Parameter -eq 'ReportServerVirtualDirectory' -or $_.Parameter -eq 'ReportServerReservedUrl'
    }

    $webServiceUrlNonCompliantState  = $compareTargetResourceNonCompliant | Where-Object -Filter {
        $_.Parameter -eq 'ReportServerReservedUrl'
    }

    #TODO: Need to update this as well if service account is changed
    #URL reservations are created for the current windows service account.
    #Changing the windows service account requires updating all the URL reservations manually.

    <#
      Is the Virtual Directory or the reservations urls out of compliance

      if Virtual Directory is out of compliance, we need to remove the urls first
      and then set the virtual directory

      if urls are out of compliance, we need to remove the urls first and then set them
      so no matter what we need to remove the urls
    #>
    if($webServiceManagerNonCompliantState -or $webServiceUrlNonCompliantState)
    {
        $webServiceCommonArguments = @{
            Lcid = $lcid
            Application = 'ReportServerWebService'
        }

        #region Remove URL Strings
        $webServiceUrlState = $compareTargetResource | Where-Object -Filter {
            $_.Parameter -eq 'ReportServerReservedUrl'
        }

        if (-not [String]::IsNullOrEmpty($webServiceUrlState.Actual))
        {
            $invokeRsCimMethodParameters = @{
                CimInstance = $rsConfigurationCIMInstance
                MethodName = 'RemoveURL'
                Arguments = $webServiceCommonArguments + @{UrlString = ''}
            }

            $webServiceUrlState.Actual | ForEach-Object {
                write-host "urlstring" $_
                $invokeRsCimMethodParameters.Arguments.UrlString = $_
                Invoke-RsCimMethod @invokeRsCimMethodParameters
            }
        }
        #endregion Remove URL Strings

        if ($webServiceManagerNonCompliantState)
        {
            # Set Virtual Directory on the Web Service (Manager)
            $invokeRsCimMethodParameters = @{
                CimInstance = $rsConfigurationCIMInstance
                MethodName = 'SetVirtualDirectory'
                Arguments = $webServiceCommonArguments + @{VirtualDirectory = $ReportServerVirtualDirectory}
            }

            Invoke-RsCimMethod @invokeRsCimMethodParameters
        }

        # Set the URLS for the Web Service (Manager)
        $invokeRsCimMethodParameters = @{
            CimInstance = $rsConfigurationCIMInstance
            MethodName = 'ReserveURL'
            Arguments = $webServiceCommonArguments + @{UrlString = ''}
        }

        $ReportServerReservedUrl | ForEach-Object -Process {
            $invokeRsCimMethodParameters.Arguments.UrlString = $_
            Invoke-RsCimMethod @invokeRsCimMethodParameters
        }
    }
    #endregion Check if web service manager is in compliance

    #region Check if database is in compliance
    <#
      You can use an existing database or create a new one
      Probably set a new parameter, useExisting

      Check if database exists first and then if it does use existing to join
      the server as a scale-out server to the database

      Otherwise we need to create the database first
    #>

    Import-SQLPSModule

    $connectSQLParameters = @{
        ServerName = $DatabaseServerName
        InstanceName = $DatabaseInstanceName
    }

    <#
      DatabaseAuthentication/DatabaseSQLCredential is only used to connect
      to the sql database, this is NOT the SSRS/PBIRS database user
    #>
    if ($DatabaseAuthentication -eq 'SQL')
    {
        $connectSQLParameters = $connectSQLParameters + @{
            SetupCredential = $DatabaseSQLCredential
            LoginType = 'SqlLogin'
        }

        $databaseServerSQLInstance = Connect-SQL @connectSQLParameters
    }
    else
    {
        $databaseServerSQLInstance = Connect-SQL @connectSQLParameters
    }

    if ($databaseServerSQLInstance.Databases[$DatabaseName])
    {
        # Database exists, so we don't create, but possibly add the node
    }
    else
    {
        <#
            Database does not exist, so we need to create it
            Create the ReportServer and ReportServerTempDB databases
        #>
        $invokeRsCimMethodParameters = @{
            CimInstance = $rsConfigurationCIMInstance
            MethodName = 'GenerateDatabaseCreationScript'
            Arguments = @{
                DatabaseName = $DatabaseName
                IsSharePointMode = $false # ALWAYS FALSE
                Lcid = $lcid
            }
        }

        [string]$reportServerGeneratedSQLScript = (Invoke-RsCimMethod @invokeRsCimMethodParameters).Script

        Invoke-Query -SQLServer $DatabaseServerName -SQLInstanceName $DatabaseInstanceName -Query $reportServerGeneratedSQLScript -Database master

    }
    #endregion Check if database is in compliance
}

<#
    .SYNOPSIS
        Tests the SQL Reporting Services initialization status.

    .PARAMETER InstanceName
        Name of the SQL Server Reporting Services instance to be configured.

    .PARAMETER DatabaseServerName
        Name of the SQL Server to host the Reporting Service database.

    .PARAMETER DatabaseInstanceName
        Name of the SQL Server instance to host the Reporting Service database.

    .PARAMETER ReportServerVirtualDirectory
        Report Server Web Service virtual directory. Optional.

    .PARAMETER ReportsVirtualDirectory
        Report Manager/Report Web App virtual directory name. Optional.

    .PARAMETER ReportServerReservedUrl
        Report Server URL reservations. Optional. If not specified,
        http://+:80' URL reservation will be used.

    .PARAMETER ReportsReservedUrl
        Report Manager/Report Web App URL reservations. Optional.
        If not specified, 'http://+:80' URL reservation will be used.

    .PARAMETER UseSsl
        If connections to the Reporting Services must use SSL. If this
        parameter is not assigned a value, the default is that Reporting
        Services does not use SSL.

    .PARAMETER SuppressRestart
        Reporting Services need to be restarted after initialization or
        settings change. If this parameter is set to $true, Reporting Services
        will not be restarted, even after initialisation.
#>
Function Test-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DatabaseServerName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DatabaseInstanceName,

        [Parameter()]
        [System.String]
        $DatabaseAuthentication,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $DatabaseSQLCredential,

        [Parameter()]
        [System.String]
        $ServiceAccount,

        [Parameter()]
        [System.String]
        $ReportServerVirtualDirectory,

        [Parameter()]
        [System.String[]]
        $ReportServerReservedUrl,

        [Parameter()]
        [System.String]
        $ReportsVirtualDirectory,

        [Parameter()]
        [System.String[]]
        $ReportsReservedUrl,

        [Parameter()]
        [System.String]
        $EmailSender,

        [Parameter()]
        [System.String]
        $EmailSMTP,

        [Parameter()]
        [ValidateSet('None','Basic','Integrated')]
        [System.String]
        $EmailAuthentication,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $EmailSMTPUser,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ExecutionAccount,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $FileShareAccount,

        [Parameter()]
        [System.Boolean]
        $UseSsl
    )

    $compareTargetResourceNonCompliant = Compare-TargetResourceState @PSBoundParameters | Where-Object {$_.Pass -eq $false}

    $compareTargetResourceNonCompliant | ForEach-Object {
        Write-Verbose -Message ($LocalizedData.NotDesiredPropertyState -f `
            $_.Parameter, $_.Expected, $_.Actual)
    }

    if ($compareTargetResourceNonCompliant)
    {
        Write-Verbose -Message ($LocalizedData.RSNotInDesiredState -f $InstanceName)
        return $false
    }
    else
    {
        Write-Verbose -Message ($LocalizedData.RSInDesiredState -f $InstanceName)
        return $true
    }
}

Function Compare-TargetResourceState
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DatabaseServerName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DatabaseInstanceName,

        [Parameter()]
        [System.String]
        $DatabaseAuthentication,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $DatabaseSQLCredential,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ServiceAccount,

        [Parameter()]
        [System.String]
        $ReportServerVirtualDirectory,

        [Parameter()]
        [System.String[]]
        $ReportServerReservedUrl,

        [Parameter()]
        [System.String]
        $ReportsVirtualDirectory,

        [Parameter()]
        [System.String[]]
        $ReportsReservedUrl,

        [Parameter()]
        [System.String]
        $EmailSender,

        [Parameter()]
        [System.String]
        $EmailSMTP,

        [Parameter()]
        [ValidateSet('None','Basic','Integrated')]
        [System.String]
        $EmailAuthentication,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $EmailSMTPUser,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $ExecutionAccount,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $FileShareAccount,

        [Parameter()]
        [System.Boolean]
        $UseSsl
    )

    $parametersToCompare = @{} + $PSBoundParameters
    $getTargetResourceResult = Get-TargetResource
    $compareTargetResource = @()

    # Need to add these parameters for set
    $parametersToCompare['ServiceName'] = $getTargetResourceResult.ServiceName

    # Only check parameters that we passed in explicitly
    foreach ($parameter in $parametersToCompare.Keys)
    {
        $expectedValue = $parametersToCompare.$parameter
        $actualValue   = $getTargetResourceResult.$parameter

        # We only need the username from credentials to compare
        if ($expectedValue -is [PSCredential])
        {
            $expectedValue = $parametersToCompare.$parameter.UserName
        }

        # Need to check if parameter is part of schema, otherwise ignore all other parameters like verbose
        if ($getTargetResourceResult.Contains($parameter))
        {
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

            Write-Host $parameter ":" $isOutOfCompliance
            if($isOutOfCompliance)
            {
                $compareTargetResource += [pscustomobject] @{
                    Parameter = $parameter
                    Expected  = $expectedValue
                    Actual    = $actualValue
                    Pass      = $false
                }
            }
            else
            {
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

<#
    .SYNOPSIS
        Returns SQL Reporting Services data: configuration object used to initialize and configure
        SQL Reporting Services and the name of the Reports Web application name (changed in SQL 2016)

    .PARAMETER InstanceName
        Name of the SQL Server Reporting Services instance for which the data is being retrieved.

    .NOTES
        We can use WMI to get and set all values for Reporting services instead of relying on the registry
        There are 2 classes that we can use to get most of the information we need. The only thing we cannot
        retrieve is the Product Key, which i believe is in the checksum within the registry and it's encrypted.

        WMI Classes:
            Namespace: root\Microsoft\SqlServer\ReportServer\<InstanceName>\v<Version>, Class: MSReportServer_Instance
            Namespace: root\Microsoft\SqlServer\ReportServer\<InstanceName>\v<Version>\Admin, Class: MSReportServer_ConfigurationSetting
#>
function Get-ReportingServicesCIM
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
    )
    #TODO: Need a try/get here to verify that RS is actually installed.

    $rootReportServerNameSpace = 'ROOT\Microsoft\SqlServer\ReportServer'
    $instanceName = (Get-CimInstance -Namespace $rootReportServerNameSpace -Class __NameSpace).Name

    $rootReportServerInstanceNameSpace = '{0}\{1}' -f $rootReportServerNameSpace, $instanceName
    $instanceVersion = (Get-CimInstance -Namespace $rootReportServerInstanceNameSpace -Class __NameSpace).Name

    $cimMSReportServerInstance = @{
        Namespace = '{0}\{1}\{2}' -f $rootReportServerNameSpace, $instanceName, $instanceVersion
        Class = 'MSReportServer_Instance'
    }
    $cimReportServerInstanceObject = Get-CimInstance @cimMSReportServerInstance

    $cimMSReportServerConfigurationSetting = @{
        Namespace = '{0}\Admin' -f $cimMSReportServerInstance.Namespace
        Class = 'MSReportServer_ConfigurationSetting'
    }
    $cimReportServerConfigurationObject = Get-CimInstance @cimMSReportServerConfigurationSetting

    return @{
        InstanceCIM      = $cimReportServerInstanceObject
        ConfigurationCIM = $cimReportServerConfigurationObject
    }
}

<#
    .SYNOPSIS
        A wrapper for Invoke-CimMethod to be able to handle errors in one place.

    .PARAMETER CimInstance
        The CIM instance object that contains the method to call.

    .PARAMETER MethodName
        The method to call in the CIM Instance object.

    .PARAMETER Arguments
        The arguments that should be
#>
Function Invoke-RsCimMethod
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

    if ($PSBoundParameters.ContainsKey('Arguments'))
    {
        $invokeCimMethodParameters['Arguments'] = $Arguments
    }

    $invokeCimMethodResult = $CimInstance | Invoke-CimMethod @invokeCimMethodParameters
    <#
        Successfully calling the method returns $invokeCimMethodResult.HRESULT -eq 0.
        If an general error occur in the Invoke-CimMethod, like calling a method
        that does not exist, returns $null in $invokeCimMethodResult.
    #>
    if ($invokeCimMethodResult -and $invokeCimMethodResult.HRESULT -ne 0)
    {
        if ($invokeCimMethodResult | Get-Member -Name 'ExtendedErrors')
        {
            <#
                The returned object property ExtendedErrors is an array
                so that needs to be concatenated.
            #>
            $errorMessage = $invokeCimMethodResult.ExtendedErrors -join ';'
        }
        else
        {
            $errorMessage = $invokeCimMethodResult.Error
        }

        throw 'Method {0}() failed with an error. Error: {1} (HRESULT:{2})' -f @(
            $MethodName
            $errorMessage
            $invokeCimMethodResult.HRESULT
        )
    }

    return $invokeCimMethodResult
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
        Write-host 'connecting'
        $databaseServerSQLInstance = Connect-SQL @connectSQLParameters
    }
    catch
    {
        #TODO: Issues connecting, throw error
    }

    return $databaseServerSQLInstance
}
Function Get-SQLServerVersion
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

Function Test-NewSQLInstanceSku
{
    param
    (
        [Parameter(Mandatory)]
        [System.String] $ReportServicesSku
    )

    $sqlVersion = Get-SQLServerVersion
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

Function Assert-NewSQLInstanceSku
{
    #compare sql sku or rs sku, but how do we get rs sku? We do we get edition from fullname and then convert to
    #edition
}

Function Assert-CatalogSkuCompatibility
{

}

Function New-RSSQLCreateDatabase
{

}

Function Set-RSSQLDatabase
{

}

Function New-RSSQLCredentials
{

}

Function Assert-RSDatabaseExist
{

}

Function New-RSSQLUserRights
{

}
Function Set-RSDSN
{

}


Export-ModuleMember -Function *-TargetResource
