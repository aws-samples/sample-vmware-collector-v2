#
# PerformanceCalculationEngine.ps1 - Advanced performance calculation engine
#
# Implements precise P95 and average calculations for CPU/memory metrics,
# default value handling for powered-off VMs, and memory utilization capping
# at 100% with comprehensive statistical analysis and validation.
# 
# CONSOLIDATED: Includes functionality from AdvancedPerformanceCalculator.ps1
#

# Import required interfaces and models
. "$PSScriptRoot\Interfaces.ps1"
. "$PSScriptRoot\PerformanceDataModel.ps1"

class PerformanceCalculationEngine {
    [ILogger] $Logger
    [hashtable] $DefaultValues
    [hashtable] $CalculationSettings
    [hashtable] $StatisticalCache
    [bool] $EnableCaching
    [int] $CacheMaxSize
    
    # Advanced statistical properties (from AdvancedPerformanceCalculator)
    [hashtable] $StatisticalSettings
    [hashtable] $TimezoneSettings
    [hashtable] $ConfidenceIntervalCache
    [hashtable] $StatisticalAnalysisCache
    [System.TimeZoneInfo] $SourceTimeZone
    [System.TimeZoneInfo] $TargetTimeZone
    
    # Constructor
    PerformanceCalculationEngine([ILogger] $logger) {
        $this.Logger = $logger
        $this.EnableCaching = $true
        $this.CacheMaxSize = 1000
        $this.StatisticalCache = @{}
        
        # Initialize advanced statistical caches (from AdvancedPerformanceCalculator)
        $this.ConfidenceIntervalCache = @{}
        $this.StatisticalAnalysisCache = @{}
        
        # Statistical analysis settings (from AdvancedPerformanceCalculator)
        $this.StatisticalSettings = @{
            ConfidenceLevel = 0.95  # 95% confidence intervals
            MinSampleSizeForCI = 30  # Minimum samples for reliable confidence intervals
            EnableBootstrapping = $true
            BootstrapSamples = 1000
            EnableTrendAnalysis = $true
            SeasonalityDetection = $true
            OutlierDetectionMethod = 'IQR'  # IQR, ZScore, or ModifiedZScore
            IQRMultiplier = 1.5
            ZScoreThreshold = 3.0
            ModifiedZScoreThreshold = 3.5
            EnableDataQualityScoring = $true
            MinDataPointsForReliability = 10
            MaxAcceptableGapHours = 4
        }
        
        # Timezone and DST handling settings (from AdvancedPerformanceCalculator)
        $this.TimezoneSettings = @{
            EnableTimezoneConversion = $true
            HandleDaylightSavingTime = $true
            DefaultSourceTimezone = "UTC"
            DefaultTargetTimezone = [System.TimeZoneInfo]::Local.Id
        }
        
        # Default performance values for powered-off VMs (as per requirements)
        $this.DefaultValues = @{
            PoweredOff = @{
                MaxCpuUsagePct = 25.0
                AvgCpuUsagePct = 25.0
                MaxRamUsagePct = 60.0
                AvgRamUsagePct = 60.0
            }
            PoweredOn = @{
                MaxCpuUsagePct = 25.0
                AvgCpuUsagePct = 25.0
                MaxRamUsagePct = 60.0
                AvgRamUsagePct = 60.0
            }
            Unknown = @{
                MaxCpuUsagePct = 25.0
                AvgCpuUsagePct = 25.0
                MaxRamUsagePct = 60.0
                AvgRamUsagePct = 60.0
            }
        }
        
        # Calculation settings for precision and validation
        $this.CalculationSettings = @{
            DecimalPrecision = 2
            MemoryCapAt100Percent = $true
            ValidateLogicalRelationships = $true
            EnableOutlierDetection = $false
            OutlierThreshold = 3.0  # Standard deviations
            MinDataPointsForP95 = 5
            MaxAllowedCpuPercent = 100.0
            MaxAllowedMemoryPercent = 100.0
        }
        
        $this.Logger.WriteInformation("PerformanceCalculationEngine initialized with caching=$($this.EnableCaching), precision=$($this.CalculationSettings.DecimalPrecision) decimals")
    }
    
    # Calculate P95 (95th percentile) with advanced statistical analysis
    [double] CalculateP95([array] $values, [string] $metricName = "Unknown") {
        try {
            if (-not $values -or $values.Count -eq 0) {
                $this.Logger.WriteDebug("No values provided for P95 calculation of $metricName, returning 0.0")
                return 0.0
            }
            
            # Check cache first
            $cacheKey = "P95_$metricName" + "_" + ($values | ConvertTo-Json -Compress | Get-FileHash -Algorithm MD5).Hash
            if ($this.EnableCaching -and $this.StatisticalCache.ContainsKey($cacheKey)) {
                $this.Logger.WriteDebug("Using cached P95 value for $metricName")
                return $this.StatisticalCache[$cacheKey]
            }
            
            # Validate minimum data points for reliable P95
            if ($values.Count -lt $this.CalculationSettings.MinDataPointsForP95) {
                $this.Logger.WriteWarning("Insufficient data points ($($values.Count)) for reliable P95 calculation of $metricName, using maximum value")
                $result = ($values | Measure-Object -Maximum).Maximum
                return [Math]::Round($result, $this.CalculationSettings.DecimalPrecision)
            }
            
            # Remove outliers if enabled
            $cleanedValues = if ($this.CalculationSettings.EnableOutlierDetection) {
                $this.RemoveOutliers($values, $metricName)
            } else {
                $values
            }
            
            # Sort values in ascending order for percentile calculation
            $sortedValues = $cleanedValues | Sort-Object
            
            # Calculate 95th percentile index using the nearest-rank method
            $p95Index = [Math]::Ceiling($sortedValues.Count * 0.95) - 1
            $p95Index = [Math]::Max(0, [Math]::Min($p95Index, $sortedValues.Count - 1))
            
            $p95Value = $sortedValues[$p95Index]
            
            # Apply metric-specific capping
            $cappedValue = $this.ApplyMetricCapping($p95Value, $metricName)
            
            # Round to specified precision
            $result = [Math]::Round($cappedValue, $this.CalculationSettings.DecimalPrecision)
            
            # Cache result
            if ($this.EnableCaching -and $this.StatisticalCache.Count -lt $this.CacheMaxSize) {
                $this.StatisticalCache[$cacheKey] = $result
            }
            
            $this.Logger.WriteDebug("P95 calculation for ${metricName}: $result (from $($values.Count) data points)")
            return $result
        }
        catch {
            $this.Logger.WriteError("P95 calculation failed for ${metricName}: $($_.Exception.Message)", $_.Exception)
            return 0.0
        }
    }
    
