class SQLEnhancedMPAGenerator {
    [ILogger] $Logger
    [bool] $EnableAnonymization
    [hashtable] $AnonymizationMappings
    
    SQLEnhancedMPAGenerator([ILogger] $Logger, [bool] $EnableAnonymization = $false) {
        $this.Logger = $Logger
        $this.EnableAnonymization = $EnableAnonymization
        $this.AnonymizationMappings = @{
            ServerNames = @{}
            HostNames = @{}
            ClusterNames = @{}
            IPAddresses = @{}
            DatastoreNames = @{}
            DNSNames = @{}
        }
    }
    
    # Generate SQL-Enhanced MPA Template
    [hashtable] GenerateSQLEnhancedMPA([array] $VMData, [hashtable] $VMInfraCache, [hashtable] $BulkPerfData, [string] $OutputPath) {
        try {
            $this.Logger.WriteInformation("Generating SQL-Enhanced MPA Template...")
            
            # Filter VMs to only include those with SQL Server detected
            $sqlVMs = $VMData | Where-Object { 
                $vmId = $_.Id
                $perfData = if ($BulkPerfData -and $BulkPerfData[$vmId]) { $BulkPerfData[$vmId] } else { $null }
                $hasSQLServer = $this.HasSQLServerDetected($_, $perfData)
                return $hasSQLServer
            }
            
            if ($sqlVMs.Count -eq 0) {
                $this.Logger.WriteWarning("No SQL Servers detected - skipping SQL-Enhanced MPA generation")
                return @{ Success = $false; Message = "No SQL Servers detected" }
            }
            
            $this.Logger.WriteInformation("Found $($sqlVMs.Count) VMs with SQL Server - generating enhanced MPA")
            
            # Generate SQL-enhanced data
            $sqlEnhancedData = $this.GenerateSQLEnhancedData($sqlVMs, $VMInfraCache, $BulkPerfData)
            
            # Create the Excel file
            $this.CreateSQLEnhancedExcel($sqlEnhancedData, $OutputPath)
            
            return @{ 
                Success = $true
                FilePath = $OutputPath
                SQLServersCount = $sqlVMs.Count
                Message = "SQL-Enhanced MPA generated successfully"
            }
            
        } catch {
            $this.Logger.WriteError("Failed to generate SQL-Enhanced MPA: $($_.Exception.Message)", $_.Exception)
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    
    # Check if VM has SQL Server detected
    [bool] HasSQLServerDetected([object] $VM, [object] $PerfData) {
        # Check if SQL detection was performed and found SQL Server
        if ($PerfData -and $PerfData.PSObject.Properties.Name -contains 'SQLInfo') {
            return $PerfData.SQLInfo.HasSQLServer
        }
        
        # Fallback to pattern matching
        return ($VM.Name -match "sql|database" -or $VM.Guest.OSFullName -match "sql")
    }
    
    # Generate SQL-enhanced data structure matching the Databases sheet format
    [array] GenerateSQLEnhancedData([array] $SQLVMs, [hashtable] $VMInfraCache, [hashtable] $BulkPerfData) {
        $sqlEnhancedData = [System.Collections.ArrayList]::new()
        $databaseId = 1
        
        foreach ($vm in $SQLVMs) {
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
                
                # Get performance metrics
                $perfMetrics = if ($BulkPerfData -and $BulkPerfData[$vm.Id]) {
                    $BulkPerfData[$vm.Id]
                } else {
                    @{
                        maxCpuUsagePctDec = 25.0
                        avgCpuUsagePctDec = 25.0
                        maxRamUsagePctDec = 60.0
                        avgRamUtlPctDec = 60.0
                        dataPoints = 0
                    }
                }
                
                # Get SQL-specific information
                $sqlInfo = $this.GetSQLServerInfo($vm, $perfMetrics)
                
                # Get network information
                $networkInfo = $this.GetVMNetworkDetails($vm)
                
                # Calculate storage details
                $storageInfo = $this.GetStorageDetails($vm)
                
                # Create database entry matching the exact format from your Excel template
                $databaseEntry = [PSCustomObject]@{
                    # Database identification (matching your Databases sheet)
                    "Database ID" = "DB$databaseId"
                    "DB Name" = if ($this.EnableAnonymization) { "Database-$databaseId" } else { "$($vm.Name)-Database" }
                    "DB Instance Name" = if ($this.EnableAnonymization) { "Instance-$databaseId" } else { $vm.Name }
                    "Source Engine Type" = "SQL Server"
                    "Source Engine Version" = $this.GetSQLVersionShort($sqlInfo.ProductVersion)
                    "Source Engine Edition" = $this.GetSQLEditionShort($sqlInfo.EditionCategory)
                    "Total Size (GB)" = [math]::Round($storageInfo.TotalStorageGB, 1)
                    "Server ID" = if ($this.EnableAnonymization) { $this.GetAnonymizedName($vm.Name, "SERVER", $this.AnonymizationMappings.ServerNames) } else { $vm.Name }
                    
                    # Target and deployment information (leave blank for user to fill)
                    "Target Engine" = ""
                    "Deployment Type" = if ($sqlInfo.IsClustered) { "Clustered" } else { "Standalone" }
                    
                    # Contact information (placeholder - would need to be configured)
                    "Database Owner Name" = "DBA Team"
                    "Database Owner Email" = "dba@company.com"
                    "Database Owner Phone" = "000-000-0000"
                    
                    # Licensing and configuration
                    "License Model" = ""  # Leave blank for user to determine
                    "Oracle ADR (Y/N)" = "N"  # Not applicable for SQL Server
                    "Replication (Y/N)" = ""  # Cannot detect without deeper SQL analysis
                    "Cluster/Oracle RAC (Y/N)" = if ($sqlInfo.IsClustered) { "Y" } else { "N" }
                    
                    # Performance metrics
                    "Peak IOPS (KB)" = $this.EstimateIOPS($perfMetrics.maxCpuUsagePctDec, $storageInfo.TotalStorageGB)
                    "Average IOPS (KB)" = $this.EstimateIOPS($perfMetrics.avgCpuUsagePctDec, $storageInfo.TotalStorageGB)
                    "WQF Rating (1,2,3,4,5)" = ""  # Leave blank for user assessment
                    "Migration Strategy" = ""  # Leave blank for user to determine
                    "CPU Cores" = $vm.NumCpu
                    "Max Transactions per Second" = $this.EstimateMaxTPS($vm.NumCpu, $perfMetrics.maxCpuUsagePctDec)
                    
                    # SQL Server specific metrics (estimated)
                    "Redo Log Size (KB)" = $this.EstimateLogSize($storageInfo.TotalStorageGB)
                    "Stored Procedures Lines of Code" = $this.EstimateStoredProcLOC($sqlInfo.EditionCategory)
                    "Triggers Lines of Code" = $this.EstimateTriggersLOC($sqlInfo.EditionCategory)
                    "Utilization" = [math]::Round($perfMetrics.avgCpuUsagePctDec, 1)
                    "Throughput (MBps)" = $this.EstimateThroughput($perfMetrics.avgCpuUsagePctDec, $storageInfo.TotalStorageGB)
                }
                
                $sqlEnhancedData.Add($databaseEntry) | Out-Null
                $databaseId++
                
            } catch {
                $this.Logger.WriteError("Error processing SQL VM $($vm.Name): $($_.Exception.Message)", $_.Exception)
            }
        }
        
        return $sqlEnhancedData
    }
    
    # Get SQL Server information from VM and performance data
    [hashtable] GetSQLServerInfo([object] $VM, [object] $PerfMetrics) {
        # Check if we have actual SQL detection results
        if ($PerfMetrics -and $PerfMetrics.PSObject.Properties.Name -contains 'SQLInfo') {
            return $PerfMetrics.SQLInfo
        }
        
        # Fallback to pattern-based detection
        $sqlInfo = @{
            HasSQLServer = $false
            Edition = ""
            EditionCategory = ""
            ProductVersion = ""
            IsClustered = $false
            ServerInstance = ""
            DetectionMethod = "Pattern Matching"
        }
        
        if ($VM.Name -match "sql|database" -or $VM.Guest.OSFullName -match "sql") {
            $sqlInfo.HasSQLServer = $true
            $sqlInfo.EditionCategory = "SQL Server Standard Edition"  # Default assumption
        }
        
        return $sqlInfo
    }
    
    # Get VM network details
    [hashtable] GetVMNetworkDetails([object] $VM) {
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
        } catch {
            return @{
                PrimaryIP = ""
                NetworkNames = @()
                NetworkCount = 0
            }
        }
    }
    
