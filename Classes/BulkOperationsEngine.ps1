#
# BulkOperationsEngine.ps1 - Unified bulk operations and FastMode optimization engine
#
# Consolidates BulkOperationsEngine and FastModeOptimizer into a single class that handles
# both optimized bulk data collection operations and FastMode optimization for large environments.
#
# Consolidated from:
# - BulkOperationsEngine.ps1 - Bulk Get-View operations with property filtering and batch processing
# - FastModeOptimizer.ps1 - FastMode optimization that skips detailed collection for speed
#

# Import required interfaces
if (Test-Path "$PSScriptRoot\Interfaces.ps1") {
    . "$PSScriptRoot\Interfaces.ps1"
}

class BulkOperationsEngine {
    # Bulk operations properties (from original BulkOperationsEngine)
    [ILogger] $Logger
    [IProgressTracker] $ProgressTracker
    [int] $BatchSize = 100
    [int] $MaxConcurrentOperations = 10
    [hashtable] $OptimizationSettings
    
    # Performance tracking
    [hashtable] $PerformanceMetrics
    [datetime] $OperationStartTime
    [int] $TotalOperationsCompleted = 0
    
    # FastMode optimization properties (from FastModeOptimizer)
    [bool] $FastModeEnabled = $false
    [hashtable] $FastModeSettings
    [hashtable] $SkippedOperations
    [hashtable] $OptimizationRules
    [datetime] $OptimizationStartTime
    [int] $TotalVMsProcessed = 0
    [double] $TimeWithoutFastMode = 0.0
    [double] $TimeWithFastMode = 0.0
    
    # Property sets for different collection modes (unified)
    [hashtable] $PropertySets
    
    # Constructor
    BulkOperationsEngine([ILogger] $logger, [IProgressTracker] $progressTracker) {
        $this.Logger = $logger
        $this.ProgressTracker = $progressTracker
        $this.FastModeEnabled = $false
        
        # Initialize all components
        $this.InitializePropertySets()
        $this.InitializePerformanceMetrics()
        $this.InitializeOptimizationSettings()
        $this.InitializeFastModeComponents()
        
        $this.Logger.WriteInformation("BulkOperationsEngine initialized with FastMode optimization capabilities")
    }
    
    # Initialize property sets for different collection modes (unified from both classes)
    [void] InitializePropertySets() {
        $this.PropertySets = @{
            # Full property set for comprehensive collection (from BulkOperationsEngine)
            Full = @(
                'Name', 'Config.GuestId', 'Config.Version', 'Config.Template',
                'Config.Files.VmPathName', 'Config.Uuid', 'Config.InstanceUuid',
                'Config.Hardware.SystemInfo.Uuid', 'Config.Hardware.NumCPU',
                'Config.Hardware.MemoryMB', 'Config.CreateDate', 'Config.ModifiedDate',
                'Config.Annotation', 'Config.CpuAllocation', 'Config.MemoryAllocation',
                'Config.Hardware.Device', 'Config.ExtraConfig',
                'Runtime.PowerState', 'Runtime.ConnectionState', 'Runtime.Host',
                'Guest.GuestState', 'Guest.HostName', 'Guest.IpAddress', 
                'Guest.GuestFullName', 'Guest.ToolsStatus', 'Guest.ToolsVersion',
                'Guest.Net', 'Guest.Disk',
                'Summary.Storage.Committed', 'Summary.Storage.Uncommitted',
                'Summary.Config.NumCpu', 'Summary.Config.MemorySizeMB',
                'Summary.Config.VmPathName', 'Summary.Config.Template',
                'Summary.Config.Annotation', 'Summary.Runtime.Host',
                'Summary.Runtime.PowerState', 'Summary.QuickStats',
                'ResourcePool', 'Parent', 'Datastore', 'Network',
                'Snapshot', 'LayoutEx.File'
            )
            
            # Standard property set (alias for Full, from FastModeOptimizer)
            Standard = @(
                'Name', 'Config.GuestId', 'Config.Version', 'Config.Template',
                'Config.Files.VmPathName', 'Config.Uuid', 'Config.InstanceUuid',
                'Config.Hardware.SystemInfo.Uuid', 'Config.Hardware.NumCPU',
                'Config.Hardware.MemoryMB', 'Config.CreateDate', 'Config.ModifiedDate',
                'Config.Annotation', 'Config.CpuAllocation', 'Config.MemoryAllocation',
                'Config.Hardware.Device', 'Config.ExtraConfig',
                'Runtime.PowerState', 'Runtime.ConnectionState', 'Runtime.Host',
                'Guest.GuestState', 'Guest.HostName', 'Guest.IpAddress', 
                'Guest.GuestFullName', 'Guest.ToolsStatus', 'Guest.ToolsVersion',
                'Guest.Net', 'Guest.Disk',
                'Summary.Storage.Committed', 'Summary.Storage.Uncommitted',
                'Summary.Config.NumCpu', 'Summary.Config.MemorySizeMB',
                'Summary.Config.VmPathName', 'Summary.Config.Template',
                'Summary.Config.Annotation', 'Summary.Runtime.Host',
                'Summary.Runtime.PowerState', 'Summary.QuickStats',
                'ResourcePool', 'Parent', 'Datastore', 'Network',
                'Snapshot', 'LayoutEx.File'
            )
            
            # Fast mode property set for speed optimization (60-70% reduction)
            Fast = @(
                'Name', 'Config.GuestId', 'Config.Version', 'Config.Hardware.NumCPU',
                'Config.Hardware.MemoryMB', 'Config.Uuid', 'Config.InstanceUuid',
                'Runtime.PowerState', 'Runtime.ConnectionState', 'Runtime.Host',
                'Guest.GuestState', 'Guest.HostName', 'Guest.IpAddress',
                'Guest.ToolsStatus', 'Guest.ToolsVersion',
                'Summary.Storage.Committed', 'Summary.Config.NumCpu',
                'Summary.Config.MemorySizeMB', 'Summary.Runtime.Host',
                'Summary.Runtime.PowerState', 'ResourcePool', 'Parent'
            )
            
            # FastMode property set (alias for Fast, from FastModeOptimizer)
            FastMode = @(
                'Name', 'Config.GuestId', 'Config.Version',
                'Config.Hardware.NumCPU', 'Config.Hardware.MemoryMB',
                'Config.Uuid', 'Config.InstanceUuid',
                'Runtime.PowerState', 'Runtime.ConnectionState', 'Runtime.Host',
                'Guest.GuestState', 'Guest.HostName', 'Guest.IpAddress',
                'Guest.ToolsStatus', 'Guest.ToolsVersion',
                'Summary.Storage.Committed', 'Summary.Config.NumCpu',
                'Summary.Config.MemorySizeMB', 'Summary.Runtime.Host',
                'Summary.Runtime.PowerState', 'ResourcePool', 'Parent'
            )
            
            # Minimal property set for inventory-only collection (80% reduction)
            Minimal = @(
                'Name', 'Config.GuestId', 'Config.Hardware.NumCPU',
                'Config.Hardware.MemoryMB', 'Runtime.PowerState',
                'Runtime.ConnectionState', 'Summary.Storage.Committed',
                'Summary.Config.NumCpu', 'Summary.Config.MemorySizeMB'
            )
            
            # UltraFast property set (alias for Minimal, from FastModeOptimizer)
            UltraFast = @(
                'Name', 'Config.Hardware.NumCPU', 'Config.Hardware.MemoryMB',
                'Runtime.PowerState', 'Runtime.ConnectionState',
                'Summary.Storage.Committed', 'Summary.Config.NumCpu',
                'Summary.Config.MemorySizeMB', 'Summary.Runtime.Host'
            )
            
            # Infrastructure property set for host/cluster information
            Infrastructure = @(
                'Name', 'Runtime.Host', 'ResourcePool', 'Parent',
                'Summary.Runtime.Host'
            )
        }
    }
    