    # Calculate average with statistical validation
    [double] CalculateAverage([array] $values, [string] $metricName = "Unknown") {
        try {
            if (-not $values -or $values.Count -eq 0) {
                $this.Logger.WriteDebug("No values provided for average calculation of $metricName, returning 0.0")
                return 0.0
            }
            
            # Check cache first
            $cacheKey = "AVG_$metricName" + "_" + ($values | ConvertTo-Json -Compress | Get-FileHash -Algorithm MD5).Hash
            if ($this.EnableCaching -and $this.StatisticalCache.ContainsKey($cacheKey)) {
                $this.Logger.WriteDebug("Using cached average value for $metricName")
                return $this.StatisticalCache[$cacheKey]
            }
            
            # Remove outliers if enabled
            $cleanedValues = if ($this.CalculationSettings.EnableOutlierDetection) {
                $this.RemoveOutliers($values, $metricName)
            } else {
                $values
            }
            
            # Calculate average
            $sum = ($cleanedValues | Measure-Object -Sum).Sum
            $average = $sum / $cleanedValues.Count
            
            # Apply metric-specific capping
            $cappedAverage = $this.ApplyMetricCapping($average, $metricName)
            
            # Round to specified precision
            $result = [Math]::Round($cappedAverage, $this.CalculationSettings.DecimalPrecision)
            
            # Cache result
            if ($this.EnableCaching -and $this.StatisticalCache.Count -lt $this.CacheMaxSize) {
                $this.StatisticalCache[$cacheKey] = $result
            }
            
            $this.Logger.WriteDebug("Average calculation for ${metricName}: $result (from $($values.Count) data points)")
            return $result
        }
        catch {
            $this.Logger.WriteError("Average calculation failed for ${metricName}: $($_.Exception.Message)", $_.Exception)
            return 0.0
        }
    }
    
    # Calculate memory utilization with exact formula and 100% capping
    [double] CalculateMemoryUtilization([double] $consumedMemoryMB, [double] $allocatedMemoryMB, [string] $vmName = "Unknown") {
        try {
            if ($allocatedMemoryMB -le 0) {
                $this.Logger.WriteWarning("Invalid allocated memory ($allocatedMemoryMB MB) for VM '$vmName', returning 0.0")
                return 0.0
            }
            
            if ($consumedMemoryMB -lt 0) {
                $this.Logger.WriteWarning("Invalid consumed memory ($consumedMemoryMB MB) for VM '$vmName', using 0.0")
                $consumedMemoryMB = 0.0
            }
            
            # Exact formula as per requirements: (Consumed Memory MB / VM.MemoryMB) * 100
            $utilizationPercent = ($consumedMemoryMB / $allocatedMemoryMB) * 100
            
            # Cap at 100% to prevent values exceeding limits (requirement 2.8)
            if ($this.CalculationSettings.MemoryCapAt100Percent) {
                $cappedUtilization = [Math]::Min(100.0, $utilizationPercent)
                
                if ($utilizationPercent -gt 100.0) {
                    $this.Logger.WriteDebug("Memory utilization for VM '$vmName' capped at 100% (was $([Math]::Round($utilizationPercent, 2))%)")
                }
            }
            else {
                $cappedUtilization = $utilizationPercent
            }
            
            # Ensure non-negative result
            $result = [Math]::Max(0.0, $cappedUtilization)
            
            # Round to specified precision
            $finalResult = [Math]::Round($result, $this.CalculationSettings.DecimalPrecision)
            
            $this.Logger.WriteDebug("Memory utilization for VM '$vmName': $finalResult% (consumed: $consumedMemoryMB MB, allocated: $allocatedMemoryMB MB)")
            return $finalResult
        }
        catch {
            $this.Logger.WriteError("Memory utilization calculation failed for VM '$vmName': $($_.Exception.Message)", $_.Exception)
            return 0.0
        }
    }
    
    # Get default performance values based on VM power state
    [hashtable] GetDefaultPerformanceValues([string] $powerState, [string] $vmName = "Unknown") {
        try {
            $this.Logger.WriteDebug("Getting default performance values for VM '$vmName' with power state '$powerState'")
            
            # Normalize power state
            $normalizedPowerState = switch ($powerState) {
                "PoweredOff" { "PoweredOff" }
                "PoweredOn" { "PoweredOn" }
                default { "Unknown" }
            }
            
            # Get default values for the power state
            $defaults = $this.DefaultValues[$normalizedPowerState].Clone()
            
            # Add metadata
            $defaults.IsDefaultData = $true
            $defaults.PowerState = $powerState
            $defaults.VMName = $vmName
            $defaults.CalculationTimestamp = Get-Date
            $defaults.DataQualityScore = if ($normalizedPowerState -eq "PoweredOff") { 0.0 } else { 0.1 }
            
            $this.Logger.WriteInformation("Applied default performance values for VM '$vmName' (PowerState: $powerState): CPU Max/Avg=$($defaults.MaxCpuUsagePct)%/$($defaults.AvgCpuUsagePct)%, Memory Max/Avg=$($defaults.MaxRamUsagePct)%/$($defaults.AvgRamUsagePct)%")
            
            return $defaults
        }
        catch {
            $this.Logger.WriteError("Failed to get default performance values for VM '$vmName': $($_.Exception.Message)", $_.Exception)
            
            # Return safe fallback values
            return @{
                MaxCpuUsagePct = 25.0
                AvgCpuUsagePct = 25.0
                MaxRamUsagePct = 60.0
                AvgRamUsagePct = 60.0
                IsDefaultData = $true
                PowerState = $powerState
                VMName = $vmName
                CalculationTimestamp = Get-Date
                DataQualityScore = 0.0
            }
        }
    }
    
