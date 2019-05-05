$script:resourceModulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$script:modulesFolderPath = Join-Path -Path $script:resourceModulePath -ChildPath 'Modules'

$script:localizationModulePath = Join-Path -Path $script:modulesFolderPath -ChildPath 'DscResource.LocalizationHelper'
Import-Module -Name (Join-Path -Path $script:localizationModulePath -ChildPath 'DscResource.LocalizationHelper.psm1')

$script:resourceHelperModulePath = Join-Path -Path $script:modulesFolderPath -ChildPath 'DscResource.Common'
Import-Module -Name (Join-Path -Path $script:resourceHelperModulePath -ChildPath 'DscResource.Common.psm1')

$script:localizedData = Get-LocalizedData -ResourceName 'MSFT_SqlRS'


enum ReportServiceSku
{
    None
    SsrsExpress
    SsrsWeb
    SsrsStandard
    SsrsEvaluation
    SsrsDeveloper
    SsrsEnterpriseCore
    SsrsEnterprise
    PbirsEvaluation
    PbirsDeveloper
    PbirsPremium
    PbirsSqlServerEeSa
}

enum SqlServerSku
{
    None
    Express
    Workgroup
    Standard
    Enterprise
    Developer
    Evaluation
    Web
    SBS
    DataCenter
    BusinessIntelligence
    EnterpriseCore
    SqlAzure
}

<#
    .DESCRIPTION
        This class is a set of utilities to identify any issues that may come up when
        running the report services database script. These methods were taken directly
        from a decompile version of the class [SkuUtil] inside of the RSConfigTool.exe.

        List of resources used from RSConfigTool.exe:
         - SkuUtil - Reporting services Sku utility class that you see here
         - SqlServerSkuType - SqlServerSku enum

        List of resources used from Microsoft.ReportingServices.Editions.dll:
         - SkuType - ReportServiceSku enum
#>
class ReportServiceSkuUtils
{
    [ReportServiceSku] $Sku
    [Boolean] $IsLocal

    <#
        .SYNOPSIS
            Initialize with none if no Sku is specified
    #>
    ReportServiceSkuUtils ()
    {
        $this.Sku = [ReportServiceSku] 'None'
    }

    <#
        .SYNOPSIS
            Initialize with sku
    #>
    ReportServiceSkuUtils ([System.String] $Sku, [Boolean] $IsLocal)
    {
        $this.Sku = [ReportServiceSku] $Sku
        $this.IsLocal = [ReportServiceSku] $IsLocal
    }

    <#
        .SYNOPSIS
            Check if Sku has been initialized yet or it's still none
    #>
    [Boolean] HasRSSkuBeenInitialized()
    {
        if ($this.Sku -eq [ReportServiceSku]::None)
        {
            $enumNames = [enum]::GetNames('ReportServiceSku') | Where-Object -Filter {$_ -ne [ReportServiceSku]::None}
            $errorMessage = $script:localizedData.RSSkuTypeNotInitialized -f ($enumNames -join ', ')
            New-InvalidOperationException -Message $errorMessage
        }

        return $true
    }

    <#
        .SYNOPSIS
            Check if Sku is web edition or higher
    #>
    [Boolean] IsWebOrHigher()
    {
        if ($this.HasRSSkuBeenInitialized -and $this.Sku -ne [ReportServiceSku]::SsrsWeb)
        {
            return $this.IsStandardOrHigher()
        }
        return $true
    }

    <#
        .SYNOPSIS
            Check if Sku is standard edition or higher
    #>
    [Boolean] IsStandardOrHigher()
    {
        if ($this.HasRSSkuBeenInitialized -and $this.Sku -ne [ReportServiceSku]::SsrsStandard)
        {
            return $this.IsEvaluationOrDeveloper()
        }
        return $true
    }

    <#
        .SYNOPSIS
            Check if Sku is evaulation or developer edition or higher
    #>
    [Boolean] IsEvaluationOrDeveloper()
    {
        if ($this.HasRSSkuBeenInitialized -and
            $this.Sku -ne [ReportServiceSku]::SsrsEvaluation -and
            $this.Sku -ne [ReportServiceSku]::SsrsDeveloper -and
            $this.Sku -ne [ReportServiceSku]::PbirsEvaluation)
        {
            return $this.Sku -eq [ReportServiceSku]::PbirsDeveloper
        }
        return $true
    }