    # Initialize performance metrics tracking
    [void] InitializePerformanceMetrics() {
        $this.PerformanceMetrics = @{
            TotalBulkOperations = 0
            TotalVMsProcessed = 0
            TotalAPICallsMade = 0
            AverageVMsPerSecond = 0.0
            AverageBatchProcessingTime = 0.0
            PropertyFilteringTime = 0.0
            DataTransferTime = 0.0
            MemoryUsagePeakMB = 0
            CacheHitRatio = 0.0
            OptimizationSavingsPercent = 0.0
            ErrorRate = 0.0
            BatchSizes = @()
            ProcessingTimes = @()
        }
    }
    
    # Initialize optimization settings
    [void] InitializeOptimizationSettings() {
        $this.OptimizationSettings = @{
            EnablePropertyFiltering = $true
            EnableBatchOptimization = $true
            EnableMemoryManagement = $true
            EnableProgressiveLoading = $true
            MaxMemoryUsageMB = 2048
            MemoryCleanupThreshold = 0.8
            BatchSizeAdjustment = $true
            AdaptiveBatchSizing = $true
            MinBatchSize = 10
            MaxBatchSize = 500
            PerformanceMonitoring = $true
        }
    }
    
    # Main bulk collection method with optimization
    [array] CollectVMDataBulk([array] $vmList, [string] $propertySet = 'Full', [hashtable] $options = @{}) {
        try {
            $this.OperationStartTime = Get-Date
            $this.Logger.WriteInformation("Starting bulk VM data collection for $($vmList.Count) VMs using '$propertySet' property set")
            
            # Configure operation based on options
            $this.ConfigureBulkOperation($options)
            
            # Initialize progress tracking
            $this.ProgressTracker.StartProgress("Bulk VM Data Collection", $vmList.Count)
            
            # Create optimized batches
            $batches = $this.CreateOptimizedBatches($vmList)
            $this.Logger.WriteInformation("Created $($batches.Count) optimized batches (avg size: $([Math]::Round($vmList.Count / $batches.Count, 1)))")
            
            # Process batches with bulk operations
            $allVMData = @()
            $batchNumber = 0
            
            foreach ($batch in $batches) {
                $batchNumber++
                $batchStartTime = Get-Date
                
                try {
                    # Update progress
                    $processedSoFar = ($batchNumber - 1) * $this.BatchSize
                    $this.ProgressTracker.UpdateProgress($processedSoFar, "Processing batch $batchNumber of $($batches.Count)")
                    
                    # Execute bulk Get-View operation
                    $batchData = $this.ExecuteBulkGetView($batch, $propertySet)
                    $allVMData += $batchData
                    
                    # Track performance metrics
                    $batchTime = (Get-Date) - $batchStartTime
                    $this.UpdatePerformanceMetrics($batch.Count, $batchTime.TotalSeconds)
                    
                    # Memory management
                    if ($this.OptimizationSettings.EnableMemoryManagement) {
                        $this.ManageMemoryUsage($batchNumber)
                    }
                    
                    # Adaptive batch sizing
                    if ($this.OptimizationSettings.AdaptiveBatchSizing) {
                        $this.AdjustBatchSize($batchTime.TotalSeconds, $batch.Count)
                    }
                    
                    $this.Logger.WriteDebug("Batch $batchNumber completed in $([Math]::Round($batchTime.TotalSeconds, 2))s")
                    
                } catch {
                    $this.Logger.WriteError("Failed to process batch $batchNumber", $_.Exception)
                    $this.PerformanceMetrics.ErrorRate += 1.0 / $batches.Count
                }
            }
            
            # Complete progress and finalize metrics
            $this.ProgressTracker.CompleteProgress()
            $this.FinalizePerformanceMetrics($allVMData.Count)
            
            $this.Logger.WriteInformation("Bulk collection completed: $($allVMData.Count) VMs processed in $($this.GetTotalProcessingTime()) seconds")
            $this.LogPerformanceStatistics()
            
            return $allVMData
            
        } catch {
            $this.Logger.WriteError("Bulk VM data collection failed", $_.Exception)
            throw
        }
    }
    
