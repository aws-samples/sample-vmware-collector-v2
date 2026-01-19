#
# PerformanceCollector.ps1 - Unified performance data collection engine
#
# CONSOLIDATED: Combines PerformanceDataCollector + ParallelPerformanceCollector
# Provides both sequential and parallel performance data collection capabilities
#

using module .\Interfaces.ps1

class PerformanceCollector {
    [ILogger] $Logger
    [hashtable] $StatIntervals
    
    # Parallel processing properties (from ParallelPerformanceCollector)
    [int] $MaxThreads
    [int] $BatchSize
    [int] $MaxMemoryMB
    [bool] $EnableMemoryManagement
    [bool] $EnableParallelProcessing
    [hashtable] $ThreadPoolSettings
    [hashtable] $MemorySettings
    [hashtable] $ValidationSettings
    [hashtable] $CollectionStatistics
    [System.Collections.Concurrent.ConcurrentQueue[object]] $WorkQueue
    [System.Collections.Concurrent.ConcurrentDictionary[string, object]] $Results
    [System.Threading.ManualResetEvent] $CompletionEvent
    [bool] $IsCollectionActive
    
    # Constructor for basic performance collection
    PerformanceCollector([ILogger] $Logger) {
        $this.Logger = $Logger
        $this.EnableParallelProcessing = $false
        $this.MaxThreads = 1
        $this.InitializeStatIntervals()
        $this.InitializeBasicSettings()
    }
    
    # Constructor for parallel performance collection
    PerformanceCollector([ILogger] $Logger, [int] $MaxThreads) {
        $this.Logger = $Logger
        $this.EnableParallelProcessing = $true
        $this.MaxThreads = [Math]::Max(1, [Math]::Min(50, $MaxThreads))
        $this.InitializeStatIntervals()
        $this.InitializeParallelSettings()
    }
    
    # Initialize basic settings
    [void] InitializeBasicSettings() {
        $this.BatchSize = 10
        $this.MaxMemoryMB = 1024
        $this.EnableMemoryManagement = $false
        $this.IsCollectionActive = $false
    }
    
    # Initialize parallel processing settings
    [void] InitializeParallelSettings() {
        $this.BatchSize = 25
        $this.MaxMemoryMB = 2048
        $this.EnableMemoryManagement = $true
        $this.IsCollectionActive = $false
        
        # Initialize thread pool settings
        $this.ThreadPoolSettings = @{
            MaxThreads = $this.MaxThreads
            ThreadTimeout = 300  # 5 minutes
            RetryAttempts = 3
            RetryDelayMs = 1000
            EnableThreadMonitoring = $true
        }
        
        # Initialize memory management settings
        $this.MemorySettings = @{
            MaxMemoryMB = $this.MaxMemoryMB
            MemoryCheckIntervalMs = 30000  # 30 seconds
            MemoryThresholdPercent = 80
            EnableGarbageCollection = $true
            GCCollectionMode = 'Optimized'
        }
        
        # Initialize validation settings
        $this.ValidationSettings = @{
            EnableDataValidation = $true
            ValidatePerformanceRanges = $true
            ValidateLogicalRelationships = $true
            ValidateDailyStatistics = $true
            MaxCpuPercent = 100.0
            MaxMemoryPercent = 100.0
            MinDataPointsForReliability = 5
            MaxAcceptableGapHours = 4
        }
        
        # Initialize collection statistics
        $this.CollectionStatistics = @{
            TotalVMs = 0
            ProcessedVMs = 0
            SuccessfulVMs = 0
            FailedVMs = 0
            StartTime = $null
            EndTime = $null
            TotalDurationSeconds = 0
            AverageVMProcessingTimeMs = 0
            ThreadsUsed = 0
            MemoryPeakMB = 0
            ValidationErrors = 0
            ValidationWarnings = 0
        }
        
        # Initialize concurrent collections
        $this.WorkQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $this.Results = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
        $this.CompletionEvent = [System.Threading.ManualResetEvent]::new($false)
    }
    
    # Initialize stat intervals
    [void] InitializeStatIntervals() {
        try {
            $this.Logger.WriteDebug("Retrieving vCenter stat intervals...")
            $retrievedStatIntervals = Get-StatInterval
            
            if (-not $retrievedStatIntervals) {
                $this.Logger.WriteWarning("Could not retrieve stat intervals, using defaults")
                $this.StatIntervals = @{
                    pastDay = 300      # 5 minutes
                    pastWeek = 1800    # 30 minutes
                    pastMonth = 7200   # 2 hours
                    pastYear = 86400   # 1 day
                }
            } else {
                $this.StatIntervals = @{
                    pastDay = ($retrievedStatIntervals | Where-Object { $_.Name -eq "Past Day" }).SamplingPeriodSecs
                    pastWeek = ($retrievedStatIntervals | Where-Object { $_.Name -eq "Past Week" }).SamplingPeriodSecs
                    pastMonth = ($retrievedStatIntervals | Where-Object { $_.Name -eq "Past Month" }).SamplingPeriodSecs
                    pastYear = ($retrievedStatIntervals | Where-Object { $_.Name -eq "Past Year" }).SamplingPeriodSecs
                }
            }
            
        } catch {
            $this.Logger.WriteError("Failed to initialize stat intervals: $($_.Exception.Message)", $_.Exception)
            # Use defaults
            $this.StatIntervals = @{
                pastDay = 300
                pastWeek = 1800
                pastMonth = 7200
                pastYear = 86400
            }
        }
    }
    
