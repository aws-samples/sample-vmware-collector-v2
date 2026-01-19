#
# DataAnonymizationProcessor.ps1 - Data anonymization processor for all output formats
#
# Applies anonymization to all output formats (ME, MAP, RVTools) while preserving
# performance metrics and technical specifications. Adds "_ANONYMIZED_" suffix to filenames.
#

using module .\Interfaces.ps1
using module .\AnonymizationMappingModel.ps1

class DataAnonymizationProcessor {
    [AnonymizationEngine] $AnonymizationEngine
    [ILogger] $Logger
    [bool] $IsEnabled
    [hashtable] $ProcessingStatistics
    
    # Constructor
    DataAnonymizationProcessor() {
        $this.AnonymizationEngine = [AnonymizationEngine]::new()
        $this.IsEnabled = $false
        $this.ProcessingStatistics = @{
            ProcessedFiles = 0
            ProcessedRecords = 0
            AnonymizedFields = 0
            StartTime = $null
            EndTime = $null
        }
    }
    
    DataAnonymizationProcessor([ILogger] $Logger) {
        $this.AnonymizationEngine = [AnonymizationEngine]::new($Logger)
        $this.Logger = $Logger
        $this.IsEnabled = $false
        $this.ProcessingStatistics = @{
            ProcessedFiles = 0
            ProcessedRecords = 0
            AnonymizedFields = 0
            StartTime = $null
            EndTime = $null
        }
    }
    
    # Enable/disable anonymization
    [void] SetEnabled([bool] $Enabled) {
        $this.IsEnabled = $Enabled
        $this.WriteLog("Data anonymization " + ($Enabled ? "enabled" : "disabled"), "Information")
    }
    
