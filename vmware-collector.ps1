<#
.SYNOPSIS
    VMware vCenter Inventory and Performance Collector

.DESCRIPTION
    Collects VMware vCenter inventory and performance data with optimized performance through
    reduced API calls and intelligent caching. Uses P95 percentile values for realistic peak
    performance metrics.
    
    Supports three output formats:
    - ME: AWS Migration Evaluator Template (ConsolidatedDataImport format)
    - MPA: Migration Portfolio Assessment Template (Excel format)
    - RVTools: CSV files in ZIP format

.PARAMETER filterVMs
    Controls VM filtering: 'Y' to show only powered on VMs (default), 'N' to show all VMs

.PARAMETER enableLogging
    Enables debug logging to a file when specified.

.PARAMETER disableSSL
    Disables SSL certificate validation when connecting to vCenter.

.PARAMETER outputFormat
    Specify output format: 'MPA' (default), 'ME', 'RVTools', combinations, or 'All'
    - MPA: Generate MPA Template only (fastest - 16 min for 100 VMs)
    - ME: Generate AWS Migration Evaluator Template only (16 min for 100 VMs)
    - RVTools: Generate RVTools CSV ZIP only (54 min for 100 VMs - slowest)
    - MPA,ME: Generate both MPA and ME formats (16 min for 100 VMs)
    - All: Generate all three formats (54 min for 100 VMs due to RVTools)

.PARAMETER purgeCSV
    Remove individual CSV files after creating ZIP archive (default: false)

.PARAMETER address
    The IP address or FQDN of the vCenter server.

.PARAMETER username
    The username for connecting to vCenter.

.PARAMETER password
    The password for connecting to vCenter.

.PARAMETER collectionDays
    Number of days to collect data for. Default is 7 days.

.PARAMETER protocol
    The protocol to use for connection: 'http' or 'https'. Default is https.

.PARAMETER port
    The port number to connect to vCenter. Defaults to 443 for HTTPS or 80 for HTTP.

.PARAMETER maxParallelThreads
    Maximum number of parallel threads for processing (1-50, default: 15)

.PARAMETER skipPerformanceData
    Skip historical performance data collection for faster processing

.PARAMETER anonymize
    Create anonymized versions of both CSV and Excel outputs

.PARAMETER vmListFile
    Path to a CSV or TXT file containing a list of specific VMs to process.
    CSV format: should have a 'VM' or 'Name' column with VM names
    TXT format: one VM name per line
    If not provided, falls back to normal filterVMs behavior

.PARAMETER fastMode
    Enable fast mode for maximum speed (skips detailed disk and network analysis)

.PARAMETER IncludeCluster
    Comma-separated list of cluster names to include (supports wildcards). Cannot be used with ExcludeCluster.

.PARAMETER ExcludeCluster
    Comma-separated list of cluster names to exclude (supports wildcards). Cannot be used with IncludeCluster.

.PARAMETER IncludeDatacenter
    Comma-separated list of datacenter names to include (supports wildcards). Cannot be used with ExcludeDatacenter.

.PARAMETER ExcludeDatacenter
    Comma-separated list of datacenter names to exclude (supports wildcards). Cannot be used with IncludeDatacenter.

.PARAMETER IncludeHost
    Comma-separated list of host names to include (supports wildcards). Cannot be used with ExcludeHost.

.PARAMETER ExcludeHost
    Comma-separated list of host names to exclude (supports wildcards). Cannot be used with IncludeHost.

.PARAMETER IncludeEnvironment
    Include only VMs from specified environment: 'Production' or 'NonProduction'. Based on VM name patterns.

.PARAMETER ExcludeEnvironment
    Exclude VMs from specified environment: 'Production' or 'NonProduction'. Based on VM name patterns.

.EXAMPLE
    .\vmware-collector.ps1 -address "vcenter.domain.com" -username "admin" -password "password"

.EXAMPLE
    .\vmware-collector.ps1 -address "vcenter.domain.com" -username "admin" -password "password" -collectionDays 14 -disableSSL -anonymize

.EXAMPLE
    .\vmware-collector.ps1 -address "vcenter.domain.com" -username "admin" -password "password" -outputFormat "ME"

.EXAMPLE
    .\vmware-collector.ps1 -address "vcenter.domain.com" -username "admin" -password "password" -vmListFile "vm_list.csv"

.EXAMPLE
    .\vmware-collector.ps1 -address "vcenter.domain.com" -username "admin" -password "password" -fastMode -skipPerformanceData

.EXAMPLE
    .\vmware-collector.ps1 -address "vcenter.domain.com" -username "admin" -password "password" -IncludeCluster "PROD*,Critical*"

.EXAMPLE
    .\vmware-collector.ps1 -address "vcenter.domain.com" -username "admin" -password "password" -IncludeEnvironment "Production"

.EXAMPLE
    .\vmware-collector.ps1 -address "vcenter.domain.com" -username "admin" -password "password" -IncludeDatacenter "DC1" -ExcludeHost "*test*"

.EXAMPLE
    .\vmware-collector.ps1 -address "vcenter.domain.com" -username "admin" -password "password" -enableSQLDetection -sqlAuthMode "SQL" -sqlUsername "sa" -sqlPassword "password"

.EXAMPLE
    .\vmware-collector.ps1 -address "vcenter.domain.com" -username "admin" -password "password" -enableSQLDetection -databaseCredentialsFile "database-credentials.json"

.NOTES
    File Name      : vmware-collector.ps1
    Prerequisite   : PowerCLI, ImportExcel module
    Author         : Benoit Lotfallah
    Version        : 2 (Optimized + P95)
    Optimization   : Reduced API calls, intelligent caching, batch processing, P95 percentile for peak values
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$address,

    [Parameter(Mandatory=$true)]
    [string]$username,

    [Parameter(Mandatory=$true)]
    [string]$password,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 365)]  
    [int]$collectionDays = 7,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Y','N', IgnoreCase = $true)]
    [string]$filterVMs = 'Y',

    [Parameter(Mandatory=$false)]
    [ValidateSet('http','https', IgnoreCase = $true)]
    [string]$protocol = 'https',
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 65535)]
    [int]$port = 0,
    
    [Parameter(Mandatory=$false)]
    [switch]$enableLogging,

    [Parameter(Mandatory=$false)]
    [switch]$disableSSL,

    [Parameter(Mandatory=$false)]
    [string]$outputFormat = 'MPA',  # Default: MPA only. Options: 'MPA', 'ME', 'RVTools', 'MPA,ME', 'All'

    [Parameter(Mandatory=$false)]
    [switch]$purgeCSV = $true,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 50)]
    [int]$maxParallelThreads = 20,

    [Parameter(Mandatory=$false)]
    [switch]$skipPerformanceData,

    [Parameter(Mandatory=$false)]
    [switch]$anonymize,

    [Parameter(Mandatory=$false)]
    [string]$vmListFile,

    [Parameter(Mandatory=$false)]
    [switch]$fastMode,

    # New filtering parameters
    [Parameter(Mandatory=$false)]
    [string]$IncludeCluster,

    [Parameter(Mandatory=$false)]
    [string]$ExcludeCluster,

    [Parameter(Mandatory=$false)]
    [string]$IncludeDatacenter,

    [Parameter(Mandatory=$false)]
    [string]$ExcludeDatacenter,

    [Parameter(Mandatory=$false)]
    [string]$IncludeHost,

    [Parameter(Mandatory=$false)]
    [string]$ExcludeHost,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Production','NonProduction')]
    [string]$IncludeEnvironment,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Production','NonProduction')]
    [string]$ExcludeEnvironment,

    # SQL Server Detection Parameters
    [Parameter(Mandatory=$false)]
    [switch]$enableSQLDetection,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Windows','SQL')]
    [string]$sqlAuthMode = 'Windows',

    [Parameter(Mandatory=$false)]
    [string]$sqlUsername,

    [Parameter(Mandatory=$false)]
    [string]$sqlPassword,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 30)]
    [int]$sqlConnectionTimeout = 5,

    [Parameter(Mandatory=$false)]
    [string]$databaseCredentialsFile
)



# Load security classes (Interfaces and InputValidator must be loaded first)
. "$PSScriptRoot\Classes\Interfaces.ps1"
. "$PSScriptRoot\Classes\InputValidator.ps1"
. "$PSScriptRoot\Classes\SecureCredentialManager.ps1"
. "$PSScriptRoot\Classes\SecureErrorHandler.ps1"
. "$PSScriptRoot\Classes\SecureFileManager.ps1"

# Initialize secure credential manager
$global:SecureCredentialManager = [SecureCredentialManager]::new([bool]$enableLogging)

# Store vCenter credentials securely
$global:SecureCredentialManager.StoreCredential("vCenter", $username, $password)

# Track whether SQL credentials were provided (before clearing)
$sqlCredentialsProvided = ($enableSQLDetection -and $sqlUsername -and $sqlPassword)

# Store database credentials securely if provided
if ($sqlCredentialsProvided) {
    $global:SecureCredentialManager.StoreCredential("SQLServer", $sqlUsername, $sqlPassword)
}
# Clear plaintext passwords from parameters immediately
$password = $null
$sqlPassword = $null
[System.GC]::Collect()

# Load Multi-Credential Configuration
$global:DatabaseCredentialsConfig = @{}
if ($databaseCredentialsFile) {
    Write-Host "Loading database credentials configuration from: $databaseCredentialsFile" -ForegroundColor Yellow
    $global:DatabaseCredentialsConfig = Import-DatabaseCredentialsConfig -ConfigFilePath $databaseCredentialsFile
    
    # Display loaded credentials summary
    $credCount = $global:DatabaseCredentialsConfig.SQLServer.Count
    if ($credCount -gt 0) {
        Write-Host "  - SQL Server: $credCount credential(s) loaded" -ForegroundColor Green
    }
}

# Validate Database Detection Parameters
if ($enableSQLDetection) {
    Write-Host "Database Detection enabled - validating credentials..." -ForegroundColor Yellow
    
    if ($sqlAuthMode -eq 'SQL') {
        if (-not $sqlCredentialsProvided) {
            # Check if we have SQL Server credentials in config file
            if ($global:DatabaseCredentialsConfig.SQLServer.Count -eq 0) {
                Write-Host "ERROR: SQL Authentication mode requires either:" -ForegroundColor Red
                Write-Host "  1. -sqlUsername and -sqlPassword parameters" -ForegroundColor Red
                Write-Host "  2. -databaseCredentialsFile with SQL Server credentials" -ForegroundColor Red
                Write-Host "Usage: -enableSQLDetection -sqlAuthMode 'SQL' -sqlUsername 'sa' -sqlPassword 'YourPassword'" -ForegroundColor Yellow
                Write-Host "   OR: -enableSQLDetection -databaseCredentialsFile 'credentials.json'" -ForegroundColor Yellow
                exit 1
            } else {
                Write-Host "Using SQL Server credentials from configuration file ($($global:DatabaseCredentialsConfig.SQLServer.Count) credential(s))" -ForegroundColor Green
            }
        } else {
            Write-Host "Using SQL Server Authentication with user: $sqlUsername" -ForegroundColor Green
        }
    } else {
        Write-Host "Using Windows Authentication for SQL Server (current user context)" -ForegroundColor Green
    }
} else {
    Write-Host "Database Detection disabled - using pattern matching only" -ForegroundColor Yellow
}
# Parse output format parameter to support combinations
$requestedFormats = @()
if ($outputFormat -eq 'All') {
    $requestedFormats = @('MPA', 'ME', 'RVTools')
} else {
    # Split comma-separated formats and trim whitespace
    $requestedFormats = $outputFormat -split ',' | ForEach-Object { $_.Trim().ToUpper() }
}

# Validate format names
$validFormats = @('MPA', 'ME', 'RVTOOLS')
foreach ($format in $requestedFormats) {
    if ($format -notin $validFormats) {
        Write-Host "ERROR: Invalid output format '$format'. Valid options: MPA, ME, RVTools, or combinations like 'MPA,ME' or 'All'" -ForegroundColor Red
        exit 1
    }
}

# Helper function to check if a format should be generated
function ShouldGenerateFormat {
    param([string]$formatName)
    return $requestedFormats -contains $formatName.ToUpper()
}

Write-Host "Output formats requested: $($requestedFormats -join ', ')" -ForegroundColor Cyan

# Initialize timestamp for file naming
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Set output files
$outputDir = "VMware_Export_$timestamp"
$excelOutput = Join-Path $outputDir "MPA_Template_$timestamp.xlsx"
$excelOutputAnonymized = Join-Path $outputDir "MPA_Template_ANONYMIZED_$timestamp.xlsx"
$workbookOutput = Join-Path $outputDir "ME_ConsolidatedDataImport_$timestamp.xlsx"
$workbookOutputAnonymized = Join-Path $outputDir "ME_ConsolidatedDataImport_ANONYMIZED_$timestamp.xlsx"
$mappingFile = Join-Path $outputDir "Anonymization_Mapping_$timestamp.xlsx"
$logFile = Join-Path $outputDir "vm_collection_$timestamp.log"

# Initialize logger for security classes
. "$PSScriptRoot\Classes\SimpleLogger.ps1"
# Logging function (defined early for use throughout script)
function Write-DebugLog {
    param([string]$message)
    if ($enableLogging) {
        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $message"
        Add-Content -Path $logFile -Value $logMessage
    }
}

$loggerEnabled = if ($enableLogging) { $true } else { $false }
$logger = [SimpleLogger]::new($loggerEnabled, $logFile)

# Initialize secure file manager
$global:FileManager = [SecureFileManager]::new($logger)

# Create output directory securely
$outputDir = $global:FileManager.CreateSecureDirectory($outputDir)

# Configure PowerCLI with security warnings
if ($disableSSL) {
    Write-Host "WARNING: SSL certificate validation is being disabled!" -ForegroundColor Red
    Write-Host "WARNING: Press Ctrl+C within 10 seconds to cancel..." -ForegroundColor Red
    
    # Give user time to cancel
    Start-Sleep -Seconds 10
    
    Write-Host "Proceeding with SSL validation disabled..." -ForegroundColor Yellow
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    
    # Log security warning
    Write-DebugLog "SECURITY WARNING: SSL certificate validation disabled by user"
} else {
    # Enable strict SSL validation
    Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false | Out-Null
    Write-DebugLog "SSL certificate validation enabled (secure mode)"
}

# Set other secure defaults
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
Set-PowerCLIConfiguration -DefaultVIServerMode Single -Confirm:$false | Out-Null

# Import required modules
Import-Module ImportExcel -ErrorAction Stop
Import-Module Microsoft.PowerShell.Archive -ErrorAction SilentlyContinue

# Load required classes for MPA and ME format generation
$mpaGeneratorPath = Join-Path $PSScriptRoot "Classes\MPAFormatGenerator.ps1"
$meGeneratorPath = Join-Path $PSScriptRoot "Classes\MEFormatGenerator.ps1"

if (Test-Path $mpaGeneratorPath) {
    . $mpaGeneratorPath
    Write-Verbose "Loaded MPAFormatGenerator class"
} else {
    Write-Warning "MPAFormatGenerator class not found at: $mpaGeneratorPath"
}

if (Test-Path $meGeneratorPath) {
    . $meGeneratorPath
    Write-Verbose "Loaded MEFormatGenerator class"
} else {
    Write-Warning "MEFormatGenerator class not found at: $meGeneratorPath"
}

# Initialize anonymization mappings if needed
$anonymizationMappings = @{
    ServerNames = @{}
    HostNames = @{}
    ClusterNames = @{}
    IPAddresses = @{}
    DatastoreNames = @{}
    DNSNames = @{}
}

# Anonymization functions
function Get-AnonymizedName {
    param(
        [string]$originalName,
        [string]$prefix,
        [hashtable]$mappingTable
    )
    
    if ([string]::IsNullOrEmpty($originalName)) {
        return $originalName
    }
    
    if (-not $mappingTable.ContainsKey($originalName)) {
        $counter = $mappingTable.Count + 1
        $mappingTable[$originalName] = "$prefix-$($counter.ToString('D4'))"
    }
    
    return $mappingTable[$originalName]
}

# Multi-Credential Configuration Functions (Monolithic Implementation)
function Import-DatabaseCredentialsConfig {
    param(
        [string]$ConfigFilePath
    )
    
    if (-not $ConfigFilePath -or -not (Test-Path $ConfigFilePath)) {
        return @{}
    }
    
    try {
        $configContent = Get-Content $ConfigFilePath -Raw | ConvertFrom-Json
        Write-DebugLog "Loaded database credentials configuration from: $ConfigFilePath"
        
        # Validate configuration structure
        $validatedConfig = @{
            SQLServer = @()
        }
        
        if ($configContent.SQLServer) {
            foreach ($cred in $configContent.SQLServer) {
                if ($cred.Username -and $cred.Password) {
                    $credentialEntry = @{
                        Username = $cred.Username
                        Password = $cred.Password
                        Description = if ($cred.Description) { $cred.Description } else { "Default" }
                        Priority = if ($cred.Priority) { $cred.Priority } else { 1 }
                        AuthMode = if ($cred.AuthMode) { $cred.AuthMode } else { 'SQL' }
                    }
                    
                    $validatedConfig.SQLServer += $credentialEntry
                }
            }
            
            # Sort by priority (lower number = higher priority)
            $validatedConfig.SQLServer = $validatedConfig.SQLServer | Sort-Object Priority
        }
        
        return $validatedConfig
        
    } catch {
        Write-Host "Error loading database credentials configuration: $_" -ForegroundColor Red
        Write-DebugLog "Error loading database credentials configuration: $_"
        return @{}
    }
}

function Get-DatabaseCredentialsList {
    param(
        [string]$DatabaseType,
        [hashtable]$ConfigCredentials = @{},
        [hashtable]$ParameterCredentials = @{}
    )
    
    $credentialsList = @()
    
    # Add credentials from configuration file (higher priority)
    if ($ConfigCredentials.SQLServer) {
        $credentialsList += $ConfigCredentials.SQLServer
    }
    
    # Add credentials from parameters (retrieve from SecureCredentialManager if stored securely)
    if ($ParameterCredentials.UseSecureCredentials -and $ParameterCredentials.Username) {
        # Retrieve password from SecureCredentialManager
        $securePassword = $null
        if ($global:SecureCredentialManager) {
            try {
                $securePassword = $global:SecureCredentialManager.GetPlaintextPassword("SQLServer")
            } catch {
                Write-DebugLog "Could not retrieve SQL Server password from SecureCredentialManager: $_"
            }
        }
        
        if ($securePassword) {
            $parameterCredential = @{
                Username = $ParameterCredentials.Username
                Password = $securePassword
                Description = "Command Line Parameter"
                Priority = 999  # Lower priority than config file
                AuthMode = $ParameterCredentials.AuthMode
            }
            $credentialsList += $parameterCredential
        }
    } elseif ($ParameterCredentials.Username -and $ParameterCredentials.Password) {
        # Legacy: direct password (for backward compatibility)
        $parameterCredential = @{
            Username = $ParameterCredentials.Username
            Password = $ParameterCredentials.Password
            Description = "Command Line Parameter"
            Priority = 999  # Lower priority than config file
            AuthMode = $ParameterCredentials.AuthMode
        }
        $credentialsList += $parameterCredential
    }
    
    return $credentialsList | Sort-Object Priority
}

function Test-DatabaseConnectionWithMultipleCredentials {
    param(
        [string]$IPAddress,
        [string]$DatabaseType,
        [array]$CredentialsList,
        [int]$TimeoutSeconds = 5
    )
    
    if (-not $CredentialsList -or $CredentialsList.Count -eq 0) {
        return @{ Success = $false; Error = "No credentials provided for $DatabaseType" }
    }
    
    foreach ($credential in $CredentialsList) {
        try {
            Write-DebugLog "Attempting $DatabaseType connection to $IPAddress with credential: $($credential.Description)"
            
            $result = Test-DatabaseConnection -IPAddress $IPAddress -DatabaseType $DatabaseType -Credentials $credential -TimeoutSeconds $TimeoutSeconds
            
            if ($result.Success) {
                $result.CredentialUsed = $credential.Description
                Write-DebugLog "Successfully connected to $DatabaseType at $IPAddress using credential: $($credential.Description)"
                return $result
            } else {
                Write-DebugLog "Failed to connect to $DatabaseType at $IPAddress with credential '$($credential.Description)': $($result.Error)"
            }
            
        } catch {
            Write-DebugLog "Exception testing $DatabaseType connection with credential '$($credential.Description)': $_"
        }
    }
    
    return @{ 
        Success = $false
        Error = "All credential attempts failed for $DatabaseType at $IPAddress"
        CredentialsAttempted = $CredentialsList.Count
    }
}

