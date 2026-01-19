#
# VMDataCollector.ps1 - Collects VM inventory data
#
# Replicates VM data collection logic from vmware-collector.ps1
#

using module .\Interfaces.ps1

class VMDataCollector {
    [ILogger] $Logger
    
    VMDataCollector([ILogger] $Logger) {
        $this.Logger = $Logger
    }
    
    # Process VMs into serversData format (exact same as vmware-collector.ps1)
    [array] ProcessVMsIntoServersData([array] $VMs, [hashtable] $VMInfraCache, [hashtable] $BulkPerfData) {
        try {
            $this.Logger.WriteInformation("Processing VMs into servers data format...")
            $serversData = @()
            
            foreach ($vm in $VMs) {
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
                    $networkInfo = $this.GetVMNetworkDetails($vm)
                    
                    # Calculate storage details
                    $storageInfo = $this.GetVMStorageDetails($vm, $false)
                    
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
                    
                    # Get database information if available (from performance data or pattern matching)
                    $databaseInfo = $this.GetDatabaseInformation($vm, $perfMetrics)
                    
                    # Create server data entry (exact same structure as vmware-collector.ps1)
                    $serverEntry = [PSCustomObject]@{
                        serverName = $vm.Name
                        operatingSystem = if ($vm.Guest.OSFullName) { $vm.Guest.OSFullName } else { $vm.ExtensionData.Config.GuestFullName }
                        cpuCores = $vm.NumCpu
                        ramMB = $vm.MemoryMB
                        diskGB = [math]::Round($storageInfo.TotalGB, 2)
                        powerState = $vm.PowerState.ToString()
                        ipAddress = $networkInfo.PrimaryIP
                        dnsName = if ($vm.Guest.HostName) { $vm.Guest.HostName } else { "" }
                        hostName = $infraInfo.HostName
                        clusterName = $infraInfo.ClusterName
                        datacenterName = $infraInfo.DatacenterName
                        datastoreName = $infraInfo.DatastoreNames
                        maxCpuUsagePct = [math]::Round($perfMetrics.maxCpuUsagePctDec, 2)
                        avgCpuUsagePct = [math]::Round($perfMetrics.avgCpuUsagePctDec, 2)
                        maxRamUsagePct = [math]::Round($perfMetrics.maxRamUsagePctDec, 2)
                        avgRamUsagePct = [math]::Round($perfMetrics.avgRamUtlPctDec, 2)
                        networkNames = ($networkInfo.Networks -join ", ")
                        vmPathName = if ($vm.ExtensionData.Config.Files.VmPathName) { $vm.ExtensionData.Config.Files.VmPathName } else { "" }
                        annotation = if ($vm.Notes) { $vm.Notes } else { "" }
                        hardwareVersion = if ($vm.HardwareVersion) { $vm.HardwareVersion } else { "Unknown" }
                        templateFlag = $vm.ExtensionData.Config.Template.ToString()
                        creationDate = if ($vm.ExtensionData.Config.CreateDate) { $vm.ExtensionData.Config.CreateDate } else { $null }
                        folderName = $infraInfo.FolderName
                        resourcePoolName = $infraInfo.ResourcePoolName
                        DatabaseInfo = $databaseInfo
                    }
                    
                    $serversData += $serverEntry
                    
                } catch {
                    $this.Logger.WriteError("Failed to process VM $($vm.Name): $($_.Exception.Message)", $_.Exception)
                }
            }
            
            $this.Logger.WriteInformation("Processed $($serversData.Count) VMs into servers data format")
            return $serversData
            
        } catch {
            $this.Logger.WriteError("Failed to process VMs into servers data: $($_.Exception.Message)", $_.Exception)
            return @()
        }
    }
    
    # Main VM data collection method
    [hashtable] CollectVMData([array] $VMs, [object] $CacheManager, [bool] $FastMode) {
        try {
            $this.Logger.WriteInformation("Collecting VM inventory data...")
            $collectionStartTime = Get-Date
            
            # Build VM-to-infrastructure mappings first
            $mappingResult = $CacheManager.BuildVMInfrastructureMappings($VMs)
            if (-not $mappingResult.Success) {
                $this.Logger.WriteWarning("VM infrastructure mapping had issues: $($mappingResult.ErrorMessage)")
            }
            
            # Collect VM data
            $vmData = @()
            $vmCount = 0
            $totalVMs = $VMs.Count
            
            foreach ($vm in $VMs) {
                $vmCount++
                
                # Progress reporting
                if ($totalVMs -gt 10) {
                    $vmPercent = [math]::Round(($vmCount / $totalVMs) * 100, 1)
                    Write-Progress -Activity "Collecting VM Data" -Status "Processing VM $vmCount of $totalVMs ($vmPercent%) - $($vm.Name)" -PercentComplete $vmPercent
                }
                
                try {
                    $vmInfo = $this.CollectSingleVMData($vm, $CacheManager, $FastMode)
                    $vmData += $vmInfo
                    
                } catch {
                    $this.Logger.WriteError("Failed to collect data for VM $($vm.Name): $($_.Exception.Message)", $_.Exception)
                }
            }
            
            if ($totalVMs -gt 10) {
                Write-Progress -Activity "Collecting VM Data" -Completed
            }
            
            $collectionTime = (Get-Date) - $collectionStartTime
            $this.Logger.WriteInformation("VM data collection completed in $($collectionTime.TotalSeconds.ToString('F1')) seconds")
            $this.Logger.WriteInformation("Collected data for $($vmData.Count) of $totalVMs VMs")
            
            return @{
                Success = $true
                VMData = $vmData
                CollectionTime = $collectionTime
                ProcessedCount = $vmData.Count
                TotalCount = $totalVMs
            }
            
        } catch {
            $this.Logger.WriteError("VM data collection failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                VMData = @()
            }
        }
    }
    
    # Collect data for a single VM
    [hashtable] CollectSingleVMData([object] $VM, [object] $CacheManager, [bool] $FastMode) {
        try {
            # Get infrastructure info from cache
            $infraInfo = $CacheManager.GetVMInfraInfo($VM)
            
            # Basic VM information
            $vmInfo = @{
                # Basic Information
                Name = $VM.Name
                PowerState = $VM.PowerState.ToString()
                TemplateFlag = $VM.ExtensionData.Config.Template.ToString()
                GuestOS = if ($VM.Guest.OSFullName) { $VM.Guest.OSFullName } else { $VM.ExtensionData.Config.GuestFullName }
                GuestOSDetailed = if ($VM.Guest.OSFullName) { $VM.Guest.OSFullName } else { "Unknown" }
                
                # Hardware Configuration
                NumCPUs = $VM.NumCpu
                CoresPerSocket = if ($VM.ExtensionData.Config.Hardware.NumCoresPerSocket) { $VM.ExtensionData.Config.Hardware.NumCoresPerSocket } else { 1 }
                MemoryMB = $VM.MemoryMB
                MemoryGB = [Math]::Round($VM.MemoryMB / 1024, 2)
                
                # Infrastructure Information
                HostName = $infraInfo.HostName
                ClusterName = $infraInfo.ClusterName
                DatacenterName = $infraInfo.DatacenterName
                ResourcePoolName = $infraInfo.ResourcePoolName
                FolderName = $infraInfo.FolderName
                DatastoreNames = $infraInfo.DatastoreNames
                
                # Network Information
                NetworkAdapterCount = 0
                NetworkNames = @()
                IPAddresses = @()
                PrimaryIP = ""
                
                # Storage Information
                TotalStorageGB = 0
                StorageCommittedGB = 0
                StorageUncommittedGB = 0
                DiskCount = 0
                
                # Additional Properties
                HardwareVersion = if ($VM.HardwareVersion) { $VM.HardwareVersion } else { "Unknown" }
                VMPathName = if ($VM.ExtensionData.Config.Files.VmPathName) { $VM.ExtensionData.Config.Files.VmPathName } else { "" }
                Annotation = if ($VM.Notes) { $VM.Notes } else { ""  }
                CreationDate = if ($VM.ExtensionData.Config.CreateDate) { $VM.ExtensionData.Config.CreateDate } else { $null }
                DNSName = ""
                Owner = ""
                
                # Performance placeholders (will be filled by performance collector)
                MaxCpuUsagePct = 0
                MaxRamUsagePct = 0
                MaxDiskIOPS = 0
                MaxNetworkMbps = 0
            }
            
            # Collect network information
            if (-not $FastMode) {
                $networkInfo = $this.GetVMNetworkDetails($VM)
                $vmInfo.NetworkAdapterCount = $networkInfo.AdapterCount
                $vmInfo.NetworkNames = $networkInfo.Networks
                $vmInfo.IPAddresses = $networkInfo.IPAddresses
                $vmInfo.PrimaryIP = $networkInfo.PrimaryIP
                $vmInfo.DNSName = $networkInfo.DNSName
            }
            
            # Collect storage information
            $storageInfo = $this.GetVMStorageDetails($VM, $FastMode)
            $vmInfo.TotalStorageGB = $storageInfo.TotalGB
            $vmInfo.StorageCommittedGB = $storageInfo.CommittedGB
            $vmInfo.StorageUncommittedGB = $storageInfo.UncommittedGB
            $vmInfo.DiskCount = $storageInfo.DiskCount
            
            # Additional details if not in fast mode
            if (-not $FastMode) {
                # Get owner information
                try {
                    if ($VM.ExtensionData.Config.ManagedBy) {
                        $vmInfo.Owner = $VM.ExtensionData.Config.ManagedBy.ExtensionKey
                    }
                } catch { }
                
                # Get DNS name from guest info
                try {
                    if ($VM.Guest.HostName) {
                        $vmInfo.DNSName = $VM.Guest.HostName
                    }
                } catch { }
            }
            
            return $vmInfo
            
        } catch {
            $this.Logger.WriteError("Failed to collect data for VM $($VM.Name): $($_.Exception.Message)", $_.Exception)
            throw
        }
    }
    
    # Get VM network details
    [hashtable] GetVMNetworkDetails([object] $VM) {
        try {
            $networkAdapters = Get-NetworkAdapter -VM $VM -ErrorAction SilentlyContinue
            $networks = @()
            $ipAddresses = @()
            $primaryIP = ""
            $dnsName = ""
            
            if ($networkAdapters) {
                foreach ($adapter in $networkAdapters) {
                    $networks += @{
                        NetworkName = if ($adapter.NetworkName) { $adapter.NetworkName } else { "Unknown" }
                        AdapterType = if ($adapter.Type) { $adapter.Type.ToString() } else { "Unknown" }
                        MacAddress = if ($adapter.MacAddress) { $adapter.MacAddress } else { "" }
                        Connected = $adapter.ConnectionState.Connected
                    }
                }
            }
            
            # Get IP addresses from guest info
            try {
                if ($VM.Guest.IPAddress) {
                    $ipAddresses = $VM.Guest.IPAddress | Where-Object { $_ -and $_ -ne "" }
                    if ($ipAddresses.Count -gt 0) {
                        $primaryIP = $ipAddresses[0]
                    }
                }
                
                if ($VM.Guest.HostName) {
                    $dnsName = $VM.Guest.HostName
                }
            } catch { }
            
            return @{
                AdapterCount = if ($networkAdapters) { $networkAdapters.Count } else { 0 }
                Networks = $networks
                IPAddresses = $ipAddresses
                PrimaryIP = $primaryIP
                DNSName = $dnsName
            }
            
        } catch {
            $this.Logger.WriteDebug("Failed to get network details for VM $($VM.Name): $_")
            return @{
                AdapterCount = 0
                Networks = @()
                IPAddresses = @()
                PrimaryIP = ""
                DNSName = ""
            }
        }
    }
    
    # Get VM storage details
    [hashtable] GetVMStorageDetails([object] $VM, [bool] $FastMode) {
        try {
            $totalGB = 0
            $committedGB = 0
            $uncommittedGB = 0
            $diskCount = 0
            
            if (-not $FastMode) {
                # Get detailed disk information
                $hardDisks = Get-HardDisk -VM $VM -ErrorAction SilentlyContinue
                if ($hardDisks) {
                    $diskCount = $hardDisks.Count
                    foreach ($disk in $hardDisks) {
                        $totalGB += [Math]::Round($disk.CapacityGB, 2)
                    }
                }
                
                # Get storage usage from VM properties
                try {
                    if ($VM.ExtensionData.Storage) {
                        $committedGB = [Math]::Round($VM.ExtensionData.Storage.PerDatastoreUsage[0].Committed / 1GB, 2)
                        $uncommittedGB = [Math]::Round($VM.ExtensionData.Storage.PerDatastoreUsage[0].Uncommitted / 1GB, 2)
                    }
                } catch { }
            } else {
                # Fast mode - use basic properties
                try {
                    $totalGB = [Math]::Round($VM.UsedSpaceGB, 2)
                    $committedGB = $totalGB
                    $diskCount = 1  # Estimate
                } catch {
                    $totalGB = 20  # Default estimate
                    $committedGB = 20
                    $diskCount = 1
                }
            }
            
            # Ensure we have reasonable values
            if ($totalGB -eq 0) { $totalGB = 20 }
            if ($committedGB -eq 0) { $committedGB = $totalGB }
            if ($diskCount -eq 0) { $diskCount = 1 }
            
            return @{
                TotalGB = $totalGB
                CommittedGB = $committedGB
                UncommittedGB = $uncommittedGB
                DiskCount = $diskCount
            }
            
        } catch {
            $this.Logger.WriteDebug("Failed to get storage details for VM $($VM.Name): $_")
            return @{
                TotalGB = 20
                CommittedGB = 20
                UncommittedGB = 0
                DiskCount = 1
            }
        }
    }
    
    # Get database information for a VM (pattern matching based approach)
    [hashtable] GetDatabaseInformation([object] $VM, [hashtable] $PerfMetrics) {
        try {
            # Initialize database info structure
            $databaseInfo = @{
                SQLServer = @{
                    Found = $false
                    Edition = ""
                    EditionCategory = ""
                    ProductVersion = ""
                    InstanceName = ""
                    DatabaseNames = @()
                    DetectionMethod = ""
                }
                PostgreSQL = @{
                    Found = $false
                    ProductVersion = ""
                    DatabaseNames = @()
                    DetectionMethod = ""
                }
                Oracle = @{
                    Found = $false
                    Edition = ""
                    ProductVersion = ""
                    InstanceName = ""
                    DatabaseNames = @()
                    DetectionMethod = ""
                }
                MySQL = @{
                    Found = $false
                    ProductVersion = ""
                    DatabaseNames = @()
                    DetectionMethod = ""
                }
                MariaDB = @{
                    Found = $false
                    ProductVersion = ""
                    DatabaseNames = @()
                    DetectionMethod = ""
                }
            }
            
            # Check if performance metrics contain SQL info (from enhanced detection)
            if ($PerfMetrics -and $PerfMetrics.PSObject.Properties.Name -contains 'SQLInfo') {
                $sqlInfo = $PerfMetrics.SQLInfo
                if ($sqlInfo.HasSQLServer) {
                    $databaseInfo.SQLServer.Found = $true
                    $databaseInfo.SQLServer.Edition = $sqlInfo.Edition
                    $databaseInfo.SQLServer.EditionCategory = $sqlInfo.EditionCategory
                    $databaseInfo.SQLServer.ProductVersion = $sqlInfo.ProductVersion
                    $databaseInfo.SQLServer.DetectionMethod = $sqlInfo.DetectionMethod
                    return $databaseInfo
                }
            }
            
            # Fallback to pattern matching
            $vmName = $VM.Name.ToLower()
            $osName = ""
            if ($VM.Guest.OSFullName) {
                $osName = $VM.Guest.OSFullName.ToLower()
            } elseif ($VM.ExtensionData.Config.GuestFullName) {
                $osName = $VM.ExtensionData.Config.GuestFullName.ToLower()
            }
            
            # SQL Server pattern matching
            if ($vmName -match "sql|database" -or $osName -match "sql") {
                $databaseInfo.SQLServer.Found = $true
                $databaseInfo.SQLServer.EditionCategory = "SQL Server Standard Edition"  # Default assumption
                $databaseInfo.SQLServer.DetectionMethod = "Pattern Matching"
            }
            
            # PostgreSQL pattern matching
            if ($vmName -match "postgres|pgsql" -or $osName -match "postgres") {
                $databaseInfo.PostgreSQL.Found = $true
                $databaseInfo.PostgreSQL.DetectionMethod = "Pattern Matching"
            }
            
            # Oracle pattern matching
            if ($vmName -match "oracle|ora" -or $osName -match "oracle") {
                $databaseInfo.Oracle.Found = $true
                $databaseInfo.Oracle.Edition = "Standard Edition"  # Default assumption
                $databaseInfo.Oracle.DetectionMethod = "Pattern Matching"
            }
            
            # MySQL pattern matching
            if ($vmName -match "mysql" -or $osName -match "mysql") {
                $databaseInfo.MySQL.Found = $true
                $databaseInfo.MySQL.DetectionMethod = "Pattern Matching"
            }
            
            # MariaDB pattern matching
            if ($vmName -match "mariadb|maria" -or $osName -match "mariadb") {
                $databaseInfo.MariaDB.Found = $true
                $databaseInfo.MariaDB.DetectionMethod = "Pattern Matching"
            }
            
            return $databaseInfo
            
        } catch {
            $this.Logger.WriteDebug("Failed to get database information for VM $($VM.Name): $_")
            # Return empty database info on error
            return @{
                SQLServer = @{ Found = $false }
                PostgreSQL = @{ Found = $false }
                Oracle = @{ Found = $false }
                MySQL = @{ Found = $false }
                MariaDB = @{ Found = $false }
            }
        }
    }
}