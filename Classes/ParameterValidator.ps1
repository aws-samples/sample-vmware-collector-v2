#
# ParameterValidator.ps1 - Validates input parameters for VMware collection
#
# Replicates parameter validation logic from vmware-collector.ps1
#

# Dependencies: Interfaces.ps1 (loaded by module)

class ParameterValidator {
    [ILogger] $Logger
    [InputValidator] $InputValidator
    
    ParameterValidator([ILogger] $Logger) {
        $this.Logger = $Logger
        . "$PSScriptRoot\InputValidator.ps1"
        $this.InputValidator = [InputValidator]::new()
    }
    
    # Main parameter validation method
    [hashtable] ValidateParameters([hashtable] $Parameters) {
        try {
            $this.Logger.WriteDebug("Starting parameter validation...")
            
            # Validate required parameters
            $requiredParams = @('address', 'username', 'password')
            foreach ($param in $requiredParams) {
                if (-not $Parameters.ContainsKey($param) -or [string]::IsNullOrEmpty($Parameters[$param])) {
                    return @{
                        IsValid = $false
                        ErrorMessage = "Required parameter '$param' is missing or empty"
                    }
                }
            }
            
            # Validate numeric ranges
            $rangeValidations = @{
                collectionDays = @{ Min = 1; Max = 365; Default = 7 }
                port = @{ Min = 1; Max = 65535; Default = 0 }
                maxParallelThreads = @{ Min = 1; Max = 50; Default = 20 }
            }
            
            foreach ($param in $rangeValidations.Keys) {
                if ($Parameters.ContainsKey($param)) {
                    $value = $Parameters[$param]
                    $range = $rangeValidations[$param]
                    
                    if ($value -lt $range.Min -or $value -gt $range.Max) {
                        return @{
                            IsValid = $false
                            ErrorMessage = "Parameter '$param' must be between $($range.Min) and $($range.Max)"
                        }
                    }
                }
            }
            
            # Validate enum values
            $enumValidations = @{
                filterVMs = @('Y', 'N')
                protocol = @('http', 'https')
                outputFormat = @('All', 'ME', 'MPA', 'RVTools')
                IncludeEnvironment = @('Production', 'NonProduction')
                ExcludeEnvironment = @('Production', 'NonProduction')
            }
            
            foreach ($param in $enumValidations.Keys) {
                if ($Parameters.ContainsKey($param) -and -not [string]::IsNullOrEmpty($Parameters[$param])) {
                    $value = $Parameters[$param]
                    $validValues = $enumValidations[$param]
                    
                    if ($value -notin $validValues) {
                        return @{
                            IsValid = $false
                            ErrorMessage = "Parameter '$param' must be one of: $($validValues -join ', ')"
                        }
                    }
                }
            }
            
            # Validate filter conflicts (replicates Test-FilterConflicts from vmware-collector.ps1)
            $conflictResult = $this.ValidateFilterConflicts($Parameters)
            if (-not $conflictResult.IsValid) {
                return $conflictResult
            }
            
            # Validate VM list file if specified
            if ($Parameters.ContainsKey('vmListFile') -and -not [string]::IsNullOrEmpty($Parameters.vmListFile)) {
                $fileValidation = $this.ValidateVMListFile($Parameters.vmListFile)
                if (-not $fileValidation.IsValid) {
                    return $fileValidation
                }
            }
            
            $this.Logger.WriteDebug("Parameter validation completed successfully")
            
            return @{
                IsValid = $true
                ErrorMessage = $null
            }
            
        } catch {
            $this.Logger.WriteError("Parameter validation failed: $($_.Exception.Message)", $_.Exception)
            return @{
                IsValid = $false
                ErrorMessage = "Parameter validation error: $($_.Exception.Message)"
            }
        }
    }
    