    # Process VM data for anonymization
    [array] ProcessVMData([array] $VMData) {
        if (!$this.IsEnabled) {
            $this.WriteLog("Anonymization is disabled, returning original data", "Debug")
            return $VMData
        }
        
        $this.ProcessingStatistics.StartTime = Get-Date
        $this.WriteLog("Starting anonymization processing for $($VMData.Count) VM records", "Information")
        
        try {
            $anonymizedData = $this.AnonymizationEngine.AnonymizeVMData($VMData)
            
            $this.ProcessingStatistics.ProcessedRecords = $VMData.Count
            $this.ProcessingStatistics.EndTime = Get-Date
            
            $this.WriteLog("Completed anonymization processing for $($VMData.Count) VM records", "Information")
            return $anonymizedData
        }
        catch {
            $this.WriteLog("Error during VM data anonymization: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Process ME format output with anonymization
    [void] ProcessMEOutput([string] $OriginalFilePath, [array] $VMData) {
        if (!$this.IsEnabled) {
            return
        }
        
        try {
            $this.WriteLog("Processing ME format for anonymization: $OriginalFilePath", "Information")
            
            # Generate anonymized filename
            $anonymizedFilePath = $this.GenerateAnonymizedFileName($OriginalFilePath)
            
            # Anonymize VM data
            $anonymizedVMData = $this.ProcessVMData($VMData)
            
            # Create new ME format generator and generate anonymized output
            $meGenerator = [MEFormatGenerator]::new($this.Logger)
            $outputDir = Split-Path $anonymizedFilePath -Parent
            $meGenerator.GenerateOutput($anonymizedVMData, $outputDir)
            
            # Rename the generated file to include anonymized suffix
            $generatedFile = $this.FindGeneratedMEFile($outputDir)
            if ($generatedFile -and (Test-Path $generatedFile)) {
                Move-Item $generatedFile $anonymizedFilePath -Force
                $this.WriteLog("Created anonymized ME file: $anonymizedFilePath", "Information")
            }
            
            $this.ProcessingStatistics.ProcessedFiles++
        }
        catch {
            $this.WriteLog("Error processing ME format for anonymization: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Process MAP format output with anonymization
    [void] ProcessMAPOutput([string] $OriginalFilePath, [array] $VMData) {
        if (!$this.IsEnabled) {
            return
        }
        
        try {
            $this.WriteLog("Processing MAP format for anonymization: $OriginalFilePath", "Information")
            
            # Generate anonymized filename
            $anonymizedFilePath = $this.GenerateAnonymizedFileName($OriginalFilePath)
            
            # Anonymize VM data
            $anonymizedVMData = $this.ProcessVMData($VMData)
            
            # Create new MPA format generator and generate anonymized output
            $mpaGenerator = [MPAFormatGenerator]::new($this.Logger)
            $outputDir = Split-Path $anonymizedFilePath -Parent
            $mpaGenerator.GenerateOutput($anonymizedVMData, $outputDir)
            
            # Rename the generated file to include anonymized suffix
            $generatedFile = $this.FindGeneratedMAPFile($outputDir)
            if ($generatedFile -and (Test-Path $generatedFile)) {
                Move-Item $generatedFile $anonymizedFilePath -Force
                $this.WriteLog("Created anonymized MAP file: $anonymizedFilePath", "Information")
            }
            
            $this.ProcessingStatistics.ProcessedFiles++
        }
        catch {
            $this.WriteLog("Error processing MAP format for anonymization: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Process RVTools format output with anonymization
    [void] ProcessRVToolsOutput([string] $OriginalFilePath, [array] $VMData) {
        if (!$this.IsEnabled) {
            return
        }
        
        try {
            $this.WriteLog("Processing RVTools format for anonymization: $OriginalFilePath", "Information")
            
            # Generate anonymized filename
            $anonymizedFilePath = $this.GenerateAnonymizedFileName($OriginalFilePath)
            
            # Anonymize VM data
            $anonymizedVMData = $this.ProcessVMData($VMData)
            
            # Create new RVTools format generator and generate anonymized output
            $rvToolsGenerator = [RVToolsFormatGenerator]::new($this.Logger)
            $outputDir = Split-Path $anonymizedFilePath -Parent
            $rvToolsGenerator.GenerateOutput($anonymizedVMData, $outputDir)
            
            # Rename the generated file to include anonymized suffix
            $generatedFile = $this.FindGeneratedRVToolsFile($outputDir)
            if ($generatedFile -and (Test-Path $generatedFile)) {
                Move-Item $generatedFile $anonymizedFilePath -Force
                $this.WriteLog("Created anonymized RVTools file: $anonymizedFilePath", "Information")
            }
            
            $this.ProcessingStatistics.ProcessedFiles++
        }
        catch {
            $this.WriteLog("Error processing RVTools format for anonymization: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Process all output formats with anonymization
    [void] ProcessAllOutputs([hashtable] $OutputFiles, [array] $VMData) {
        if (!$this.IsEnabled) {
            $this.WriteLog("Anonymization is disabled, skipping output processing", "Debug")
            return
        }
        
        $this.WriteLog("Processing all output formats for anonymization", "Information")
        
        try {
            # Process ME format if present
            if ($OutputFiles.ContainsKey("ME") -and ![string]::IsNullOrEmpty($OutputFiles["ME"])) {
                $this.ProcessMEOutput($OutputFiles["ME"], $VMData)
            }
            
            # Process MAP format if present
            if ($OutputFiles.ContainsKey("MAP") -and ![string]::IsNullOrEmpty($OutputFiles["MAP"])) {
                $this.ProcessMAPOutput($OutputFiles["MAP"], $VMData)
            }
            
            # Process RVTools format if present
            if ($OutputFiles.ContainsKey("RVTools") -and ![string]::IsNullOrEmpty($OutputFiles["RVTools"])) {
                $this.ProcessRVToolsOutput($OutputFiles["RVTools"], $VMData)
            }
            
            $this.WriteLog("Completed processing all output formats for anonymization", "Information")
        }
        catch {
            $this.WriteLog("Error processing outputs for anonymization: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Generate anonymized filename with "_ANONYMIZED_" suffix
    [string] GenerateAnonymizedFileName([string] $OriginalFilePath) {
        $directory = Split-Path $OriginalFilePath -Parent
        $fileName = Split-Path $OriginalFilePath -LeafBase
        $extension = Split-Path $OriginalFilePath -Extension
        
        # Insert "_ANONYMIZED_" before the file extension
        $anonymizedFileName = "${fileName}_ANONYMIZED_${extension}"
        $anonymizedFilePath = Join-Path $directory $anonymizedFileName
        
        $this.WriteLog("Generated anonymized filename: $OriginalFilePath -> $anonymizedFilePath", "Debug")
        return $anonymizedFilePath
    }
    
    # Find the most recently generated ME file in the output directory
    [string] FindGeneratedMEFile([string] $OutputDirectory) {
        $meFiles = Get-ChildItem -Path $OutputDirectory -Filter "VMWARE_Inventory_And_Usage_Workbook_*.xlsx" | 
                   Sort-Object LastWriteTime -Descending | 
                   Select-Object -First 1
        
        if ($meFiles) {
            return $meFiles.FullName
        }
        return $null
    }
    
    # Find the most recently generated MAP file in the output directory
    [string] FindGeneratedMAPFile([string] $OutputDirectory) {
        $mapFiles = Get-ChildItem -Path $OutputDirectory -Filter "MPA_Template_*.csv" | 
                    Sort-Object LastWriteTime -Descending | 
                    Select-Object -First 1
        
        if ($mapFiles) {
            return $mapFiles.FullName
        }
        return $null
    }
    
    # Find the most recently generated RVTools file in the output directory
    [string] FindGeneratedRVToolsFile([string] $OutputDirectory) {
        $rvToolsFiles = Get-ChildItem -Path $OutputDirectory -Filter "RVTools_Export_*.zip" | 
                        Sort-Object LastWriteTime -Descending | 
                        Select-Object -First 1
        
        if ($rvToolsFiles) {
            return $rvToolsFiles.FullName
        }
        return $null
    }
    
    # Validate that performance metrics and technical specifications are preserved
    [bool] ValidateDataPreservation([array] $OriginalData, [array] $AnonymizedData) {
        if ($OriginalData.Count -ne $AnonymizedData.Count) {
            $this.WriteLog("Data count mismatch: Original=$($OriginalData.Count), Anonymized=$($AnonymizedData.Count)", "Error")
            return $false
        }
        
        $preservedFields = @(
            'NumCPUs', 'MemoryMB', 'TotalStorageGB', 'HardwareVersion',
            'MaxCpuUsagePct', 'AvgCpuUsagePct', 'MaxRamUsagePct', 'AvgRamUsagePct',
            'PerformanceDataPoints', 'PerformanceCollectionPeriod',
            'PowerState', 'ConnectionState', 'GuestState', 'VMwareToolsStatus',
            'CPUReservation', 'CPULimit', 'MemoryReservation', 'MemoryLimit',
            'SnapshotCount', 'SnapshotSizeGB', 'StorageCommittedGB', 'StorageUncommittedGB'
        )
        
        for ($i = 0; $i -lt $OriginalData.Count; $i++) {
            $original = $OriginalData[$i]
            $anonymized = $AnonymizedData[$i]
            
            foreach ($field in $preservedFields) {
                if ($original.$field -ne $anonymized.$field) {
                    $this.WriteLog("Performance/technical data not preserved for field '$field': Original=$($original.$field), Anonymized=$($anonymized.$field)", "Error")
                    return $false
                }
            }
        }
        
        $this.WriteLog("Data preservation validation passed - all performance metrics and technical specifications preserved", "Information")
        return $true
    }
    
    # Get anonymization mapping table
    [hashtable] GetMappingTable() {
        return $this.AnonymizationEngine.GetMappingTable()
    }
    
    # Get processing statistics
    [hashtable] GetProcessingStatistics() {
        $stats = $this.ProcessingStatistics.Clone()
        
        if ($null -ne $stats.StartTime -and $null -ne $stats.EndTime) {
            $stats.ProcessingDuration = $stats.EndTime - $stats.StartTime
        }
        
        # Add anonymization engine statistics
        $mappingStats = $this.AnonymizationEngine.GetMappingStatistics()
        $stats.MappingStatistics = $mappingStats
        
        return $stats
    }
    
    # Reset processing statistics
    [void] ResetStatistics() {
        $this.ProcessingStatistics = @{
            ProcessedFiles = 0
            ProcessedRecords = 0
            AnonymizedFields = 0
            StartTime = $null
            EndTime = $null
        }
        
        $this.WriteLog("Processing statistics have been reset", "Information")
    }
    
    # Get anonymization engine for direct access
    [AnonymizationEngine] GetAnonymizationEngine() {
        return $this.AnonymizationEngine
    }
    
    # Helper method for logging
    [void] WriteLog([string] $Message, [string] $Level) {
        if ($null -ne $this.Logger) {
            switch ($Level) {
                "Error" { $this.Logger.WriteError($Message, $null) }
                "Warning" { $this.Logger.WriteWarning($Message) }
                "Information" { $this.Logger.WriteInformation($Message) }
                "Debug" { $this.Logger.WriteDebug($Message) }
                "Verbose" { $this.Logger.WriteVerbose($Message) }
                default { $this.Logger.WriteInformation($Message) }
            }
        }
        else {
            Write-Host "[$Level] $Message"
        }
    }
}

# Output format processor that integrates anonymization into existing generators
class AnonymizedOutputProcessor {
    [DataAnonymizationProcessor] $AnonymizationProcessor
    [ILogger] $Logger
    [hashtable] $OutputGenerators
    
    # Constructor
    AnonymizedOutputProcessor([DataAnonymizationProcessor] $AnonymizationProcessor, [ILogger] $Logger) {
        $this.AnonymizationProcessor = $AnonymizationProcessor
        $this.Logger = $Logger
        $this.OutputGenerators = @{
            ME = $null
            MAP = $null
            RVTools = $null
        }
    }
    
    # Set output generators
    [void] SetOutputGenerators([hashtable] $Generators) {
        $this.OutputGenerators = $Generators
    }
    
    # Generate all outputs with optional anonymization
    [hashtable] GenerateAllOutputs([array] $VMData, [string] $OutputPath, [array] $Formats) {
        $outputFiles = @{}
        
        try {
            foreach ($format in $Formats) {
                $this.WriteLog("Generating $format format output", "Information")
                
                # Generate original output
                $originalFile = $this.GenerateOriginalOutput($format, $VMData, $OutputPath)
                $outputFiles[$format] = $originalFile
                
                # Generate anonymized version if anonymization is enabled
                if ($this.AnonymizationProcessor.IsEnabled) {
                    $this.WriteLog("Generating anonymized version of $format format", "Information")
                    $this.GenerateAnonymizedOutput($format, $VMData, $OutputPath, $originalFile)
                }
            }
            
            return $outputFiles
        }
        catch {
            $this.WriteLog("Error generating outputs: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Generate original output file
    [string] GenerateOriginalOutput([string] $Format, [array] $VMData, [string] $OutputPath) {
        switch ($Format.ToUpper()) {
            "ME" {
                if ($null -eq $this.OutputGenerators.ME) {
                    $this.OutputGenerators.ME = [MEFormatGenerator]::new($this.Logger)
                }
                $this.OutputGenerators.ME.GenerateOutput($VMData, $OutputPath)
                return $this.FindGeneratedFile($OutputPath, "ME")
            }
            "MPA" {
                if ($null -eq $this.OutputGenerators.MPA) {
                    $this.OutputGenerators.MPA = [MPAFormatGenerator]::new($this.Logger)
                }
                $this.OutputGenerators.MPA.GenerateOutput($VMData, $OutputPath)
                return $this.FindGeneratedFile($OutputPath, "MAP")
            }
            "RVTOOLS" {
                if ($null -eq $this.OutputGenerators.RVTools) {
                    $this.OutputGenerators.RVTools = [RVToolsFormatGenerator]::new($this.Logger)
                }
                $this.OutputGenerators.RVTools.GenerateOutput($VMData, $OutputPath)
                return $this.FindGeneratedFile($OutputPath, "RVTools")
            }
            default {
                throw "Unsupported output format: $Format"
            }
        }
        
        # Fallback return (should never reach here due to switch default throwing)
        return $null
    }
    
    # Generate anonymized output file
    [void] GenerateAnonymizedOutput([string] $Format, [array] $VMData, [string] $OutputPath, [string] $OriginalFile) {
        switch ($Format.ToUpper()) {
            "ME" {
                $this.AnonymizationProcessor.ProcessMEOutput($OriginalFile, $VMData)
            }
            "MAP" {
                $this.AnonymizationProcessor.ProcessMAPOutput($OriginalFile, $VMData)
            }
            "RVTOOLS" {
                $this.AnonymizationProcessor.ProcessRVToolsOutput($OriginalFile, $VMData)
            }
            default {
                throw "Unsupported output format for anonymization: $Format"
            }
        }
    }
    
    # Find generated file by format
    [string] FindGeneratedFile([string] $OutputPath, [string] $Format) {
        switch ($Format.ToUpper()) {
            "ME" {
                $files = Get-ChildItem -Path $OutputPath -Filter "VMWARE_Inventory_And_Usage_Workbook_*.xlsx" | 
                         Sort-Object LastWriteTime -Descending | Select-Object -First 1
            }
            "MAP" {
                $files = Get-ChildItem -Path $OutputPath -Filter "MPA_Template_*.csv" | 
                         Sort-Object LastWriteTime -Descending | Select-Object -First 1
            }
            "RVTOOLS" {
                $files = Get-ChildItem -Path $OutputPath -Filter "RVTools_Export_*.zip" | 
                         Sort-Object LastWriteTime -Descending | Select-Object -First 1
            }
            default {
                return $null
            }
        }
        
        if ($files) {
            return $files.FullName
        }
        return $null
    }
    
    # Helper method for logging
    [void] WriteLog([string] $Message, [string] $Level) {
        if ($null -ne $this.Logger) {
            switch ($Level) {
                "Error" { $this.Logger.WriteError($Message, $null) }
                "Warning" { $this.Logger.WriteWarning($Message) }
                "Information" { $this.Logger.WriteInformation($Message) }
                "Debug" { $this.Logger.WriteDebug($Message) }
                "Verbose" { $this.Logger.WriteVerbose($Message) }
                default { $this.Logger.WriteInformation($Message) }
            }
        }
        else {
            Write-Host "[$Level] $Message"
        }
    }
}