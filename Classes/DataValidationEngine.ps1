#
# DataValidationEngine.ps1 - Comprehensive data validation and quality assurance engine
#
# Implements comprehensive validation for VM data completeness, performance data ranges,
# unique identifier consistency, and data quality indicators as specified in requirements 8.9, 15.1-15.5
#

# Import required interfaces
if (Test-Path "$PSScriptRoot\Interfaces.ps1") {
    . "$PSScriptRoot\Interfaces.ps1"
}

class DataValidationEngine : IValidator {
    # Validation configuration
    [hashtable] $ValidationRules
    [hashtable] $ValidationErrors
    [hashtable] $ValidationWarnings
    [hashtable] $ValidationStatistics
    [hashtable] $UniqueIdentifierMap
    [bool] $StrictValidation
    [ILogger] $Logger
    
    # Data quality thresholds
    [double] $MinDataCompletenessThreshold = 0.85  # 85% completeness required
    [double] $MaxPerformanceVarianceThreshold = 0.15  # 15% variance allowed
    [int] $MinPerformanceDataPoints = 5  # Minimum data points for reliable metrics
    
    # Constructor
    DataValidationEngine() {
        $this.InitializeValidationRules()
        $this.ValidationErrors = @{}
        $this.ValidationWarnings = @{}
        $this.ValidationStatistics = @{}
        $this.UniqueIdentifierMap = @{}
        $this.StrictValidation = $true
    }
    
    DataValidationEngine([ILogger] $Logger) {
        $this.Logger = $Logger
        $this.InitializeValidationRules()
        $this.ValidationErrors = @{}
        $this.ValidationWarnings = @{}
        $this.ValidationStatistics = @{}
        $this.UniqueIdentifierMap = @{}
        $this.StrictValidation = $true
    }
    
    # Initialize validation rules based on requirements
    [void] InitializeValidationRules() {
        $this.ValidationRules = @{
            # Required fields for VM data completeness (Requirement 15.1)
            RequiredFields = @(
                'Name', 'NumCPUs', 'MemoryMB', 'TotalStorageGB', 'PowerState',
                'HostName', 'ClusterName', 'DatacenterName'
            )
            
            # Performance data range validation (Requirement 15.2)
            PerformanceRanges = @{
                'MaxCpuUsagePct' = @{ Min = 0; Max = 100 }
                'AvgCpuUsagePct' = @{ Min = 0; Max = 100 }
                'MaxRamUsagePct' = @{ Min = 0; Max = 100 }
                'AvgRamUsagePct' = @{ Min = 0; Max = 100 }
            }
            
            # Numeric field validation ranges
            NumericRanges = @{
                'NumCPUs' = @{ Min = 1; Max = 128 }
                'MemoryMB' = @{ Min = 1; Max = 4194304 }  # Up to 4TB
                'TotalStorageGB' = @{ Min = 0; Max = 102400 }  # Up to 100TB
                'PerformanceDataPoints' = @{ Min = 0; Max = 10080 }  # Max 7 days * 24 hours * 60 minutes
            }
            
            # String field validation patterns
            StringPatterns = @{
                'PowerState' = @('PoweredOn', 'PoweredOff', 'Suspended', 'Unknown')
                'ConnectionState' = @('Connected', 'Disconnected', 'Orphaned', 'Inaccessible', 'Unknown')
                'GuestState' = @('Running', 'NotRunning', 'Shutdown', 'Unknown')
                'VMwareToolsStatus' = @('toolsOk', 'toolsOld', 'toolsNotRunning', 'toolsNotInstalled', 'Unknown')
            }
            
            # Unique identifier fields (Requirement 15.3)
            UniqueIdentifierFields = @('Name', 'VMId', 'VMUuid', 'InstanceUuid', 'BiosUuid')
            
            # Data consistency rules
            ConsistencyRules = @{
                'MemoryConsistency' = @{
                    Description = 'Average performance should not exceed maximum performance'
                    Fields = @('MaxCpuUsagePct', 'AvgCpuUsagePct', 'MaxRamUsagePct', 'AvgRamUsagePct')
                }
                'StorageConsistency' = @{
                    Description = 'Committed storage should not exceed total storage'
                    Fields = @('TotalStorageGB', 'StorageCommittedGB')
                }
            }
        }
    }
    