    <#
        .SYNOPSIS
            Check if Sku is enterprise edition or higher
    #>
    [Boolean] IsEnterpriseOrHigher()
    {
        if ($this.HasRSSkuBeenInitialized -and
            $this.Sku -ne [ReportServiceSku]::SsrsDeveloper -and $this.Sku -ne [ReportServiceSku]::PbirsDeveloper -and
            ($this.Sku -ne [ReportServiceSku]::SsrsEvaluation -and $this.Sku -ne [ReportServiceSku]::PbirsEvaluation) -and
            ($this.Sku -ne [ReportServiceSku]::SsrsEnterprise -and $this.Sku -ne [ReportServiceSku]::SsrsEnterpriseCore -and
             $this.Sku -ne [ReportServiceSku]::PbirsPremium))
        {
            return $this.Sku -eq [ReportServiceSku]::PbirsSqlServerEeSa
        }
        return $true
    }

    <#
        .SYNOPSIS
            Check if Sku is SSRS and not PBIRS
    #>
    [Boolean] IsSSRSSku()
    {
        if ($this.HasRSSkuBeenInitialized -and
            $this.Sku -ne [ReportServiceSku]::SsrsDeveloper -and $this.Sku -ne [ReportServiceSku]::SsrsEnterprise -and
            ($this.Sku -ne [ReportServiceSku]::SsrsEnterpriseCore -and $this.Sku -ne [ReportServiceSku]::SsrsEvaluation) -and
            ($this.Sku -ne [ReportServiceSku]::SsrsExpress -and $this.Sku -ne [ReportServiceSku]::SsrsStandard))
        {
            return $this.Sku -eq [ReportServiceSku]::SsrsWeb
        }
        return $true
    }

    <#
        .SYNOPSIS
            Check if Sku is PBIRS and not SSRS
    #>
    [Boolean] IsPBIRSSku()
    {
        if ($this.HasRSSkuBeenInitialized -and
            $this.Sku -ne [ReportServiceSku]::PbirsDeveloper -and
            $this.Sku -ne [ReportServiceSku]::PbirsEvaluation -and
            $this.Sku -ne [ReportServiceSku]::PbirsPremium)
        {
            return $this.Sku -eq [ReportServiceSku]::PbirsSqlServerEeSa
        }
        return $true
    }

    <#
        .SYNOPSIS
            Check if feature is enabled for a particular Reporting Service Sku

        .DESCRIPTION
            Some features are not available for certain reporting services editions.
            This will determine whether or not a feature is enabled. For instance, if
            you are running a standard reporting service instance (SsrsStandard), then
            you will not be able to build out the reporting services with high availability
            or scale-out
    #>
    [Boolean] IsFeatureEnabled([System.String] $Feature)
    {
        $disabledFeatures = @(
            'Sharepoint'
            'DataAlerting'
            'Crescent'
            'CommentAlerting'
        )

        $standardOrHigherFeatures = @(
            'NonSqlDataSources'
            'OtherSkuDatasources'
            'RemoteDataSources'
            'Caching'
            'ExecutionSnapshots'
            'History'
            'Delivery'
            'Scheduling'
            'Extensibility'
            'Subscriptions'
            'CustomRolesSecurity'
            'ModelItemSecurity'
            'DynamicDrillthrough'
            'EventGeneration'
            'ComponentLibrary'
            'SharedDataset'
            'PowerBIPinning'
        )

        $enterpriseOrHigherFeatures = @(
            'ScaleOut'
            'DataDrivenSubscriptions'
            'NoCpuThrottling'
            'NoMemoryThrottling'
            'KpiItems'
            'MobileReportItems'
            'Branding'
        )

        $webOrHigherFeatures = @(
            'ReportBuilder'
        )

        $pbirsSkuFeatures = @(
            'ReportBuilder'
        )

        if ($Feature -in $standardOrHigherFeatures)
        {
            return $this.IsStandardOrHigher()
        }
        elseif ($Feature -eq 'CustomAuth')
        {
            return $true
        }
        elseif ($Feature -in $disabledFeatures)
        {
            return $false
        }
        elseif ($Feature -in $enterpriseOrHigherFeatures)
        {
            return $this.IsEnterpriseOrHigher()
        }
        elseif ($Feature -in $webOrHigherFeatures)
        {
            return $this.IsWebOrHigher()
        }
        elseif ($Feature -in $pbirsSkuFeatures)
        {
            return $this.IsPBIRSSku()
        }
        else
        {
            # Feature doesn't exist
            return $false
        }
    }

