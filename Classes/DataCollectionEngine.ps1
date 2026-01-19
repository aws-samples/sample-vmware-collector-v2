#
# DataCollectionEngine.ps1 - VM discovery and inventory collection engine
#
# Implements comprehensive VM discovery with support for PoweredOnOnly filtering,
# VM list file processing with fuzzy matching, bulk operations, and FastMode optimization.
#

# Import required interfaces and models
if (Test-Path "$PSScriptRoot\Interfaces.ps1") {
    . "$PSScriptRoot\Interfaces.ps1"
}
if (Test-Path "$PSScriptRoot\VMDataModel.ps1") {
    . "$PSScriptRoot\VMDataModel.ps1"
}

class DataCollectionEngine : IDataCollector {
    # Configuration properties
    [IConnectionManager] $ConnectionManager
    [ILogger] $Logger
    [IProgressTracker] $ProgressTracker
    [object] $BulkOperationsEngine
    [object] $FastModeOptimizer
    [object] $MemoryManager
    [hashtable] $Configuration
    [hashtable] $InfrastructureCache
    
    # Collection settings
    [bool] $FastMode = $false
    [bool] $PoweredOnOnly = $false
    [bool] $SkipPerformanceData = $false
    [int] $MaxThreads = 10
    [int] $BatchSize = 100
    [string] $VMListFile = ""
    
    # Statistics tracking
    [hashtable] $CollectionStatistics
    [datetime] $CollectionStartTime
    [datetime] $CollectionEndTime
    
    # Constructor
    DataCollectionEngine([IConnectionManager] $connectionManager, [ILogger] $logger, [IProgressTracker] $progressTracker) {
        $this.ConnectionManager = $connectionManager
        $this.Logger = $logger
        $this.ProgressTracker = $progressTracker
        
        # Initialize BulkOperationsEngine if available
        try {
            $this.BulkOperationsEngine = [BulkOperationsEngine]::new($logger, $progressTracker)
        } catch {
            $this.Logger.WriteWarning("BulkOperationsEngine not available, using basic operations")
            $this.BulkOperationsEngine = $null
        }
        
        # Initialize FastModeOptimizer if available
        try {
            $this.FastModeOptimizer = [FastModeOptimizer]::new($logger)
        } catch {
            $this.Logger.WriteWarning("FastModeOptimizer not available, using basic optimization")
            $this.FastModeOptimizer = $null
        }
        
        # Import and initialize AdvancedMemoryManager
        . "$PSScriptRoot\AdvancedMemoryManager.ps1"
        $this.MemoryManager = [AdvancedMemoryManager]::new($logger)
        
        $this.InfrastructureCache = @{}
        $this.CollectionStatistics = @{
            TotalVMsDiscovered = 0
            TotalVMsProcessed = 0
            TotalAPICallsMade = 0
            TotalBulkOperations = 0
            CacheHits = 0
            CacheMisses = 0
            ProcessingTimeSeconds = 0
            MemoryPeakMB = 0
            TotalMemoryFreedMB = 0
            TotalCleanupOperations = 0
            MemoryWarningEvents = 0
            MemoryCriticalEvents = 0
            ErrorCount = 0
            WarningCount = 0
        }
        $this.Configuration = @{
            BulkViewProperties = @(
                'Name', 'Config.GuestId', 'Config.Version', 'Config.Template',
                'Config.Files.VmPathName', 'Config.Uuid', 'Config.InstanceUuid',
                'Config.Hardware.SystemInfo.Uuid', 'Config.Hardware.NumCPU',
                'Config.Hardware.MemoryMB', 'Config.CreateDate', 'Config.ModifiedDate',
                'Runtime.PowerState', 'Runtime.ConnectionState', 'Guest.GuestState',
                'Guest.HostName', 'Guest.IpAddress', 'Guest.GuestFullName',
                'Guest.ToolsStatus', 'Guest.ToolsVersion', 'Summary.Storage.Committed',
                'Summary.Storage.Uncommitted', 'Summary.Config.NumCpu',
                'Summary.Config.MemorySizeMB', 'Summary.Config.VmPathName',
                'Summary.Config.Template', 'Summary.Config.Annotation',
                'Summary.Runtime.Host', 'Summary.Runtime.PowerState',
                'ResourcePool', 'Parent'
            )
            FastModeProperties = @(
                'Name', 'Config.GuestId', 'Config.Version', 'Config.Hardware.NumCPU',
                'Config.Hardware.MemoryMB', 'Runtime.PowerState', 'Runtime.ConnectionState',
                'Guest.GuestState', 'Guest.HostName', 'Guest.IpAddress',
                'Summary.Storage.Committed', 'Summary.Config.NumCpu',
                'Summary.Config.MemorySizeMB', 'Summary.Runtime.Host'
            )
        }
    }
    