    # Collect bulk performance data (exact same as vmware-collector.ps1)
    [hashtable] CollectBulkPerformanceData([array] $VMs, [int] $CollectionDays) {
        try {
            $this.Logger.WriteInformation("Collecting bulk performance data for $($VMs.Count) VMs over $CollectionDays days...")
            $bulkPerfStartTime = Get-Date
            
            # Determine appropriate stat interval based on collection days
            $statInterval = $this.GetStatInterval($CollectionDays)
            
            # Calculate date range
            $endDate = Get-Date
            $startDate = $endDate.AddDays(-$CollectionDays)
            
            # Initialize bulk performance data (exact same structure as vmware-collector.ps1)
            $bulkPerfData = @{}
            
            # Collect performance data for all VMs
            $vmCount = 0
            foreach ($vm in $VMs) {
                $vmCount++
                
                if ($VMs.Count -gt 5) {
                    $vmPercent = [math]::Round(($vmCount / $VMs.Count) * 100, 1)
                    Write-Progress -Activity "Collecting Performance Data" -Status "Processing VM $vmCount of $($VMs.Count) ($vmPercent%) - $($vm.Name)" -PercentComplete $vmPercent
                }
                
                try {
                    # Skip if VM is powered off
                    if ($vm.PowerState -ne "PoweredOn") {
                        $bulkPerfData[$vm.Id] = @{
                            maxCpuUsagePctDec = 25.0
                            avgCpuUsagePctDec = 15.0
                            maxRamUsagePctDec = 60.0
                            avgRamUtlPctDec = 45.0
                            dataPoints = 0
                        }
                        continue
                    }
                    
                    # Collect CPU and Memory statistics (exact same as vmware-collector.ps1)
                    $cpuStats = $this.GetVMStatistics($vm, "cpu.usage.average", $startDate, $endDate, $statInterval)
                    $memStats = $this.GetVMStatistics($vm, "mem.usage.average", $startDate, $endDate, $statInterval)
                    
                    # Calculate metrics using P95 percentile (exact same as vmware-collector.ps1)
                    $cpuP95 = $this.GetPercentile($cpuStats, 95)
                    $cpuAvg = if ($cpuStats.Count -gt 0) { ($cpuStats | Measure-Object -Average).Average } else { 25.0 }
                    $memP95 = $this.GetPercentile($memStats, 95)
                    $memAvg = if ($memStats.Count -gt 0) { ($memStats | Measure-Object -Average).Average } else { 60.0 }
                    
                    # Store in exact same format as vmware-collector.ps1
                    $bulkPerfData[$vm.Id] = @{
                        maxCpuUsagePctDec = if ($cpuP95 -gt 0) { $cpuP95 } else { 25.0 }
                        avgCpuUsagePctDec = if ($cpuAvg -gt 0) { $cpuAvg } else { 15.0 }
                        maxRamUsagePctDec = if ($memP95 -gt 0) { $memP95 } else { 60.0 }
                        avgRamUtlPctDec = if ($memAvg -gt 0) { $memAvg } else { 45.0 }
                        dataPoints = $cpuStats.Count + $memStats.Count
                    }
                    
                } catch {
                    $this.Logger.WriteError("Failed to collect performance data for VM $($vm.Name): $($_.Exception.Message)", $_.Exception)
                    
                    # Use defaults on error (exact same as vmware-collector.ps1)
                    $bulkPerfData[$vm.Id] = @{
                        maxCpuUsagePctDec = 25.0
                        avgCpuUsagePctDec = 15.0
                        maxRamUsagePctDec = 60.0
                        avgRamUtlPctDec = 45.0
                        dataPoints = 0
                    }
                }
            }
            
            if ($VMs.Count -gt 5) {
                Write-Progress -Activity "Collecting Performance Data" -Completed
            }
            
            $bulkPerfTime = (Get-Date) - $bulkPerfStartTime
            $vmsWithData = ($bulkPerfData.Values | Where-Object { $_.dataPoints -gt 0 }).Count
            
            $this.Logger.WriteInformation("Bulk performance collection completed in $($bulkPerfTime.TotalSeconds.ToString('F1')) seconds")
            $this.Logger.WriteInformation("Successfully collected performance data for $vmsWithData of $($VMs.Count) VMs")
            
            return @{
                Success = $true
                BulkPerfData = $bulkPerfData
                CollectionTime = $bulkPerfTime
                VmsWithData = $vmsWithData
                TotalVMs = $VMs.Count
            }
            
        } catch {
            $this.Logger.WriteError("Bulk performance data collection failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                BulkPerfData = @{}
            }
        }
    }
    