    <#
        .SYNOPSIS
            Convert Reporting Service Sku Full Name edition into the Reporting Service
            Sku Type and set the class sku variable.

        .DESCRIPTION
            This will allow us to get additional information about the different sku types
            and easily reference them for comparison

        .PARAMETER ReportServiceSkuFullName
            The full name of the Reporting service instance. This is retrieved using the
            WMI MSReportServer_Instance Class. (EditionName)

    #>
    [Boolean] SetRSSkuFromString([System.String] $ReportServiceSkuFullName)
    {
        $rsSkuObject = $this.GetRSSkuFromString($ReportServiceSkuFullName)

        if (-not $rsSkuObject)
        {
            $errorMessage = $script:localizedData.RSSkuTypeFullNameNotFound -f ($ReportServiceSkuFullName)
            New-InvalidOperationException -Message $errorMessage
        }

        $this.Sku = [ReportServiceSku]::($rsSkuObject.Sku)

        return $true
    }

    <#
        .SYNOPSIS
            Convert Reporting Service Sku Full Name edition into the Reporting Service
            Sku Type.

        .DESCRIPTION
            This will allow us to get additional information about the different sku types
            and easily reference them for comparison

        .PARAMETER ReportServiceSkuFullName
            The full name of the Reporting service instance. This is retrieved using the
            WMI MSReportServer_Instance Class. (EditionName)

    #>
    [PSCustomObject] GetRSSkuFromString([System.String] $ReportServiceSkuFullName)
    {
        $rsSkuObject = $this.GetRSSkuTypes() | Where-Object -Filter {$_.FullName -eq $ReportServiceSkuFullName}

        if (-not $rsSkuObject)
        {
            if ($ReportServiceSkuFullName -eq 'SQL Server Express with Advanced Services')
            {
                $rsSkuObject = $this.GetRSSkuTypes() | Where-Object -Filter {$_.Sku -eq 'SsrsExpress'}
            }
            elseif ($ReportServiceSkuFullName -eq 'SQL Server Enterprise: Core-Based Licensing')
            {
                $rsSkuObject = $this.GetRSSkuTypes() | Where-Object -Filter {$_.Sku -eq 'SsrsEnterpriseCore'}
            }
        }

        return $rsSkuObject
    }

    <#
        .SYNOPSIS
            Returns all the currently available reporting services sku types