    # Calculate comprehensive performance metrics for a VM
    [hashtable] CalculateVMPerformanceMetrics([object] $vm, [array] $cpuStats, [array] $memoryStats) {
        try {
            $this.Logger.WriteDebug("Calculating comprehensive performance metrics for VM '$($vm.Name)'")
            
            $result = @{
                VMName = $vm.Name
                PowerState = $vm.PowerState
                CalculationTimestamp = Get-Date
                IsDefaultData = $false
                DataQualityScore = 0.0
                ValidationErrors = @()
            }
            
            # Check if VM is powered off - use default values
            if ($vm.PowerState -eq "PoweredOff") {
                $defaults = $this.GetDefaultPerformanceValues($vm.PowerState, $vm.Name)
                foreach ($key in $defaults.Keys) {
                    $result[$key] = $defaults[$key]
                }
                return $result
            }
            
            # Calculate CPU metrics
            if ($cpuStats -and $cpuStats.Count -gt 0) {
                $cpuValues = $cpuStats | ForEach-Object { $_.Value }
                $result.MaxCpuUsagePct = $this.CalculateP95($cpuValues, "CPU")
                $result.AvgCpuUsagePct = $this.CalculateAverage($cpuValues, "CPU")
                $result.CpuDataPoints = $cpuStats.Count
                
                $this.Logger.WriteDebug("CPU metrics calculated for '$($vm.Name)': Max=$($result.MaxCpuUsagePct)%, Avg=$($result.AvgCpuUsagePct)%, DataPoints=$($result.CpuDataPoints)")
            }
            else {
                $this.Logger.WriteWarning("No CPU performance data available for VM '$($vm.Name)', using default values")
                $result.MaxCpuUsagePct = $this.DefaultValues.PoweredOn.MaxCpuUsagePct
                $result.AvgCpuUsagePct = $this.DefaultValues.PoweredOn.AvgCpuUsagePct
                $result.CpuDataPoints = 0
                $result.IsDefaultData = $true
            }
            
            # Calculate memory metrics with exact formula and capping
            if ($memoryStats -and $memoryStats.Count -gt 0) {
                $memoryUtilizations = @()
                
                foreach ($stat in $memoryStats) {
                    # Convert KB to MB (vCenter memory stats are typically in KB)
                    $consumedMemoryMB = $stat.Value / 1024
                    
                    # Calculate utilization using exact formula with capping
                    $memUtilization = $this.CalculateMemoryUtilization($consumedMemoryMB, $vm.MemoryMB, $vm.Name)
                    $memoryUtilizations += $memUtilization
                }
                
                if ($memoryUtilizations.Count -gt 0) {
                    $result.MaxRamUsagePct = $this.CalculateP95($memoryUtilizations, "Memory")
                    $result.AvgRamUsagePct = $this.CalculateAverage($memoryUtilizations, "Memory")
                    $result.MemoryDataPoints = $memoryStats.Count
                    
                    $this.Logger.WriteDebug("Memory metrics calculated for '$($vm.Name)': Max=$($result.MaxRamUsagePct)%, Avg=$($result.AvgRamUsagePct)%, DataPoints=$($result.MemoryDataPoints)")
                }
            }
            else {
                $this.Logger.WriteWarning("No memory performance data available for VM '$($vm.Name)', using default values")
                $result.MaxRamUsagePct = $this.DefaultValues.PoweredOn.MaxRamUsagePct
                $result.AvgRamUsagePct = $this.DefaultValues.PoweredOn.AvgRamUsagePct
                $result.MemoryDataPoints = 0
                $result.IsDefaultData = $true
            }
            
            # Validate logical relationships and apply corrections
            $this.ValidateAndCorrectMetrics($result)
            
            # Calculate overall data quality score
            $result.DataQualityScore = $this.CalculateDataQualityScore($result)
            
            $this.Logger.WriteInformation("Performance metrics calculated for VM '$($vm.Name)': CPU Max/Avg=$($result.MaxCpuUsagePct)%/$($result.AvgCpuUsagePct)%, Memory Max/Avg=$($result.MaxRamUsagePct)%/$($result.AvgRamUsagePct)%, Quality Score=$($result.DataQualityScore)")
            
            return $result
        }
        catch {
            $this.Logger.WriteError("Failed to calculate performance metrics for VM '$($vm.Name)': $($_.Exception.Message)", $_.Exception)
            
            # Return default values on error
            $defaults = $this.GetDefaultPerformanceValues($vm.PowerState, $vm.Name)
            $defaults.ValidationErrors = @("Calculation failed: $($_.Exception.Message)")
            return $defaults
        }
    }
    
    # Apply metric-specific capping rules
    [double] ApplyMetricCapping([double] $value, [string] $metricName) {
        switch ($metricName.ToLower()) {
            "cpu" {
                return [Math]::Min($this.CalculationSettings.MaxAllowedCpuPercent, [Math]::Max(0.0, $value))
            }
            "memory" {
                return [Math]::Min($this.CalculationSettings.MaxAllowedMemoryPercent, [Math]::Max(0.0, $value))
            }
            default {
                return [Math]::Max(0.0, $value)
            }
        }
        
        # Fallback return (should never reach here due to switch default)
        return [Math]::Max(0.0, $value)
    }
    
    # Remove statistical outliers using standard deviation method
    [array] RemoveOutliers([array] $values, [string] $metricName) {
        try {
            if ($values.Count -lt 10) {
                # Don't remove outliers from small datasets
                return $values
            }
            
            $mean = ($values | Measure-Object -Average).Average
            $variance = ($values | ForEach-Object { [Math]::Pow($_ - $mean, 2) } | Measure-Object -Average).Average
            $stdDev = [Math]::Sqrt($variance)
            
            $threshold = $this.CalculationSettings.OutlierThreshold * $stdDev
            $lowerBound = $mean - $threshold
            $upperBound = $mean + $threshold
            
            $cleanedValues = $values | Where-Object { $_ -ge $lowerBound -and $_ -le $upperBound }
            
            $removedCount = $values.Count - $cleanedValues.Count
            if ($removedCount -gt 0) {
                $this.Logger.WriteDebug("Removed $removedCount outliers from $metricName data (threshold: ±$([Math]::Round($threshold, 2)))")
            }
            
            return $cleanedValues
        }
        catch {
            $this.Logger.WriteWarning("Outlier removal failed for $metricName, using original values: $($_.Exception.Message)")
            return $values
        }
    }
    
    # Validate and correct logical relationships between metrics
    [void] ValidateAndCorrectMetrics([hashtable] $metrics) {
        if (-not $this.CalculationSettings.ValidateLogicalRelationships) {
            return
        }
        
        $validationErrors = @()
        
        # Ensure peak values are >= average values
        if ($metrics.ContainsKey('MaxCpuUsagePct') -and $metrics.ContainsKey('AvgCpuUsagePct')) {
            if ($metrics.MaxCpuUsagePct -lt $metrics.AvgCpuUsagePct) {
                $validationErrors += "CPU peak ($($metrics.MaxCpuUsagePct)%) < average ($($metrics.AvgCpuUsagePct)%)"
                $metrics.MaxCpuUsagePct = $metrics.AvgCpuUsagePct
                $this.Logger.WriteDebug("Corrected CPU peak to match average for VM '$($metrics.VMName)'")
            }
        }
        
        if ($metrics.ContainsKey('MaxRamUsagePct') -and $metrics.ContainsKey('AvgRamUsagePct')) {
            if ($metrics.MaxRamUsagePct -lt $metrics.AvgRamUsagePct) {
                $validationErrors += "Memory peak ($($metrics.MaxRamUsagePct)%) < average ($($metrics.AvgRamUsagePct)%)"
                $metrics.MaxRamUsagePct = $metrics.AvgRamUsagePct
                $this.Logger.WriteDebug("Corrected memory peak to match average for VM '$($metrics.VMName)'")
            }
        }
        
        # Validate percentage ranges
        $percentageFields = @('MaxCpuUsagePct', 'AvgCpuUsagePct', 'MaxRamUsagePct', 'AvgRamUsagePct')
        foreach ($field in $percentageFields) {
            if ($metrics.ContainsKey($field)) {
                if ($metrics[$field] -lt 0 -or $metrics[$field] -gt 100) {
                    $validationErrors += "$field value ($($metrics[$field])) outside valid range (0-100%)"
                    $metrics[$field] = [Math]::Min(100.0, [Math]::Max(0.0, $metrics[$field]))
                }
            }
        }
        
        # Store validation errors
        if ($validationErrors.Count -gt 0) {
            $metrics.ValidationErrors = $validationErrors
            $this.Logger.WriteWarning("Performance metrics validation issues for VM '$($metrics.VMName)': $($validationErrors -join '; ')")
        }
    }
    