    # Main performance data collection method
    [hashtable] CollectPerformanceData([array] $VMData, [int] $CollectionDays, [int] $MaxParallelThreads) {
        try {
            $this.Logger.WriteInformation("Collecting performance data for $($VMData.Count) VMs over $CollectionDays days...")
            $perfStartTime = Get-Date
            
            # Determine appropriate stat interval based on collection days
            $statInterval = $this.GetStatInterval($CollectionDays)
            $this.Logger.WriteDebug("Using stat interval: $statInterval seconds for $CollectionDays days")
            
            # Calculate date range
            $endDate = Get-Date
            $startDate = $endDate.AddDays(-$CollectionDays)
            
            $this.Logger.WriteDebug("Performance collection period: $($startDate.ToString('yyyy-MM-dd HH:mm:ss')) to $($endDate.ToString('yyyy-MM-dd HH:mm:ss'))")
            
            # Collect performance data for each VM
            $performanceData = @()
            $vmCount = 0
            $totalVMs = $VMData.Count
            
            foreach ($vmInfo in $VMData) {
                $vmCount++
                
                # Progress reporting
                if ($totalVMs -gt 5) {
                    $vmPercent = [math]::Round(($vmCount / $totalVMs) * 100, 1)
                    Write-Progress -Activity "Collecting Performance Data" -Status "Processing VM $vmCount of $totalVMs ($vmPercent%) - $($vmInfo.Name)" -PercentComplete $vmPercent
                }
                
                try {
                    $vmPerfData = $this.CollectVMPerformanceData($vmInfo, $startDate, $endDate, $statInterval)
                    if ($vmPerfData) {
                        $performanceData += $vmPerfData
                        
                        # Update VM data with performance metrics
                        $this.UpdateVMDataWithPerformance($vmInfo, $vmPerfData)
                    }
                    
                } catch {
                    $this.Logger.WriteError("Failed to collect performance data for VM $($vmInfo.Name): $($_.Exception.Message)", $_.Exception)
                }
            }
            
            if ($totalVMs -gt 5) {
                Write-Progress -Activity "Collecting Performance Data" -Completed
            }
            
            $perfTime = (Get-Date) - $perfStartTime
            $this.Logger.WriteInformation("Performance data collection completed in $($perfTime.TotalSeconds.ToString('F1')) seconds")
            $this.Logger.WriteInformation("Collected performance data for $($performanceData.Count) VMs")
            
            return @{
                Success = $true
                PerformanceData = $performanceData
                CollectionTime = $perfTime
                ProcessedCount = $performanceData.Count
                TotalCount = $totalVMs
                StatInterval = $statInterval
                DateRange = @{
                    StartDate = $startDate
                    EndDate = $endDate
                }
            }
            
        } catch {
            $this.Logger.WriteError("Performance data collection failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                PerformanceData = @()
            }
        }
    }
    
    # Get appropriate stat interval based on collection days
    [int] GetStatInterval([int] $CollectionDays) {
        if ($CollectionDays -le 7) {
            return $this.StatIntervals.pastDay      # 5 minutes
        } elseif ($CollectionDays -le 30) {
            return $this.StatIntervals.pastWeek     # 30 minutes
        } elseif ($CollectionDays -le 365) {
            return $this.StatIntervals.pastMonth    # 2 hours
        } else {
            return $this.StatIntervals.pastYear     # 1 day
        }
    }
    
    # Collect performance data for a single VM
    [hashtable] CollectVMPerformanceData([hashtable] $VMInfo, [DateTime] $StartDate, [DateTime] $EndDate, [int] $StatInterval) {
        try {
            # Get VM object
            $vm = Get-VM -Name $VMInfo.Name -ErrorAction SilentlyContinue
            if (-not $vm) {
                $this.Logger.WriteWarning("VM $($VMInfo.Name) not found for performance collection")
                return $null
            }
            
            # Skip if VM is powered off (no performance data available)
            if ($vm.PowerState -ne "PoweredOn") {
                $this.Logger.WriteDebug("Skipping performance collection for powered off VM: $($VMInfo.Name)")
                return $this.CreateDefaultPerformanceData($VMInfo)
            }
            
            # Collect CPU statistics
            $cpuStats = $this.GetVMStatistics($vm, "cpu.usage.average", $StartDate, $EndDate, $StatInterval)
            
            # Collect Memory statistics
            $memStats = $this.GetVMStatistics($vm, "mem.usage.average", $StartDate, $EndDate, $StatInterval)
            
            # Collect Disk statistics (if available)
            $diskStats = $this.GetVMStatistics($vm, "disk.usage.average", $StartDate, $EndDate, $StatInterval)
            
            # Collect Network statistics (if available)
            $networkStats = $this.GetVMStatistics($vm, "net.usage.average", $StartDate, $EndDate, $StatInterval)
            
            # Calculate performance metrics using P95 percentile
            $perfMetrics = $this.CalculatePerformanceMetrics($cpuStats, $memStats, $diskStats, $networkStats)
            
            return @{
                VMName = $VMInfo.Name
                CollectionPeriod = @{
                    StartDate = $StartDate
                    EndDate = $EndDate
                    StatInterval = $StatInterval
                }
                RawStatistics = @{
                    CPU = $cpuStats
                    Memory = $memStats
                    Disk = $diskStats
                    Network = $networkStats
                }
                CalculatedMetrics = $perfMetrics
            }
            
        } catch {
            $this.Logger.WriteError("Failed to collect performance data for VM $($VMInfo.Name): $($_.Exception.Message)", $_.Exception)
            return $this.CreateDefaultPerformanceData($VMInfo)
        }
    }
    
    # Get VM statistics for a specific metric
    [array] GetVMStatistics([object] $VM, [string] $MetricName, [DateTime] $StartDate, [DateTime] $EndDate, [int] $StatInterval) {
        try {
            $stats = Get-Stat -Entity $VM -Stat $MetricName -Start $StartDate -Finish $EndDate -IntervalSecs $StatInterval -ErrorAction SilentlyContinue
            
            if ($stats) {
                return $stats | ForEach-Object { $_.Value }
            } else {
                return @()
            }
            
        } catch {
            $this.Logger.WriteDebug("Failed to get $MetricName statistics for VM $($VM.Name): $_")
            return @()
        }
    }
    
