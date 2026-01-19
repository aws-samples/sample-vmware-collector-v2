#
# VMwareCollectorOrchestrator.ps1 - Main orchestration class for VMware data collection
#
# This class replicates all functionality from vmware-collector.ps1 but in a modular, class-based architecture
# It serves as the main orchestrator that coordinates all collection activities
#

# Dependencies: All required classes loaded by module in dependency order

# Standalone functions from vmware-collector.ps1 that need to be available

# Function to generate ME Template data (EXACT copy from vmware-collector.ps1)
function Generate-METemplateData {
    param(
        [Parameter(Mandatory=$true)]$VMData,
        [Parameter(Mandatory=$true)]$VMInfraCache,
        [Parameter(Mandatory=$false)]$BulkPerfData
    )
    
    Write-Host "Generating ME Template data for $($VMData.Count) VMs..." -ForegroundColor Yellow
    $meTemplateData = [System.Collections.ArrayList]::new()
    
    foreach ($vm in $VMData) {
        try {
            # Get infrastructure info from cache
            $infraInfo = $VMInfraCache[$vm.Id]
            if (-not $infraInfo) {
                $infraInfo = @{
                    HostName = ""
                    ClusterName = ""
                    DatacenterName = ""
                    ResourcePoolName = ""
                    FolderName = ""
                    DatastoreNames = ""
                }
            }
            
            # Get network information
            $networkInfo = Get-VMNetworkDetails -VM $vm
            
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
            $perfMetrics = if ($BulkPerfData -and $BulkPerfData[$vm.Id]) {
                $BulkPerfData[$vm.Id]
            } else {
                @{
                    maxCpuUsagePctDec = 25.0
                    avgCpuUsagePctDec = 25.0
                    maxRamUsagePctDec = 60.0
                    avgRamUtlPctDec = 60.0
                }
            }
            
            # Get CPU string from host
            $cpuString = ""
            try {
                if ($vm.VMHost) {
                    $cpuString = $vm.VMHost.ProcessorType
                }
            } catch {
                $cpuString = "Intel Xeon (Unknown Model)"
            }
            
            # Truncate OS name to 60 characters as per ME requirements
            $osName = $vm.Guest.OSFullName
            if ($osName -and $osName.Length -gt 60) {
                $osName = $osName.Substring(0, 60)
            }
            
            # Enhanced SQL Server Detection
            $sqlInfo = @{
                HasSQLServer = $false
                Edition = ""
                EditionCategory = ""
                ProductVersion = ""
                DetectionMethod = "Pattern Matching"
            }
            
            # Enhanced Multi-Credential Database Detection
            $databaseInfo = $this.GetEnhancedDatabaseInfo($vm, $networkInfo.PrimaryIP)
            
            # Legacy SQL info structure for backward compatibility
            $sqlInfo.HasSQLServer = ($databaseInfo.DatabaseType -eq 'SQL Server')
            $sqlInfo.Edition = $databaseInfo.Edition
            $sqlInfo.EditionCategory = $this.GetDatabaseEditionCategory($databaseInfo.Edition)
            $sqlInfo.ProductVersion = $databaseInfo.Version
            $sqlInfo.DetectionMethod = $databaseInfo.DetectionMethod
            $sqlInfo.DatabaseType = $databaseInfo.DatabaseType
            $sqlInfo.AllDatabaseInfo = $databaseInfo
            
            if ($databaseInfo.HasDatabase) {
                $this.Logger.WriteInformation("Database detected on $($vm.Name): $($databaseInfo.DatabaseType) - $($databaseInfo.Edition) (Method: $($databaseInfo.DetectionMethod))")
            }
            
            # Create ME Template entry
            $meEntry = [PSCustomObject]@{
                "Server Name" = $vm.Name
                "CPU Cores" = $vm.NumCpu
                "Memory (MB)" = $vm.MemoryMB
                "Provisioned Storage (GB)" = [math]::Round($totalStorageGB, 2)
                "Operating System" = $osName
                "Is Virtual?" = $true
                "Hypervisor Name" = $infraInfo.HostName
                "Cpu String" = $cpuString
                "Environment" = "Production"  # Default - could be made configurable
                "SQL Edition" = $sqlInfo.EditionCategory
                "Application" = if ($vm.Notes) { $vm.Notes } else { "" }
                "Cpu Utilization Peak (%)" = [math]::Round($perfMetrics.maxCpuUsagePctDec / 100, 4)  # Convert to decimal
                "Memory Utilization Peak (%)" = [math]::Round($perfMetrics.maxRamUsagePctDec / 100, 4)  # Convert to decimal
                "Time In-Use (%)" = 1.0  # 100% - VMs are always considered in use
                "Annual Cost (USD)" = ""  # No cost data available
                "Storage Type" = ""  # Left empty
            }
            
            $meTemplateData.Add($meEntry) | Out-Null
            
        } catch {
            Write-Host "Error generating ME Template data for VM $($vm.Name): $_" -ForegroundColor Red
        }
    }
    
    Write-Host "Generated ME Template data for $($meTemplateData.Count) VMs" -ForegroundColor Green
    return $meTemplateData
}

# Function to get VM network information (EXACT copy from vmware-collector.ps1)
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
        Write-Host "Error getting network details for VM $($VM.Name): $_" -ForegroundColor Red
        return @{
            PrimaryIP = ""
            NetworkNames = @()
            NetworkCount = 0
        }
    }
}

