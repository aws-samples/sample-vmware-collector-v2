#
# AdvancedMemoryManager.ps1 - Advanced memory management and garbage collection
#
# Implements automatic memory cleanup procedures, memory pressure detection and response,
# and comprehensive memory usage monitoring and reporting for large-scale VM data collection.
#

# Import required interfaces
if (Test-Path "$PSScriptRoot\Interfaces.ps1") {
    . "$PSScriptRoot\Interfaces.ps1"
}

class AdvancedMemoryManager {
    [ILogger] $Logger
    [hashtable] $MemorySettings
    [hashtable] $MemoryStatistics
    [hashtable] $MemoryThresholds
    [hashtable] $CleanupStrategies
    [System.Timers.Timer] $MonitoringTimer
    [bool] $IsMonitoring
    [int] $ProcessId
    [System.Diagnostics.Process] $CurrentProcess
    
    # Constructor
    AdvancedMemoryManager([ILogger] $logger) {
        $this.Logger = $logger
        $this.ProcessId = $global:PID
        $this.CurrentProcess = Get-Process -Id $this.ProcessId
        $this.IsMonitoring = $false
        
        # Memory management settings
        $this.MemorySettings = @{
            MaxMemoryMB = 2048  # Default 2GB limit
            WarningThresholdPercent = 75  # Warning at 75% of max
            CriticalThresholdPercent = 90  # Critical at 90% of max
            AutoCleanupEnabled = $true
            MonitoringIntervalSeconds = 30
            ForceGCOnCleanup = $true
            EnableMemoryPressureDetection = $true
            EnableProactiveCleanup = $true
            CleanupOnBatchCompletion = $true
            MaxObjectCacheSize = 10000
            EnableDetailedLogging = $false
        }
        
        # Memory thresholds in bytes
        $this.MemoryThresholds = @{
            MaxMemoryBytes = $this.MemorySettings.MaxMemoryMB * 1MB
            WarningThresholdBytes = ($this.MemorySettings.MaxMemoryMB * $this.MemorySettings.WarningThresholdPercent / 100) * 1MB
            CriticalThresholdBytes = ($this.MemorySettings.MaxMemoryMB * $this.MemorySettings.CriticalThresholdPercent / 100) * 1MB
        }
        
        # Memory statistics tracking
        $this.MemoryStatistics = @{
            PeakMemoryMB = 0
            CurrentMemoryMB = 0
            TotalCleanupOperations = 0
            TotalGCCollections = 0
            TotalMemoryFreedMB = 0
            WarningEvents = 0
            CriticalEvents = 0
            LastCleanupTime = $null
            MonitoringStartTime = $null
            MemoryPressureEvents = 0
            ProactiveCleanups = 0
            BatchCleanups = 0
        }
        
        # Cleanup strategies configuration
        $this.CleanupStrategies = @{
            ClearVariables = $true
            ClearHashtables = $true
            ClearArrays = $true
            ClearPSObjects = $true
            ClearEventLogs = $false
            ForceGarbageCollection = $true
            CompactLargeObjectHeap = $true
            ClearUnusedModules = $false
            OptimizeStringPool = $true
            ClearTempFiles = $false
        }
        
        $this.Logger.WriteInformation("AdvancedMemoryManager initialized with max memory: $($this.MemorySettings.MaxMemoryMB) MB, monitoring interval: $($this.MemorySettings.MonitoringIntervalSeconds)s")
    }
    
    # Start memory monitoring
    [void] StartMemoryMonitoring() {
        try {
            if ($this.IsMonitoring) {
                $this.Logger.WriteWarning("Memory monitoring is already running")
                return
            }
            
            # Create and configure timer
            $this.MonitoringTimer = New-Object System.Timers.Timer
            $this.MonitoringTimer.Interval = $this.MemorySettings.MonitoringIntervalSeconds * 1000
            $this.MonitoringTimer.AutoReset = $true
            
            # Register event handler
            Register-ObjectEvent -InputObject $this.MonitoringTimer -EventName Elapsed -Action {
                try {
                    $memoryManager = $Event.MessageData
                    $memoryManager.PerformMemoryCheck()
                } catch {
                    Write-Warning "Memory monitoring error: $($_.Exception.Message)"
                }
            } -MessageData $this | Out-Null
            
            # Start monitoring
            $this.MonitoringTimer.Start()
            $this.IsMonitoring = $true
            $this.MemoryStatistics.MonitoringStartTime = Get-Date
            
            $this.Logger.WriteInformation("Memory monitoring started with $($this.MemorySettings.MonitoringIntervalSeconds)s interval")
            
        } catch {
            $this.Logger.WriteError("Failed to start memory monitoring: $($_.Exception.Message)", $_.Exception)
        }
    }
    