    # Calculate performance metrics using P95 percentile
    [hashtable] CalculatePerformanceMetrics([array] $CpuStats, [array] $MemStats, [array] $DiskStats, [array] $NetworkStats) {
        try {
            # Calculate P95 percentiles (replicates Get-Percentile function from vmware-collector.ps1)
            $cpuP95 = $this.GetPercentile($CpuStats, 95)
            $memP95 = $this.GetPercentile($MemStats, 95)
            $diskP95 = $this.GetPercentile($DiskStats, 95)
            $networkP95 = $this.GetPercentile($NetworkStats, 95)
            
            # Calculate averages
            $cpuAvg = if ($CpuStats.Count -gt 0) { ($CpuStats | Measure-Object -Average).Average } else { 0 }
            $memAvg = if ($MemStats.Count -gt 0) { ($MemStats | Measure-Object -Average).Average } else { 0 }
            $diskAvg = if ($DiskStats.Count -gt 0) { ($DiskStats | Measure-Object -Average).Average } else { 0 }
            $networkAvg = if ($NetworkStats.Count -gt 0) { ($NetworkStats | Measure-Object -Average).Average } else { 0 }
            
            # Calculate maximums
            $cpuMax = if ($CpuStats.Count -gt 0) { ($CpuStats | Measure-Object -Maximum).Maximum } else { 0 }
            $memMax = if ($MemStats.Count -gt 0) { ($MemStats | Measure-Object -Maximum).Maximum } else { 0 }
            $diskMax = if ($DiskStats.Count -gt 0) { ($DiskStats | Measure-Object -Maximum).Maximum } else { 0 }
            $networkMax = if ($NetworkStats.Count -gt 0) { ($NetworkStats | Measure-Object -Maximum).Maximum } else { 0 }
            
            return @{
                CPU = @{
                    P95 = [Math]::Round($cpuP95, 2)
                    Average = [Math]::Round($cpuAvg, 2)
                    Maximum = [Math]::Round($cpuMax, 2)
                    SampleCount = $CpuStats.Count
                }
                Memory = @{
                    P95 = [Math]::Round($memP95, 2)
                    Average = [Math]::Round($memAvg, 2)
                    Maximum = [Math]::Round($memMax, 2)
                    SampleCount = $MemStats.Count
                }
                Disk = @{
                    P95 = [Math]::Round($diskP95, 2)
                    Average = [Math]::Round($diskAvg, 2)
                    Maximum = [Math]::Round($diskMax, 2)
                    SampleCount = $DiskStats.Count
                }
                Network = @{
                    P95 = [Math]::Round($networkP95, 2)
                    Average = [Math]::Round($networkAvg, 2)
                    Maximum = [Math]::Round($networkMax, 2)
                    SampleCount = $NetworkStats.Count
                }
            }
            
        } catch {
            $this.Logger.WriteError("Failed to calculate performance metrics: $($_.Exception.Message)", $_.Exception)
            return $this.GetDefaultMetrics()
        }
    }
    
    # Calculate percentile from array of values (replicates Get-Percentile function)
    [double] GetPercentile([array] $Values, [double] $Percentile) {
        if (-not $Values -or $Values.Count -eq 0) {
            return 0
        }
        
        # Sort the values in ascending order
        $sortedValues = $Values | Sort-Object
        
        # Calculate the index for the percentile
        $index = ($Percentile / 100) * ($sortedValues.Count - 1)
        
        # If index is a whole number, return that value
        if ($index -eq [math]::Floor($index)) {
            return $sortedValues[[int]$index]
        }
        
        # Otherwise, interpolate between the two nearest values
        $lowerIndex = [math]::Floor($index)
        $upperIndex = [math]::Ceiling($index)
        $weight = $index - $lowerIndex
        
        $lowerValue = $sortedValues[$lowerIndex]
        $upperValue = $sortedValues[$upperIndex]
        
        return $lowerValue + ($weight * ($upperValue - $lowerValue))
    }
    
    # Update VM data with performance metrics
    [void] UpdateVMDataWithPerformance([hashtable] $VMInfo, [hashtable] $PerfData) {
        try {
            if ($PerfData.CalculatedMetrics) {
                $metrics = $PerfData.CalculatedMetrics
                
                # Use P95 values as the "Max" values for migration sizing (more realistic than true maximum)
                $VMInfo.MaxCpuUsagePct = $metrics.CPU.P95
                $VMInfo.MaxRamUsagePct = $metrics.Memory.P95
                $VMInfo.MaxDiskIOPS = $metrics.Disk.P95
                $VMInfo.MaxNetworkMbps = $metrics.Network.P95
                
                # Also store averages for reference
                $VMInfo.AvgCpuUsagePct = $metrics.CPU.Average
                $VMInfo.AvgRamUsagePct = $metrics.Memory.Average
                $VMInfo.AvgDiskIOPS = $metrics.Disk.Average
                $VMInfo.AvgNetworkMbps = $metrics.Network.Average
            }
            
        } catch {
            $this.Logger.WriteError("Failed to update VM data with performance metrics: $($_.Exception.Message)", $_.Exception)
        }
    }
    
    # Create default performance data for VMs without statistics
    [hashtable] CreateDefaultPerformanceData([hashtable] $VMInfo) {
        return @{
            VMName = $VMInfo.Name
            CollectionPeriod = @{
                StartDate = (Get-Date).AddDays(-7)
                EndDate = Get-Date
                StatInterval = 300
            }
            RawStatistics = @{
                CPU = @()
                Memory = @()
                Disk = @()
                Network = @()
            }
            CalculatedMetrics = $this.GetDefaultMetrics()
        }
    }
    