    # Calculate overall data quality score
    [double] CalculateDataQualityScore([hashtable] $metrics) {
        try {
            if ($metrics.IsDefaultData) {
                return 0.0
            }
            
            $qualityFactors = @()
            
            # Factor 1: Data availability (0.0 - 0.4)
            $cpuDataPoints = if ($metrics.ContainsKey('CpuDataPoints')) { $metrics.CpuDataPoints } else { 0 }
            $memoryDataPoints = if ($metrics.ContainsKey('MemoryDataPoints')) { $metrics.MemoryDataPoints } else { 0 }
            $totalDataPoints = $cpuDataPoints + $memoryDataPoints
            
            if ($totalDataPoints -gt 0) {
                $dataAvailabilityScore = [Math]::Min(0.4, $totalDataPoints / 1000.0)  # Max 0.4 for 1000+ data points
                $qualityFactors += $dataAvailabilityScore
            }
            
            # Factor 2: Logical consistency (0.0 - 0.3)
            $consistencyScore = 0.3
            if ($metrics.ContainsKey('ValidationErrors') -and $metrics.ValidationErrors.Count -gt 0) {
                $consistencyScore -= ($metrics.ValidationErrors.Count * 0.1)
            }
            $qualityFactors += [Math]::Max(0.0, $consistencyScore)
            
            # Factor 3: Completeness (0.0 - 0.3)
            $completenessScore = 0.0
            if ($metrics.ContainsKey('MaxCpuUsagePct') -and $metrics.ContainsKey('AvgCpuUsagePct')) {
                $completenessScore += 0.15
            }
            if ($metrics.ContainsKey('MaxRamUsagePct') -and $metrics.ContainsKey('AvgRamUsagePct')) {
                $completenessScore += 0.15
            }
            $qualityFactors += $completenessScore
            
            # Calculate final score
            $finalScore = ($qualityFactors | Measure-Object -Sum).Sum
            return [Math]::Round([Math]::Min(1.0, $finalScore), 3)
        }
        catch {
            $this.Logger.WriteError("Data quality score calculation failed: $($_.Exception.Message)", $_.Exception)
            return 0.0
        }
    }
    
    # Configure calculation settings
    [void] ConfigureCalculationSettings([hashtable] $settings) {
        foreach ($key in $settings.Keys) {
            if ($this.CalculationSettings.ContainsKey($key)) {
                $this.CalculationSettings[$key] = $settings[$key]
                $this.Logger.WriteDebug("Updated calculation setting: $key = $($settings[$key])")
            }
        }
        
        $this.Logger.WriteInformation("Performance calculation settings updated: $($settings.Keys -join ', ')")
    }
    
    # Clear statistical cache
    [void] ClearCache() {
        $cacheSize = $this.StatisticalCache.Count
        $this.StatisticalCache.Clear()
        $this.Logger.WriteDebug("Cleared statistical cache ($cacheSize entries)")
    }
    
    # Calculate advanced performance metrics with statistical analysis and confidence intervals
    [hashtable] CalculateAdvancedVMPerformanceMetrics([object] $vm, [array] $cpuStats, [array] $memoryStats, [array] $timestamps = @()) {
        try {
            $this.Logger.WriteDebug("Calculating advanced performance metrics with statistical analysis for VM '$($vm.Name)'")
            
            $result = @{
                VMName = $vm.Name
                PowerState = $vm.PowerState
                CalculationTimestamp = Get-Date
                IsDefaultData = $false
                BasicMetrics = @{}
                AdvancedAnalysis = @{}
                DataQuality = @{}
                ValidationErrors = @()
            }
            
            # Calculate basic metrics first
            $basicMetrics = $this.CalculateVMPerformanceMetrics($vm, $cpuStats, $memoryStats)
            $result.BasicMetrics = $basicMetrics
            
            # Skip advanced analysis for powered-off VMs
            if ($vm.PowerState -eq "PoweredOff") {
                $result.IsDefaultData = $true
                $result.AdvancedAnalysis = @{
                    CPU = @{ P95Value = $basicMetrics.MaxCpuUsagePct; ConfidenceInterval = @{ Lower = $basicMetrics.MaxCpuUsagePct; Upper = $basicMetrics.MaxCpuUsagePct }; Reliability = 'Default' }
                    Memory = @{ P95Value = $basicMetrics.MaxRamUsagePct; ConfidenceInterval = @{ Lower = $basicMetrics.MaxRamUsagePct; Upper = $basicMetrics.MaxRamUsagePct }; Reliability = 'Default' }
                }
                $result.DataQuality = @{ Score = 0.0; Issues = @("VM is powered off - using default values") }
                return $result
            }
            
            # Perform advanced CPU analysis
            if ($cpuStats -and $cpuStats.Count -gt 0) {
                $cpuValues = $cpuStats | ForEach-Object { $_.Value }
                $cpuTimestamps = if ($timestamps.Count -eq $cpuStats.Count) { $timestamps } else { @() }
                $result.AdvancedAnalysis.CPU = $this.AdvancedCalculator.CalculateAdvancedP95($cpuValues, "CPU", $cpuTimestamps)
                
                $this.Logger.WriteDebug("Advanced CPU analysis for '$($vm.Name)': P95=$($result.AdvancedAnalysis.CPU.P95Value)%, CI=[$($result.AdvancedAnalysis.CPU.ConfidenceInterval.Lower)-$($result.AdvancedAnalysis.CPU.ConfidenceInterval.Upper)], Reliability=$($result.AdvancedAnalysis.CPU.Reliability)")
            } else {
                $result.AdvancedAnalysis.CPU = @{
                    P95Value = $basicMetrics.MaxCpuUsagePct
                    ConfidenceInterval = @{ Lower = $basicMetrics.MaxCpuUsagePct; Upper = $basicMetrics.MaxCpuUsagePct }
                    Reliability = 'No Data'
                    DataQuality = @{ Score = 0.0; Issues = @("No CPU performance data available") }
                }
            }
            
            # Perform advanced memory analysis
            if ($memoryStats -and $memoryStats.Count -gt 0) {
                # Calculate memory utilization percentages first
                $memoryUtilizations = @()
                foreach ($stat in $memoryStats) {
                    $consumedMemoryMB = $stat.Value / 1024  # Convert KB to MB
                    $memUtilization = $this.CalculateMemoryUtilization($consumedMemoryMB, $vm.MemoryMB, $vm.Name)
                    $memoryUtilizations += $memUtilization
                }
                
                $memoryTimestamps = if ($timestamps.Count -eq $memoryStats.Count) { $timestamps } else { @() }
                $result.AdvancedAnalysis.Memory = $this.AdvancedCalculator.CalculateAdvancedP95($memoryUtilizations, "Memory", $memoryTimestamps)
                
                $this.Logger.WriteDebug("Advanced Memory analysis for '$($vm.Name)': P95=$($result.AdvancedAnalysis.Memory.P95Value)%, CI=[$($result.AdvancedAnalysis.Memory.ConfidenceInterval.Lower)-$($result.AdvancedAnalysis.Memory.ConfidenceInterval.Upper)], Reliability=$($result.AdvancedAnalysis.Memory.Reliability)")
            } else {
                $result.AdvancedAnalysis.Memory = @{
                    P95Value = $basicMetrics.MaxRamUsagePct
                    ConfidenceInterval = @{ Lower = $basicMetrics.MaxRamUsagePct; Upper = $basicMetrics.MaxRamUsagePct }
                    Reliability = 'No Data'
                    DataQuality = @{ Score = 0.0; Issues = @("No memory performance data available") }
                }
            }
            
            # Calculate overall data quality score
            $cpuQuality = if ($result.AdvancedAnalysis.CPU.ContainsKey('DataQuality')) { $result.AdvancedAnalysis.CPU.DataQuality.Score } else { 0.5 }
            $memoryQuality = if ($result.AdvancedAnalysis.Memory.ContainsKey('DataQuality')) { $result.AdvancedAnalysis.Memory.DataQuality.Score } else { 0.5 }
            $overallQuality = ($cpuQuality + $memoryQuality) / 2.0
            
            $result.DataQuality = @{
                Score = [Math]::Round($overallQuality, 3)
                CPUQuality = $cpuQuality
                MemoryQuality = $memoryQuality
                OverallReliability = if ($overallQuality -gt 0.8) { 'High' } elseif ($overallQuality -gt 0.5) { 'Medium' } else { 'Low' }
            }
            
            $this.Logger.WriteInformation("Advanced performance metrics calculated for VM '$($vm.Name)': Overall Quality Score=$($result.DataQuality.Score), Reliability=$($result.DataQuality.OverallReliability)")
            
            return $result
            
        } catch {
            $this.Logger.WriteError("Failed to calculate advanced performance metrics for VM '$($vm.Name)': $($_.Exception.Message)", $_.Exception)
            
            # Return basic metrics on error
            $basicMetrics = $this.CalculateVMPerformanceMetrics($vm, $cpuStats, $memoryStats)
            return @{
                VMName = $vm.Name
                PowerState = $vm.PowerState
                CalculationTimestamp = Get-Date
                IsDefaultData = $basicMetrics.IsDefaultData
                BasicMetrics = $basicMetrics
                AdvancedAnalysis = @{
                    CPU = @{ P95Value = $basicMetrics.MaxCpuUsagePct; Reliability = 'Error' }
                    Memory = @{ P95Value = $basicMetrics.MaxRamUsagePct; Reliability = 'Error' }
                }
                DataQuality = @{ Score = 0.0; Issues = @("Advanced calculation failed: $($_.Exception.Message)") }
                ValidationErrors = @("Advanced metrics calculation failed")
            }
        }
    }
    