    # Stop memory monitoring
    [void] StopMemoryMonitoring() {
        try {
            if (-not $this.IsMonitoring) {
                return
            }
            
            if ($this.MonitoringTimer) {
                $this.MonitoringTimer.Stop()
                $this.MonitoringTimer.Dispose()
                $this.MonitoringTimer = $null
            }
            
            # Unregister event handlers
            Get-EventSubscriber | Where-Object { $_.SourceObject -eq $this.MonitoringTimer } | Unregister-Event
            
            $this.IsMonitoring = $false
            
            $monitoringDuration = if ($this.MemoryStatistics.MonitoringStartTime) {
                (Get-Date) - $this.MemoryStatistics.MonitoringStartTime
            } else {
                [TimeSpan]::Zero
            }
            
            $this.Logger.WriteInformation("Memory monitoring stopped after $($monitoringDuration.TotalMinutes.ToString('F1')) minutes")
            
        } catch {
            $this.Logger.WriteError("Failed to stop memory monitoring: $($_.Exception.Message)", $_.Exception)
        }
    }
    
    # Perform memory check and take action if needed
    [void] PerformMemoryCheck() {
        try {
            $currentMemory = $this.GetCurrentMemoryUsage()
            $this.MemoryStatistics.CurrentMemoryMB = [Math]::Round($currentMemory.WorkingSetMB, 2)
            
            # Update peak memory
            if ($this.MemoryStatistics.CurrentMemoryMB -gt $this.MemoryStatistics.PeakMemoryMB) {
                $this.MemoryStatistics.PeakMemoryMB = $this.MemoryStatistics.CurrentMemoryMB
            }
            
            # Check thresholds and take action
            if ($currentMemory.WorkingSetBytes -gt $this.MemoryThresholds.CriticalThresholdBytes) {
                $this.HandleCriticalMemoryPressure($currentMemory)
            } elseif ($currentMemory.WorkingSetBytes -gt $this.MemoryThresholds.WarningThresholdBytes) {
                $this.HandleMemoryWarning($currentMemory)
            }
            
            # Proactive cleanup if enabled
            if ($this.MemorySettings.EnableProactiveCleanup -and $this.ShouldPerformProactiveCleanup($currentMemory)) {
                $this.PerformProactiveCleanup($currentMemory)
            }
            
            # Detailed logging if enabled
            if ($this.MemorySettings.EnableDetailedLogging) {
                $this.Logger.WriteDebug("Memory check: Current=$($this.MemoryStatistics.CurrentMemoryMB) MB, Peak=$($this.MemoryStatistics.PeakMemoryMB) MB, Limit=$($this.MemorySettings.MaxMemoryMB) MB")
            }
            
        } catch {
            $this.Logger.WriteError("Memory check failed: $($_.Exception.Message)", $_.Exception)
        }
    }
    
