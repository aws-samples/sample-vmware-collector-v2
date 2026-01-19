#
# EnhancedMPAGenerator.ps1 - Enhanced MPA format generator with database support
#
# Generates single CSV file with original 22 MPA columns plus database columns
# Maintains compatibility with standard MPA format while adding database information
#

class EnhancedMPAGenerator {
    [bool] $AnonymizeData
    [hashtable] $AnonymizationMappings
    [object] $Logger
    
    EnhancedMPAGenerator([bool] $AnonymizeData, [object] $Logger) {
        $this.AnonymizeData = $AnonymizeData
        $this.Logger = $Logger
        $this.AnonymizationMappings = @{
            ServerNames = @{}
            IPAddresses = @{}
            DatabaseInstances = @{}
            Hostnames = @{}
        }
    }
    
    # Generate enhanced MPA format with database columns (single CSV with extended columns)
    [array] GenerateEnhancedMPA([array] $VMData) {
        $this.Logger.WriteInformation("Generating Enhanced MPA format for $($VMData.Count) VMs with database support")
        
        $data = @()
        
        # Add header row with original 22 columns plus database columns
        $headers = @(
            # Original MPA columns (1-22)
            "Serverid",                           # Column 1
            "Migration Evaluator GUID",           # Column 2
            "isPhysical",                         # Column 3
            "hypervisor",                         # Column 4
            "HOSTNAME",                           # Column 5
            "osName",                             # Column 6
            "osVersion",                          # Column 7
            "numCpus",                            # Column 8
            "numCoresPerCpu",                     # Column 9
            "numThreadsPerCore",                  # Column 10
            "maxCpuUsage",                        # Column 11
            "avgCpuUsage",                        # Column 12
            "totalRAM (GB)",                      # Column 13
            "maxRamUsage",                        # Column 14
            "avgRamUsage",                        # Column 15
            "Uptime",                             # Column 16
            "Environment Type",                   # Column 17
            "Storage-Total Disk Size (GB)",      # Column 18
            "Storage-Utilization %",              # Column 19
            "Storage-Max Read IOPS Size (KB)",   # Column 20
            "Storage-Max Write IOPS Size (KB)",  # Column 21
            "EC2 Instance Preference",           # Column 22
            
            # Database columns (23+)
            "Database Types Found",               # Column 23
            "Database Count",                     # Column 24
            "SQL Server Found",                   # Column 25
            "SQL Server Edition",                 # Column 26
            "SQL Server Version",                 # Column 27
            "PostgreSQL Found",                   # Column 28
            "PostgreSQL Version",                 # Column 29
            "Oracle Found",                       # Column 30
            "Oracle Edition",                     # Column 31
            "Oracle Version",                     # Column 32
            "MySQL Found",                        # Column 33
            "MySQL Version",                      # Column 34
            "MariaDB Found",                      # Column 35
            "MariaDB Version"                     # Column 36
        )
        $data += ,$headers
        
        # Add data rows
        foreach ($vm in $VMData) {
            # Get database information
            $databaseTypes = @()
            $databaseCount = 0
            $sqlServerInfo = @{ Found = "No"; Edition = ""; Version = "" }
            $postgresqlInfo = @{ Found = "No"; Version = "" }
            $oracleInfo = @{ Found = "No"; Edition = ""; Version = "" }
            $mysqlInfo = @{ Found = "No"; Version = "" }
            $mariadbInfo = @{ Found = "No"; Version = "" }
            
            if ($vm.DatabaseInfo) {
                # SQL Server
                if ($vm.DatabaseInfo.SQLServer -and $vm.DatabaseInfo.SQLServer.Found) {
                    $databaseTypes += "SQL Server"
                    $databaseCount++
                    $sqlServerInfo.Found = "Yes"
                    $sqlServerInfo.Edition = $vm.DatabaseInfo.SQLServer.EditionCategory
                    $sqlServerInfo.Version = $vm.DatabaseInfo.SQLServer.ProductVersion
                }
                
                # PostgreSQL
                if ($vm.DatabaseInfo.PostgreSQL -and $vm.DatabaseInfo.PostgreSQL.Found) {
                    $databaseTypes += "PostgreSQL"
                    $databaseCount++
                    $postgresqlInfo.Found = "Yes"
                    $postgresqlInfo.Version = $vm.DatabaseInfo.PostgreSQL.ProductVersion
                }
                
                # Oracle
                if ($vm.DatabaseInfo.Oracle -and $vm.DatabaseInfo.Oracle.Found) {
                    $databaseTypes += "Oracle"
                    $databaseCount++
                    $oracleInfo.Found = "Yes"
                    $oracleInfo.Edition = $vm.DatabaseInfo.Oracle.Edition
                    $oracleInfo.Version = $vm.DatabaseInfo.Oracle.ProductVersion
                }
                
                # MySQL
                if ($vm.DatabaseInfo.MySQL -and $vm.DatabaseInfo.MySQL.Found) {
                    $databaseTypes += "MySQL"
                    $databaseCount++
                    $mysqlInfo.Found = "Yes"
                    $mysqlInfo.Version = $vm.DatabaseInfo.MySQL.ProductVersion
                }
                
                # MariaDB
                if ($vm.DatabaseInfo.MariaDB -and $vm.DatabaseInfo.MariaDB.Found) {
                    $databaseTypes += "MariaDB"
                    $databaseCount++
                    $mariadbInfo.Found = "Yes"
                    $mariadbInfo.Version = $vm.DatabaseInfo.MariaDB.ProductVersion
                }
            }
            
            $serverName = if ($this.AnonymizeData) { $this.AnonymizeServerName($vm.Name) } else { $vm.Name }
            $hostName = if ($this.AnonymizeData) { $this.AnonymizeServerName($vm.HostName) } else { $vm.HostName }
            
            $row = @(
                # Original MPA columns (1-22)
                $serverName,                                                # Column 1: Serverid
                $serverName.ToLower(),                                      # Column 2: Migration Evaluator GUID
                "Virtual",                                                  # Column 3: isPhysical
                "VMware",                                                   # Column 4: hypervisor
                $this.GetHostName($hostName),                               # Column 5: HOSTNAME
                $this.MapOSName($vm.OperatingSystem),                       # Column 6: osName
                $this.MapOSVersion($vm.OperatingSystem),                    # Column 7: osVersion
                $vm.NumCPUs,                                                # Column 8: numCpus
                $this.CalculateCoresPerCpu($vm),                            # Column 9: numCoresPerCpu
                1,                                                          # Column 10: numThreadsPerCore
                $this.FormatDecimal($vm.MaxCpuUsagePct / 100.0, 2),       # Column 11: maxCpuUsage
                $this.FormatDecimal($vm.AvgCpuUsagePct / 100.0, 2),       # Column 12: avgCpuUsage
                $this.FormatDecimal($vm.MemoryMB / 1024.0, 1),            # Column 13: totalRAM (GB)
                $this.FormatDecimal($vm.MaxRamUsagePct / 100.0, 2),       # Column 14: maxRamUsage
                $this.FormatDecimal($vm.AvgRamUsagePct / 100.0, 2),       # Column 15: avgRamUsage
                1.0,                                                        # Column 16: Uptime
                "",                                                         # Column 17: Environment Type
                $this.FormatDecimal($vm.TotalStorageGB, 7),                # Column 18: Storage-Total Disk Size (GB)
                "",                                                         # Column 19: Storage-Utilization %
                "",                                                         # Column 20: Storage-Max Read IOPS Size (KB)
                "",                                                         # Column 21: Storage-Max Write IOPS Size (KB)
                "",                                                         # Column 22: EC2 Instance Preference
                
                # Database columns (23-36)
                ($databaseTypes -join ', '),                               # Column 23: Database Types Found
                $databaseCount,                                             # Column 24: Database Count
                $sqlServerInfo.Found,                                       # Column 25: SQL Server Found
                $sqlServerInfo.Edition,                                     # Column 26: SQL Server Edition
                $sqlServerInfo.Version,                                     # Column 27: SQL Server Version
                $postgresqlInfo.Found,                                      # Column 28: PostgreSQL Found
                $postgresqlInfo.Version,                                    # Column 29: PostgreSQL Version
                $oracleInfo.Found,                                          # Column 30: Oracle Found
                $oracleInfo.Edition,                                        # Column 31: Oracle Edition
                $oracleInfo.Version,                                        # Column 32: Oracle Version
                $mysqlInfo.Found,                                           # Column 33: MySQL Found
                $mysqlInfo.Version,                                         # Column 34: MySQL Version
                $mariadbInfo.Found,                                         # Column 35: MariaDB Found
                $mariadbInfo.Version                                        # Column 36: MariaDB Version
            )
            $data += ,$row
        }
        
        if ($this.AnonymizeData) {
            $this.Logger.WriteInformation("Applied anonymization to $($this.AnonymizationMappings.ServerNames.Count) servers")
        }
        
        $this.Logger.WriteInformation("Generated Enhanced MPA data for $($VMData.Count) VMs with $($headers.Count) columns")
        return $data
    }
    