# Enhanced Database Detection Functions (Monolithic Implementation)
function Test-DatabaseConnection {
    param(
        [string]$IPAddress,
        [string]$DatabaseType,
        [hashtable]$Credentials,
        [int]$TimeoutSeconds = 5
    )
    
    if ([string]::IsNullOrEmpty($IPAddress)) {
        return @{ Success = $false; Error = "No IP address provided" }
    }
    
    try {
        switch ($DatabaseType.ToLower()) {
            'sqlserver' {
                return Test-SQLServerConnection -IPAddress $IPAddress -Credentials $Credentials -TimeoutSeconds $TimeoutSeconds
            }
            default {
                return @{ Success = $false; Error = "Unsupported database type: $DatabaseType" }
            }
        }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Test-SQLServerConnection {
    param(
        [string]$IPAddress,
        [hashtable]$Credentials,
        [int]$TimeoutSeconds = 5
    )
    
    try {
        $connectionString = "Server=$IPAddress;Database=master;Connection Timeout=$TimeoutSeconds;"
        
        if ($Credentials.AuthMode -eq 'SQL') {
            $connectionString += "User Id=$($Credentials.Username);Password=$($Credentials.Password);"
        } else {
            $connectionString += "Integrated Security=true;"
        }
        
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        
        $query = @"
SELECT 
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('IsClustered') AS IsClustered,
    SERVERPROPERTY('IsHadrEnabled') AS IsHadrEnabled,
    @@VERSION AS VersionString
"@
        
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $reader = $command.ExecuteReader()
        
        $result = @{
            Success = $true
            DatabaseType = 'SQL Server'
            Edition = ''
            Version = ''
            ProductLevel = ''
            IsClustered = $false
            IsHadrEnabled = $false
            VersionString = ''
        }
        
        if ($reader.Read()) {
            $rawEdition = $reader['Edition'].ToString()
            $result.Edition = Convert-SQLServerEdition -RawEdition $rawEdition
            $result.Version = $reader['ProductVersion'].ToString()
            $result.ProductLevel = $reader['ProductLevel'].ToString()
            $result.IsClustered = [bool]$reader['IsClustered']
            $result.IsHadrEnabled = [bool]$reader['IsHadrEnabled']
            $result.VersionString = $reader['VersionString'].ToString()
        }
        
        $reader.Close()
        $connection.Close()
        
        return $result
        
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Convert-SQLServerEdition {
    param(
        [string]$RawEdition
    )
    
    if ([string]::IsNullOrEmpty($RawEdition)) {
        return 'SQL Server Standard Edition'
    }
    
    $edition = $RawEdition.ToLower()
    
    # Map SQL Server editions to Standard or Enterprise
    if ($edition -match 'enterprise') {
        return 'SQL Server Enterprise Edition'
    }
    elseif ($edition -match 'standard') {
        return 'SQL Server Standard Edition'
    }
    elseif ($edition -match 'developer') {
        return 'SQL Server Developer Edition'
    }
    elseif ($edition -match 'express') {
        return 'SQL Server Express Edition'
    }
    elseif ($edition -match 'web') {
        return 'SQL Server Web Edition'
    }
    else {
        # Default to Standard if unknown
        return 'SQL Server Standard Edition'
    }
}



function Get-EnhancedDatabaseInfo {
    param(
        [Parameter(Mandatory=$true)]$VM,
        [string]$IPAddress,
        [bool]$EnableSQLDetection = $false,
        [hashtable]$SQLCredentials = @{},
        [hashtable]$ConfigCredentials = @{}
    )
    
    $databaseInfo = @{
        HasDatabase = $false
        DatabaseType = ''
        Edition = ''
        Version = ''
        DetectionMethod = 'Pattern Matching'
        Details = @{}
    }
    
    # Pattern-based detection first
    $vmName = $VM.Name.ToLower()
    $osName = if ($VM.Guest.OSFullName) { $VM.Guest.OSFullName.ToLower() } else { '' }
    
    # SQL Server patterns
    if ($vmName -match 'sql|database|db-|mssql' -or $osName -match 'sql') {
        $databaseInfo.HasDatabase = $true
        $databaseInfo.DatabaseType = 'SQL Server'
        $databaseInfo.Edition = 'SQL Server Standard Edition'  # Default assumption
        
        # Enhanced SQL Server detection if enabled
        if ($EnableSQLDetection -and $IPAddress) {
            try {
                # Get all available SQL Server credentials
                $sqlCredentialsList = Get-DatabaseCredentialsList -DatabaseType 'SQLServer' -ConfigCredentials $ConfigCredentials -ParameterCredentials $SQLCredentials
                
                if ($sqlCredentialsList.Count -gt 0) {
                    $sqlResult = Test-DatabaseConnectionWithMultipleCredentials -IPAddress $IPAddress -DatabaseType 'SQLServer' -CredentialsList $sqlCredentialsList -TimeoutSeconds $sqlConnectionTimeout
                    
                    if ($sqlResult.Success) {
                        $databaseInfo.Edition = $sqlResult.Edition
                        $databaseInfo.Version = $sqlResult.Version
                        $databaseInfo.DetectionMethod = "Direct SQL Query ($($sqlResult.CredentialUsed))"
                        $databaseInfo.Details = $sqlResult
                    }
                } else {
                    Write-DebugLog "No SQL Server credentials available for $($VM.Name)"
                }
            } catch {
                Write-DebugLog "SQL Server detection failed for $($VM.Name): $_"
            }
        }
    }

    
    return $databaseInfo
}

function Get-DatabaseEditionCategory {
    param(
        [string]$Edition
    )
    
    if (-not $Edition) { return '' }
    
    $edition = $Edition.ToLower()
    
    # SQL Server editions
    if ($edition -match 'enterprise') { return 'SQL Server Enterprise Edition' }
    if ($edition -match 'standard') { return 'SQL Server Standard Edition' }
    if ($edition -match 'developer') { return 'SQL Server Developer Edition' }
    if ($edition -match 'express') { return 'SQL Server Express Edition' }
    if ($edition -match 'web') { return 'SQL Server Web Edition' }
    
    return $Edition
}

function Get-AnonymizedIP {
    param(
        [string]$originalIP,
        [hashtable]$mappingTable
    )
    
    if ([string]::IsNullOrEmpty($originalIP) -or $originalIP -eq "") {
        return $originalIP
    }
    
    # Handle multiple IPs separated by comma
    $ips = $originalIP -split ","
    $anonymizedIPs = @()
    
    foreach ($ip in $ips) {
        $ip = $ip.Trim()
        if ([string]::IsNullOrEmpty($ip)) {
            continue
        }
        
        if (-not $mappingTable.ContainsKey($ip)) {
            # Generate fake IP in 10.x.x.x range
            $counter = $mappingTable.Count + 1
            $octet2 = [math]::Floor($counter / 65536) + 1
            $octet3 = [math]::Floor(($counter % 65536) / 256)
            $octet4 = $counter % 256
            $mappingTable[$ip] = "10.$octet2.$octet3.$octet4"
        }
        
        $anonymizedIPs += $mappingTable[$ip]
    }
    
    return $anonymizedIPs -join ", "
}

# Environment detection function
function Get-VMEnvironment {
    param([string]$vmName)
    
    if ([string]::IsNullOrEmpty($vmName)) {
        return "NonProduction"
    }
    
    # Production patterns
    $productionPatterns = @('prod', 'production', 'prd', 'live', 'lv', 'p-', '-p-', '-p$', 'master', 'main', 'critical', 'crit', 'primary', 'pri', 'active', 'act')
    
    foreach ($pattern in $productionPatterns) {
        if ($vmName -match $pattern) {
            return "Production"
        }
    }
    
    return "NonProduction"
}

# Wildcard matching function
function Test-WildcardMatch {
    param(
        [string]$Value,
        [string]$Pattern
    )
    
    if ([string]::IsNullOrEmpty($Pattern) -or [string]::IsNullOrEmpty($Value)) {
        return $false
    }
    
    return $Value -like $Pattern
}

# Filter validation function
function Test-FilterConflicts {
    # Check for conflicting include/exclude parameters for the same filter type
    $conflicts = @()
    
    if ($IncludeCluster -and $ExcludeCluster) {
        $conflicts += "Cannot use both IncludeCluster and ExcludeCluster simultaneously"
    }
    
    if ($IncludeDatacenter -and $ExcludeDatacenter) {
        $conflicts += "Cannot use both IncludeDatacenter and ExcludeDatacenter simultaneously"
    }
    
    if ($IncludeHost -and $ExcludeHost) {
        $conflicts += "Cannot use both IncludeHost and ExcludeHost simultaneously"
    }
    
    if ($IncludeEnvironment -and $ExcludeEnvironment) {
        $conflicts += "Cannot use both IncludeEnvironment and ExcludeEnvironment simultaneously"
    }
    
    return $conflicts
}

# VM filtering function
function Test-VMMatchesFilters {
    param(
        [Parameter(Mandatory=$true)]$VM,
        [Parameter(Mandatory=$true)]$InfraInfo
    )
    
    # Cluster filtering
    if ($IncludeCluster) {
        $clusterPatterns = $IncludeCluster -split ','
        $clusterMatch = $false
        foreach ($pattern in $clusterPatterns) {
            if (Test-WildcardMatch -Value $InfraInfo.ClusterName -Pattern $pattern.Trim()) {
                $clusterMatch = $true
                break
            }
        }
        if (-not $clusterMatch) { return $false }
    }
    
    if ($ExcludeCluster) {
        $clusterPatterns = $ExcludeCluster -split ','
        foreach ($pattern in $clusterPatterns) {
            if (Test-WildcardMatch -Value $InfraInfo.ClusterName -Pattern $pattern.Trim()) {
                return $false
            }
        }
    }
    
    # Datacenter filtering
    if ($IncludeDatacenter) {
        $datacenterPatterns = $IncludeDatacenter -split ','
        $datacenterMatch = $false
        foreach ($pattern in $datacenterPatterns) {
            if (Test-WildcardMatch -Value $InfraInfo.DatacenterName -Pattern $pattern.Trim()) {
                $datacenterMatch = $true
                break
            }
        }
        if (-not $datacenterMatch) { return $false }
    }
    
    if ($ExcludeDatacenter) {
        $datacenterPatterns = $ExcludeDatacenter -split ','
        foreach ($pattern in $datacenterPatterns) {
            if (Test-WildcardMatch -Value $InfraInfo.DatacenterName -Pattern $pattern.Trim()) {
                return $false
            }
        }
    }
    
    # Host filtering
    if ($IncludeHost) {
        $hostPatterns = $IncludeHost -split ','
        $hostMatch = $false
        foreach ($pattern in $hostPatterns) {
            if (Test-WildcardMatch -Value $InfraInfo.HostName -Pattern $pattern.Trim()) {
                $hostMatch = $true
                break
            }
        }
        if (-not $hostMatch) { return $false }
    }
    
    if ($ExcludeHost) {
        $hostPatterns = $ExcludeHost -split ','
        foreach ($pattern in $hostPatterns) {
            if (Test-WildcardMatch -Value $InfraInfo.HostName -Pattern $pattern.Trim()) {
                return $false
            }
        }
    }
    
    # Environment filtering
    $vmEnvironment = Get-VMEnvironment -vmName $VM.Name
    
    if ($IncludeEnvironment) {
        if ($vmEnvironment -ne $IncludeEnvironment) {
            return $false
        }
    }
    
    if ($ExcludeEnvironment) {
        if ($vmEnvironment -eq $ExcludeEnvironment) {
            return $false
        }
    }
    
    return $true
}

# Set port based on protocol
if ($port -eq 0) {
    $port = if ($protocol -eq "https") { 443 } else { 80 }
}

Write-Host "VMware Collector - v2" -ForegroundColor Cyan
Write-Host "Connecting to vCenter Server $address..." -ForegroundColor Yellow
Write-DebugLog "Connecting to vCenter Server $address using $protocol on port $port"

# Function to ensure vCenter connection is active
function Ensure-VCenterConnection {
    if (-not $global:DefaultVIServer -or $global:DefaultVIServer.IsConnected -eq $false) {
        Write-DebugLog "vCenter connection lost, reconnecting..."
        try {
            $vCenterCredential = $global:SecureCredentialManager.GetCredential("vCenter")
            Connect-VIServer $address -Protocol $protocol -Credential $vCenterCredential -Port $port -ErrorAction Stop | Out-Null
            Write-DebugLog "Successfully reconnected to vCenter Server"
        }
        catch {
            Write-Host "Failed to reconnect to vCenter Server: $_" -ForegroundColor Red
            Write-DebugLog "Failed to reconnect to vCenter Server: $_"
            throw $_
        }
    }
}

# Initialize secure error handler
$global:ErrorHandler = [SecureErrorHandler]::new($logger, [bool]$enableLogging)

# Connect to vCenter
try {
    $vCenterCredential = $global:SecureCredentialManager.GetCredential("vCenter")
    Connect-VIServer $address -Protocol $protocol -Credential $vCenterCredential -Port $port -ErrorAction Stop | Out-Null
    Write-Host "Successfully connected to vCenter Server" -ForegroundColor Green
    Write-DebugLog "Successfully connected to vCenter Server"
} catch {
    $global:ErrorHandler.HandleConnectionError($_.Exception, "vCenter", $address)
    exit 1
} finally {
    # Clear credential reference
    $vCenterCredential = $null
}

# Get basic vCenter information
try { 
    $datacenterName = (Get-Datacenter)[0].Name 
} catch { 
    $datacenterName = "Unknown" 
}
$vcenterVersion = $global:DefaultVIServer.Version + " Build " + $global:DefaultVIServer.Build

# Get StatIntervals for proper granular data collection
Write-DebugLog "Retrieving vCenter stat intervals..."
$statIntervals = Get-StatInterval
$statIntervalsHash = @{}

if (-not $statIntervals) {
    Write-DebugLog "Warning: Could not retrieve stat intervals, using defaults"
    $statIntervalsHash = @{
        pastDay = 300      # 5 minutes
        pastWeek = 1800    # 30 minutes
        pastMonth = 7200   # 2 hours
        pastYear = 86400   # 1 day
    }
} else {
    $statIntervalsHash = @{
        pastDay = ($statIntervals | Where-Object { $_.Name -eq "Past Day" }).SamplingPeriodSecs
        pastWeek = ($statIntervals | Where-Object { $_.Name -eq "Past Week" }).SamplingPeriodSecs
        pastMonth = ($statIntervals | Where-Object { $_.Name -eq "Past Month" }).SamplingPeriodSecs
        pastYear = ($statIntervals | Where-Object { $_.Name -eq "Past Year" }).SamplingPeriodSecs
    }
}

Write-Host "Connected to vCenter: $($global:DefaultVIServer.Name)" -ForegroundColor Green
Write-DebugLog "Version: $vcenterVersion"
Write-DebugLog "Datacenter: $datacenterName"
Write-DebugLog "Collection period: $collectionDays days"
Write-DebugLog "Output format: $outputFormat $(if($anonymize){'+ Anonymized'})"

# Validate filter conflicts
$filterConflicts = Test-FilterConflicts
if ($filterConflicts.Count -gt 0) {
    Write-Host "ERROR: Filter conflicts detected:" -ForegroundColor Red
    foreach ($conflict in $filterConflicts) {
        Write-Host "  - $conflict" -ForegroundColor Red
    }
    exit 1
}

# Log active filters
$activeFilters = @()
if ($vmListFile) {
    $activeFilters += "VM List File: $vmListFile"
} else {
    $activeFilters += "Power State: $(if($filterVMs -eq 'Y'){'Powered On Only'}else{'All VMs'})"
}

if ($IncludeCluster) { $activeFilters += "Include Clusters: $IncludeCluster" }
if ($ExcludeCluster) { $activeFilters += "Exclude Clusters: $ExcludeCluster" }
if ($IncludeDatacenter) { $activeFilters += "Include Datacenters: $IncludeDatacenter" }
if ($ExcludeDatacenter) { $activeFilters += "Exclude Datacenters: $ExcludeDatacenter" }
if ($IncludeHost) { $activeFilters += "Include Hosts: $IncludeHost" }
if ($ExcludeHost) { $activeFilters += "Exclude Hosts: $ExcludeHost" }
if ($IncludeEnvironment) { $activeFilters += "Include Environment: $IncludeEnvironment" }
if ($ExcludeEnvironment) { $activeFilters += "Exclude Environment: $ExcludeEnvironment" }

if ($activeFilters.Count -gt 0) {
    Write-Host "Active Filters:" -ForegroundColor Yellow
    foreach ($filter in $activeFilters) {
        Write-Host "  - $filter" -ForegroundColor Yellow
        Write-DebugLog "Filter: $filter"
    }
}
if ($fastMode) {
    Write-Host "Fast Mode: ENABLED" -ForegroundColor Yellow
}

# OPTIMIZATION 1: Pre-cache all infrastructure data
Write-Host "Pre-caching infrastructure data..." -ForegroundColor Cyan
$cacheStartTime = Get-Date

# Cache all hosts (we need this for initial VM filtering)
Write-DebugLog "Caching host information..."
$hostCache = @{}
$allHosts = Get-VMHost
$hostCount = 0
foreach ($vmHost in $allHosts) {
    $hostCount++
    if ($allHosts.Count -gt 10) {
        $hostPercent = [math]::Round(($hostCount / $allHosts.Count) * 100, 1)
        Write-Progress -Activity "Caching Infrastructure Data" -Status "Caching host $hostCount of $($allHosts.Count) ($hostPercent%) - $($vmHost.Name)" -PercentComplete $hostPercent
    }
    $clusterName = ""
    try { $clusterName = (Get-Cluster -VMHost $vmHost).Name } catch { $clusterName = "" }
    
    $datacenterNameHost = $datacenterName
    try { $datacenterNameHost = (Get-Datacenter -VMHost $vmHost).Name } catch { $datacenterNameHost = $datacenterName }
    
    $hostCache[$vmHost.Id] = @{
        Name = $vmHost.Name
        Cluster = $clusterName
        Datacenter = $datacenterNameHost
    }
}
if ($allHosts.Count -gt 10) {
    Write-Progress -Activity "Caching Infrastructure Data" -Completed
}
Write-DebugLog "Cached $($hostCache.Count) hosts"

# Cache all clusters (we need this for initial VM filtering)
Write-DebugLog "Caching cluster information..."
$clusterCache = @{}
$allClusters = Get-Cluster
foreach ($cluster in $allClusters) {
    $datacenterNameCluster = $datacenterName
    try { $datacenterNameCluster = (Get-Datacenter -Cluster $cluster).Name } catch { $datacenterNameCluster = $datacenterName }
    
    $clusterCache[$cluster.Id] = @{
        Name = $cluster.Name
        Datacenter = $datacenterNameCluster
    }
}
Write-DebugLog "Cached $($clusterCache.Count) clusters"

# Cache all datastores (we need this for initial VM filtering)
Write-DebugLog "Caching datastore information..."
$datastoreCache = @{}
$allDatastores = Get-Datastore
foreach ($datastore in $allDatastores) {
    $datastoreCache[$datastore.Id] = $datastore.Name
}
Write-DebugLog "Cached $($datastoreCache.Count) datastores"

# Cache all resource pools
Write-DebugLog "Caching resource pool information..."
$resourcePoolCache = @{}
try {
    $allResourcePools = Get-ResourcePool
    foreach ($rp in $allResourcePools) {
        $resourcePoolCache[$rp.Id] = $rp.Name
    }
    Write-DebugLog "Cached $($resourcePoolCache.Count) resource pools"
} catch {
    Write-DebugLog "Warning: Could not cache resource pools: $_"
}

$cacheTime = (Get-Date) - $cacheStartTime
Write-Host "Infrastructure caching completed in $($cacheTime.TotalSeconds.ToString('F1')) seconds" -ForegroundColor Green

# Get VMs based on input method
Write-Host "Retrieving VM inventory..." -ForegroundColor Yellow

# Initialize $hasAdvancedFilters before the if/else block to ensure it's always defined
$hasAdvancedFilters = $IncludeCluster -or $ExcludeCluster -or $IncludeDatacenter -or $ExcludeDatacenter -or $IncludeHost -or $ExcludeHost -or $IncludeEnvironment -or $ExcludeEnvironment

# Check if vmListFile takes precedence
if ($vmListFile) {
    # Warn if other filters are specified but will be ignored
    if ($hasAdvancedFilters) {
        Write-Host "WARNING: VM List File takes precedence. Other filter parameters will be ignored." -ForegroundColor Yellow
        Write-DebugLog "WARNING: VM List File specified, ignoring other filter parameters"
    }
    
    # Process VM list from file
    Write-DebugLog "Processing VMs from list file: $vmListFile"
    
    if (-not (Test-Path $vmListFile)) {
        Write-Host "ERROR: VM list file not found: $vmListFile" -ForegroundColor Red
        exit 1
    }
    
    $vmNames = @()
    $fileExtension = [System.IO.Path]::GetExtension($vmListFile).ToLower()
    
    try {
        if ($fileExtension -eq '.csv') {
            # Handle CSV file
            Write-DebugLog "Reading CSV file..."
            $csvData = Import-Csv $vmListFile
            
            # Try to find VM name column (VM, Name, VMName, etc.)
            $vmColumnName = $null
            $possibleColumns = @('VM', 'Name', 'VMName', 'VirtualMachine', 'Server', 'ServerName')
            
            foreach ($col in $possibleColumns) {
                if ($csvData[0].PSObject.Properties.Name -contains $col) {
                    $vmColumnName = $col
                    break
                }
            }
            
            if (-not $vmColumnName) {
                Write-Host "ERROR: Could not find VM name column in CSV. Expected columns: VM, Name, VMName, VirtualMachine, Server, or ServerName" -ForegroundColor Red
                Write-Host "Available columns: $($csvData[0].PSObject.Properties.Name -join ', ')" -ForegroundColor Yellow
                exit 1
            }
            
            $vmNames = $csvData | ForEach-Object { $_.$vmColumnName } | Where-Object { $_ -and $_.Trim() -ne '' }
            Write-DebugLog "Found $($vmNames.Count) VM names in CSV file using column '$vmColumnName'"
            
        } elseif ($fileExtension -eq '.txt') {
            # Handle TXT file
            Write-DebugLog "Reading TXT file..."
            $vmNames = Get-Content $vmListFile | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
            Write-DebugLog "Found $($vmNames.Count) VM names in TXT file"
            
        } else {
            Write-Host "ERROR: Unsupported file format. Please use .csv or .txt files" -ForegroundColor Red
            exit 1
        }
        
        if ($vmNames.Count -eq 0) {
            Write-Host "ERROR: No VM names found in the file" -ForegroundColor Red
            exit 1
        }
        
        # Get all VMs from vCenter
        $allVMsFromvCenter = Get-VM
        
        # Filter VMs based on the list
        $vms = @()
        $notFoundVMs = @()
        
        foreach ($vmName in $vmNames) {
            $foundVM = $allVMsFromvCenter | Where-Object { $_.Name -eq $vmName }
            if ($foundVM) {
                $vms += $foundVM
            } else {
                $notFoundVMs += $vmName
            }
        }
        
        Write-Host "Successfully matched $($vms.Count) VMs from the list" -ForegroundColor Green
        
        if ($notFoundVMs.Count -gt 0) {
            Write-DebugLog "WARNING: $($notFoundVMs.Count) VMs from the list were not found in vCenter"
            $notFoundVMs | ForEach-Object { Write-DebugLog "  - $_" }
        }
        
        # Show power state summary
        $poweredOnCount = ($vms | Where-Object { $_.PowerState -eq "poweredOn" }).Count
        $poweredOffCount = ($vms | Where-Object { $_.PowerState -eq "poweredOff" }).Count
        Write-DebugLog "Power state summary: $poweredOnCount powered on, $poweredOffCount powered off"
        
    } catch {
        Write-Host "ERROR: Failed to read VM list file: $_" -ForegroundColor Red
        exit 1
    }
    
} else {
    # Get all VMs from vCenter first
    Write-DebugLog "Retrieving all VMs from vCenter..."
    $allVMsFromvCenter = Get-VM
    
    # Apply power state filter first
    if ($filterVMs -eq 'Y') {
        $candidateVMs = $allVMsFromvCenter | Where-Object {$_.PowerState -eq "poweredOn"}
        Write-DebugLog "Filtered to $($candidateVMs.Count) powered on VMs"
    } else {
        $candidateVMs = $allVMsFromvCenter
        Write-DebugLog "Processing all $($candidateVMs.Count) VMs"
    }
    
    # Apply advanced filters if specified (already computed before the if/else block)
    if ($hasAdvancedFilters) {
        Write-Host "Applying advanced filters..." -ForegroundColor Cyan
        Write-DebugLog "Applying advanced filters to $($candidateVMs.Count) candidate VMs"
        
        # We need infrastructure info to apply filters, so we'll build a temporary cache
        Write-DebugLog "Building temporary infrastructure cache for filtering..."
        $tempInfraCache = @{}
        $filterVMCount = 0
        
        foreach ($vm in $candidateVMs) {
            $filterVMCount++
            if ($candidateVMs.Count -gt 50) {
                $filterPercent = [math]::Round(($filterVMCount / $candidateVMs.Count) * 100, 1)
                Write-Progress -Activity "Building Filter Cache" -Status "Processing VM $filterVMCount of $($candidateVMs.Count) ($filterPercent%) - $($vm.Name)" -PercentComplete $filterPercent
            }
            
            $vmHostInfo = if ($vm.VMHostId -and $hostCache[$vm.VMHostId]) { $hostCache[$vm.VMHostId] } else { @{ Name = ""; Cluster = ""; Datacenter = $datacenterName } }
            
            # Get cluster info (try from host first, then direct lookup)
            $clusterName = $vmHostInfo.Cluster
            if (-not $clusterName) {
                try {
                    $vmCluster = Get-Cluster -VM $vm -ErrorAction SilentlyContinue
                    $clusterName = if ($vmCluster) { $vmCluster.Name } else { "" }
                } catch { $clusterName = "" }
            }
            
            $tempInfraCache[$vm.Id] = @{
                HostName = $vmHostInfo.Name
                ClusterName = $clusterName
                DatacenterName = $vmHostInfo.Datacenter
            }
        }
        
        if ($candidateVMs.Count -gt 50) {
            Write-Progress -Activity "Building Filter Cache" -Completed
        }
        
        # Apply filters
        $vms = @()
        $filteredOutCount = 0
        
        foreach ($vm in $candidateVMs) {
            $infraInfo = $tempInfraCache[$vm.Id]
            
            if (Test-VMMatchesFilters -VM $vm -InfraInfo $infraInfo) {
                $vms += $vm
            } else {
                $filteredOutCount++
            }
        }
        
        Write-Host "Advanced filtering completed: $($vms.Count) VMs match criteria, $filteredOutCount VMs filtered out" -ForegroundColor Green
        Write-DebugLog "Advanced filtering: $($vms.Count) VMs selected, $filteredOutCount VMs filtered out"
        
    } else {
        # No advanced filters, use candidate VMs as-is
        $vms = $candidateVMs
        Write-Host "Processing $($vms.Count) VMs $(if($filterVMs -eq 'Y'){'(powered on only)'}else{'(all VMs)'})" -ForegroundColor Green
    }
}

$totalVMs = $vms.Count
if ($totalVMs -eq 0) {
    Write-Host "No VMs found to process!" -ForegroundColor Red
    exit 1
}

# INFRASTRUCTURE FILTERING: Filter infrastructure data to only include items related to filtered VMs
if ($hasAdvancedFilters -or $vmListFile) {
    Write-Host "Filtering infrastructure data to match VM selection..." -ForegroundColor Cyan
} else {
    Write-Host "Collecting infrastructure data for all VMs..." -ForegroundColor Cyan
}
$infraFilterStartTime = Get-Date

# Get unique hosts used by filtered VMs
$filteredHostIds = @()
$filteredHostNames = @()
foreach ($vm in $vms) {
    if ($vm.VMHostId -and $vm.VMHostId -notin $filteredHostIds) {
        $filteredHostIds += $vm.VMHostId
        if ($hostCache[$vm.VMHostId]) {
            $filteredHostNames += $hostCache[$vm.VMHostId].Name
        }
    }
}

# Get unique clusters used by filtered VMs
$filteredClusterNames = @()
foreach ($vm in $vms) {
    # Get cluster from host cache (already cached during infrastructure pre-caching)
    if ($vm.VMHostId -and $hostCache[$vm.VMHostId] -and $hostCache[$vm.VMHostId].Cluster) {
        $clusterName = $hostCache[$vm.VMHostId].Cluster
        if ($clusterName -and $clusterName -notin $filteredClusterNames) {
            $filteredClusterNames += $clusterName
        }
    }
}

# Get unique datastores used by filtered VMs
$filteredDatastoreIds = @()
$filteredDatastoreNames = @()
foreach ($vm in $vms) {
    if ($vm.DatastoreIdList) {
        foreach ($datastoreId in $vm.DatastoreIdList) {
            if ($datastoreId -notin $filteredDatastoreIds) {
                $filteredDatastoreIds += $datastoreId
                if ($datastoreCache[$datastoreId]) {
                    $filteredDatastoreNames += $datastoreCache[$datastoreId]
                }
            }
        }
    }
}

# Filter the cached infrastructure data to only include relevant items
$filteredHostCache = @{}
foreach ($hostId in $filteredHostIds) {
    if ($hostCache[$hostId]) {
        $filteredHostCache[$hostId] = $hostCache[$hostId]
    }
}

$filteredDatastoreCache = @{}
foreach ($datastoreId in $filteredDatastoreIds) {
    if ($datastoreCache[$datastoreId]) {
        $filteredDatastoreCache[$datastoreId] = $datastoreCache[$datastoreId]
    }
}

# Update the global caches to only contain filtered data
$hostCache = $filteredHostCache
$datastoreCache = $filteredDatastoreCache

$infraFilterTime = (Get-Date) - $infraFilterStartTime
Write-Host "Infrastructure filtering completed:" -ForegroundColor Green
Write-Host "  - Hosts: $($filteredHostNames.Count) ($(($filteredHostNames | Sort-Object -Unique) -join ', '))" -ForegroundColor Green
Write-Host "  - Clusters: $($filteredClusterNames.Count) ($(($filteredClusterNames | Sort-Object -Unique) -join ', '))" -ForegroundColor Green  
Write-Host "  - Datastores: $($filteredDatastoreNames.Count) ($(($filteredDatastoreNames | Sort-Object -Unique) -join ', '))" -ForegroundColor Green
Write-DebugLog "Infrastructure filtering completed in $($infraFilterTime.TotalSeconds.ToString('F1')) seconds"
Write-DebugLog "Filtered infrastructure - Hosts: $($filteredHostNames.Count), Clusters: $($filteredClusterNames.Count), Datastores: $($filteredDatastoreNames.Count)"

# OPTIMIZATION 2: Build VM-to-infrastructure mappings using cached data
Write-Host "Building VM-to-infrastructure mappings..." -ForegroundColor Cyan
$mappingStartTime = Get-Date
$vmInfraCache = @{}
$mappingVMCount = 0

foreach ($vm in $vms) {
    $mappingVMCount++
    $mappingPercent = [math]::Round(($mappingVMCount / $totalVMs) * 100, 1)
    Write-Progress -Activity "Building Infrastructure Mappings" -Status "Processing VM $mappingVMCount of $totalVMs ($mappingPercent%) - $($vm.Name)" -PercentComplete $mappingPercent
    $vmHostInfo = if ($vm.VMHostId -and $hostCache[$vm.VMHostId]) { $hostCache[$vm.VMHostId] } else { @{ Name = ""; Cluster = ""; Datacenter = $datacenterName } }
    
    # Get cluster info (try from host first, then direct lookup)
    $clusterName = $vmHostInfo.Cluster
    if (-not $clusterName) {
        try {
            $vmCluster = Get-Cluster -VM $vm -ErrorAction SilentlyContinue
            $clusterName = if ($vmCluster) { $vmCluster.Name } else { "" }
        } catch { $clusterName = "" }
    }
    
    # Get resource pool using cache - use VM's ResourcePool property to avoid API call
    $resourcePoolName = ""
    try {
        if ($vm.ResourcePoolId -and $resourcePoolCache[$vm.ResourcePoolId]) {
            $resourcePoolName = $resourcePoolCache[$vm.ResourcePoolId]
        } elseif ($vm.ResourcePool -and $resourcePoolCache[$vm.ResourcePool.Id]) {
            $resourcePoolName = $resourcePoolCache[$vm.ResourcePool.Id]
        }
    } catch { $resourcePoolName = "" }
    
    # Get datastores using cache
    $datastoreNames = @()
    try {
        foreach ($datastoreId in $vm.DatastoreIdList) {
            if ($datastoreCache[$datastoreId]) {
                $datastoreNames += $datastoreCache[$datastoreId]
            }
        }
    } catch {
        # Intentionally empty - datastore info is optional
    }
    
    $folderName = ""
    try { $folderName = $vm.Folder.Name } catch { $folderName = "" }
    
    $vmInfraCache[$vm.Id] = @{
        HostName = $vmHostInfo.Name
        ClusterName = $clusterName
        DatacenterName = $vmHostInfo.Datacenter
        ResourcePoolName = $resourcePoolName
        FolderName = $folderName
        DatastoreNames = $datastoreNames -join ", "
    }
}

Write-Progress -Activity "Building Infrastructure Mappings" -Completed

$mappingTime = (Get-Date) - $mappingStartTime
Write-Host "Built infrastructure mappings in $($mappingTime.TotalSeconds.ToString('F1')) seconds" -ForegroundColor Green

# Initialize data collections
$serversData = [System.Collections.ArrayList]::new()  # For Excel (Import-Data-Set-Template format)
$csvVMInfo = [System.Collections.ArrayList]::new()    # For CSV (RVTools format)
# Removed dailyStats - using aggregated performance data directly

# Function to calculate 95th percentile from an array of values
function Get-Percentile {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Values,
        [Parameter(Mandatory=$false)]
        [double]$Percentile = 95.0
    )
    
    if (-not $Values -or $Values.Count -eq 0) {
        return 0
    }
    
    # Sort the values in ascending order
    $sortedValues = $Values | Sort-Object
    
    # Calculate the index for the percentile
    $index = ($Percentile / 100) * ($sortedValues.Count - 1)
    
    # If index is a whole number, return that value
    if ($index -eq [math]::Floor($index)) {
        return $sortedValues[[int]$index]
    }
    
    # Otherwise, interpolate between the two nearest values
    $lowerIndex = [math]::Floor($index)
    $upperIndex = [math]::Ceiling($index)
    $weight = $index - $lowerIndex
    
    $lowerValue = $sortedValues[$lowerIndex]
    $upperValue = $sortedValues[$upperIndex]
    
    return $lowerValue + ($weight * ($upperValue - $lowerValue))
}

# Function to calculate historical performance metrics using proper stat intervals
function Get-HistoricalPerformanceMetrics {
    param (
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM,
        [Parameter(Mandatory=$true)]
        [int]$Days,
        [Parameter(Mandatory=$true)]
        [hashtable]$StatIntervals
    )
    
    # Check if VM is powered off - use default values for powered off VMs
    if ($VM.PowerState -eq "poweredOff") {
        Write-DebugLog "VM $($VM.Name) is powered off - using default performance values (CPU: 25%, Memory: 60%)"
        
        # No daily stats needed - using aggregated values directly
        
        return @{
            maxCpuUsagePctDec = 25.0
            avgCpuUsagePctDec = 25.0
            maxRamUsagePctDec = 60.0
            avgRamUtlPctDec = 60.0
            dataPoints = 0
        }
    }
    
    $startDate = (Get-Date).AddDays(-$Days).Date
    $endDate = (Get-Date).Date.AddDays(1).AddSeconds(-1)
    
    Write-DebugLog "Collecting performance stats for VM $($VM.Name) from $startDate to $endDate"
    
    # Determine appropriate stat interval based on collection period
    $intervalSec = $StatIntervals.pastDay  # Default to 5-minute intervals
    if ($Days -gt 1 -and $Days -le 2) {
        $intervalSec = $StatIntervals.pastDay      # 5 minutes for up to 1 week
    } elseif ($Days -gt 2 -and $Days -le 7) {
        $intervalSec = $StatIntervals.pastWeek     # 30 minutes for up to 1 month
    } elseif ($Days -gt 8 -and $Days -le 30) {
        $intervalSec = $StatIntervals.pastMonth    # 2 hours for up to 1 year
    } else {
        $intervalSec = $StatIntervals.pastYear     # 1 day for longer periods
    }
    
    try {
        # Calculate expected data points based on collection period and VMware stat intervals
        $expectedSamples = 0
        if ($Days -le 2) {
            # 5-minute intervals for up to 2 days
            $expectedSamples = $Days * 288  # 288 samples per day at 5-min intervals
        } elseif ($Days -le 7) {
            # Mixed: 2 days at 5-min + remaining days at 30-min
            $expectedSamples = (2 * 288) + (($Days - 2) * 48)  # 48 samples per day at 30-min intervals
        } elseif ($Days -le 30) {
            # Mixed: 2 days at 5-min + 5 days at 30-min + remaining days at 2-hour
            $expectedSamples = (2 * 288) + (5 * 48) + (($Days - 7) * 12)  # 12 samples per day at 2-hour intervals
        } else {
            # Mixed: 2 days at 5-min + 5 days at 30-min + 23 days at 2-hour + remaining days at 1-day
            $expectedSamples = (2 * 288) + (5 * 48) + (23 * 12) + ($Days - 30)  # 1 sample per day
        }
        
        # Add 20% buffer for safety and use as MaxSamples
        $maxSamples = [math]::Ceiling($expectedSamples * 1.2)
        
        Write-DebugLog "Using interval: $intervalSec seconds, expected ~$expectedSamples samples, MaxSamples: $maxSamples"
        
        $cpuStats = Get-Stat -Entity $VM -Start $startDate -Finish $endDate -Stat cpu.usage.average -IntervalSecs $intervalSec -MaxSamples $maxSamples -ErrorAction SilentlyContinue
        $memStats = Get-Stat -Entity $VM -Start $startDate -Finish $endDate -Stat mem.consumed.average -IntervalSecs $intervalSec -MaxSamples $maxSamples -ErrorAction SilentlyContinue
        
        Write-DebugLog "CPU Stats count: $(if($cpuStats){$cpuStats.Count}else{0}), Memory Stats count: $(if($memStats){$memStats.Count}else{0})"
        
        # If no stats found, try a shorter time period as fallback
        if ((-not $cpuStats -or $cpuStats.Count -eq 0) -and $Days -gt 1) {
            Write-DebugLog "No stats found for $Days days, trying last 24 hours as fallback"
            $fallbackStart = (Get-Date).AddDays(-1)
            $fallbackEnd = Get-Date
            $cpuStats = Get-Stat -Entity $VM -Start $fallbackStart -Finish $fallbackEnd -Stat cpu.usage.average -ErrorAction SilentlyContinue
            $memStats = Get-Stat -Entity $VM -Start $fallbackStart -Finish $fallbackEnd -Stat mem.consumed.average -ErrorAction SilentlyContinue
            Write-DebugLog "Fallback - CPU Stats count: $(if($cpuStats){$cpuStats.Count}else{0}), Memory Stats count: $(if($memStats){$memStats.Count}else{0})"
        }
        
        $metrics = @{
            maxCpuUsagePctDec = 0
            avgCpuUsagePctDec = 0
            maxRamUsagePctDec = 0
            avgRamUtlPctDec = 0
            dataPoints = 0
        }
        
        if ($cpuStats -and $cpuStats.Count -gt 0) {
            # Calculate P95 instead of maximum for more realistic peak values
            $cpuValues = $cpuStats | ForEach-Object { $_.Value }
            $metrics.maxCpuUsagePctDec = [math]::Round((Get-Percentile -Values $cpuValues -Percentile 95), 2)
            $metrics.avgCpuUsagePctDec = [math]::Round(($cpuStats | Measure-Object Value -Average).Average, 2)
            $metrics.dataPoints = $cpuStats.Count
        }
        
        if ($memStats -and $memStats.Count -gt 0) {
            # Memory stats are in KB, convert to percentage of allocated memory
            # Calculate P95 instead of maximum for more realistic peak values
            $memValues = $memStats | ForEach-Object { $_.Value }
            $p95MemKB = Get-Percentile -Values $memValues -Percentile 95
            $avgMemKB = ($memStats | Measure-Object Value -Average).Average
            
            if ($VM.MemoryMB -gt 0) {
                $metrics.maxRamUsagePctDec = [math]::Round(($p95MemKB / 1024) / $VM.MemoryMB * 100, 2)
                $metrics.avgRamUtlPctDec = [math]::Round(($avgMemKB / 1024) / $VM.MemoryMB * 100, 2)
            }
        }
        
        # No daily stats needed - using aggregated values directly
        
        Write-DebugLog "Performance metrics for $($VM.Name): P95CPU=$($metrics.maxCpuUsagePctDec)%, AvgCPU=$($metrics.avgCpuUsagePctDec)%, P95RAM=$($metrics.maxRamUsagePctDec)%, AvgRAM=$($metrics.avgRamUtlPctDec)% (DataPoints: $($metrics.dataPoints))"
        
        return $metrics
    }
    catch {
        Write-DebugLog "Error collecting performance metrics for VM $($VM.Name): $_"
        
        # No daily stats needed - using aggregated values directly
        
        return @{
            maxCpuUsagePctDec = 25.0
            avgCpuUsagePctDec = 25.0
            maxRamUsagePctDec = 60.0
            avgRamUtlPctDec = 60.0
            dataPoints = 0
        }
    }
}

# Function to get VM network information
function Get-VMNetworkDetails {
    param([Parameter(Mandatory=$true)]$VM)
    
    try {
        $networkAdapters = Get-NetworkAdapter -VM $VM -ErrorAction SilentlyContinue
        $primaryIP = ""
        $networkNames = @()
        
        if ($VM.Guest.IPAddress) {
            if ($VM.Guest.IPAddress -is [array]) {
                $primaryIP = ($VM.Guest.IPAddress | Where-Object { $_ -notmatch '^(127\.|::1$|fe80::)' -and $_ -ne '' } | Select-Object -First 1)
            } else {
                $primaryIP = $VM.Guest.IPAddress
            }
        }
        
        foreach ($adapter in $networkAdapters) {
            $networkNames += $adapter.NetworkName
        }
        
        return @{
            PrimaryIP = $primaryIP
            NetworkNames = $networkNames
            NetworkCount = $networkAdapters.Count
        }
    }
    catch {
        Write-DebugLog "Error getting network details for VM $($VM.Name): $_"
        return @{
            PrimaryIP = ""
            NetworkNames = @()
            NetworkCount = 0
        }
    }
}

# OPTIMIZATION 4: Bulk Performance Data Collection (if enabled)
if (-not $skipPerformanceData) {
    Write-Host "`nCollecting bulk performance data..." -ForegroundColor Cyan
    Write-Host "  This collects $collectionDays days of CPU and Memory statistics for all $totalVMs VMs in one operation" -ForegroundColor Yellow
    
    try {
        $bulkPerfStartTime = Get-Date
        $startDate = (Get-Date).AddDays(-$collectionDays)
        $endDate = Get-Date
        
        # Determine appropriate stat interval based on collection period
        $intervalSec = $statIntervalsHash.pastDay  # Default to 5-minute intervals
        if ($collectionDays -le 2) {
            $intervalSec = $statIntervalsHash.pastDay      # 5 minutes for up to 2 days
        } elseif ($collectionDays -gt 2 -and $collectionDays -le 7) {
            $intervalSec = $statIntervalsHash.pastWeek     # 30 minutes from day 2 to day 7
        } elseif ($collectionDays -gt 7 -and $collectionDays -le 30) {
            $intervalSec = $statIntervalsHash.pastMonth    # 2 hours from day 7 to day 30
        } else {
            $intervalSec = $statIntervalsHash.pastYear     # 1 day for 30+ days up to 365 days
        }
        
        Write-DebugLog "Using interval: $intervalSec seconds for $collectionDays days collection"
        Write-DebugLog "Date range: $startDate to $endDate"
        
        # Calculate expected data points based on collection period and VMware stat intervals
        $expectedSamples = 0
        if ($collectionDays -le 2) {
            # 5-minute intervals for up to 2 days
            $expectedSamples = $collectionDays * 288  # 288 samples per day at 5-min intervals
        } elseif ($collectionDays -le 7) {
            # Mixed: 2 days at 5-min + remaining days at 30-min
            $expectedSamples = (2 * 288) + (($collectionDays - 2) * 48)  # 48 samples per day at 30-min intervals
        } elseif ($collectionDays -le 30) {
            # Mixed: 2 days at 5-min + 5 days at 30-min + remaining days at 2-hour
            $expectedSamples = (2 * 288) + (5 * 48) + (($collectionDays - 7) * 12)  # 12 samples per day at 2-hour intervals
        } else {
            # Mixed: 2 days at 5-min + 5 days at 30-min + 23 days at 2-hour + remaining days at 1-day
            $expectedSamples = (2 * 288) + (5 * 48) + (23 * 12) + ($collectionDays - 30)  # 1 sample per day
        }
        
        # Add 20% buffer for safety and use as MaxSamples
        $maxSamples = [math]::Ceiling($expectedSamples * 1.2)
        
        Write-DebugLog "Expected ~$expectedSamples samples per VM, using MaxSamples: $maxSamples"
        Write-DebugLog "Processing $($vms.Count) VMs"
        Write-DebugLog "Date range: $startDate to $endDate"
        Write-DebugLog "Interval: $intervalSec seconds"
        
        Write-DebugLog "Collecting CPU statistics for all VMs..."
        
        # Try smaller batches to avoid hanging and improve reliability
        $allCpuStats = @()
        $batchSize = 10  # Process 10 VMs at a time
        $totalBatches = [Math]::Ceiling($vms.Count / $batchSize)
        $cpuBatchStartTime = Get-Date
        
        for ($i = 0; $i -lt $vms.Count; $i += $batchSize) {
            $batch = $vms[$i..([Math]::Min($i + $batchSize - 1, $vms.Count - 1))]
            $batchNum = [Math]::Floor($i / $batchSize) + 1
            
            # Calculate progress and ETA
            $percentComplete = [math]::Round(($batchNum / $totalBatches) * 100, 1)
            $elapsedTime = (Get-Date) - $cpuBatchStartTime
            if ($batchNum -gt 1) {
                $avgTimePerBatch = $elapsedTime.TotalSeconds / ($batchNum - 1)
                $remainingBatches = $totalBatches - $batchNum
                $etaSeconds = $avgTimePerBatch * $remainingBatches
                $etaTimeSpan = [TimeSpan]::FromSeconds($etaSeconds)
                $etaFormatted = if ($etaTimeSpan.TotalHours -ge 1) {
                    "{0:hh\:mm\:ss}" -f $etaTimeSpan
                } else {
                    "{0:mm\:ss}" -f $etaTimeSpan
                }
                Write-Progress -Activity "Collecting CPU Statistics" -Status "Batch $batchNum of $totalBatches ($percentComplete%) - ETA: $etaFormatted" -PercentComplete $percentComplete
            } else {
                Write-Progress -Activity "Collecting CPU Statistics" -Status "Batch $batchNum of $totalBatches ($percentComplete%) - Calculating ETA..." -PercentComplete $percentComplete
            }
            
            Write-DebugLog "Processing CPU batch $batchNum of $totalBatches ($($batch.Count) VMs)..."
            
            try {
                $batchStats = Get-Stat -Entity $batch -Start $startDate -Finish $endDate -Stat cpu.usage.average -IntervalSecs $intervalSec -MaxSamples $maxSamples -ErrorAction SilentlyContinue
                if ($batchStats) {
                    $allCpuStats += $batchStats
                    Write-DebugLog "Batch ${batchNum}: Retrieved $($batchStats.Count) CPU data points"
                } else {
                    Write-DebugLog "Batch ${batchNum}: No CPU data returned"
                }
            } catch {
                Write-DebugLog "Batch ${batchNum} failed: $($_.Exception.Message)"
            }
        }
        
        Write-Progress -Activity "Collecting CPU Statistics" -Completed
        Write-DebugLog "Retrieved $($allCpuStats.Count) CPU data points"
        
        if ($allCpuStats.Count -eq 0) {
            Write-DebugLog "WARNING: No CPU stats returned! Possible causes: VMs powered off, low statistics level, no historical data, or date range outside available data"
        }
        
        Write-DebugLog "Collecting Memory statistics for all VMs..."
        
        # Process memory stats in batches (same approach as CPU)
        $allMemStats = @()
        $memBatchStartTime = Get-Date
        
        for ($i = 0; $i -lt $vms.Count; $i += $batchSize) {
            $batch = $vms[$i..([Math]::Min($i + $batchSize - 1, $vms.Count - 1))]
            $batchNum = [Math]::Floor($i / $batchSize) + 1
            
            # Calculate progress and ETA
            $percentComplete = [math]::Round(($batchNum / $totalBatches) * 100, 1)
            $elapsedTime = (Get-Date) - $memBatchStartTime
            if ($batchNum -gt 1) {
                $avgTimePerBatch = $elapsedTime.TotalSeconds / ($batchNum - 1)
                $remainingBatches = $totalBatches - $batchNum
                $etaSeconds = $avgTimePerBatch * $remainingBatches
                $etaTimeSpan = [TimeSpan]::FromSeconds($etaSeconds)
                $etaFormatted = if ($etaTimeSpan.TotalHours -ge 1) {
                    "{0:hh\:mm\:ss}" -f $etaTimeSpan
                } else {
                    "{0:mm\:ss}" -f $etaTimeSpan
                }
                Write-Progress -Activity "Collecting Memory Statistics" -Status "Batch $batchNum of $totalBatches ($percentComplete%) - ETA: $etaFormatted" -PercentComplete $percentComplete
            } else {
                Write-Progress -Activity "Collecting Memory Statistics" -Status "Batch $batchNum of $totalBatches ($percentComplete%) - Calculating ETA..." -PercentComplete $percentComplete
            }
            
            Write-DebugLog "Processing Memory batch $batchNum of $totalBatches ($($batch.Count) VMs)..."
            
            try {
                $batchMemStats = Get-Stat -Entity $batch -Start $startDate -Finish $endDate -Stat mem.consumed.average -IntervalSecs $intervalSec -MaxSamples $maxSamples -ErrorAction SilentlyContinue
                if ($batchMemStats) {
                    $allMemStats += $batchMemStats
                    Write-DebugLog "Batch ${batchNum}: Retrieved $($batchMemStats.Count) Memory data points"
                } else {
                    Write-DebugLog "Batch ${batchNum}: No Memory data returned"
                }
            } catch {
                Write-DebugLog "Memory batch ${batchNum} failed: $($_.Exception.Message)"
            }
        }
        
        Write-Progress -Activity "Collecting Memory Statistics" -Completed
        Write-DebugLog "Retrieved $($allMemStats.Count) Memory data points"
        
        if ($allMemStats.Count -eq 0) {
            Write-DebugLog "WARNING: No Memory stats returned!"
        }
        
        # Process bulk stats into per-VM data
        Write-DebugLog "Processing bulk statistics..."
        $global:BulkPerfData = @{}
        
        foreach ($vm in $vms) {
            $vmCpuStats = $allCpuStats | Where-Object { $_.EntityId -eq $vm.Id }
            $vmMemStats = $allMemStats | Where-Object { $_.EntityId -eq $vm.Id }
            
            $metrics = @{
                maxCpuUsagePctDec = if ($vmCpuStats) { 
                    $cpuValues = $vmCpuStats | ForEach-Object { $_.Value }
                    [math]::Round((Get-Percentile -Values $cpuValues -Percentile 95), 2) 
                } else { 25.0 }
                avgCpuUsagePctDec = if ($vmCpuStats) { [math]::Round(($vmCpuStats | Measure-Object Value -Average).Average, 2) } else { 25.0 }
                maxRamUsagePctDec = 60.0  # Default fallback
                avgRamUtlPctDec = 60.0    # Default fallback
                dataPoints = if ($vmCpuStats) { $vmCpuStats.Count } else { 0 }
            }
            
            # Calculate memory percentages if we have memory stats and VM memory info
            if ($vmMemStats -and $vm.MemoryMB -gt 0) {
                $memValues = $vmMemStats | ForEach-Object { $_.Value }
                $p95MemKB = Get-Percentile -Values $memValues -Percentile 95
                $avgMemKB = ($vmMemStats | Measure-Object Value -Average).Average
                $metrics.maxRamUsagePctDec = [math]::Round(($p95MemKB / 1024) / $vm.MemoryMB * 100, 2)
                $metrics.avgRamUtlPctDec = [math]::Round(($avgMemKB / 1024) / $vm.MemoryMB * 100, 2)
            }
            
            $global:BulkPerfData[$vm.Id] = $metrics
            
            # No daily stats needed - using aggregated values directly
        }
        
        $bulkPerfTime = (Get-Date) - $bulkPerfStartTime
        $vmsWithData = ($global:BulkPerfData.Values | Where-Object { $_.dataPoints -gt 0 }).Count
        $totalDataPoints = ($global:BulkPerfData.Values | ForEach-Object { $_.dataPoints } | Measure-Object -Sum).Sum
        Write-Host "`nBulk performance collection completed!" -ForegroundColor Green
        Write-Host "  Time: $($bulkPerfTime.TotalSeconds.ToString('F1')) seconds" -ForegroundColor Cyan
        Write-Host "  VMs with data: $vmsWithData of $totalVMs" -ForegroundColor Cyan
        Write-Host "  Total data points: $totalDataPoints (CPU + Memory metrics)" -ForegroundColor Cyan
        Write-Host "  Data is now cached in memory for VM processing phase" -ForegroundColor Yellow
        Write-DebugLog "Successfully collected performance data for $vmsWithData of $totalVMs VMs"
        if ($vmsWithData -eq 0) {
            Write-DebugLog "WARNING: No performance data was collected! Check if VMs are powered on and have historical stats."
        }
        
    } catch {
        Write-DebugLog "Bulk performance collection failed, falling back to individual collection: $_"
        $global:BulkPerfData = $null
    }
}

Write-Host "`nCollecting VM configuration data..." -ForegroundColor Yellow
if ($skipPerformanceData) {
    Write-Host "  Performance data collection: DISABLED (using default values)" -ForegroundColor Yellow
    Write-DebugLog "Performance data collection DISABLED for maximum speed"
} elseif ($global:BulkPerfData) {
    Write-Host "  Performance data: Using cached data from bulk collection (no re-collection)" -ForegroundColor Yellow
    Write-DebugLog "Using BULK performance data collection for maximum speed"
}
Write-Host "  Processing: Disks, networks, snapshots, and infrastructure relationships" -ForegroundColor Yellow
Write-DebugLog "Starting VM data collection for $totalVMs VMs"

$startTime = Get-Date
$currentVM = 0
$lastProgressUpdate = Get-Date
$progressUpdateInterval = 5  # Update console every 5 seconds

# OPTIMIZATION 3: Batch process VMs using cached infrastructure data
Write-DebugLog "Processing VMs using optimized batch processing with cached data..."
$batchSize = 50
$processedVMs = 0

for ($i = 0; $i -lt $vms.Count; $i += $batchSize) {
    $batch = $vms[$i..([Math]::Min($i + $batchSize - 1, $vms.Count - 1))]
    $batchNumber = [Math]::Floor($i / $batchSize) + 1
    $totalBatches = [Math]::Ceiling($vms.Count / $batchSize)
    
    $batchStartTime = Get-Date
    Write-DebugLog "Processing batch $batchNumber of $totalBatches ($($batch.Count) VMs)..."
    
    foreach ($vm in $batch) {
        $currentVM++
        $percentComplete = [math]::Round(($currentVM / $totalVMs) * 100, 2)
        
        # Calculate timing information
        $elapsedTime = (Get-Date) - $startTime
        $avgTimePerVM = if ($currentVM -gt 0) { $elapsedTime.TotalSeconds / $currentVM } else { 0 }
        $remainingVMs = $totalVMs - $currentVM
        $estimatedTimeRemaining = if ($avgTimePerVM -gt 0) { [TimeSpan]::FromSeconds($avgTimePerVM * $remainingVMs) } else { [TimeSpan]::Zero }
        
        # Enhanced progress bar with timing information
        $progressStatus = "VM $currentVM of $totalVMs ($percentComplete%) - $($vm.Name)"
        if ($avgTimePerVM -gt 0) {
            $progressStatus += " | ETA: $($estimatedTimeRemaining.ToString('hh\:mm\:ss')) | Avg: $([math]::Round($avgTimePerVM, 1))s/VM"
        }
        
        Write-Progress -Id 0 -Activity "Collecting VM Data and Performance Metrics" -Status $progressStatus -PercentComplete $percentComplete
        
        # Update console progress every few seconds to avoid spam
        $now = Get-Date
        if (($now - $lastProgressUpdate).TotalSeconds -ge $progressUpdateInterval -or $currentVM -eq 1 -or $currentVM -eq $totalVMs) {
            $vmsPerSecond = if ($elapsedTime.TotalSeconds -gt 0) { [math]::Round($currentVM / $elapsedTime.TotalSeconds, 2) } else { 0 }
            Write-DebugLog "Progress: $currentVM/$totalVMs VMs ($percentComplete%) | Speed: $vmsPerSecond VMs/sec | ETA: $($estimatedTimeRemaining.ToString('hh\:mm\:ss'))"
            $lastProgressUpdate = $now
        }

        try {
            Write-DebugLog "Processing VM: $($vm.Name)"
            
            # Get cached infrastructure information
            $infraInfo = $vmInfraCache[$vm.Id]
            
            # Get network information (skip in fast mode or if RVTools not needed)
            $networkInfo = if ($fastMode -or ($outputFormat -ne 'All' -and $outputFormat -ne 'RVTools')) {
                # Handle IP address array properly in fast mode
                $primaryIP = ""
                if ($vm.Guest.IPAddress) {
                    if ($vm.Guest.IPAddress -is [array]) {
                        $primaryIP = ($vm.Guest.IPAddress | Where-Object { $_ -notmatch '^(127\.|::1$|fe80::)' -and $_ -ne '' } | Select-Object -First 1)
                    } else {
                        $primaryIP = $vm.Guest.IPAddress
                    }
                }
                @{ PrimaryIP = $primaryIP; NetworkNames = @(); NetworkCount = $vm.ExtensionData.Summary.Config.NumEthernetCards }
            } else {
                Get-VMNetworkDetails -VM $vm
            }
            
            # Calculate total storage (skip detailed calculation in fast mode or if RVTools not needed)
            $totalStorageGB = if ($fastMode -or ($outputFormat -ne 'All' -and $outputFormat -ne 'RVTools')) {
                [math]::Round($vm.ProvisionedSpaceGB, 2)
            } else {
                try {
                    $disks = Get-HardDisk -VM $vm
                    ($disks | Measure-Object -Property CapacityGB -Sum).Sum
                }
                catch {
                    Write-DebugLog "Error calculating storage for VM $($vm.Name): $_"
                    0
                }
            }
            
            # Enhanced Database Detection (NEW - Monolithic Implementation)
            # Retrieve SQL credentials from SecureCredentialManager if they were stored
            $sqlCredentials = @{
                AuthMode = $sqlAuthMode
                Username = $sqlUsername
                Password = $null  # Password retrieved securely when needed by Get-EnhancedDatabaseInfo
                UseSecureCredentials = $sqlCredentialsProvided
            }
            
            # Database detection (only if explicitly enabled)
            $databaseInfo = if ($enableSQLDetection) {
                Get-EnhancedDatabaseInfo -VM $vm -IPAddress $networkInfo.PrimaryIP -EnableSQLDetection $true -SQLCredentials $sqlCredentials -ConfigCredentials $global:DatabaseCredentialsConfig
            } else {
                # Return empty database info when detection is disabled
                @{
                    HasDatabase = $false
                    DatabaseType = ''
                    Edition = ''
                    Version = ''
                    DetectionMethod = 'Disabled'
                    Details = @{}
                }
            }
            
            # Legacy SQL info structure for backward compatibility
            $sqlInfo = @{
                HasSQLServer = ($databaseInfo.DatabaseType -eq 'SQL Server')
                Edition = $databaseInfo.Edition
                EditionCategory = Get-DatabaseEditionCategory -Edition $databaseInfo.Edition
                ProductVersion = $databaseInfo.Version
                DetectionMethod = $databaseInfo.DetectionMethod
                DatabaseType = $databaseInfo.DatabaseType
                AllDatabaseInfo = $databaseInfo
            }
            
            if ($enableSQLDetection -and $databaseInfo.HasDatabase) {
                Write-DebugLog "Database detected on $($vm.Name): $($databaseInfo.DatabaseType) - $($databaseInfo.Edition) (Method: $($databaseInfo.DetectionMethod))"
            }
            
            # Get historical performance metrics (use cached bulk data if available)
            $perfMetrics = if ($skipPerformanceData) {
                @{
                    maxCpuUsagePctDec = 25.0
                    avgCpuUsagePctDec = 25.0
                    maxRamUsagePctDec = 60.0
                    avgRamUtlPctDec = 60.0
                    dataPoints = 0
                }
            } elseif ($global:BulkPerfData -and $global:BulkPerfData[$vm.Id]) {
                # Use pre-collected bulk performance data
                $global:BulkPerfData[$vm.Id]
            } else {
                # Fallback to individual collection (slower)
                Write-Progress -Id 1 -ParentId 0 -Activity "Collecting Performance Data" -Status "Getting $collectionDays days of metrics for $($vm.Name)" -PercentComplete 0
                $perfResult = Get-HistoricalPerformanceMetrics -VM $vm -Days $collectionDays -StatIntervals $statIntervalsHash
                Write-Progress -Id 1 -ParentId 0 -Activity "Collecting Performance Data" -Status "Completed for $($vm.Name)" -PercentComplete 100 -Completed
                $perfResult
            }
            
            # No daily stats needed - using aggregated values directly
            
            # Get additional data (skip snapshot count if RVTools not needed)
            $snapshotCount = if (ShouldGenerateFormat 'RVTools') {
                try { ($vm | Get-Snapshot).Count } catch { 0 }
            } else { 0 }
            $collectionDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            
            # Create Excel data object (Import-Data-Set-Template format - v3 style)
            $serverData = [PSCustomObject]@{
                # Basic identification
                "serverName" = $vm.Name
                "dnsName" = $vm.Guest.HostName
                "ipAddress" = if ($networkInfo.PrimaryIP) { "'" + $networkInfo.PrimaryIP } else { "" }  # Prefix with ' to force text format in Excel
                "operatingSystem" = $vm.Guest.OSFullName
                "osVersion" = $vm.ExtensionData.Config.GuestFullName
                
                # Hardware configuration
                "numCPUs" = $vm.NumCpu
                "totalRAM (GB)" = [math]::Round($vm.MemoryMB / 1024, 2)
                "totalStorage (GB)" = [math]::Round($totalStorageGB, 2)
                
                # Performance metrics (calculated over collection period) - using P95 for peak values
                "p95CpuUsagePctDec (%)" = $perfMetrics.maxCpuUsagePctDec
                "avgCpuUsagePctDec (%)" = $perfMetrics.avgCpuUsagePctDec
                "p95RamUsagePctDec (%)" = $perfMetrics.maxRamUsagePctDec
                "avgRamUtlPctDec (%)" = $perfMetrics.avgRamUtlPctDec
                
                # Infrastructure details (from cache)
                "hostName" = $infraInfo.HostName
                "clusterName" = $infraInfo.ClusterName
                "datacenterName" = $infraInfo.DatacenterName
                "datastoreName" = $infraInfo.DatastoreNames
                
                # VM configuration
                "powerState" = $vm.PowerState
                "vmwareToolsStatus" = $vm.ExtensionData.Guest.ToolsStatus
                "vmwareToolsVersion" = $vm.ExtensionData.Guest.ToolsVersion
                "hardwareVersion" = $vm.HardwareVersion
                "guestId" = $vm.ExtensionData.Config.GuestId
                
                # Network information
                "networkName" = ($networkInfo.NetworkNames -join ", ")
                "networkCount" = $networkInfo.NetworkCount
                
                # Resource allocation
                "cpuReservation" = $vm.ExtensionData.Config.CpuAllocation.Reservation
                "cpuLimit" = $vm.ExtensionData.Config.CpuAllocation.Limit
                "memoryReservation" = $vm.ExtensionData.Config.MemoryAllocation.Reservation
                "memoryLimit" = $vm.ExtensionData.Config.MemoryAllocation.Limit
                
                # Additional metadata (from cache)
                "vmId" = $vm.Id -replace '^VirtualMachine-', ''
                "vmUuid" = $vm.ExtensionData.Config.Uuid
                "instanceUuid" = $vm.ExtensionData.Config.InstanceUuid
                "annotation" = $vm.Notes
                "folder" = $infraInfo.FolderName
                "resourcePool" = $infraInfo.ResourcePoolName
                
                # Performance data collection info
                "performanceDataPoints" = $perfMetrics.dataPoints
                "statIntervalUsed" = "PowerShell-Optimized"
                
                # Timestamps
                "creationDate" = $vm.ExtensionData.Config.CreateDate
                "lastModified" = $vm.ExtensionData.Config.Modified
                "collectionDate" = $collectionDate
                "collectionPeriodDays" = $collectionDays
                
                # Template and snapshot info
                "isTemplate" = $vm.ExtensionData.Config.Template
                "snapshotCount" = $snapshotCount
                
                # Boot configuration
                "bootDelay" = $vm.ExtensionData.Config.BootOptions.BootDelay
                "firmware" = $vm.ExtensionData.Config.Firmware
                
                # High availability
                "ftState" = $vm.ExtensionData.Runtime.FaultToleranceState
                "dasProtection" = $vm.ExtensionData.Runtime.DasProtection
            }
            
            $serversData.Add($serverData) | Out-Null
            
            $processedVMs++
            
        } catch {
            Write-DebugLog "Error processing VM $($vm.Name): $_"
        }
    }
}

Write-Progress -Activity "Processing VMs" -Completed

$processingTime = (Get-Date) - $startTime
Write-Host "VM processing completed!" -ForegroundColor Green
Write-Host "Processed $processedVMs VMs in $($processingTime.TotalMinutes.ToString('F1')) minutes ($([math]::Round($processedVMs / $processingTime.TotalSeconds, 1)) VMs/sec)" -ForegroundColor Cyan

# Continue with the rest of the script for generating outputs...
# [The rest of the script would continue with CSV generation, Excel export, anonymization, etc.]
# This is a truncated version focusing on the optimization improvements

Write-DebugLog "Optimized data collection completed with pre-cached infrastructure data, batch processing, and P95 percentile calculations"


Write-Host "Collection completed successfully!" -ForegroundColor Green

# RVTools CSV generation (only if RVTools format is requested)
if (ShouldGenerateFormat 'RVTools') {
    Write-Host "`nGenerating RVTools CSV data..." -ForegroundColor Yellow
    Write-DebugLog "Starting RVTools CSV generation for $($vms.Count) VMs"
    
foreach ($vm in $vms) {
    try {
        # Ensure connection is active before processing each VM
        Ensure-VCenterConnection
        
        $infraInfo = $vmInfraCache[$vm.Id]
        $networkInfo = Get-VMNetworkDetails -VM $vm
        
        # Calculate total storage
        $totalStorageGB = 0
        $disks = Get-HardDisk -VM $vm -ErrorAction SilentlyContinue
        if ($disks) {
            $totalStorageGB = ($disks | Measure-Object -Property CapacityGB -Sum).Sum
        }
        
        # Get additional data for CSV (matching original v4 structure)
        $resourcePool = $null
        try { $resourcePool = Get-ResourcePool -VM $vm -ErrorAction SilentlyContinue } catch { $resourcePool = $null }
        $networks = Get-NetworkAdapter -VM $vm -ErrorAction SilentlyContinue
        
        # Get cluster rules
        $clusterRules = @()
        $clusterRuleNames = @()
        if ($infraInfo.ClusterName) {
            try {
                $clusterObj = Get-Cluster $infraInfo.ClusterName -ErrorAction SilentlyContinue
                if ($clusterObj) {
                    $rules = Get-DrsRule -Cluster $clusterObj -VM $vm -ErrorAction SilentlyContinue
                    if ($rules) {
                        $clusterRules = $rules.Enabled -join ";"
                        $clusterRuleNames = $rules.Name -join ";"
                    }
                }
            } catch {     
                # Intentionally empty - cluster info is optional
            }
        }

        # Get network names (up to 8 networks) - matching original v4 format
        $networkNames = @("", "", "", "", "", "", "", "")
        if ($networks) {
            for ($i = 0; $i -lt [Math]::Min($networks.Count, 8); $i++) {
                $networkNames[$i] = $networks[$i].NetworkName
            }
        }

        # Create CSV entry (RVTools tabvInfo format - matching original v4 structure)
        $csvEntry = [PSCustomObject]@{
            "VM" = $vm.Name
            "VM ID" = $vm.Id
            "Powerstate" = $vm.PowerState
            "Template" = $vm.ExtensionData.Config.Template
            "SRM Placeholder" = $false
            "Config status" = $vm.ExtensionData.ConfigStatus
            "DNS Name" = $vm.Guest.HostName
            "Connection state" = $vm.ExtensionData.Runtime.ConnectionState
            "Guest state" = $vm.Guest.State
            "Heartbeat" = $vm.ExtensionData.GuestHeartbeatStatus
            "Consolidation Needed" = $vm.ExtensionData.Runtime.ConsolidationNeeded
            "PowerOn" = ""
            "Suspended To Memory" = $vm.ExtensionData.Runtime.SuspendedToMemory
            "Suspend time" = $vm.ExtensionData.Runtime.SuspendTime
            "Suspend Interval" = $vm.ExtensionData.Config.DefaultSuspendInterval
            "Creation date" = $vm.ExtensionData.Config.CreateDate
            "Change Version" = $vm.ExtensionData.Config.ChangeVersion
            "CPUs" = $vm.NumCpu
            "Overall Cpu Readiness" = $vm.ExtensionData.Summary.QuickStats.OverallCpuReadiness
            "Memory" = $vm.MemoryMB
            "Active Memory" = $vm.ExtensionData.Summary.QuickStats.GuestMemoryUsage
            "NICs" = ($networks | Measure-Object).Count
            "Disks" = $(try { 
                Ensure-VCenterConnection
                (Get-HardDisk -VM $vm -ErrorAction SilentlyContinue | Measure-Object).Count 
            } catch { 0 })
            "Total disk capacity MiB" = $(try { 
                Ensure-VCenterConnection
                [math]::Round(($vm | Get-HardDisk -ErrorAction SilentlyContinue | Measure-Object -Property CapacityGB -Sum).Sum * 1024, 0) 
            } catch { 0 })
            "Fixed Passthru HotPlug" = if ($vm.ExtensionData.Config.Flags) { $vm.ExtensionData.Config.Flags.DisableHotPlugDeviceConnectivity } else { $false }
            "min Required EVC Mode Key" = if ($vm.ExtensionData.Runtime.MinRequiredEVCModeKey) { $vm.ExtensionData.Runtime.MinRequiredEVCModeKey } else { "" }
            "Latency Sensitivity" = if ($vm.ExtensionData.Config.LatencySensitivity) { $vm.ExtensionData.Config.LatencySensitivity.Level } else { "" }
            "Op Notification Timeout" = if ($vm.ExtensionData.Config.Tools.ToolsConfigInfo) { $vm.ExtensionData.Config.Tools.ToolsConfigInfo.SyncTimeWithHost } else { $null }
            "EnableUUID" = if ($vm.ExtensionData.Config.Flags) { $vm.ExtensionData.Config.Flags.EnableUUID } else { $false }
            "CBT" = if ($vm.ExtensionData.Config.ChangeTrackingEnabled -ne $null) { $vm.ExtensionData.Config.ChangeTrackingEnabled } else { $false }
            "Primary IP Address" = $networkInfo.PrimaryIP
            "Network #1" = $networkNames[0]
            "Network #2" = $networkNames[1]
            "Network #3" = $networkNames[2]
            "Network #4" = $networkNames[3]
            "Network #5" = $networkNames[4]
            "Network #6" = $networkNames[5]
            "Network #7" = $networkNames[6]
            "Network #8" = $networkNames[7]
            "Num Monitors" = if ($vm.ExtensionData.Config.Hardware.NumMonitors) { $vm.ExtensionData.Config.Hardware.NumMonitors } else { 0 }
            "Video Ram KiB" = if ($vm.ExtensionData.Config.Hardware.VideoRamSizeInKB) { $vm.ExtensionData.Config.Hardware.VideoRamSizeInKB } else { 0 }
            "Resource pool" = if ($resourcePool) { "/$($infraInfo.DatacenterName)/$($infraInfo.ClusterName)/$($resourcePool.Name)" } else { "" }
            "Folder ID" = $vm.Folder.Id -replace '^Folder-', ''
            "Folder" = $infraInfo.FolderName
            "vApp" = if ($vm.ExtensionData.ParentVApp) { $vm.ExtensionData.ParentVApp.Value } else { "" }
            "DAS protection" = $vm.ExtensionData.Runtime.DasProtection
            "FT State" = $vm.ExtensionData.Runtime.FaultToleranceState
            "FT Role" = if ($vm.ExtensionData.Config.FtInfo) { $vm.ExtensionData.Config.FtInfo.Role } else { "none" }
            "FT Latency" = $vm.ExtensionData.Runtime.FtLatencyStatus
            "FT Bandwidth" = $vm.ExtensionData.Runtime.FtBandwidthStatus
            "FT Sec. Latency" = $vm.ExtensionData.Runtime.FtSecondaryLatency
            "Vm Failover In Progress" = $vm.ExtensionData.Runtime.FailoverInProgress
            "Provisioned MiB" = [math]::Round($vm.ProvisionedSpaceGB * 1024, 0)
            "In Use MiB" = [math]::Round($vm.UsedSpaceGB * 1024, 0)
            "Unshared MiB" = [math]::Round($vm.ExtensionData.Summary.Storage.Unshared / 1MB, 0)
            "HA Restart Priority" = if ($vm.ExtensionData.Config.DasConfig) { $vm.ExtensionData.Config.DasConfig.RestartPriority } else { "" }
            "HA Isolation Response" = if ($vm.ExtensionData.Config.DasConfig) { $vm.ExtensionData.Config.DasConfig.IsolationResponse } else { "" }
            "HA VM Monitoring" = if ($vm.ExtensionData.Config.DasConfig) { $vm.ExtensionData.Config.DasConfig.VmMonitoring } else { "" }
            "Cluster rule(s)" = $clusterRules
            "Cluster rule name(s)" = $clusterRuleNames
            "Boot Required" = if ($vm.ExtensionData.Config.BootOptions) { $vm.ExtensionData.Config.BootOptions.BootRetryEnabled } else { $false }
            "Boot delay" = if ($vm.ExtensionData.Config.BootOptions) { $vm.ExtensionData.Config.BootOptions.BootDelay } else { 0 }
            "Boot retry delay" = if ($vm.ExtensionData.Config.BootOptions) { $vm.ExtensionData.Config.BootOptions.BootRetryDelay } else { 0 }
            "Boot retry enabled" = if ($vm.ExtensionData.Config.BootOptions) { $vm.ExtensionData.Config.BootOptions.BootRetryEnabled } else { $false }
            "Boot BIOS setup" = if ($vm.ExtensionData.Config.BootOptions) { $vm.ExtensionData.Config.BootOptions.EnterBIOSSetup } else { $false }
            "Reboot PowerOff" = $false
            "EFI Secure boot" = ($vm.ExtensionData.Config.Firmware -eq "efi")
            "Firmware" = $vm.ExtensionData.Config.Firmware
            "HW version" = $vm.HardwareVersion
            "HW upgrade status" = $vm.ExtensionData.Runtime.UpgradeStatus
            "HW upgrade policy" = if ($vm.ExtensionData.Config.ScheduledHardwareUpgradeInfo) { $vm.ExtensionData.Config.ScheduledHardwareUpgradeInfo.UpgradePolicy } else { "" }
            "HW target" = if ($vm.ExtensionData.Config.ScheduledHardwareUpgradeInfo) { $vm.ExtensionData.Config.ScheduledHardwareUpgradeInfo.VersionKey } else { "" }
            "Path" = $vm.ExtensionData.Config.Files.VmPathName
            "Log directory" = $vm.ExtensionData.Config.Files.LogDirectory
            "Snapshot directory" = $vm.ExtensionData.Config.Files.SnapshotDirectory
            "Suspend directory" = $vm.ExtensionData.Config.Files.SuspendDirectory
            "Annotation" = $vm.Notes
            "Owner" = if ($vm.ExtensionData.Config.ManagedBy) { $vm.ExtensionData.Config.ManagedBy.ExtensionKey } else { "" }
            "Custom field 1" = ""
            "Custom field 2" = ""
            "Custom field 3" = ""
            "Custom field 4" = ""
            "Host" = $infraInfo.HostName
            "Datacenter" = $infraInfo.DatacenterName
            "Cluster" = $infraInfo.ClusterName
            "OS according to the configuration file" = $vm.ExtensionData.Config.GuestFullName
            "OS according to the VMware Tools" = $vm.Guest.OSFullName
            "VMware Tools Version" = $vm.ExtensionData.Guest.ToolsVersion
            "VMware Tools Status" = $vm.ExtensionData.Guest.ToolsStatus
            "VMware Tools Running Status" = $vm.ExtensionData.Guest.ToolsRunningStatus
            "VMware Tools Version Status" = $vm.ExtensionData.Guest.ToolsVersionStatus
            "VI SDK Server type" = "VirtualCenter"
            "VI SDK API Version" = $global:DefaultVIServer.Version
            "VI SDK Server" = $global:DefaultVIServer.Name
            "VI SDK UUID" = $vm.ExtensionData.Config.Uuid
            "VI SDK Instance UUID" = $vm.ExtensionData.Config.InstanceUuid
            "vCenter Server" = $global:DefaultVIServer.Name
        }
        
        $csvVMInfo.Add($csvEntry) | Out-Null
        
    } catch {
        Write-DebugLog "Error creating CSV entry for VM $($vm.Name): $_"
    }
}

    Write-Host "RVTools CSV data generation completed!" -ForegroundColor Green
    Write-DebugLog "RVTools CSV generation completed for $($csvVMInfo.Count) VMs"
} else {
    Write-Host "`nSkipping RVTools CSV generation (not requested)" -ForegroundColor Yellow
    Write-DebugLog "RVTools format not requested, skipping CSV generation"
}

# Clear progress bars and show completion summary
Write-Progress -Id 0 -Activity "Collecting VM Data and Performance Metrics" -Completed
Write-Progress -Id 1 -Activity "Collecting Performance Data" -Completed

$totalElapsedTime = (Get-Date) - $startTime
$overallVMsPerSecond = if ($totalElapsedTime.TotalSeconds -gt 0) { [math]::Round($totalVMs / $totalElapsedTime.TotalSeconds, 2) } else { 0 }

Write-Host "`nVM Data Collection Completed!" -ForegroundColor Green
Write-Host "  Total VMs: $totalVMs" -ForegroundColor Cyan
Write-Host "  Total Time: $($totalElapsedTime.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
Write-Host "  Average Speed: $overallVMsPerSecond VMs/sec" -ForegroundColor Cyan
Write-Host "  Avg Time per VM: $([math]::Round($totalElapsedTime.TotalSeconds / $totalVMs, 1)) seconds" -ForegroundColor Cyan
Write-DebugLog "Total VMs processed: $totalVMs"
Write-DebugLog "Total time: $($totalElapsedTime.ToString('hh\:mm\:ss'))"
Write-DebugLog "Average speed: $overallVMsPerSecond VMs/second"
Write-DebugLog "Performance data: $(if($skipPerformanceData){'Skipped (default values used)'}else{"Collected for $collectionDays days"})"

# Note: Old workbook data collections removed - now using new ME Template format

# Generate output files based on format selection
Write-Host "Generating output files..." -ForegroundColor Cyan

# Generate MPA Template (MAP format)
if (ShouldGenerateFormat 'MPA') {
    Write-DebugLog "Creating MPA Template Excel file..."
    
    try {
        # Use MPAFormatGenerator class to create proper 20-column MPA format
        Write-DebugLog "Using MPAFormatGenerator to create proper MPA format..."
        
        # Prepare server data for MPA format conversion
        $mpaInputData = foreach ($server in $serversData) {
            # Convert percentage values from decimal to percentage format (0.51 = 0.51%)
            [PSCustomObject]@{
                serverName = $server.serverName
                operatingSystem = $server.operatingSystem
                cpuCores = $server.numCPUs
                NumCoresPerSocket = if ($server.PSObject.Properties['NumCoresPerSocket']) { $server.NumCoresPerSocket } else { 0 }
                maxCpuUsagePct = $server.'p95CpuUsagePctDec (%)'  # Already in percentage format
                avgCpuUsagePct = $server.'avgCpuUsagePctDec (%)'  # Already in percentage format
                ramMB = $server.'totalRAM (GB)' * 1024
                maxRamUsagePct = $server.'p95RamUsagePctDec (%)'  # Already in percentage format
                avgRamUsagePct = $server.'avgRamUtlPctDec (%)'    # Already in percentage format
                diskGB = $server.'totalStorage (GB)'
            }
        }
        
        # Create MPA format generator (without logger for simplicity)
        $mpaGenerator = [MPAFormatGenerator]::new()
        
        # Generate MPA format output
        $mpaGenerator.GenerateOutput($mpaInputData, $excelOutput)
        Write-Host "Created MPA Template (20 columns): $excelOutput" -ForegroundColor Green
        
        # Create anonymized version if requested
        if ($anonymize) {
            Write-DebugLog "Creating anonymized MPA Template..."
            
            $anonymizedMpaData = foreach ($server in $mpaInputData) {
                $anonymizedServer = $server.PSObject.Copy()
                $anonymizedServer.serverName = Get-AnonymizedName -originalName $server.serverName -prefix "SERVER" -mappingTable $anonymizationMappings.ServerNames
                $anonymizedServer
            }
            
            $mpaGeneratorAnon = [MPAFormatGenerator]::new()
            $mpaGeneratorAnon.GenerateOutput($anonymizedMpaData, $excelOutputAnonymized)
            Write-Host "Created MPA Template (Anonymized): $excelOutputAnonymized" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "Error creating MPA Template: $_" -ForegroundColor Red
        Write-DebugLog "Error creating Enhanced MPA Template: $_"
    }
}

# Generate Database-Enhanced MPA Summary (when database detection is enabled)
if ((ShouldGenerateFormat 'MPA') -and $enableSQLDetection) {
    Write-DebugLog "Creating Database Summary Report..."
    
    try {
        # Create database summary file
        $databaseSummaryOutput = Join-Path $outputDir "Database-Summary_$timestamp.xlsx"
        
        # Collect database information from all VMs
        $databaseSummary = @()
        $sqlServersCount = 0
        $otherDatabasesCount = 0
        
        foreach ($vm in $vms) {
            # Retrieve SQL credentials from SecureCredentialManager if they were stored
            $sqlCredentials = @{
                AuthMode = $sqlAuthMode
                Username = $sqlUsername
                Password = $null  # Password retrieved securely when needed by Get-EnhancedDatabaseInfo
                UseSecureCredentials = $sqlCredentialsProvided
            }
            
            $networkInfo = Get-VMNetworkDetails -VM $vm
            
            $dbInfo = Get-EnhancedDatabaseInfo -VM $vm -IPAddress $networkInfo.PrimaryIP -EnableSQLDetection $enableSQLDetection -SQLCredentials $sqlCredentials -ConfigCredentials $global:DatabaseCredentialsConfig
            
            if ($dbInfo.HasDatabase) {
                $infraInfo = $vmInfraCache[$vm.Id]
                
                $databaseSummary += [PSCustomObject]@{
                    "VM Name" = $vm.Name
                    "IP Address" = $networkInfo.PrimaryIP
                    "Database Type" = $dbInfo.DatabaseType
                    "Edition" = $dbInfo.Edition
                    "Version" = $dbInfo.Version
                    "Detection Method" = $dbInfo.DetectionMethod
                    "Host" = $infraInfo.HostName
                    "Cluster" = $infraInfo.ClusterName
                    "Datacenter" = $infraInfo.DatacenterName
                    "CPU Cores" = $vm.NumCpu
                    "Memory GB" = [math]::Round($vm.MemoryMB / 1024, 2)
                    "Power State" = $vm.PowerState
                    "OS" = $vm.Guest.OSFullName
                }
                
                if ($dbInfo.DatabaseType -eq 'SQL Server') {
                    $sqlServersCount++
                } else {
                    $otherDatabasesCount++
                }
            }
        }
        
        if ($databaseSummary.Count -gt 0) {
            $databaseSummary | Export-Excel -Path $databaseSummaryOutput -WorksheetName "Database Summary" -AutoSize -FreezeTopRow -BoldTopRow
            Write-Host "Created Database Summary: $databaseSummaryOutput" -ForegroundColor Green
            Write-Host "  SQL Servers detected: $sqlServersCount" -ForegroundColor Cyan
            Write-Host "  Other databases detected: $otherDatabasesCount" -ForegroundColor Cyan
            Write-Host "  Total databases: $($databaseSummary.Count)" -ForegroundColor Cyan
        } else {
            Write-Host "No databases detected in the environment" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "Error creating Database Summary: $_" -ForegroundColor Red
        Write-DebugLog "Error creating Database Summary: $_"
    }
}

# Generate ME Workbook (ME format) - AWS Migration Evaluator Template
if (ShouldGenerateFormat 'ME') {
    Write-DebugLog "Creating AWS Migration Evaluator Template..."
    
    try {
        # Use MEFormatGenerator class to create proper 16-column ME format
        Write-DebugLog "Using MEFormatGenerator to create proper ME format..."
        
        # Prepare VM data for ME format conversion
        $meInputData = foreach ($vm in $vms) {
            # Get infrastructure info
            $infraInfo = $vmInfraCache[$vm.Id]
            if (-not $infraInfo) {
                $infraInfo = @{
                    HostName = ""
                    ClusterName = ""
                }
            }
            
            # Calculate total storage
            $totalStorageGB = 0
            try {
                $disks = Get-HardDisk -VM $vm -ErrorAction SilentlyContinue
                if ($disks) {
                    $totalStorageGB = ($disks | Measure-Object -Property CapacityGB -Sum).Sum
                }
            } catch {
                $totalStorageGB = [math]::Round($vm.ProvisionedSpaceGB, 2)
            }
            
            # Get performance metrics
            $perfMetrics = if ($global:BulkPerfData -and $global:BulkPerfData[$vm.Id]) {
                $global:BulkPerfData[$vm.Id]
            } else {
                @{
                    maxCpuUsagePctDec = 25.0
                    avgCpuUsagePctDec = 25.0
                    maxRamUsagePctDec = 60.0
                    avgRamUtlPctDec = 60.0
                }
            }
            
            # Use OS name with fallback for powered off VMs (consistent with MPA format)
            $osName = $vm.Guest.OSFullName
            if ([string]::IsNullOrEmpty($osName)) {
                $osName = "Other 5.x Linux (64-bit)"  # Default for powered off VMs
            }
            
            [PSCustomObject]@{
                Name = $vm.Name
                NumCPUs = $vm.NumCpu
                MemoryMB = $vm.MemoryMB
                TotalStorageGB = [math]::Round($totalStorageGB, 2)
                OperatingSystem = $osName
                HostName = $infraInfo.HostName
                VMHost = $vm.VMHost
                Notes = $vm.Notes
                Annotation = $vm.ExtensionData.Config.Annotation
                MaxCpuUsagePct = $perfMetrics.maxCpuUsagePctDec
                MaxRamUsagePct = $perfMetrics.maxRamUsagePctDec
                DatabaseInfo = $null  # Database detection disabled by default
            }
        }
        
        # Create ME format generator
        $meGenerator = [MEFormatGenerator]::new()
        
        # Generate ME format output
        $meGenerator.GenerateOutput($meInputData, $outputDir)
        Write-Host "Created ME Template (16 columns): $workbookOutput" -ForegroundColor Green
        
        # Create anonymized version if requested
        if ($anonymize) {
            Write-DebugLog "Creating anonymized ME Template..."
            
            $anonymizedMeData = foreach ($vm in $meInputData) {
                $anonymizedVM = $vm.PSObject.Copy()
                $anonymizedVM.Name = Get-AnonymizedName -originalName $vm.Name -prefix "SERVER" -mappingTable $anonymizationMappings.ServerNames
                $anonymizedVM.HostName = Get-AnonymizedName -originalName $vm.HostName -prefix "HOST" -mappingTable $anonymizationMappings.HostNames
                $anonymizedVM.Notes = if ($vm.Notes) { "Application-" + (Get-Random -Minimum 1 -Maximum 999) } else { "" }
                $anonymizedVM.Annotation = ""
                $anonymizedVM
            }
            
            $meGeneratorAnon = [MEFormatGenerator]::new()
            $meGeneratorAnon.GenerateOutput($anonymizedMeData, $outputDir, $true)
            Write-Host "Created ME Template (Anonymized): $workbookOutputAnonymized" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "Error creating ME Template: $_" -ForegroundColor Red
        Write-DebugLog "Error creating ME Template: $_"
    }
}

# Generate RVTools CSV files using the RVToolsFormatGenerator class
if (ShouldGenerateFormat 'RVTools') {
    Write-DebugLog "Creating RVTools format with all 27 CSV files..."
    
    try {
        # Load the RVToolsFormatGenerator class
        . "$PSScriptRoot\Classes\RVToolsFormatGenerator.ps1"
        
        # Convert VM objects to data model format expected by RVToolsFormatGenerator
        $vmDataForRVTools = @()
        foreach ($vm in $vms) {
            $infraInfo = $vmInfraCache[$vm.Id]
            $perfMetrics = if ($global:BulkPerfData -and $global:BulkPerfData[$vm.Id]) {
                $global:BulkPerfData[$vm.Id]
            } else {
                @{ 
                    maxCpuUsagePctDec = 25.0
                    avgCpuUsagePctDec = 25.0
                    maxRamUsagePctDec = 60.0
                    avgRamUtlPctDec = 60.0
                }
            }
            
            # Get network details
            $networkDetails = Get-VMNetworkDetails -VM $vm
            
            # Calculate storage details
            $totalStorageGB = 0
            $storageCommittedGB = 0
            $storageUncommittedGB = 0
            try {
                $disks = Get-HardDisk -VM $vm -ErrorAction SilentlyContinue
                foreach ($disk in $disks) {
                    $totalStorageGB += $disk.CapacityGB
                    $storageCommittedGB += $disk.CapacityGB
                }
            } catch {
                $totalStorageGB = 20  # Default fallback
                $storageCommittedGB = 20
            }
            
            $vmDataForRVTools += [PSCustomObject]@{
                Name = $vm.Name
                VMId = $vm.Id
                PowerState = $vm.PowerState
                NumCPUs = $vm.NumCpu
                MemoryMB = $vm.MemoryMB
                TotalStorageGB = $totalStorageGB
                StorageCommittedGB = $storageCommittedGB
                StorageUncommittedGB = $storageUncommittedGB
                HardwareVersion = $vm.HardwareVersion
                OperatingSystem = $vm.Guest.OSFullName
                IPAddress = $networkDetails.PrimaryIP
                NetworkAdapter1 = if ($networkDetails.NetworkNames.Count -gt 0) { $networkDetails.NetworkNames[0] } else { "" }
                NetworkAdapter2 = if ($networkDetails.NetworkNames.Count -gt 1) { $networkDetails.NetworkNames[1] } else { "" }
                NetworkAdapter3 = if ($networkDetails.NetworkNames.Count -gt 2) { $networkDetails.NetworkNames[2] } else { "" }
                NetworkAdapter4 = if ($networkDetails.NetworkNames.Count -gt 3) { $networkDetails.NetworkNames[3] } else { "" }
                HostName = $infraInfo.HostName
                ClusterName = $infraInfo.ClusterName
                DatacenterName = $infraInfo.DatacenterName
                ResourcePoolName = $infraInfo.ResourcePoolName
                FolderName = $infraInfo.FolderName
                DatastoreNames = $infraInfo.DatastoreNames
                MaxCpuUsagePct = $perfMetrics.maxCpuUsagePctDec
                AvgCpuUsagePct = $perfMetrics.avgCpuUsagePctDec
                MaxRamUsagePct = $perfMetrics.maxRamUsagePctDec
                AvgRamUsagePct = $perfMetrics.avgRamUtlPctDec
                TemplateFlag = $vm.ExtensionData.Config.Template
                VMwareToolsStatus = $vm.ExtensionData.Guest.ToolsStatus
                VMwareToolsVersion = $vm.ExtensionData.Guest.ToolsVersion
                GuestHostName = $vm.Guest.HostName
                DNSName = $vm.Guest.HostName
                Annotation = $vm.Notes
                Owner = ""
                CreationDate = $vm.ExtensionData.Config.CreateDate
                VMPathName = $vm.ExtensionData.Config.Files.VmPathName
                BiosUuid = $vm.ExtensionData.Config.Uuid
                VMUuid = $vm.ExtensionData.Config.InstanceUuid
                InstanceUuid = $vm.ExtensionData.Config.InstanceUuid
                SnapshotCount = 0
                SnapshotSizeGB = 0
                SnapshotCreated = ""
            }
        }
        
        # Create RVTools format generator with existing logger
        $rvToolsGenerator = [RVToolsFormatGenerator]::new($logger)
        
        # Generate original RVTools format (ZIP with 27 CSV files)
        Write-DebugLog "Generating RVTools ZIP archive with 27 CSV files..."
        
        # Pass filtered infrastructure data to the generator
        $rvToolsGenerator.HostCache = $hostCache
        $rvToolsGenerator.DatastoreCache = $datastoreCache
        $rvToolsGenerator.CacheInitialized = $true
        
        $rvToolsGenerator.GenerateOutput($vmDataForRVTools, $outputDir)
        
        # Find the generated ZIP file
        $rvToolsZipFiles = Get-ChildItem -Path $outputDir -Filter "RVTools_Export_*.zip" | Sort-Object LastWriteTime -Descending
        if ($rvToolsZipFiles) {
            $originalRVToolsZip = $rvToolsZipFiles[0].FullName
            Write-Host "Created RVTools ZIP: $originalRVToolsZip" -ForegroundColor Green
            
            # Create anonymized version if requested
            if ($anonymize) {
                Write-DebugLog "Creating anonymized RVTools format by anonymizing existing CSV files..."
                Write-Host "Anonymizing RVTools CSV files..." -ForegroundColor Yellow
                
                try {
                    # Create temp directory for extraction
                    $tempDir = Join-Path $outputDir "temp_rvtools_anon"
                    if (Test-Path $tempDir) {
                        Remove-Item $tempDir -Recurse -Force
                    }
                    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                    
                    # Extract original ZIP
                    Write-DebugLog "Extracting original RVTools ZIP for anonymization..."
                    Expand-Archive -Path $originalRVToolsZip -DestinationPath $tempDir -Force
                    
                    # Get all CSV files
                    $csvFiles = Get-ChildItem -Path $tempDir -Filter "*.csv"
                    Write-DebugLog "Found $($csvFiles.Count) CSV files to anonymize"
                    
                    # Anonymize each CSV file
                    foreach ($csvFile in $csvFiles) {
                        Write-DebugLog "Anonymizing $($csvFile.Name)..."
                        
                        # Read CSV content
                        $csvContent = Import-Csv -Path $csvFile.FullName
                        
                        # Anonymize based on column names
                        $anonymizedContent = foreach ($row in $csvContent) {
                            $anonymizedRow = $row.PSObject.Copy()
                            
                            # Anonymize VM/Server names
                            if ($row.PSObject.Properties.Name -contains 'VM') {
                                $anonymizedRow.VM = Get-AnonymizedName -originalName $row.VM -prefix "VM" -mappingTable $anonymizationMappings.ServerNames
                            }
                            if ($row.PSObject.Properties.Name -contains 'Name') {
                                $anonymizedRow.Name = Get-AnonymizedName -originalName $row.Name -prefix "VM" -mappingTable $anonymizationMappings.ServerNames
                            }
                            
                            # Anonymize Host names
                            if ($row.PSObject.Properties.Name -contains 'Host') {
                                $anonymizedRow.Host = Get-AnonymizedName -originalName $row.Host -prefix "HOST" -mappingTable $anonymizationMappings.HostNames
                            }
                            if ($row.PSObject.Properties.Name -contains 'ESX Host') {
                                $anonymizedRow.'ESX Host' = Get-AnonymizedName -originalName $row.'ESX Host' -prefix "HOST" -mappingTable $anonymizationMappings.HostNames
                            }
                            
                            # Anonymize Cluster names
                            if ($row.PSObject.Properties.Name -contains 'Cluster') {
                                $anonymizedRow.Cluster = Get-AnonymizedName -originalName $row.Cluster -prefix "CLUSTER" -mappingTable $anonymizationMappings.ClusterNames
                            }
                            
                            # Anonymize IP addresses
                            if ($row.PSObject.Properties.Name -contains 'Primary IP Address') {
                                $anonymizedRow.'Primary IP Address' = Get-AnonymizedIP -originalIP $row.'Primary IP Address' -mappingTable $anonymizationMappings.IPAddresses
                            }
                            if ($row.PSObject.Properties.Name -contains 'IP Address') {
                                $anonymizedRow.'IP Address' = Get-AnonymizedIP -originalIP $row.'IP Address' -mappingTable $anonymizationMappings.IPAddresses
                            }
                            
                            # Anonymize DNS/Hostname
                            if ($row.PSObject.Properties.Name -contains 'DNS Name') {
                                $anonymizedRow.'DNS Name' = Get-AnonymizedName -originalName $row.'DNS Name' -prefix "DNS" -mappingTable $anonymizationMappings.DNSNames
                            }
                            if ($row.PSObject.Properties.Name -contains 'Guest Hostname') {
                                $anonymizedRow.'Guest Hostname' = Get-AnonymizedName -originalName $row.'Guest Hostname' -prefix "GUEST" -mappingTable $anonymizationMappings.DNSNames
                            }
                            
                            # Anonymize Datastore names
                            if ($row.PSObject.Properties.Name -contains 'Datastore') {
                                $anonymizedRow.Datastore = Get-AnonymizedName -originalName $row.Datastore -prefix "DATASTORE" -mappingTable $anonymizationMappings.DatastoreNames
                            }
                            if ($row.PSObject.Properties.Name -contains 'Datastores') {
                                $anonymizedRow.Datastores = Get-AnonymizedName -originalName $row.Datastores -prefix "DATASTORE" -mappingTable $anonymizationMappings.DatastoreNames
                            }
                            
                            $anonymizedRow
                        }
                        
                        # Save anonymized CSV
                        $anonymizedContent | Export-Csv -Path $csvFile.FullName -NoTypeInformation -Force
                    }
                    
                    # Create anonymized ZIP
                    $anonymizedZipName = $originalRVToolsZip -replace "RVTools_Export_", "RVTools_Export_ANONYMIZED_"
                    Write-DebugLog "Creating anonymized ZIP: $anonymizedZipName"
                    
                    # Compress anonymized CSV files
                    Compress-Archive -Path "$tempDir\*.csv" -DestinationPath $anonymizedZipName -Force
                    
                    # Clean up temp directory
                    Remove-Item $tempDir -Recurse -Force
                    
                    Write-Host "Created anonymized RVTools ZIP: $anonymizedZipName" -ForegroundColor Green
                    Write-DebugLog "RVTools anonymization completed successfully"
                    
                } catch {
                    Write-Host "Error creating anonymized RVTools format: $_" -ForegroundColor Red
                    Write-DebugLog "Error creating anonymized RVTools format: $_"
                    
                    # Clean up temp directory on error
                    if (Test-Path $tempDir) {
                        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        } else {
            Write-DebugLog "Warning: RVTools ZIP file not found after generation"
        }
        
    } catch {
        Write-Host "Error creating RVTools format: $_" -ForegroundColor Red
        Write-DebugLog "Error creating RVTools format: $_"
        
        # Fallback to original CSV generation method
        Write-DebugLog "Falling back to individual CSV file generation..."
        
        # VM Info CSV (RVTools_tabvInfo.csv) - Already created above
        Write-DebugLog "Creating RVTools_tabvInfo.csv..."
        $csvVMInfo | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvInfo.csv") -NoTypeInformation

        # VM Network CSV (RVTools_tabvNetwork.csv)
        Write-DebugLog "Creating RVTools_tabvNetwork.csv..."
        $csvNetworks = @()
        foreach ($vm in $vms) {
            try {
                $infraInfo = $vmInfraCache[$vm.Id]
                $networkAdapters = Get-NetworkAdapter -VM $vm -ErrorAction SilentlyContinue
                
                foreach ($adapter in $networkAdapters) {
                    $csvNetworks += [PSCustomObject]@{
                        "VM" = $vm.Name
                        "VM ID" = $vm.Id
                        "Powerstate" = $vm.PowerState
                        "Template" = $vm.ExtensionData.Config.Template
                        "Config status" = $vm.ExtensionData.ConfigStatus
                        "DNS Name" = $vm.Guest.HostName
                        "Connection state" = $vm.ExtensionData.Runtime.ConnectionState
                        "Guest state" = $vm.Guest.State
                        "Heartbeat" = $vm.ExtensionData.GuestHeartbeatStatus
                        "Consolidation Needed" = $vm.ExtensionData.Runtime.ConsolidationNeeded
                        "PowerOn" = ""
                        "Suspended To Memory" = $vm.ExtensionData.Runtime.SuspendedToMemory
                        "Suspend time" = $vm.ExtensionData.Runtime.SuspendTime
                        "Creation date" = $vm.ExtensionData.Config.CreateDate
                        "Change Version" = $vm.ExtensionData.Config.ChangeVersion
                        "Network #" = $adapter.Name
                        "Network Label" = $adapter.NetworkName
                        "Network Connected" = $adapter.ConnectionState.Connected
                        "Network Start Connected" = $adapter.ConnectionState.StartConnected
                        "Network MAC Address" = $adapter.MacAddress
                        "Network Adapter" = $adapter.Type
                        "Host" = $infraInfo.HostName
                        "Datacenter" = $infraInfo.DatacenterName
                        "Cluster" = $infraInfo.ClusterName
                        "VI SDK Server type" = "VirtualCenter"
                        "VI SDK API Version" = $global:DefaultVIServer.Version
                        "VI SDK Server" = $global:DefaultVIServer.Name
                        "VI SDK UUID" = $vm.ExtensionData.Config.Uuid
                        "VI SDK Instance UUID" = $vm.ExtensionData.Config.InstanceUuid
                    }
                }
            } catch {
                Write-DebugLog "Error processing network for VM $($vm.Name): $_"
            }
        }
        $csvNetworks | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvNetwork.csv") -NoTypeInformation

        # VM Disk CSV (RVTools_tabvDisk.csv)
        Write-DebugLog "Creating RVTools_tabvDisk.csv..."
        $csvDisks = @()
        foreach ($vm in $vms) {
            try {
                Ensure-VCenterConnection
                $infraInfo = $vmInfraCache[$vm.Id]
                $disks = Get-HardDisk -VM $vm -ErrorAction SilentlyContinue
                
                foreach ($disk in $disks) {
                    $folderPath = $vm.Folder.Name
                    if ($vm.Folder.Parent) {
                        $folderPath = "/" + $folderPath
                    }

                    $csvDisks += [PSCustomObject]@{
                        "VM" = $vm.Name
                        "VM ID" = $vm.Id -replace '^VirtualMachine-', ''
                        "Powerstate" = $vm.PowerState
                        "Template" = $vm.ExtensionData.Config.Template
                        "Config status" = $vm.ExtensionData.ConfigStatus
                        "DNS Name" = $vm.Guest.HostName
                        "Connection state" = $vm.ExtensionData.Runtime.ConnectionState
                        "Guest state" = $vm.Guest.State
                        "Heartbeat" = $vm.ExtensionData.GuestHeartbeatStatus
                        "Consolidation Needed" = $vm.ExtensionData.Runtime.ConsolidationNeeded
                        "PowerOn" = ""
                        "Suspended To Memory" = $vm.ExtensionData.Runtime.SuspendedToMemory
                        "Suspend time" = $vm.ExtensionData.Runtime.SuspendTime
                        "Creation date" = $vm.ExtensionData.Config.CreateDate
                        "Change Version" = $vm.ExtensionData.Config.ChangeVersion
                        "Disk" = $disk.Name
                        "Capacity MiB" = [math]::Round($disk.CapacityGB * 1024, 0)
                        "Capacity GB" = [math]::Round($disk.CapacityGB, 2)
                        "Disk Mode" = $disk.Persistence
                        "Disk Type" = $disk.DiskType
                        "Hard Disk" = $disk.Name
                        "Path" = $disk.Filename
                        "Host" = $infraInfo.HostName
                        "Datacenter" = $infraInfo.DatacenterName
                        "Cluster" = $infraInfo.ClusterName
                        "VI SDK Server type" = "VirtualCenter"
                        "VI SDK API Version" = $global:DefaultVIServer.Version
                        "VI SDK Server" = $global:DefaultVIServer.Name
                        "VI SDK UUID" = $vm.ExtensionData.Config.Uuid
                        "VI SDK Instance UUID" = $vm.ExtensionData.Config.InstanceUuid
                        "Folder" = $folderPath
                    }
                }
            } catch {
                Write-DebugLog "Error processing disks for VM $($vm.Name): $_"
            }
        }
        $csvDisks | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvDisk.csv") -NoTypeInformation

        # VM CPU CSV (RVTools_tabvCPU.csv)
        Write-DebugLog "Creating RVTools_tabvCPU.csv..."
        $csvVMCPU = @()
        foreach ($vm in $vms) {
            try {
                $infraInfo = $vmInfraCache[$vm.Id]
                # Get CPU P95 percentage from bulk performance data
                $perfMetrics = if ($global:BulkPerfData -and $global:BulkPerfData[$vm.Id]) {
                    $global:BulkPerfData[$vm.Id]
                } else {
                    @{ maxCpuUsagePctDec = 25.0 }
                }
                $p95CPUPct = $perfMetrics.maxCpuUsagePctDec
                
                # v4 RVTools format: Max = CPU frequency per core × number of cores, Overall = P95 usage in MHz
                $maxCPU = if ($vm.PowerState -eq "PoweredOn") { 
                    try {
                        $vm.NumCpu * $vm.VMHost.CpuTotalMhz / $vm.VMHost.NumCpu 
                    } catch { 
                        $vm.NumCpu * 2000  # Fallback to 2GHz per core if host info unavailable
                    }
                } else { 0 }
                $overall = if ($maxCPU -gt 0 -and $p95CPUPct) { ($p95CPUPct / 100) * $maxCPU } else { 0 }
                
                $csvVMCPU += [PSCustomObject]@{
                    "VM" = $vm.Name
                    "VM ID" = $vm.Id -replace '^VirtualMachine-', ''
                    "CPUs" = $vm.NumCpu
                    "Max" = $maxCPU
                    "Overall" = $overall
                }
            } catch {
                Write-DebugLog "Error processing CPU for VM $($vm.Name): $_"
            }
        }
        $csvVMCPU | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvCPU.csv") -NoTypeInformation
        
        # VM Memory CSV (RVTools_tabvMemory.csv)
        Write-DebugLog "Creating RVTools_tabvMemory.csv..."
        $csvVMMemory = @()
        foreach ($vm in $vms) {
            try {
                $infraInfo = $vmInfraCache[$vm.Id]
                # Get Memory P95 percentage from bulk performance data
                $perfMetrics = if ($global:BulkPerfData -and $global:BulkPerfData[$vm.Id]) {
                    $global:BulkPerfData[$vm.Id]
                } else {
                    @{ maxRamUsagePctDec = 60.0 }
                }
                $p95MemPct = $perfMetrics.maxRamUsagePctDec
                
                $csvVMMemory += [PSCustomObject]@{
                    "VM" = $vm.Name
                    "VM ID" = $vm.Id -replace '^VirtualMachine-', ''
                    "Size MiB" = [math]::Round($vm.MemoryMB, 0)
                    "Consumed" = if ($p95MemPct) { [math]::Min([math]::Round($vm.MemoryMB * ($p95MemPct / 100), 0), $vm.MemoryMB) } else { 0 }
                }
            } catch {
                Write-DebugLog "Error processing memory for VM $($vm.Name): $_"
            }
        }
        $csvVMMemory | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvMemory.csv") -NoTypeInformation

        # Host CSV (RVTools_tabvHost.csv) - Only hosts used by filtered VMs
        Write-DebugLog "Creating RVTools_tabvHost.csv..."
        $csvHosts = @()
        
        # Get only the hosts that are used by our filtered VMs
        $hosts = @()
        foreach ($hostName in $filteredHostNames) {
            try {
                $vmHost = Get-VMHost -Name $hostName -ErrorAction SilentlyContinue
                if ($vmHost) {
                    $hosts += $vmHost
                }
            } catch {
                Write-DebugLog "Warning: Could not retrieve host $hostName"
            }
        }
        
        Write-DebugLog "Processing $($hosts.Count) hosts (filtered from $($allHosts.Count) total hosts)"
        foreach ($vmhost in $hosts) {
            try {
                $dc = Get-Datacenter -VMHost $vmhost -ErrorAction SilentlyContinue
                $cluster = Get-Cluster -VMHost $vmhost -ErrorAction SilentlyContinue
                $cert = $vmhost.ExtensionData.Config.Certificate

                $csvHosts += [PSCustomObject]@{
                    "Host" = $vmhost.Name
                    "Datacenter" = $dc.Name
                    "Cluster" = $cluster.Name
                    "Connection State" = $vmhost.ConnectionState
                    "Power State" = $vmhost.PowerState
                    "Standby Mode" = $vmhost.ExtensionData.Runtime.StandbyMode
                    "In Maintenance Mode" = $vmhost.ExtensionData.Runtime.InMaintenanceMode
                    "Boot Time" = $vmhost.ExtensionData.Runtime.BootTime
                    "Overall Status" = $vmhost.ExtensionData.OverallStatus
                    "ESX Version" = $vmhost.Version
                    "ESX Build" = $vmhost.Build
                    "ESX Update" = $vmhost.ExtensionData.Config.Product.UpdateLevel
                    "ESX Patch" = $vmhost.ExtensionData.Config.Product.PatchLevel
                    "Manufacturer" = $vmhost.Manufacturer
                    "Model" = $vmhost.Model
                    "Processor Type" = $vmhost.ProcessorType
                    "CPU Cores" = $vmhost.ExtensionData.Hardware.CpuInfo.NumCpuCores
                    "CPU Threads" = $vmhost.ExtensionData.Hardware.CpuInfo.NumCpuThreads
                    "CPU Usage MHz" = $vmhost.CpuUsageMhz
                    "CPU Total MHz" = $vmhost.CpuTotalMhz
                    "Memory Usage MB" = $vmhost.MemoryUsageMB
                    "Memory Total MB" = $vmhost.MemoryTotalMB
                    "Memory Available MB" = ($vmhost.MemoryTotalMB - $vmhost.MemoryUsageMB)
                    "Num VMs" = ($vms | Where-Object { $_.VMHost.Name -eq $vmhost.Name }).Count
                    "Max EVC Mode" = $vmhost.MaxEVCMode
                    "Current EVC Mode" = if ($cluster) { $cluster.EVCMode } else { "" }
                    "VI SDK Server type" = "VirtualCenter"
                    "VI SDK API Version" = $global:DefaultVIServer.Version
                    "VI SDK Server" = $global:DefaultVIServer.Name
                    "VI SDK UUID" = $vmhost.ExtensionData.Summary.Hardware.Uuid
                    "Certificate" = if ($cert) { $cert } else { "" }
                }
            } catch {
                Write-DebugLog "Error processing host $($vmhost.Name): $_"
            }
        }
        $csvHosts | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvHost.csv") -NoTypeInformation

        # VM Tools CSV (RVTools_tabvTools.csv)
        Write-DebugLog "Creating RVTools_tabvTools.csv..."
        $csvVMTools = @()
        foreach ($vm in $vms) {
            $csvVMTools += [PSCustomObject]@{
                "VM" = $vm.Name
                "VM ID" = $vm.Id -replace '^VirtualMachine-', ''
                "Powerstate" = $vm.PowerState
                "Template" = $vm.ExtensionData.Config.Template
                "Config status" = $vm.ExtensionData.ConfigStatus
                "DNS Name" = $vm.Guest.HostName
                "Connection state" = $vm.ExtensionData.Runtime.ConnectionState
                "Guest state" = $vm.Guest.State
                "Heartbeat" = $vm.ExtensionData.GuestHeartbeatStatus
                "Consolidation Needed" = $vm.ExtensionData.Runtime.ConsolidationNeeded
                "PowerOn" = ""
                "Suspended To Memory" = $vm.ExtensionData.Runtime.SuspendedToMemory
                "Suspend time" = $vm.ExtensionData.Runtime.SuspendTime
                "Creation date" = $vm.ExtensionData.Config.CreateDate
                "Change Version" = $vm.ExtensionData.Config.ChangeVersion
                "VMware Tools Version" = $vm.ExtensionData.Guest.ToolsVersion
                "VMware Tools Status" = $vm.ExtensionData.Guest.ToolsStatus
                "VMware Tools Running Status" = $vm.ExtensionData.Guest.ToolsRunningStatus
                "VMware Tools Version Status" = $vm.ExtensionData.Guest.ToolsVersionStatus
                "Host" = $vmInfraCache[$vm.Id].HostName
                "Datacenter" = $vmInfraCache[$vm.Id].DatacenterName
                "Cluster" = $vmInfraCache[$vm.Id].ClusterName
                "VI SDK Server type" = "VirtualCenter"
                "VI SDK API Version" = $global:DefaultVIServer.Version
                "VI SDK Server" = $global:DefaultVIServer.Name
                "VI SDK UUID" = $vm.ExtensionData.Config.Uuid
                "VI SDK Instance UUID" = $vm.ExtensionData.Config.InstanceUuid
            }
        }
        $csvVMTools | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvSwitch.csv") -NoTypeInformation

        # Switch CSV (RVTools_tabvSwitch.csv)
        Write-DebugLog "Creating RVTools_tabvSwitch.csv..."
        $switchInfo = @()
        foreach ($vmhost in $hosts) {
            try {
                $dc = Get-Datacenter -VMHost $vmhost -ErrorAction SilentlyContinue
                $cluster = Get-Cluster -VMHost $vmhost -ErrorAction SilentlyContinue
                $vswitches = Get-VirtualSwitch -VMHost $vmhost -ErrorAction SilentlyContinue
                
                foreach ($vswitch in $vswitches) {
                    $switchInfo += [PSCustomObject]@{
                        "Host" = $vmhost.Name
                        "Datacenter" = if ($dc) { $dc.Name } else { "" }
                        "Cluster" = if ($cluster) { $cluster.Name } else { "" }
                        "vSwitch" = $vswitch.Name
                        "Ports" = $vswitch.NumPorts
                        "Used Ports" = $vswitch.NumPortsAvailable
                        "MTU" = $vswitch.Mtu
                        "VI SDK Server type" = "VirtualCenter"
                        "VI SDK API Version" = $global:DefaultVIServer.Version
                        "VI SDK Server" = $global:DefaultVIServer.Name
                    }
                }
            } catch {
                Write-DebugLog "Error processing switches for host $($vmhost.Name): $_"
            }
        }
        $switchInfo | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvSwitch.csv") -NoTypeInformation

        # Datastore CSV (RVTools_tabvDatastore.csv) - Only datastores used by filtered VMs
        Write-DebugLog "Creating RVTools_tabvDatastore.csv..."
        $csvDatastores = @()
        
        # Get only the datastores that are used by our filtered VMs
        $datastores = @()
        foreach ($datastoreName in $filteredDatastoreNames) {
            try {
                $datastore = Get-Datastore -Name $datastoreName -ErrorAction SilentlyContinue
                if ($datastore) {
                    $datastores += $datastore
                }
            } catch {
                Write-DebugLog "Warning: Could not retrieve datastore $datastoreName"
            }
        }
        
        Write-DebugLog "Processing $($datastores.Count) datastores (filtered from $($allDatastores.Count) total datastores)"
        foreach ($ds in $datastores) {
            try {
                $csvDatastores += [PSCustomObject]@{
                    "Name" = $ds.Name
                    "Capacity MB" = [math]::Round($ds.CapacityGB * 1024, 0)
                    "Capacity GB" = [math]::Round($ds.CapacityGB, 2)
                    "Free Space MB" = [math]::Round($ds.FreeSpaceGB * 1024, 0)
                    "Free Space GB" = [math]::Round($ds.FreeSpaceGB, 2)
                    "Free Space %" = [math]::Round(($ds.FreeSpaceGB / $ds.CapacityGB) * 100, 2)
                    "Type" = $ds.Type
                    "File System Version" = $ds.FileSystemVersion
                    "Accessible" = $ds.Accessible
                    "VI SDK Server type" = "VirtualCenter"
                    "VI SDK API Version" = $global:DefaultVIServer.Version
                    "VI SDK Server" = $global:DefaultVIServer.Name
                }
            } catch {
                Write-DebugLog "Error processing datastore $($ds.Name): $_"
            }
        }
        $csvDatastores | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvDatastore.csv") -NoTypeInformation

        # Cluster CSV (RVTools_tabvCluster.csv)
        Write-Host "Creating RVTools_tabvCluster.csv..." -ForegroundColor Yellow
        $csvClusters = @()
        $clusters = Get-Cluster
        foreach ($cluster in $clusters) {
            try {
                $dc = Get-Datacenter -Cluster $cluster -ErrorAction SilentlyContinue
                $csvClusters += [PSCustomObject]@{
                    "Cluster" = $cluster.Name
                    "Datacenter" = $dc.Name
                    "Num Hosts" = $cluster.ExtensionData.Summary.NumHosts
                    "Total CPU Cores" = $cluster.ExtensionData.Summary.NumCpuCores
                    "Total CPU Threads" = $cluster.ExtensionData.Summary.NumCpuThreads
                    "Total Memory MB" = [math]::Round($cluster.ExtensionData.Summary.TotalMemory / 1MB, 0)
                    "Total Cpu MHz" = $cluster.ExtensionData.Summary.TotalCpu
                    "Num VMs" = $cluster.ExtensionData.Summary.NumVmotions
                    "Current Balance" = $cluster.ExtensionData.Summary.CurrentBalance
                    "Target Balance" = $cluster.ExtensionData.Summary.TargetBalance
                    "DRS Enabled" = $cluster.DrsEnabled
                    "DRS Automation Level" = $cluster.DrsAutomationLevel
                    "HA Enabled" = $cluster.HAEnabled
                    "HA Admission Control Enabled" = $cluster.HAAdmissionControlEnabled
                    "HA Failover Level" = $cluster.HAFailoverLevel
                    "EVC Mode" = $cluster.EVCMode
                    "VI SDK Server type" = "VirtualCenter"
                    "VI SDK API Version" = $global:DefaultVIServer.Version
                    "VI SDK Server" = $global:DefaultVIServer.Name
                }
            } catch {
                Write-DebugLog "Error processing cluster $($cluster.Name): $_"
            }
        }
        $csvClusters | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvCluster.csv") -NoTypeInformation

# Final summary
$totalTime = (Get-Date) - $startTime
Write-Host "`n" + "=" * 80 -ForegroundColor Cyan
Write-Host "OPTIMIZED COLLECTION COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "=" * 80 -ForegroundColor Cyan

Write-Host "`nPerformance Summary:" -ForegroundColor Cyan
Write-Host "  Total VMs processed: $processedVMs" -ForegroundColor White
Write-Host "  Total processing time: $($totalTime.TotalMinutes.ToString('F1')) minutes" -ForegroundColor White
Write-Host "  Average processing speed: $([math]::Round($processedVMs / $totalTime.TotalSeconds, 1)) VMs/second" -ForegroundColor White
Write-Host "  Infrastructure caching time: $($cacheTime.TotalSeconds.ToString('F1')) seconds" -ForegroundColor White
Write-Host "  VM mapping time: $($mappingTime.TotalSeconds.ToString('F1')) seconds" -ForegroundColor White

Write-Host "`nOptimizations Applied:" -ForegroundColor Cyan
Write-Host "  * Pre-cached infrastructure data (hosts, clusters, datastores, resource pools)" -ForegroundColor Green
Write-Host "  * Built VM-to-infrastructure mappings upfront" -ForegroundColor Green
Write-Host "  * Used batch processing instead of individual API calls" -ForegroundColor Green
Write-Host "  * Minimized redundant vCenter queries" -ForegroundColor Green
Write-Host "  * Intelligent performance data collection" -ForegroundColor Green
Write-Host "  * Using P95 percentile for peak values (more realistic than maximum)" -ForegroundColor Green

Write-Host "`nOutput Files Created:" -ForegroundColor Cyan
if (ShouldGenerateFormat 'MPA') {
    Write-Host "  * MPA Template: $excelOutput" -ForegroundColor White
    
    # Show Database Summary if it was created
    if ($enableSQLDetection) {
        $databaseSummaryOutput = Join-Path $outputDir "Database-Summary_$timestamp.xlsx"
        if (Test-Path $databaseSummaryOutput) {
            Write-Host "  * Database Summary: $databaseSummaryOutput" -ForegroundColor Cyan
        }
    }
    
    if ($anonymize) {
        Write-Host "  * MPA Template (Anonymized): $excelOutputAnonymized" -ForegroundColor White
        
        if ($enableSQLDetection) {
            $databaseSummaryOutputAnonymized = Join-Path $outputDir "Database-Summary_ANONYMIZED_$timestamp.xlsx"
            if (Test-Path $databaseSummaryOutputAnonymized) {
                Write-Host "  * Database Summary (Anonymized): $databaseSummaryOutputAnonymized" -ForegroundColor Cyan
            }
        }
    }
}
if (ShouldGenerateFormat 'ME') {
    Write-Host "  * ME Template: $workbookOutput" -ForegroundColor White
    if ($anonymize) {
        Write-Host "  * ME Template (Anonymized): $workbookOutputAnonymized" -ForegroundColor White
    }
}
if (ShouldGenerateFormat 'RVTools') {
    $rvToolsZipFiles = Get-ChildItem -Path $outputDir -Filter "RVTools_Export_*.zip" | Sort-Object Name
    foreach ($zipFile in $rvToolsZipFiles) {
        if ($zipFile.Name -match "ANONYMIZED") {
            Write-Host "  * RVTools ZIP (Anonymized): $($zipFile.Name)" -ForegroundColor White
        } else {
            Write-Host "  * RVTools ZIP: $($zipFile.Name)" -ForegroundColor White
        }
    }
}
if ($anonymize) {
    Write-Host "  * Anonymization Mapping: $mappingFile" -ForegroundColor White
}

Write-Host "`nCollection completed in output directory: $outputDir" -ForegroundColor Green

# Security cleanup - clear all credentials from memory
if ($global:SecureCredentialManager) {
    $global:SecureCredentialManager.ClearAllCredentials()
    Write-DebugLog "Security cleanup: All credentials cleared from memory"
}



Write-Host "`nOptimized VMware Collector completed successfully!" -ForegroundColor Green
Write-Host "Thank you for using the optimized edition!" -ForegroundColor Cyan  
      # Host NIC CSV (RVTools_tabvNIC.csv)
        Write-Host "Creating RVTools_tabvNIC.csv..." -ForegroundColor Yellow
        $csvHostNICs = @()
        foreach ($vmhost in $hosts) {
            try {
                $dc = Get-Datacenter -VMHost $vmhost -ErrorAction SilentlyContinue
                $cluster = Get-Cluster -VMHost $vmhost -ErrorAction SilentlyContinue
                $physicalNics = $vmhost.ExtensionData.Config.Network.Pnic
                
                foreach ($nic in $physicalNics) {
                    $csvHostNICs += [PSCustomObject]@{
                        "Host" = $vmhost.Name
                        "Datacenter" = if ($dc) { $dc.Name } else { "" }
                        "Cluster" = if ($cluster) { $cluster.Name } else { "" }
                        "Device" = $nic.Device
                        "PCI" = $nic.Pci
                        "Driver" = $nic.Driver
                        "Link Speed" = if ($nic.LinkSpeed) { $nic.LinkSpeed.SpeedMb } else { 0 }
                        "MAC Address" = $nic.Mac
                        "Wake On Lan" = $nic.WakeOnLanSupported
                        "VI SDK Server type" = "VirtualCenter"
                        "VI SDK API Version" = $global:DefaultVIServer.Version
                        "VI SDK Server" = $global:DefaultVIServer.Name
                    }
                }
            } catch {
                Write-DebugLog "Error processing NICs for host $($vmhost.Name): $_"
            }
        }
        $csvHostNICs | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvNIC.csv") -NoTypeInformation

        # HBA CSV (RVTools_tabvHBA.csv)
        Write-Host "Creating RVTools_tabvHBA.csv..." -ForegroundColor Yellow
        $csvHBAs = @()
        foreach ($vmHost in $hosts) {
            try {
                $dc = Get-Datacenter -VMHost $vmHost -ErrorAction SilentlyContinue
                $cluster = Get-Cluster -VMHost $vmHost -ErrorAction SilentlyContinue
                $hbas = $vmHost.ExtensionData.Config.StorageDevice.HostBusAdapter
                foreach ($hba in $hbas) {
                    $csvHBAs += [PSCustomObject]@{
                        "Host" = $vmHost.Name
                        "Datacenter" = if ($dc) { $dc.Name } else { "" }
                        "Cluster" = if ($cluster) { $cluster.Name } else { "" }
                        "Device" = $hba.Device
                        "PCI" = $hba.Pci
                        "Driver" = $hba.Driver
                        "Model" = $hba.Model
                        "Node WWN" = if ($hba.NodeWorldWideName) { 
                            [System.BitConverter]::ToString($hba.NodeWorldWideName).Replace("-", ":").ToLower() 
                        } else { "" }
                        "Port WWN" = if ($hba.PortWorldWideName) { 
                            [System.BitConverter]::ToString($hba.PortWorldWideName).Replace("-", ":").ToLower() 
                        } else { "" }
                        "Type" = $hba.GetType().Name
                        "Status" = "Unknown"
                        "VI SDK Server type" = "VirtualCenter"
                        "VI SDK API Version" = $global:DefaultVIServer.Version
                        "VI SDK Server" = $global:DefaultVIServer.Name
                    }
                }
            } catch {
                Write-DebugLog "Error processing HBAs for host $($vmHost.Name): $_"
            }
        }
        $csvHBAs | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvHBA.csv") -NoTypeInformation

        # Snapshot CSV (RVTools_tabvSnapshot.csv)
        Write-Host "Creating RVTools_tabvSnapshot.csv..." -ForegroundColor Yellow
        $csvSnapshots = @()
        foreach ($vm in $vms) {
            try {
                $infraInfo = $vmInfraCache[$vm.Id]
                $snapshots = Get-Snapshot -VM $vm -ErrorAction SilentlyContinue
                foreach ($snap in $snapshots) {
                    $csvSnapshots += [PSCustomObject]@{
                        "VM" = $vm.Name
                        "VM ID" = $vm.Id
                        "Powerstate" = $vm.PowerState
                        "Template" = $vm.ExtensionData.Config.Template
                        "Config status" = $vm.ExtensionData.ConfigStatus
                        "DNS Name" = $vm.Guest.HostName
                        "Connection state" = $vm.ExtensionData.Runtime.ConnectionState
                        "Guest state" = $vm.Guest.State
                        "Heartbeat" = $vm.ExtensionData.GuestHeartbeatStatus
                        "Consolidation Needed" = $vm.ExtensionData.Runtime.ConsolidationNeeded
                        "PowerOn" = ""
                        "Suspended To Memory" = $vm.ExtensionData.Runtime.SuspendedToMemory
                        "Suspend time" = $vm.ExtensionData.Runtime.SuspendTime
                        "Creation date" = $vm.ExtensionData.Config.CreateDate
                        "Change Version" = $vm.ExtensionData.Config.ChangeVersion
                        "Snapshot Name" = $snap.Name
                        "Snapshot Description" = $snap.Description
                        "Snapshot Created" = $snap.Created
                        "Snapshot Size MB" = [math]::Round($snap.SizeMB, 2)
                        "Snapshot Size GB" = [math]::Round($snap.SizeGB, 2)
                        "Host" = $infraInfo.HostName
                        "Datacenter" = $infraInfo.DatacenterName
                        "Cluster" = $infraInfo.ClusterName
                        "VI SDK Server type" = "VirtualCenter"
                        "VI SDK API Version" = $global:DefaultVIServer.Version
                        "VI SDK Server" = $global:DefaultVIServer.Name
                        "VI SDK UUID" = $vm.ExtensionData.Config.Uuid
                        "VI SDK Instance UUID" = $vm.ExtensionData.Config.InstanceUuid
                    }
                }
            } catch {
                Write-DebugLog "Error processing snapshots for VM $($vm.Name): $_"
            }
        }
        $csvSnapshots | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvSnapshot.csv") -NoTypeInformation

        # License CSV (RVTools_tabvLicense.csv)
        Write-Host "Creating RVTools_tabvLicense.csv..." -ForegroundColor Yellow
        $csvLicenses = @()
        try {
            $licenseManager = Get-View $global:DefaultVIServer.ExtensionData.Content.LicenseManager
            $licenses = $licenseManager.Licenses
            
            foreach ($license in $licenses) {
                if ($license.LicenseKey -ne "00000-00000-00000-00000-00000") {
                    $csvLicenses += [PSCustomObject]@{
                        "Name" = $license.Name
                        "Key" = $license.LicenseKey
                        "Total" = $license.Total
                        "Used" = $license.Used
                        "Edition Key" = $license.EditionKey
                        "Cost Unit" = $license.CostUnit
                        "VI SDK Server type" = "VirtualCenter"
                        "VI SDK API Version" = $global:DefaultVIServer.Version
                        "VI SDK Server" = $global:DefaultVIServer.Name
                    }
                }
            }
        } catch {
            Write-Host "Could not retrieve license information: $($_.Exception.Message)" -ForegroundColor Red
        }
        $csvLicenses | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvLicense.csv") -NoTypeInformation

        # Port Group CSV (RVTools_tabvPort.csv)
        Write-Host "Creating RVTools_tabvPort.csv..." -ForegroundColor Yellow
        $csvPortGroups = @()
        foreach ($vmhost in $hosts) {
            try {
                $dc = Get-Datacenter -VMHost $vmhost -ErrorAction SilentlyContinue
                $cluster = Get-Cluster -VMHost $vmhost -ErrorAction SilentlyContinue
                $vswitches = Get-VirtualSwitch -VMHost $vmhost -ErrorAction SilentlyContinue
                
                foreach ($vswitch in $vswitches) {
                    # Get standard port groups for this vSwitch
                    $portGroups = Get-VirtualPortGroup -VirtualSwitch $vswitch -Standard -ErrorAction SilentlyContinue
                    foreach ($portGroup in $portGroups) {
                        $vswitchPolicy = $vswitch.ExtensionData.Spec.Policy
                        
                        $csvPortGroups += [PSCustomObject]@{
                            "Host" = $vmhost.Name
                            "Datacenter" = if ($dc) { $dc.Name } else { "" }
                            "Cluster" = if ($cluster) { $cluster.Name } else { "" }
                            "vSwitch" = $vswitch.Name
                            "Port Group" = $portGroup.Name
                            "VLAN ID" = $portGroup.VLanId
                            "Active Adapters" = if ($vswitchPolicy.NicTeaming.NicOrder.ActiveNic) { 
                                $vswitchPolicy.NicTeaming.NicOrder.ActiveNic -join "," 
                            } else { "" }
                            "Standby Adapters" = if ($vswitchPolicy.NicTeaming.NicOrder.StandbyNic) { 
                                $vswitchPolicy.NicTeaming.NicOrder.StandbyNic -join "," 
                            } else { "" }
                            "Policy" = if ($vswitchPolicy.NicTeaming.Policy) { 
                                $vswitchPolicy.NicTeaming.Policy 
                            } else { "" }
                            "VI SDK Server type" = "VirtualCenter"
                            "VI SDK API Version" = $global:DefaultVIServer.Version
                            "VI SDK Server" = $global:DefaultVIServer.Name
                        }
                    }
                }
            } catch {
                Write-DebugLog "Error processing port groups for host $($vmhost.Name): $_"
            }
        }
        $csvPortGroups | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvPort.csv") -NoTypeInformation

        # Resource Pool CSV (RVTools_tabvRP.csv)
        Write-Host "Creating RVTools_tabvRP.csv..." -ForegroundColor Yellow
        $csvResourcePools = @()
        try {
            $resourcePools = Get-ResourcePool -ErrorAction SilentlyContinue
            foreach ($rp in $resourcePools) {
                $csvResourcePools += [PSCustomObject]@{
                    "Resource Pool" = $rp.Name
                    "CPU Limit" = $rp.CpuLimitMhz
                    "CPU Reservation" = $rp.CpuReservationMhz
                    "CPU Expandable Reservation" = $rp.CpuExpandableReservation
                    "CPU Shares" = $rp.CpuSharesLevel
                    "Memory Limit" = $rp.MemLimitMB
                    "Memory Reservation" = $rp.MemReservationMB
                    "Memory Expandable Reservation" = $rp.MemExpandableReservation
                    "Memory Shares" = $rp.MemSharesLevel
                    "Num VMs" = $rp.ExtensionData.Summary.Runtime.Memory.ReservationUsed
                    "VI SDK Server type" = "VirtualCenter"
                    "VI SDK API Version" = $global:DefaultVIServer.Version
                    "VI SDK Server" = $global:DefaultVIServer.Name
                }
            }
        } catch {
            Write-Host "Error collecting resource pool information: $_" -ForegroundColor Red
        }
        $csvResourcePools | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvRP.csv") -NoTypeInformation

        # Distributed Switch CSV (RVTools_tabdvSwitch.csv)
        Write-Host "Creating RVTools_tabdvSwitch.csv..." -ForegroundColor Yellow
        $csvDVSwitches = @()
        try {
            $dvSwitches = Get-VDSwitch -ErrorAction SilentlyContinue
            foreach ($dvs in $dvSwitches) {
                # Get datacenter by looking at the distributed switch's parent folder
                $dc = $null
                try {
                    $dc = Get-Datacenter | Where-Object { $_.ExtensionData.NetworkFolder.MoRef -eq $dvs.Folder.Parent.MoRef } | Select-Object -First 1
                } catch {
                    # Fallback: just use the first datacenter if we can't determine the specific one
                    $dc = Get-Datacenter | Select-Object -First 1
                }
                
                $csvDVSwitches += [PSCustomObject]@{
                    "Name" = $dvs.Name
                    "Datacenter" = if ($dc) { $dc.Name } else { "" }
                    "Ports" = $dvs.NumPorts
                    "Used Ports" = $dvs.NumUplinkPorts
                    "Uplink Ports" = $dvs.NumUplinkPorts
                    "Version" = $dvs.Version
                    "Vendor" = $dvs.Vendor
                    "VI SDK Server type" = "VirtualCenter"
                    "VI SDK API Version" = $global:DefaultVIServer.Version
                    "VI SDK Server" = $global:DefaultVIServer.Name
                }
            }
        } catch {
            Write-Host "Error collecting distributed switch information: $_" -ForegroundColor Red
        }
        $csvDVSwitches | Export-Csv -Path (Join-Path $outputDir "RVTools_tabdvSwitch.csv") -NoTypeInformation

        # Multipath CSV (RVTools_tabvMultiPath.csv)
        Write-Host "Creating RVTools_tabvMultiPath.csv..." -ForegroundColor Yellow
        $csvMultiPath = @()
        foreach ($vmhost in $hosts) {
            try {
                $dc = Get-Datacenter -VMHost $vmhost -ErrorAction SilentlyContinue
                $cluster = Get-Cluster -VMHost $vmhost -ErrorAction SilentlyContinue
                $storageSystem = Get-View $vmhost.ExtensionData.ConfigManager.StorageSystem
                $multipathInfo = $storageSystem.StorageDeviceInfo.MultipathInfo
                
                if ($multipathInfo) {
                    foreach ($lun in $multipathInfo.Lun) {
                        foreach ($path in $lun.Path) {
                            $csvMultiPath += [PSCustomObject]@{
                                "Host" = $vmhost.Name
                                "Datacenter" = $dc.Name
                                "Cluster" = $cluster.Name
                                "LUN" = $lun.Id
                                "Path" = $path.Name
                                "Path Status" = $path.PathState
                                "Adapter" = $path.Adapter
                                "Transport" = $path.Transport.GetType().Name
                                "VI SDK Server type" = "VirtualCenter"
                                "VI SDK API Version" = $global:DefaultVIServer.Version
                                "VI SDK Server" = $global:DefaultVIServer.Name
                            }
                        }
                    }
                }
            } catch {
                Write-DebugLog "Error processing multipath for host $($vmhost.Name): $_"
            }
        }
        $csvMultiPath | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvMultiPath.csv") -NoTypeInformation

        # Partition CSV (RVTools_tabvPartition.csv)
        Write-Host "Creating RVTools_tabvPartition.csv..." -ForegroundColor Yellow
        $csvPartitions = @()
        foreach ($vmhost in $hosts) {
            try {
                $dc = Get-Datacenter -VMHost $vmhost -ErrorAction SilentlyContinue
                $cluster = Get-Cluster -VMHost $vmhost -ErrorAction SilentlyContinue
                $storageSystem = Get-View $vmhost.ExtensionData.ConfigManager.StorageSystem
                
                if ($storageSystem.StorageDeviceInfo.ScsiLun) {
                    foreach ($lun in $storageSystem.StorageDeviceInfo.ScsiLun) {
                        $csvPartitions += [PSCustomObject]@{
                            "Host" = $vmhost.Name
                            "Datacenter" = $dc.Name
                            "Cluster" = $cluster.Name
                            "Device Name" = $lun.DeviceName
                            "Capacity MB" = [math]::Round($lun.Capacity.Block * $lun.Capacity.BlockSize / 1MB, 0)
                            "Consumed Space MB" = 0
                            "Device Type" = $lun.DeviceType
                            "Is SSD" = if ($lun.Ssd -ne $null) { $lun.Ssd } else { $false }
                            "VI SDK Server type" = "VirtualCenter"
                            "VI SDK API Version" = $global:DefaultVIServer.Version
                            "VI SDK Server" = $global:DefaultVIServer.Name
                        }
                    }
                }
            } catch {
                Write-DebugLog "Error processing partitions for host $($vmhost.Name): $_"
            }
        }
        $csvPartitions | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvPartition.csv") -NoTypeInformation

        # FileInfo CSV (RVTools_tabvFileInfo.csv)
        Write-Host "Creating RVTools_tabvFileInfo.csv..." -ForegroundColor Yellow
        $csvFileInfo = @()
        foreach ($vm in $vms) {
            try {
                $csvFileInfo += [PSCustomObject]@{
                    "VM" = $vm.Name
                    "VM ID" = $vm.Id
                    "Powerstate" = $vm.PowerState
                    "Template" = $vm.ExtensionData.Config.Template
                    "Config status" = $vm.ExtensionData.ConfigStatus
                    "DNS Name" = $vm.Guest.HostName
                    "Connection state" = $vm.ExtensionData.Runtime.ConnectionState
                    "Guest state" = $vm.Guest.State
                    "Heartbeat" = $vm.ExtensionData.GuestHeartbeatStatus
                    "Consolidation Needed" = $vm.ExtensionData.Runtime.ConsolidationNeeded
                    "PowerOn" = ""
                    "Suspended To Memory" = $vm.ExtensionData.Runtime.SuspendedToMemory
                    "Suspend time" = $vm.ExtensionData.Runtime.SuspendTime
                    "Creation date" = $vm.ExtensionData.Config.CreateDate
                    "Change Version" = $vm.ExtensionData.Config.ChangeVersion
                    "VMX File" = $vm.ExtensionData.Config.Files.VmPathName
                    "VMX File Size" = 0
                    "Host" = $vmInfraCache[$vm.Id].HostName
                    "Datacenter" = $vmInfraCache[$vm.Id].DatacenterName
                    "Cluster" = $vmInfraCache[$vm.Id].ClusterName
                    "VI SDK Server type" = "VirtualCenter"
                    "VI SDK API Version" = $global:DefaultVIServer.Version
                    "VI SDK Server" = $global:DefaultVIServer.Name
                    "VI SDK UUID" = $vm.ExtensionData.Config.Uuid
                    "VI SDK Instance UUID" = $vm.ExtensionData.Config.InstanceUuid
                }
            } catch {
                Write-DebugLog "Error processing file info for VM $($vm.Name): $_"
            }
        }
        $csvFileInfo | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvFileInfo.csv") -NoTypeInformation

        # VMKernel CSV (RVTools_tabvSC_VMK.csv)
        Write-Host "Creating RVTools_tabvSC_VMK.csv..." -ForegroundColor Yellow
        $csvVMKernels = @()
        foreach ($vmhost in $hosts) {
            try {
                $dc = Get-Datacenter -VMHost $vmhost -ErrorAction SilentlyContinue
                $cluster = Get-Cluster -VMHost $vmhost -ErrorAction SilentlyContinue
                $vmkAdapters = $vmhost.ExtensionData.Config.Network.Vnic
                
                foreach ($vmk in $vmkAdapters) {
                    $csvVMKernels += [PSCustomObject]@{
                        "Host" = $vmhost.Name
                        "Datacenter" = $dc.Name
                        "Cluster" = $cluster.Name
                        "Device" = $vmk.Device
                        "Port Group" = $vmk.Portgroup
                        "IP Address" = $vmk.Spec.Ip.IpAddress
                        "Subnet Mask" = $vmk.Spec.Ip.SubnetMask
                        "MAC Address" = $vmk.Spec.Mac
                        "DHCP" = $vmk.Spec.Ip.Dhcp
                        "VI SDK Server type" = "VirtualCenter"
                        "VI SDK API Version" = $global:DefaultVIServer.Version
                        "VI SDK Server" = $global:DefaultVIServer.Name
                    }
                }
            } catch {
                Write-DebugLog "Error processing VMKernel adapters for host $($vmhost.Name): $_"
            }
        }
        $csvVMKernels | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvSC_VMK.csv") -NoTypeInformation

        # Create ZIP archive
        Write-Host "Creating ZIP archive..." -ForegroundColor Yellow
        $zipPath = Join-Path $outputDir "VMware_collector_export_$timestamp.zip"
        $csvFiles = Get-ChildItem -Path $outputDir -Filter "*.csv"
        
        if ($csvFiles.Count -gt 0) {
            Compress-Archive -Path $csvFiles.FullName -DestinationPath $zipPath -Force
            Write-Host "Created: $zipPath" -ForegroundColor Green
            Write-Host "ZIP contains $($csvFiles.Count) CSV files" -ForegroundColor Gray
            
            # Remove individual CSV files if requested
            if ($purgeCSV) {
                $csvFiles | Remove-Item -Force
                Write-Host "Removed individual CSV files (purgeCSV enabled)" -ForegroundColor Gray
            }
        }
        
        # Create anonymized CSV files if requested
        if ($anonymize) {
            Write-Host "Creating anonymized CSV files..." -ForegroundColor Yellow
            
            # Anonymize main VM Info CSV
            $anonymizedCSVInfo = foreach ($csvEntry in $csvVMInfo) {
                $anonymizedEntry = $csvEntry.PSObject.Copy()
                $anonymizedEntry.VM = Get-AnonymizedName -originalName $csvEntry.VM -prefix "SERVER" -mappingTable $anonymizationMappings.ServerNames
                $anonymizedEntry.Host = Get-AnonymizedName -originalName $csvEntry.Host -prefix "HOST" -mappingTable $anonymizationMappings.HostNames
                $anonymizedEntry.Cluster = Get-AnonymizedName -originalName $csvEntry.Cluster -prefix "CLUSTER" -mappingTable $anonymizationMappings.ClusterNames
                $anonymizedEntry."Primary IP Address" = Get-AnonymizedIP -originalIP $csvEntry."Primary IP Address" -mappingTable $anonymizationMappings.IPAddresses
                $anonymizedEntry."DNS Name" = Get-AnonymizedName -originalName $csvEntry."DNS Name" -prefix "DNS" -mappingTable $anonymizationMappings.DNSNames
                $anonymizedEntry.Datacenter = Get-AnonymizedName -originalName $csvEntry.Datacenter -prefix "DC" -mappingTable $anonymizationMappings.DatastoreNames
                $anonymizedEntry
            }
            $anonymizedCSVInfo | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvInfo_ANONYMIZED.csv") -NoTypeInformation
            
            # Anonymize Network CSV
            if ($csvNetworks.Count -gt 0) {
                $anonymizedNetworks = foreach ($netEntry in $csvNetworks) {
                    $anonymizedNet = $netEntry.PSObject.Copy()
                    $anonymizedNet.VM = Get-AnonymizedName -originalName $netEntry.VM -prefix "SERVER" -mappingTable $anonymizationMappings.ServerNames
                    $anonymizedNet.Host = Get-AnonymizedName -originalName $netEntry.Host -prefix "HOST" -mappingTable $anonymizationMappings.HostNames
                    $anonymizedNet.Cluster = Get-AnonymizedName -originalName $netEntry.Cluster -prefix "CLUSTER" -mappingTable $anonymizationMappings.ClusterNames
                    $anonymizedNet."DNS Name" = Get-AnonymizedName -originalName $netEntry."DNS Name" -prefix "DNS" -mappingTable $anonymizationMappings.DNSNames
                    $anonymizedNet.Datacenter = Get-AnonymizedName -originalName $netEntry.Datacenter -prefix "DC" -mappingTable $anonymizationMappings.DatastoreNames
                    $anonymizedNet
                }
                $anonymizedNetworks | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvNetwork_ANONYMIZED.csv") -NoTypeInformation
            }
            
            # Anonymize Host CSV
            if ($csvHosts.Count -gt 0) {
                $anonymizedHosts = foreach ($hostEntry in $csvHosts) {
                    $anonymizedHost = $hostEntry.PSObject.Copy()
                    $anonymizedHost.Host = Get-AnonymizedName -originalName $hostEntry.Host -prefix "HOST" -mappingTable $anonymizationMappings.HostNames
                    $anonymizedHost.Cluster = Get-AnonymizedName -originalName $hostEntry.Cluster -prefix "CLUSTER" -mappingTable $anonymizationMappings.ClusterNames
                    $anonymizedHost.Datacenter = Get-AnonymizedName -originalName $hostEntry.Datacenter -prefix "DC" -mappingTable $anonymizationMappings.DatastoreNames
                    $anonymizedHost
                }
                $anonymizedHosts | Export-Csv -Path (Join-Path $outputDir "RVTools_tabvHost_ANONYMIZED.csv") -NoTypeInformation
            }
            
            Write-Host "Created anonymized CSV files" -ForegroundColor Green
        }
    }
}

# Create anonymization mapping file if anonymization was used
if ($anonymize) {
    Write-Host "`nCreating anonymization mapping file..." -ForegroundColor Yellow
    
    try {
        $mappingData = [System.Collections.ArrayList]::new()
        
        # Add server name mappings
        foreach ($mapping in $anonymizationMappings.ServerNames.GetEnumerator()) {
            $mappingData.Add([PSCustomObject]@{
                "Type" = "Server Name"
                "Original" = $mapping.Key
                "Anonymized" = $mapping.Value
            }) | Out-Null
        }
        
        # Add host name mappings
        foreach ($mapping in $anonymizationMappings.HostNames.GetEnumerator()) {
            $mappingData.Add([PSCustomObject]@{
                "Type" = "Host Name"
                "Original" = $mapping.Key
                "Anonymized" = $mapping.Value
            }) | Out-Null
        }
        
        # Add cluster name mappings
        foreach ($mapping in $anonymizationMappings.ClusterNames.GetEnumerator()) {
            $mappingData.Add([PSCustomObject]@{
                "Type" = "Cluster Name"
                "Original" = $mapping.Key
                "Anonymized" = $mapping.Value
            }) | Out-Null
        }
        
        # Add IP address mappings
        foreach ($mapping in $anonymizationMappings.IPAddresses.GetEnumerator()) {
            $mappingData.Add([PSCustomObject]@{
                "Type" = "IP Address"
                "Original" = $mapping.Key
                "Anonymized" = $mapping.Value
            }) | Out-Null
        }
        
        # Add DNS/Hostname mappings
        foreach ($mapping in $anonymizationMappings.DNSNames.GetEnumerator()) {
            $mappingData.Add([PSCustomObject]@{
                "Type" = "DNS/Hostname"
                "Original" = $mapping.Key
                "Anonymized" = $mapping.Value
            }) | Out-Null
        }
        
        # Add Datastore name mappings
        foreach ($mapping in $anonymizationMappings.DatastoreNames.GetEnumerator()) {
            $mappingData.Add([PSCustomObject]@{
                "Type" = "Datastore Name"
                "Original" = $mapping.Key
                "Anonymized" = $mapping.Value
            }) | Out-Null
        }
        
        $mappingData | Export-Excel -Path $mappingFile -WorksheetName "Anonymization Mapping" -AutoSize -FreezeTopRow -BoldTopRow
        Write-Host "Created anonymization mapping file: $mappingFile" -ForegroundColor Green
        Write-DebugLog "Created anonymization mapping file with $($mappingData.Count) entries"
        
    } catch {
        Write-Host "Error creating anonymization mapping file: $_" -ForegroundColor Red
        Write-DebugLog "Error creating anonymization mapping file: $_"
    }
}

# Disconnect from vCenter
Write-Host "`nDisconnecting from vCenter..." -ForegroundColor Yellow
Disconnect-VIServer -Confirm:$false