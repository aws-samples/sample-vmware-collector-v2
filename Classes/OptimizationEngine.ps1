using namespace System.Collections.Generic
using namespace System.Management.Automation

<#
.SYNOPSIS
    Unified optimization engine combining cache optimization and final performance optimization
    
.DESCRIPTION
    Consolidates CacheOptimizationEngine and FinalOptimizationEngine into a single class
    that handles both intelligent caching and performance optimization for VMware environments.
    
.NOTES
    Consolidated from:
    - CacheOptimizationEngine.ps1 - Advanced caching with TTL, cache warming, and predictive prefetching
    - FinalOptimizationEngine.ps1 - Final performance optimizations and error handling
#>

class OptimizationEngine {
    # Cache-related properties (from CacheOptimizationEngine)
    [hashtable] $CacheStorage
    [hashtable] $CacheMetadata
    [hashtable] $CacheStatistics
    [hashtable] $CacheConfiguration
    [System.Timers.Timer] $CleanupTimer
    
    # Performance optimization properties (from FinalOptimizationEngine)
    [hashtable] $OptimizationSettings
    [hashtable] $PerformanceMetrics
    [hashtable] $ErrorHandlingConfig
    [hashtable] $PerformanceThresholds
    
    # Common properties
    [ILogger] $Logger
    [bool] $IsEnabled
    [bool] $IsOptimized
    
    # Constructor
    OptimizationEngine([ILogger] $logger) {
        $this.Logger = $logger
        $this.IsEnabled = $true
        $this.IsOptimized = $false
        
        # Initialize cache components
        $this.InitializeCacheComponents()
        
        # Initialize optimization components
        $this.InitializeOptimizationComponents()
        
        $this.Logger.WriteInformation("OptimizationEngine initialized with caching and performance optimization")
    }
    
    # Initialize cache-related components
    [void] InitializeCacheComponents() {
        $this.CacheStorage = @{}
        $this.CacheMetadata = @{}
        
        $this.CacheConfiguration = @{
            DefaultTTLMinutes = 30
            MaxCacheSize = 10000
            CleanupIntervalMinutes = 5
            EnablePredictivePrefetch = $true
            EnableCacheWarming = $true
            CompressionEnabled = $true
            PersistentCacheEnabled = $false
            CacheHitRatioThreshold = 0.7
        }
        
        $this.CacheStatistics = @{
            TotalRequests = 0
            CacheHits = 0
            CacheMisses = 0
            CacheEvictions = 0
            CacheWarmingOperations = 0
            PrefetchOperations = 0
            CompressionSavings = 0
            AverageRetrievalTime = 0.0
        }
        
        $this.InitializeCleanupTimer()
    }
    
    # Initialize optimization-related components
    [void] InitializeOptimizationComponents() {
        $this.PerformanceThresholds = @{
            SmallEnvironment = @{ MaxVMs = 1000; TargetMinutes = 5; MaxMemoryMB = 1024 }
            MediumEnvironment = @{ MaxVMs = 5000; TargetMinutes = 15; MaxMemoryMB = 2048 }
            LargeEnvironment = @{ MaxVMs = 10000; TargetMinutes = 60; MaxMemoryMB = 4096 }
            UltraLargeEnvironment = @{ MaxVMs = 50000; TargetMinutes = 120; MaxMemoryMB = 8192 }
        }
        
        $this.OptimizationSettings = @{}
        $this.PerformanceMetrics = @{}
        $this.ErrorHandlingConfig = @{}
        
        $this.InitializeOptimizationSettings()
        $this.InitializeErrorHandling()
    }
    
    # ========================================
    # CACHE OPTIMIZATION METHODS
    # ========================================
    
    # Initialize cleanup timer
    [void] InitializeCleanupTimer() {
        $this.CleanupTimer = New-Object System.Timers.Timer
        $this.CleanupTimer.Interval = $this.CacheConfiguration.CleanupIntervalMinutes * 60 * 1000
        $this.CleanupTimer.AutoReset = $true
        
        Register-ObjectEvent -InputObject $this.CleanupTimer -EventName Elapsed -Action {
            $cacheEngine = $Event.MessageData
            $cacheEngine.PerformCacheCleanup()
        } -MessageData $this | Out-Null
        
        $this.CleanupTimer.Start()
    }
    