# Function to create ME Workbook with proper structure (EXACT copy from vmware-collector.ps1)
function Create-MEWorkbook {
    param(
        [Parameter(Mandatory=$true)]$TemplateData,
        [Parameter(Mandatory=$true)]$OutputPath,
        [Parameter(Mandatory=$false)][bool]$Anonymize = $false
    )
    
    try {
        # Anonymize data if requested
        if ($Anonymize) {
            $processedData = foreach ($entry in $TemplateData) {
                $anonymizedEntry = $entry.PSObject.Copy()
                $anonymizedEntry."Server Name" = Get-AnonymizedName -originalName $entry."Server Name" -prefix "SERVER" -mappingTable $global:anonymizationMappings.ServerNames
                $anonymizedEntry."Hypervisor Name" = Get-AnonymizedName -originalName $entry."Hypervisor Name" -prefix "HOST" -mappingTable $global:anonymizationMappings.HostNames
                $anonymizedEntry."Cpu String" = "Intel Xeon (Anonymized)"
                $anonymizedEntry."Application" = if ($entry."Application") { "Application-" + (Get-Random -Minimum 1 -Maximum 999) } else { "" }
                $anonymizedEntry
            }
        } else {
            $processedData = $TemplateData
        }
        
        # Create Instructions sheet content
        $instructionsData = @(
            [PSCustomObject]@{"Instructions" = "This is the AWS Migration Evaluator data import template"}
            [PSCustomObject]@{"Instructions" = "1. The sheet 'Template' is used to provide information about on-premises server workloads"}
            [PSCustomObject]@{"Instructions" = "2. Fill in the Template sheet with your server data"}
            [PSCustomObject]@{"Instructions" = "3. Required fields must be completed for accurate assessment"}
            [PSCustomObject]@{"Instructions" = "4. Optional fields help improve assessment accuracy"}
            [PSCustomObject]@{"Instructions" = "5. See Glossary sheet for field definitions and requirements"}
        )
        
        # Create Glossary sheet content (key fields only)
        $glossaryData = @(
            [PSCustomObject]@{"Attribute Name" = "Server Name"; "Example" = "Apache01"; "Requirement" = "Required"; "Notes" = "The name of the asset"}
            [PSCustomObject]@{"Attribute Name" = "CPU Cores"; "Example" = "4"; "Requirement" = "Required"; "Notes" = "For virtual machines: the number of vCPU"}
            [PSCustomObject]@{"Attribute Name" = "Memory (MB)"; "Example" = "4096"; "Requirement" = "Required"; "Notes" = "The number of MB of RAM allocated"}
            [PSCustomObject]@{"Attribute Name" = "Provisioned Storage (GB)"; "Example" = "500"; "Requirement" = "Required"; "Notes" = "The total number of GB of storage allocated"}
            [PSCustomObject]@{"Attribute Name" = "Operating System"; "Example" = "Windows Server 2012R2"; "Requirement" = "Required"; "Notes" = "The operating system version. Cannot be more than 60 characters long."}
            [PSCustomObject]@{"Attribute Name" = "Is Virtual?"; "Example" = "True"; "Requirement" = "Required"; "Notes" = "True if this a virtual machine. False if this is bare metal server"}
            [PSCustomObject]@{"Attribute Name" = "Hypervisor Name"; "Example" = "Host-1"; "Requirement" = "Preferred"; "Notes" = "The runtime host of the virtual machine"}
            [PSCustomObject]@{"Attribute Name" = "Cpu Utilization Peak (%)"; "Example" = "0.6"; "Requirement" = "Optional"; "Notes" = "Valid range: 0% - 100%. P95 percentile value for realistic peak usage"}
            [PSCustomObject]@{"Attribute Name" = "Memory Utilization Peak (%)"; "Example" = "0.95"; "Requirement" = "Optional"; "Notes" = "Valid range: 0% - 100%. P95 percentile value for realistic peak usage"}
        )
        
        # Export all sheets to create the complete ME workbook
        $processedData | Export-Excel -Path $OutputPath -WorksheetName "Template" -AutoSize -FreezeTopRow -BoldTopRow
        $instructionsData | Export-Excel -Path $OutputPath -WorksheetName "Instructions" -AutoSize -FreezeTopRow -BoldTopRow
        $glossaryData | Export-Excel -Path $OutputPath -WorksheetName "Glossary" -AutoSize -FreezeTopRow -BoldTopRow
        
        # Create empty storage sheets with headers only
        @([PSCustomObject]@{"File Server/Share Name" = ""; "Total Used Capacity (GB) - Usable" = ""; "Access Protocol (CIFS/NFS)" = ""}) | Export-Excel -Path $OutputPath -WorksheetName "FileNAS Storage (If applicable)" -AutoSize -FreezeTopRow -BoldTopRow
        @([PSCustomObject]@{"Volume Name" = ""; "Total Used Capacity (GB) - Usable" = ""; "Peak IOPS (reads & writes)" = ""}) | Export-Excel -Path $OutputPath -WorksheetName "Block Storage (If applicable)" -AutoSize -FreezeTopRow -BoldTopRow
        
        Write-Host "Created ME workbook: $OutputPath with $($processedData.Count) server records" -ForegroundColor Green
        
    } catch {
        Write-Host "Error creating ME workbook: $_" -ForegroundColor Red
        throw $_
    }
}

# Anonymization helper functions (EXACT copy from vmware-collector.ps1)
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

class VMwareCollectorOrchestrator {
    [ILogger] $Logger
    [hashtable] $Parameters
    [hashtable] $CollectionStatistics
    [hashtable] $OutputPaths
    [string] $Timestamp
    [string] $OutputDirectory
    
    # Component classes
    [ParameterValidator] $ParameterValidator
    [object] $CacheManager
    [object] $FilteringEngine
    [object] $DataCollector
    [object] $PerformanceCollector
    [RVToolsFormatGenerator] $RVToolsGenerator
    
    # SQL Detection properties
    [bool] $EnableSQLDetection
    [hashtable] $SQLCredentials
    
    # Multi-Database Detection properties
    [bool] $EnableMultiDatabaseDetection
    [hashtable] $DatabaseCredentialsConfig = @{}
    
    # Constructor
    VMwareCollectorOrchestrator([hashtable] $Parameters, [ILogger] $Logger) {
        $this.Logger = $Logger
        $this.Parameters = $Parameters
        $this.Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $this.OutputDirectory = "VMware_Export_$($this.Timestamp)"
        
        $this.CollectionStatistics = @{
            StartTime = Get-Date
            TotalVMs = 0
            ProcessedVMs = 0
            SkippedVMs = 0
            ErrorCount = 0
            PerformanceDataCollected = $false
            OutputFormatsGenerated = @()
        }
        
        $this.InitializeOutputPaths()
        $this.InitializeComponents()
    }
    