    # Get current memory usage information
    [hashtable] GetCurrentMemoryUsage() {
        try {
            # Refresh process information
            $this.CurrentProcess.Refresh()
            
            $workingSetBytes = $this.CurrentProcess.WorkingSet64
            $privateMemoryBytes = $this.CurrentProcess.PrivateMemorySize64
            $virtualMemoryBytes = $this.CurrentProcess.VirtualMemorySize64
            
            # Get GC information
            $gen0Collections = [System.GC]::CollectionCount(0)
            $gen1Collections = [System.GC]::CollectionCount(1)
            $gen2Collections = [System.GC]::CollectionCount(2)
            $totalMemory = [System.GC]::GetTotalMemory($false)
            
            return @{
                WorkingSetBytes = $workingSetBytes
                WorkingSetMB = $workingSetBytes / 1MB
                PrivateMemoryBytes = $privateMemoryBytes
                PrivateMemoryMB = $privateMemoryBytes / 1MB
                VirtualMemoryBytes = $virtualMemoryBytes
                VirtualMemoryMB = $virtualMemoryBytes / 1MB
                GCTotalMemoryBytes = $totalMemory
                GCTotalMemoryMB = $totalMemory / 1MB
                Gen0Collections = $gen0Collections
                Gen1Collections = $gen1Collections
                Gen2Collections = $gen2Collections
                Timestamp = Get-Date
            }
            
        } catch {
            $this.Logger.WriteError("Failed to get memory usage: $($_.Exception.Message)", $_.Exception)
            return @{
                WorkingSetBytes = 0
                WorkingSetMB = 0
                PrivateMemoryBytes = 0
                PrivateMemoryMB = 0
                VirtualMemoryBytes = 0
                VirtualMemoryMB = 0
                GCTotalMemoryBytes = 0
                GCTotalMemoryMB = 0
                Gen0Collections = 0
                Gen1Collections = 0
                Gen2Collections = 0
                Timestamp = Get-Date
            }
        }
    }
    
    # Handle critical memory pressure
    [void] HandleCriticalMemoryPressure([hashtable] $memoryInfo) {
        try {
            $this.MemoryStatistics.CriticalEvents++
            $this.Logger.WriteWarning("CRITICAL: Memory usage at $($memoryInfo.WorkingSetMB.ToString('F1')) MB (limit: $($this.MemorySettings.MaxMemoryMB) MB)")
            
            if ($this.MemorySettings.AutoCleanupEnabled) {
                $this.Logger.WriteInformation("Performing emergency memory cleanup...")
                $cleanupResult = $this.PerformEmergencyCleanup()
                
                $this.Logger.WriteInformation("Emergency cleanup completed: Freed $($cleanupResult.MemoryFreedMB.ToString('F1')) MB in $($cleanupResult.CleanupTimeMs) ms")
            }
            
            # Check if we're still over the limit
            $postCleanupMemory = $this.GetCurrentMemoryUsage()
            if ($postCleanupMemory.WorkingSetBytes -gt $this.MemoryThresholds.MaxMemoryBytes) {
                $this.Logger.WriteError("Memory usage still critical after cleanup: $($postCleanupMemory.WorkingSetMB.ToString('F1')) MB")
                
                # Consider more aggressive measures
                if ($this.CleanupStrategies.ClearUnusedModules) {
                    $this.ClearUnusedModules()
                }
            }
            
        } catch {
            $this.Logger.WriteError("Failed to handle critical memory pressure: $($_.Exception.Message)", $_.Exception)
        }
    }
    
    # Handle memory warning
    [void] HandleMemoryWarning([hashtable] $memoryInfo) {
        try {
            $this.MemoryStatistics.WarningEvents++
            
            if ($this.MemorySettings.EnableDetailedLogging) {
                $this.Logger.WriteWarning("Memory usage warning: $($memoryInfo.WorkingSetMB.ToString('F1')) MB (warning threshold: $($this.MemoryThresholds.WarningThresholdBytes / 1MB) MB)")
            }
            
            if ($this.MemorySettings.AutoCleanupEnabled) {
                $cleanupResult = $this.PerformStandardCleanup()
                
                if ($this.MemorySettings.EnableDetailedLogging) {
                    $this.Logger.WriteDebug("Standard cleanup completed: Freed $($cleanupResult.MemoryFreedMB.ToString('F1')) MB")
                }
            }
            
        } catch {
            $this.Logger.WriteError("Failed to handle memory warning: $($_.Exception.Message)", $_.Exception)
        }
    }
    
    # Determine if proactive cleanup should be performed
    [bool] ShouldPerformProactiveCleanup([hashtable] $memoryInfo) {
        try {
            # Perform proactive cleanup if:
            # 1. Memory usage is above 50% of limit
            # 2. It's been more than 5 minutes since last cleanup
            # 3. Memory growth rate is concerning
            
            $memoryUsagePercent = ($memoryInfo.WorkingSetBytes / $this.MemoryThresholds.MaxMemoryBytes) * 100
            
            if ($memoryUsagePercent -lt 50) {
                return $false
            }
            
            if ($this.MemoryStatistics.LastCleanupTime) {
                $timeSinceLastCleanup = (Get-Date) - $this.MemoryStatistics.LastCleanupTime
                if ($timeSinceLastCleanup.TotalMinutes -lt 5) {
                    return $false
                }
            }
            
            return $true
            
        } catch {
            return $false
        }
    }
    