    # Get default metrics for VMs without performance data
    [hashtable] GetDefaultMetrics() {
        return @{
            CPU = @{
                P95 = 25.0
                Average = 15.0
                Maximum = 50.0
                SampleCount = 0
            }
            Memory = @{
                P95 = 60.0
                Average = 45.0
                Maximum = 80.0
                SampleCount = 0
            }
            Disk = @{
                P95 = 100.0
                Average = 50.0
                Maximum = 200.0
                SampleCount = 0
            }
            Network = @{
                P95 = 10.0
                Average = 5.0
                Maximum = 25.0
                SampleCount = 0
            }
        }
    }
    
    # ===== PARALLEL PROCESSING METHODS (from ParallelPerformanceCollector) =====
    
    # Collect performance data for multiple VMs in parallel
    [hashtable] CollectPerformanceDataParallel([array] $VMs, [datetime] $StartDate, [datetime] $EndDate) {
        if (-not $this.EnableParallelProcessing) {
            $this.Logger.WriteWarning("Parallel processing not enabled, falling back to sequential collection")
            return $this.CollectBulkPerformanceData($VMs, ($EndDate - $StartDate).Days)
        }
        
        try {
            $this.Logger.WriteInformation("Starting parallel performance collection for $($VMs.Count) VMs")
            $this.ResetCollectionStatistics($VMs.Count)
            $this.CollectionStatistics.StartTime = Get-Date
            
            # Start memory monitoring if enabled
            $memoryMonitorJob = $null
            if ($this.EnableMemoryManagement) {
                $memoryMonitorJob = $this.StartMemoryMonitoring()
            }
            
            try {
                # Create work items and process them
                $this.CreateWorkItems($VMs, $StartDate, $EndDate)
                $this.ProcessVMsWithThreadPool()
                
                # Wait for completion
                $this.CompletionEvent.WaitOne()
                
                # Collect results
                $collectedResults = @{}
                foreach ($key in $this.Results.Keys) {
                    $collectedResults[$key] = $this.Results[$key]
                }
                
                $this.CollectionStatistics.EndTime = Get-Date
                $this.CollectionStatistics.TotalDurationSeconds = ($this.CollectionStatistics.EndTime - $this.CollectionStatistics.StartTime).TotalSeconds
                
                $this.Logger.WriteInformation("Parallel performance collection completed: $($this.CollectionStatistics.ProcessedVMs)/$($this.CollectionStatistics.TotalVMs) VMs processed in $($this.CollectionStatistics.TotalDurationSeconds.ToString('F1')) seconds")
                
                return @{
                    Success = $true
                    BulkPerfData = $collectedResults
                    Statistics = $this.CollectionStatistics.Clone()
                    CollectionTime = [TimeSpan]::FromSeconds($this.CollectionStatistics.TotalDurationSeconds)
                    VmsWithData = $this.CollectionStatistics.SuccessfulVMs
                    TotalVMs = $this.CollectionStatistics.TotalVMs
                }
                
            } finally {
                # Stop memory monitoring
                if ($memoryMonitorJob) {
                    $this.StopMemoryMonitoring($memoryMonitorJob)
                }
                
                $this.IsCollectionActive = $false
            }
            
        } catch {
            $this.Logger.WriteError("Parallel performance collection failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                BulkPerfData = @{}
                Statistics = $this.CollectionStatistics.Clone()
            }
        }
    }
    
    # Create work items for the thread pool
    [void] CreateWorkItems([array] $VMs, [datetime] $StartDate, [datetime] $EndDate) {
        # Create batches of VMs for processing
        $batches = @()
        for ($i = 0; $i -lt $VMs.Count; $i += $this.BatchSize) {
            $endIndex = [Math]::Min($i + $this.BatchSize - 1, $VMs.Count - 1)
            $batch = $VMs[$i..$endIndex]
            
            $workItem = @{
                BatchId = [Guid]::NewGuid().ToString()
                VMs = $batch
                StartDate = $StartDate
                EndDate = $EndDate
                BatchIndex = $batches.Count
                TotalBatches = [Math]::Ceiling($VMs.Count / $this.BatchSize)
            }
            
            $this.WorkQueue.Enqueue($workItem)
            $batches += $workItem
        }
        
        $this.Logger.WriteDebug("Created $($batches.Count) work batches for parallel processing")
    }
    
    # Process VMs using thread pool
    [void] ProcessVMsWithThreadPool() {
        $threads = @()
        $threadCount = [Math]::Min($this.MaxThreads, $this.WorkQueue.Count)
        $this.CollectionStatistics.ThreadsUsed = $threadCount
        
        $this.Logger.WriteDebug("Starting $threadCount worker threads for parallel processing")
        
        # Start worker threads
        for ($i = 0; $i -lt $threadCount; $i++) {
            $thread = [System.Threading.Thread]::new([System.Threading.ThreadStart]{ $this.WorkerThreadMain() })
            $thread.Name = "PerfCollector-$i"
            $thread.IsBackground = $true
            $thread.Start()
            $threads += $thread
        }
        
        # Monitor thread completion
        $completedThreads = 0
        while ($completedThreads -lt $threadCount) {
            Start-Sleep -Milliseconds 100
            $completedThreads = ($threads | Where-Object { -not $_.IsAlive }).Count
        }
        
        $this.CompletionEvent.Set()
        $this.Logger.WriteDebug("All worker threads completed")
    }
    