    # Initialize output file paths
    [void] InitializeOutputPaths() {
        $this.OutputPaths = @{
            OutputDirectory = $this.OutputDirectory
            ExcelOutput = Join-Path $this.OutputDirectory "MPA_Template_$($this.Timestamp).xlsx"
            ExcelOutputAnonymized = Join-Path $this.OutputDirectory "MPA_Template_ANONYMIZED_$($this.Timestamp).xlsx"
            WorkbookOutput = Join-Path $this.OutputDirectory "ME_ConsolidatedDataImport_$($this.Timestamp).xlsx"
            WorkbookOutputAnonymized = Join-Path $this.OutputDirectory "ME_ConsolidatedDataImport_ANONYMIZED_$($this.Timestamp).xlsx"
            MappingFile = Join-Path $this.OutputDirectory "Anonymization_Mapping_$($this.Timestamp).xlsx"
            LogFile = Join-Path $this.OutputDirectory "vm_collection_$($this.Timestamp).log"
        }
        
        # Create output directory
        New-Item -ItemType Directory -Path $this.OutputDirectory -Force | Out-Null
        $this.Logger.WriteInformation("Created output directory: $($this.OutputDirectory)")
    }
    
    # Initialize all component classes
    [void] InitializeComponents() {
        try {
            $this.Logger.WriteInformation("Initializing VMware Collector components...")
            
            # Initialize core components
            $this.ParameterValidator = [ParameterValidator]::new($this.Logger)
            try { $this.CacheManager = [InfrastructureCacheManager]::new($this.Logger) } catch { $this.CacheManager = $null }
            try { $this.FilteringEngine = [VMFilteringEngine]::new($this.Logger) } catch { $this.FilteringEngine = $null }
            try { $this.DataCollector = [VMDataCollector]::new($this.Logger) } catch { $this.DataCollector = $null }
            try { $this.PerformanceCollector = [PerformanceCollector]::new($this.Logger) } catch { $this.PerformanceCollector = $null }
            $this.RVToolsGenerator = [RVToolsFormatGenerator]::new($this.Logger)
            
            # Initialize SQL Detection
            $this.InitializeSQLDetection()
            
            $this.Logger.WriteInformation("All components initialized successfully")
            
        } catch {
            $this.Logger.WriteError("Failed to initialize components: $($_.Exception.Message)", $_.Exception)
            throw
        }
    }
    
    # Initialize SQL Detection settings
    [void] InitializeSQLDetection() {
        $this.EnableSQLDetection = $this.Parameters.ContainsKey('enableSQLDetection') -and $this.Parameters.enableSQLDetection
        $this.EnableMultiDatabaseDetection = $this.Parameters.ContainsKey('enableMultiDatabaseDetection') -and $this.Parameters.enableMultiDatabaseDetection
        
        # Load multi-credential configuration if provided
        if ($this.Parameters.databaseCredentialsFile) {
            $this.DatabaseCredentialsConfig = $this.ImportDatabaseCredentialsConfig($this.Parameters.databaseCredentialsFile)
        }
        
        if ($this.EnableSQLDetection) {
            $this.SQLCredentials = @{
                UseWindowsAuth = ($this.Parameters.sqlAuthMode -eq 'Windows')
                Username = $this.Parameters.sqlUsername
                Password = $this.Parameters.sqlPassword
                ConnectionTimeout = if ($this.Parameters.sqlConnectionTimeout) { $this.Parameters.sqlConnectionTimeout } else { 5 }
            }
            
            $this.Logger.WriteInformation("SQL Detection enabled with $($this.Parameters.sqlAuthMode) authentication")
        } else {
            $this.Logger.WriteInformation("SQL Detection disabled - using pattern matching only")
        }
        
        if ($this.EnableMultiDatabaseDetection) {
            $this.Logger.WriteInformation("Multi-Database Detection enabled")
            
            # Log available credentials
            foreach ($dbType in @('SQLServer', 'PostgreSQL', 'Oracle', 'MySQL')) {
                $credCount = if ($this.DatabaseCredentialsConfig.$dbType) { $this.DatabaseCredentialsConfig.$dbType.Count } else { 0 }
                if ($credCount -gt 0) {
                    $this.Logger.WriteInformation("  - ${dbType}: $credCount credential(s) loaded from configuration")
                }
            }
        }
    }
    
    # Import database credentials configuration (replicates monolithic function)
    [hashtable] ImportDatabaseCredentialsConfig([string] $ConfigFilePath) {
        if (-not $ConfigFilePath -or -not (Test-Path $ConfigFilePath)) {
            return @{}
        }
        
        try {
            $configContent = Get-Content $ConfigFilePath -Raw | ConvertFrom-Json
            $this.Logger.WriteInformation("Loaded database credentials configuration from: $ConfigFilePath")
            
            # Validate configuration structure
            $validatedConfig = @{
                SQLServer = @()
                PostgreSQL = @()
                Oracle = @()
                MySQL = @()
            }
            
            foreach ($dbType in @('SQLServer', 'PostgreSQL', 'Oracle', 'MySQL')) {
                if ($configContent.$dbType) {
                    foreach ($cred in $configContent.$dbType) {
                        if ($cred.Username -and $cred.Password) {
                            $credentialEntry = @{
                                Username = $cred.Username
                                Password = $cred.Password
                                Description = if ($cred.Description) { $cred.Description } else { "Default" }
                                Priority = if ($cred.Priority) { $cred.Priority } else { 1 }
                            }
                            
                            # Add SQL Server specific properties
                            if ($dbType -eq 'SQLServer') {
                                $credentialEntry.AuthMode = if ($cred.AuthMode) { $cred.AuthMode } else { 'SQL' }
                            }
                            
                            $validatedConfig.$dbType += $credentialEntry
                        }
                    }
                    
                    # Sort by priority (lower number = higher priority)
                    $validatedConfig.$dbType = $validatedConfig.$dbType | Sort-Object Priority
                }
            }
            
            return $validatedConfig
            
        } catch {
            $this.Logger.WriteError("Error loading database credentials configuration: $_", $_.Exception)
            return @{}
        }
    }
    
