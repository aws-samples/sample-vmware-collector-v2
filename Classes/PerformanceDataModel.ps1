#
# PerformanceDataModel.ps1 - Performance data model for daily statistics
#
# Implements the performance data structure for tracking daily CPU, memory,
# and storage utilization metrics with statistical calculations.
#

# Import base interface
. "$PSScriptRoot\Interfaces.ps1"

class PerformanceDataModel : IVMwareDataModel {
    [string] $ServerName              # VM name
    [string] $UniqueIdentifier        # Sequential unique ID
    [datetime] $Date                  # Date of performance data
    [double] $CpuPeak                 # P95 CPU utilization for the day (0-1 decimal)
    [double] $CpuAvg                  # Average CPU utilization for the day (0-1 decimal)
    [double] $MemPeak                 # P95 Memory utilization for the day (0-1 decimal)
    [double] $MemAvg                  # Average Memory utilization for the day (0-1 decimal)
    [double] $StoragePeak             # P95 Storage utilization for the day (0-1 decimal)
    [double] $StorageAvg              # Average Storage utilization for the day (0-1 decimal)
    [double] $TimeInUsePercentage     # Percentage of time VM was in use (0-1 decimal)
    [double] $TimeOnPercentage        # Percentage of time VM was powered on (0-1 decimal)
    [int] $DataPointCount             # Number of performance samples for this day
    [string] $StatInterval            # Stat interval used (5min, 30min, 2hr)
    [bool] $IsDefaultData             # True if using default values for powered-off VM
    
    # Constructor with default values
    PerformanceDataModel() {
        $this.Date = Get-Date
        $this.CpuPeak = 0.0
        $this.CpuAvg = 0.0
        $this.MemPeak = 0.0
        $this.MemAvg = 0.0
        $this.StoragePeak = 0.0
        $this.StorageAvg = 0.0
        $this.TimeInUsePercentage = 1.0
        $this.TimeOnPercentage = 1.0
        $this.DataPointCount = 0
        $this.StatInterval = "Unknown"
        $this.IsDefaultData = $false
    }
    
    # Constructor with parameters
    PerformanceDataModel([string] $serverName, [datetime] $date) {
        $this.ServerName = $serverName
        $this.Date = $date
        $this.CpuPeak = 0.0
        $this.CpuAvg = 0.0
        $this.MemPeak = 0.0
        $this.MemAvg = 0.0
        $this.StoragePeak = 0.0
        $this.StorageAvg = 0.0
        $this.TimeInUsePercentage = 1.0
        $this.TimeOnPercentage = 1.0
        $this.DataPointCount = 0
        $this.StatInterval = "Unknown"
        $this.IsDefaultData = $false
    }
    
    # Validate performance data ranges
    [bool] ValidateData() {
        $isValid = $true
        $validationErrors = @()
        
        # Check required fields
        if ([string]::IsNullOrEmpty($this.ServerName)) {
            $validationErrors += "ServerName is required"
            $isValid = $false
        }
        
        # Validate percentage fields (must be between 0 and 1 for decimal representation)
        $percentageFields = @{
            'CpuPeak' = $this.CpuPeak
            'CpuAvg' = $this.CpuAvg
            'MemPeak' = $this.MemPeak
            'MemAvg' = $this.MemAvg
            'StoragePeak' = $this.StoragePeak
            'StorageAvg' = $this.StorageAvg
            'TimeInUsePercentage' = $this.TimeInUsePercentage
            'TimeOnPercentage' = $this.TimeOnPercentage
        }
        
        foreach ($field in $percentageFields.GetEnumerator()) {
            if ($field.Value -lt 0 -or $field.Value -gt 1) {
                $validationErrors += "$($field.Key) must be between 0 and 1 (decimal), got: $($field.Value)"
                $isValid = $false
            }
        }
        
        # Validate data point count
        if ($this.DataPointCount -lt 0) {
            $validationErrors += "DataPointCount cannot be negative, got: $($this.DataPointCount)"
            $isValid = $false
        }
        
        # Validate logical relationships
        if ($this.CpuPeak -lt $this.CpuAvg) {
            $validationErrors += "CpuPeak ($($this.CpuPeak)) should be >= CpuAvg ($($this.CpuAvg))"
            $isValid = $false
        }
        
        if ($this.MemPeak -lt $this.MemAvg) {
            $validationErrors += "MemPeak ($($this.MemPeak)) should be >= MemAvg ($($this.MemAvg))"
            $isValid = $false
        }
        
        if ($this.StoragePeak -lt $this.StorageAvg) {
            $validationErrors += "StoragePeak ($($this.StoragePeak)) should be >= StorageAvg ($($this.StorageAvg))"
            $isValid = $false
        }
        
        # Log validation errors if any
        if ($validationErrors.Count -gt 0) {
            Write-Warning "Performance Data validation failed for '$($this.ServerName)' on $($this.Date.ToString('yyyy-MM-dd')): $($validationErrors -join '; ')"
        }
        
        return $isValid
    }
    