    # Worker thread main execution method
    [void] WorkerThreadMain() {
        $threadName = [System.Threading.Thread]::CurrentThread.Name
        $this.Logger.WriteDebug("Worker thread $threadName started")
        
        try {
            while ($true) {
                $workItem = $null
                if (-not $this.WorkQueue.TryDequeue([ref]$workItem)) {
                    break  # No more work items
                }
                
                $this.ProcessWorkItem($workItem, $threadName)
            }
        } catch {
            $this.Logger.WriteError("Worker thread $threadName failed: $($_.Exception.Message)", $_.Exception)
        } finally {
            $this.Logger.WriteDebug("Worker thread $threadName finished")
        }
    }
    
    # Process a single work item (batch of VMs)
    [void] ProcessWorkItem([hashtable] $workItem, [string] $threadName) {
        try {
            $batchId = $workItem.BatchId
            $vms = $workItem.VMs
            $startDate = $workItem.StartDate
            $endDate = $workItem.EndDate
            
            $this.Logger.WriteDebug("Thread $threadName processing batch $batchId with $($vms.Count) VMs")
            
            foreach ($vm in $vms) {
                try {
                    $vmResult = $this.ProcessSingleVM($vm, $startDate, $endDate, $threadName)
                    $this.Results.TryAdd($vm.Id, $vmResult)
                    
                    # Update statistics
                    [System.Threading.Interlocked]::Increment([ref]$this.CollectionStatistics.ProcessedVMs)
                    if ($vmResult.Success) {
                        [System.Threading.Interlocked]::Increment([ref]$this.CollectionStatistics.SuccessfulVMs)
                    } else {
                        [System.Threading.Interlocked]::Increment([ref]$this.CollectionStatistics.FailedVMs)
                    }
                    
                } catch {
                    $this.Logger.WriteError("Thread $threadName failed to process VM $($vm.Name): $($_.Exception.Message)", $_.Exception)
                    [System.Threading.Interlocked]::Increment([ref]$this.CollectionStatistics.FailedVMs)
                }
            }
            
        } catch {
            $this.Logger.WriteError("Thread $threadName failed to process work item: $($_.Exception.Message)", $_.Exception)
        }
    }
    
    # Process a single VM with performance data collection and validation
    [hashtable] ProcessSingleVM([object] $vm, [datetime] $startDate, [datetime] $endDate, [string] $threadName) {
        try {
            $vmStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Skip if VM is powered off
            if ($vm.PowerState -ne "PoweredOn") {
                return @{
                    Success = $true
                    maxCpuUsagePctDec = 25.0
                    avgCpuUsagePctDec = 15.0
                    maxRamUsagePctDec = 60.0
                    avgRamUtlPctDec = 45.0
                    dataPoints = 0
                    ProcessingTimeMs = $vmStopwatch.ElapsedMilliseconds
                    ThreadName = $threadName
                    PowerState = "PoweredOff"
                }
            }
            
            # Collect performance statistics
            $statInterval = $this.GetStatInterval(($endDate - $startDate).Days)
            $cpuStats = $this.GetVMStatistics($vm, "cpu.usage.average", $startDate, $endDate, $statInterval)
            $memStats = $this.GetVMStatistics($vm, "mem.usage.average", $startDate, $endDate, $statInterval)
            
            # Calculate metrics using P95 percentile
            $cpuP95 = $this.GetPercentile($cpuStats, 95)
            $cpuAvg = if ($cpuStats.Count -gt 0) { ($cpuStats | Measure-Object -Average).Average } else { 25.0 }
            $memP95 = $this.GetPercentile($memStats, 95)
            $memAvg = if ($memStats.Count -gt 0) { ($memStats | Measure-Object -Average).Average } else { 60.0 }
            
            $result = @{
                Success = $true
                maxCpuUsagePctDec = if ($cpuP95 -gt 0) { $cpuP95 } else { 25.0 }
                avgCpuUsagePctDec = if ($cpuAvg -gt 0) { $cpuAvg } else { 15.0 }
                maxRamUsagePctDec = if ($memP95 -gt 0) { $memP95 } else { 60.0 }
                avgRamUtlPctDec = if ($memAvg -gt 0) { $memAvg } else { 45.0 }
                dataPoints = $cpuStats.Count + $memStats.Count
                ProcessingTimeMs = $vmStopwatch.ElapsedMilliseconds
                ThreadName = $threadName
                PowerState = $vm.PowerState
            }
            
            # Perform validation if enabled
            if ($this.ValidationSettings.EnableDataValidation) {
                $validationResult = $this.ValidatePerformanceData($result, @($cpuStats, $memStats), $vm.Name)
                $result.ValidationResult = $validationResult
                
                if ($validationResult.Errors.Count -gt 0) {
                    [System.Threading.Interlocked]::Add([ref]$this.CollectionStatistics.ValidationErrors, $validationResult.Errors.Count)
                }
                if ($validationResult.Warnings.Count -gt 0) {
                    [System.Threading.Interlocked]::Add([ref]$this.CollectionStatistics.ValidationWarnings, $validationResult.Warnings.Count)
                }
            }
            
            return $result
            
        } catch {
            $this.Logger.WriteError("Failed to process VM $($vm.Name) in thread $threadName`: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                maxCpuUsagePctDec = 25.0
                avgCpuUsagePctDec = 15.0
                maxRamUsagePctDec = 60.0
                avgRamUtlPctDec = 45.0
                dataPoints = 0
                ProcessingTimeMs = 0
                ThreadName = $threadName
            }
        }
    }
    