    # Execute bulk Get-View operation with property filtering
    [array] ExecuteBulkGetView([array] $vmBatch, [string] $propertySet) {
        try {
            $properties = $this.PropertySets[$propertySet]
            if (-not $properties) {
                throw "Invalid property set: $propertySet"
            }
            
            $this.Logger.WriteDebug("Executing bulk Get-View for $($vmBatch.Count) VMs with $($properties.Count) properties")
            
            # Measure property filtering time
            $filterStartTime = Get-Date
            
            # Execute bulk Get-View with property filtering
            $vmViews = $vmBatch | Get-View -Property $properties -ErrorAction SilentlyContinue
            
            $filterTime = (Get-Date) - $filterStartTime
            $this.PerformanceMetrics.PropertyFilteringTime += $filterTime.TotalSeconds
            $this.PerformanceMetrics.TotalAPICallsMade++
            $this.PerformanceMetrics.TotalBulkOperations++
            
            # Validate results
            if ($vmViews.Count -ne $vmBatch.Count) {
                $this.Logger.WriteWarning("Bulk Get-View returned $($vmViews.Count) results for $($vmBatch.Count) VMs")
            }
            
            return $vmViews
            
        } catch {
            $this.Logger.WriteError("Bulk Get-View operation failed", $_.Exception)
            throw
        }
    }
    
    # Create optimized batches based on VM characteristics and system resources
    [array] CreateOptimizedBatches([array] $vmList) {
        $batches = @()
        $currentBatchSize = $this.BatchSize
        
        # Adjust batch size based on VM list size and system resources
        if ($this.OptimizationSettings.BatchSizeAdjustment) {
            $currentBatchSize = $this.CalculateOptimalBatchSize($vmList.Count)
        }
        
        # Group VMs by characteristics for better batching (optional optimization)
        if ($this.OptimizationSettings.EnableProgressiveLoading) {
            $vmList = $this.SortVMsForOptimalProcessing($vmList)
        }
        
        # Create batches
        for ($i = 0; $i -lt $vmList.Count; $i += $currentBatchSize) {
            $endIndex = [Math]::Min($i + $currentBatchSize - 1, $vmList.Count - 1)
            $batch = $vmList[$i..$endIndex]
            $batches += ,$batch
            
            # Track batch sizes for performance analysis
            $this.PerformanceMetrics.BatchSizes += $batch.Count
        }
        
        return $batches
    }
    
    # Calculate optimal batch size based on environment and resources
    [int] CalculateOptimalBatchSize([int] $totalVMs) {
        # Base calculation on total VMs and available memory
        $availableMemoryMB = $this.GetAvailableMemoryMB()
        $optimalSize = $this.BatchSize
        
        # Adjust based on VM count
        if ($totalVMs -lt 100) {
            $optimalSize = [Math]::Min(50, $totalVMs)
        } elseif ($totalVMs -lt 1000) {
            $optimalSize = 100
        } elseif ($totalVMs -lt 5000) {
            $optimalSize = 150
        } else {
            $optimalSize = 200
        }
        
        # Adjust based on available memory
        if ($availableMemoryMB -lt 1024) {
            $optimalSize = [Math]::Max(25, $optimalSize / 2)
        } elseif ($availableMemoryMB -gt 4096) {
            $optimalSize = [Math]::Min(300, $optimalSize * 1.5)
        }
        
        # Ensure within bounds
        $optimalSize = [Math]::Max($this.OptimizationSettings.MinBatchSize, $optimalSize)
        $optimalSize = [Math]::Min($this.OptimizationSettings.MaxBatchSize, $optimalSize)
        
        $this.Logger.WriteDebug("Calculated optimal batch size: $optimalSize (Total VMs: $totalVMs, Available Memory: $availableMemoryMB MB)")
        
        return $optimalSize
    }
    
    # Sort VMs for optimal processing order
    [array] SortVMsForOptimalProcessing([array] $vmList) {
        try {
            # Sort by power state (powered on first), then by name for consistency
            $sortedVMs = $vmList | Sort-Object @{
                Expression = { if ($_.PowerState -eq 'PoweredOn') { 0 } else { 1 } }
            }, Name
            
            $this.Logger.WriteDebug("Sorted VMs for optimal processing: PoweredOn VMs first")
            return $sortedVMs
            
        } catch {
            $this.Logger.WriteWarning("Failed to sort VMs for optimal processing, using original order")
            return $vmList
        }
    }
    