    # Configure advanced calculator settings
    [void] ConfigureAdvancedCalculator([hashtable] $statisticalSettings = @{}, [hashtable] $timezoneSettings = @{}) {
        if ($statisticalSettings.Count -gt 0) {
            $this.AdvancedCalculator.ConfigureStatisticalSettings($statisticalSettings)
            $this.Logger.WriteInformation("Updated advanced calculator statistical settings")
        }
        
        if ($timezoneSettings.Count -gt 0) {
            $this.AdvancedCalculator.ConfigureTimezoneSettings($timezoneSettings)
            $this.Logger.WriteInformation("Updated advanced calculator timezone settings")
        }
    }
    
    # Get calculation engine statistics
    [hashtable] GetCalculationStatistics() {
        $basicStats = @{
            CacheEnabled = $this.EnableCaching
            CacheSize = $this.StatisticalCache.Count
            CacheMaxSize = $this.CacheMaxSize
            DecimalPrecision = $this.CalculationSettings.DecimalPrecision
            MemoryCapAt100Percent = $this.CalculationSettings.MemoryCapAt100Percent
            OutlierDetectionEnabled = $this.CalculationSettings.EnableOutlierDetection
            ValidationEnabled = $this.CalculationSettings.ValidateLogicalRelationships
        }
        
        # Add advanced calculator statistics
        if ($this.AdvancedCalculator) {
            $advancedStats = $this.AdvancedCalculator.GetCalculatorStatistics()
            $basicStats.AdvancedCalculator = $advancedStats
        }
        
        return $basicStats
    }
    
    # ===== ADVANCED STATISTICAL METHODS (from AdvancedPerformanceCalculator) =====
    
    # Calculate P95 with advanced statistical analysis and confidence intervals
    [hashtable] CalculateAdvancedP95([array] $values, [string] $metricName = "Unknown", [array] $timestamps = @()) {
        try {
            $result = @{
                P95Value = 0.0
                ConfidenceInterval = @{ Lower = 0.0; Upper = 0.0 }
                StatisticalAnalysis = @{}
                DataQuality = @{}
                Reliability = 'Unknown'
                OutlierAnalysis = @{}
                TrendAnalysis = @{}
                TimezoneAdjustment = @{}
            }
            
            if (-not $values -or $values.Count -eq 0) {
                $result.Reliability = 'No Data'
                $result.DataQuality = @{ Score = 0.0; Issues = @("No data points available") }
                return $result
            }
            
            # Perform outlier detection and removal
            $outlierResult = $this.DetectAndRemoveOutliers($values, $metricName)
            $cleanedValues = $outlierResult.CleanedValues
            $result.OutlierAnalysis = $outlierResult.OutlierAnalysis
            
            # Apply timezone adjustments if timestamps are provided
            if ($timestamps.Count -eq $values.Count -and $this.TimezoneSettings.EnableTimezoneConversion) {
                $timezoneResult = $this.AdjustForTimezoneAndDST($cleanedValues, $timestamps, $metricName)
                $cleanedValues = $timezoneResult.AdjustedValues
                $result.TimezoneAdjustment = $timezoneResult.AdjustmentInfo
            }
            
            # Calculate basic P95
            $p95Value = $this.CalculatePercentile($cleanedValues, 95)
            $result.P95Value = [Math]::Round($p95Value, 3)
            
            # Calculate confidence interval
            if ($cleanedValues.Count -ge $this.StatisticalSettings.MinSampleSizeForCI) {
                $result.ConfidenceInterval = $this.CalculateConfidenceInterval($cleanedValues, 95, $this.StatisticalSettings.ConfidenceLevel)
                $result.Reliability = 'High'
            } elseif ($cleanedValues.Count -ge 10) {
                $result.ConfidenceInterval = $this.CalculateConfidenceInterval($cleanedValues, 95, $this.StatisticalSettings.ConfidenceLevel)
                $result.Reliability = 'Medium'
            } else {
                $result.ConfidenceInterval = @{ Lower = $p95Value; Upper = $p95Value }
                $result.Reliability = 'Low'
            }
            
            # Perform comprehensive statistical analysis
            $result.StatisticalAnalysis = $this.PerformStatisticalAnalysis($cleanedValues, $metricName)
            
            # Calculate data quality indicators
            $result.DataQuality = $this.CalculateDataQualityIndicators($cleanedValues, $timestamps, $metricName)
            
            # Perform trend analysis if enabled
            if ($this.StatisticalSettings.EnableTrendAnalysis -and $cleanedValues.Count -gt 5) {
                $result.TrendAnalysis = $this.AnalyzeTrend($cleanedValues)
            }
            
            $this.Logger.WriteDebug("Advanced P95 calculation for $metricName completed: P95=$($result.P95Value), Reliability=$($result.Reliability), DataPoints=$($cleanedValues.Count)")
            
            return $result
        }
        catch {
            $this.Logger.WriteError("Advanced P95 calculation failed for $metricName`: $($_.Exception.Message)", $_.Exception)
            return @{
                P95Value = 0.0
                ConfidenceInterval = @{ Lower = 0.0; Upper = 0.0 }
                Reliability = 'Error'
                DataQuality = @{ Score = 0.0; Issues = @("Calculation failed: $($_.Exception.Message)") }
            }
        }
    }
    