    # Get cached data with intelligent retrieval
    [object] GetCachedData([string] $key, [scriptblock] $dataProvider = $null, [int] $ttlMinutes = -1) {
        if (-not $this.IsEnabled) {
            if ($dataProvider) {
                return & $dataProvider
            }
            return $null
        }
        
        $this.CacheStatistics.TotalRequests++
        $startTime = Get-Date
        
        try {
            # Check if key exists and is valid
            if ($this.IsValidCacheEntry($key)) {
                $cachedData = $this.RetrieveCachedData($key)
                $this.CacheStatistics.CacheHits++
                
                # Update access metadata
                $this.CacheMetadata[$key].LastAccessed = Get-Date
                $this.CacheMetadata[$key].AccessCount++
                
                $retrievalTime = (Get-Date) - $startTime
                $this.UpdateAverageRetrievalTime($retrievalTime.TotalMilliseconds)
                
                $this.Logger.WriteDebug("Cache HIT for key: $key")
                return $cachedData
            }
            
            # Cache miss - get data from provider if available
            if ($dataProvider) {
                $this.CacheStatistics.CacheMisses++
                $this.Logger.WriteDebug("Cache MISS for key: $key, fetching from provider")
                
                $freshData = & $dataProvider
                
                # Store in cache
                $ttl = if ($ttlMinutes -gt 0) { $ttlMinutes } else { $this.CacheConfiguration.DefaultTTLMinutes }
                $this.CacheData($key, $freshData, $ttl)
                
                # Trigger predictive prefetch if enabled
                if ($this.CacheConfiguration.EnablePredictivePrefetch) {
                    $this.TriggerPredictivePrefetch($key)
                }
                
                return $freshData
            }
            
            $this.CacheStatistics.CacheMisses++
            return $null
            
        } catch {
            $this.Logger.WriteError("Cache retrieval failed for key: $key", $_.Exception)
            
            # Fallback to data provider
            if ($dataProvider) {
                return & $dataProvider
            }
            
            return $null
        }
    }
    
    # Set cached data with metadata
    [void] CacheData([string] $key, [object] $data, [int] $ttlMinutes = -1) {
        if (-not $this.IsEnabled) { return }
        
        try {
            # Check cache size limits
            if ($this.CacheStorage.Count -ge $this.CacheConfiguration.MaxCacheSize) {
                $this.EvictLeastRecentlyUsed()
            }
            
            $ttl = if ($ttlMinutes -gt 0) { $ttlMinutes } else { $this.CacheConfiguration.DefaultTTLMinutes }
            $expiryTime = (Get-Date).AddMinutes($ttl)
            
            # Compress data if enabled
            $storedData = if ($this.CacheConfiguration.CompressionEnabled) {
                $this.CompressData($data)
            } else {
                $data
            }
            
            # Store data and metadata
            $this.CacheStorage[$key] = $storedData
            $this.CacheMetadata[$key] = @{
                CreatedTime = Get-Date
                ExpiryTime = $expiryTime
                LastAccessed = Get-Date
                AccessCount = 0
                TTLMinutes = $ttl
                IsCompressed = $this.CacheConfiguration.CompressionEnabled
                DataSize = $this.CalculateDataSize($data)
                DataType = $data.GetType().Name
            }
            
            $this.Logger.WriteDebug("Cached data for key: $key (TTL: $ttl minutes)")
            
        } catch {
            $this.Logger.WriteError("Failed to cache data for key: $key", $_.Exception)
        }
    }
    
    # Check if cache entry is valid
    [bool] IsValidCacheEntry([string] $key) {
        if (-not $this.CacheStorage.ContainsKey($key)) {
            return $false
        }
        
        $metadata = $this.CacheMetadata[$key]
        if ((Get-Date) -gt $metadata.ExpiryTime) {
            $this.RemoveCacheEntry($key)
            return $false
        }
        
        return $true
    }
    
    # Retrieve cached data with decompression
    [object] RetrieveCachedData([string] $key) {
        $storedData = $this.CacheStorage[$key]
        $metadata = $this.CacheMetadata[$key]
        
        if ($metadata.IsCompressed) {
            return $this.DecompressData($storedData)
        }
        
        return $storedData
    }    
   