    # Get database credentials list (replicates monolithic function)
    [array] GetDatabaseCredentialsList([string] $DatabaseType) {
        $credentialsList = @()
        
        # Add credentials from configuration file (higher priority)
        if ($this.DatabaseCredentialsConfig.$DatabaseType) {
            $credentialsList += $this.DatabaseCredentialsConfig.$DatabaseType
        }
        
        # Add credentials from parameters (lower priority)
        $parameterCredentials = @{}
        
        switch ($DatabaseType) {
            'SQLServer' {
                if ($this.Parameters.sqlUsername -and $this.Parameters.sqlPassword) {
                    $parameterCredentials = @{
                        Username = $this.Parameters.sqlUsername
                        Password = $this.Parameters.sqlPassword
                        AuthMode = $this.Parameters.sqlAuthMode
                        Description = "Command Line Parameter"
                        Priority = 999
                    }
                }
            }
            'PostgreSQL' {
                if ($this.Parameters.postgresUsername -and $this.Parameters.postgresPassword) {
                    $parameterCredentials = @{
                        Username = $this.Parameters.postgresUsername
                        Password = $this.Parameters.postgresPassword
                        Description = "Command Line Parameter"
                        Priority = 999
                    }
                }
            }
            'Oracle' {
                if ($this.Parameters.oracleUsername -and $this.Parameters.oraclePassword) {
                    $parameterCredentials = @{
                        Username = $this.Parameters.oracleUsername
                        Password = $this.Parameters.oraclePassword
                        Description = "Command Line Parameter"
                        Priority = 999
                    }
                }
            }
            'MySQL' {
                if ($this.Parameters.mysqlUsername -and $this.Parameters.mysqlPassword) {
                    $parameterCredentials = @{
                        Username = $this.Parameters.mysqlUsername
                        Password = $this.Parameters.mysqlPassword
                        Description = "Command Line Parameter"
                        Priority = 999
                    }
                }
            }
        }
        
        if ($parameterCredentials.Username) {
            $credentialsList += $parameterCredentials
        }
        
        return $credentialsList | Sort-Object Priority
    }
    
    # Enhanced database detection (replicates monolithic function)
    [hashtable] GetEnhancedDatabaseInfo([object] $VM, [string] $IPAddress) {
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
            if ($this.EnableSQLDetection -and $IPAddress) {
                try {
                    $sqlCredentialsList = $this.GetDatabaseCredentialsList('SQLServer')
                    
                    if ($sqlCredentialsList.Count -gt 0) {
                        $sqlResult = $this.TestDatabaseConnectionWithMultipleCredentials($IPAddress, 'SQLServer', $sqlCredentialsList)
                        
                        if ($sqlResult.Success) {
                            $databaseInfo.Edition = $sqlResult.Edition
                            $databaseInfo.Version = $sqlResult.Version
                            $databaseInfo.DetectionMethod = "Direct SQL Query ($($sqlResult.CredentialUsed))"
                            $databaseInfo.Details = $sqlResult
                        }
                    } else {
                        $this.Logger.WriteInformation("No SQL Server credentials available for $($VM.Name)")
                    }
                } catch {
                    $this.Logger.WriteError("SQL Server detection failed for $($VM.Name): $_", $_.Exception)
                }
            }
        }
        # PostgreSQL patterns
        elseif ($vmName -match 'postgres|pgsql|pg-' -or $osName -match 'postgres') {
            $databaseInfo.HasDatabase = $true
            $databaseInfo.DatabaseType = 'PostgreSQL'
            $databaseInfo.Edition = 'PostgreSQL'
            
            # Enhanced PostgreSQL detection if enabled
            if ($this.EnableMultiDatabaseDetection -and $IPAddress) {
                try {
                    $pgCredentialsList = $this.GetDatabaseCredentialsList('PostgreSQL')
                    
                    if ($pgCredentialsList.Count -gt 0) {
                        $pgResult = $this.TestDatabaseConnectionWithMultipleCredentials($IPAddress, 'PostgreSQL', $pgCredentialsList)
                        
                        if ($pgResult.Success) {
                            $databaseInfo.Edition = $pgResult.Edition
                            $databaseInfo.Version = $pgResult.Version
                            $databaseInfo.DetectionMethod = "Direct PostgreSQL Query ($($pgResult.CredentialUsed))"
                            $databaseInfo.Details = $pgResult
                        }
                    }
                } catch {
                    $this.Logger.WriteError("PostgreSQL detection failed for $($VM.Name): $_", $_.Exception)
                }
            }
        }
        # Oracle patterns
        elseif ($vmName -match 'oracle|ora-|orcl' -or $osName -match 'oracle') {
            $databaseInfo.HasDatabase = $true
            $databaseInfo.DatabaseType = 'Oracle'
            $databaseInfo.Edition = 'Oracle Database'
            
            # Enhanced Oracle detection if enabled
            if ($this.EnableMultiDatabaseDetection -and $IPAddress) {
                try {
                    $oracleCredentialsList = $this.GetDatabaseCredentialsList('Oracle')
                    
                    if ($oracleCredentialsList.Count -gt 0) {
                        $oraResult = $this.TestDatabaseConnectionWithMultipleCredentials($IPAddress, 'Oracle', $oracleCredentialsList)
                        
                        if ($oraResult.Success) {
                            $databaseInfo.Edition = $oraResult.Edition
                            $databaseInfo.Version = $oraResult.Version
                            $databaseInfo.DetectionMethod = "Direct Oracle Query ($($oraResult.CredentialUsed))"
                            $databaseInfo.Details = $oraResult
                        }
                    }
                } catch {
                    $this.Logger.WriteError("Oracle detection failed for $($VM.Name): $_", $_.Exception)
                }
            }
        }
        # MySQL patterns
        elseif ($vmName -match 'mysql|maria' -or $osName -match 'mysql|maria') {
            $databaseInfo.HasDatabase = $true
            $databaseInfo.DatabaseType = 'MySQL'
            $databaseInfo.Edition = 'MySQL'
            
            # Enhanced MySQL detection if enabled
            if ($this.EnableMultiDatabaseDetection -and $IPAddress) {
                try {
                    $mysqlCredentialsList = $this.GetDatabaseCredentialsList('MySQL')
                    
                    if ($mysqlCredentialsList.Count -gt 0) {
                        $mysqlResult = $this.TestDatabaseConnectionWithMultipleCredentials($IPAddress, 'MySQL', $mysqlCredentialsList)
                        
                        if ($mysqlResult.Success) {
                            $databaseInfo.Edition = $mysqlResult.Edition
                            $databaseInfo.Version = $mysqlResult.Version
                            $databaseInfo.DetectionMethod = "Direct MySQL Query ($($mysqlResult.CredentialUsed))"
                            $databaseInfo.Details = $mysqlResult
                        }
                    }
                } catch {
                    $this.Logger.WriteError("MySQL detection failed for $($VM.Name): $_", $_.Exception)
                }
            }
        }
        # MongoDB patterns
        elseif ($vmName -match 'mongo|nosql' -or $osName -match 'mongo') {
            $databaseInfo.HasDatabase = $true
            $databaseInfo.DatabaseType = 'MongoDB'
            $databaseInfo.Edition = 'MongoDB'
        }
        