    # Validate performance data with quality checks
    [hashtable] ValidatePerformanceData([hashtable] $performanceMetrics, [array] $dailyStats, [string] $vmName) {
        try {
            if (-not $this.ValidationSettings.EnableDataValidation) {
                return @{
                    IsValid = $true
                    Errors = @()
                    Warnings = @()
                    QualityScore = 1.0
                }
            }
            
            $errors = @()
            $warnings = @()
            
            # Validate performance ranges
            if ($this.ValidationSettings.ValidatePerformanceRanges) {
                $rangeValidation = $this.ValidatePerformanceRanges($performanceMetrics, $vmName)
                $errors += $rangeValidation.Errors
                $warnings += $rangeValidation.Warnings
            }
            
            # Validate logical relationships
            if ($this.ValidationSettings.ValidateLogicalRelationships) {
                $relationshipValidation = $this.ValidateLogicalRelationships($performanceMetrics, $vmName)
                $errors += $relationshipValidation.Errors
                $warnings += $relationshipValidation.Warnings
            }
            
            # Validate daily statistics
            if ($this.ValidationSettings.ValidateDailyStatistics -and $dailyStats.Count -gt 0) {
                $statsValidation = $this.ValidateDailyStatistics($dailyStats, $vmName)
                $errors += $statsValidation.Errors
                $warnings += $statsValidation.Warnings
            }
            
            # Calculate quality score
            $qualityScore = $this.CalculateValidationQualityScore($performanceMetrics, $dailyStats, $errors.Count, $warnings.Count)
            
            return @{
                IsValid = ($errors.Count -eq 0)
                Errors = $errors
                Warnings = $warnings
                QualityScore = $qualityScore
                ValidationTimestamp = Get-Date
            }
            
        } catch {
            $this.Logger.WriteError("Performance data validation failed for VM $vmName`: $($_.Exception.Message)", $_.Exception)
            return @{
                IsValid = $false
                Errors = @("Validation failed: $($_.Exception.Message)")
                Warnings = @()
                QualityScore = 0.0
            }
        }
    }
    
    # Validate performance value ranges
    [hashtable] ValidatePerformanceRanges([hashtable] $metrics, [string] $vmName) {
        $errors = @()
        $warnings = @()
        
        # Validate CPU percentages
        if ($metrics.ContainsKey('maxCpuUsagePctDec')) {
            if ($metrics.maxCpuUsagePctDec -lt 0 -or $metrics.maxCpuUsagePctDec -gt $this.ValidationSettings.MaxCpuPercent) {
                $errors += "CPU max usage out of range: $($metrics.maxCpuUsagePctDec)% (valid: 0-$($this.ValidationSettings.MaxCpuPercent)%)"
            }
        }
        
        if ($metrics.ContainsKey('avgCpuUsagePctDec')) {
            if ($metrics.avgCpuUsagePctDec -lt 0 -or $metrics.avgCpuUsagePctDec -gt $this.ValidationSettings.MaxCpuPercent) {
                $errors += "CPU avg usage out of range: $($metrics.avgCpuUsagePctDec)% (valid: 0-$($this.ValidationSettings.MaxCpuPercent)%)"
            }
        }
        
        # Validate memory percentages
        if ($metrics.ContainsKey('maxRamUsagePctDec')) {
            if ($metrics.maxRamUsagePctDec -lt 0 -or $metrics.maxRamUsagePctDec -gt $this.ValidationSettings.MaxMemoryPercent) {
                $errors += "Memory max usage out of range: $($metrics.maxRamUsagePctDec)% (valid: 0-$($this.ValidationSettings.MaxMemoryPercent)%)"
            }
        }
        
        if ($metrics.ContainsKey('avgRamUtlPctDec')) {
            if ($metrics.avgRamUtlPctDec -lt 0 -or $metrics.avgRamUtlPctDec -gt $this.ValidationSettings.MaxMemoryPercent) {
                $errors += "Memory avg usage out of range: $($metrics.avgRamUtlPctDec)% (valid: 0-$($this.ValidationSettings.MaxMemoryPercent)%)"
            }
        }
        
        return @{
            Errors = $errors
            Warnings = $warnings
        }
    }
    
    # Validate logical relationships between metrics
    [hashtable] ValidateLogicalRelationships([hashtable] $metrics, [string] $vmName) {
        $errors = @()
        $warnings = @()
        
        # CPU: Max should be >= Average
        if ($metrics.ContainsKey('maxCpuUsagePctDec') -and $metrics.ContainsKey('avgCpuUsagePctDec')) {
            if ($metrics.maxCpuUsagePctDec -lt $metrics.avgCpuUsagePctDec) {
                $warnings += "CPU max ($($metrics.maxCpuUsagePctDec)%) < avg ($($metrics.avgCpuUsagePctDec)%)"
            }
        }
        
        # Memory: Max should be >= Average
        if ($metrics.ContainsKey('maxRamUsagePctDec') -and $metrics.ContainsKey('avgRamUtlPctDec')) {
            if ($metrics.maxRamUsagePctDec -lt $metrics.avgRamUtlPctDec) {
                $warnings += "Memory max ($($metrics.maxRamUsagePctDec)%) < avg ($($metrics.avgRamUtlPctDec)%)"
            }
        }
        
        return @{
            Errors = $errors
            Warnings = $warnings
        }
    }
    