 # Evict least recently used entries
    [void] EvictLeastRecentlyUsed() {
        try {
            # Find LRU entry
            $lruKey = $null
            $oldestAccess = Get-Date
            
            foreach ($key in $this.CacheMetadata.Keys) {
                $lastAccessed = $this.CacheMetadata[$key].LastAccessed
                if ($lastAccessed -lt $oldestAccess) {
                    $oldestAccess = $lastAccessed
                    $lruKey = $key
                }
            }
            
            if ($lruKey) {
                $this.RemoveCacheEntry($lruKey)
                $this.CacheStatistics.CacheEvictions++
                $this.Logger.WriteDebug("Evicted LRU cache entry: $lruKey")
            }
            
        } catch {
            $this.Logger.WriteError("Failed to evict LRU cache entry", $_.Exception)
        }
    }
    
    # Remove cache entry
    [void] RemoveCacheEntry([string] $key) {
        $this.CacheStorage.Remove($key)
        $this.CacheMetadata.Remove($key)
    }
    
    # Perform cache cleanup
    [void] PerformCacheCleanup() {
        try {
            $expiredKeys = @()
            $currentTime = Get-Date
            
            foreach ($key in $this.CacheMetadata.Keys) {
                if ($currentTime -gt $this.CacheMetadata[$key].ExpiryTime) {
                    $expiredKeys += $key
                }
            }
            
            foreach ($key in $expiredKeys) {
                $this.RemoveCacheEntry($key)
            }
            
            if ($expiredKeys.Count -gt 0) {
                $this.Logger.WriteDebug("Cache cleanup removed $($expiredKeys.Count) expired entries")
            }
            
        } catch {
            $this.Logger.WriteError("Cache cleanup failed", $_.Exception)
        }
    }
    
    # Warm cache with common data patterns
    [void] WarmCache([hashtable] $warmingData) {
        if (-not $this.CacheConfiguration.EnableCacheWarming) { return }
        
        try {
            foreach ($key in $warmingData.Keys) {
                $data = $warmingData[$key]
                $this.CacheData($key, $data.Value, $data.TTL)
                $this.CacheStatistics.CacheWarmingOperations++
            }
            
            $this.Logger.WriteInformation("Cache warming completed with $($warmingData.Count) entries")
            
        } catch {
            $this.Logger.WriteError("Cache warming failed", $_.Exception)
        }
    }
    
    # Trigger predictive prefetch
    [void] TriggerPredictivePrefetch([string] $accessedKey) {
        if (-not $this.CacheConfiguration.EnablePredictivePrefetch) { return }
        
        try {
            # Simple predictive logic - prefetch related keys
            $relatedKeys = $this.GetRelatedKeys($accessedKey)
            
            foreach ($relatedKey in $relatedKeys) {
                if (-not $this.CacheStorage.ContainsKey($relatedKey)) {
                    # This would trigger background prefetch in a real implementation
                    $this.Logger.WriteDebug("Predictive prefetch candidate: $relatedKey")
                    $this.CacheStatistics.PrefetchOperations++
                }
            }
            
        } catch {
            $this.Logger.WriteError("Predictive prefetch failed for key: $accessedKey", $_.Exception)
        }
    }
    
    # Get related keys for predictive prefetch
    [array] GetRelatedKeys([string] $key) {
        $relatedKeys = @()
        
        # Simple pattern matching for related keys
        if ($key -match "^VM_(.+)_Info$") {
            $vmName = $Matches[1]
            $relatedKeys += @(
                "VM_${vmName}_Performance",
                "VM_${vmName}_Network",
                "VM_${vmName}_Storage"
            )
        } elseif ($key -match "^Host_(.+)_Info$") {
            $hostName = $Matches[1]
            $relatedKeys += @(
                "Host_${hostName}_VMs",
                "Host_${hostName}_Performance",
                "Host_${hostName}_Network"
            )
        }
        
        return $relatedKeys
    }
    
    # Compress data for storage
    [object] CompressData([object] $data) {
        try {
            # Simple compression simulation - in real implementation would use actual compression
            $serialized = $data | ConvertTo-Json -Compress
            $compressed = [System.Text.Encoding]::UTF8.GetBytes($serialized)
            
            $originalSize = $this.CalculateDataSize($data)
            $compressedSize = $compressed.Length
            $this.CacheStatistics.CompressionSavings += ($originalSize - $compressedSize)
            
            return @{
                CompressedData = $compressed
                OriginalType = $data.GetType().Name
            }
            
        } catch {
            $this.Logger.WriteWarning("Data compression failed, storing uncompressed")
            return $data
        }
    }
    