    # Update performance metrics during processing
    [void] UpdatePerformanceMetrics([int] $batchSize, [double] $processingTimeSeconds) {
        $this.PerformanceMetrics.TotalVMsProcessed += $batchSize
        $this.PerformanceMetrics.ProcessingTimes += $processingTimeSeconds
        
        # Calculate running averages
        if ($this.PerformanceMetrics.ProcessingTimes.Count -gt 0) {
            $this.PerformanceMetrics.AverageBatchProcessingTime = ($this.PerformanceMetrics.ProcessingTimes | Measure-Object -Average).Average
        }
        
        # Calculate VMs per second
        $totalTime = $this.GetTotalProcessingTime()
        if ($totalTime -gt 0) {
            $this.PerformanceMetrics.AverageVMsPerSecond = $this.PerformanceMetrics.TotalVMsProcessed / $totalTime
        }
        
        # Update memory usage
        $currentMemoryMB = $this.GetCurrentMemoryUsageMB()
        $this.PerformanceMetrics.MemoryUsagePeakMB = [Math]::Max($this.PerformanceMetrics.MemoryUsagePeakMB, $currentMemoryMB)
    }
    
    # Manage memory usage during bulk operations
    [void] ManageMemoryUsage([int] $batchNumber) {
        $currentMemoryMB = $this.GetCurrentMemoryUsageMB()
        $memoryThreshold = $this.OptimizationSettings.MaxMemoryUsageMB * $this.OptimizationSettings.MemoryCleanupThreshold
        
        if ($currentMemoryMB -gt $memoryThreshold) {
            $this.Logger.WriteDebug("Memory usage ($currentMemoryMB MB) exceeds threshold ($memoryThreshold MB), performing cleanup")
            
            # Force garbage collection
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $afterCleanupMB = $this.GetCurrentMemoryUsageMB()
            $this.Logger.WriteDebug("Memory cleanup completed: $currentMemoryMB MB -> $afterCleanupMB MB")
        }
        
        # Periodic cleanup every 10 batches
        if ($batchNumber % 10 -eq 0) {
            [System.GC]::Collect()
        }
    }
    
    # Adjust batch size based on performance
    [void] AdjustBatchSize([double] $processingTime, [int] $batchSize) {
        # Target processing time per batch (in seconds)
        $targetTime = 30.0
        
        if ($processingTime -gt $targetTime * 1.5 -and $batchSize -gt $this.OptimizationSettings.MinBatchSize) {
            # Reduce batch size if processing is too slow
            $this.BatchSize = [Math]::Max($this.OptimizationSettings.MinBatchSize, [Math]::Floor($batchSize * 0.8))
            $this.Logger.WriteDebug("Reduced batch size to $($this.BatchSize) due to slow processing ($processingTime s)")
        } elseif ($processingTime -lt $targetTime * 0.5 -and $batchSize -lt $this.OptimizationSettings.MaxBatchSize) {
            # Increase batch size if processing is fast
            $this.BatchSize = [Math]::Min($this.OptimizationSettings.MaxBatchSize, [Math]::Ceiling($batchSize * 1.2))
            $this.Logger.WriteDebug("Increased batch size to $($this.BatchSize) due to fast processing ($processingTime s)")
        }
    }
    
    # Configure bulk operation based on options
    [void] ConfigureBulkOperation([hashtable] $options) {
        if ($options.ContainsKey('BatchSize')) {
            $this.BatchSize = $options.BatchSize
        }
        if ($options.ContainsKey('MaxConcurrentOperations')) {
            $this.MaxConcurrentOperations = $options.MaxConcurrentOperations
        }
        if ($options.ContainsKey('OptimizationSettings')) {
            foreach ($setting in $options.OptimizationSettings.GetEnumerator()) {
                $this.OptimizationSettings[$setting.Key] = $setting.Value
            }
        }
        
        $this.Logger.WriteDebug("Bulk operation configured: BatchSize=$($this.BatchSize), MaxConcurrent=$($this.MaxConcurrentOperations)")
    }
    
    # Finalize performance metrics
    [void] FinalizePerformanceMetrics([int] $totalProcessed) {
        $totalTime = $this.GetTotalProcessingTime()
        
        if ($totalTime -gt 0) {
            $this.PerformanceMetrics.AverageVMsPerSecond = $totalProcessed / $totalTime
        }
        
        # Calculate optimization savings (estimated)
        $estimatedNonBulkTime = $totalProcessed * 0.5  # Assume 0.5s per VM without bulk operations
        if ($estimatedNonBulkTime -gt 0) {
            $this.PerformanceMetrics.OptimizationSavingsPercent = [Math]::Max(0, (($estimatedNonBulkTime - $totalTime) / $estimatedNonBulkTime) * 100)
        }
        
        # Calculate cache hit ratio (if applicable)
        $totalCacheOperations = $this.PerformanceMetrics.TotalBulkOperations
        if ($totalCacheOperations -gt 0) {
            $this.PerformanceMetrics.CacheHitRatio = (1.0 - ($this.PerformanceMetrics.TotalAPICallsMade / $totalCacheOperations)) * 100
        }
    }
    