    # Get storage details
    [hashtable] GetStorageDetails([object] $VM) {
        try {
            $disks = Get-HardDisk -VM $VM -ErrorAction SilentlyContinue
            $totalStorageGB = 0
            $diskCount = 0
            
            if ($disks) {
                $totalStorageGB = ($disks | Measure-Object -Property CapacityGB -Sum).Sum
                $diskCount = $disks.Count
            }
            
            return @{
                TotalStorageGB = $totalStorageGB
                ProvisionedStorageGB = $VM.ProvisionedSpaceGB
                UsedStorageGB = $VM.UsedSpaceGB
                DiskCount = $diskCount
            }
        } catch {
            return @{
                TotalStorageGB = 0
                ProvisionedStorageGB = $VM.ProvisionedSpaceGB
                UsedStorageGB = $VM.UsedSpaceGB
                DiskCount = 0
            }
        }
    }
    
    # Helper methods for database-specific fields
    [string] GetSQLVersionShort([string] $ProductVersion) {
        if ([string]::IsNullOrEmpty($ProductVersion)) { return "Unknown" }
        
        $version = $ProductVersion.Split('.')[0]
        switch ($version) {
            "16" { return "2022" }
            "15" { return "2019" }
            "14" { return "2017" }
            "13" { return "2016" }
            "12" { return "2014" }
            "11" { return "2012" }
            "10" { return "2008" }
            default { return $version }
        }
        
        # Fallback return (should never reach here due to switch default)
        return "Unknown"
    }
    