    # Decompress data
    [object] DecompressData([object] $compressedData) {
        try {
            if ($compressedData -is [hashtable] -and $compressedData.ContainsKey('CompressedData')) {
                $jsonString = [System.Text.Encoding]::UTF8.GetString($compressedData.CompressedData)
                return $jsonString | ConvertFrom-Json
            }
            
            return $compressedData
            
        } catch {
            $this.Logger.WriteWarning("Data decompression failed, returning as-is")
            return $compressedData
        }
    }
    
    # Calculate data size
    [int] CalculateDataSize([object] $data) {
        try {
            $serialized = $data | ConvertTo-Json
            return [System.Text.Encoding]::UTF8.GetByteCount($serialized)
        } catch {
            return 1024  # Default estimate
        }
    }
    
    # Update average retrieval time
    [void] UpdateAverageRetrievalTime([double] $retrievalTimeMs) {
        $totalRequests = $this.CacheStatistics.TotalRequests
        $currentAverage = $this.CacheStatistics.AverageRetrievalTime
        
        # Calculate running average
        $this.CacheStatistics.AverageRetrievalTime = (($currentAverage * ($totalRequests - 1)) + $retrievalTimeMs) / $totalRequests
    }
    
    # Get cache statistics
    [hashtable] GetCacheStatistics() {
        $hitRatio = if ($this.CacheStatistics.TotalRequests -gt 0) {
            $this.CacheStatistics.CacheHits / $this.CacheStatistics.TotalRequests
        } else { 0.0 }
        
        $totalCacheSize = 0
        foreach ($key in $this.CacheMetadata.Keys) {
            $totalCacheSize += $this.CacheMetadata[$key].DataSize
        }
        
        return @{
            TotalRequests = $this.CacheStatistics.TotalRequests
            CacheHits = $this.CacheStatistics.CacheHits
            CacheMisses = $this.CacheStatistics.CacheMisses
            HitRatio = [Math]::Round($hitRatio, 4)
            CacheEvictions = $this.CacheStatistics.CacheEvictions
            CacheWarmingOperations = $this.CacheStatistics.CacheWarmingOperations
            PrefetchOperations = $this.CacheStatistics.PrefetchOperations
            CompressionSavingsBytes = $this.CacheStatistics.CompressionSavings
            AverageRetrievalTimeMs = [Math]::Round($this.CacheStatistics.AverageRetrievalTime, 2)
            CurrentCacheSize = $this.CacheStorage.Count
            MaxCacheSize = $this.CacheConfiguration.MaxCacheSize
            TotalCacheSizeBytes = $totalCacheSize
            IsEnabled = $this.IsEnabled
        }
    }
    
    # Configure cache settings
    [void] ConfigureCache([hashtable] $settings) {
        foreach ($key in $settings.Keys) {
            if ($this.CacheConfiguration.ContainsKey($key)) {
                $this.CacheConfiguration[$key] = $settings[$key]
                $this.Logger.WriteDebug("Updated cache setting: $key = $($settings[$key])")
            }
        }
        
        $this.Logger.WriteInformation("Cache configuration updated")
    }
    
    # Clear cache
    [void] ClearCache() {
        $entriesCleared = $this.CacheStorage.Count
        $this.CacheStorage.Clear()
        $this.CacheMetadata.Clear()
        
        $this.Logger.WriteInformation("Cache cleared: $entriesCleared entries removed")
    }
    
    # ========================================
    # PERFORMANCE OPTIMIZATION METHODS
    # ========================================
    
    [void] InitializeOptimizationSettings() {
        $this.OptimizationSettings = @{
            # Memory Management
            MemoryManagement = @{
                EnableGarbageCollection = $true
                GCInterval = 100  # VMs processed before GC
                MaxMemoryThresholdMB = 2048
                MemoryPressureThreshold = 0.8
                EnableMemoryMonitoring = $true
            }
            
            # Thread Pool Optimization
            ThreadPoolOptimization = @{
                EnableDynamicThreading = $true
                MinThreads = 1
                MaxThreads = 50
                ThreadScalingFactor = 1.5
                ThreadIdleTimeout = 30000  # milliseconds
                EnableThreadMonitoring = $true
            }
            
            # API Call Optimization
            APIOptimization = @{
                EnableBulkOperations = $true
                BatchSize = 100
                EnableAPICallCaching = $true
                CacheExpirationMinutes = 30
                MaxRetryAttempts = 3
                RetryDelaySeconds = 5
            }
            
            # Data Processing Optimization
            DataProcessing = @{
                EnableStreamProcessing = $true
                EnableDataCompression = $false
                EnableParallelValidation = $true
                ValidationBatchSize = 50
                EnableProgressiveOutput = $true
            }
            
            # Network Optimization
            NetworkOptimization = @{
                EnableConnectionPooling = $true
                MaxConnectionsPerHost = 10
                ConnectionTimeout = 300  # seconds
                ReadTimeout = 120  # seconds
                EnableKeepAlive = $true
            }
        }
    }
    