    # Get hostname with fallback
    [string] GetHostName([string] $HostName) {
        if (-not [string]::IsNullOrEmpty($HostName)) {
            return $HostName
        }
        return "mocked-host-1"
    }
    
    # Map operating system name
    [string] MapOSName([string] $OperatingSystem) {
        if ([string]::IsNullOrEmpty($OperatingSystem)) {
            return "Other 5.x Linux (64-bit)"
        }
        
        $os = $OperatingSystem.ToLower()
        
        if ($os -match "windows.*server.*2019") {
            return "Windows Server 2019 (64-bit)"
        }
        elseif ($os -match "windows.*server.*2016") {
            return "Windows Server 2016 (64-bit)"
        }
        elseif ($os -match "windows.*server") {
            return "Windows Server 2019 (64-bit)"
        }
        elseif ($os -match "ubuntu") {
            return "Ubuntu (64-bit)"
        }
        elseif ($os -match "linux") {
            return "Other 5.x Linux (64-bit)"
        }
        else {
            return "Other 5.x Linux (64-bit)"
        }
    }
    
    # Map operating system version
    [string] MapOSVersion([string] $OperatingSystem) {
        if ([string]::IsNullOrEmpty($OperatingSystem)) {
            return "other 5.x linux 64-bit"
        }
        
        $os = $OperatingSystem.ToLower()
        
        if ($os -match "windows.*server.*2019") {
            return "2019 64-bit"
        }
        elseif ($os -match "windows.*server.*2016") {
            return "2016 64-bit"
        }
        elseif ($os -match "windows.*10") {
            return "10 64-bit"
        }
        elseif ($os -match "windows") {
            return "2019 64-bit"
        }
        else {
            return "other 5.x linux 64-bit"
        }
    }
    