    # Calculate percentile using interpolation method
    [double] CalculatePercentile([array] $values, [double] $percentile) {
        if (-not $values -or $values.Count -eq 0) {
            return 0.0
        }
        
        $sortedValues = $values | Sort-Object
        $index = ($percentile / 100.0) * ($sortedValues.Count - 1)
        
        if ($index -eq [Math]::Floor($index)) {
            return $sortedValues[[int]$index]
        } else {
            $lowerIndex = [Math]::Floor($index)
            $upperIndex = [Math]::Ceiling($index)
            $weight = $index - $lowerIndex
            
            return $sortedValues[$lowerIndex] * (1 - $weight) + $sortedValues[$upperIndex] * $weight
        }
    }
    
    # Calculate confidence interval using bootstrap method
    [hashtable] CalculateConfidenceInterval([array] $values, [double] $percentile, [double] $confidenceLevel) {
        try {
            $cacheKey = "CI_$percentile" + "_$confidenceLevel" + "_" + ($values | ConvertTo-Json -Compress | Get-FileHash -Algorithm MD5).Hash
            
            if ($this.ConfidenceIntervalCache.ContainsKey($cacheKey)) {
                return $this.ConfidenceIntervalCache[$cacheKey]
            }
            
            if (-not $this.StatisticalSettings.EnableBootstrapping -or $values.Count -lt 10) {
                $percentileValue = $this.CalculatePercentile($values, $percentile)
                return @{
                    Lower = $percentileValue
                    Upper = $percentileValue
                    ConfidenceLevel = $confidenceLevel
                    Method = 'Single Value'
                    SampleSize = $values.Count
                }
            }
            
            # Bootstrap resampling
            $bootstrapSamples = @()
            $random = New-Object System.Random
            
            for ($i = 0; $i -lt $this.StatisticalSettings.BootstrapSamples; $i++) {
                $bootstrapSample = @()
                for ($j = 0; $j -lt $values.Count; $j++) {
                    $randomIndex = $random.Next(0, $values.Count)
                    $bootstrapSample += $values[$randomIndex]
                }
                $bootstrapSamples += $this.CalculatePercentile($bootstrapSample, $percentile)
            }
            
            # Calculate confidence interval from bootstrap distribution
            $sortedBootstrap = $bootstrapSamples | Sort-Object
            $alpha = 1 - $confidenceLevel
            $lowerIndex = [Math]::Floor($alpha / 2 * $sortedBootstrap.Count)
            $upperIndex = [Math]::Ceiling((1 - $alpha / 2) * $sortedBootstrap.Count) - 1
            
            $result = @{
                Lower = [Math]::Round($sortedBootstrap[$lowerIndex], 3)
                Upper = [Math]::Round($sortedBootstrap[$upperIndex], 3)
                ConfidenceLevel = $confidenceLevel
                Method = 'Bootstrap'
                SampleSize = $values.Count
                BootstrapSamples = $this.StatisticalSettings.BootstrapSamples
            }
            
            # Cache result
            if ($this.ConfidenceIntervalCache.Count -lt 100) {
                $this.ConfidenceIntervalCache[$cacheKey] = $result
            }
            
            return $result
        }
        catch {
            $this.Logger.WriteError("Confidence interval calculation failed: $($_.Exception.Message)", $_.Exception)
            $percentileValue = $this.CalculatePercentile($values, $percentile)
            return @{
                Lower = $percentileValue
                Upper = $percentileValue
                ConfidenceLevel = $confidenceLevel
                Method = 'Error Fallback'
                SampleSize = $values.Count
            }
        }
    }
    
    # Perform comprehensive statistical analysis
    [hashtable] PerformStatisticalAnalysis([array] $values, [string] $metricName) {
        try {
            if (-not $values -or $values.Count -eq 0) {
                return @{
                    Count = 0
                    Mean = 0.0
                    Median = 0.0
                    StandardDeviation = 0.0
                    Variance = 0.0
                    Skewness = 0.0
                    Kurtosis = 0.0
                    Range = 0.0
                    InterquartileRange = 0.0
                    CoefficientOfVariation = 0.0
                }
            }
            
            $sortedValues = $values | Sort-Object
            
            # Basic statistics
            $mean = ($values | Measure-Object -Average).Average
            $median = $this.CalculatePercentile($sortedValues, 50)
            $stdDev = $this.CalculateStandardDeviation($values)
            $variance = $stdDev * $stdDev
            $range = ($sortedValues[-1] - $sortedValues[0])
            $q1 = $this.CalculatePercentile($sortedValues, 25)
            $q3 = $this.CalculatePercentile($sortedValues, 75)
            $iqr = $q3 - $q1
            $cv = if ($mean -ne 0) { $stdDev / $mean } else { 0.0 }
            
            # Advanced statistics
            $skewness = $this.CalculateSkewness($values, $mean, $stdDev)
            $kurtosis = $this.CalculateKurtosis($values, $mean, $stdDev)
            
            return @{
                Count = $values.Count
                Mean = [Math]::Round($mean, 3)
                Median = [Math]::Round($median, 3)
                StandardDeviation = [Math]::Round($stdDev, 3)
                Variance = [Math]::Round($variance, 3)
                Skewness = [Math]::Round($skewness, 3)
                Kurtosis = [Math]::Round($kurtosis, 3)
                Range = [Math]::Round($range, 3)
                InterquartileRange = [Math]::Round($iqr, 3)
                CoefficientOfVariation = [Math]::Round($cv, 3)
                Q1 = [Math]::Round($q1, 3)
                Q3 = [Math]::Round($q3, 3)
                Min = [Math]::Round($sortedValues[0], 3)
                Max = [Math]::Round($sortedValues[-1], 3)
            }
        }
        catch {
            $this.Logger.WriteError("Statistical analysis failed for $metricName`: $($_.Exception.Message)", $_.Exception)
            return @{ Error = "Statistical analysis failed: $($_.Exception.Message)" }
        }
    }
    
    # Detect and remove outliers using configurable methods
    [hashtable] DetectAndRemoveOutliers([array] $values, [string] $metricName) {
        try {
            if (-not $values -or $values.Count -lt 5) {
                return @{
                    CleanedValues = $values
                    OutlierAnalysis = @{
                        Method = 'None'
                        OutliersDetected = 0
                        OutlierIndices = @()
                        Reason = 'Insufficient data points'
                    }
                }
            }
            
            $outlierIndices = @()
            
            switch ($this.StatisticalSettings.OutlierDetectionMethod) {
                'IQR' {
                    $outlierIndices = $this.DetectOutliersIQR($values)
                }
                'ZScore' {
                    $outlierIndices = $this.DetectOutliersZScore($values)
                }
                'ModifiedZScore' {
                    $outlierIndices = $this.DetectOutliersModifiedZScore($values)
                }
                default {
                    $outlierIndices = $this.DetectOutliersIQR($values)
                }
            }
            
            # Remove outliers
            $cleanedValues = @()
            for ($i = 0; $i -lt $values.Count; $i++) {
                if ($i -notin $outlierIndices) {
                    $cleanedValues += $values[$i]
                }
            }
            
            return @{
                CleanedValues = $cleanedValues
                OutlierAnalysis = @{
                    Method = $this.StatisticalSettings.OutlierDetectionMethod
                    OutliersDetected = $outlierIndices.Count
                    OutlierIndices = $outlierIndices
                    PercentageRemoved = [Math]::Round(($outlierIndices.Count / $values.Count) * 100, 2)
                    OriginalCount = $values.Count
                    CleanedCount = $cleanedValues.Count
                }
            }
        }
        catch {
            $this.Logger.WriteError("Outlier detection failed for $metricName`: $($_.Exception.Message)", $_.Exception)
            return @{
                CleanedValues = $values
                OutlierAnalysis = @{
                    Method = 'Error'
                    OutliersDetected = 0
                    Error = $_.Exception.Message
                }
            }
        }
    }
    