    # Validate filter conflicts (replicates Test-FilterConflicts function)
    [hashtable] ValidateFilterConflicts([hashtable] $Parameters) {
        $conflicts = @()
        
        # Check for conflicting include/exclude parameters for the same filter type
        $filterPairs = @(
            @('IncludeCluster', 'ExcludeCluster'),
            @('IncludeDatacenter', 'ExcludeDatacenter'),
            @('IncludeHost', 'ExcludeHost'),
            @('IncludeEnvironment', 'ExcludeEnvironment')
        )
        
        foreach ($pair in $filterPairs) {
            $includeParam = $pair[0]
            $excludeParam = $pair[1]
            
            $hasInclude = $Parameters.ContainsKey($includeParam) -and -not [string]::IsNullOrEmpty($Parameters[$includeParam])
            $hasExclude = $Parameters.ContainsKey($excludeParam) -and -not [string]::IsNullOrEmpty($Parameters[$excludeParam])
            
            if ($hasInclude -and $hasExclude) {
                $conflicts += "Cannot specify both $includeParam and $excludeParam parameters"
            }
        }
        
        if ($conflicts.Count -gt 0) {
            return @{
                IsValid = $false
                ErrorMessage = "Filter conflicts detected: $($conflicts -join '; ')"
            }
        }
        
        return @{
            IsValid = $true
            ErrorMessage = $null
        }
    }
    
    # Validate VM list file
    [hashtable] ValidateVMListFile([string] $FilePath) {
        try {
            # Use secure path validation
            $validatedPath = $this.InputValidator.ValidateFilePath($FilePath, $true)
            
            $fileExtension = [System.IO.Path]::GetExtension($validatedPath).ToLower()
            if ($fileExtension -notin @('.csv', '.txt')) {
                return @{
                    IsValid = $false
                    ErrorMessage = "VM list file must be .csv or .txt format"
                }
            }
            
            # Basic content validation
            if ($fileExtension -eq '.csv') {
                try {
                    $csvData = Import-Csv $validatedPath -ErrorAction Stop
                    if ($csvData.Count -eq 0) {
                        return @{
                            IsValid = $false
                            ErrorMessage = "CSV file is empty"
                        }
                    }
                    
                    # Check for VM name columns
                    $possibleColumns = @('VM', 'Name', 'VMName', 'VirtualMachine', 'Server', 'ServerName')
                    $hasValidColumn = $false
                    
                    foreach ($col in $possibleColumns) {
                        if ($csvData[0].PSObject.Properties.Name -contains $col) {
                            $hasValidColumn = $true
                            break
                        }
                    }
                    
                    if (-not $hasValidColumn) {
                        return @{
                            IsValid = $false
                            ErrorMessage = "CSV file must contain one of these columns: $($possibleColumns -join ', ')"
                        }
                    }
                    
                } catch {
                    return @{
                        IsValid = $false
                        ErrorMessage = "Failed to read CSV file: $($_.Exception.Message)"
                    }
                }
            } elseif ($fileExtension -eq '.txt') {
                try {
                    $txtContent = Get-Content $validatedPath -ErrorAction Stop
                    $nonEmptyLines = $txtContent | Where-Object { $_ -and $_.Trim() -ne '' }
                    
                    if ($nonEmptyLines.Count -eq 0) {
                        return @{
                            IsValid = $false
                            ErrorMessage = "TXT file contains no VM names"
                        }
                    }
                    
                } catch {
                    return @{
                        IsValid = $false
                        ErrorMessage = "Failed to read TXT file: $($_.Exception.Message)"
                    }
                }
            }
            
            return @{
                IsValid = $true
                ErrorMessage = $null
            }
            
        } catch {
            return @{
                IsValid = $false
                ErrorMessage = "VM list file validation error: $($_.Exception.Message)"
            }
        }
    }
    
    # Set default values for optional parameters
    [hashtable] ApplyDefaultValues([hashtable] $Parameters) {
        $defaults = @{
            collectionDays = 7
            filterVMs = 'Y'
            protocol = 'https'
            port = 0
            outputFormat = 'All'
            purgeCSV = $true
            maxParallelThreads = 20
            enableLogging = $false
            disableSSL = $false
            skipPerformanceData = $false
            anonymize = $false
            fastMode = $false
        }
        
        $result = $Parameters.Clone()
        
        foreach ($key in $defaults.Keys) {
            if (-not $result.ContainsKey($key)) {
                $result[$key] = $defaults[$key]
            }
        }
        
        return $result
    }
}