        .DESCRIPTION
            This will return the enture list of sku types for reporting services
            and include all information about that sku, such as command line name,
            short name, guid and more. This can be used for comparison to ensure
            certain features exist or easily identify which version of SSRS or PBIRS
            we are working with
    #>
    [System.Array] GetRSSkuTypes()
    {
        $productTypeSSRS = [PSCustomObject]@{
            FullName            = 'SQL Server Reporting Services'
            ShortName           = 'SSRS'
            DefaultInstanceName = 'SSRS'
        }

        $productTypePBIRS = [PSCustomObject]@{
            FullName            = 'Power BI Report Server'
            ShortName           = 'PBIRS'
            DefaultInstanceName = 'PBIRS'
        }

        $productTypes = @{
            SqlServerReportingServices = $productTypeSSRS
            PowerBiReportServer        = $productTypePBIRS
        }

        $skuTypeSsrsEvaluation = [PSCustomObject]@{
            Sku         = 'SsrsEvaluation'
            CommandLineName = 'EVAL'
            FullName        = 'SQL Server Evaluation'
            PkConfigName    = 'EVAL'
            ShortName       = 'Evaluation'
            Guid            = '18F508AC-AE35-4D36-8C8C-C1AD2B86B9EB'
            Product         = $productTypes.SqlServerReportingServices
            RequiresKey     = $false
            ProductId       = 20
        }

        $skuTypeSsrsDeveloper = [PSCustomObject]@{
            Sku         = 'SsrsDeveloper'
            CommandLineName = 'DEV'
            FullName        = 'SQL Server Developer'
            PkConfigName    = 'DEVELOPER'
            ShortName       = 'Developer'
            Guid            = 'DEE16405-1594-4D48-90BC-DBDAA97F25E0'
            Product         = $productTypes.SqlServerReportingServices
            RequiresKey     = $false
            ProductId       = 21
        }

        $skuTypeSsrsExpress = [PSCustomObject]@{
            Sku         = 'SsrsExpress'
            CommandLineName = 'EXPR'
            FullName        = 'SQL Server Express'
            PkConfigName    = 'EXPRESS_ADVANCED'
            ShortName       = 'Express'
            Guid            = '8CD588A6-811C-40AD-B939-24C63CF6C77C'
            Product         = $productTypes.SqlServerReportingServices
            RequiresKey     = $false
            ProductId       = 22
        }

        $skuTypeSsrsWeb = [PSCustomObject]@{
            Sku         = 'SsrsWeb'
            CommandLineName = 'WEB'
            FullName        = 'SQL Server Web'
            PkConfigName    = 'WEB'
            ShortName       = 'Web'
            Guid            = 'ECD8539D-B652-4141-8CFF-B7674C856D8F'
            Product         = $productTypes.SqlServerReportingServices
            RequiresKey     = $true
            ProductId       = 23
        }

        $skuTypeSsrsStandard = [PSCustomObject]@{
            Sku         = 'SsrsStandard'
            CommandLineName = 'STANDARD'
            FullName        = 'SQL Server Standard'
            PkConfigName    = 'STANDARD'
            ShortName       = 'Standard'
            Guid            = 'F21BFA60-1FAB-42F2-9A8C-4D03C6E98C34'
            Product         = $productTypes.SqlServerReportingServices
            RequiresKey     = $true
            ProductId       = 24
        }

        $skuTypeSsrsEnterprise = [PSCustomObject]@{
            Sku         = 'SsrsEnterprise'
            CommandLineName = 'ENTERPRISE'
            FullName        = 'SQL Server Enterprise'
            PkConfigName    = 'ENTERPRISE'
            ShortName       = 'Enterprise'
            Guid            = '0145C5C1-D24A-4141-9815-2FF76DDF7CEC'
            Product         = $productTypes.SqlServerReportingServices
            RequiresKey     = $true
            ProductId       = 25
        }

        $skuTypeSsrsEnterpriseCore = [PSCustomObject]@{
            Sku         = 'SsrsEnterpriseCore'
            CommandLineName = 'ENTERPRISECORE'
            FullName        = 'SQL Server Enterprise (Core-Based Licensing)'
            PkConfigName    = 'ENTERPRISE CORE'
            ShortName       = 'Enterprise'
            Guid            = 'A399186B-AB71-4251-B343-6681EF496FAF'
            Product         = $productTypes.SqlServerReportingServices
            RequiresKey     = $true
            ProductId       = 26
        }

        $skuTypePbirsEvaluation = [PSCustomObject]@{
            Sku         = 'SsrsEvaluation'
            CommandLineName = 'EVAL'
            FullName        = 'Power BI Report Server - Evaluation'
            PkConfigName    = 'EVAL'
            ShortName       = 'PBIRS Evaluation'
            Guid            = '519A9098-0389-47AB-BA02-25AB120AB706'
            Product         = $productTypes.PowerBiReportServer
            RequiresKey     = $false
            ProductId       = 30
        }

        $skuTypePbirsDeveloper = [PSCustomObject]@{
            Sku     = 'PbirsDeveloper'
            CommandLineName = 'DEV'
            FullName        = 'Power BI Report Server - Developer'
            PkConfigName    = 'DEVELOPER'
            ShortName       = 'PBIRS Developer'
            Guid            = '78426786-77FE-462C-B921-6AE8F1AB9062'
            Product         = $productTypes.PowerBiReportServer
            RequiresKey     = $false
            ProductId       = 31
        }

        $skuTypePbirsPremium = [PSCustomObject]@{
            Sku         = 'PbirsPremium'
            CommandLineName = 'PREMIUM'
            FullName        = 'Power BI Report Server - Premium'
            PkConfigName    = 'PBI PREMIUM'
            ShortName       = 'PBIRS Premium'
            Guid            = '6B2E5C11-3AB7-4F3F-88CD-15FD73BF45AB'
            Product         = $productTypes.PowerBiReportServer
            RequiresKey     = $true
            ProductId       = 32
        }

        $skuTypePbirsSqlServerEeSa = [PSCustomObject]@{
            Sku         = 'PbirsSqlServerEeSa'
            CommandLineName = 'SQLEESA'
            FullName        = 'Power BI Report Server - SQL Server Enterprise with Software Assurance'
            PkConfigName    = 'SQL SERVER EE SA'
            ShortName       = 'PBIRS SQL EESA'
            Guid            = '0361A3D4-EEAA-4033-9033-4F42BE2ED7AF'
            Product         = $productTypes.PowerBiReportServer
            RequiresKey     = $true
            ProductId       = 33
        }

        return @(
            $skuTypeSsrsEvaluation
            $skuTypeSsrsDeveloper
            $skuTypeSsrsExpress
            $skuTypeSsrsWeb
            $skuTypeSsrsEnterprise
            $skuTypeSsrsEnterpriseCore
            $skuTypePbirsEvaluation
            $skuTypePbirsDeveloper
            $skuTypePbirsPremium
            $skuTypePbirsSqlServerEeSa
        )
    }