    # Detect outliers using IQR method
    [array] DetectOutliersIQR([array] $values) {
        $sortedValues = $values | Sort-Object
        $q1 = $this.CalculatePercentile($sortedValues, 25)
        $q3 = $this.CalculatePercentile($sortedValues, 75)
        $iqr = $q3 - $q1
        $lowerBound = $q1 - ($this.StatisticalSettings.IQRMultiplier * $iqr)
        $upperBound = $q3 + ($this.StatisticalSettings.IQRMultiplier * $iqr)
        
        $outlierIndices = @()
        for ($i = 0; $i -lt $values.Count; $i++) {
            if ($values[$i] -lt $lowerBound -or $values[$i] -gt $upperBound) {
                $outlierIndices += $i
            }
        }
        
        return $outlierIndices
    }
    
    # Detect outliers using Z-Score method
    [array] DetectOutliersZScore([array] $values) {
        $mean = ($values | Measure-Object -Average).Average
        $stdDev = $this.CalculateStandardDeviation($values)
        
        if ($stdDev -eq 0) {
            return @()
        }
        
        $outlierIndices = @()
        for ($i = 0; $i -lt $values.Count; $i++) {
            $zScore = [Math]::Abs(($values[$i] - $mean) / $stdDev)
            if ($zScore -gt $this.StatisticalSettings.ZScoreThreshold) {
                $outlierIndices += $i
            }
        }
        
        return $outlierIndices
    }
    
    # Detect outliers using Modified Z-Score method
    [array] DetectOutliersModifiedZScore([array] $values) {
        $median = $this.CalculatePercentile($values, 50)
        $deviations = $values | ForEach-Object { [Math]::Abs($_ - $median) }
        $mad = $this.CalculatePercentile($deviations, 50)  # Median Absolute Deviation
        
        if ($mad -eq 0) {
            return @()
        }
        
        $outlierIndices = @()
        for ($i = 0; $i -lt $values.Count; $i++) {
            $modifiedZScore = 0.6745 * ($values[$i] - $median) / $mad
            if ([Math]::Abs($modifiedZScore) -gt $this.StatisticalSettings.ModifiedZScoreThreshold) {
                $outlierIndices += $i
            }
        }
        
        return $outlierIndices
    }
    
    # Calculate data quality indicators
    [hashtable] CalculateDataQualityIndicators([array] $values, [array] $timestamps, [string] $metricName) {
        try {
            $quality = @{
                Score = 0.0
                Issues = @()
                Indicators = @{}
            }
            
            if (-not $values -or $values.Count -eq 0) {
                $quality.Issues += "No data points available"
                return $quality
            }
            
            # Data completeness (0-30 points)
            $completenessScore = [Math]::Min(30, ($values.Count / $this.StatisticalSettings.MinDataPointsForReliability) * 30)
            $quality.Indicators.Completeness = [Math]::Round($completenessScore, 1)
            
            # Data consistency (0-25 points)
            $consistencyScore = 25
            $nullCount = ($values | Where-Object { $_ -eq $null -or $_ -eq '' }).Count
            if ($nullCount -gt 0) {
                $consistencyScore -= ($nullCount / $values.Count) * 25
                $quality.Issues += "Contains $nullCount null/empty values"
            }
            $quality.Indicators.Consistency = [Math]::Round($consistencyScore, 1)
            
            # Data freshness (0-20 points) - based on timestamps if available
            $freshnessScore = 20
            if ($timestamps.Count -eq $values.Count -and $timestamps.Count -gt 1) {
                $gapAnalysis = $this.AnalyzeDataGaps($timestamps)
                if ($gapAnalysis.MaxGapHours -gt $this.StatisticalSettings.MaxAcceptableGapHours) {
                    $freshnessScore -= 10
                    $quality.Issues += "Data gaps detected (max: $($gapAnalysis.MaxGapHours) hours)"
                }
                $quality.Indicators.DataGaps = $gapAnalysis
            }
            $quality.Indicators.Freshness = [Math]::Round($freshnessScore, 1)
            
            # Data accuracy (0-25 points) - based on outlier percentage
            $accuracyScore = 25
            $outlierResult = $this.DetectAndRemoveOutliers($values, $metricName)
            $outlierPercentage = $outlierResult.OutlierAnalysis.PercentageRemoved
            if ($outlierPercentage -gt 10) {
                $accuracyScore -= ($outlierPercentage - 10) * 1.5
                $quality.Issues += "High outlier percentage: $outlierPercentage%"
            }
            $quality.Indicators.Accuracy = [Math]::Round([Math]::Max(0, $accuracyScore), 1)
            
            # Calculate overall score
            $quality.Score = [Math]::Round(($quality.Indicators.Completeness + $quality.Indicators.Consistency + $quality.Indicators.Freshness + $quality.Indicators.Accuracy), 1)
            
            return $quality
        }
        catch {
            $this.Logger.WriteError("Data quality calculation failed for $metricName`: $($_.Exception.Message)", $_.Exception)
            return @{
                Score = 0.0
                Issues = @("Quality calculation failed: $($_.Exception.Message)")
                Indicators = @{}
            }
        }
    }
    
    # Analyze data gaps in timestamps
    [hashtable] AnalyzeDataGaps([array] $timestamps) {
        if ($timestamps.Count -lt 2) {
            return @{
                TotalGaps = 0
                MaxGapHours = 0.0
                AverageGapHours = 0.0
                GapDetails = @()
            }
        }
        
        $sortedTimestamps = $timestamps | Sort-Object
        $gaps = @()
        
        for ($i = 1; $i -lt $sortedTimestamps.Count; $i++) {
            $gapHours = ($sortedTimestamps[$i] - $sortedTimestamps[$i-1]).TotalHours
            $gaps += $gapHours
        }
        
        return @{
            TotalGaps = $gaps.Count
            MaxGapHours = [Math]::Round(($gaps | Measure-Object -Maximum).Maximum, 2)
            AverageGapHours = [Math]::Round(($gaps | Measure-Object -Average).Average, 2)
            GapDetails = $gaps | ForEach-Object { [Math]::Round($_, 2) }
        }
    }
    