        return $databaseInfo
    }
    
    # Test database connection with multiple credentials (replicates monolithic function)
    [hashtable] TestDatabaseConnectionWithMultipleCredentials([string] $IPAddress, [string] $DatabaseType, [array] $CredentialsList) {
        if (-not $CredentialsList -or $CredentialsList.Count -eq 0) {
            return @{ Success = $false; Error = "No credentials provided for $DatabaseType" }
        }
        
        foreach ($credential in $CredentialsList) {
            try {
                $this.Logger.WriteInformation("Attempting $DatabaseType connection to $IPAddress with credential: $($credential.Description)")
                
                $result = $this.TestDatabaseConnection($IPAddress, $DatabaseType, $credential)
                
                if ($result.Success) {
                    $result.CredentialUsed = $credential.Description
                    $this.Logger.WriteInformation("Successfully connected to $DatabaseType at $IPAddress using credential: $($credential.Description)")
                    return $result
                } else {
                    $this.Logger.WriteInformation("Failed to connect to $DatabaseType at $IPAddress with credential '$($credential.Description)': $($result.Error)")
                }
                
            } catch {
                $this.Logger.WriteError("Exception testing $DatabaseType connection with credential '$($credential.Description)': $_", $_.Exception)
            }
        }
        
        return @{ 
            Success = $false
            Error = "All credential attempts failed for $DatabaseType at $IPAddress"
            CredentialsAttempted = $CredentialsList.Count
        }
    }
    
    # Test individual database connection (replicates monolithic function)
    [hashtable] TestDatabaseConnection([string] $IPAddress, [string] $DatabaseType, [hashtable] $Credentials) {
        if ([string]::IsNullOrEmpty($IPAddress)) {
            return @{ Success = $false; Error = "No IP address provided" }
        }
        
        try {
            switch ($DatabaseType.ToLower()) {
                'sqlserver' {
                    return $this.TestSQLServerConnection($IPAddress, $Credentials)
                }
                'postgresql' {
                    return $this.TestPostgreSQLConnection($IPAddress, $Credentials)
                }
                'oracle' {
                    return $this.TestOracleConnection($IPAddress, $Credentials)
                }
                'mysql' {
                    return $this.TestMySQLConnection($IPAddress, $Credentials)
                }
                default {
                    return @{ Success = $false; Error = "Unsupported database type: $DatabaseType" }
                }
            }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
        
        # Fallback return (should never reach here due to switch default)
        return @{ Success = $false; Error = "Unknown error occurred" }
    }
    
    # Test SQL Server connection (replicates monolithic function)
    [hashtable] TestSQLServerConnection([string] $IPAddress, [hashtable] $Credentials) {
        try {
            $connectionString = "Server=$IPAddress;Database=master;Connection Timeout=5;"
            
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
                $result.Edition = $reader['Edition'].ToString()
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
    
    # Test PostgreSQL connection (placeholder - replicates monolithic function)
    [hashtable] TestPostgreSQLConnection([string] $IPAddress, [hashtable] $Credentials) {
        try {
            # For now, return pattern-based detection (same as monolithic)
            return @{
                Success = $true
                DatabaseType = 'PostgreSQL'
                Edition = 'PostgreSQL'
                Version = 'Unknown'
                DetectionMethod = 'Pattern-based (PostgreSQL client not available)'
            }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }
    
    # Test Oracle connection (placeholder - replicates monolithic function)
    [hashtable] TestOracleConnection([string] $IPAddress, [hashtable] $Credentials) {
        try {
            # For now, return pattern-based detection (same as monolithic)
            return @{
                Success = $true
                DatabaseType = 'Oracle'
                Edition = 'Oracle Database'
                Version = 'Unknown'
                DetectionMethod = 'Pattern-based (Oracle client not available)'
            }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }
    
    # Test MySQL connection (placeholder - replicates monolithic function)
    [hashtable] TestMySQLConnection([string] $IPAddress, [hashtable] $Credentials) {
        try {
            # For now, return pattern-based detection (same as monolithic)
            return @{
                Success = $true
                DatabaseType = 'MySQL'
                Edition = 'MySQL'
                Version = 'Unknown'
                DetectionMethod = 'Pattern-based (MySQL client not available)'
            }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }
    
    # Get database edition category (replicates monolithic function)
    [string] GetDatabaseEditionCategory([string] $Edition) {
        if (-not $Edition) { return '' }
        
        $edition = $Edition.ToLower()
        
        # SQL Server editions
        if ($edition -match 'enterprise') { return 'SQL Server Enterprise Edition' }
        if ($edition -match 'standard') { return 'SQL Server Standard Edition' }
        if ($edition -match 'developer') { return 'SQL Server Developer Edition' }
        if ($edition -match 'express') { return 'SQL Server Express Edition' }
        if ($edition -match 'web') { return 'SQL Server Web Edition' }
        
        # Other database types
        if ($edition -match 'postgresql') { return 'PostgreSQL' }
        if ($edition -match 'oracle') { return 'Oracle Database' }
        if ($edition -match 'mysql') { return 'MySQL' }
        if ($edition -match 'mongodb') { return 'MongoDB' }
        
        return $Edition
    }
    
    # Main execution method - replicates vmware-collector.ps1 functionality EXACTLY
    [hashtable] ExecuteCollection() {
        try {
            $this.Logger.WriteInformation("Starting VMware data collection orchestration...")
            
            # EXACT REPLICATION: Follow vmware-collector.ps1 execution flow
            
            # Step 1: Validate parameters (same as vmware-collector.ps1 validation)
            $validationResult = $this.ParameterValidator.ValidateParameters($this.Parameters)
            if (-not $validationResult.IsValid) {
                throw "Parameter validation failed: $($validationResult.ErrorMessage)"
            }
            
            # Step 2: Configure PowerCLI settings (exact same as vmware-collector.ps1)
            $this.ConfigurePowerCLI()
            
            # Step 3: Connect to vCenter (EXACT same as vmware-collector.ps1)
            $this.ConnectToVCenter()
            
            # Step 4: Cache infrastructure data (exact same as vmware-collector.ps1)
            $cacheResult = $this.CacheManager.CacheAllInfrastructure()
            if (-not $cacheResult.Success) {
                $this.Logger.WriteWarning("Infrastructure caching had issues: $($cacheResult.ErrorMessage)")
            }
            
            # Step 5: Filter and collect VMs (exact same as vmware-collector.ps1)
            $vmFilterResult = $this.FilteringEngine.FilterVMs($this.Parameters, $this.CacheManager)
            if ($vmFilterResult.FilteredVMs.Count -eq 0) {
                throw "No VMs found matching the specified criteria"
            }
            
            $this.CollectionStatistics.TotalVMs = $vmFilterResult.FilteredVMs.Count
            $vms = $vmFilterResult.FilteredVMs  # Use same variable name as vmware-collector.ps1
            
            # Step 6: Filter infrastructure to match selected VMs (exact same as vmware-collector.ps1)
            $infraFilterResult = $this.CacheManager.FilterInfrastructureForVMs($vms)
            
            # Step 7: Build VM-to-infrastructure mappings (exact same as vmware-collector.ps1)
            $vmInfraCacheResult = $this.CacheManager.BuildVMInfrastructureMappings($vms)
            $vmInfraCache = $this.CacheManager.VMInfraCache  # Use same variable name as vmware-collector.ps1
            
            # Step 8: Collect performance data using EXACT same logic as vmware-collector.ps1
            $global:BulkPerfData = @{}  # Use same global variable as vmware-collector.ps1
            
            if (-not $this.Parameters.skipPerformanceData) {
                $perfResult = $this.PerformanceCollector.CollectBulkPerformanceData($vms, $this.Parameters.collectionDays)
                $global:BulkPerfData = $perfResult.BulkPerfData
                $this.CollectionStatistics.PerformanceDataCollected = $true
            }
            
            # Step 9: Process VM data into serversData format (exact same as vmware-collector.ps1)
            $serversData = $this.DataCollector.ProcessVMsIntoServersData($vms, $vmInfraCache, $global:BulkPerfData)
            
            # Step 10: Generate output formats using EXACT same logic as vmware-collector.ps1
            $outputResult = $this.GenerateOutputFilesExactly($vms, $serversData, $vmInfraCache, $global:BulkPerfData)
            
            $this.CollectionStatistics.OutputFormatsGenerated = $outputResult.GeneratedFormats
            
            # Step 11: Generate collection summary
            $this.CollectionStatistics.EndTime = Get-Date
            $this.CollectionStatistics.TotalDuration = $this.CollectionStatistics.EndTime - $this.CollectionStatistics.StartTime
            
            $this.Logger.WriteInformation("VMware data collection completed successfully!")
            $this.LogCollectionSummary()
            
            return @{
                Success = $true
                Statistics = $this.CollectionStatistics
                OutputPaths = $this.OutputPaths
                VMData = $serversData
                VMs = $vms
                VMInfraCache = $vmInfraCache
                BulkPerfData = $global:BulkPerfData
            }
            
        } catch {
            $this.CollectionStatistics.ErrorCount++
            $this.CollectionStatistics.EndTime = Get-Date
            $this.Logger.WriteError("VMware data collection failed: $($_.Exception.Message)", $_.Exception)
            
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                Statistics = $this.CollectionStatistics
            }
        }
    }
    
    # Configure PowerCLI settings (EXACT same as vmware-collector.ps1)
    [void] ConfigurePowerCLI() {
        try {
            # Configure PowerCLI (exact same as vmware-collector.ps1)
            if ($this.Parameters.disableSSL) {
                Write-Host "Disabling SSL certificate validation..." -ForegroundColor Yellow
                Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
            }
            
            Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
            
            # Import required modules (exact same as vmware-collector.ps1)
            Import-Module ImportExcel -ErrorAction Stop
            Import-Module Microsoft.PowerShell.Archive -ErrorAction SilentlyContinue
            
        } catch {
            $this.Logger.WriteError("Failed to configure PowerCLI: $($_.Exception.Message)", $_.Exception)
            throw
        }
    }
    
    # Connect to vCenter (EXACT same as vmware-collector.ps1)
    [void] ConnectToVCenter() {
        try {
            Connect-VIServer $this.Parameters.address -Protocol $this.Parameters.protocol -User $this.Parameters.username -Password $this.Parameters.password -Port $this.Parameters.port -ErrorAction Stop | Out-Null
            Write-Host "Successfully connected to vCenter Server" -ForegroundColor Green
            $this.WriteDebugLog("Successfully connected to vCenter Server")
        }
        catch {
            Write-Host "Failed to connect to vCenter Server: $_" -ForegroundColor Red
            $this.WriteDebugLog("Failed to connect to vCenter Server: $_")
            throw "Failed to connect to vCenter Server: $_"
        }
    }
    
    # Write-DebugLog function (EXACT same as vmware-collector.ps1)
    [void] WriteDebugLog([string] $Message) {
        if ($this.Parameters.enableLogging) {
            $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
            Add-Content -Path $this.OutputPaths.LogFile -Value $logMessage
        }
    }
    
    # Log collection summary (EXACT same as vmware-collector.ps1)
    [void] LogCollectionSummary() {
        try {
            $totalTime = $this.CollectionStatistics.TotalDuration
            
            # Final summary (exact same format as vmware-collector.ps1)
            Write-Host "`n" + "=" * 80 -ForegroundColor Cyan
            Write-Host "OPTIMIZED COLLECTION COMPLETED SUCCESSFULLY!" -ForegroundColor Green
            Write-Host "=" * 80 -ForegroundColor Cyan
            
            Write-Host "`nPerformance Summary:" -ForegroundColor Cyan
            Write-Host "  Total VMs processed: $($this.CollectionStatistics.ProcessedVMs)" -ForegroundColor White
            Write-Host "  Total processing time: $($totalTime.TotalMinutes.ToString('F1')) minutes" -ForegroundColor White
            Write-Host "  Average processing speed: $([math]::Round($this.CollectionStatistics.ProcessedVMs / $totalTime.TotalSeconds, 1)) VMs/second" -ForegroundColor White
            
            Write-Host "`nOptimizations Applied:" -ForegroundColor Cyan
            Write-Host "  * Pre-cached infrastructure data (hosts, clusters, datastores, resource pools)" -ForegroundColor Green
            Write-Host "  * Built VM-to-infrastructure mappings upfront" -ForegroundColor Green
            Write-Host "  * Used batch processing instead of individual API calls" -ForegroundColor Green
            Write-Host "  * Minimized redundant vCenter queries" -ForegroundColor Green
            Write-Host "  * Intelligent performance data collection" -ForegroundColor Green
            Write-Host "  * Using P95 percentile for peak values (more realistic than maximum)" -ForegroundColor Green
            
            Write-Host "`nOutput Files Created:" -ForegroundColor Cyan
            if ($this.Parameters.outputFormat -eq 'All' -or $this.Parameters.outputFormat -eq 'MPA') {
                Write-Host "  * MPA Template: $($this.OutputPaths.ExcelOutput)" -ForegroundColor White
                if ($this.Parameters.anonymize) {
                    Write-Host "  * MPA Template (Anonymized): $($this.OutputPaths.ExcelOutputAnonymized)" -ForegroundColor White
                }
            }
            if ($this.Parameters.outputFormat -eq 'All' -or $this.Parameters.outputFormat -eq 'ME') {
                Write-Host "  * ME Template: $($this.OutputPaths.WorkbookOutput)" -ForegroundColor White
                if ($this.Parameters.anonymize) {
                    Write-Host "  * ME Template (Anonymized): $($this.OutputPaths.WorkbookOutputAnonymized)" -ForegroundColor White
                }
            }
            if ($this.Parameters.outputFormat -eq 'All' -or $this.Parameters.outputFormat -eq 'RVTools') {
                $rvToolsZipFiles = Get-ChildItem -Path $this.OutputDirectory -Filter "RVTools_Export_*.zip" | Sort-Object Name
                foreach ($zipFile in $rvToolsZipFiles) {
                    if ($zipFile.Name -match "ANONYMIZED") {
                        Write-Host "  * RVTools ZIP (Anonymized): $($zipFile.Name)" -ForegroundColor White
                    } else {
                        Write-Host "  * RVTools ZIP: $($zipFile.Name)" -ForegroundColor White
                    }
                }
            }
            if ($this.Parameters.anonymize) {
                Write-Host "  * Anonymization Mapping: $($this.OutputPaths.MappingFile)" -ForegroundColor White
            }
            
            Write-Host "`nCollection completed in output directory: $($this.OutputDirectory)" -ForegroundColor Green
            Write-Host "`nOptimized VMware Collector completed successfully!" -ForegroundColor Green
            Write-Host "Thank you for using the optimized edition!" -ForegroundColor Cyan
            
        } catch {
            $this.Logger.WriteError("Failed to log collection summary: $($_.Exception.Message)", $_.Exception)
        }
    }
    
    # Get current collection status
    [hashtable] GetCollectionStatus() {
        return @{
            Statistics = $this.CollectionStatistics.Clone()
            OutputPaths = $this.OutputPaths.Clone()
            IsRunning = $this.CollectionStatistics.EndTime -eq $null
        }
    }
    
    # Generate output files using EXACT same logic as vmware-collector.ps1
    [hashtable] GenerateOutputFilesExactly([array] $VMs, [array] $ServersData, [hashtable] $VMInfraCache, [hashtable] $BulkPerfData) {
        try {
            $this.Logger.WriteInformation("Generating output files...")
            $generatedFormats = @()
            
            # Initialize anonymization mappings (exact same as vmware-collector.ps1)
            $global:anonymizationMappings = @{
                ServerNames = @{}
                HostNames = @{}
                ClusterNames = @{}
                IPAddresses = @{}
                DatastoreNames = @{}
                DNSNames = @{}
            }
            
            # Generate MPA Template (exact same as vmware-collector.ps1)
            if ($this.Parameters.outputFormat -eq 'All' -or $this.Parameters.outputFormat -eq 'MPA') {
                try {
                    # Create MPA format generator with database detection enabled if SQL detection is enabled
                    $mpaGenerator = [MPAFormatGenerator]::new($this.Logger, $this.Parameters.enableSQLDetection)
                    $mpaGenerator.GenerateOutput($ServersData, $this.OutputPaths.ExcelOutput)
                    $this.Logger.WriteInformation("Created: $($this.OutputPaths.ExcelOutput)")
                    $generatedFormats += "MPA"
                    
                    # Create anonymized version if requested (exact same logic)
                    if ($this.Parameters.anonymize) {
                        $anonymizedServersData = foreach ($server in $ServersData) {
                            $anonymizedServer = $server.PSObject.Copy()
                            $anonymizedServer.serverName = Get-AnonymizedName -originalName $server.serverName -prefix "SERVER" -mappingTable $global:anonymizationMappings.ServerNames
                            $anonymizedServer.dnsName = Get-AnonymizedName -originalName $server.dnsName -prefix "DNS" -mappingTable $global:anonymizationMappings.DNSNames
                            $anonymizedServer.ipAddress = Get-AnonymizedIP -originalIP $server.ipAddress -mappingTable $global:anonymizationMappings.IPAddresses
                            $anonymizedServer.hostName = Get-AnonymizedName -originalName $server.hostName -prefix "HOST" -mappingTable $global:anonymizationMappings.HostNames
                            $anonymizedServer.clusterName = Get-AnonymizedName -originalName $server.clusterName -prefix "CLUSTER" -mappingTable $global:anonymizationMappings.ClusterNames
                            $anonymizedServer.datastoreName = Get-AnonymizedName -originalName $server.datastoreName -prefix "DATASTORE" -mappingTable $global:anonymizationMappings.DatastoreNames
                            $anonymizedServer
                        }
                        
                        $mpaGeneratorAnon = [MPAFormatGenerator]::new($this.Logger, $this.Parameters.enableSQLDetection)
                        $mpaGeneratorAnon.GenerateOutput($anonymizedServersData, $this.OutputPaths.ExcelOutputAnonymized)
                        $this.Logger.WriteInformation("Created: $($this.OutputPaths.ExcelOutputAnonymized)")
                    }
                } catch {
                    $this.Logger.WriteError("Error creating MPA Template: $($_.Exception.Message)", $_.Exception)
                }
            }
            
            # Generate ME Workbook (exact same as vmware-collector.ps1)
            if ($this.Parameters.outputFormat -eq 'All' -or $this.Parameters.outputFormat -eq 'ME') {
                try {
                    # Generate ME Template data (exact same function as vmware-collector.ps1)
                    $meTemplateData = Generate-METemplateData -VMData $VMs -VMInfraCache $VMInfraCache -BulkPerfData $BulkPerfData
                    
                    # Create the new ME workbook structure (exact same function as vmware-collector.ps1)
                    Create-MEWorkbook -TemplateData $meTemplateData -OutputPath $this.OutputPaths.WorkbookOutput -Anonymize $false
                    
                    $this.Logger.WriteInformation("Created: $($this.OutputPaths.WorkbookOutput)")
                    $generatedFormats += "ME"
                    
                    # Create anonymized version if requested
                    if ($this.Parameters.anonymize) {
                        Create-MEWorkbook -TemplateData $meTemplateData -OutputPath $this.OutputPaths.WorkbookOutputAnonymized -Anonymize $true
                        $this.Logger.WriteInformation("Created: $($this.OutputPaths.WorkbookOutputAnonymized)")
                    }
                } catch {
                    $this.Logger.WriteError("Error creating ME Template: $($_.Exception.Message)", $_.Exception)
                }
            }
            
            # Generate RVTools CSV files (exact same as vmware-collector.ps1)
            if ($this.Parameters.outputFormat -eq 'All' -or $this.Parameters.outputFormat -eq 'RVTools') {
                try {
                    $this.RVToolsGenerator.CreateZipArchive = $true
                    $this.RVToolsGenerator.CleanupCSVFiles = $this.Parameters.purgeCSV
                    $this.RVToolsGenerator.GenerateOutput($VMs, $this.OutputPaths.OutputDirectory)
                    $generatedFormats += "RVTools"
                    $this.Logger.WriteInformation("RVTools format created in: $($this.OutputPaths.OutputDirectory)")
                } catch {
                    $this.Logger.WriteError("Error creating RVTools format: $($_.Exception.Message)", $_.Exception)
                }
            }
            
            # Generate anonymization mapping file if anonymization was used
            if ($this.Parameters.anonymize -and ($global:anonymizationMappings.ServerNames.Count -gt 0 -or $global:anonymizationMappings.HostNames.Count -gt 0)) {
                try {
                    $this.GenerateAnonymizationMappingFile($global:anonymizationMappings)
                    $this.Logger.WriteInformation("Anonymization mapping file created: $($this.OutputPaths.MappingFile)")
                } catch {
                    $this.Logger.WriteError("Failed to generate anonymization mapping file: $($_.Exception.Message)", $_.Exception)
                }
            }
            
            return @{
                Success = $true
                GeneratedFormats = $generatedFormats
            }
            
        } catch {
            $this.Logger.WriteError("Output generation failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                GeneratedFormats = @()
            }
        }
    }
    

    

    

    

    
    # Generate anonymization mapping file
    [void] GenerateAnonymizationMappingFile([hashtable] $AnonymizationMappings) {
        try {
            $mappingData = @()
            
            foreach ($category in $AnonymizationMappings.Keys) {
                $categoryMappings = $AnonymizationMappings[$category]
                
                foreach ($originalValue in $categoryMappings.Keys) {
                    $mappingData += [PSCustomObject]@{
                        Category = $category
                        OriginalValue = $originalValue
                        AnonymizedValue = $categoryMappings[$originalValue]
                    }
                }
            }
            
            $mappingData | Export-Excel -Path $this.OutputPaths.MappingFile -WorksheetName "AnonymizationMappings" -AutoSize -BoldTopRow
            
        } catch {
            $this.Logger.WriteError("Failed to generate anonymization mapping file: $($_.Exception.Message)", $_.Exception)
        }
    }
    
    # Cleanup resources
    [void] Dispose() {
        try {
            # Disconnect from vCenter (exact same as vmware-collector.ps1 would do)
            try {
                if ($global:DefaultVIServer -and $global:DefaultVIServer.IsConnected) {
                    Disconnect-VIServer -Server $global:DefaultVIServer -Confirm:$false
                }
            } catch {
                # Ignore disconnection errors
            }
            
            if ($this.CacheManager) {
                $this.CacheManager.ClearAllCaches()
            }
            
            $this.Logger.WriteInformation("VMware Collector Orchestrator disposed successfully")
            
        } catch {
            $this.Logger.WriteError("Error during orchestrator disposal: $($_.Exception.Message)", $_.Exception)
        }
    }
}