    # Log performance statistics
    [void] LogPerformanceStatistics() {
        $stats = $this.PerformanceMetrics
        $totalTime = $this.GetTotalProcessingTime()
        
        $this.Logger.WriteInformation("Bulk Operations Performance Statistics:")
        $this.Logger.WriteInformation("  Total VMs Processed: $($stats.TotalVMsProcessed)")
        $this.Logger.WriteInformation("  Total Processing Time: $([Math]::Round($totalTime, 2)) seconds")
        $this.Logger.WriteInformation("  Average VMs/Second: $([Math]::Round($stats.AverageVMsPerSecond, 2))")
        $this.Logger.WriteInformation("  Total Bulk Operations: $($stats.TotalBulkOperations)")
        $this.Logger.WriteInformation("  Total API Calls: $($stats.TotalAPICallsMade)")
        $this.Logger.WriteInformation("  Average Batch Size: $([Math]::Round(($stats.BatchSizes | Measure-Object -Average).Average, 1))")
        $this.Logger.WriteInformation("  Average Batch Time: $([Math]::Round($stats.AverageBatchProcessingTime, 2)) seconds")
        $this.Logger.WriteInformation("  Peak Memory Usage: $($stats.MemoryUsagePeakMB) MB")
        $this.Logger.WriteInformation("  Optimization Savings: $([Math]::Round($stats.OptimizationSavingsPercent, 1))%")
        $this.Logger.WriteInformation("  Error Rate: $([Math]::Round($stats.ErrorRate * 100, 2))%")
    }
    
    # Helper methods for system resource monitoring
    [int] GetCurrentMemoryUsageMB() {
        try {
            $currentPID = [System.Diagnostics.Process]::GetCurrentProcess().Id
            return [Math]::Round((Get-Process -Id $currentPID).WorkingSet64 / 1MB, 0)
        } catch {
            return 0
        }
    }
    
    [int] GetAvailableMemoryMB() {
        try {
            $totalMemory = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
            $availableMemory = (Get-CimInstance -ClassName Win32_OperatingSystem).AvailablePhysicalMemory
            return [Math]::Round($availableMemory / 1KB / 1KB, 0)
        } catch {
            return 2048  # Default assumption
        }
    }
    
    [double] GetTotalProcessingTime() {
        if ($this.OperationStartTime) {
            return (Get-Date - $this.OperationStartTime).TotalSeconds
        }
        return 0.0
    }
    
    # Get performance metrics
    [hashtable] GetPerformanceMetrics() {
        return $this.PerformanceMetrics
    }
    
    # Get optimization settings
    [hashtable] GetOptimizationSettings() {
        return $this.OptimizationSettings
    }
    
    # Update optimization settings
    [void] UpdateOptimizationSettings([hashtable] $newSettings) {
        foreach ($setting in $newSettings.GetEnumerator()) {
            $this.OptimizationSettings[$setting.Key] = $setting.Value
        }
        $this.Logger.WriteDebug("Optimization settings updated")
    }
    
    # ========================================
    # FASTMODE OPTIMIZATION METHODS
    # ========================================
    
    # Initialize FastMode-specific components
    [void] InitializeFastModeComponents() {
        $this.InitializeFastModeSettings()
        $this.InitializeSkippedOperations()
        $this.InitializeOptimizationRules()
    }
    
    # Initialize FastMode settings
    [void] InitializeFastModeSettings() {
        $this.FastModeSettings = @{
            AutoSelectMode = $true
            EnablePropertyFiltering = $true
            EnableOperationSkipping = $true
            EnablePerformanceTracking = $true
            MaxNetworkAdapters = 1
            MaxDatastores = 1
            SkipSnapshots = $true
            SkipResourceDetails = $true
            SkipCustomFields = $true
            SkipGuestDetails = $false
            EnableProgressiveOptimization = $true
            AdaptiveOptimization = $true
        }
    }
    
    # Initialize operations that are skipped in FastMode
    [void] InitializeSkippedOperations() {
        $this.SkippedOperations = @{
            DetailedNetworkCollection = @{
                Description = "Skip detailed network adapter enumeration beyond primary adapter"
                EstimatedTimeSavingPercent = 15
                Operations = @('Get-NetworkAdapter', 'Network.Config.Device enumeration')
            }
            DetailedStorageCollection = @{
                Description = "Skip detailed disk and datastore enumeration"
                EstimatedTimeSavingPercent = 20
                Operations = @('Get-HardDisk', 'Datastore.Info collection', 'LayoutEx.File processing')
            }
            SnapshotInformation = @{
                Description = "Skip snapshot enumeration and size calculations"
                EstimatedTimeSavingPercent = 10
                Operations = @('Snapshot tree traversal', 'Snapshot size calculation')
            }
            ResourceManagementDetails = @{
                Description = "Skip detailed CPU/Memory allocation and shares information"
                EstimatedTimeSavingPercent = 8
                Operations = @('Config.CpuAllocation', 'Config.MemoryAllocation', 'Resource pool details')
            }
            NonEssentialVMProperties = @{
                Description = "Skip non-essential VM properties and custom fields"
                EstimatedTimeSavingPercent = 12
                Operations = @('Config.ExtraConfig', 'Custom fields', 'Advanced settings')
            }
            GuestDetailedInformation = @{
                Description = "Skip detailed guest OS information and disk usage"
                EstimatedTimeSavingPercent = 10
                Operations = @('Guest.Net details', 'Guest.Disk details', 'Guest OS version detection')
            }
        }
    }
    
    # Initialize optimization rules
    [void] InitializeOptimizationRules() {
        $this.OptimizationRules = @{
            # Environment size-based rules
            SmallEnvironment = @{
                VMThreshold = 1000
                RecommendedMode = 'Standard'
                ExpectedTimeMinutes = 5
                Description = "Small environments (<1,000 VMs) - FastMode optional"
            }
            MediumEnvironment = @{
                VMThreshold = 5000
                RecommendedMode = 'FastMode'
                ExpectedTimeMinutes = 15
                Description = "Medium environments (1,000-5,000 VMs) - FastMode recommended"
            }
            LargeEnvironment = @{
                VMThreshold = 10000
                RecommendedMode = 'FastMode'
                ExpectedTimeMinutes = 60
                Description = "Large environments (5,000-10,000 VMs) - FastMode required"
            }
            UltraLargeEnvironment = @{
                VMThreshold = 999999
                RecommendedMode = 'UltraFast'
                ExpectedTimeMinutes = 120
                Description = "Ultra-large environments (10,000+ VMs) - UltraFast mode required"
            }
        }
    }
    
