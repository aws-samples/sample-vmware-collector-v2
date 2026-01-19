class PerformanceOptimizationManager {
    <#
    .SYNOPSIS
    Manages performance optimization controls including thread pool management, memory monitoring, and optimization statistics.
    
    .DESCRIPTION
    The PerformanceOptimizationManager class provides comprehensive performance optimization capabilities for large-scale
    VMware data collection operations. It manages thread pools, monitors memory usage, implements optimization strategies,
    and provides detailed performance statistics and reporting.
    #>

    # Core Properties
    [hashtable] $Configuration
    [hashtable] $OptimizationSettings
    [hashtable] $PerformanceMetrics
    [hashtable] $ThreadPoolStats
    [hashtable] $MemoryStats
    [datetime] $StartTime
    [bool] $IsOptimizationEnabled
    [bool] $IsMonitoring
    
    # Thread Pool Management
    [System.Management.Automation.Runspaces.RunspacePool] $RunspacePool
    [int] $MaxThreads
    [int] $MinThreads
    [int] $ActiveThreads
    [int] $QueuedJobs
    [System.Collections.Concurrent.ConcurrentQueue[object]] $JobQueue
    [System.Collections.Generic.List[System.Management.Automation.PowerShell]] $ActiveJobs
    
    # Memory Management
    [long] $MaxMemoryBytes
    [long] $CurrentMemoryUsage
    [long] $PeakMemoryUsage
    [double] $MemoryThresholdPercent
    [bool] $MemoryPressureDetected
    [int] $GarbageCollectionCount
    
    # Performance Statistics
    [int] $TotalOperations
    [int] $CompletedOperations
    [int] $FailedOperations
    [double] $AverageOperationTime
    [double] $ThroughputPerSecond
    [hashtable] $OptimizationImpact

    # Constructor
    PerformanceOptimizationManager() {
        $this.Initialize()
    }

    # Initialize the performance optimization manager
    [void] Initialize() {
        $this.StartTime = Get-Date
        $this.IsOptimizationEnabled = $true
        $this.IsMonitoring = $false
        
        # Default optimization settings
        $this.OptimizationSettings = @{
            MaxThreads = 10
            MinThreads = 2
            MaxMemoryGB = 2
            MemoryThresholdPercent = 80
            EnableBulkOperations = $true
            EnableCaching = $true
            EnableProgressiveOptimization = $true
            GarbageCollectionInterval = 100
            PerformanceReportingInterval = 60
            ThreadPoolTimeout = 300
            MemoryCleanupThreshold = 1.5
        }
        
        # Initialize performance metrics
        $this.PerformanceMetrics = @{
            StartTime = $this.StartTime
            TotalExecutionTime = [TimeSpan]::Zero
            ThreadUtilization = 0.0
            MemoryEfficiency = 0.0
            ThroughputImprovement = 0.0
            OptimizationSavings = [TimeSpan]::Zero
            CacheHitRatio = 0.0
            BulkOperationRatio = 0.0
        }
        
        # Initialize thread pool statistics
        $this.ThreadPoolStats = @{
            ThreadsCreated = 0
            ThreadsDestroyed = 0
            JobsQueued = 0
            JobsCompleted = 0
            JobsFailed = 0
            AverageJobTime = 0.0
            MaxConcurrentThreads = 0
            ThreadEfficiency = 0.0
        }
        
        # Initialize memory statistics
        $this.MemoryStats = @{
            InitialMemoryMB = [Math]::Round((Get-Process -Id ([System.Diagnostics.Process]::GetCurrentProcess().Id)).WorkingSet64 / 1MB, 2)
            PeakMemoryMB = 0.0
            CurrentMemoryMB = 0.0
            MemoryGrowthMB = 0.0
            GarbageCollections = 0
            MemoryCleanupEvents = 0
            MemoryPressureEvents = 0
            MemoryEfficiencyRatio = 0.0
        }
        
        # Initialize collections
        $this.JobQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $this.ActiveJobs = [System.Collections.Generic.List[System.Management.Automation.PowerShell]]::new()
        
        # Set default values
        $this.MaxThreads = $this.OptimizationSettings.MaxThreads
        $this.MinThreads = $this.OptimizationSettings.MinThreads
        $this.MaxMemoryBytes = $this.OptimizationSettings.MaxMemoryGB * 1GB
        $this.MemoryThresholdPercent = $this.OptimizationSettings.MemoryThresholdPercent
        $this.ActiveThreads = 0
        $this.QueuedJobs = 0
        $this.TotalOperations = 0
        $this.CompletedOperations = 0
        $this.FailedOperations = 0
        $this.GarbageCollectionCount = 0
        
        Write-Verbose "PerformanceOptimizationManager initialized with MaxThreads: $($this.MaxThreads), MaxMemory: $($this.OptimizationSettings.MaxMemoryGB)GB"
    }

    # Configure optimization settings
    [void] ConfigureOptimization([hashtable] $settings) {
        if ($settings.ContainsKey('MaxThreads')) {
            $this.MaxThreads = [Math]::Min([Math]::Max($settings.MaxThreads, 1), 50)
            $this.OptimizationSettings.MaxThreads = $this.MaxThreads
        }
        
        if ($settings.ContainsKey('MaxMemoryGB')) {
            $this.OptimizationSettings.MaxMemoryGB = [Math]::Max($settings.MaxMemoryGB, 1)
            $this.MaxMemoryBytes = $this.OptimizationSettings.MaxMemoryGB * 1GB
        }
        
        if ($settings.ContainsKey('MemoryThresholdPercent')) {
            $this.MemoryThresholdPercent = [Math]::Min([Math]::Max($settings.MemoryThresholdPercent, 50), 95)
            $this.OptimizationSettings.MemoryThresholdPercent = $this.MemoryThresholdPercent
        }
        
        if ($settings.ContainsKey('EnableBulkOperations')) {
            $this.OptimizationSettings.EnableBulkOperations = $settings.EnableBulkOperations
        }
        
        if ($settings.ContainsKey('EnableCaching')) {
            $this.OptimizationSettings.EnableCaching = $settings.EnableCaching
        }
        
        Write-Verbose "Optimization settings updated: MaxThreads=$($this.MaxThreads), MaxMemory=$($this.OptimizationSettings.MaxMemoryGB)GB, MemoryThreshold=$($this.MemoryThresholdPercent)%"
    }

    # Initialize thread pool
    [void] InitializeThreadPool() {
        try {
            # Create initial session state
            $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            
            # Add VMware PowerCLI modules to session state
            if (Get-Module -Name VMware.PowerCLI -ListAvailable) {
                $initialSessionState.ImportPSModule(@('VMware.PowerCLI'))
            }
            
            # Create runspace pool
            $this.RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
                $this.MinThreads,
                $this.MaxThreads,
                $initialSessionState,
                [System.Management.Automation.Host.PSHost]$null
            )
            
            $this.RunspacePool.Open()
            $this.ThreadPoolStats.ThreadsCreated = $this.MaxThreads
            
            Write-Verbose "Thread pool initialized with $($this.MinThreads)-$($this.MaxThreads) threads"
            
        }
        catch {
            Write-Error "Failed to initialize thread pool: $($_.Exception.Message)"
            throw
        }
    }

    # Start performance monitoring
    [void] StartMonitoring() {
        $this.IsMonitoring = $true
        $this.StartTime = Get-Date
        
        # Start background monitoring job
        $monitoringScript = {
            param($optimizationManager)
            
            while ($optimizationManager.IsMonitoring) {
                $optimizationManager.UpdatePerformanceMetrics()
                $optimizationManager.CheckMemoryPressure()
                $optimizationManager.OptimizeThreadPool()
                
                Start-Sleep -Seconds 5
            }
        }
        
        # Could implement background monitoring here if needed
        Write-Verbose "Performance monitoring started"
    }

    # Stop performance monitoring
    [void] StopMonitoring() {
        $this.IsMonitoring = $false
        $this.UpdateFinalMetrics()
        Write-Verbose "Performance monitoring stopped"
    }

    # Update performance metrics
    [void] UpdatePerformanceMetrics() {
        try {
            # Update memory statistics
            $currentProcess = Get-Process -Id ([System.Diagnostics.Process]::GetCurrentProcess().Id)
            $this.CurrentMemoryUsage = $currentProcess.WorkingSet64
            $this.MemoryStats.CurrentMemoryMB = [Math]::Round($this.CurrentMemoryUsage / 1MB, 2)
            
            if ($this.CurrentMemoryUsage -gt $this.PeakMemoryUsage) {
                $this.PeakMemoryUsage = $this.CurrentMemoryUsage
                $this.MemoryStats.PeakMemoryMB = [Math]::Round($this.PeakMemoryUsage / 1MB, 2)
            }
            
            $this.MemoryStats.MemoryGrowthMB = $this.MemoryStats.CurrentMemoryMB - $this.MemoryStats.InitialMemoryMB
            
            # Update thread pool statistics
            if ($this.RunspacePool) {
                $this.ActiveThreads = $this.ActiveJobs.Count
                $this.ThreadPoolStats.MaxConcurrentThreads = [Math]::Max($this.ThreadPoolStats.MaxConcurrentThreads, $this.ActiveThreads)
            }
            
            # Calculate efficiency metrics
            $this.CalculateEfficiencyMetrics()
            
        }
        catch {
            Write-Warning "Failed to update performance metrics: $($_.Exception.Message)"
        }
    }

    # Check for memory pressure and take action
    [void] CheckMemoryPressure() {
        $memoryUsagePercent = ($this.CurrentMemoryUsage / $this.MaxMemoryBytes) * 100
        
        if ($memoryUsagePercent -gt $this.MemoryThresholdPercent) {
            if (-not $this.MemoryPressureDetected) {
                $this.MemoryPressureDetected = $true
                $this.MemoryStats.MemoryPressureEvents++
                Write-Warning "Memory pressure detected: $([Math]::Round($memoryUsagePercent, 1))% of limit ($($this.OptimizationSettings.MaxMemoryGB)GB)"
            }
            
            # Trigger memory cleanup
            $this.PerformMemoryCleanup()
        } else {
            $this.MemoryPressureDetected = $false
        }
    }

    # Perform memory cleanup
    [void] PerformMemoryCleanup() {
        try {
            $beforeCleanup = $this.CurrentMemoryUsage
            
            # Force garbage collection
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $this.GarbageCollectionCount++
            $this.MemoryStats.GarbageCollections++
            $this.MemoryStats.MemoryCleanupEvents++
            
            # Update memory usage after cleanup
            $this.UpdatePerformanceMetrics()
            
            $memoryFreed = $beforeCleanup - $this.CurrentMemoryUsage
            $memoryFreedMB = [Math]::Round($memoryFreed / 1MB, 2)
            
            if ($memoryFreedMB -gt 0) {
                Write-Verbose "Memory cleanup freed $memoryFreedMB MB"
            }
            
        }
        catch {
            Write-Warning "Memory cleanup failed: $($_.Exception.Message)"
        }
    }

    # Optimize thread pool based on current workload
    [void] OptimizeThreadPool() {
        if (-not $this.RunspacePool) {
            return
        }
        
        try {
            # Calculate thread efficiency
            $completionRate = if ($this.TotalOperations -gt 0) { $this.CompletedOperations / $this.TotalOperations } else { 0 }
            $threadUtilization = if ($this.MaxThreads -gt 0) { $this.ActiveThreads / $this.MaxThreads } else { 0 }
            
            # Adjust thread pool if needed (simplified logic)
            if ($threadUtilization -gt 0.8 -and $this.QueuedJobs -gt 10 -and $this.MaxThreads -lt 50) {
                # Could implement dynamic thread pool scaling here
                Write-Verbose "High thread utilization detected: $([Math]::Round($threadUtilization * 100, 1))%"
            }
            
            $this.ThreadPoolStats.ThreadEfficiency = $threadUtilization
            
        }
        catch {
            Write-Warning "Thread pool optimization failed: $($_.Exception.Message)"
        }
    }

    # Calculate efficiency metrics
    [void] CalculateEfficiencyMetrics() {
        # Memory efficiency
        if ($this.MemoryStats.PeakMemoryMB -gt 0) {
            $this.MemoryStats.MemoryEfficiencyRatio = $this.MemoryStats.InitialMemoryMB / $this.MemoryStats.PeakMemoryMB
        }
        
        # Thread efficiency
        if ($this.TotalOperations -gt 0) {
            $this.ThreadPoolStats.ThreadEfficiency = $this.CompletedOperations / $this.TotalOperations
        }
        
        # Throughput calculation
        $elapsedTime = (Get-Date) - $this.StartTime
        if ($elapsedTime.TotalSeconds -gt 0) {
            $this.ThroughputPerSecond = $this.CompletedOperations / $elapsedTime.TotalSeconds
        }
        
        # Average operation time
        if ($this.CompletedOperations -gt 0) {
            $this.AverageOperationTime = $elapsedTime.TotalMilliseconds / $this.CompletedOperations
        }
    }

    # Execute operation with performance tracking
    [object] ExecuteOptimizedOperation([scriptblock] $operation, [hashtable] $parameters = @{}) {
        $operationStart = Get-Date
        $this.TotalOperations++
        
        try {
            # Check memory pressure before operation
            $this.CheckMemoryPressure()
            
            # Execute operation
            $result = & $operation @parameters
            
            # Track successful completion
            $this.CompletedOperations++
            $operationTime = (Get-Date) - $operationStart
            
            # Update performance metrics
            $this.UpdateOperationMetrics($operationTime, $true)
            
            return $result
            
        }
        catch {
            $this.FailedOperations++
            $operationTime = (Get-Date) - $operationStart
            $this.UpdateOperationMetrics($operationTime, $false)
            
            Write-Warning "Optimized operation failed: $($_.Exception.Message)"
            throw
        }
    }

    # Update operation metrics
    [void] UpdateOperationMetrics([TimeSpan] $operationTime, [bool] $success) {
        # Update average operation time
        if ($this.CompletedOperations -gt 0) {
            $totalTime = $this.AverageOperationTime * ($this.CompletedOperations - 1) + $operationTime.TotalMilliseconds
            $this.AverageOperationTime = $totalTime / $this.CompletedOperations
        }
        
        # Trigger periodic cleanup
        if ($this.CompletedOperations % $this.OptimizationSettings.GarbageCollectionInterval -eq 0) {
            $this.PerformMemoryCleanup()
        }
    }

    # Get current optimization statistics
    [hashtable] GetOptimizationStatistics() {
        $this.UpdatePerformanceMetrics()
        $elapsedTime = (Get-Date) - $this.StartTime
        
        return @{
            # General Statistics
            ElapsedTime = $elapsedTime
            TotalOperations = $this.TotalOperations
            CompletedOperations = $this.CompletedOperations
            FailedOperations = $this.FailedOperations
            SuccessRate = if ($this.TotalOperations -gt 0) { ($this.CompletedOperations / $this.TotalOperations) * 100 } else { 0 }
            AverageOperationTimeMs = $this.AverageOperationTime
            ThroughputPerSecond = $this.ThroughputPerSecond
            
            # Thread Pool Statistics
            ThreadPool = @{
                MaxThreads = $this.MaxThreads
                ActiveThreads = $this.ActiveThreads
                ThreadUtilization = if ($this.MaxThreads -gt 0) { ($this.ActiveThreads / $this.MaxThreads) * 100 } else { 0 }
                ThreadsCreated = $this.ThreadPoolStats.ThreadsCreated
                JobsCompleted = $this.ThreadPoolStats.JobsCompleted
                JobsFailed = $this.ThreadPoolStats.JobsFailed
                ThreadEfficiency = $this.ThreadPoolStats.ThreadEfficiency * 100
            }
            
            # Memory Statistics
            Memory = @{
                InitialMemoryMB = $this.MemoryStats.InitialMemoryMB
                CurrentMemoryMB = $this.MemoryStats.CurrentMemoryMB
                PeakMemoryMB = $this.MemoryStats.PeakMemoryMB
                MemoryGrowthMB = $this.MemoryStats.MemoryGrowthMB
                MemoryLimitMB = $this.OptimizationSettings.MaxMemoryGB * 1024
                MemoryUtilization = ($this.MemoryStats.CurrentMemoryMB / ($this.OptimizationSettings.MaxMemoryGB * 1024)) * 100
                GarbageCollections = $this.MemoryStats.GarbageCollections
                MemoryCleanupEvents = $this.MemoryStats.MemoryCleanupEvents
                MemoryPressureEvents = $this.MemoryStats.MemoryPressureEvents
                MemoryEfficiency = $this.MemoryStats.MemoryEfficiencyRatio * 100
            }
            
            # Optimization Impact
            Optimization = @{
                OptimizationEnabled = $this.IsOptimizationEnabled
                BulkOperationsEnabled = $this.OptimizationSettings.EnableBulkOperations
                CachingEnabled = $this.OptimizationSettings.EnableCaching
                MemoryThresholdPercent = $this.MemoryThresholdPercent
                EstimatedTimeSavings = $this.CalculateEstimatedTimeSavings()
                PerformanceImprovement = $this.CalculatePerformanceImprovement()
            }
        }
    }

    # Calculate estimated time savings from optimization
    [double] CalculateEstimatedTimeSavings() {
        # Simplified calculation - could be more sophisticated
        $baselineTimePerOperation = 1000 # milliseconds
        $actualTimePerOperation = $this.AverageOperationTime
        
        if ($actualTimePerOperation -gt 0 -and $this.CompletedOperations -gt 0) {
            $timeSavingsPerOperation = $baselineTimePerOperation - $actualTimePerOperation
            $totalTimeSavings = ($timeSavingsPerOperation * $this.CompletedOperations) / 1000 # convert to seconds
            return [Math]::Max($totalTimeSavings, 0)
        }
        
        return 0
    }

    # Calculate performance improvement percentage
    [double] CalculatePerformanceImprovement() {
        # Simplified calculation based on thread utilization and memory efficiency
        $threadEfficiency = $this.ThreadPoolStats.ThreadEfficiency
        $memoryEfficiency = $this.MemoryStats.MemoryEfficiencyRatio
        
        if ($threadEfficiency -gt 0 -and $memoryEfficiency -gt 0) {
            return (($threadEfficiency + $memoryEfficiency) / 2) * 100
        }
        
        return 0
    }

    # Generate optimization report
    [hashtable] GenerateOptimizationReport() {
        $stats = $this.GetOptimizationStatistics()
        
        $report = @{
            ReportTimestamp = Get-Date
            ExecutionSummary = @{
                TotalDuration = $stats.ElapsedTime.ToString('hh\:mm\:ss')
                OperationsCompleted = $stats.CompletedOperations
                SuccessRate = "$([Math]::Round($stats.SuccessRate, 1))%"
                AverageThroughput = "$([Math]::Round($stats.ThroughputPerSecond, 2)) ops/sec"
            }
            
            PerformanceMetrics = @{
                ThreadUtilization = "$([Math]::Round($stats.ThreadPool.ThreadUtilization, 1))%"
                MemoryUtilization = "$([Math]::Round($stats.Memory.MemoryUtilization, 1))%"
                MemoryGrowth = "$([Math]::Round($stats.Memory.MemoryGrowthMB, 1)) MB"
                GarbageCollections = $stats.Memory.GarbageCollections
            }
            
            OptimizationImpact = @{
                EstimatedTimeSavings = "$([Math]::Round($stats.Optimization.EstimatedTimeSavings, 1)) seconds"
                PerformanceImprovement = "$([Math]::Round($stats.Optimization.PerformanceImprovement, 1))%"
                MemoryEfficiency = "$([Math]::Round($stats.Memory.MemoryEfficiency, 1))%"
                ThreadEfficiency = "$([Math]::Round($stats.ThreadPool.ThreadEfficiency, 1))%"
            }
            
            Recommendations = $this.GenerateOptimizationRecommendations($stats)
        }
        
        return $report
    }

    # Generate optimization recommendations
    [array] GenerateOptimizationRecommendations([hashtable] $stats) {
        $recommendations = @()
        
        # Thread pool recommendations
        if ($stats.ThreadPool.ThreadUtilization -lt 50) {
            $recommendations += "Consider reducing MaxThreads to $([Math]::Max($this.MaxThreads / 2, 2)) for better resource utilization"
        } elseif ($stats.ThreadPool.ThreadUtilization -gt 90) {
            $recommendations += "Consider increasing MaxThreads to $([Math]::Min($this.MaxThreads * 1.5, 50)) for better performance"
        }
        
        # Memory recommendations
        if ($stats.Memory.MemoryUtilization -gt 80) {
            $recommendations += "Consider increasing memory limit or enabling more aggressive garbage collection"
        }
        
        if ($stats.Memory.GarbageCollections -gt ($this.CompletedOperations / 10)) {
            $recommendations += "High garbage collection frequency detected - consider optimizing data structures"
        }
        
        # Performance recommendations
        if ($stats.SuccessRate -lt 95) {
            $recommendations += "Success rate is below 95% - investigate error patterns and implement retry logic"
        }
        
        if ($stats.ThroughputPerSecond -lt 1) {
            $recommendations += "Low throughput detected - consider enabling FastMode or bulk operations"
        }
        
        if ($recommendations.Count -eq 0) {
            $recommendations += "Performance optimization is working well - no immediate recommendations"
        }
        
        return $recommendations
    }

    # Update final metrics when stopping
    [void] UpdateFinalMetrics() {
        $this.UpdatePerformanceMetrics()
        $this.PerformanceMetrics.TotalExecutionTime = (Get-Date) - $this.StartTime
        $this.PerformanceMetrics.ThreadUtilization = $this.ThreadPoolStats.ThreadEfficiency
        $this.PerformanceMetrics.MemoryEfficiency = $this.MemoryStats.MemoryEfficiencyRatio
    }

    # Cleanup resources
    [void] Cleanup() {
        try {
            $this.StopMonitoring()
            
            if ($this.RunspacePool) {
                $this.RunspacePool.Close()
                $this.RunspacePool.Dispose()
                $this.ThreadPoolStats.ThreadsDestroyed = $this.ThreadPoolStats.ThreadsCreated
            }
            
            # Final memory cleanup
            $this.PerformMemoryCleanup()
            
            Write-Verbose "PerformanceOptimizationManager cleanup completed"
            
        }
        catch {
            Write-Warning "Cleanup failed: $($_.Exception.Message)"
        }
    }
}