    # Main method to collect all VM data
    [array] CollectAllData([array] $VMList) {
        try {
            $this.CollectionStartTime = Get-Date
            $this.Logger.WriteInformation("Starting VM data collection with $($VMList.Count) VMs")
            
            # Start memory monitoring
            $this.MemoryManager.StartMemoryMonitoring()
            
            # Initialize progress tracking
            $this.ProgressTracker.StartProgress("Collecting VM Data", $VMList.Count)
            
            # Collect infrastructure data first for caching
            $this.CollectInfrastructureData()
            
            # Process VMs in batches for optimal performance
            $allVMData = @()
            $batches = $this.CreateVMBatches($VMList)
            
            $currentBatch = 0
            foreach ($batch in $batches) {
                $currentBatch++
                $this.Logger.WriteInformation("Processing batch $currentBatch of $($batches.Count) (VMs: $($batch.Count))")
                
                # Use bulk operations for better performance
                $batchData = $this.ProcessVMBatch($batch, $currentBatch, $batches.Count)
                $allVMData += $batchData
                
                # Memory management after each batch
                if ($this.MemoryManager.MemorySettings.CleanupOnBatchCompletion) {
                    $cleanupResult = $this.MemoryManager.PerformBatchCompletionCleanup()
                    if ($cleanupResult.MemoryFreedMB -gt 0) {
                        $this.Logger.WriteDebug("Batch $currentBatch cleanup: Freed $($cleanupResult.MemoryFreedMB) MB")
                    }
                }
                
                # Additional memory check every 5 batches
                if ($currentBatch % 5 -eq 0) {
                    $this.PerformMemoryCleanup()
                }
            }
            
            # Final memory cleanup
            $finalCleanup = $this.MemoryManager.PerformStandardCleanup()
            $this.Logger.WriteInformation("Final cleanup: Freed $($finalCleanup.MemoryFreedMB) MB")
            
            # Stop memory monitoring
            $this.MemoryManager.StopMemoryMonitoring()
            
            $this.CollectionEndTime = Get-Date
            $this.CollectionStatistics.ProcessingTimeSeconds = ($this.CollectionEndTime - $this.CollectionStartTime).TotalSeconds
            $this.CollectionStatistics.TotalVMsProcessed = $allVMData.Count
            
            # Update memory statistics
            $memoryReport = $this.MemoryManager.GetMemoryReport()
            $this.CollectionStatistics.MemoryPeakMB = $memoryReport.Statistics.PeakMemoryMB
            $this.CollectionStatistics.TotalMemoryFreedMB = $memoryReport.Statistics.TotalMemoryFreedMB
            $this.CollectionStatistics.TotalCleanupOperations = $memoryReport.Statistics.TotalCleanupOperations
            
            $this.ProgressTracker.CompleteProgress()
            $this.Logger.WriteInformation("VM data collection completed. Processed $($allVMData.Count) VMs in $($this.CollectionStatistics.ProcessingTimeSeconds) seconds, Peak Memory: $($memoryReport.Statistics.PeakMemoryMB) MB")
            
            return $allVMData
            
        } catch {
            $this.CollectionStatistics.ErrorCount++
            $this.Logger.WriteError("Failed to collect VM data", $_.Exception)
            
            # Ensure memory monitoring is stopped on error
            try {
                $this.MemoryManager.StopMemoryMonitoring()
            } catch {
                # Ignore cleanup errors
            }
            
            throw
        }
    }
    
    # Get VM list with filtering and file processing
    [array] GetVMList() {
        try {
            $this.Logger.WriteInformation("Discovering VMs...")
            
            # Ensure connection is active
            $this.ConnectionManager.EnsureConnection()
            
            $vmList = @()
            
            # If VM list file is specified, process it
            if (-not [string]::IsNullOrEmpty($this.VMListFile)) {
                $vmList = $this.GetVMsFromFile($this.VMListFile)
                $this.Logger.WriteInformation("Loaded $($vmList.Count) VMs from file: $($this.VMListFile)")
            } else {
                # Get all VMs from vCenter
                $this.Logger.WriteInformation("Discovering all VMs from vCenter...")
                $vmList = Get-VM
                $this.CollectionStatistics.TotalAPICallsMade++
                $this.Logger.WriteInformation("Discovered $($vmList.Count) VMs from vCenter")
            }
            
            # Apply PoweredOnOnly filter if specified
            if ($this.PoweredOnOnly) {
                $originalCount = $vmList.Count
                $vmList = $vmList | Where-Object { $_.PowerState -eq 'PoweredOn' }
                $this.Logger.WriteInformation("Filtered to $($vmList.Count) powered-on VMs (was $originalCount)")
            }
            
            $this.CollectionStatistics.TotalVMsDiscovered = $vmList.Count
            return $vmList
            
        } catch {
            $this.CollectionStatistics.ErrorCount++
            $this.Logger.WriteError("Failed to get VM list", $_.Exception)
            throw
        }
    }
    