    # Enable FastMode with specified level
    [void] EnableFastMode([string] $mode = 'FastMode', [int] $vmCount = 0) {
        try {
            $this.FastModeEnabled = $true
            $this.OptimizationStartTime = Get-Date
            
            # Auto-select mode based on VM count if not specified
            if ($this.FastModeSettings.AutoSelectMode -and $vmCount -gt 0) {
                $mode = $this.SelectOptimalMode($vmCount)
            }
            
            # Configure optimization based on mode
            $this.ConfigureOptimizationMode($mode)
            
            $this.Logger.WriteInformation("FastMode enabled: $mode for $vmCount VMs")
            $this.LogOptimizationSettings($mode)
            
        } catch {
            $this.Logger.WriteError("Failed to enable FastMode", $_.Exception)
            throw
        }
    }
    
    # Select optimal mode based on environment size and constraints
    [string] SelectOptimalMode([int] $vmCount) {
        foreach ($rule in $this.OptimizationRules.GetEnumerator()) {
            if ($rule.Value.ContainsKey('VMThreshold') -and $vmCount -le $rule.Value.VMThreshold) {
                $this.Logger.WriteInformation("Selected $($rule.Value.RecommendedMode) mode for $vmCount VMs ($($rule.Value.Description))")
                return $rule.Value.RecommendedMode
            }
        }
        
        # Default to FastMode if no rule matches
        return 'FastMode'
    }
    
    # Configure optimization mode
    [void] ConfigureOptimizationMode([string] $mode) {
        switch ($mode) {
            'Standard' {
                $this.FastModeSettings.SkipSnapshots = $false
                $this.FastModeSettings.SkipResourceDetails = $false
                $this.FastModeSettings.SkipCustomFields = $false
                $this.FastModeSettings.MaxNetworkAdapters = 4
                $this.FastModeSettings.MaxDatastores = 10
            }
            'FastMode' {
                $this.FastModeSettings.SkipSnapshots = $true
                $this.FastModeSettings.SkipResourceDetails = $true
                $this.FastModeSettings.SkipCustomFields = $true
                $this.FastModeSettings.MaxNetworkAdapters = 1
                $this.FastModeSettings.MaxDatastores = 1
                $this.FastModeSettings.SkipGuestDetails = $false
            }
            'UltraFast' {
                $this.FastModeSettings.SkipSnapshots = $true
                $this.FastModeSettings.SkipResourceDetails = $true
                $this.FastModeSettings.SkipCustomFields = $true
                $this.FastModeSettings.MaxNetworkAdapters = 1
                $this.FastModeSettings.MaxDatastores = 1
                $this.FastModeSettings.SkipGuestDetails = $true
            }
        }
        
        $this.Logger.WriteDebug("Optimization mode configured: $mode")
    }
    
    # Check if operation should be skipped in FastMode
    [bool] ShouldSkipOperation([string] $operationType) {
        if (-not $this.FastModeEnabled) {
            return $false
        }
        
        $skipOperation = $false
        
        switch ($operationType) {
            'DetailedNetworkCollection' {
                $skipOperation = $this.FastModeSettings.MaxNetworkAdapters -le 1
            }
            'DetailedStorageCollection' {
                $skipOperation = $this.FastModeSettings.MaxDatastores -le 1
            }
            'SnapshotInformation' {
                $skipOperation = $this.FastModeSettings.SkipSnapshots
            }
            'ResourceManagementDetails' {
                $skipOperation = $this.FastModeSettings.SkipResourceDetails
            }
            'NonEssentialVMProperties' {
                $skipOperation = $this.FastModeSettings.SkipCustomFields
            }
            'GuestDetailedInformation' {
                $skipOperation = $this.FastModeSettings.SkipGuestDetails
            }
        }
        
        if ($skipOperation) {
            $this.PerformanceMetrics.TotalOperationsCompleted++
            $this.Logger.WriteDebug("Skipping operation: $operationType")
        }
        
        return $skipOperation
    }
    
    # Apply FastMode optimizations to VM data collection
    [hashtable] ApplyFastModeOptimizations([object] $vm, [object] $vmView, [hashtable] $vmData) {
        try {
            if (-not $this.FastModeEnabled) {
                return $vmData
            }
            
            # Skip detailed network collection
            if ($this.ShouldSkipOperation('DetailedNetworkCollection')) {
                $vmData = $this.OptimizeNetworkCollection($vm, $vmView, $vmData)
            }
            
            # Skip detailed storage collection
            if ($this.ShouldSkipOperation('DetailedStorageCollection')) {
                $vmData = $this.OptimizeStorageCollection($vm, $vmView, $vmData)
            }
            
            # Skip snapshot information
            if ($this.ShouldSkipOperation('SnapshotInformation')) {
                $vmData = $this.OptimizeSnapshotCollection($vm, $vmView, $vmData)
            }
            
            # Skip resource management details
            if ($this.ShouldSkipOperation('ResourceManagementDetails')) {
                $vmData = $this.OptimizeResourceManagement($vm, $vmView, $vmData)
            }
            
            # Skip non-essential properties
            if ($this.ShouldSkipOperation('NonEssentialVMProperties')) {
                $vmData = $this.OptimizeNonEssentialProperties($vm, $vmView, $vmData)
            }
            
            # Skip guest detailed information
            if ($this.ShouldSkipOperation('GuestDetailedInformation')) {
                $vmData = $this.OptimizeGuestInformation($vm, $vmView, $vmData)
            }
            
            return $vmData
            
        } catch {
            $this.Logger.WriteError("Failed to apply FastMode optimizations", $_.Exception)
            return $vmData
        }
    }
    