    # Perform proactive cleanup
    [void] PerformProactiveCleanup([hashtable] $memoryInfo) {
        try {
            $this.MemoryStatistics.ProactiveCleanups++
            
            if ($this.MemorySettings.EnableDetailedLogging) {
                $this.Logger.WriteDebug("Performing proactive memory cleanup at $($memoryInfo.WorkingSetMB.ToString('F1')) MB")
            }
            
            $cleanupResult = $this.PerformLightweightCleanup()
            
            if ($this.MemorySettings.EnableDetailedLogging) {
                $this.Logger.WriteDebug("Proactive cleanup completed: Freed $($cleanupResult.MemoryFreedMB.ToString('F1')) MB")
            }
            
        } catch {
            $this.Logger.WriteError("Proactive cleanup failed: $($_.Exception.Message)", $_.Exception)
        }
    }
    
    # Perform emergency cleanup (most aggressive)
    [hashtable] PerformEmergencyCleanup() {
        $startTime = Get-Date
        $memoryBefore = $this.GetCurrentMemoryUsage()
        
        try {
            $this.Logger.WriteInformation("Starting emergency memory cleanup...")
            
            # Clear all possible caches and collections
            if ($this.CleanupStrategies.ClearHashtables) {
                $this.ClearHashtableCaches()
            }
            
            if ($this.CleanupStrategies.ClearArrays) {
                $this.ClearArrayCaches()
            }
            
            if ($this.CleanupStrategies.ClearPSObjects) {
                $this.ClearPSObjectCaches()
            }
            
            if ($this.CleanupStrategies.OptimizeStringPool) {
                $this.OptimizeStringPool()
            }
            
            # Force multiple garbage collections
            if ($this.CleanupStrategies.ForceGarbageCollection) {
                for ($i = 0; $i -lt 3; $i++) {
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                    [System.GC]::Collect()
                }
                
                if ($this.CleanupStrategies.CompactLargeObjectHeap) {
                    [System.GC]::Collect(2, [System.GCCollectionMode]::Forced, $true, $true)
                }
            }
            
            $memoryAfter = $this.GetCurrentMemoryUsage()
            $endTime = Get-Date
            
            $memoryFreed = $memoryBefore.WorkingSetMB - $memoryAfter.WorkingSetMB
            $cleanupTime = ($endTime - $startTime).TotalMilliseconds
            
            $this.MemoryStatistics.TotalCleanupOperations++
            $this.MemoryStatistics.TotalMemoryFreedMB += $memoryFreed
            $this.MemoryStatistics.LastCleanupTime = $endTime
            
            return @{
                MemoryFreedMB = [Math]::Round($memoryFreed, 2)
                CleanupTimeMs = [Math]::Round($cleanupTime, 0)
                MemoryBefore = $memoryBefore.WorkingSetMB
                MemoryAfter = $memoryAfter.WorkingSetMB
                CleanupType = 'Emergency'
            }
            
        } catch {
            $this.Logger.WriteError("Emergency cleanup failed: $($_.Exception.Message)", $_.Exception)
            return @{
                MemoryFreedMB = 0.0
                CleanupTimeMs = 0
                MemoryBefore = $memoryBefore.WorkingSetMB
                MemoryAfter = $memoryBefore.WorkingSetMB
                CleanupType = 'Emergency (Failed)'
            }
        }
    }
    