    # Main validation method for VM data (Requirement 15.1)
    [bool] ValidateVMData([object] $VMData) {
        if ($null -eq $VMData) {
            $this.AddValidationError("VMData", "VM data object is null")
            return $false
        }
        
        $vmName = if ($VMData.Name) { $VMData.Name } else { "Unknown VM" }
        $isValid = $true
        
        try {
            # Initialize validation tracking for this VM
            if (-not $this.ValidationErrors.ContainsKey($vmName)) {
                $this.ValidationErrors[$vmName] = @()
                $this.ValidationWarnings[$vmName] = @()
            }
            
            # Validate data completeness
            $isValid = $this.ValidateDataCompleteness($VMData, $vmName) -and $isValid
            
            # Validate performance data ranges
            $isValid = $this.ValidatePerformanceDataRanges($VMData, $vmName) -and $isValid
            
            # Validate numeric ranges
            $isValid = $this.ValidateNumericRanges($VMData, $vmName) -and $isValid
            
            # Validate string patterns
            $isValid = $this.ValidateStringPatterns($VMData, $vmName) -and $isValid
            
            # Validate data consistency
            $isValid = $this.ValidateDataConsistency($VMData, $vmName) -and $isValid
            
            # Track unique identifiers
            $this.TrackUniqueIdentifiers($VMData, $vmName)
            
            # Log validation result
            if ($this.Logger) {
                if ($isValid) {
                    $this.Logger.WriteDebug("VM data validation passed for: $vmName")
                } else {
                    $errorCount = $this.ValidationErrors[$vmName].Count
                    $this.Logger.WriteWarning("VM data validation failed for: $vmName ($errorCount errors)")
                }
            }
            
        } catch {
            $this.AddValidationError($vmName, "Validation exception: $($_.Exception.Message)")
            $isValid = $false
            
            if ($this.Logger) {
                $this.Logger.WriteError("VM data validation exception for: $vmName", $_.Exception)
            }
        }
        
        return $isValid
    }
    
    # Validate data completeness (Requirement 15.1)
    [bool] ValidateDataCompleteness([object] $VMData, [string] $VMName) {
        $isValid = $true
        $missingFields = @()
        $emptyFields = @()
        
        foreach ($field in $this.ValidationRules.RequiredFields) {
            # Check if field exists
            if (-not $VMData.PSObject.Properties.Name -contains $field) {
                $missingFields += $field
                $isValid = $false
                continue
            }
            
            # Check if field has value
            $value = $VMData.$field
            if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
                $emptyFields += $field
                $isValid = $false
            }
        }
        
        # Report missing fields
        if ($missingFields.Count -gt 0) {
            $this.AddValidationError($VMName, "Missing required fields: $($missingFields -join ', ')")
        }
        
        # Report empty fields
        if ($emptyFields.Count -gt 0) {
            $this.AddValidationError($VMName, "Empty required fields: $($emptyFields -join ', ')")
        }
        
        # Calculate completeness percentage
        $totalRequiredFields = $this.ValidationRules.RequiredFields.Count
        $completedFields = $totalRequiredFields - $missingFields.Count - $emptyFields.Count
        $completenessPercentage = $completedFields / $totalRequiredFields
        
        # Check completeness threshold
        if ($completenessPercentage -lt $this.MinDataCompletenessThreshold) {
            $this.AddValidationWarning($VMName, "Data completeness below threshold: $([math]::Round($completenessPercentage * 100, 2))% (minimum: $([math]::Round($this.MinDataCompletenessThreshold * 100, 2))%)")
        }
        