    <#
        .SYNOPSIS
            Returns the correct SQL Server sku from the SQL Edition value

        .DESCRIPTION
            This will return the the SQL server sku using the SQL Edition.
            It just does a simple wild card comparison to identify the correct
            sku type. This is used to compare if the SSRS/PBIRS instance matches
            the SQL instance

        .PARAMETER SQLEdition
            The SQL Edition parameter retrieved from the Database using the query:
            SELECT SERVERPROPERTY('Edition')
    #>
    [System.String] GetSQLSkuFromSQLEdition([System.String] $SQLEdition)
    {
        switch ($SQLEdition)
        {
            '*EVALUATION*' {
                return [SqlServerSku]::Evaluation
            }
            '*BETA*' {
                return [SqlServerSku]::Evaluation
            }
            '*CORE*' {
                return [SqlServerSku]::EnterpriseCore
            }
            '*DEVELOPER*' {
                return [SqlServerSku]::Developer
            }
            '*SQL AZURE*' {
                return [SqlServerSku]::SqlAzure
            }
            '*WORKGROUP*' {
                return [SqlServerSku]::Workgroup
            }
            '*EXPRESS*' {
                return [SqlServerSku]::Express
            }
            '*WEB*' {
                return [SqlServerSku]::Web
            }
            '*DATA*CENTER*' {
                return [SqlServerSku]::DataCenter
            }
            '*BUSINESS*INTELLIGENCE*' {
                return [SqlServerSku]::BusinessIntelligence
            }
        }

        return [SqlServerSku]::None
    }

    <#
        .SYNOPSIS
            Returns a list of supported and restricted skus based on
            reporting services sku type and sql sku type

