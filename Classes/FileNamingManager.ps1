#
# FileNamingManager.ps1 - File Naming and Versioning Manager
#
# Manages consistent file naming with timestamps, file conflict resolution,
# versioning, and log file management with rotation.
#

using module .\Interfaces.ps1

class FileNamingManager {
    [string] $Timestamp
    [hashtable] $NamingPatterns
    [hashtable] $FileVersions
    [ILogger] $Logger
    [int] $MaxLogFiles
    [long] $MaxLogSizeBytes
    
    # Constructor
    FileNamingManager([ILogger] $Logger) {
        $this.Logger = $Logger
        $this.Timestamp = $this.GenerateTimestamp()
        $this.FileVersions = @{}
        $this.MaxLogFiles = 10
        $this.MaxLogSizeBytes = 50MB
        $this.InitializeNamingPatterns()
    }
    
    # Generate consistent timestamp format (YYYYMMDD_HHMMSS)
    [string] GenerateTimestamp() {
        return (Get-Date).ToString("yyyyMMdd_HHmmss")
    }
    
    # Initialize file naming patterns for different output formats
    [void] InitializeNamingPatterns() {
        $this.NamingPatterns = @{
            ME = @{
                Pattern = "VMWARE_Inventory_And_Usage_Workbook_{0}.xlsx"
                Description = "Migration Evaluator Excel workbook"
                AnonymizedSuffix = "_ANONYMIZED_"
            }
            MAP = @{
                Pattern = "MPA_Template_{0}.csv"
                Description = "Migration Portfolio Assessment CSV file"
                AnonymizedSuffix = "_ANONYMIZED_"
            }
            RVTools = @{
                Pattern = "RVTools_Export_{0}.zip"
                Description = "RVTools compatible ZIP archive"
                AnonymizedSuffix = "_ANONYMIZED_"
            }
            Log = @{
                Pattern = "VMware_Collector_Log_{0}.log"
                Description = "Application log file"
                AnonymizedSuffix = ""
            }
            Summary = @{
                Pattern = "Collection_Summary_{0}.txt"
                Description = "Collection summary report"
                AnonymizedSuffix = ""
            }
            AnonymizationMapping = @{
                Pattern = "Anonymization_Mapping_{0}.xlsx"
                Description = "Anonymization mapping file"
                AnonymizedSuffix = ""
            }
            ValidationReport = @{
                Pattern = "Validation_Report_{0}.html"
                Description = "Data validation report"
                AnonymizedSuffix = ""
            }
            PerformanceReport = @{
                Pattern = "Performance_Report_{0}.txt"
                Description = "Collection performance metrics"
                AnonymizedSuffix = ""
            }
            NotFoundVMs = @{
                Pattern = "Not_Found_VMs_Report_{0}.csv"
                Description = "VMs not found during processing"
                AnonymizedSuffix = ""
            }
            MasterArchive = @{
                Pattern = "VMware_Collection_Master_Archive_{0}.zip"
                Description = "Master archive containing all outputs"
                AnonymizedSuffix = "_ANONYMIZED_"
            }
        }
    }
    
    # Generate filename for a specific format with timestamp
    [string] GenerateFileName([string] $Format, [bool] $Anonymized = $false, [string] $CustomTimestamp = "") {
        try {
            # Use custom timestamp if provided, otherwise use instance timestamp
            $timestampToUse = if ([string]::IsNullOrEmpty($CustomTimestamp)) { $this.Timestamp } else { $CustomTimestamp }
            
            # Validate format
            if (-not $this.NamingPatterns.ContainsKey($Format)) {
                throw "Unknown file format: $Format. Supported formats: $($this.NamingPatterns.Keys -join ', ')"
            }
            
            $pattern = $this.NamingPatterns[$Format]
            $baseFileName = $pattern.Pattern -f $timestampToUse
            
            # Add anonymized suffix if requested
            if ($Anonymized -and -not [string]::IsNullOrEmpty($pattern.AnonymizedSuffix)) {
                $extension = [System.IO.Path]::GetExtension($baseFileName)
                $nameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($baseFileName)
                $baseFileName = "$nameWithoutExtension$($pattern.AnonymizedSuffix)$extension"
            }
            
            $this.Logger.WriteDebug("Generated filename for $Format`: $baseFileName")
            return $baseFileName
            
        } catch {
            $this.Logger.WriteError("Failed to generate filename for format: $Format", $_.Exception)
            throw
        }
    }
    
