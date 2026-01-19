#
# ParallelProcessingEngine.ps1 - Advanced parallel processing with dynamic load balancing
#
# Implements intelligent parallel processing with dynamic thread allocation, load balancing,
# and adaptive batch sizing for optimal performance across different environment sizes.
#

class ParallelProcessingEngine {
    [hashtable] $ProcessingConfiguration
    [hashtable] $ThreadPoolManager
    [hashtable] $LoadBalancer
    [hashtable] $PerformanceMetrics
    [ILogger] $Logger
    [System.Collections.Concurrent.ConcurrentQueue[object]] $WorkQueue
    [System.Collections.Generic.List[System.Management.Automation.PowerShell]] $ActiveJobs
    [System.Management.Automation.Runspaces.RunspacePool] $RunspacePool
    [bool] $IsProcessing
    [int] $OptimalThreadCount
    
    # Constructor
    ParallelProcessingEngine([ILogger] $logger) {
        $this.Logger = $logger
        $this.WorkQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $this.ActiveJobs = [System.Collections.Generic.List[System.Management.Automation.PowerShell]]::new()
        $this.IsProcessing = $false
        
        $this.ProcessingConfiguration = @{
            MinThreads = 2
            MaxThreads = 50
            DefaultThreads = 10
            AdaptiveThreading = $true
            DynamicBatchSizing = $true
            LoadBalancingEnabled = $true
            PerformanceMonitoring = $true
            ThreadScalingFactor = 1.5
            BatchSizeMin = 10
            BatchSizeMax = 500
            BatchSizeDefault = 100
        }
        
        $this.ThreadPoolManager = @{
            CurrentThreadCount = 0
            OptimalThreadCount = $this.ProcessingConfiguration.DefaultThreads
            ThreadUtilization = 0.0
            ThreadEfficiency = 0.0
            LastOptimizationTime = Get-Date
            OptimizationInterval = 60  # seconds
        }
        
        $this.LoadBalancer = @{
            Algorithm = 'Dynamic'  # Static, RoundRobin, Dynamic, WorkStealing
            WorkDistribution = @{}
            ThreadWorkloads = @{}
            RebalancingThreshold = 0.3
            LastRebalanceTime = Get-Date
        }
        
        $this.PerformanceMetrics = @{
            TotalItemsProcessed = 0
            TotalProcessingTime = [TimeSpan]::Zero
            AverageItemProcessingTime = 0.0
            ThroughputPerSecond = 0.0
            ThreadScalingEvents = 0
            LoadRebalancingEvents = 0
            OptimizationEvents = 0
            ErrorRate = 0.0
        }
        
        $this.OptimalThreadCount = $this.CalculateOptimalThreadCount()
        $this.Logger.WriteInformation("ParallelProcessingEngine initialized with optimal thread count: $($this.OptimalThreadCount)")
    }
    
    # Calculate optimal thread count based on system resources
    [int] CalculateOptimalThreadCount() {
        try {
            $cpuCores = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum
            $logicalProcessors = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
            $availableMemoryGB = [Math]::Round((Get-CimInstance -ClassName Win32_OperatingSystem).TotalVisibleMemorySize / 1MB, 2)
            
            # Base calculation on CPU cores with memory consideration
            $baseThreadCount = [Math]::Min($logicalProcessors, $cpuCores * 2)
            
            # Adjust based on available memory (assume 100MB per thread)
            $memoryBasedThreads = [Math]::Floor($availableMemoryGB * 1024 / 100)
            
            # Take the minimum to avoid resource exhaustion
            $optimalThreads = [Math]::Min($baseThreadCount, $memoryBasedThreads)
            
            # Apply configuration constraints
            $optimalThreads = [Math]::Max($this.ProcessingConfiguration.MinThreads, 
                              [Math]::Min($this.ProcessingConfiguration.MaxThreads, $optimalThreads))
            
            $this.Logger.WriteInformation("System analysis: CPU Cores=$cpuCores, Logical Processors=$logicalProcessors, Memory=${availableMemoryGB}GB, Optimal Threads=$optimalThreads")
            
            return $optimalThreads
            
        } catch {
            $this.Logger.WriteWarning("Failed to calculate optimal thread count, using default: $($_.Exception.Message)")
            return $this.ProcessingConfiguration.DefaultThreads
        }
    }
    