    # Optimize network collection (limit to primary adapter)
    [hashtable] OptimizeNetworkCollection([object] $vm, [object] $vmView, [hashtable] $vmData) {
        # Only collect primary network adapter information
        if ($vm.NetworkAdapters -and $vm.NetworkAdapters.Count -gt 0) {
            $vmData.NetworkAdapter1 = $vm.NetworkAdapters[0].NetworkName
            $vmData.MACAddress = $vm.NetworkAdapters[0].MacAddress
            $vmData.NetworkName = $vm.NetworkAdapters[0].NetworkName
        }
        
        # Clear additional network adapters
        $vmData.NetworkAdapter2 = ""
        $vmData.NetworkAdapter3 = ""
        $vmData.NetworkAdapter4 = ""
        
        return $vmData
    }
    
    # Optimize storage collection (primary datastore only)
    [hashtable] OptimizeStorageCollection([object] $vm, [object] $vmView, [hashtable] $vmData) {
        # Use summary storage information only
        if ($vmView.Summary.Storage) {
            $vmData.StorageCommittedGB = [Math]::Round($vmView.Summary.Storage.Committed / 1GB, 2)
            $vmData.TotalStorageGB = $vmData.StorageCommittedGB
        }
        
        # Set default values for detailed storage info
        $vmData.StorageFormat = "VMDK"
        $vmData.DiskMode = "persistent"
        $vmData.StorageUncommittedGB = 0
        
        return $vmData
    }
    
    # Optimize snapshot collection (skip entirely)
    [hashtable] OptimizeSnapshotCollection([object] $vm, [object] $vmView, [hashtable] $vmData) {
        # Set default values without collecting actual snapshot data
        $vmData.SnapshotCount = 0
        $vmData.SnapshotSizeGB = 0.0
        $vmData.SnapshotCreated = ""
        
        return $vmData
    }
    
    # Optimize resource management (use defaults)
    [hashtable] OptimizeResourceManagement([object] $vm, [object] $vmView, [hashtable] $vmData) {
        # Set default resource management values
        $vmData.CPUReservation = 0
        $vmData.CPULimit = -1
        $vmData.MemoryReservation = 0
        $vmData.MemoryLimit = -1
        $vmData.CPUShares = "Normal"
        $vmData.MemoryShares = "Normal"
        
        return $vmData
    }
    
    # Optimize non-essential properties
    [hashtable] OptimizeNonEssentialProperties([object] $vm, [object] $vmView, [hashtable] $vmData) {
        # Set default values for custom fields
        $vmData.CustomField1 = ""
        $vmData.CustomField2 = ""
        $vmData.CustomField3 = ""
        
        # Use simplified environment/application detection
        $vmData.Environment = $this.GetSimplifiedEnvironment($vm.Name)
        $vmData.Application = $this.GetSimplifiedApplication($vm.Name)
        $vmData.Owner = "Unknown"
        
        return $vmData
    }
    
    # Optimize guest information collection
    [hashtable] OptimizeGuestInformation([object] $vm, [object] $vmView, [hashtable] $vmData) {
        # Use basic guest information only
        if ($vm.Guest) {
            $vmData.DNSName = $vm.Guest.HostName
            $vmData.OperatingSystem = $vm.Guest.OSFullName
            if ($vm.Guest.IPAddress -and $vm.Guest.IPAddress.Count -gt 0) {
                $vmData.IPAddress = $vm.Guest.IPAddress[0]
            }
        }
        
        # Skip detailed OS version detection
        $vmData.OSVersion = $vmView.Config.GuestId
        
        return $vmData
    }
    
    # Simplified environment detection
    [string] GetSimplifiedEnvironment([string] $vmName) {
        $name = $vmName.ToLower()
        if ($name -match 'prod') { return 'Production' }
        elseif ($name -match 'test') { return 'Test' }
        elseif ($name -match 'dev') { return 'Development' }
        else { return 'Unknown' }
    }
    
    # Simplified application detection
    [string] GetSimplifiedApplication([string] $vmName) {
        $name = $vmName.ToLower()
        if ($name -match 'web') { return 'Web Server' }
        elseif ($name -match 'sql|db') { return 'Database' }
        elseif ($name -match 'app') { return 'Application Server' }
        else { return 'Unknown' }
    }
    
    # Log optimization settings
    [void] LogOptimizationSettings([string] $mode) {
        $this.Logger.WriteInformation("FastMode Optimization Settings:")
        $this.Logger.WriteInformation("  Mode: $mode")
        $this.Logger.WriteInformation("  Skip Snapshots: $($this.FastModeSettings.SkipSnapshots)")
        $this.Logger.WriteInformation("  Skip Resource Details: $($this.FastModeSettings.SkipResourceDetails)")
        $this.Logger.WriteInformation("  Skip Custom Fields: $($this.FastModeSettings.SkipCustomFields)")
        $this.Logger.WriteInformation("  Max Network Adapters: $($this.FastModeSettings.MaxNetworkAdapters)")
        $this.Logger.WriteInformation("  Max Datastores: $($this.FastModeSettings.MaxDatastores)")
        $this.Logger.WriteInformation("  Skip Guest Details: $($this.FastModeSettings.SkipGuestDetails)")
    }
    