    # Calculate cores per CPU based on requirements
    [int] CalculateCoresPerCpu([object] $VM) {
        # If VM has NumCoresPerSocket property and it's valid, use it
        if ($VM.PSObject.Properties['NumCoresPerSocket'] -and $VM.NumCoresPerSocket -gt 0) {
            return $VM.NumCoresPerSocket
        }
        
        # Estimate based on total CPUs
        $result = switch ($VM.NumCPUs) {
            1 { 1 }
            2 { 1 }
            4 { 2 }
            8 { 4 }
            default { [Math]::Max(1, [Math]::Floor($VM.NumCPUs / 2)) }
        }
        return $result
    }
    
    # Format decimal value with specified precision
    [string] FormatDecimal([double] $Value, [int] $DecimalPlaces) {
        $roundedValue = [Math]::Round($Value, $DecimalPlaces)
        return $roundedValue.ToString("F$DecimalPlaces")
    }
    
    # Anonymize server name
    [string] AnonymizeServerName([string] $ServerName) {
        if ([string]::IsNullOrEmpty($ServerName)) {
            return ""
        }
        
        if (-not $this.AnonymizationMappings.ServerNames.ContainsKey($ServerName)) {
            $anonymizedName = "SERVER-{0:D3}" -f ($this.AnonymizationMappings.ServerNames.Count + 1)
            $this.AnonymizationMappings.ServerNames[$ServerName] = $anonymizedName
        }
        
        return $this.AnonymizationMappings.ServerNames[$ServerName]
    }
    
    # Anonymize IP address
    [string] AnonymizeIPAddress([string] $IPAddress) {
        if ([string]::IsNullOrEmpty($IPAddress)) {
            return ""
        }
        
        if (-not $this.AnonymizationMappings.IPAddresses.ContainsKey($IPAddress)) {
            $anonymizedIP = "10.0.0.{0}" -f ($this.AnonymizationMappings.IPAddresses.Count + 100)
            $this.AnonymizationMappings.IPAddresses[$IPAddress] = $anonymizedIP
        }
        
        return $this.AnonymizationMappings.IPAddresses[$IPAddress]
    }
    
    # Anonymize database instance name
    [string] AnonymizeDatabaseInstance([string] $InstanceName) {
        if ([string]::IsNullOrEmpty($InstanceName)) {
            return ""
        }
        
        if (-not $this.AnonymizationMappings.DatabaseInstances.ContainsKey($InstanceName)) {
            $anonymizedInstance = "DB-INSTANCE-{0:D3}" -f ($this.AnonymizationMappings.DatabaseInstances.Count + 1)
            $this.AnonymizationMappings.DatabaseInstances[$InstanceName] = $anonymizedInstance
        }
        
        return $this.AnonymizationMappings.DatabaseInstances[$InstanceName]
    }
}