    # Process VM list from file with fuzzy matching
    [array] GetVMsFromFile([string] $FilePath) {
        try {
            $this.Logger.WriteInformation("Processing VM list file: $FilePath")
            
            # Import and initialize VMListProcessor
            . "$PSScriptRoot\VMListProcessor.ps1"
            $vmListProcessor = [VMListProcessor]::new($this.Logger)
            
            # Get all VMs from vCenter for matching
            $allVMs = Get-VM
            $this.CollectionStatistics.TotalAPICallsMade++
            
            # Process VM list file with advanced fuzzy matching
            $processingResult = $vmListProcessor.ProcessVMListFile($FilePath, $allVMs)
            
            # Update collection statistics
            $processingStats = $processingResult.ProcessingStatistics
            $this.CollectionStatistics.WarningCount += $processingStats.NotFound
            
            $this.Logger.WriteInformation("VM list processing completed: $($processingStats.SuccessfullyMatched) matched, $($processingStats.NotFound) not found (Success rate: $($processingStats.SuccessRate)%)")
            
            return $processingResult.MatchedVMs
            
        } catch {
            $this.CollectionStatistics.ErrorCount++
            $this.Logger.WriteError("Failed to process VM list file: $FilePath", $_.Exception)
            throw
        }
    }
    
    # DEPRECATED: Read VM names from file (supports CSV and TXT)
    # This method is replaced by VMListProcessor class for enhanced fuzzy matching
    [array] ReadVMNamesFromFile([string] $FilePath) {
        $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
        $vmNames = @()
        
        try {
            if ($extension -eq '.csv') {
                # Try to detect CSV format and column
                $csvData = Import-Csv $FilePath
                $headers = $csvData[0].PSObject.Properties.Name
                
                # Look for common VM name columns
                $vmColumnName = $null
                $possibleColumns = @('VM Name', 'Server Name', 'Virtual Machine', 'Name', 'VM', 'Server')
                
                foreach ($column in $possibleColumns) {
                    if ($headers -contains $column) {
                        $vmColumnName = $column
                        break
                    }
                }
                
                # If no standard column found, use first column
                if (-not $vmColumnName) {
                    $vmColumnName = $headers[0]
                    $this.Logger.WriteWarning("No standard VM name column found, using first column: $vmColumnName")
                }
                
                $vmNames = $csvData | ForEach-Object { $_.$vmColumnName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                $this.Logger.WriteInformation("CSV format detected, using column: $vmColumnName")
                
            } else {
                # Treat as text file with one VM name per line
                $vmNames = Get-Content $FilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
                $this.Logger.WriteInformation("Text format detected, reading one VM name per line")
            }
            
            # Remove duplicates and sanitize
            $vmNames = $vmNames | Sort-Object -Unique | ForEach-Object { $this.SanitizeVMName($_) }
            
            return $vmNames
            
        } catch {
            $this.Logger.WriteError("Failed to read VM names from file: $FilePath", $_.Exception)
            throw
        }
    }
    
    # DEPRECATED: Fuzzy matching for VM names
    # This method is replaced by VMListProcessor class for enhanced fuzzy matching
    [object] FindVMWithFuzzyMatching([string] $targetName, [array] $allVMs) {
        # First try exact match
        $exactMatch = $allVMs | Where-Object { $_.Name -eq $targetName }
        if ($exactMatch) {
            return $exactMatch
        }
        
        # Try case-insensitive match
        $caseInsensitiveMatch = $allVMs | Where-Object { $_.Name -ieq $targetName }
        if ($caseInsensitiveMatch) {
            return $caseInsensitiveMatch
        }
        
        # Try partial matches (contains)
        $partialMatches = $allVMs | Where-Object { $_.Name -like "*$targetName*" -or $targetName -like "*$($_.Name)*" }
        if ($partialMatches.Count -eq 1) {
            return $partialMatches[0]
        }
        
        # Try removing common suffixes/prefixes and special characters
        $cleanTargetName = $this.CleanVMNameForMatching($targetName)
        $cleanMatches = $allVMs | Where-Object { 
            $cleanVMName = $this.CleanVMNameForMatching($_.Name)
            $cleanVMName -eq $cleanTargetName
        }
        if ($cleanMatches.Count -eq 1) {
            return $cleanMatches[0]
        }
        
        # If multiple partial matches, log them for manual review
        if ($partialMatches.Count -gt 1) {
            $matchNames = $partialMatches | ForEach-Object { $_.Name }
            $this.Logger.WriteWarning("Multiple partial matches found for '$targetName': $($matchNames -join ', ')")
        }
        
        return $null
    }
    
    # Clean VM name for better matching
    [string] CleanVMNameForMatching([string] $vmName) {
        # Remove common suffixes, prefixes, and special characters
        $cleaned = $vmName -replace '[-_\.]', '' -replace '\s+', '' -replace '(test|prod|dev|staging)$', '' -replace '^(vm|server)', ''
        return $cleaned.ToLower()
    }
    
    # Sanitize VM name input
    [string] SanitizeVMName([string] $vmName) {
        # Remove invalid characters and trim whitespace
        return $vmName.Trim() -replace '[^\w\-\._\s]', ''
    }
    
    # Generate unmatched VMs report
    [void] GenerateUnmatchedVMsReport([array] $unmatchedNames, [string] $originalFilePath) {
        try {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $reportPath = Join-Path (Split-Path $originalFilePath) "Not_Found_VMs_Report_$timestamp.csv"
            
            $reportData = $unmatchedNames | ForEach-Object {
                [PSCustomObject]@{
                    'VM Name' = $_
                    'Status' = 'Not Found'
                    'Timestamp' = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
            }
            
            $reportData | Export-Csv -Path $reportPath -NoTypeInformation
            $this.Logger.WriteInformation("Generated unmatched VMs report: $reportPath")
            
        } catch {
            $this.Logger.WriteError("Failed to generate unmatched VMs report", $_.Exception)
        }
    }
    
    # Generate VM list processing summary
    [void] GenerateVMListProcessingSummary([string] $filePath, [int] $totalInFile, [int] $matched, [int] $unmatched) {
        $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
        $format = if ($extension -eq '.csv') { 'CSV' } else { 'Text' }
        $successRate = if ($totalInFile -gt 0) { [Math]::Round(($matched / $totalInFile) * 100, 2) } else { 0 }
        
        $summary = @"
VM List Processing Summary:
- File: $filePath
- Format: $format
- Total VMs in file: $totalInFile
- Successfully matched: $matched
- Not found: $unmatched
- Success rate: $successRate%
"@
        
        $this.Logger.WriteInformation($summary)
    }
    
    # Create VM batches for processing
    [array] CreateVMBatches([array] $vmList) {
        $batches = @()
        $effectiveBatchSize = $this.BatchSize
        
        for ($i = 0; $i -lt $vmList.Count; $i += $effectiveBatchSize) {
            $endIndex = [Math]::Min($i + $batchSize - 1, $vmList.Count - 1)
            $batch = $vmList[$i..$endIndex]
            $batches += ,$batch
        }
        
        $this.Logger.WriteInformation("Created $($batches.Count) batches with batch size $batchSize")
        return $batches
    }
    
    # Process a batch of VMs
    [array] ProcessVMBatch([array] $vmBatch, [int] $batchNumber, [int] $totalBatches) {
        $batchData = @()
        
        try {
            # Use bulk Get-View operation for better performance
            $vmViews = $this.GetVMViewsBulk($vmBatch)
            
            # Process each VM in the batch
            for ($i = 0; $i -lt $vmBatch.Count; $i++) {
                $vm = $vmBatch[$i]
                $vmView = $vmViews[$i]
                
                try {
                    # Update progress
                    $overallProgress = (($batchNumber - 1) * $this.BatchSize) + $i + 1
                    $this.ProgressTracker.UpdateProgress($overallProgress, "Processing VM: $($vm.Name)")
                    
                    # Collect VM data
                    $vmData = $this.CollectVMData($vm, $vmView)
                    if ($vmData) {
                        $batchData += $vmData
                    }
                    
                } catch {
                    $this.CollectionStatistics.ErrorCount++
                    $this.Logger.WriteError("Failed to process VM: $($vm.Name)", $_.Exception)
                }
            }
            
        } catch {
            $this.CollectionStatistics.ErrorCount++
            $this.Logger.WriteError("Failed to process VM batch $batchNumber", $_.Exception)
        }
        
        return $batchData
    }
    
    # Get VM views in bulk for better performance using BulkOperationsEngine
    [array] GetVMViewsBulk([array] $vmBatch) {
        try {
            # Determine property set based on mode
            $propertySet = if ($this.FastMode) { 'Fast' } else { 'Full' }
            
            # Configure bulk operations
            $bulkOptions = @{
                BatchSize = $this.BatchSize
                OptimizationSettings = @{
                    EnablePropertyFiltering = $true
                    EnableBatchOptimization = $true
                    EnableMemoryManagement = $true
                }
            }
            
            # Use BulkOperationsEngine for optimized collection
            $vmViews = $this.BulkOperationsEngine.CollectVMDataBulk($vmBatch, $propertySet, $bulkOptions)
            
            # Update statistics from bulk operations
            $bulkMetrics = $this.BulkOperationsEngine.GetPerformanceMetrics()
            $this.CollectionStatistics.TotalAPICallsMade += $bulkMetrics.TotalAPICallsMade
            $this.CollectionStatistics.TotalBulkOperations += $bulkMetrics.TotalBulkOperations
            
            return $vmViews
            
        } catch {
            $this.Logger.WriteError("Failed to get VM views in bulk", $_.Exception)
            throw
        }
    }
    
    # Collect data for a single VM
    [VMDataModel] CollectVMData([object] $vm, [object] $vmView = $null) {
        try {
            # Get VM view if not provided
            if (-not $vmView) {
                $properties = if ($this.FastMode) { $this.Configuration.FastModeProperties } else { $this.Configuration.BulkViewProperties }
                $vmView = $vm | Get-View -Property $properties
                $this.CollectionStatistics.TotalAPICallsMade++
            }
            
            # Create VM data model
            $vmData = [VMDataModel]::new()
            
            # Populate basic information
            $this.PopulateBasicInformation($vmData, $vm, $vmView)
            
            # Populate hardware configuration
            $this.PopulateHardwareConfiguration($vmData, $vm, $vmView)
            
            # Populate infrastructure details (with caching)
            $this.PopulateInfrastructureDetails($vmData, $vm, $vmView)
            
            # Populate VM configuration
            $this.PopulateVMConfiguration($vmData, $vm, $vmView)
            
            # Populate network information (skip detailed in FastMode)
            if (-not $this.FastMode) {
                $this.PopulateNetworkInformation($vmData, $vm, $vmView)
                $this.PopulateStorageInformation($vmData, $vm, $vmView)
                $this.PopulateResourceManagement($vmData, $vm, $vmView)
                $this.PopulateSnapshotInformation($vmData, $vm, $vmView)
            } else {
                # Apply FastMode optimizations
                $vmDataHash = $vmData.ToHashtable()
                $optimizedData = $this.FastModeOptimizer.ApplyFastModeOptimizations($vm, $vmView, $vmDataHash)
                
                # Update VM data with optimized values
                foreach ($key in $optimizedData.Keys) {
                    if ($vmData.PSObject.Properties.Name -contains $key) {
                        $vmData.$key = $optimizedData[$key]
                    }
                }
            }
            
            # Populate metadata
            $this.PopulateMetadata($vmData, $vm, $vmView)
            
            # Set collection timestamp
            $vmData.CollectionDate = Get-Date
            
            # Validate data
            if (-not $vmData.ValidateData()) {
                $this.Logger.WriteWarning("VM data validation failed for: $($vm.Name)")
                $this.CollectionStatistics.WarningCount++
            }
            
            return $vmData
            
        } catch {
            $this.CollectionStatistics.ErrorCount++
            $this.Logger.WriteError("Failed to collect data for VM: $($vm.Name)", $_.Exception)
            return $null
        }
    }
    
    # Populate basic VM information
    [void] PopulateBasicInformation([VMDataModel] $vmData, [object] $vm, [object] $vmView) {
        $vmData.Name = $vm.Name
        $vmData.PowerState = $vm.PowerState.ToString()
        $vmData.ConnectionState = $vmView.Runtime.ConnectionState.ToString()
        $vmData.GuestState = $vmView.Guest.GuestState.ToString()
        $vmData.GuestId = $vmView.Config.GuestId
        
        # Guest information (may be null if tools not running)
        if ($vm.Guest) {
            $vmData.DNSName = $vm.Guest.HostName
            $vmData.OperatingSystem = $vm.Guest.OSFullName
            if ($vm.Guest.IPAddress -and $vm.Guest.IPAddress.Count -gt 0) {
                $vmData.IPAddress = $vm.Guest.IPAddress[0]
            }
        }
        
        # Derive OS version from GuestId if OS name not available
        if ([string]::IsNullOrEmpty($vmData.OperatingSystem)) {
            $vmData.OSVersion = $this.DeriveOSVersionFromGuestId($vmView.Config.GuestId)
        } else {
            $vmData.OSVersion = $this.ExtractOSVersionFromName($vmData.OperatingSystem)
        }
    }
    
    # Populate hardware configuration
    [void] PopulateHardwareConfiguration([VMDataModel] $vmData, [object] $vm, [object] $vmView) {
        $vmData.NumCPUs = $vm.NumCpu
        $vmData.MemoryMB = $vm.MemoryMB
        $vmData.HardwareVersion = $vmView.Config.Version
        
        # Calculate total storage
        if ($vm.UsedSpaceGB) {
            $vmData.TotalStorageGB = $vm.UsedSpaceGB
        } elseif ($vm.ProvisionedSpaceGB) {
            $vmData.TotalStorageGB = $vm.ProvisionedSpaceGB
        }
        
        # Storage committed/uncommitted
        if ($vmView.Summary.Storage) {
            $vmData.StorageCommittedGB = [Math]::Round($vmView.Summary.Storage.Committed / 1GB, 2)
            if ($vmView.Summary.Storage.Uncommitted) {
                $vmData.StorageUncommittedGB = [Math]::Round($vmView.Summary.Storage.Uncommitted / 1GB, 2)
            }
        }
        
        # Calculate uncommitted storage
        $vmData.CalculateStorageUncommitted()
    }
    
    # Populate infrastructure details with caching
    [void] PopulateInfrastructureDetails([VMDataModel] $vmData, [object] $vm, [object] $vmView) {
        # Host information
        if ($vm.VMHost) {
            $vmData.HostName = $vm.VMHost.Name
            
            # Cluster information (with caching)
            $clusterName = $this.GetCachedClusterName($vm.VMHost.Name)
            if ($clusterName) {
                $vmData.ClusterName = $clusterName
                $this.CollectionStatistics.CacheHits++
            } else {
                if ($vm.VMHost.Parent -and $vm.VMHost.Parent.GetType().Name -eq 'ClusterImpl') {
                    $vmData.ClusterName = $vm.VMHost.Parent.Name
                    $this.InfrastructureCache["Cluster_$($vm.VMHost.Name)"] = $vm.VMHost.Parent.Name
                }
                $this.CollectionStatistics.CacheMisses++
            }
        }
        
        # Datacenter information (with caching)
        $datacenterName = $this.GetCachedDatacenterName($vm.Name)
        if ($datacenterName) {
            $vmData.DatacenterName = $datacenterName
            $this.CollectionStatistics.CacheHits++
        } else {
            $datacenter = $this.GetVMDatacenter($vm)
            if ($datacenter) {
                $vmData.DatacenterName = $datacenter.Name
                $this.InfrastructureCache["Datacenter_$($vm.Name)"] = $datacenter.Name
            }
            $this.CollectionStatistics.CacheMisses++
        }
        
        # Resource pool
        if ($vm.ResourcePool) {
            $vmData.ResourcePoolName = $vm.ResourcePool.Name
        }
        
        # Folder
        if ($vm.Folder) {
            $vmData.FolderName = $vm.Folder.Name
        }
        
        # Primary datastore and network (simplified in FastMode)
        if (-not $this.FastMode) {
            $vmData.DatastoreName = $this.GetPrimaryDatastore($vm)
            $vmData.NetworkName = $this.GetPrimaryNetwork($vm)
        }
    }
    
    # Perform memory cleanup during collection
    [void] PerformMemoryCleanup() {
        try {
            $this.Logger.WriteDebug("Performing periodic memory cleanup")
            
            # Get current memory status
            $currentMemory = $this.MemoryManager.GetCurrentMemoryUsage()
            
            # Perform cleanup based on memory usage
            if ($currentMemory.WorkingSetMB -gt ($this.MemoryManager.MemorySettings.MaxMemoryMB * 0.7)) {
                $cleanupResult = $this.MemoryManager.PerformStandardCleanup()
                $this.Logger.WriteInformation("Memory cleanup: Freed $($cleanupResult.MemoryFreedMB) MB (was at $($currentMemory.WorkingSetMB) MB)")
                
                # Update statistics
                $this.CollectionStatistics.TotalMemoryFreedMB += $cleanupResult.MemoryFreedMB
                $this.CollectionStatistics.TotalCleanupOperations++
            }
            
            # Clear local caches
            if ($this.InfrastructureCache.Count -gt 1000) {
                $cacheSize = $this.InfrastructureCache.Count
                $this.InfrastructureCache.Clear()
                $this.Logger.WriteDebug("Cleared infrastructure cache ($cacheSize entries)")
            }
            
        } catch {
            $this.Logger.WriteError("Memory cleanup failed", $_.Exception)
        }
    }
    
    # Configure memory management settings
    [void] ConfigureMemoryManagement([hashtable] $memorySettings) {
        try {
            $this.MemoryManager.ConfigureMemorySettings($memorySettings)
            $this.Logger.WriteInformation("Memory management configured with settings: $($memorySettings.Keys -join ', ')")
        } catch {
            $this.Logger.WriteError("Failed to configure memory management", $_.Exception)
        }
    }
    
    # Get memory management report
    [hashtable] GetMemoryReport() {
        try {
            return $this.MemoryManager.GetMemoryReport()
        } catch {
            $this.Logger.WriteError("Failed to get memory report", $_.Exception)
            return @{
                Error = "Failed to get memory report: $($_.Exception.Message)"
            }
        }
    }
    
    # Additional helper methods for data population...
    [void] PopulateVMConfiguration([VMDataModel] $vmData, [object] $vm, [object] $vmView) {
        $vmData.VMwareToolsStatus = $vmView.Guest.ToolsStatus.ToString()
        $vmData.VMwareToolsVersion = $vmView.Guest.ToolsVersion
        $vmData.VMPathName = $vmView.Config.Files.VmPathName
        $vmData.VMConfigFile = $vmView.Config.Files.VmPathName
        $vmData.TemplateFlag = $vmView.Config.Template
        
        # VM IDs
        $vmData.VMId = $vm.Id
        $vmData.VMUuid = $vmView.Config.Uuid
        $vmData.InstanceUuid = $vmView.Config.InstanceUuid
        if ($vmView.Config.Hardware.SystemInfo) {
            $vmData.BiosUuid = $vmView.Config.Hardware.SystemInfo.Uuid
        }
    }
    
    [void] PopulateNetworkInformation([VMDataModel] $vmData, [object] $vm, [object] $vmView) {
        # Get network adapters (limit to 4 for data model)
        $networkAdapters = $vm.NetworkAdapters
        if ($networkAdapters) {
            if ($networkAdapters.Count -ge 1) { $vmData.NetworkAdapter1 = $networkAdapters[0].NetworkName }
            if ($networkAdapters.Count -ge 2) { $vmData.NetworkAdapter2 = $networkAdapters[1].NetworkName }
            if ($networkAdapters.Count -ge 3) { $vmData.NetworkAdapter3 = $networkAdapters[2].NetworkName }
            if ($networkAdapters.Count -ge 4) { $vmData.NetworkAdapter4 = $networkAdapters[3].NetworkName }
            
            # Primary MAC address
            $vmData.MACAddress = $networkAdapters[0].MacAddress
        }
    }
    
    [void] PopulateStorageInformation([VMDataModel] $vmData, [object] $vm, [object] $vmView) {
        # Storage format and disk mode (simplified)
        $vmData.StorageFormat = "VMDK"  # Default for VMware
        $vmData.DiskMode = "persistent"  # Default mode
        
        # Could be enhanced to detect actual disk modes from VM configuration
    }
    
    [void] PopulateResourceManagement([VMDataModel] $vmData, [object] $vm, [object] $vmView) {
        # CPU and Memory resource settings
        if ($vmView.Config.CpuAllocation) {
            $vmData.CPUReservation = $vmView.Config.CpuAllocation.Reservation
            $vmData.CPULimit = $vmView.Config.CpuAllocation.Limit
            $vmData.CPUShares = $vmView.Config.CpuAllocation.Shares.Level.ToString()
        }
        
        if ($vmView.Config.MemoryAllocation) {
            $vmData.MemoryReservation = $vmView.Config.MemoryAllocation.Reservation
            $vmData.MemoryLimit = $vmView.Config.MemoryAllocation.Limit
            $vmData.MemoryShares = $vmView.Config.MemoryAllocation.Shares.Level.ToString()
        }
    }
    
    [void] PopulateSnapshotInformation([VMDataModel] $vmData, [object] $vm, [object] $vmView) {
        # Snapshot information
        if ($vm.Snapshots) {
            $vmData.SnapshotCount = $vm.Snapshots.Count
            $vmData.SnapshotSizeGB = [Math]::Round(($vm.Snapshots | Measure-Object -Property SizeGB -Sum).Sum, 2)
            if ($vm.Snapshots.Count -gt 0) {
                $latestSnapshot = $vm.Snapshots | Sort-Object Created -Descending | Select-Object -First 1
                $vmData.SnapshotCreated = $latestSnapshot.Created.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
    
    [void] PopulateMetadata([VMDataModel] $vmData, [object] $vm, [object] $vmView) {
        # Creation and modification dates
        if ($vmView.Config.CreateDate) {
            $vmData.CreationDate = $vmView.Config.CreateDate
        }
        if ($vmView.Config.ModifiedDate) {
            $vmData.LastModified = $vmView.Config.ModifiedDate
        }
        
        # Annotation/Notes
        if ($vm.Notes) {
            $vmData.Annotation = $vm.Notes
            $vmData.Notes = $vm.Notes
        }
        
        # Custom fields and derived information
        $vmData.Environment = $this.DeriveEnvironmentFromVM($vm)
        $vmData.Application = $this.DeriveApplicationFromVM($vm)
        $vmData.Owner = $this.DeriveOwnerFromVM($vm)
    }
    
    # Helper methods for infrastructure caching and data derivation
    [string] GetCachedClusterName([string] $hostName) {
        return $this.InfrastructureCache["Cluster_$hostName"]
    }
    
    [string] GetCachedDatacenterName([string] $vmName) {
        return $this.InfrastructureCache["Datacenter_$vmName"]
    }
    
    [object] GetVMDatacenter([object] $vm) {
        try {
            # Navigate up the inventory hierarchy to find datacenter
            $parent = $vm.Folder
            while ($parent -and $parent.GetType().Name -ne 'DatacenterImpl') {
                $parent = $parent.Parent
            }
            return $parent
        } catch {
            return $null
        }
    }
    
    [string] GetPrimaryDatastore([object] $vm) {
        if ($vm.DatastoreIdList -and $vm.DatastoreIdList.Count -gt 0) {
            $datastore = Get-Datastore -Id $vm.DatastoreIdList[0]
            $this.CollectionStatistics.TotalAPICallsMade++
            return $datastore.Name
        }
        return ""
    }
    
    [string] GetPrimaryNetwork([object] $vm) {
        $networkAdapters = $vm.NetworkAdapters
        if ($networkAdapters -and $networkAdapters.Count -gt 0) {
            return $networkAdapters[0].NetworkName
        }
        return ""
    }
    
    # Data derivation methods
    [string] DeriveOSVersionFromGuestId([string] $guestId) {
        # Map common guest IDs to OS versions
        $osMap = @{
            'windows9Server64Guest' = 'Windows Server 2019'
            'windows2019srv_64Guest' = 'Windows Server 2019'
            'windows2016srvNext_64Guest' = 'Windows Server 2016'
            'ubuntu64Guest' = 'Ubuntu Linux'
            'rhel8_64Guest' = 'Red Hat Enterprise Linux 8'
            'centos8_64Guest' = 'CentOS 8'
        }
        
        return $osMap[$guestId] ?? $guestId
    }
    
    [string] ExtractOSVersionFromName([string] $osName) {
        # Extract version information from OS full name
        if ($osName -match 'Windows Server (\d{4})') {
            return "Windows Server $($matches[1])"
        } elseif ($osName -match 'Ubuntu (\d+\.\d+)') {
            return "Ubuntu $($matches[1])"
        } elseif ($osName -match 'Red Hat Enterprise Linux (\d+)') {
            return "RHEL $($matches[1])"
        }
        return $osName
    }
    
    [string] DeriveEnvironmentFromVM([object] $vm) {
        # Derive environment from VM name or folder structure
        $vmName = $vm.Name.ToLower()
        if ($vmName -match '(prod|production)') { return 'Production' }
        elseif ($vmName -match '(test|testing)') { return 'Test' }
        elseif ($vmName -match '(dev|development)') { return 'Development' }
        elseif ($vmName -match '(stage|staging)') { return 'Staging' }
        else { return 'Unknown' }
    }
    
    [string] DeriveApplicationFromVM([object] $vm) {
        # Derive application from VM name patterns
        $vmName = $vm.Name.ToLower()
        if ($vmName -match '(web|iis|apache)') { return 'Web Server' }
        elseif ($vmName -match '(sql|database|db)') { return 'Database' }
        elseif ($vmName -match '(app|application)') { return 'Application Server' }
        elseif ($vmName -match '(dc|domain)') { return 'Domain Controller' }
        else { return 'Unknown' }
    }
    
    [string] DeriveOwnerFromVM([object] $vm) {
        # Could be enhanced to read from custom attributes
        return 'Unknown'
    }
    
    # Collect infrastructure data for caching
    [hashtable] CollectInfrastructureData() {
        try {
            $this.Logger.WriteInformation("Collecting infrastructure data for caching...")
            
            # Get all hosts and their clusters
            $hosts = Get-VMHost
            $this.CollectionStatistics.TotalAPICallsMade++
            
            foreach ($host in $hosts) {
                if ($host.Parent -and $host.Parent.GetType().Name -eq 'ClusterImpl') {
                    $this.InfrastructureCache["Cluster_$($host.Name)"] = $host.Parent.Name
                }
            }
            
            # Get all datacenters
            $datacenters = Get-Datacenter
            $this.CollectionStatistics.TotalAPICallsMade++
            
            $infrastructureData = @{
                Hosts = $hosts
                Datacenters = $datacenters
                CacheEntries = $this.InfrastructureCache.Count
            }
            
            $this.Logger.WriteInformation("Infrastructure data cached: $($hosts.Count) hosts, $($datacenters.Count) datacenters")
            
            return $infrastructureData
            
        } catch {
            $this.Logger.WriteError("Failed to collect infrastructure data", $_.Exception)
            return @{}
        }
    }
    
    # Memory management
    [void] PerformMemoryCleanup() {
        try {
            $beforeMB = [Math]::Round((Get-Process -Id $global:PID).WorkingSet64 / 1MB, 2)
            
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $afterMB = [Math]::Round((Get-Process -Id $global:PID).WorkingSet64 / 1MB, 2)
            $this.CollectionStatistics.MemoryPeakMB = [Math]::Max($this.CollectionStatistics.MemoryPeakMB, $beforeMB)
            
            $this.Logger.WriteDebug("Memory cleanup: $beforeMB MB -> $afterMB MB")
            
        } catch {
            $this.Logger.WriteWarning("Memory cleanup failed: $($_.Exception.Message)")
        }
    }
    
    # Get collection statistics
    [hashtable] GetCollectionStatistics() {
        return $this.CollectionStatistics
    }
    
    # Configure collection settings
    [void] ConfigureCollection([hashtable] $settings) {
        if ($settings.ContainsKey('FastMode')) { 
            $this.FastMode = $settings.FastMode 
            if ($this.FastMode) {
                $vmCount = if ($settings.ContainsKey('EstimatedVMCount')) { $settings.EstimatedVMCount } else { 0 }
                $this.FastModeOptimizer.EnableFastMode('FastMode', $vmCount)
            }
        }
        if ($settings.ContainsKey('PoweredOnOnly')) { $this.PoweredOnOnly = $settings.PoweredOnOnly }
        if ($settings.ContainsKey('SkipPerformanceData')) { $this.SkipPerformanceData = $settings.SkipPerformanceData }
        if ($settings.ContainsKey('MaxThreads')) { $this.MaxThreads = $settings.MaxThreads }
        if ($settings.ContainsKey('BatchSize')) { $this.BatchSize = $settings.BatchSize }
        if ($settings.ContainsKey('VMListFile')) { $this.VMListFile = $settings.VMListFile }
        
        $this.Logger.WriteInformation("Collection configured: FastMode=$($this.FastMode), PoweredOnOnly=$($this.PoweredOnOnly), BatchSize=$($this.BatchSize)")
    }
}