    # Disable FastMode
    [void] DisableFastMode() {
        $this.FastModeEnabled = $false
        $this.Logger.WriteInformation("FastMode disabled")
    }
    
    # Check if FastMode is enabled
    [bool] IsFastModeEnabled() {
        return $this.FastModeEnabled
    }
    
    # Get optimization recommendations
    [hashtable] GetOptimizationRecommendations([int] $vmCount, [int] $availableMemoryMB = 4096, [int] $timeConstraintMinutes = 0) {
        $recommendations = @{
            RecommendedMode = 'Standard'
            Reasoning = @()
            EstimatedTimeMinutes = 0
            ExpectedTimeSavingsPercent = 0
            MemoryRequirementMB = 0
        }
        
        # Analyze environment size
        foreach ($rule in $this.OptimizationRules.GetEnumerator()) {
            if ($rule.Value.ContainsKey('VMThreshold') -and $vmCount -le $rule.Value.VMThreshold) {
                $recommendations.RecommendedMode = $rule.Value.RecommendedMode
                $recommendations.EstimatedTimeMinutes = $rule.Value.ExpectedTimeMinutes
                $recommendations.Reasoning += $rule.Value.Description
                break
            }
        }
        
        # Check memory constraints
        if ($availableMemoryMB -lt 2048) {
            $recommendations.RecommendedMode = 'UltraFast'
            $recommendations.Reasoning += "Limited memory available ($availableMemoryMB MB)"
        }
        
        # Check time constraints
        if ($timeConstraintMinutes -gt 0 -and $recommendations.EstimatedTimeMinutes -gt $timeConstraintMinutes) {
            if ($recommendations.RecommendedMode -eq 'Standard') {
                $recommendations.RecommendedMode = 'FastMode'
            } elseif ($recommendations.RecommendedMode -eq 'FastMode') {
                $recommendations.RecommendedMode = 'UltraFast'
            }
            $recommendations.Reasoning += "Time constraint requires faster mode ($timeConstraintMinutes min limit)"
        }
        
        # Calculate expected savings
        switch ($recommendations.RecommendedMode) {
            'FastMode' { $recommendations.ExpectedTimeSavingsPercent = 60 }
            'UltraFast' { $recommendations.ExpectedTimeSavingsPercent = 80 }
            default { $recommendations.ExpectedTimeSavingsPercent = 0 }
        }
        
        return $recommendations
    }
    
    # ========================================
    # UNIFIED OPTIMIZATION METHODS
    # ========================================
    
    # Get optimized property set for current mode (unified method)
    [array] GetOptimizedPropertySet([string] $mode = 'Full') {
        # Map FastMode modes to property sets
        $propertySetMap = @{
            'Standard' = 'Full'
            'FastMode' = 'Fast'
            'UltraFast' = 'Minimal'
        }
        
        # Use mapped property set if FastMode mode is specified
        if ($propertySetMap.ContainsKey($mode)) {
            $mode = $propertySetMap[$mode]
        }
        
        if ($this.PropertySets.ContainsKey($mode)) {
            $properties = $this.PropertySets[$mode]
            $standardCount = $this.PropertySets.Full.Count
            $optimizedCount = $properties.Count
            $reductionPercent = [Math]::Round((($standardCount - $optimizedCount) / $standardCount) * 100, 1)
            
            $this.Logger.WriteDebug("Using $mode property set: $optimizedCount properties ($reductionPercent% reduction)")
            
            return $properties
        } else {
            $this.Logger.WriteWarning("Unknown property set: $mode, using Full")
            return $this.PropertySets.Full
        }
    }
    
    # Enhanced bulk collection with FastMode integration
    [array] CollectVMDataInBulk([array] $vmList, [string] $propertySet = 'Full') {
        # If FastMode is enabled, automatically adjust property set
        if ($this.FastModeEnabled) {
            $fastModeMap = @{
                'Full' = 'Fast'
                'Fast' = 'Fast'
                'Minimal' = 'Minimal'
            }
            
            if ($fastModeMap.ContainsKey($propertySet)) {
                $originalPropertySet = $propertySet
                $propertySet = $fastModeMap[$propertySet]
                $this.Logger.WriteInformation("FastMode enabled: adjusted property set from $originalPropertySet to $propertySet")
            }
        }
        
        # Use the existing bulk collection method
        return $this.CollectVMDataBulk($vmList, $propertySet, @{})
    }
    
    # Process VMs in batches with FastMode optimizations
    [array] ProcessInBatches([array] $items, [int] $batchSize) {
        if ($batchSize -le 0) {
            $effectiveBatchSize = $this.BatchSize
        } else {
            $effectiveBatchSize = $batchSize
        }
        
        $results = @()
        $batches = $this.CreateOptimizedBatches($items)
        
        foreach ($batch in $batches) {
            # Apply FastMode optimizations if enabled
            if ($this.FastModeEnabled) {
                $batch = $batch | Where-Object { $this.ShouldProcessVM($_) }
            }
            
            $results += $batch
        }
        
        return $results
    }
    
    # Check if VM should be processed (FastMode filtering)
    [bool] ShouldProcessVM([object] $vm) {
        if (-not $this.FastModeEnabled) {
            return $true
        }
        
        # In UltraFast mode, only process powered-on VMs
        if ($this.FastModeSettings.SkipGuestDetails -and $vm.PowerState -ne 'PoweredOn') {
            return $false
        }
        
        return $true
    }
}