    [void] InitializeErrorHandling() {
        $this.ErrorHandlingConfig = @{
            # Retry Configuration
            RetryConfig = @{
                MaxRetryAttempts = 3
                BaseDelaySeconds = 2
                MaxDelaySeconds = 60
                ExponentialBackoff = $true
                JitterEnabled = $true
            }
            
            # Error Classification
            ErrorClassification = @{
                TransientErrors = @(
                    "TimeoutException",
                    "SocketException", 
                    "HttpRequestException",
                    "TaskCanceledException"
                )
                PermanentErrors = @(
                    "UnauthorizedAccessException",
                    "SecurityException",
                    "ArgumentException"
                )
                RecoverableErrors = @(
                    "InvalidOperationException",
                    "COMException",
                    "PowerCLIException"
                )
            }
            
            # Circuit Breaker
            CircuitBreaker = @{
                Enabled = $true
                FailureThreshold = 5
                TimeoutSeconds = 60
                HalfOpenRetryCount = 3
            }
            
            # Graceful Degradation
            GracefulDegradation = @{
                EnableFallbackMethods = $true
                EnablePartialResults = $true
                EnableSkipOnError = $true
                MaxErrorPercentage = 10
            }
        }
    }    
  
  [hashtable] OptimizeForEnvironment([int] $VMCount, [hashtable] $UserSettings) {
        $this.Logger.WriteInformation("Optimizing for environment with $VMCount VMs")
        
        # Determine environment size
        $environmentType = $this.DetermineEnvironmentType($VMCount)
        $this.Logger.WriteInformation("Environment type: $environmentType")
        
        # Get base optimization settings
        $optimizedSettings = $this.GetOptimizedSettings($environmentType, $VMCount)
        
        # Apply user overrides
        $optimizedSettings = $this.ApplyUserOverrides($optimizedSettings, $UserSettings)
        
        # Validate settings
        $optimizedSettings = $this.ValidateSettings($optimizedSettings)
        
        # Log optimization decisions
        $this.LogOptimizationDecisions($optimizedSettings, $environmentType)
        
        $this.IsOptimized = $true
        return $optimizedSettings
    }
    
    [string] DetermineEnvironmentType([int] $VMCount) {
        if ($VMCount -le $this.PerformanceThresholds.SmallEnvironment.MaxVMs) {
            return "SmallEnvironment"
        } elseif ($VMCount -le $this.PerformanceThresholds.MediumEnvironment.MaxVMs) {
            return "MediumEnvironment"
        } elseif ($VMCount -le $this.PerformanceThresholds.LargeEnvironment.MaxVMs) {
            return "LargeEnvironment"
        } else {
            return "UltraLargeEnvironment"
        }
    }
    