    # Initialize runspace pool with optimal configuration
    [void] InitializeRunspacePool([int] $threadCount = -1) {
        try {
            if ($threadCount -le 0) {
                $threadCount = $this.OptimalThreadCount
            }
            
            # Dispose existing pool if it exists
            if ($this.RunspacePool) {
                $this.RunspacePool.Close()
                $this.RunspacePool.Dispose()
            }
            
            # Create new runspace pool
            $this.RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
                $this.ProcessingConfiguration.MinThreads,
                $threadCount
            )
            
            # Configure runspace pool
            $this.RunspacePool.ApartmentState = [System.Threading.ApartmentState]::MTA
            $this.RunspacePool.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
            
            $this.RunspacePool.Open()
            $this.ThreadPoolManager.CurrentThreadCount = $threadCount
            
            $this.Logger.WriteInformation("Initialized runspace pool with $threadCount threads")
            
        } catch {
            $this.Logger.WriteError("Failed to initialize runspace pool", $_.Exception)
            throw
        }
    }
    
    # Process items in parallel with dynamic optimization
    [array] ProcessItemsParallel([array] $items, [scriptblock] $processingScript, [hashtable] $parameters = @{}) {
        try {
            $this.IsProcessing = $true
            $startTime = Get-Date
            $results = @()
            
            $this.Logger.WriteInformation("Starting parallel processing of $($items.Count) items")
            
            # Initialize runspace pool if not already done
            if (-not $this.RunspacePool) {
                $this.InitializeRunspacePool()
            }
            
            # Determine optimal batch size
            $batchSize = $this.CalculateOptimalBatchSize($items.Count)
            $batches = $this.CreateBatches($items, $batchSize)
            
            $this.Logger.WriteInformation("Processing $($batches.Count) batches with batch size $batchSize using $($this.ThreadPoolManager.CurrentThreadCount) threads")
            
            # Process batches in parallel
            $jobs = @()
            foreach ($batch in $batches) {
                $job = $this.CreateParallelJob($batch, $processingScript, $parameters)
                $jobs += $job
                $this.ActiveJobs.Add($job)
            }
            
            # Monitor and collect results
            $results = $this.MonitorAndCollectResults($jobs)
            
            # Performance optimization
            if ($this.ProcessingConfiguration.AdaptiveThreading) {
                $this.OptimizeThreadCount($startTime)
            }
            
            $endTime = Get-Date
            $totalTime = $endTime - $startTime
            $this.UpdatePerformanceMetrics($items.Count, $totalTime)
            
            $this.Logger.WriteInformation("Parallel processing completed: $($items.Count) items in $($totalTime.TotalSeconds.ToString('F2')) seconds (Throughput: $($this.PerformanceMetrics.ThroughputPerSecond.ToString('F2')) items/sec)")
            
            return $results
            
        } catch {
            $this.Logger.WriteError("Parallel processing failed", $_.Exception)
            throw
        } finally {
            $this.IsProcessing = $false
            $this.CleanupActiveJobs()
        }
    }
    
    # Calculate optimal batch size based on item count and system resources
    [int] CalculateOptimalBatchSize([int] $itemCount) {
        if (-not $this.ProcessingConfiguration.DynamicBatchSizing) {
            return $this.ProcessingConfiguration.BatchSizeDefault
        }
        
        try {
            $threadCount = $this.ThreadPoolManager.CurrentThreadCount
            
            # Base calculation: items per thread with some overlap
            $baseBatchSize = [Math]::Ceiling($itemCount / ($threadCount * 2))
            
            # Apply constraints
            $optimalBatchSize = [Math]::Max($this.ProcessingConfiguration.BatchSizeMin,
                               [Math]::Min($this.ProcessingConfiguration.BatchSizeMax, $baseBatchSize))
            
            # Adjust based on historical performance
            if ($this.PerformanceMetrics.AverageItemProcessingTime -gt 0) {
                $estimatedBatchTime = $optimalBatchSize * $this.PerformanceMetrics.AverageItemProcessingTime
                
                # Target 30-60 seconds per batch
                if ($estimatedBatchTime -gt 60) {
                    $optimalBatchSize = [Math]::Max($this.ProcessingConfiguration.BatchSizeMin, 
                                       [Math]::Floor(60 / $this.PerformanceMetrics.AverageItemProcessingTime))
                } elseif ($estimatedBatchTime -lt 30) {
                    $optimalBatchSize = [Math]::Min($this.ProcessingConfiguration.BatchSizeMax,
                                       [Math]::Ceiling(30 / $this.PerformanceMetrics.AverageItemProcessingTime))
                }
            }
            
            $this.Logger.WriteDebug("Calculated optimal batch size: $optimalBatchSize (for $itemCount items with $threadCount threads)")
            
            return $optimalBatchSize
            
        } catch {
            $this.Logger.WriteWarning("Failed to calculate optimal batch size, using default")
            return $this.ProcessingConfiguration.BatchSizeDefault
        }
    }
    
    # Create batches from items
    [array] CreateBatches([array] $items, [int] $batchSize) {
        $batches = @()
        
        for ($i = 0; $i -lt $items.Count; $i += $batchSize) {
            $endIndex = [Math]::Min($i + $batchSize - 1, $items.Count - 1)
            $batch = $items[$i..$endIndex]
            $batches += ,$batch
        }
        
        return $batches
    }
    
    # Create parallel job for batch processing
    [System.Management.Automation.PowerShell] CreateParallelJob([array] $batch, [scriptblock] $processingScript, [hashtable] $parameters) {
        try {
            $job = [System.Management.Automation.PowerShell]::Create()
            $job.RunspacePool = $this.RunspacePool
            
            # Add the processing script
            $job.AddScript($processingScript) | Out-Null
            
            # Add parameters
            $job.AddParameter("Items", $batch) | Out-Null
            foreach ($key in $parameters.Keys) {
                $job.AddParameter($key, $parameters[$key]) | Out-Null
            }
            
            # Start the job
            $asyncResult = $job.BeginInvoke()
            
            # Store async result for monitoring
            $job | Add-Member -NotePropertyName "AsyncResult" -NotePropertyValue $asyncResult
            $job | Add-Member -NotePropertyName "StartTime" -NotePropertyValue (Get-Date)
            $job | Add-Member -NotePropertyName "BatchSize" -NotePropertyValue $batch.Count
            
            return $job
            
        } catch {
            $this.Logger.WriteError("Failed to create parallel job", $_.Exception)
            throw
        }
    }
    
    # Monitor jobs and collect results
    [array] MonitorAndCollectResults([array] $jobs) {
        $results = @()
        $completedJobs = @()
        
        try {
            while ($jobs.Count -gt $completedJobs.Count) {
                foreach ($job in $jobs) {
                    if ($job -in $completedJobs) { continue }
                    
                    if ($job.AsyncResult.IsCompleted) {
                        try {
                            $jobResults = $job.EndInvoke($job.AsyncResult)
                            $results += $jobResults
                            $completedJobs += $job
                            
                            # Update performance metrics
                            $jobDuration = (Get-Date) - $job.StartTime
                            $this.UpdateJobPerformanceMetrics($job.BatchSize, $jobDuration)
                            
                            $this.Logger.WriteDebug("Job completed: $($job.BatchSize) items in $($jobDuration.TotalSeconds.ToString('F2')) seconds")
                            
                        } catch {
                            $this.Logger.WriteError("Job execution failed", $_.Exception)
                            $completedJobs += $job
                            $this.PerformanceMetrics.ErrorRate++
                        }
                    }
                }
                
                # Brief pause to avoid busy waiting
                Start-Sleep -Milliseconds 100
                
                # Perform load balancing check
                if ($this.LoadBalancer.Algorithm -eq 'Dynamic') {
                    $this.CheckAndRebalanceLoad($jobs, $completedJobs)
                }
            }
            
            return $results
            
        } catch {
            $this.Logger.WriteError("Failed to monitor and collect results", $_.Exception)
            throw
        }
    }
    
    # Check and rebalance load across threads
    [void] CheckAndRebalanceLoad([array] $allJobs, [array] $completedJobs) {
        try {
            $currentTime = Get-Date
            $timeSinceLastRebalance = $currentTime - $this.LoadBalancer.LastRebalanceTime
            
            # Only rebalance every 30 seconds
            if ($timeSinceLastRebalance.TotalSeconds -lt 30) { return }
            
            $currentActiveJobs = $allJobs | Where-Object { $_ -notin $completedJobs }
            if ($currentActiveJobs.Count -eq 0) { return }
            
            # Calculate thread utilization
            $threadUtilization = $currentActiveJobs.Count / $this.ThreadPoolManager.CurrentThreadCount
            
            # Check if rebalancing is needed
            if ($threadUtilization -lt (1 - $this.LoadBalancer.RebalancingThreshold) -or 
                $threadUtilization -gt (1 + $this.LoadBalancer.RebalancingThreshold)) {
                
                $this.PerformLoadRebalancing($threadUtilization)
                $this.LoadBalancer.LastRebalanceTime = $currentTime
                $this.PerformanceMetrics.LoadRebalancingEvents++
            }
            
        } catch {
            $this.Logger.WriteDebug("Load balancing check failed: $($_.Exception.Message)")
        }
    }
    
    # Perform load rebalancing
    [void] PerformLoadRebalancing([double] $currentUtilization) {
        try {
            $optimalThreads = $this.ThreadPoolManager.CurrentThreadCount
            
            if ($currentUtilization -lt 0.5) {
                # Under-utilized - consider reducing threads
                $optimalThreads = [Math]::Max($this.ProcessingConfiguration.MinThreads,
                                 [Math]::Floor($this.ThreadPoolManager.CurrentThreadCount * 0.8))
            } elseif ($currentUtilization -gt 1.2) {
                # Over-utilized - consider increasing threads
                $optimalThreads = [Math]::Min($this.ProcessingConfiguration.MaxThreads,
                                 [Math]::Ceiling($this.ThreadPoolManager.CurrentThreadCount * 1.2))
            }
            
            if ($optimalThreads -ne $this.ThreadPoolManager.CurrentThreadCount) {
                $this.Logger.WriteInformation("Load rebalancing: Adjusting thread count from $($this.ThreadPoolManager.CurrentThreadCount) to $optimalThreads (Utilization: $($currentUtilization.ToString('F2')))")
                # Note: Actual thread pool resizing would require more complex implementation
                $this.ThreadPoolManager.OptimalThreadCount = $optimalThreads
            }
            
        } catch {
            $this.Logger.WriteError("Load rebalancing failed", $_.Exception)
        }
    }
    
    # Optimize thread count based on performance
    [void] OptimizeThreadCount([datetime] $startTime) {
        try {
            $currentTime = Get-Date
            $timeSinceOptimization = $currentTime - $this.ThreadPoolManager.LastOptimizationTime
            
            # Only optimize every few minutes
            if ($timeSinceOptimization.TotalSeconds -lt $this.ThreadPoolManager.OptimizationInterval) { return }
            
            $currentThroughput = $this.PerformanceMetrics.ThroughputPerSecond
            $currentThreadCount = $this.ThreadPoolManager.CurrentThreadCount
            
            # Simple optimization: if throughput is low and we have capacity, increase threads
            if ($currentThroughput -lt 10 -and $currentThreadCount -lt $this.ProcessingConfiguration.MaxThreads) {
                $newThreadCount = [Math]::Min($this.ProcessingConfiguration.MaxThreads,
                                 [Math]::Ceiling($currentThreadCount * $this.ProcessingConfiguration.ThreadScalingFactor))
                
                $this.Logger.WriteInformation("Performance optimization: Increasing thread count from $currentThreadCount to $newThreadCount")
                $this.ThreadPoolManager.OptimalThreadCount = $newThreadCount
                $this.PerformanceMetrics.OptimizationEvents++
            }
            
            $this.ThreadPoolManager.LastOptimizationTime = $currentTime
            
        } catch {
            $this.Logger.WriteError("Thread count optimization failed", $_.Exception)
        }
    }
    
    # Update performance metrics
    [void] UpdatePerformanceMetrics([int] $itemsProcessed, [TimeSpan] $processingTime) {
        $this.PerformanceMetrics.TotalItemsProcessed += $itemsProcessed
        $this.PerformanceMetrics.TotalProcessingTime = $this.PerformanceMetrics.TotalProcessingTime.Add($processingTime)
        
        if ($processingTime.TotalSeconds -gt 0) {
            $this.PerformanceMetrics.ThroughputPerSecond = $itemsProcessed / $processingTime.TotalSeconds
        }
        
        if ($this.PerformanceMetrics.TotalItemsProcessed -gt 0) {
            $this.PerformanceMetrics.AverageItemProcessingTime = $this.PerformanceMetrics.TotalProcessingTime.TotalSeconds / $this.PerformanceMetrics.TotalItemsProcessed
        }
    }
    
    # Update job-specific performance metrics
    [void] UpdateJobPerformanceMetrics([int] $batchSize, [TimeSpan] $jobDuration) {
        # Update thread efficiency metrics
        $this.ThreadPoolManager.ThreadEfficiency = ($this.ThreadPoolManager.ThreadEfficiency + ($batchSize / $jobDuration.TotalSeconds)) / 2
    }
    
    # Cleanup active jobs
    [void] CleanupActiveJobs() {
        try {
            foreach ($job in $this.ActiveJobs) {
                if ($job) {
                    $job.Dispose()
                }
            }
            
            $this.ActiveJobs.Clear()
            
        } catch {
            $this.Logger.WriteError("Failed to cleanup active jobs", $_.Exception)
        }
    }
    
    # Get processing statistics
    [hashtable] GetProcessingStatistics() {
        return @{
            Configuration = $this.ProcessingConfiguration.Clone()
            ThreadPoolManager = $this.ThreadPoolManager.Clone()
            LoadBalancer = $this.LoadBalancer.Clone()
            PerformanceMetrics = $this.PerformanceMetrics.Clone()
            IsProcessing = $this.IsProcessing
            OptimalThreadCount = $this.OptimalThreadCount
            ActiveJobCount = $this.ActiveJobs.Count
        }
    }
    
    # Configure processing settings
    [void] ConfigureProcessing([hashtable] $settings) {
        foreach ($key in $settings.Keys) {
            if ($this.ProcessingConfiguration.ContainsKey($key)) {
                $this.ProcessingConfiguration[$key] = $settings[$key]
                $this.Logger.WriteDebug("Updated processing setting: $key = $($settings[$key])")
            }
        }
        
        # Recalculate optimal thread count if relevant settings changed
        if ($settings.ContainsKey('MaxThreads') -or $settings.ContainsKey('MinThreads')) {
            $this.OptimalThreadCount = $this.CalculateOptimalThreadCount()
        }
        
        $this.Logger.WriteInformation("Processing configuration updated")
    }
    
    # Dispose and cleanup
    [void] Dispose() {
        try {
            $this.CleanupActiveJobs()
            
            if ($this.RunspacePool) {
                $this.RunspacePool.Close()
                $this.RunspacePool.Dispose()
            }
            
            $this.Logger.WriteInformation("ParallelProcessingEngine disposed")
            
        } catch {
            $this.Logger.WriteError("Failed to dispose ParallelProcessingEngine", $_.Exception)
        }
    }
}