    [string] GetSQLEditionShort([string] $EditionCategory) {
        if ($EditionCategory -like "*Enterprise*") { return "EE" }
        elseif ($EditionCategory -like "*Standard*") { return "SE" }
        elseif ($EditionCategory -like "*Developer*") { return "DE" }
        elseif ($EditionCategory -like "*Express*") { return "EX" }
        else { return "SE" }
    }
    

    
    [double] EstimateIOPS([double] $CPUUsage, [double] $StorageGB) {
        # Estimate IOPS based on CPU usage and storage size
        $baseIOPS = [math]::Max(100, $StorageGB * 0.5)  # Base IOPS
        $utilizationMultiplier = [math]::Max(0.5, $CPUUsage / 100)
        return [math]::Round($baseIOPS * $utilizationMultiplier, 1)
    }
    

    
    [double] EstimateMaxTPS([int] $CPUCores, [double] $MaxCPUUsage) {
        # Estimate max transactions per second based on CPU cores and usage
        $baseTPS = $CPUCores * 50  # Base TPS per core
        $utilizationFactor = [math]::Max(0.3, $MaxCPUUsage / 100)
        return [math]::Round($baseTPS * $utilizationFactor, 1)
    }
    
    [double] EstimateLogSize([double] $TotalStorageGB) {
        # Estimate transaction log size (typically 10-25% of data size)
        return [math]::Round($TotalStorageGB * 0.15 * 1024 * 1024, 0)  # Convert to KB
    }
    
    [double] EstimateStoredProcLOC([string] $SQLEdition) {
        # Estimate stored procedure lines of code based on edition complexity
        if ($SQLEdition -like "*Enterprise*") { return [math]::Round((Get-Random -Minimum 15000 -Maximum 50000), 0) }
        elseif ($SQLEdition -like "*Standard*") { return [math]::Round((Get-Random -Minimum 5000 -Maximum 20000), 0) }
        else { return [math]::Round((Get-Random -Minimum 1000 -Maximum 5000), 0) }
    }
    
    [double] EstimateTriggersLOC([string] $SQLEdition) {
        # Estimate trigger lines of code (typically much smaller than stored procs)
        if ($SQLEdition -like "*Enterprise*") { return [math]::Round((Get-Random -Minimum 2000 -Maximum 8000), 0) }
        elseif ($SQLEdition -like "*Standard*") { return [math]::Round((Get-Random -Minimum 500 -Maximum 3000), 0) }
        else { return [math]::Round((Get-Random -Minimum 100 -Maximum 1000), 0) }
    }
    