    [hashtable] GetOptimizedSettings([string] $EnvironmentType, [int] $VMCount) {
        $settings = @{}
        
        switch ($EnvironmentType) {
            "SmallEnvironment" {
                $settings = @{
                    MaxThreads = [Math]::Min(15, [Math]::Max(5, [Math]::Ceiling($VMCount / 100)))
                    FastMode = $false
                    PoweredOnOnly = $false
                    SkipPerformanceData = $false
                    CollectionDays = 7
                    BatchSize = 50
                    EnableMemoryOptimization = $false
                    EnableProgressiveOutput = $false
                }
            }
            "MediumEnvironment" {
                $settings = @{
                    MaxThreads = [Math]::Min(25, [Math]::Max(10, [Math]::Ceiling($VMCount / 200)))
                    FastMode = $false
                    PoweredOnOnly = $false
                    SkipPerformanceData = $false
                    CollectionDays = 7
                    BatchSize = 100
                    EnableMemoryOptimization = $true
                    EnableProgressiveOutput = $true
                }
            }
            "LargeEnvironment" {
                $settings = @{
                    MaxThreads = [Math]::Min(35, [Math]::Max(20, [Math]::Ceiling($VMCount / 300)))
                    FastMode = $true
                    PoweredOnOnly = $false
                    SkipPerformanceData = $false
                    CollectionDays = 3
                    BatchSize = 150
                    EnableMemoryOptimization = $true
                    EnableProgressiveOutput = $true
                }
            }
            "UltraLargeEnvironment" {
                $settings = @{
                    MaxThreads = [Math]::Min(50, [Math]::Max(30, [Math]::Ceiling($VMCount / 400)))
                    FastMode = $true
                    PoweredOnOnly = $true
                    SkipPerformanceData = $false
                    CollectionDays = 1
                    BatchSize = 200
                    EnableMemoryOptimization = $true
                    EnableProgressiveOutput = $true
                }
            }
        }
        
        return $settings
    }
    
    [hashtable] ApplyUserOverrides([hashtable] $OptimizedSettings, [hashtable] $UserSettings) {
        foreach ($key in $UserSettings.Keys) {
            if ($OptimizedSettings.ContainsKey($key)) {
                $originalValue = $OptimizedSettings[$key]
                $OptimizedSettings[$key] = $UserSettings[$key]
                $this.Logger.WriteInformation("User override: $key = $($UserSettings[$key]) (was $originalValue)")
            }
        }
        
        return $OptimizedSettings
    }
    
    [hashtable] ValidateSettings([hashtable] $Settings) {
        # Validate thread count
        if ($Settings.MaxThreads -lt 1) {
            $Settings.MaxThreads = 1
            $this.Logger.WriteWarning("MaxThreads adjusted to minimum value: 1")
        } elseif ($Settings.MaxThreads -gt 50) {
            $Settings.MaxThreads = 50
            $this.Logger.WriteWarning("MaxThreads adjusted to maximum value: 50")
        }
        
        # Validate collection days
        if ($Settings.CollectionDays -lt 1) {
            $Settings.CollectionDays = 1
            $this.Logger.WriteWarning("CollectionDays adjusted to minimum value: 1")
        } elseif ($Settings.CollectionDays -gt 365) {
            $Settings.CollectionDays = 365
            $this.Logger.WriteWarning("CollectionDays adjusted to maximum value: 365")
        }
        
        # Validate batch size
        if ($Settings.BatchSize -lt 10) {
            $Settings.BatchSize = 10
            $this.Logger.WriteWarning("BatchSize adjusted to minimum value: 10")
        } elseif ($Settings.BatchSize -gt 500) {
            $Settings.BatchSize = 500
            $this.Logger.WriteWarning("BatchSize adjusted to maximum value: 500")
        }
        
        return $Settings
    }
    
    [void] LogOptimizationDecisions([hashtable] $Settings, [string] $EnvironmentType) {
        $this.Logger.WriteInformation("Optimization decisions for $EnvironmentType`:")
        $this.Logger.WriteInformation("  MaxThreads: $($Settings.MaxThreads)")
        $this.Logger.WriteInformation("  FastMode: $($Settings.FastMode)")
        $this.Logger.WriteInformation("  PoweredOnOnly: $($Settings.PoweredOnOnly)")
        $this.Logger.WriteInformation("  SkipPerformanceData: $($Settings.SkipPerformanceData)")
        $this.Logger.WriteInformation("  CollectionDays: $($Settings.CollectionDays)")
        $this.Logger.WriteInformation("  BatchSize: $($Settings.BatchSize)")
        $this.Logger.WriteInformation("  EnableMemoryOptimization: $($Settings.EnableMemoryOptimization)")
        $this.Logger.WriteInformation("  EnableProgressiveOutput: $($Settings.EnableProgressiveOutput)")
    }
    