        .DESCRIPTION
            This will ensure that we can install the reporting services in the
            database instance or if it's a version mismatch
    #>
    [System.Collections.Hashtable] GetSupportDatabaseSkus()
    {
        $supportedSQLSkus = @()
        $restrictedSQLSkus = @()
        if ($this.HasRSSkuBeenInitialized -and $this.Sku -eq [ReportServiceSku]::SsrsExpress)
        {
            $supportedSQLSkus += [SqlServerSku]::Express
        }

        if ($this.HasRSSkuBeenInitialized -and $this.Sku -eq [ReportServiceSku]::SsrsWeb)
        {
            $supportedSQLSkus += [SqlServerSku]::Web
        }

        $restrictedSkusDeveloperEvaluation = @(
            [ReportServiceSku]::SsrsStandard
            [ReportServiceSku]::SsrsEnterprise
            [ReportServiceSku]::SsrsEnterpriseCore
            [ReportServiceSku]::PbirsPremium
            [ReportServiceSku]::PbirsSqlServerEeSa
        )

        if ($this.HasRSSkuBeenInitialized -and $this.Sku -in $restrictedSkusDeveloperEvaluation)
        {
            $restrictedSQLSkus += [SqlServerSku]::Developer
            $restrictedSQLSkus += [SqlServerSku]::Evaluation
        }

        if ($this.IsStandardOrHigher())
        {
            $restrictedSQLSkus += [SqlServerSku]::Workgroup
            $restrictedSQLSkus += [SqlServerSku]::Express
            $restrictedSQLSkus += [SqlServerSku]::Web
        }

        if ($this.IsEvaluationOrDeveloper() -and $restrictedSQLSkus -contains [SqlServerSku]::Express)
        {
            $restrictedSQLSkus = $restrictedSQLSkus | Where-Object -Filter {$_ -ne [SqlServerSku]::Express}
        }

        return @{
            SupportedSQLSkus = $supportedSQLSkus
            RestrictedSQLSkus = $restrictedSQLSkus
        }
    }

    <#
        .SYNOPSIS
            Returns true of false depending on if we can install reporting services
            to the database instance specified.

        .DESCRIPTION
            This will return whether or not an edition of sql can install the current
            edition of reporting services.

        .PARAMETER SqlSku
            The SQL sku type from the SqlServerSku enum
    #>
    [Boolean] EnsureCorrectEdition([SqlServerSku] $SqlSku)
    {
        if ($this.HasRSSkuBeenInitialized()){
            <#
            IsLocal will need to be set when intializing the class object
            or modifying it after the fact. This is because we need to make
            a sql query and it's best that we don't do any queries
            inside this class
            #>
            if (-not $this.IsStandardOrHigher() -and $this.IsLocal)
            {
                $errorMessage = $script:localizedData.RSandSQLEditionsNotValidLocal -f ($this.Sku, $SqlSku)
                New-InvalidOperationException -Message $errorMessage
            }

            $getSupportedDatabases = $this.GetSupportDatabaseSkus()
            $supportedDatabaseSkus = $getSupportedDatabases.SupportedSQLSkus
            $restrictedDatabaseSkus = $getSupportedDatabases.RestrictedSQLSkus

            if ($supportedDatabaseSkus -and -not $supportedDatabaseSkus -contains $SqlSku)
            {
                $errorMessage = $script:localizedData.RSandSQLEditionsNotValid -f ($this.Sku, $SqlSku)
                New-InvalidOperationException -Message $errorMessage
            }

            if ($restrictedDatabaseSkus -and $restrictedDatabaseSkus -contains $SqlSku)
            {
                $errorMessage = $script:localizedData.RSandSQLEditionsNotValid -f ($this.Sku, $SqlSku)
                New-InvalidOperationException -Message $errorMessage
            }

            return $true
        }

        return $false
    }
}

<#
    .SYNOPSIS
        Initializes a [ReportServiceSkuUtils] object to be used

    .DESCRIPTION
        This will create a [ReportServiceSkuUtils] object so that we can
        import this module and start using the class like normal

    .PARAMETER ReportServicesSku
        The reporting services sku type to set if known
#>
Function Get-ReportServiceSkuUtils
{
    param
    (
        [System.String]
        $ReportServicesSku,

        [System.Boolean]
        $IsLocal = $false
    )

    if ($PSBoundParameters.ContainsKey('ReportServicesSku'))
    {
        return [ReportServiceSkuUtils]::new($ReportServicesSku, $IsLocal)
    }
    else
    {
        return [ReportServiceSkuUtils]::new()
    }
}

Export-ModuleMember -Function Get-ReportServiceSkuUtils