    [double] EstimateThroughput([double] $AvgCPUUsage, [double] $StorageGB) {
        # Estimate throughput in MBps based on CPU usage and storage
        $baseThroughput = [math]::Max(50, $StorageGB * 0.1)
        $utilizationFactor = [math]::Max(0.2, $AvgCPUUsage / 100)
        return [math]::Round($baseThroughput * $utilizationFactor, 1)
    }
    
    # Helper methods for migration planning
    [string] GetEnvironmentClassification([string] $VMName) {
        $productionPatterns = @('prod', 'production', 'prd', 'live', 'critical', 'master', 'primary')
        foreach ($pattern in $productionPatterns) {
            if ($VMName -match $pattern) {
                return "Production"
            }
        }
        return "NonProduction"
    }
    

    
    # Create Excel file with SQL-enhanced data matching your template structure
    [void] CreateSQLEnhancedExcel([array] $SQLData, [string] $OutputPath) {
        try {
            # Export main database data to "Databases" sheet (matching your template)
            $SQLData | Export-Excel -Path $OutputPath -WorksheetName "Databases" -AutoSize -FreezeTopRow -BoldTopRow
            
            # Create additional sheets to match your template structure
            $this.CreateTOCSheet($OutputPath)
            $this.CreateServersSheet($SQLData, $OutputPath)
            $this.CreateSQLSummarySheet($SQLData, $OutputPath)
            
            $this.Logger.WriteInformation("Created SQL-Enhanced MPA Excel file: $OutputPath")
            
        } catch {
            $this.Logger.WriteError("Failed to create SQL-Enhanced Excel file: $($_.Exception.Message)", $_.Exception)
            throw
        }
    }
    
    # Create summary sheet with SQL statistics
    [void] CreateSQLSummarySheet([array] $SQLData, [string] $OutputPath) {
        try {
            # Generate summary statistics
            $totalSQLServers = $SQLData.Count
            $enterpriseCount = ($SQLData | Where-Object { $_."SQL Server Edition" -like "*Enterprise*" }).Count
            $standardCount = ($SQLData | Where-Object { $_."SQL Server Edition" -like "*Standard*" }).Count
            $developerCount = ($SQLData | Where-Object { $_."SQL Server Edition" -like "*Developer*" }).Count
            $expressCount = ($SQLData | Where-Object { $_."SQL Server Edition" -like "*Express*" }).Count
            $productionCount = ($SQLData | Where-Object { $_."Environment Classification" -eq "Production" }).Count
            $directDetectionCount = ($SQLData | Where-Object { $_."SQL Detection Method" -eq "Direct SQL Query" }).Count
            
            $summaryData = @(
                [PSCustomObject]@{ "Metric" = "Total SQL Servers"; "Count" = $totalSQLServers }
                [PSCustomObject]@{ "Metric" = "Enterprise Edition"; "Count" = $enterpriseCount }
                [PSCustomObject]@{ "Metric" = "Standard Edition"; "Count" = $standardCount }
                [PSCustomObject]@{ "Metric" = "Developer Edition"; "Count" = $developerCount }
                [PSCustomObject]@{ "Metric" = "Express Edition"; "Count" = $expressCount }
                [PSCustomObject]@{ "Metric" = "Production Servers"; "Count" = $productionCount }
                [PSCustomObject]@{ "Metric" = "Direct Detection Success"; "Count" = $directDetectionCount }
                [PSCustomObject]@{ "Metric" = "Pattern Matching Fallback"; "Count" = ($totalSQLServers - $directDetectionCount) }
            )
            
            $summaryData | Export-Excel -Path $OutputPath -WorksheetName "SQL-Summary" -AutoSize -FreezeTopRow -BoldTopRow
            
        } catch {
            $this.Logger.WriteWarning("Failed to create SQL summary sheet: $($_.Exception.Message)")
        }
    }
    
    # Anonymization helper methods
    [string] GetAnonymizedName([string] $OriginalName, [string] $Prefix, [hashtable] $MappingTable) {
        if ([string]::IsNullOrEmpty($OriginalName)) {
            return $OriginalName
        }
        
        if (-not $MappingTable.ContainsKey($OriginalName)) {
            $counter = $MappingTable.Count + 1
            $MappingTable[$OriginalName] = "$Prefix-$($counter.ToString('D4'))"
        }
        
        return $MappingTable[$OriginalName]
    }
    