    # Perform standard cleanup
    [hashtable] PerformStandardCleanup() {
        $startTime = Get-Date
        $memoryBefore = $this.GetCurrentMemoryUsage()
        
        try {
            # Clear caches selectively
            if ($this.CleanupStrategies.ClearHashtables) {
                $this.ClearHashtableCaches()
            }
            
            if ($this.CleanupStrategies.ClearArrays) {
                $this.ClearArrayCaches()
            }
            
            # Force garbage collection
            if ($this.CleanupStrategies.ForceGarbageCollection) {
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
            }
            
            $memoryAfter = $this.GetCurrentMemoryUsage()
            $endTime = Get-Date
            
            $memoryFreed = $memoryBefore.WorkingSetMB - $memoryAfter.WorkingSetMB
            $cleanupTime = ($endTime - $startTime).TotalMilliseconds
            
            $this.MemoryStatistics.TotalCleanupOperations++
            $this.MemoryStatistics.TotalMemoryFreedMB += $memoryFreed
            $this.MemoryStatistics.LastCleanupTime = $endTime
            
            return @{
                MemoryFreedMB = [Math]::Round($memoryFreed, 2)
                CleanupTimeMs = [Math]::Round($cleanupTime, 0)
                MemoryBefore = $memoryBefore.WorkingSetMB
                MemoryAfter = $memoryAfter.WorkingSetMB
                CleanupType = 'Standard'
            }
            
        } catch {
            $this.Logger.WriteError("Standard cleanup failed: $($_.Exception.Message)", $_.Exception)
            return @{
                MemoryFreedMB = 0.0
                CleanupTimeMs = 0
                MemoryBefore = $memoryBefore.WorkingSetMB
                MemoryAfter = $memoryBefore.WorkingSetMB
                CleanupType = 'Standard (Failed)'
            }
        }
    }
    
    # Perform lightweight cleanup
    [hashtable] PerformLightweightCleanup() {
        $startTime = Get-Date
        $memoryBefore = $this.GetCurrentMemoryUsage()
        
        try {
            # Light cleanup - just GC
            if ($this.CleanupStrategies.ForceGarbageCollection) {
                [System.GC]::Collect(0, [System.GCCollectionMode]::Optimized)
            }
            
            $memoryAfter = $this.GetCurrentMemoryUsage()
            $endTime = Get-Date
            
            $memoryFreed = $memoryBefore.WorkingSetMB - $memoryAfter.WorkingSetMB
            $cleanupTime = ($endTime - $startTime).TotalMilliseconds
            
            $this.MemoryStatistics.TotalCleanupOperations++
            $this.MemoryStatistics.TotalMemoryFreedMB += $memoryFreed
            $this.MemoryStatistics.LastCleanupTime = $endTime
            
            return @{
                MemoryFreedMB = [Math]::Round($memoryFreed, 2)
                CleanupTimeMs = [Math]::Round($cleanupTime, 0)
                MemoryBefore = $memoryBefore.WorkingSetMB
                MemoryAfter = $memoryAfter.WorkingSetMB
                CleanupType = 'Lightweight'
            }
            
        } catch {
            $this.Logger.WriteError("Lightweight cleanup failed: $($_.Exception.Message)", $_.Exception)
            return @{
                MemoryFreedMB = 0.0
                CleanupTimeMs = 0
                MemoryBefore = $memoryBefore.WorkingSetMB
                MemoryAfter = $memoryBefore.WorkingSetMB
                CleanupType = 'Lightweight (Failed)'
            }
        }
    }
    
    # Perform batch completion cleanup
    [hashtable] PerformBatchCompletionCleanup() {
        try {
            $this.MemoryStatistics.BatchCleanups++
            
            if ($this.MemorySettings.EnableDetailedLogging) {
                $this.Logger.WriteDebug("Performing batch completion cleanup")
            }
            
            return $this.PerformStandardCleanup()
            
        } catch {
            $this.Logger.WriteError("Batch completion cleanup failed: $($_.Exception.Message)", $_.Exception)
            return @{
                MemoryFreedMB = 0.0
                CleanupTimeMs = 0
                CleanupType = 'Batch (Failed)'
            }
        }
    }
    
    # Clear hashtable caches
    [void] ClearHashtableCaches() {
        try {
            # This would be implemented to clear specific hashtable caches
            # For now, just trigger GC on hashtables
            $this.Logger.WriteDebug("Clearing hashtable caches")
            
            # Clear known cache variables if they exist in the calling scope
            $cacheVariables = @('InfrastructureCache', 'StatisticalCache', 'PerformanceCache', 'VMDataCache')
            
            foreach ($varName in $cacheVariables) {
                if (Get-Variable -Name $varName -Scope Global -ErrorAction SilentlyContinue) {
                    $var = Get-Variable -Name $varName -Scope Global
                    if ($var.Value -is [hashtable]) {
                        $var.Value.Clear()
                        $this.Logger.WriteDebug("Cleared cache: $varName")
                    }
                }
            }
            
        } catch {
            $this.Logger.WriteDebug("Hashtable cache clearing failed: $($_.Exception.Message)")
        }
    }
    