    # Resolve file conflicts by adding version numbers
    [string] ResolveFileConflict([string] $FilePath) {
        try {
            if (-not (Test-Path $FilePath)) {
                return $FilePath
            }
            
            $directory = [System.IO.Path]::GetDirectoryName($FilePath)
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
            $extension = [System.IO.Path]::GetExtension($FilePath)
            
            # Track version for this base filename
            $baseKey = "$directory\$fileName"
            if (-not $this.FileVersions.ContainsKey($baseKey)) {
                $this.FileVersions[$baseKey] = 1
            }
            
            # Find next available version
            $version = $this.FileVersions[$baseKey]
            $versionedFilePath = ""
            do {
                $versionedFileName = "$fileName`_v$version$extension"
                $versionedFilePath = Join-Path $directory $versionedFileName
                $version++
            } while (Test-Path $versionedFilePath)
            
            # Update version tracking
            $this.FileVersions[$baseKey] = $version - 1
            
            $this.Logger.WriteInformation("Resolved file conflict: $FilePath -> $versionedFilePath")
            return $versionedFilePath
            
        } catch {
            $this.Logger.WriteError("Failed to resolve file conflict for: $FilePath", $_.Exception)
            throw
        }
    }
    
    # Create versioned backup of existing file
    [string] CreateVersionedBackup([string] $FilePath) {
        try {
            if (-not (Test-Path $FilePath)) {
                $this.Logger.WriteWarning("Cannot create backup - file does not exist: $FilePath")
                return ""
            }
            
            $directory = [System.IO.Path]::GetDirectoryName($FilePath)
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
            $extension = [System.IO.Path]::GetExtension($FilePath)
            $timestampForBackup = $this.GenerateTimestamp()
            
            $backupFileName = "$fileName`_backup_$timestampForBackup$extension"
            $backupFilePath = Join-Path $directory $backupFileName
            
            Copy-Item -Path $FilePath -Destination $backupFilePath -Force
            $this.Logger.WriteInformation("Created backup: $backupFilePath")
            
            return $backupFilePath
            
        } catch {
            $this.Logger.WriteError("Failed to create versioned backup for: $FilePath", $_.Exception)
            throw
        }
    }
    
    # Manage log file rotation
    [void] RotateLogFiles([string] $LogDirectory) {
        try {
            if (-not (Test-Path $LogDirectory)) {
                $this.Logger.WriteWarning("Log directory does not exist: $LogDirectory")
                return
            }
            
            # Get all log files sorted by creation time (oldest first)
            $logFiles = Get-ChildItem -Path $LogDirectory -Filter "*.log" | Sort-Object CreationTime
            
            # Remove excess log files if we exceed the maximum count
            if ($logFiles.Count -gt $this.MaxLogFiles) {
                $filesToRemove = $logFiles | Select-Object -First ($logFiles.Count - $this.MaxLogFiles)
                foreach ($file in $filesToRemove) {
                    Remove-Item $file.FullName -Force
                    $this.Logger.WriteInformation("Removed old log file: $($file.Name)")
                }
            }
            
            # Check for oversized log files and rotate them
            foreach ($logFile in $logFiles) {
                if ($logFile.Length -gt $this.MaxLogSizeBytes) {
                    $this.RotateOversizedLogFile($logFile.FullName)
                }
            }
            
        } catch {
            $this.Logger.WriteError("Failed to rotate log files in directory: $LogDirectory", $_.Exception)
        }
    }
    
    # Rotate a single oversized log file
    [void] RotateOversizedLogFile([string] $LogFilePath) {
        try {
            $directory = [System.IO.Path]::GetDirectoryName($LogFilePath)
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($LogFilePath)
            $extension = [System.IO.Path]::GetExtension($LogFilePath)
            $timestampForRotation = $this.GenerateTimestamp()
            
            $rotatedFileName = "$fileName`_rotated_$timestampForRotation$extension"
            $rotatedFilePath = Join-Path $directory $rotatedFileName
            
            # Move the current log file to rotated name
            Move-Item -Path $LogFilePath -Destination $rotatedFilePath -Force
            
            # Create new empty log file
            New-Item -Path $LogFilePath -ItemType File -Force | Out-Null
            
            $this.Logger.WriteInformation("Rotated oversized log file: $LogFilePath -> $rotatedFilePath")
            
        } catch {
            $this.Logger.WriteError("Failed to rotate oversized log file: $LogFilePath", $_.Exception)
        }
    }
    
    # Get safe filename by removing invalid characters
    [string] GetSafeFileName([string] $FileName) {
        try {
            # Remove invalid filename characters
            $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
            $safeFileName = $FileName
            
            foreach ($char in $invalidChars) {
                $safeFileName = $safeFileName.Replace($char, '_')
            }
            
            # Remove multiple consecutive underscores
            $safeFileName = $safeFileName -replace '_+', '_'
            
            # Trim underscores from start and end
            $safeFileName = $safeFileName.Trim('_')
            
            # Ensure filename is not empty
            if ([string]::IsNullOrEmpty($safeFileName)) {
                $safeFileName = "unnamed_file"
            }
            
            return $safeFileName
            
        } catch {
            $this.Logger.WriteError("Failed to create safe filename from: $FileName", $_.Exception)
            return "safe_filename"
        }
    }
    