        return $isValid
    }
    
    # Validate performance data ranges (0-100%) (Requirement 15.2)
    [bool] ValidatePerformanceDataRanges([object] $VMData, [string] $VMName) {
        $isValid = $true
        
        foreach ($field in $this.ValidationRules.PerformanceRanges.Keys) {
            if ($VMData.PSObject.Properties.Name -contains $field) {
                $value = $VMData.$field
                $range = $this.ValidationRules.PerformanceRanges[$field]
                
                if ($null -ne $value -and $value -is [double]) {
                    if ($value -lt $range.Min -or $value -gt $range.Max) {
                        $this.AddValidationError($VMName, "Performance field '$field' out of range: $value (valid range: $($range.Min)-$($range.Max))")
                        $isValid = $false
                    }
                    
                    # Additional validation for performance consistency
                    if ($field -eq 'MaxCpuUsagePct' -and $VMData.PSObject.Properties.Name -contains 'AvgCpuUsagePct') {
                        if ($VMData.AvgCpuUsagePct -gt $value) {
                            $this.AddValidationError($VMName, "Average CPU usage ($($VMData.AvgCpuUsagePct)%) exceeds maximum CPU usage ($value%)")
                            $isValid = $false
                        }
                    }
                    
                    if ($field -eq 'MaxRamUsagePct' -and $VMData.PSObject.Properties.Name -contains 'AvgRamUsagePct') {
                        if ($VMData.AvgRamUsagePct -gt $value) {
                            $this.AddValidationError($VMName, "Average RAM usage ($($VMData.AvgRamUsagePct)%) exceeds maximum RAM usage ($value%)")
                            $isValid = $false
                        }
                    }
                }
            }
        }
        
        # Validate performance data quality
        if ($VMData.PSObject.Properties.Name -contains 'PerformanceDataPoints') {
            $dataPoints = $VMData.PerformanceDataPoints
            if ($dataPoints -lt $this.MinPerformanceDataPoints -and $VMData.PowerState -eq 'PoweredOn') {
                $this.AddValidationWarning($VMName, "Low performance data points: $dataPoints (minimum recommended: $($this.MinPerformanceDataPoints))")
            }
        }
        
        return $isValid
    }
    
    # Validate numeric field ranges
    [bool] ValidateNumericRanges([object] $VMData, [string] $VMName) {
        $isValid = $true
        
        foreach ($field in $this.ValidationRules.NumericRanges.Keys) {
            if ($VMData.PSObject.Properties.Name -contains $field) {
                $value = $VMData.$field
                $range = $this.ValidationRules.NumericRanges[$field]
                
                if ($null -ne $value -and ($value -is [int] -or $value -is [double])) {
                    if ($value -lt $range.Min -or $value -gt $range.Max) {
                        $this.AddValidationError($VMName, "Numeric field '$field' out of range: $value (valid range: $($range.Min)-$($range.Max))")
                        $isValid = $false
                    }
                }
            }
        }
        
        return $isValid
    }
    
    # Validate string field patterns
    [bool] ValidateStringPatterns([object] $VMData, [string] $VMName) {
        $isValid = $true
        
        foreach ($field in $this.ValidationRules.StringPatterns.Keys) {
            if ($VMData.PSObject.Properties.Name -contains $field) {
                $value = $VMData.$field
                $validValues = $this.ValidationRules.StringPatterns[$field]
                
                if ($null -ne $value -and $value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) {
                    if ($validValues -notcontains $value) {
                        $this.AddValidationError($VMName, "String field '$field' has invalid value: '$value' (valid values: $($validValues -join ', '))")
                        $isValid = $false
                    }
                }
            }
        }
        
        return $isValid
    }
    
    # Validate data consistency rules
    [bool] ValidateDataConsistency([object] $VMData, [string] $VMName) {
        $isValid = $true
        
        # Memory consistency: Average should not exceed maximum
        if ($VMData.PSObject.Properties.Name -contains 'MaxCpuUsagePct' -and 
            $VMData.PSObject.Properties.Name -contains 'AvgCpuUsagePct') {
            if ($VMData.AvgCpuUsagePct -gt $VMData.MaxCpuUsagePct) {
                $this.AddValidationError($VMName, "Data consistency error: Average CPU usage ($($VMData.AvgCpuUsagePct)%) exceeds maximum ($($VMData.MaxCpuUsagePct)%)")
                $isValid = $false
            }
        }
        
        if ($VMData.PSObject.Properties.Name -contains 'MaxRamUsagePct' -and 
            $VMData.PSObject.Properties.Name -contains 'AvgRamUsagePct') {
            if ($VMData.AvgRamUsagePct -gt $VMData.MaxRamUsagePct) {
                $this.AddValidationError($VMName, "Data consistency error: Average RAM usage ($($VMData.AvgRamUsagePct)%) exceeds maximum ($($VMData.MaxRamUsagePct)%)")
                $isValid = $false
            }
        }
        
        # Storage consistency: Committed should not exceed total
        if ($VMData.PSObject.Properties.Name -contains 'TotalStorageGB' -and 
            $VMData.PSObject.Properties.Name -contains 'StorageCommittedGB') {
            if ($VMData.StorageCommittedGB -gt $VMData.TotalStorageGB) {
                $this.AddValidationError($VMName, "Data consistency error: Committed storage ($($VMData.StorageCommittedGB)GB) exceeds total storage ($($VMData.TotalStorageGB)GB)")
                $isValid = $false
            }
        }
        
        return $isValid
    }
    
    # Track unique identifiers for consistency checking (Requirement 15.3)
    [void] TrackUniqueIdentifiers([object] $VMData, [string] $VMName) {
        foreach ($field in $this.ValidationRules.UniqueIdentifierFields) {
            if ($VMData.PSObject.Properties.Name -contains $field) {
                $value = $VMData.$field
                
                if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace($value)) {
                    if (-not $this.UniqueIdentifierMap.ContainsKey($field)) {
                        $this.UniqueIdentifierMap[$field] = @{}
                    }
                    
                    if ($this.UniqueIdentifierMap[$field].ContainsKey($value)) {
                        # Duplicate identifier found
                        $existingVM = $this.UniqueIdentifierMap[$field][$value]
                        $this.AddValidationError($VMName, "Duplicate unique identifier '$field': '$value' (also used by: $existingVM)")
                        $this.AddValidationError($existingVM, "Duplicate unique identifier '$field': '$value' (also used by: $VMName)")
                    } else {
                        $this.UniqueIdentifierMap[$field][$value] = $VMName
                    }
                }
            }
        }
    }
    
    # Validate output file structure and format (Requirement 15.6-15.10)
    [bool] ValidateOutputFile([string] $FilePath, [string] $Format) {
        if (-not (Test-Path $FilePath)) {
            $this.AddValidationError("File", "Output file does not exist: $FilePath")
            return $false
        }
        
        $isValid = $true
        
        try {
            switch ($Format.ToUpper()) {
                'ME' {
                    $isValid = $this.ValidateMEFormat($FilePath)
                }
                'MPA' {
                    $isValid = $this.ValidateMPAFormat($FilePath)
                }
                'RVTOOLS' {
                    $isValid = $this.ValidateRVToolsFormat($FilePath)
                }
                default {
                    $this.AddValidationError("File", "Unknown format for validation: $Format")
                    $isValid = $false
                }
            }
        } catch {
            $this.AddValidationError("File", "File validation exception for $FilePath`: $($_.Exception.Message)")
            $isValid = $false
        }
        
        return $isValid
    }
    
    # Validate ME format file structure
    [bool] ValidateMEFormat([string] $FilePath) {
        $isValid = $true
        
        try {
            # Check if it's an Excel file
            if (-not $FilePath.EndsWith('.xlsx')) {
                $this.AddValidationError("ME", "ME format file must be .xlsx format")
                return $false
            }
            
            # Additional ME format validation would require Excel COM object
            # For now, validate file existence and extension
            $fileInfo = Get-Item $FilePath
            if ($fileInfo.Length -eq 0) {
                $this.AddValidationError("ME", "ME format file is empty")
                $isValid = $false
            }
            
        } catch {
            $this.AddValidationError("ME", "ME format validation error: $($_.Exception.Message)")
            $isValid = $false
        }
        
        return $isValid
    }
    
    # Validate MPA format file structure
    [bool] ValidateMPAFormat([string] $FilePath) {
        $isValid = $true
        
        try {
            # Check if it's a CSV file
            if (-not $FilePath.EndsWith('.csv')) {
                $this.AddValidationError("MAP", "MAP format file must be .csv format")
                return $false
            }
            
            # Read and validate CSV structure
            $csvContent = Import-Csv $FilePath
            if ($csvContent.Count -eq 0) {
                $this.AddValidationError("MAP", "MAP format file contains no data")
                $isValid = $false
            }
            
            # Validate required columns (22 columns as per specification)
            $requiredColumns = @(
                'Serverid', 'Migration Evaluator GUID', 'isPhysical', 'hypervisor', 'HOSTNAME',
                'osName', 'osVersion', 'numCpus', 'numCoresPerCpu', 'numThreadsPerCore',
                'maxCpuUsage', 'avgCpuUsage', 'totalRAM (GB)', 'maxRamUsage', 'avgRamUsage',
                'Uptime', 'Environment Type', 'Storage-Total Disk Size (GB)', 'Storage-Utilization %',
                'Storage-Max Read IOPS Size (KB)', 'Storage-Max Write IOPS Size (KB)', 'EC2 Instance Preference'
            )
            
            $actualColumns = $csvContent[0].PSObject.Properties.Name
            $missingColumns = $requiredColumns | Where-Object { $_ -notin $actualColumns }
            
            if ($missingColumns.Count -gt 0) {
                $this.AddValidationError("MAP", "MAP format missing required columns: $($missingColumns -join ', ')")
                $isValid = $false
            }
            
        } catch {
            $this.AddValidationError("MAP", "MAP format validation error: $($_.Exception.Message)")
            $isValid = $false
        }
        
        return $isValid
    }
    
    # Validate RVTools format file structure
    [bool] ValidateRVToolsFormat([string] $FilePath) {
        $isValid = $true
        
        try {
            # Check if it's a ZIP file
            if (-not $FilePath.EndsWith('.zip')) {
                $this.AddValidationError("RVTools", "RVTools format file must be .zip format")
                return $false
            }
            
            # Additional RVTools format validation would require ZIP extraction
            # For now, validate file existence and extension
            $fileInfo = Get-Item $FilePath
            if ($fileInfo.Length -eq 0) {
                $this.AddValidationError("RVTools", "RVTools format file is empty")
                $isValid = $false
            }
            
        } catch {
            $this.AddValidationError("RVTools", "RVTools format validation error: $($_.Exception.Message)")
            $isValid = $false
        }
        
        return $isValid
    }
    
    # Get all validation errors
    [array] GetValidationErrors() {
        $allErrors = @()
        
        foreach ($vmName in $this.ValidationErrors.Keys) {
            foreach ($error in $this.ValidationErrors[$vmName]) {
                $allErrors += @{
                    VMName = $vmName
                    Error = $error
                    Timestamp = Get-Date
                }
            }
        }
        
        return $allErrors
    }
    
    # Get comprehensive validation report
    [hashtable] GetValidationReport() {
        $totalVMs = $this.ValidationErrors.Keys.Count
        $vmsWithErrors = ($this.ValidationErrors.Keys | Where-Object { $this.ValidationErrors[$_].Count -gt 0 }).Count
        $vmsWithWarnings = ($this.ValidationWarnings.Keys | Where-Object { $this.ValidationWarnings[$_].Count -gt 0 }).Count
        $totalErrors = ($this.ValidationErrors.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        $totalWarnings = ($this.ValidationWarnings.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        
        # Calculate data quality score
        $dataQualityScore = if ($totalVMs -gt 0) {
            [math]::Round((($totalVMs - $vmsWithErrors) / $totalVMs) * 100, 2)
        } else { 0 }
        
        # Generate unique identifier statistics
        $uniqueIdStats = @{}
        foreach ($field in $this.UniqueIdentifierMap.Keys) {
            $uniqueIdStats[$field] = @{
                TotalValues = $this.UniqueIdentifierMap[$field].Count
                UniqueValues = $this.UniqueIdentifierMap[$field].Keys.Count
                DuplicateCount = $this.UniqueIdentifierMap[$field].Count - $this.UniqueIdentifierMap[$field].Keys.Count
            }
        }
        
        return @{
            Summary = @{
                TotalVMsValidated = $totalVMs
                VMsWithErrors = $vmsWithErrors
                VMsWithWarnings = $vmsWithWarnings
                TotalErrors = $totalErrors
                TotalWarnings = $totalWarnings
                DataQualityScore = $dataQualityScore
                ValidationTimestamp = Get-Date
            }
            
            DataQuality = @{
                Score = $dataQualityScore
                Threshold = $this.MinDataCompletenessThreshold * 100
                Status = if ($dataQualityScore -ge ($this.MinDataCompletenessThreshold * 100)) { "PASS" } else { "FAIL" }
                Recommendation = if ($dataQualityScore -lt ($this.MinDataCompletenessThreshold * 100)) {
                    "Data quality below threshold. Review and correct validation errors before proceeding."
                } else {
                    "Data quality meets requirements for migration assessment use."
                }
            }
            
            UniqueIdentifiers = $uniqueIdStats
            
            ValidationErrors = $this.ValidationErrors
            ValidationWarnings = $this.ValidationWarnings
            
            Statistics = @{
                RequiredFieldsValidated = $this.ValidationRules.RequiredFields.Count
                PerformanceFieldsValidated = $this.ValidationRules.PerformanceRanges.Keys.Count
                NumericFieldsValidated = $this.ValidationRules.NumericRanges.Keys.Count
                StringFieldsValidated = $this.ValidationRules.StringPatterns.Keys.Count
                UniqueIdentifierFieldsTracked = $this.ValidationRules.UniqueIdentifierFields.Count
            }
        }
    }
    
    # Helper method to add validation error
    [void] AddValidationError([string] $VMName, [string] $Error) {
        if (-not $this.ValidationErrors.ContainsKey($VMName)) {
            $this.ValidationErrors[$VMName] = @()
        }
        $this.ValidationErrors[$VMName] += $Error
    }
    
    # Helper method to add validation warning
    [void] AddValidationWarning([string] $VMName, [string] $Warning) {
        if (-not $this.ValidationWarnings.ContainsKey($VMName)) {
            $this.ValidationWarnings[$VMName] = @()
        }
        $this.ValidationWarnings[$VMName] += $Warning
    }
    
    # Reset validation state for new validation run
    [void] ResetValidationState() {
        $this.ValidationErrors.Clear()
        $this.ValidationWarnings.Clear()
        $this.ValidationStatistics.Clear()
        $this.UniqueIdentifierMap.Clear()
    }
    
    # Set validation configuration
    [void] SetValidationConfiguration([hashtable] $Config) {
        if ($Config.ContainsKey('StrictValidation')) {
            $this.StrictValidation = $Config.StrictValidation
        }
        if ($Config.ContainsKey('MinDataCompletenessThreshold')) {
            $this.MinDataCompletenessThreshold = $Config.MinDataCompletenessThreshold
        }
        if ($Config.ContainsKey('MaxPerformanceVarianceThreshold')) {
            $this.MaxPerformanceVarianceThreshold = $Config.MaxPerformanceVarianceThreshold
        }
        if ($Config.ContainsKey('MinPerformanceDataPoints')) {
            $this.MinPerformanceDataPoints = $Config.MinPerformanceDataPoints
        }
    }
    
    # Get validation configuration
    [hashtable] GetValidationConfiguration() {
        return @{
            StrictValidation = $this.StrictValidation
            MinDataCompletenessThreshold = $this.MinDataCompletenessThreshold
            MaxPerformanceVarianceThreshold = $this.MaxPerformanceVarianceThreshold
            MinPerformanceDataPoints = $this.MinPerformanceDataPoints
            ValidationRules = $this.ValidationRules
        }
    }
}