    [void] MonitorPerformance([hashtable] $Metrics) {
        $this.PerformanceMetrics = $Metrics
        
        # Check if performance is within expected thresholds
        $environmentType = $this.DetermineEnvironmentType($Metrics.VMCount)
        $threshold = $this.PerformanceThresholds[$environmentType]
        
        if ($Metrics.DurationMinutes -gt $threshold.TargetMinutes * 1.5) {
            $this.Logger.WriteWarning("Performance below target: $($Metrics.DurationMinutes) minutes (target: $($threshold.TargetMinutes))")
            $this.SuggestOptimizations($Metrics, $environmentType)
        }
        
        if ($Metrics.MemoryUsageMB -gt $threshold.MaxMemoryMB) {
            $this.Logger.WriteWarning("Memory usage above threshold: $($Metrics.MemoryUsageMB) MB (max: $($threshold.MaxMemoryMB))")
            $this.SuggestMemoryOptimizations($Metrics)
        }
    }
    
    [void] SuggestOptimizations([hashtable] $Metrics, [string] $EnvironmentType) {
        $suggestions = @()
        
        if (-not $Metrics.FastMode -and $Metrics.VMCount -gt 1000) {
            $suggestions += "Enable FastMode for better performance"
        }
        
        if ($Metrics.MaxThreads -lt 20 -and $EnvironmentType -in @("LargeEnvironment", "UltraLargeEnvironment")) {
            $suggestions += "Increase MaxThreads to $([Math]::Min(50, $Metrics.MaxThreads * 2))"
        }
        
        if (-not $Metrics.PoweredOnOnly -and $EnvironmentType -eq "UltraLargeEnvironment") {
            $suggestions += "Consider using PoweredOnOnly filter"
        }
        
        if ($Metrics.CollectionDays -gt 7 -and $Metrics.DurationMinutes -gt 60) {
            $suggestions += "Reduce CollectionDays to improve performance"
        }
        
        foreach ($suggestion in $suggestions) {
            $this.Logger.WriteInformation("Performance suggestion: $suggestion")
        }
    }
    
    [void] SuggestMemoryOptimizations([hashtable] $Metrics) {
        $suggestions = @()
        
        $suggestions += "Enable memory optimization features"
        $suggestions += "Reduce MaxThreads to lower memory usage"
        $suggestions += "Process VMs in smaller batches"
        $suggestions += "Consider running on system with more RAM"
        
        foreach ($suggestion in $suggestions) {
            $this.Logger.WriteInformation("Memory optimization suggestion: $suggestion")
        }
    }
    
    [hashtable] HandleError([Exception] $Exception, [string] $Context, [int] $AttemptNumber = 1) {
        $errorInfo = @{
            Exception = $Exception
            Context = $Context
            AttemptNumber = $AttemptNumber
            IsRetryable = $false
            SuggestedAction = "None"
            DelaySeconds = 0
        }
        
        # Classify error type
        $errorType = $this.ClassifyError($Exception)
        $errorInfo.ErrorType = $errorType
        
        # Determine if error is retryable
        $errorInfo.IsRetryable = $this.IsRetryableError($errorType, $AttemptNumber)
        
        # Calculate retry delay
        if ($errorInfo.IsRetryable) {
            $errorInfo.DelaySeconds = $this.CalculateRetryDelay($AttemptNumber)
            $errorInfo.SuggestedAction = "Retry"
        } else {
            $errorInfo.SuggestedAction = $this.GetErrorSuggestion($errorType, $Exception)
        }
        
        # Log error details
        $this.LogErrorDetails($errorInfo)
        
        return $errorInfo
    }
    
    [string] ClassifyError([Exception] $Exception) {
        $exceptionType = $Exception.GetType().Name
        
        if ($exceptionType -in $this.ErrorHandlingConfig.ErrorClassification.TransientErrors) {
            return "Transient"
        } elseif ($exceptionType -in $this.ErrorHandlingConfig.ErrorClassification.PermanentErrors) {
            return "Permanent"
        } elseif ($exceptionType -in $this.ErrorHandlingConfig.ErrorClassification.RecoverableErrors) {
            return "Recoverable"
        } else {
            return "Unknown"
        }
    }
    
    [bool] IsRetryableError([string] $ErrorType, [int] $AttemptNumber) {
        if ($AttemptNumber -ge $this.ErrorHandlingConfig.RetryConfig.MaxRetryAttempts) {
            return $false
        }
        
        return $ErrorType -in @("Transient", "Recoverable")
    }
    