    # Validate filename against naming conventions
    [bool] ValidateFileName([string] $FileName, [string] $Format) {
        try {
            if ([string]::IsNullOrEmpty($FileName)) {
                return $false
            }
            
            # Check if format is supported
            if (-not $this.NamingPatterns.ContainsKey($Format)) {
                return $false
            }
            
            $pattern = $this.NamingPatterns[$Format]
            
            # Create regex pattern from naming pattern
            $regexPattern = $pattern.Pattern -replace '\{0\}', '\d{8}_\d{6}'
            $regexPattern = [regex]::Escape($regexPattern) -replace '\\d\\\{8\\\}_\\d\\\{6\\\}', '\d{8}_\d{6}'
            
            # Check if filename matches the expected pattern
            $matches = $FileName -match $regexPattern
            
            if (-not $matches) {
                $this.Logger.WriteWarning("Filename does not match expected pattern for $Format`: $FileName")
            }
            
            return $matches
            
        } catch {
            $this.Logger.WriteError("Failed to validate filename: $FileName for format: $Format", $_.Exception)
            return $false
        }
    }
    
    # Get all supported file formats
    [array] GetSupportedFormats() {
        return $this.NamingPatterns.Keys
    }
    
    # Get naming pattern information for a format
    [hashtable] GetNamingPatternInfo([string] $Format) {
        if ($this.NamingPatterns.ContainsKey($Format)) {
            return $this.NamingPatterns[$Format].Clone()
        } else {
            return @{}
        }
    }
    
    # Set custom timestamp for filename generation
    [void] SetTimestamp([string] $CustomTimestamp) {
        if ($CustomTimestamp -match '^\d{8}_\d{6}$') {
            $this.Timestamp = $CustomTimestamp
            $this.Logger.WriteInformation("Set custom timestamp: $CustomTimestamp")
        } else {
            throw "Invalid timestamp format. Expected: YYYYMMDD_HHMMSS"
        }
    }
    
    # Configure log rotation settings
    [void] ConfigureLogRotation([int] $MaxFiles, [long] $MaxSizeBytes) {
        if ($MaxFiles -gt 0) {
            $this.MaxLogFiles = $MaxFiles
        }
        if ($MaxSizeBytes -gt 0) {
            $this.MaxLogSizeBytes = $MaxSizeBytes
        }
        
        $this.Logger.WriteInformation("Configured log rotation: MaxFiles=$($this.MaxLogFiles), MaxSize=$([math]::Round($this.MaxLogSizeBytes / 1MB, 2))MB")
    }
    
    # Get file versioning statistics
    [hashtable] GetVersioningStatistics() {
        return @{
            TrackedFiles = $this.FileVersions.Count
            TotalVersions = ($this.FileVersions.Values | Measure-Object -Sum).Sum
            FileVersions = $this.FileVersions.Clone()
            Timestamp = $this.Timestamp
            MaxLogFiles = $this.MaxLogFiles
            MaxLogSizeBytes = $this.MaxLogSizeBytes
        }
    }
    
    # Clean up old versioned files
    [void] CleanupOldVersions([string] $Directory, [int] $KeepVersions = 5) {
        try {
            if (-not (Test-Path $Directory)) {
                return
            }
            
            # Group files by base name (without version suffix)
            $files = Get-ChildItem -Path $Directory -File
            $fileGroups = @{}
            
            foreach ($file in $files) {
                $baseName = $file.Name -replace '_v\d+\.', '.'
                if (-not $fileGroups.ContainsKey($baseName)) {
                    $fileGroups[$baseName] = @()
                }
                $fileGroups[$baseName] += $file
            }
            
            # Clean up excess versions for each file group
            foreach ($group in $fileGroups.GetEnumerator()) {
                $sortedFiles = $group.Value | Sort-Object CreationTime -Descending
                if ($sortedFiles.Count -gt $KeepVersions) {
                    $filesToRemove = $sortedFiles | Select-Object -Skip $KeepVersions
                    foreach ($file in $filesToRemove) {
                        Remove-Item $file.FullName -Force
                        $this.Logger.WriteInformation("Cleaned up old version: $($file.Name)")
                    }
                }
            }
            
        } catch {
            $this.Logger.WriteError("Failed to cleanup old versions in directory: $Directory", $_.Exception)
        }
    }
}