    # Validate daily statistics consistency
    [hashtable] ValidateDailyStatistics([array] $dailyStats, [string] $vmName) {
        $errors = @()
        $warnings = @()
        
        if ($dailyStats.Count -lt $this.ValidationSettings.MinDataPointsForReliability) {
            $warnings += "Insufficient data points: $($dailyStats.Count) (minimum: $($this.ValidationSettings.MinDataPointsForReliability))"
        }
        
        return @{
            Errors = $errors
            Warnings = $warnings
        }
    }
    
    # Calculate validation quality score
    [double] CalculateValidationQualityScore([hashtable] $metrics, [array] $dailyStats, [int] $errorCount, [int] $warningCount) {
        try {
            $baseScore = 1.0
            
            # Deduct for errors (more severe)
            $baseScore -= ($errorCount * 0.2)
            
            # Deduct for warnings (less severe)
            $baseScore -= ($warningCount * 0.1)
            
            # Bonus for sufficient data points
            if ($metrics.ContainsKey('dataPoints') -and $metrics.dataPoints -ge $this.ValidationSettings.MinDataPointsForReliability) {
                $baseScore += 0.1
            }
            
            return [Math]::Max(0.0, [Math]::Min(1.0, $baseScore))
        } catch {
            return 0.0
        }
    }
    
    # Memory monitoring methods
    [object] StartMemoryMonitoring() {
        try {
            $memoryMonitorScript = {
                param($maxMemoryMB, $checkIntervalMs, $enableGC)
                
                while ($true) {
                    Start-Sleep -Milliseconds $checkIntervalMs
                    
                    $currentProcess = Get-Process -Id $PID
                    $currentMemoryMB = [Math]::Round($currentProcess.WorkingSet64 / 1MB, 2)
                    
                    if ($currentMemoryMB -gt $maxMemoryMB) {
                        if ($enableGC) {
                            [System.GC]::Collect()
                            [System.GC]::WaitForPendingFinalizers()
                        }
                    }
                }
            }
            
            $job = Start-Job -ScriptBlock $memoryMonitorScript -ArgumentList $this.MemorySettings.MaxMemoryMB, $this.MemorySettings.MemoryCheckIntervalMs, $this.MemorySettings.EnableGarbageCollection
            $this.Logger.WriteDebug("Memory monitoring job started (ID: $($job.Id))")
            return $job
            
        } catch {
            $this.Logger.WriteWarning("Failed to start memory monitoring: $($_.Exception.Message)")
            return $null
        }
    }
    
    # Stop memory monitoring background job
    [void] StopMemoryMonitoring([object] $memoryMonitorJob) {
        if ($memoryMonitorJob) {
            try {
                Stop-Job -Job $memoryMonitorJob -ErrorAction SilentlyContinue
                Remove-Job -Job $memoryMonitorJob -Force -ErrorAction SilentlyContinue
                $this.Logger.WriteDebug("Memory monitoring job stopped")
            } catch {
                $this.Logger.WriteWarning("Failed to stop memory monitoring job: $($_.Exception.Message)")
            }
        }
    }
    
    # Reset collection statistics
    [void] ResetCollectionStatistics([int] $totalVMs) {
        $this.CollectionStatistics.TotalVMs = $totalVMs
        $this.CollectionStatistics.ProcessedVMs = 0
        $this.CollectionStatistics.SuccessfulVMs = 0
        $this.CollectionStatistics.FailedVMs = 0
        $this.CollectionStatistics.ValidationErrors = 0
        $this.CollectionStatistics.ValidationWarnings = 0
        $this.CollectionStatistics.StartTime = $null
        $this.CollectionStatistics.EndTime = $null
    }
    
    # Configure parallel collection settings
    [void] ConfigureSettings([hashtable] $settings) {
        if ($settings.ContainsKey('MaxThreads')) {
            $this.MaxThreads = [Math]::Max(1, [Math]::Min(50, $settings.MaxThreads))
            if ($this.ThreadPoolSettings) {
                $this.ThreadPoolSettings.MaxThreads = $this.MaxThreads
            }
        }
        
        if ($settings.ContainsKey('BatchSize')) {
            $this.BatchSize = [Math]::Max(1, $settings.BatchSize)
        }
        
        if ($settings.ContainsKey('EnableParallelProcessing')) {
            $this.EnableParallelProcessing = $settings.EnableParallelProcessing
        }
        
        $this.Logger.WriteDebug("Performance collector settings updated: MaxThreads=$($this.MaxThreads), BatchSize=$($this.BatchSize), Parallel=$($this.EnableParallelProcessing)")
    }
    
    # Get collection statistics
    [hashtable] GetCollectionStatistics() {
        return $this.CollectionStatistics.Clone()
    }
    
    # Unified method that chooses parallel vs sequential based on settings and VM count
    [hashtable] CollectPerformanceDataOptimal([array] $VMs, [int] $Days, [bool] $UseParallel = $null) {
        # Auto-determine parallel usage if not specified
        if ($UseParallel -eq $null) {
            $UseParallel = $this.EnableParallelProcessing -and $VMs.Count -gt 50
        }
        
        if ($UseParallel -and $this.EnableParallelProcessing) {
            $startDate = (Get-Date).AddDays(-$Days)
            $endDate = Get-Date
            return $this.CollectPerformanceDataParallel($VMs, $startDate, $endDate)
        } else {
            return $this.CollectBulkPerformanceData($VMs, $Days)
        }
    }
}