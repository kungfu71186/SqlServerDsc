$script:resourceModulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$script:modulesFolderPath = Join-Path -Path $script:resourceModulePath -ChildPath 'Modules'

$script:localizationModulePath = Join-Path -Path $script:modulesFolderPath -ChildPath 'DscResource.LocalizationHelper'
Import-Module -Name (Join-Path -Path $script:localizationModulePath -ChildPath 'DscResource.LocalizationHelper.psm1')

$script:resourceHelperModulePath = Join-Path -Path $script:modulesFolderPath -ChildPath 'DscResource.Common'
Import-Module -Name (Join-Path -Path $script:resourceHelperModulePath -ChildPath 'DscResource.Common.psm1')

$script:localizedData = Get-LocalizedData -ResourceName 'MSFT_SqlRS'

<#
    .SYNOPSIS
        Gets the SQL Reporting Services configuration.
#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
    )

    $reportingServicesCIMObjects = Get-ReportingServicesCIM

    $instanceCIMObject      = $reportingServicesCIMObjects.InstanceCIM
    $configurationCIMObject = $reportingServicesCIMObjects.ConfigurationCIM

    $databaseLogonTypes = @('Windows Login', 'SQL Server Account', 'Current User - Integrated Security')
    $smtpAuthenticationTypes = @('No Authentication', 'Username and password (Basic)', 'Report service service account (NTLM)')

    #region Get list of servers in cluster
    $scaleOutServersParameters = @{
        CimInstance = $configurationCIMObject
        MethodName = 'ListReportServersInDatabase'
    }
    $scaleOutServers = $(Invoke-RsCimMethod @scaleOutServersParameters).MachineNames
    #endregion Get list of servers in cluster

    #region Get and separate Report Server URLs
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
        $associatedUrl = ($reportServerUrls.URLS)[$i]
        $reportServeUrlList[$application] += @($associatedUrl)
    }
    #endregion Get and separate Report Server URLs

    $getTargetResourceResult = @{
        InstanceName           = $instanceCIMObject.InstanceName
        Version                = $instanceCIMObject.Version
        EditionName            = $instanceCIMObject.EditionName
        InstallationID         = $configurationCIMObject.InstallationID
        IsInitialized          = $configurationCIMObject.IsInitialized
        ReportServerConfigPath = $configurationCIMObject.PathName

        # Service Account
        ServiceAccountActual = $configurationCIMObject.WindowsServiceIdentityActual
        ServiceAccount       = $configurationCIMObject.WindowsServiceIdentityConfigured

        # Web Service URL
        ReportServerVirtualDirectory = $configurationCIMObject.VirtualDirectoryReportServer # This is the Web Service URL
        ReportServerReservedUrl      = $reportServeUrlList.ReportServerWebService

        # Database
        DatabaseServerName   = $configurationCIMObject.DatabaseServerName
        DatabaseInstanceName = $configurationCIMObject.DatabaseName
        DatabaseLogonAccount = $configurationCIMObject.DatabaseLogonAccount
        DatabaseLogonType    = $databaseLogonTypes[$configurationCIMObject.DatabaseLogonType]

        # Web Portal URL
        ReportsVirtualDirectory = $configurationCIMObject.VirtualDirectoryReportManager # This the Web Portal (Front-end for users)
        ReportsReservedUrl      = $reportServeUrlList.ReportServerWebApp

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
function Set-TargetResource
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
        $ReportServerVirtualDirectory,

        [Parameter()]
        [System.String]
        $ReportsVirtualDirectory,

        [Parameter()]
        [System.String[]]
        $ReportServerReservedUrl,

        [Parameter()]
        [System.String[]]
        $ReportsReservedUrl,

        [Parameter()]
        [System.Boolean]
        $UseSsl,

        [Parameter()]
        [System.Boolean]
        $SuppressRestart
    )

    $reportingServicesData = Get-ReportingServicesData -InstanceName $InstanceName

    if ( $null -ne $reportingServicesData.Configuration )
    {
        if ( $InstanceName -eq 'MSSQLSERVER' )
        {
            if ( [System.String]::IsNullOrEmpty($ReportServerVirtualDirectory) )
            {
                $ReportServerVirtualDirectory = 'ReportServer'
            }

            if ( [System.String]::IsNullOrEmpty($ReportsVirtualDirectory) )
            {
                $ReportsVirtualDirectory = 'Reports'
            }

            $reportingServicesServiceName = 'ReportServer'
            $reportingServicesDatabaseName = 'ReportServer'
        }
        else
        {
            if ( [System.String]::IsNullOrEmpty($ReportServerVirtualDirectory) )
            {
                $ReportServerVirtualDirectory = "ReportServer_$InstanceName"
            }

            if ( [System.String]::IsNullOrEmpty($ReportsVirtualDirectory) )
            {
                $ReportsVirtualDirectory = "Reports_$InstanceName"
            }

            $reportingServicesServiceName = "ReportServer`$$InstanceName"
            $reportingServicesDatabaseName = "ReportServer`$$InstanceName"
        }

        if ( $DatabaseInstanceName -eq 'MSSQLSERVER' )
        {
            $reportingServicesConnection = $DatabaseServerName
        }
        else
        {
            $reportingServicesConnection = "$DatabaseServerName\$DatabaseInstanceName"
        }

        $wmiOperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -Namespace 'root/cimv2' -ErrorAction SilentlyContinue
        if ( $null -eq $wmiOperatingSystem )
        {
            throw 'Unable to find WMI object Win32_OperatingSystem.'
        }

        $language = $wmiOperatingSystem.OSLanguage
        $restartReportingService = $false

        if ( -not $reportingServicesData.Configuration.IsInitialized )
        {
            New-VerboseMessage -Message "Initializing Reporting Services on $DatabaseServerName\$DatabaseInstanceName."

            # We will restart Reporting Services after initialization (unless SuppressRestart is set)
            $restartReportingService = $true

            # If no Report Server reserved URLs have been specified, use the default one.
            if ( $null -eq $ReportServerReservedUrl )
            {
                $ReportServerReservedUrl = @('http://+:80')
            }

            # If no Report Manager/Report Web App reserved URLs have been specified, use the default one.
            if ( $null -eq $ReportsReservedUrl )
            {
                $ReportsReservedUrl = @('http://+:80')
            }

            if ( $reportingServicesData.Configuration.VirtualDirectoryReportServer -ne $ReportServerVirtualDirectory )
            {
                New-VerboseMessage -Message "Setting report server virtual directory on $DatabaseServerName\$DatabaseInstanceName to $ReportServerVirtualDirectory."

                $invokeRsCimMethodParameters = @{
                    CimInstance = $reportingServicesData.Configuration
                    MethodName = 'SetVirtualDirectory'
                    Arguments = @{
                        Application = 'ReportServerWebService'
                        VirtualDirectory = $ReportServerVirtualDirectory
                        Lcid = $language
                    }
                }

                Invoke-RsCimMethod @invokeRsCimMethodParameters

                $ReportServerReservedUrl | ForEach-Object -Process {
                    New-VerboseMessage -Message "Adding report server URL reservation on $DatabaseServerName\$DatabaseInstanceName`: $_."

                    $invokeRsCimMethodParameters = @{
                        CimInstance = $reportingServicesData.Configuration
                        MethodName = 'ReserveUrl'
                        Arguments = @{
                            Application = 'ReportServerWebService'
                            UrlString = $_
                            Lcid = $language
                        }
                    }

                    Invoke-RsCimMethod @invokeRsCimMethodParameters
                }
            }

            if ( $reportingServicesData.Configuration.VirtualDirectoryReportManager -ne $ReportsVirtualDirectory )
            {
                New-VerboseMessage -Message "Setting reports virtual directory on $DatabaseServerName\$DatabaseInstanceName to $ReportServerVirtualDirectory."

                $invokeRsCimMethodParameters = @{
                    CimInstance = $reportingServicesData.Configuration
                    MethodName = 'SetVirtualDirectory'
                    Arguments = @{
                        Application = $reportingServicesData.ReportsApplicationName
                        VirtualDirectory = $ReportsVirtualDirectory
                        Lcid = $language
                    }
                }

                Invoke-RsCimMethod @invokeRsCimMethodParameters

                $ReportsReservedUrl | ForEach-Object -Process {
                    New-VerboseMessage -Message "Adding reports URL reservation on $DatabaseServerName\$DatabaseInstanceName`: $_."

                    $invokeRsCimMethodParameters = @{
                        CimInstance = $reportingServicesData.Configuration
                        MethodName = 'ReserveUrl'
                        Arguments = @{
                            Application = $reportingServicesData.ReportsApplicationName
                            UrlString = $_
                            Lcid = $language
                        }
                    }

                    Invoke-RsCimMethod @invokeRsCimMethodParameters
                }
            }

            $invokeRsCimMethodParameters = @{
                CimInstance = $reportingServicesData.Configuration
                MethodName = 'GenerateDatabaseCreationScript'
                Arguments = @{
                    DatabaseName = $reportingServicesDatabaseName
                    IsSharePointMode = $false
                    Lcid = $language
                }
            }

            $reportingServicesDatabaseScript = Invoke-RsCimMethod @invokeRsCimMethodParameters

            # Determine RS service account
            $reportingServicesServiceAccountUserName = (Get-CimInstance -ClassName Win32_Service | Where-Object -FilterScript {
                    $_.Name -eq $reportingServicesServiceName
                }).StartName

            $invokeRsCimMethodParameters = @{
                CimInstance = $reportingServicesData.Configuration
                MethodName = 'GenerateDatabaseRightsScript'
                Arguments = @{
                    DatabaseName = $reportingServicesDatabaseName
                    UserName = $reportingServicesServiceAccountUserName
                    IsRemote = $false
                    IsWindowsUser = $true
                }
            }

            $reportingServicesDatabaseRightsScript = Invoke-RsCimMethod @invokeRsCimMethodParameters

            <#
                Import-SQLPSModule cmdlet will import SQLPS (SQL 2012/14) or SqlServer module (SQL 2016),
                and if importing SQLPS, change directory back to the original one, since SQLPS changes the
                current directory to SQLSERVER:\ on import.
            #>
            Import-SQLPSModule
            Invoke-Sqlcmd -ServerInstance $reportingServicesConnection -Query $reportingServicesDatabaseScript.Script
            Invoke-Sqlcmd -ServerInstance $reportingServicesConnection -Query $reportingServicesDatabaseRightsScript.Script

            $invokeRsCimMethodParameters = @{
                CimInstance = $reportingServicesData.Configuration
                MethodName = 'SetDatabaseConnection'
                Arguments = @{
                    Server = $reportingServicesConnection
                    DatabaseName = $reportingServicesDatabaseName
                    Username = ''
                    Password = ''

                    <#
                        Can be set to either:
                        0 = Windows
                        1 = Sql Server
                        2 = Windows Service (Integrated Security)

                        When set to 2 the Reporting Server Web service will use
                        either the ASP.NET account or an application pool’s account
                        and the Windows service account to access the report server
                        database.

                        See more in the article
                        https://docs.microsoft.com/en-us/sql/reporting-services/wmi-provider-library-reference/configurationsetting-method-setdatabaseconnection#remarks

                    #>
                    CredentialsType = 2
                }
            }

            Invoke-RsCimMethod @invokeRsCimMethodParameters

            $invokeRsCimMethodParameters = @{
                CimInstance = $reportingServicesData.Configuration
                MethodName = 'InitializeReportServer'
                Arguments = @{
                    InstallationId = $reportingServicesData.Configuration.InstallationID
                }
            }

            Invoke-RsCimMethod @invokeRsCimMethodParameters

            if ( $PSBoundParameters.ContainsKey('UseSsl') -and $UseSsl -ne $currentConfig.UseSsl )
            {
                New-VerboseMessage -Message "Changing value for using SSL to '$UseSsl'."

                $invokeRsCimMethodParameters = @{
                    CimInstance = $reportingServicesData.Configuration
                    MethodName = 'SetSecureConnectionLevel'
                    Arguments = @{
                        Level = @(0,1)[$UseSsl]
                    }
                }

                Invoke-RsCimMethod @invokeRsCimMethodParameters
            }
        }
        else
        {
            $getTargetResourceParameters = @{
                InstanceName         = $InstanceName
                DatabaseServerName   = $DatabaseServerName
                DatabaseInstanceName = $DatabaseInstanceName
            }

            $currentConfig = Get-TargetResource @getTargetResourceParameters

            <#
                SQL Server Reporting Services virtual directories (both
                Report Server and Report Manager/Report Web App) are a
                part of SQL Server Reporting Services URL reservations.

                The default SQL Server Reporting Services URL reservations are:
                http://+:80/ReportServer/ (for Report Server)
                and
                http://+:80/Reports/ (for Report Manager/Report Web App)

                You can get them by running 'netsh http show urlacl' from
                command line.

                In order to change a virtual directory, we first need to remove
                existing URL reservations, change the appropriate virtual directory
                setting and re-add URL reservations, which will then contain the
                new virtual directory.
            #>

            if ( -not [System.String]::IsNullOrEmpty($ReportServerVirtualDirectory) -and ($ReportServerVirtualDirectory -ne $currentConfig.ReportServerVirtualDirectory) )
            {
                New-VerboseMessage -Message "Setting report server virtual directory on $DatabaseServerName\$DatabaseInstanceName to $ReportServerVirtualDirectory."

                $restartReportingService = $true

                $currentConfig.ReportServerReservedUrl | ForEach-Object -Process {
                    $invokeRsCimMethodParameters = @{
                        CimInstance = $reportingServicesData.Configuration
                        MethodName = 'RemoveURL'
                        Arguments = @{
                            Application = 'ReportServerWebService'
                            UrlString = $_
                            Lcid = $language
                        }
                    }

                    Invoke-RsCimMethod @invokeRsCimMethodParameters
                }

                $invokeRsCimMethodParameters = @{
                    CimInstance = $reportingServicesData.Configuration
                    MethodName = 'SetVirtualDirectory'
                    Arguments = @{
                        Application = 'ReportServerWebService'
                        VirtualDirectory = $ReportServerVirtualDirectory
                        Lcid = $language
                    }
                }

                Invoke-RsCimMethod @invokeRsCimMethodParameters

                $currentConfig.ReportServerReservedUrl | ForEach-Object -Process {
                    $invokeRsCimMethodParameters = @{
                        CimInstance = $reportingServicesData.Configuration
                        MethodName = 'ReserveUrl'
                        Arguments = @{
                            Application = 'ReportServerWebService'
                            UrlString = $_
                            Lcid = $language
                        }
                    }

                    Invoke-RsCimMethod @invokeRsCimMethodParameters
                }
            }

            if ( -not [System.String]::IsNullOrEmpty($ReportsVirtualDirectory) -and ($ReportsVirtualDirectory -ne $currentConfig.ReportsVirtualDirectory) )
            {
                New-VerboseMessage -Message "Setting reports virtual directory on $DatabaseServerName\$DatabaseInstanceName to $ReportServerVirtualDirectory."

                $restartReportingService = $true

                $currentConfig.ReportsReservedUrl | ForEach-Object -Process {
                    $invokeRsCimMethodParameters = @{
                        CimInstance = $reportingServicesData.Configuration
                        MethodName = 'RemoveURL'
                        Arguments = @{
                            Application = $reportingServicesData.ReportsApplicationName
                            UrlString = $_
                            Lcid = $language
                        }
                    }

                    Invoke-RsCimMethod @invokeRsCimMethodParameters
                }

                $invokeRsCimMethodParameters = @{
                    CimInstance = $reportingServicesData.Configuration
                    MethodName = 'SetVirtualDirectory'
                    Arguments = @{
                        Application = $reportingServicesData.ReportsApplicationName
                        VirtualDirectory = $ReportsVirtualDirectory
                        Lcid = $language
                    }
                }

                Invoke-RsCimMethod @invokeRsCimMethodParameters

                $currentConfig.ReportsReservedUrl | ForEach-Object -Process {
                    $invokeRsCimMethodParameters = @{
                        CimInstance = $reportingServicesData.Configuration
                        MethodName = 'ReserveUrl'
                        Arguments = @{
                            Application = $reportingServicesData.ReportsApplicationName
                            UrlString = $_
                            Lcid = $language
                        }
                    }

                    Invoke-RsCimMethod @invokeRsCimMethodParameters
                }
            }

            $compareParameters = @{
                ReferenceObject  = $currentConfig.ReportServerReservedUrl
                DifferenceObject = $ReportServerReservedUrl
            }

            if ( ($null -ne $ReportServerReservedUrl) -and ($null -ne (Compare-Object @compareParameters)) )
            {
                $restartReportingService = $true

                $currentConfig.ReportServerReservedUrl | ForEach-Object -Process {
                    $invokeRsCimMethodParameters = @{
                        CimInstance = $reportingServicesData.Configuration
                        MethodName = 'RemoveURL'
                        Arguments = @{
                            Application = 'ReportServerWebService'
                            UrlString = $_
                            Lcid = $language
                        }
                    }

                    Invoke-RsCimMethod @invokeRsCimMethodParameters
                }

                $ReportServerReservedUrl | ForEach-Object -Process {
                    New-VerboseMessage -Message "Adding report server URL reservation on $DatabaseServerName\$DatabaseInstanceName`: $_."
                    $invokeRsCimMethodParameters = @{
                        CimInstance = $reportingServicesData.Configuration
                        MethodName = 'ReserveUrl'
                        Arguments = @{
                            Application = 'ReportServerWebService'
                            UrlString = $_
                            Lcid = $language
                        }
                    }

                    Invoke-RsCimMethod @invokeRsCimMethodParameters
                }
            }

            $compareParameters = @{
                ReferenceObject  = $currentConfig.ReportsReservedUrl
                DifferenceObject = $ReportsReservedUrl
            }

            if ( ($null -ne $ReportsReservedUrl) -and ($null -ne (Compare-Object @compareParameters)) )
            {
                $restartReportingService = $true

                $currentConfig.ReportsReservedUrl | ForEach-Object -Process {
                    $invokeRsCimMethodParameters = @{
                        CimInstance = $reportingServicesData.Configuration
                        MethodName = 'RemoveURL'
                        Arguments = @{
                            Application = $reportingServicesData.ReportsApplicationName
                            UrlString = $_
                            Lcid = $language
                        }
                    }

                    Invoke-RsCimMethod @invokeRsCimMethodParameters
                }

                $ReportsReservedUrl | ForEach-Object -Process {
                    New-VerboseMessage -Message "Adding reports URL reservation on $DatabaseServerName\$DatabaseInstanceName`: $_."

                    $invokeRsCimMethodParameters = @{
                        CimInstance = $reportingServicesData.Configuration
                        MethodName = 'ReserveUrl'
                        Arguments = @{
                            Application = $reportingServicesData.ReportsApplicationName
                            UrlString = $_
                            Lcid = $language
                        }
                    }

                    Invoke-RsCimMethod @invokeRsCimMethodParameters
                }
            }

            if ( $PSBoundParameters.ContainsKey('UseSsl') -and $UseSsl -ne $currentConfig.UseSsl )
            {
                New-VerboseMessage -Message "Changing value for using SSL to '$UseSsl'."

                $restartReportingService = $true

                $invokeRsCimMethodParameters = @{
                    CimInstance = $reportingServicesData.Configuration
                    MethodName = 'SetSecureConnectionLevel'
                    Arguments = @{
                        Level = @(0,1)[$UseSsl]
                    }
                }

                Invoke-RsCimMethod @invokeRsCimMethodParameters
            }
        }

        if ( $restartReportingService -and $SuppressRestart )
        {
            Write-Warning -Message $script:localizedData.SuppressRestart
        }
        elseif ( $restartReportingService -and (-not $SuppressRestart) )
        {
            Write-Verbose -Message $script:localizedData.Restart
            Restart-ReportingServicesService -SQLInstanceName $InstanceName -WaitTime 30
        }
    }

    if ( -not (Test-TargetResource @PSBoundParameters) )
    {
        $errorMessage = $script:localizedData.TestFailedAfterSet
        New-InvalidResultException -Message $errorMessage
    }
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
function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
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
        $ReportServerVirtualDirectory,

        [Parameter()]
        [System.String]
        $ReportsVirtualDirectory,

        [Parameter()]
        [System.String[]]
        $ReportServerReservedUrl,

        [Parameter()]
        [System.String[]]
        $ReportsReservedUrl,

        [Parameter()]
        [System.Boolean]
        $UseSsl,

        [Parameter()]
        [System.Boolean]
        $SuppressRestart
    )

    $result = $true

    $getTargetResourceParameters = @{
        InstanceName         = $InstanceName
        DatabaseServerName   = $DatabaseServerName
        DatabaseInstanceName = $DatabaseInstanceName
    }

    $currentConfig = Get-TargetResource @getTargetResourceParameters

    if ( -not $currentConfig.IsInitialized )
    {
        New-VerboseMessage -Message "Reporting services $DatabaseServerName\$DatabaseInstanceName are not initialized."
        $result = $false
    }

    if ( -not [System.String]::IsNullOrEmpty($ReportServerVirtualDirectory) -and ($ReportServerVirtualDirectory -ne $currentConfig.ReportServerVirtualDirectory) )
    {
        New-VerboseMessage -Message "Report server virtual directory on $DatabaseServerName\$DatabaseInstanceName is $($currentConfig.ReportServerVirtualDir), should be $ReportServerVirtualDirectory."
        $result = $false
    }

    if ( -not [System.String]::IsNullOrEmpty($ReportsVirtualDirectory) -and ($ReportsVirtualDirectory -ne $currentConfig.ReportsVirtualDirectory) )
    {
        New-VerboseMessage -Message "Reports virtual directory on $DatabaseServerName\$DatabaseInstanceName is $($currentConfig.ReportsVirtualDir), should be $ReportsVirtualDirectory."
        $result = $false
    }

    $compareParameters = @{
        ReferenceObject  = $currentConfig.ReportServerReservedUrl
        DifferenceObject = $ReportServerReservedUrl
    }

    if ( ($null -ne $ReportServerReservedUrl) -and ($null -ne (Compare-Object @compareParameters)) )
    {
        New-VerboseMessage -Message "Report server reserved URLs on $DatabaseServerName\$DatabaseInstanceName are $($currentConfig.ReportServerReservedUrl -join ', '), should be $($ReportServerReservedUrl -join ', ')."
        $result = $false
    }

    $compareParameters = @{
        ReferenceObject  = $currentConfig.ReportsReservedUrl
        DifferenceObject = $ReportsReservedUrl
    }

    if ( ($null -ne $ReportsReservedUrl) -and ($null -ne (Compare-Object @compareParameters)) )
    {
        New-VerboseMessage -Message "Reports reserved URLs on $DatabaseServerName\$DatabaseInstanceName are $($currentConfig.ReportsReservedUrl -join ', ')), should be $($ReportsReservedUrl -join ', ')."
        $result = $false
    }

    if ( $PSBoundParameters.ContainsKey('UseSsl') -and $UseSsl -ne $currentConfig.UseSsl )
    {
        New-VerboseMessage -Message "The value for using SSL are not in desired state. Should be '$UseSsl', but was '$($currentConfig.UseSsl)'."
        $result = $false
    }

    $result
}

function Compare-TargetResourceState
{

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
function Invoke-RsCimMethod
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

Export-ModuleMember -Function *-TargetResource