    # Helper methods for statistical calculations
    [double] CalculateStandardDeviation([array] $values) {
        if ($values.Count -lt 2) {
            return 0.0
        }
        
        $mean = ($values | Measure-Object -Average).Average
        $variance = ($values | ForEach-Object { [Math]::Pow($_ - $mean, 2) } | Measure-Object -Average).Average
        return [Math]::Sqrt($variance)
    }
    
    [double] CalculateSkewness([array] $values, [double] $mean, [double] $stdDev) {
        if ($values.Count -lt 3 -or $stdDev -eq 0) {
            return 0.0
        }
        
        $n = $values.Count
        $skewness = ($values | ForEach-Object { [Math]::Pow(($_ - $mean) / $stdDev, 3) } | Measure-Object -Sum).Sum / $n
        return $skewness
    }
    
    [double] CalculateKurtosis([array] $values, [double] $mean, [double] $stdDev) {
        if ($values.Count -lt 4 -or $stdDev -eq 0) {
            return 0.0
        }
        
        $n = $values.Count
        $kurtosis = ($values | ForEach-Object { [Math]::Pow(($_ - $mean) / $stdDev, 4) } | Measure-Object -Sum).Sum / $n
        return $kurtosis - 3  # Excess kurtosis
    }
    
    [hashtable] AnalyzeTrend([array] $values) {
        try {
            $n = $values.Count
            if ($n -lt 3) {
                return @{
                    Trend = 'Insufficient Data'
                    Slope = 0.0
                    RSquared = 0.0
                }
            }
            
            # Simple linear regression
            $x = 1..$n
            $y = $values
            
            $sumX = ($x | Measure-Object -Sum).Sum
            $sumY = ($y | Measure-Object -Sum).Sum
            $sumXY = 0
            $sumXX = 0
            
            for ($i = 0; $i -lt $n; $i++) {
                $sumXY += $x[$i] * $y[$i]
                $sumXX += $x[$i] * $x[$i]
            }
            
            $slope = ($n * $sumXY - $sumX * $sumY) / ($n * $sumXX - $sumX * $sumX)
            $intercept = ($sumY - $slope * $sumX) / $n
            
            # Calculate R-squared
            $meanY = $sumY / $n
            $ssTotal = ($y | ForEach-Object { [Math]::Pow($_ - $meanY, 2) } | Measure-Object -Sum).Sum
            $ssResidual = 0
            
            for ($i = 0; $i -lt $n; $i++) {
                $predicted = $slope * $x[$i] + $intercept
                $ssResidual += [Math]::Pow($y[$i] - $predicted, 2)
            }
            
            $rSquared = if ($ssTotal -ne 0) { 1 - ($ssResidual / $ssTotal) } else { 0 }
            
            # Determine trend direction
            $trend = if ([Math]::Abs($slope) -lt 0.01) {
                'Stable'
            } elseif ($slope -gt 0) {
                'Increasing'
            } else {
                'Decreasing'
            }
            
            return @{
                Trend = $trend
                Slope = [Math]::Round($slope, 4)
                RSquared = [Math]::Round($rSquared, 4)
                Intercept = [Math]::Round($intercept, 4)
                Confidence = if ($rSquared -gt 0.7) { 'High' } elseif ($rSquared -gt 0.3) { 'Medium' } else { 'Low' }
            }
        }
        catch {
            $this.Logger.WriteError("Trend analysis failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Trend = 'Error'
                Slope = 0.0
                RSquared = 0.0
                Error = $_.Exception.Message
            }
        }
    }
    
    # Adjust data for timezone and daylight saving time
    [hashtable] AdjustForTimezoneAndDST([array] $values, [array] $timestamps, [string] $metricName) {
        try {
            if (-not $this.TimezoneSettings.HandleDaylightSavingTime -or $timestamps.Count -ne $values.Count) {
                return @{
                    AdjustedValues = $values
                    AdjustmentInfo = @{
                        Applied = $false
                        Reason = 'Timezone adjustment disabled or timestamp mismatch'
                    }
                }
            }
            
            # This is a simplified implementation - in practice, you'd need more sophisticated DST handling
            $adjustedValues = $values  # For now, return original values
            
            return @{
                AdjustedValues = $adjustedValues
                AdjustmentInfo = @{
                    Applied = $false
                    Reason = 'Timezone adjustment not implemented in this version'
                    SourceTimezone = $this.TimezoneSettings.DefaultSourceTimezone
                    TargetTimezone = $this.TimezoneSettings.DefaultTargetTimezone
                }
            }
        }
        catch {
            $this.Logger.WriteError("Timezone adjustment failed for $metricName`: $($_.Exception.Message)", $_.Exception)
            return @{
                AdjustedValues = $values
                AdjustmentInfo = @{
                    Applied = $false
                    Error = $_.Exception.Message
                }
            }
        }
    }
    
    # Configuration methods
    [void] ConfigureStatisticalSettings([hashtable] $settings) {
        foreach ($key in $settings.Keys) {
            if ($this.StatisticalSettings.ContainsKey($key)) {
                $this.StatisticalSettings[$key] = $settings[$key]
                $this.Logger.WriteDebug("Updated statistical setting: $key = $($settings[$key])")
            }
        }
    }
    
    [void] ConfigureTimezoneSettings([hashtable] $settings) {
        foreach ($key in $settings.Keys) {
            if ($this.TimezoneSettings.ContainsKey($key)) {
                $this.TimezoneSettings[$key] = $settings[$key]
                $this.Logger.WriteDebug("Updated timezone setting: $key = $($settings[$key])")
            }
        }
        
        # Update timezone objects if specified
        if ($settings.ContainsKey('DefaultSourceTimezone')) {
            try {
                $this.SourceTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($settings.DefaultSourceTimezone)
            } catch {
                $this.Logger.WriteWarning("Invalid source timezone: $($settings.DefaultSourceTimezone)")
            }
        }
        
        if ($settings.ContainsKey('DefaultTargetTimezone')) {
            try {
                $this.TargetTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($settings.DefaultTargetTimezone)
            } catch {
                $this.Logger.WriteWarning("Invalid target timezone: $($settings.DefaultTargetTimezone)")
            }
        }
    }
    
    # Clear caches
    [void] ClearCaches() {
        $ciCacheSize = $this.ConfidenceIntervalCache.Count
        $saCacheSize = $this.StatisticalAnalysisCache.Count
        
        $this.ConfidenceIntervalCache.Clear()
        $this.StatisticalAnalysisCache.Clear()
        
        $this.Logger.WriteDebug("Cleared advanced statistical caches: CI=$ciCacheSize, SA=$saCacheSize")
    }
    
    # Get calculator statistics
    [hashtable] GetCalculatorStatistics() {
        return @{
            ConfidenceLevel = $this.StatisticalSettings.ConfidenceLevel
            OutlierDetectionMethod = $this.StatisticalSettings.OutlierDetectionMethod
            EnableBootstrapping = $this.StatisticalSettings.EnableBootstrapping
            BootstrapSamples = $this.StatisticalSettings.BootstrapSamples
            CacheSize = @{
                Statistical = $this.StatisticalCache.Count
                ConfidenceInterval = $this.ConfidenceIntervalCache.Count
                StatisticalAnalysis = $this.StatisticalAnalysisCache.Count
            }
            TimezoneSettings = $this.TimezoneSettings
        }
    }
}