    # Clear array caches
    [void] ClearArrayCaches() {
        try {
            $this.Logger.WriteDebug("Clearing array caches")
            
            # Clear known array variables if they exist
            $arrayVariables = @('VMDataArray', 'PerformanceDataArray', 'ProcessingQueue')
            
            foreach ($varName in $arrayVariables) {
                if (Get-Variable -Name $varName -Scope Global -ErrorAction SilentlyContinue) {
                    $var = Get-Variable -Name $varName -Scope Global
                    if ($var.Value -is [array]) {
                        $var.Value = @()
                        $this.Logger.WriteDebug("Cleared array: $varName")
                    }
                }
            }
            
        } catch {
            $this.Logger.WriteDebug("Array cache clearing failed: $($_.Exception.Message)")
        }
    }
    
    # Clear PSObject caches
    [void] ClearPSObjectCaches() {
        try {
            $this.Logger.WriteDebug("Clearing PSObject caches")
            
            # Force cleanup of PSObject references
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            
        } catch {
            $this.Logger.WriteDebug("PSObject cache clearing failed: $($_.Exception.Message)")
        }
    }
    
    # Optimize string pool
    [void] OptimizeStringPool() {
        try {
            $this.Logger.WriteDebug("Optimizing string pool")
            
            # Force string interning cleanup
            [System.GC]::Collect(2, [System.GCCollectionMode]::Forced)
            
        } catch {
            $this.Logger.WriteDebug("String pool optimization failed: $($_.Exception.Message)")
        }
    }
    
    # Clear unused modules
    [void] ClearUnusedModules() {
        try {
            $this.Logger.WriteDebug("Clearing unused modules")
            
            # Get list of loaded modules
            $loadedModules = Get-Module
            
            # Remove modules that are not essential (be very careful here)
            $nonEssentialModules = $loadedModules | Where-Object { 
                $_.Name -notmatch '^(Microsoft\.|System\.|VMware\.|PowerCLI)' -and
                $_.Name -ne 'VMwareCollector'
            }
            
            foreach ($module in $nonEssentialModules) {
                try {
                    Remove-Module -Name $module.Name -Force -ErrorAction SilentlyContinue
                    $this.Logger.WriteDebug("Removed module: $($module.Name)")
                } catch {
                    # Ignore errors when removing modules
                }
            }
            
        } catch {
            $this.Logger.WriteDebug("Module clearing failed: $($_.Exception.Message)")
        }
    }
    
    # Get comprehensive memory report
    [hashtable] GetMemoryReport() {
        try {
            $currentMemory = $this.GetCurrentMemoryUsage()
            
            $monitoringDuration = if ($this.MemoryStatistics.MonitoringStartTime) {
                (Get-Date) - $this.MemoryStatistics.MonitoringStartTime
            } else {
                [TimeSpan]::Zero
            }
            
            return @{
                CurrentMemory = $currentMemory
                Statistics = $this.MemoryStatistics.Clone()
                Settings = $this.MemorySettings.Clone()
                Thresholds = @{
                    MaxMemoryMB = $this.MemorySettings.MaxMemoryMB
                    WarningThresholdMB = $this.MemoryThresholds.WarningThresholdBytes / 1MB
                    CriticalThresholdMB = $this.MemoryThresholds.CriticalThresholdBytes / 1MB
                }
                MonitoringStatus = @{
                    IsMonitoring = $this.IsMonitoring
                    MonitoringDuration = $monitoringDuration
                    MonitoringInterval = $this.MemorySettings.MonitoringIntervalSeconds
                }
                MemoryEfficiency = @{
                    MemoryUtilizationPercent = [Math]::Round(($currentMemory.WorkingSetMB / $this.MemorySettings.MaxMemoryMB) * 100, 2)
                    AverageMemoryFreedPerCleanup = if ($this.MemoryStatistics.TotalCleanupOperations -gt 0) { 
                        [Math]::Round($this.MemoryStatistics.TotalMemoryFreedMB / $this.MemoryStatistics.TotalCleanupOperations, 2) 
                    } else { 0.0 }
                    CleanupEffectiveness = if ($this.MemoryStatistics.TotalCleanupOperations -gt 0) { 'Active' } else { 'Inactive' }
                }
                Recommendations = $this.GetMemoryRecommendations($currentMemory)
            }
            
        } catch {
            $this.Logger.WriteError("Failed to generate memory report: $($_.Exception.Message)", $_.Exception)
            return @{
                CurrentMemory = @{ WorkingSetMB = 0; Error = $_.Exception.Message }
                Statistics = $this.MemoryStatistics
                Error = "Report generation failed"
            }
        }
    }
    