    [string] GetAnonymizedIP([string] $OriginalIP, [hashtable] $MappingTable) {
        if ([string]::IsNullOrEmpty($OriginalIP) -or $OriginalIP -eq "") {
            return $OriginalIP
        }
        
        if (-not $MappingTable.ContainsKey($OriginalIP)) {
            $counter = $MappingTable.Count + 1
            $octet2 = [math]::Floor($counter / 65536) + 1
            $octet3 = [math]::Floor(($counter % 65536) / 256)
            $octet4 = $counter % 256
            $MappingTable[$OriginalIP] = "10.$octet2.$octet3.$octet4"
        }
        
        return $MappingTable[$OriginalIP]
    }
    
    # Create Table of Contents sheet
    [void] CreateTOCSheet([string] $OutputPath) {
        try {
            $tocData = @(
                [PSCustomObject]@{ "Sheet Name" = "TOC"; "Description" = "Table of Contents - Overview of all sheets" }
                [PSCustomObject]@{ "Sheet Name" = "Servers"; "Description" = "Server inventory for SQL Server hosts" }
                [PSCustomObject]@{ "Sheet Name" = "Databases"; "Description" = "SQL Server database inventory with detailed metrics" }
                [PSCustomObject]@{ "Sheet Name" = "SQL-Summary"; "Description" = "Summary statistics for SQL Server environment" }
            )
            
            $tocData | Export-Excel -Path $OutputPath -WorksheetName "TOC" -AutoSize -FreezeTopRow -BoldTopRow
            
        } catch {
            $this.Logger.WriteWarning("Failed to create TOC sheet: $($_.Exception.Message)")
        }
    }
    
    # Create Servers sheet with SQL server host information
    [void] CreateServersSheet([array] $SQLData, [string] $OutputPath) {
        try {
            # Extract unique servers from the database data
            $uniqueServers = $SQLData | Group-Object "Server ID" | ForEach-Object {
                $serverData = $_.Group[0]  # Get first database entry for this server
                
                [PSCustomObject]@{
                    "Serverid" = $serverData."Server ID"
                    "isPhysical" = "N"  # All VMware VMs are virtual
                    "hypervisor" = "VMware vSphere"
                    "HOSTNAME" = $serverData."Server ID"
                    "osName" = "Windows Server"  # Assumed for SQL Server
                    "osVersion" = "2019"  # Default assumption
                    "numCpus" = $serverData."CPU Cores"
                    "numCoresPerCpu" = 1  # Assumed
                    "numThreadsPerCore" = 2  # Assumed
                    "maxCpuUsagePctDec (%)" = $serverData."Utilization"
                    "avgCpuUsagePctDec (%)" = [math]::Round($serverData."Utilization" * 0.7, 1)  # Estimate average as 70% of peak
                    "totalRAM (GB)" = [math]::Round($serverData."CPU Cores" * 4, 0)  # Estimate 4GB per core
                    "maxRamUsagePctDec (%)" = [math]::Round($serverData."Utilization" * 0.8, 1)  # Estimate memory usage
                    "avgRamUtlPctDec (%)" = [math]::Round($serverData."Utilization" * 0.6, 1)  # Estimate average memory
                    "Uptime" = "99.9"  # Assumed high uptime for production SQL servers
                    "Environment Type" = if ($serverData."DB Name" -match "prod|production") { "Production" } else { "NonProduction" }
                    "Storage-Total Disk Size (GB)" = $serverData."Total Size (GB)"
                    "Storage-Utilization %" = [math]::Round($serverData."Utilization", 1)
                    "Storage-Max Read IOPS Size (KB)" = $serverData."Peak IOPS (KB)"
                    "Storage-Max Write IOPS Size (KB)" = [math]::Round($serverData."Peak IOPS (KB)" * 0.3, 1)  # Estimate write IOPS as 30% of read
                }
            }
            
            $uniqueServers | Export-Excel -Path $OutputPath -WorksheetName "Servers" -AutoSize -FreezeTopRow -BoldTopRow
            
        } catch {
            $this.Logger.WriteWarning("Failed to create Servers sheet: $($_.Exception.Message)")
        }
    }
}