    # Convert to hashtable for easy manipulation
    [hashtable] ToHashtable() {
        return @{
            ServerName = $this.ServerName
            UniqueIdentifier = $this.UniqueIdentifier
            Date = $this.Date
            CpuPeak = $this.CpuPeak
            CpuAvg = $this.CpuAvg
            MemPeak = $this.MemPeak
            MemAvg = $this.MemAvg
            StoragePeak = $this.StoragePeak
            StorageAvg = $this.StorageAvg
            TimeInUsePercentage = $this.TimeInUsePercentage
            TimeOnPercentage = $this.TimeOnPercentage
            DataPointCount = $this.DataPointCount
            StatInterval = $this.StatInterval
            IsDefaultData = $this.IsDefaultData
        }
    }
    
    # String representation
    [string] ToString() {
        return "PerformanceDataModel: Server='$($this.ServerName)', Date='$($this.Date.ToString('yyyy-MM-dd'))', CPU Peak=$($this.CpuPeak), Mem Peak=$($this.MemPeak), DataPoints=$($this.DataPointCount)"
    }
    
    # Set default performance values for powered-off VMs
    [void] SetDefaultValues() {
        $this.CpuPeak = 0.25      # 25% as decimal
        $this.CpuAvg = 0.25       # 25% as decimal
        $this.MemPeak = 0.60      # 60% as decimal
        $this.MemAvg = 0.60       # 60% as decimal
        $this.StoragePeak = 0.50  # 50% as decimal (estimated)
        $this.StorageAvg = 0.50   # 50% as decimal (estimated)
        $this.TimeInUsePercentage = 0.0  # 0% for powered-off VM
        $this.TimeOnPercentage = 0.0     # 0% for powered-off VM
        $this.DataPointCount = 1
        $this.IsDefaultData = $true
    }
    
    # Convert percentage values from 0-100 scale to 0-1 decimal scale
    [void] ConvertPercentagesToDecimals([double] $cpuPeak, [double] $cpuAvg, [double] $memPeak, [double] $memAvg) {
        $this.CpuPeak = [Math]::Min(1.0, [Math]::Max(0.0, $cpuPeak / 100.0))
        $this.CpuAvg = [Math]::Min(1.0, [Math]::Max(0.0, $cpuAvg / 100.0))
        $this.MemPeak = [Math]::Min(1.0, [Math]::Max(0.0, $memPeak / 100.0))
        $this.MemAvg = [Math]::Min(1.0, [Math]::Max(0.0, $memAvg / 100.0))
    }
    
    # Get performance values as percentages (0-100 scale) for display
    [hashtable] GetPercentageValues() {
        return @{
            CpuPeakPct = [Math]::Round($this.CpuPeak * 100, 2)
            CpuAvgPct = [Math]::Round($this.CpuAvg * 100, 2)
            MemPeakPct = [Math]::Round($this.MemPeak * 100, 2)
            MemAvgPct = [Math]::Round($this.MemAvg * 100, 2)
            StoragePeakPct = [Math]::Round($this.StoragePeak * 100, 2)
            StorageAvgPct = [Math]::Round($this.StorageAvg * 100, 2)
            TimeInUsePct = [Math]::Round($this.TimeInUsePercentage * 100, 2)
            TimeOnPct = [Math]::Round($this.TimeOnPercentage * 100, 2)
        }
    }
    
    # Calculate data quality score based on data points and consistency
    [double] GetDataQualityScore() {
        if ($this.IsDefaultData) {
            return 0.0  # No real data
        }
        
        if ($this.DataPointCount -eq 0) {
            return 0.0
        }
        
        # Base score on data point count (more points = higher quality)
        $baseScore = [Math]::Min(1.0, $this.DataPointCount / 288.0)  # 288 = 24 hours * 12 (5-min intervals)
        
        # Adjust for consistency (peak should be >= average)
        $consistencyPenalty = 0.0
        if ($this.CpuPeak -lt $this.CpuAvg) { $consistencyPenalty += 0.1 }
        if ($this.MemPeak -lt $this.MemAvg) { $consistencyPenalty += 0.1 }
        if ($this.StoragePeak -lt $this.StorageAvg) { $consistencyPenalty += 0.1 }
        
        return [Math]::Max(0.0, $baseScore - $consistencyPenalty)
    }
    
    # Check if this is a complete day of data
    [bool] IsCompleteDayData() {
        # For 5-minute intervals: 288 data points = complete day
        # For 30-minute intervals: 48 data points = complete day
        # For 2-hour intervals: 12 data points = complete day
        
        $expectedDataPoints = switch ($this.StatInterval) {
            "5min" { 288 }
            "30min" { 48 }
            "2hr" { 12 }
            default { 288 }
        }
        
        return $this.DataPointCount -ge ($expectedDataPoints * 0.8)  # Allow 20% tolerance
    }
}