    # Get memory optimization recommendations
    [array] GetMemoryRecommendations([hashtable] $currentMemory) {
        $recommendations = @()
        
        try {
            $memoryUsagePercent = ($currentMemory.WorkingSetMB / $this.MemorySettings.MaxMemoryMB) * 100
            
            if ($memoryUsagePercent -gt 80) {
                $recommendations += "Consider increasing memory limit (currently at $($memoryUsagePercent.ToString('F1'))%)"
            }
            
            if ($this.MemoryStatistics.CriticalEvents -gt 5) {
                $recommendations += "Frequent critical memory events detected - consider optimizing data processing batch sizes"
            }
            
            if ($this.MemoryStatistics.TotalCleanupOperations -gt 0) {
                $avgFreed = $this.MemoryStatistics.TotalMemoryFreedMB / $this.MemoryStatistics.TotalCleanupOperations
                if ($avgFreed -lt 10) {
                    $recommendations += "Low cleanup effectiveness - consider reviewing data retention strategies"
                }
            }
            
            if (-not $this.IsMonitoring) {
                $recommendations += "Enable memory monitoring for better memory management"
            }
            
            if ($this.MemorySettings.MonitoringIntervalSeconds -gt 60) {
                $recommendations += "Consider reducing monitoring interval for more responsive memory management"
            }
            
            return $recommendations
            
        } catch {
            return @("Unable to generate recommendations: $($_.Exception.Message)")
        }
    }
    
    # Configure memory management settings
    [void] ConfigureMemorySettings([hashtable] $settings) {
        foreach ($key in $settings.Keys) {
            if ($this.MemorySettings.ContainsKey($key)) {
                $oldValue = $this.MemorySettings[$key]
                $this.MemorySettings[$key] = $settings[$key]
                $this.Logger.WriteDebug("Updated memory setting: $key = $($settings[$key]) (was: $oldValue)")
                
                # Update thresholds if memory limits changed
                if ($key -eq 'MaxMemoryMB') {
                    $this.UpdateMemoryThresholds()
                }
            }
        }
        
        $this.Logger.WriteInformation("Memory management settings updated: $($settings.Keys -join ', ')")
    }
    
    # Update memory thresholds based on current settings
    [void] UpdateMemoryThresholds() {
        $this.MemoryThresholds.MaxMemoryBytes = $this.MemorySettings.MaxMemoryMB * 1MB
        $this.MemoryThresholds.WarningThresholdBytes = ($this.MemorySettings.MaxMemoryMB * $this.MemorySettings.WarningThresholdPercent / 100) * 1MB
        $this.MemoryThresholds.CriticalThresholdBytes = ($this.MemorySettings.MaxMemoryMB * $this.MemorySettings.CriticalThresholdPercent / 100) * 1MB
        
        $this.Logger.WriteDebug("Updated memory thresholds: Max=$($this.MemorySettings.MaxMemoryMB)MB, Warning=$($this.MemoryThresholds.WarningThresholdBytes/1MB)MB, Critical=$($this.MemoryThresholds.CriticalThresholdBytes/1MB)MB")
    }
    
    # Dispose and cleanup
    [void] Dispose() {
        try {
            $this.StopMemoryMonitoring()
            
            if ($this.CurrentProcess) {
                $this.CurrentProcess.Dispose()
            }
            
            $this.Logger.WriteInformation("AdvancedMemoryManager disposed")
            
        } catch {
            $this.Logger.WriteError("Failed to dispose AdvancedMemoryManager: $($_.Exception.Message)", $_.Exception)
        }
    }
}