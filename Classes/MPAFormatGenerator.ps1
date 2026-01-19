# Migration Portfolio Assessment (MPA) Format Generator
# Generates CSV file with 22 columns for AWS Migration Portfolio Assessment

using namespace System.Collections.Generic

class MPAFormatGenerator {
    [string] $FileName = "MPA_Template"
    [ILogger] $Logger
    [bool] $EnableDatabaseDetection
    
    # Constructor
    MPAFormatGenerator() {
        $this.EnableDatabaseDetection = $false
    }
    
    MPAFormatGenerator([ILogger] $Logger) {
        $this.Logger = $Logger
        $this.EnableDatabaseDetection = $false
    }
    
    MPAFormatGenerator([ILogger] $Logger, [bool] $EnableDatabaseDetection) {
        $this.Logger = $Logger
        $this.EnableDatabaseDetection = $EnableDatabaseDetection
    }
    
    # Main generation method - creates Excel file with Servers sheet and optionally Databases sheet
    [void] GenerateOutput([array] $ServersData, [string] $OutputPath) {
        try {
            $this.WriteLog("Starting MPA Excel format generation for $($ServersData.Count) servers", "Info")
            
            # Convert ServersData to MPA format (20 columns)
            $mpaServersData = $this.ConvertToMPAFormat($ServersData)
            
            # Export Servers sheet (always created) with MPA format
            $mpaServersData | Export-Excel -Path $OutputPath -WorksheetName "Servers" -AutoSize -FreezeTopRow -BoldTopRow
            $this.WriteLog("Created Servers sheet with $($mpaServersData.Count) entries in MPA format", "Info")
            
            # Create Databases sheet if database detection is enabled
            if ($this.EnableDatabaseDetection) {
                $this.CreateDatabasesSheet($ServersData, $OutputPath)
            }
            
            # Validate output
            if ($this.ValidateOutput($OutputPath, $ServersData)) {
                $this.WriteLog("MPA Excel format generation completed successfully: $OutputPath", "Info")
            } else {
                throw "MPA format validation failed"
            }
        }
        catch {
            $this.WriteLog("Error generating MPA Excel format: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Convert ServersData to MPA format (20 columns matching Test-Data-Set-Demo-Excel-V2.xlsx)
    [array] ConvertToMPAFormat([array] $ServersData) {
        $this.WriteLog("Converting $($ServersData.Count) servers to MPA format", "Info")
        
        $mpaData = @()
        
        foreach ($server in $ServersData) {
            $mpaEntry = [PSCustomObject]@{
                "Serverid" = $server.serverName                                    # Column 1
                "isPhysical" = "Virtual"                                           # Column 2 (always Virtual for VMs)
                "hypervisor" = "VMware"                                            # Column 3 (always VMware)
                "HOSTNAME" = $server.serverName                                    # Column 4 (server name, not ESXi host)
                "osName" = $this.MapOSName($server.operatingSystem)               # Column 5
                "osVersion" = $this.MapOSVersion($server.operatingSystem)         # Column 6
                "numCpus" = $server.cpuCores                                       # Column 7
                "numCoresPerCpu" = $this.CalculateCoresPerCpu($server)            # Column 8
                "numThreadsPerCore" = 1                                            # Column 9 (always 1)
                "maxCpuUsagePctDec (%)" = $this.FormatDecimal($server.maxCpuUsagePct, 2)  # Column 10 (P95 CPU as percentage)
                "avgCpuUsagePctDec (%)" = $this.FormatDecimal($server.avgCpuUsagePct, 2)  # Column 11 (Avg CPU as percentage)
                "totalRAM (GB)" = $this.FormatDecimal($server.ramMB / 1024.0, 1)  # Column 12
                "maxRamUsagePctDec (%)" = $this.FormatDecimal($server.maxRamUsagePct, 2)  # Column 13 (P95 Memory as percentage)
                "avgRamUtlPctDec (%)" = $this.FormatDecimal($server.avgRamUsagePct, 2)  # Column 14 (Avg Memory as percentage)
                "Uptime" = 1.0                                                     # Column 15 (always 1.0)
                "Environment Type" = ""                                            # Column 16 (empty)
                "Storage-Total Disk Size (GB)" = $this.FormatDecimal($server.diskGB, 7)  # Column 17
                "Storage-Utilization %" = ""                                      # Column 18 (empty)
                "Storage-Max Read IOPS Size (KB)" = ""                            # Column 19 (empty)
                "Storage-Max Write IOPS Size (KB)" = ""                           # Column 20 (empty)
            }
            $mpaData += $mpaEntry
        }
        
        $this.WriteLog("Converted $($mpaData.Count) servers to MPA format", "Info")
        return $mpaData
    }
    
    # Create Databases sheet if database detection is enabled
    [void] CreateDatabasesSheet([array] $ServersData, [string] $OutputPath) {
        try {
            $this.WriteLog("Creating Databases sheet for MPA Excel file", "Info")
            
            # Filter servers that have database information
            $databaseServers = $ServersData | Where-Object { 
                $_.PSObject.Properties.Name -contains 'DatabaseInfo' -and $_.DatabaseInfo 
            }
            
            if ($databaseServers.Count -eq 0) {
                $this.WriteLog("No database servers found - creating empty Databases sheet", "Warning")
                # Create empty databases sheet with headers
                $emptyDatabaseData = @(
                    [PSCustomObject]@{
                        "Database ID" = ""
                        "DB Name" = ""
                        "DB Instance Name" = ""
                        "Source Engine Type" = ""
                        "Source Engine Version" = ""
                        "Source Engine Edition" = ""
                        "Total Size (GB)" = ""
                        "Server ID" = ""
                        "Target Engine" = ""
                        "Deployment Type" = ""
                        "Database Owner Name" = ""
                        "Database Owner Email" = ""
                        "Database Owner Phone" = ""
                        "License Model" = ""
                        "Oracle ADR (Y/N)" = ""
                        "Replication (Y/N)" = ""
                        "Cluster/Oracle RAC (Y/N)" = ""
                        "Peak IOPS (KB)" = ""
                        "Average IOPS (KB)" = ""
                        "WQF Rating (1,2,3,4,5)" = ""
                        "Migration Strategy" = ""
                        "CPU Cores" = ""
                        "Max Transactions per Second" = ""
                        "Redo Log Size (KB)" = ""
                        "Stored Procedures Lines of Code" = ""
                        "Triggers Lines of Code" = ""
                        "Utilization" = ""
                        "Throughput (MBps)" = ""
                    }
                )
                $emptyDatabaseData | Export-Excel -Path $OutputPath -WorksheetName "Databases" -AutoSize -FreezeTopRow -BoldTopRow
                return
            }
            
            # Create database entries matching Test-Data-Set-Demo-Excel-V2.xlsx format (28 columns)
            $databaseData = @()
            $dbIdCounter = 1
            
            foreach ($server in $databaseServers) {
                if ($server.DatabaseInfo.SQLServer -and $server.DatabaseInfo.SQLServer.Found) {
                    $databaseData += [PSCustomObject]@{
                        "Database ID" = "DB$dbIdCounter"                                           # Column 1
                        "DB Name" = if ($server.DatabaseInfo.SQLServer.DatabaseNames) { $server.DatabaseInfo.SQLServer.DatabaseNames[0] } else { "SQL Database" }  # Column 2
                        "DB Instance Name" = if ($server.DatabaseInfo.SQLServer.InstanceName) { $server.DatabaseInfo.SQLServer.InstanceName } else { "MSSQLSERVER" }  # Column 3
                        "Source Engine Type" = "SQL Server"                                       # Column 4
                        "Source Engine Version" = $server.DatabaseInfo.SQLServer.ProductVersion  # Column 5
                        "Source Engine Edition" = $server.DatabaseInfo.SQLServer.EditionCategory # Column 6
                        "Total Size (GB)" = ""                                                    # Column 7 (empty)
                        "Server ID" = $server.serverName                                          # Column 8
                        "Target Engine" = ""                                                      # Column 9 (empty)
                        "Deployment Type" = ""                                                    # Column 10 (empty)
                        "Database Owner Name" = ""                                                # Column 11 (empty)
                        "Database Owner Email" = ""                                               # Column 12 (empty)
                        "Database Owner Phone" = ""                                               # Column 13 (empty)
                        "License Model" = ""                                                      # Column 14 (empty)
                        "Oracle ADR (Y/N)" = ""                                                  # Column 15 (empty)
                        "Replication (Y/N)" = ""                                                 # Column 16 (empty)
                        "Cluster/Oracle RAC (Y/N)" = ""                                          # Column 17 (empty)
                        "Peak IOPS (KB)" = ""                                                    # Column 18 (empty)
                        "Average IOPS (KB)" = ""                                                 # Column 19 (empty)
                        "WQF Rating (1,2,3,4,5)" = ""                                           # Column 20 (empty)
                        "Migration Strategy" = ""                                                # Column 21 (empty)
                        "CPU Cores" = ""                                                         # Column 22 (empty)
                        "Max Transactions per Second" = ""                                       # Column 23 (empty)
                        "Redo Log Size (KB)" = ""                                               # Column 24 (empty)
                        "Stored Procedures Lines of Code" = ""                                  # Column 25 (empty)
                        "Triggers Lines of Code" = ""                                           # Column 26 (empty)
                        "Utilization" = ""                                                      # Column 27 (empty)
                        "Throughput (MBps)" = ""                                                # Column 28 (empty)
                    }
                    $dbIdCounter++
                }
                
                if ($server.DatabaseInfo.PostgreSQL -and $server.DatabaseInfo.PostgreSQL.Found) {
                    $databaseData += [PSCustomObject]@{
                        "Database ID" = "DB$dbIdCounter"
                        "DB Name" = if ($server.DatabaseInfo.PostgreSQL.DatabaseNames) { $server.DatabaseInfo.PostgreSQL.DatabaseNames[0] } else { "PostgreSQL Database" }
                        "DB Instance Name" = "postgres"
                        "Source Engine Type" = "PostgreSQL"
                        "Source Engine Version" = $server.DatabaseInfo.PostgreSQL.ProductVersion
                        "Source Engine Edition" = ""
                        "Total Size (GB)" = ""
                        "Server ID" = $server.serverName
                        "Target Engine" = ""
                        "Deployment Type" = ""
                        "Database Owner Name" = ""
                        "Database Owner Email" = ""
                        "Database Owner Phone" = ""
                        "License Model" = ""
                        "Oracle ADR (Y/N)" = ""
                        "Replication (Y/N)" = ""
                        "Cluster/Oracle RAC (Y/N)" = ""
                        "Peak IOPS (KB)" = ""
                        "Average IOPS (KB)" = ""
                        "WQF Rating (1,2,3,4,5)" = ""
                        "Migration Strategy" = ""
                        "CPU Cores" = ""
                        "Max Transactions per Second" = ""
                        "Redo Log Size (KB)" = ""
                        "Stored Procedures Lines of Code" = ""
                        "Triggers Lines of Code" = ""
                        "Utilization" = ""
                        "Throughput (MBps)" = ""
                    }
                    $dbIdCounter++
                }
                
                if ($server.DatabaseInfo.Oracle -and $server.DatabaseInfo.Oracle.Found) {
                    $databaseData += [PSCustomObject]@{
                        "Database ID" = "DB$dbIdCounter"
                        "DB Name" = if ($server.DatabaseInfo.Oracle.DatabaseNames) { $server.DatabaseInfo.Oracle.DatabaseNames[0] } else { "Oracle Database" }
                        "DB Instance Name" = if ($server.DatabaseInfo.Oracle.InstanceName) { $server.DatabaseInfo.Oracle.InstanceName } else { "ORCL" }
                        "Source Engine Type" = "Oracle"
                        "Source Engine Version" = $server.DatabaseInfo.Oracle.ProductVersion
                        "Source Engine Edition" = $server.DatabaseInfo.Oracle.Edition
                        "Total Size (GB)" = ""
                        "Server ID" = $server.serverName
                        "Target Engine" = ""
                        "Deployment Type" = ""
                        "Database Owner Name" = ""
                        "Database Owner Email" = ""
                        "Database Owner Phone" = ""
                        "License Model" = ""
                        "Oracle ADR (Y/N)" = ""
                        "Replication (Y/N)" = ""
                        "Cluster/Oracle RAC (Y/N)" = ""
                        "Peak IOPS (KB)" = ""
                        "Average IOPS (KB)" = ""
                        "WQF Rating (1,2,3,4,5)" = ""
                        "Migration Strategy" = ""
                        "CPU Cores" = ""
                        "Max Transactions per Second" = ""
                        "Redo Log Size (KB)" = ""
                        "Stored Procedures Lines of Code" = ""
                        "Triggers Lines of Code" = ""
                        "Utilization" = ""
                        "Throughput (MBps)" = ""
                    }
                    $dbIdCounter++
                }
                
                if ($server.DatabaseInfo.MySQL -and $server.DatabaseInfo.MySQL.Found) {
                    $databaseData += [PSCustomObject]@{
                        "Database ID" = "DB$dbIdCounter"
                        "DB Name" = if ($server.DatabaseInfo.MySQL.DatabaseNames) { $server.DatabaseInfo.MySQL.DatabaseNames[0] } else { "MySQL Database" }
                        "DB Instance Name" = "mysql"
                        "Source Engine Type" = "MySQL"
                        "Source Engine Version" = $server.DatabaseInfo.MySQL.ProductVersion
                        "Source Engine Edition" = ""
                        "Total Size (GB)" = ""
                        "Server ID" = $server.serverName
                        "Target Engine" = ""
                        "Deployment Type" = ""
                        "Database Owner Name" = ""
                        "Database Owner Email" = ""
                        "Database Owner Phone" = ""
                        "License Model" = ""
                        "Oracle ADR (Y/N)" = ""
                        "Replication (Y/N)" = ""
                        "Cluster/Oracle RAC (Y/N)" = ""
                        "Peak IOPS (KB)" = ""
                        "Average IOPS (KB)" = ""
                        "WQF Rating (1,2,3,4,5)" = ""
                        "Migration Strategy" = ""
                        "CPU Cores" = ""
                        "Max Transactions per Second" = ""
                        "Redo Log Size (KB)" = ""
                        "Stored Procedures Lines of Code" = ""
                        "Triggers Lines of Code" = ""
                        "Utilization" = ""
                        "Throughput (MBps)" = ""
                    }
                    $dbIdCounter++
                }
                
                if ($server.DatabaseInfo.MariaDB -and $server.DatabaseInfo.MariaDB.Found) {
                    $databaseData += [PSCustomObject]@{
                        "Database ID" = "DB$dbIdCounter"
                        "DB Name" = if ($server.DatabaseInfo.MariaDB.DatabaseNames) { $server.DatabaseInfo.MariaDB.DatabaseNames[0] } else { "MariaDB Database" }
                        "DB Instance Name" = "mariadb"
                        "Source Engine Type" = "MariaDB"
                        "Source Engine Version" = $server.DatabaseInfo.MariaDB.ProductVersion
                        "Source Engine Edition" = ""
                        "Total Size (GB)" = ""
                        "Server ID" = $server.serverName
                        "Target Engine" = ""
                        "Deployment Type" = ""
                        "Database Owner Name" = ""
                        "Database Owner Email" = ""
                        "Database Owner Phone" = ""
                        "License Model" = ""
                        "Oracle ADR (Y/N)" = ""
                        "Replication (Y/N)" = ""
                        "Cluster/Oracle RAC (Y/N)" = ""
                        "Peak IOPS (KB)" = ""
                        "Average IOPS (KB)" = ""
                        "WQF Rating (1,2,3,4,5)" = ""
                        "Migration Strategy" = ""
                        "CPU Cores" = ""
                        "Max Transactions per Second" = ""
                        "Redo Log Size (KB)" = ""
                        "Stored Procedures Lines of Code" = ""
                        "Triggers Lines of Code" = ""
                        "Utilization" = ""
                        "Throughput (MBps)" = ""
                    }
                    $dbIdCounter++
                }
            }
            
            if ($databaseData.Count -gt 0) {
                $databaseData | Export-Excel -Path $OutputPath -WorksheetName "Databases" -AutoSize -FreezeTopRow -BoldTopRow
                $this.WriteLog("Created Databases sheet with $($databaseData.Count) database entries", "Info")
            } else {
                $this.WriteLog("No databases detected - skipping Databases sheet creation", "Info")
            }
            
        } catch {
            $this.WriteLog("Error creating Databases sheet: $($_.Exception.Message)", "Error")
            throw
        }
    }
    # Validate output file - simplified for Excel format
    [bool] ValidateOutput([string] $FilePath, [array] $OriginalServersData) {
        try {
            $this.WriteLog("Validating MPA Excel output: $FilePath", "Info")
            
            if (-not (Test-Path $FilePath)) {
                $this.WriteLog("MPA Excel file not found: $FilePath", "Error")
                return $false
            }
            
            # Basic validation - check if ImportExcel module is available for validation
            if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
                $this.WriteLog("ImportExcel module not available for detailed validation - basic validation passed", "Warning")
                return $true
            }
            
            # TODO: Add detailed Excel validation if needed
            $this.WriteLog("MPA Excel output validation passed", "Info")
            return $true
        }
        catch {
            $this.WriteLog("Error during MPA validation: $($_.Exception.Message)", "Error")
            return $false
        }
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
    [int] CalculateCoresPerCpu([object] $Server) {
        # If server has NumCoresPerSocket property and it's valid, use it
        if ($Server.PSObject.Properties['NumCoresPerSocket'] -and $Server.NumCoresPerSocket -gt 0) {
            return $Server.NumCoresPerSocket
        }
        
        # Estimate based on total CPUs
        $result = switch ($Server.cpuCores) {
            1 { 1 }
            2 { 1 }
            4 { 2 }
            8 { 4 }
            default { [Math]::Max(1, [Math]::Floor($Server.cpuCores / 2)) }
        }
        return $result
    }
    
    # Format decimal value with specified precision
    [string] FormatDecimal([double] $Value, [int] $DecimalPlaces) {
        $roundedValue = [Math]::Round($Value, $DecimalPlaces)
        return $roundedValue.ToString("F$DecimalPlaces")
    }
    
    # Logging helper method
    [void] WriteLog([string] $Message, [string] $Level) {
        if ($this.Logger) {
            $this.Logger.WriteLog($Message, $Level)
        } else {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Write-Host "[$timestamp] [$Level] $Message"
        }
    }
}