    [int] CalculateRetryDelay([int] $AttemptNumber) {
        $baseDelay = $this.ErrorHandlingConfig.RetryConfig.BaseDelaySeconds
        $maxDelay = $this.ErrorHandlingConfig.RetryConfig.MaxDelaySeconds
        
        if ($this.ErrorHandlingConfig.RetryConfig.ExponentialBackoff) {
            $delay = $baseDelay * [Math]::Pow(2, $AttemptNumber - 1)
        } else {
            $delay = $baseDelay
        }
        
        # Add jitter if enabled
        if ($this.ErrorHandlingConfig.RetryConfig.JitterEnabled) {
            $jitter = Get-Random -Minimum 0 -Maximum ($delay * 0.1)
            $delay += $jitter
        }
        
        return [Math]::Min($delay, $maxDelay)
    }
    
    [string] GetErrorSuggestion([string] $ErrorType, [Exception] $Exception) {
        switch ($ErrorType) {
            "Permanent" {
                return "Check credentials and permissions"
            }
            "Transient" {
                return "Retry operation after delay"
            }
            "Recoverable" {
                return "Check system resources and retry"
            }
            default {
                return "Review error details and system configuration"
            }
        }
        
        # Fallback return (should never reach here due to switch default)
        return "Review error details and system configuration"
    }
    
    [void] LogErrorDetails([hashtable] $ErrorInfo) {
        $this.Logger.WriteError("Error in $($ErrorInfo.Context): $($ErrorInfo.Exception.Message)")
        $this.Logger.WriteError("Error Type: $($ErrorInfo.ErrorType)")
        $this.Logger.WriteError("Attempt: $($ErrorInfo.AttemptNumber)")
        $this.Logger.WriteError("Retryable: $($ErrorInfo.IsRetryable)")
        $this.Logger.WriteError("Suggested Action: $($ErrorInfo.SuggestedAction)")
        
        if ($ErrorInfo.IsRetryable) {
            $this.Logger.WriteInformation("Will retry in $($ErrorInfo.DelaySeconds) seconds")
        }
    }
    
    [void] OptimizeMemoryUsage() {
        if (-not $this.OptimizationSettings.MemoryManagement.EnableGarbageCollection) {
            return
        }
        
        $beforeMemory = [System.GC]::GetTotalMemory($false)
        
        # Force garbage collection
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
        
        $afterMemory = [System.GC]::GetTotalMemory($false)
        $freedMemory = ($beforeMemory - $afterMemory) / 1MB
        
        if ($freedMemory -gt 10) {
            $this.Logger.WriteInformation("Memory optimization freed $([Math]::Round($freedMemory, 1)) MB")
        }
    }
    
    [bool] CheckMemoryPressure() {
        $currentProcess = Get-Process -Id $global:PID
        $memoryUsageMB = $currentProcess.WorkingSet64 / 1MB
        $maxMemoryMB = $this.OptimizationSettings.MemoryManagement.MaxMemoryThresholdMB
        
        $memoryPressure = $memoryUsageMB / $maxMemoryMB
        
        if ($memoryPressure -gt $this.OptimizationSettings.MemoryManagement.MemoryPressureThreshold) {
            $this.Logger.WriteWarning("Memory pressure detected: $([Math]::Round($memoryPressure * 100, 1))%")
            return $true
        }
        
        return $false
    }
    
    # ========================================
    # UNIFIED OPTIMIZATION METHODS
    # ========================================
    
    [hashtable] GetOptimizationSummary() {
        return @{
            IsOptimized = $this.IsOptimized
            OptimizationSettings = $this.OptimizationSettings
            PerformanceMetrics = $this.PerformanceMetrics
            ErrorHandlingConfig = $this.ErrorHandlingConfig
            CacheStatistics = $this.GetCacheStatistics()
            MemoryOptimizationEnabled = $this.OptimizationSettings.MemoryManagement.EnableGarbageCollection
            ThreadOptimizationEnabled = $this.OptimizationSettings.ThreadPoolOptimization.EnableDynamicThreading
            APIOptimizationEnabled = $this.OptimizationSettings.APIOptimization.EnableBulkOperations
            CacheOptimizationEnabled = $this.IsEnabled
        }
    }
    
    # Dispose and cleanup
    [void] Dispose() {
        try {
            if ($this.CleanupTimer) {
                $this.CleanupTimer.Stop()
                $this.CleanupTimer.Dispose()
            }
            
            $this.ClearCache()
            $this.Logger.WriteInformation("OptimizationEngine disposed")
            
        } catch {
            $this.Logger.WriteError("Failed to dispose OptimizationEngine", $_.Exception)
        }
    }
}