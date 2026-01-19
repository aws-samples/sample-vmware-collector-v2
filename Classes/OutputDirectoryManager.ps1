#
# OutputDirectoryManager.ps1 - Output Directory Structure Manager
#
# Manages the creation and organization of output directories with timestamps,
# format-specific subdirectories, and master ZIP archive functionality.
#

using module .\Interfaces.ps1

class OutputDirectoryManager : IFileManager {
    [string] $BasePath
    [string] $Timestamp
    [string] $MainOutputDirectory
    [hashtable] $DirectoryStructure
    [ILogger] $Logger
    
    # Constructor
    OutputDirectoryManager([string] $BasePath, [ILogger] $Logger) {
        $this.BasePath = $BasePath
        $this.Logger = $Logger
        $this.Timestamp = $this.GenerateTimestamp()
        $this.DirectoryStructure = @{}
        $this.InitializeDirectoryStructure()
    }
    
    # Generate consistent timestamp format (YYYYMMDD_HHMMSS)
    [string] GenerateTimestamp() {
        return (Get-Date).ToString("yyyyMMdd_HHmmss")
    }
    
    # Initialize the directory structure configuration
    [void] InitializeDirectoryStructure() {
        $this.DirectoryStructure = @{
            MainDirectory = "VMware_Collection_$($this.Timestamp)"
            Subdirectories = @{
                ME = "ME_Format"
                MAP = "MAP_Format" 
                RVTools = "RVTools_Format"
                Logs = "Logs"
                Reports = "Reports"
                Anonymization = "Anonymization_Mappings"
                Archives = "Archives"
            }
        }
    }
    
    # Create the complete output directory structure with timestamps
    [void] CreateOutputDirectory([string] $BasePath, [string] $Timestamp) {
        try {
            # Use provided timestamp or generate new one
            if (-not [string]::IsNullOrEmpty($Timestamp)) {
                $this.Timestamp = $Timestamp
                $this.InitializeDirectoryStructure()
            }
            
            # Set base path
            if (-not [string]::IsNullOrEmpty($BasePath)) {
                $this.BasePath = $BasePath
            }
            
            # Create main output directory
            $this.MainOutputDirectory = Join-Path $this.BasePath $this.DirectoryStructure.MainDirectory
            
            if (-not (Test-Path $this.MainOutputDirectory)) {
                New-Item -Path $this.MainOutputDirectory -ItemType Directory -Force | Out-Null
                $this.Logger.WriteInformation("Created main output directory: $($this.MainOutputDirectory)")
            }
            
            # Create format-specific subdirectories
            foreach ($subdir in $this.DirectoryStructure.Subdirectories.GetEnumerator()) {
                $subdirPath = Join-Path $this.MainOutputDirectory $subdir.Value
                if (-not (Test-Path $subdirPath)) {
                    New-Item -Path $subdirPath -ItemType Directory -Force | Out-Null
                    $this.Logger.WriteInformation("Created subdirectory: $($subdir.Key) at $subdirPath")
                }
            }
            
            $this.Logger.WriteInformation("Output directory structure created successfully")
            
        } catch {
            $this.Logger.WriteError("Failed to create output directory structure", $_.Exception)
            throw
        }
    }
    
    # Get the path for a specific format subdirectory
    [string] GetFormatDirectory([string] $Format) {
        $formatKey = $Format.ToUpper()
        if ($this.DirectoryStructure.Subdirectories.ContainsKey($formatKey)) {
            return Join-Path $this.MainOutputDirectory $this.DirectoryStructure.Subdirectories[$formatKey]
        } else {
            throw "Unknown format: $Format. Supported formats: ME, MAP, RVTools"
        }
    }
    
    # Get the logs directory path
    [string] GetLogsDirectory() {
        return Join-Path $this.MainOutputDirectory $this.DirectoryStructure.Subdirectories.Logs
    }
    
    # Get the reports directory path
    [string] GetReportsDirectory() {
        return Join-Path $this.MainOutputDirectory $this.DirectoryStructure.Subdirectories.Reports
    }
    
    # Get the anonymization mappings directory path
    [string] GetAnonymizationDirectory() {
        return Join-Path $this.MainOutputDirectory $this.DirectoryStructure.Subdirectories.Anonymization
    }
    
    # Get the archives directory path
    [string] GetArchivesDirectory() {
        return Join-Path $this.MainOutputDirectory $this.DirectoryStructure.Subdirectories.Archives
    }
    
    # Organize output files into appropriate directories
    [void] OrganizeOutputFiles([hashtable] $Files, [string] $OutputPath) {
        try {
            foreach ($file in $Files.GetEnumerator()) {
                $fileName = $file.Key
                $fileInfo = $file.Value
                
                # Determine target directory based on file type/format
                $targetDirectory = $this.DetermineTargetDirectory($fileName, $fileInfo)
                $targetPath = Join-Path $targetDirectory $fileName
                
                # Move or copy file to target directory
                if ($fileInfo.ContainsKey('SourcePath') -and (Test-Path $fileInfo.SourcePath)) {
                    if ($fileInfo.ContainsKey('Move') -and $fileInfo.Move) {
                        Move-Item -Path $fileInfo.SourcePath -Destination $targetPath -Force
                        $this.Logger.WriteInformation("Moved file: $fileName to $targetDirectory")
                    } else {
                        Copy-Item -Path $fileInfo.SourcePath -Destination $targetPath -Force
                        $this.Logger.WriteInformation("Copied file: $fileName to $targetDirectory")
                    }
                }
            }
            
        } catch {
            $this.Logger.WriteError("Failed to organize output files", $_.Exception)
            throw
        }
    }
    
    # Determine the target directory for a file based on its name and properties
    [string] DetermineTargetDirectory([string] $FileName, [hashtable] $FileInfo) {
        # Check if file type is explicitly specified
        if ($FileInfo.ContainsKey('Format')) {
            return $this.GetFormatDirectory($FileInfo.Format)
        }
        
        # Determine format based on filename patterns
        if ($FileName -match "VMWARE_Inventory_And_Usage_Workbook.*\.xlsx$") {
            return $this.GetFormatDirectory("ME")
        } elseif ($FileName -match "MPA_Template.*\.csv$") {
            return $this.GetFormatDirectory("MAP")
        } elseif ($FileName -match "RVTools_Export.*\.zip$") {
            return $this.GetFormatDirectory("RVTools")
        } elseif ($FileName -match ".*\.log$") {
            return $this.GetLogsDirectory()
        } elseif ($FileName -match "Collection_Summary.*\.txt$" -or $FileName -match ".*_Report.*\.(txt|html|csv)$") {
            return $this.GetReportsDirectory()
        } elseif ($FileName -match "Anonymization_Mapping.*\.xlsx$") {
            return $this.GetAnonymizationDirectory()
        } elseif ($FileName -match ".*\.zip$") {
            return $this.GetArchivesDirectory()
        } else {
            # Default to main output directory
            return $this.MainOutputDirectory
        }
    }
    
    # Create master ZIP archive containing all output files
    [void] CreateArchive([string] $SourcePath, [string] $ArchivePath) {
        try {
            # If no specific archive path provided, create in archives directory
            if ([string]::IsNullOrEmpty($ArchivePath)) {
                $archivesDir = $this.GetArchivesDirectory()
                $archiveName = "VMware_Collection_Master_Archive_$($this.Timestamp).zip"
                $ArchivePath = Join-Path $archivesDir $archiveName
            }
            
            # Use provided source path or default to main output directory
            if ([string]::IsNullOrEmpty($SourcePath)) {
                $SourcePath = $this.MainOutputDirectory
            }
            
            # Create ZIP archive using .NET compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            
            # Remove existing archive if it exists
            if (Test-Path $ArchivePath) {
                Remove-Item $ArchivePath -Force
                $this.Logger.WriteInformation("Removed existing archive: $ArchivePath")
            }
            
            # Create the archive
            [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $ArchivePath)
            
            $archiveSize = (Get-Item $ArchivePath).Length
            $this.Logger.WriteInformation("Created master archive: $ArchivePath (Size: $([math]::Round($archiveSize / 1MB, 2)) MB)")
            
        } catch {
            $this.Logger.WriteError("Failed to create master archive", $_.Exception)
            throw
        }
    }
    
    # Get the complete file organization structure
    [hashtable] GetFileOrganizationStructure() {
        return @{
            BasePath = $this.BasePath
            Timestamp = $this.Timestamp
            MainDirectory = $this.MainOutputDirectory
            DirectoryStructure = $this.DirectoryStructure
            CreatedDirectories = $this.GetCreatedDirectories()
        }
    }
    
    # Get list of actually created directories
    [array] GetCreatedDirectories() {
        $createdDirs = @()
        
        if (Test-Path $this.MainOutputDirectory) {
            $createdDirs += $this.MainOutputDirectory
            
            foreach ($subdir in $this.DirectoryStructure.Subdirectories.Values) {
                $subdirPath = Join-Path $this.MainOutputDirectory $subdir
                if (Test-Path $subdirPath) {
                    $createdDirs += $subdirPath
                }
            }
        }
        
        return $createdDirs
    }
    
    # Clean up temporary files and directories
    [void] CleanupTemporaryFiles([array] $TempFiles) {
        try {
            foreach ($tempFile in $TempFiles) {
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force -Recurse
                    $this.Logger.WriteInformation("Cleaned up temporary file: $tempFile")
                }
            }
        } catch {
            $this.Logger.WriteWarning("Failed to clean up some temporary files: $($_.Exception.Message)")
        }
    }
    
    # Validate directory structure integrity
    [bool] ValidateDirectoryStructure() {
        try {
            # Check if main directory exists
            if (-not (Test-Path $this.MainOutputDirectory)) {
                $this.Logger.WriteError("Main output directory does not exist: $($this.MainOutputDirectory)", $null)
                return $false
            }
            
            # Check if all required subdirectories exist
            $missingDirs = @()
            foreach ($subdir in $this.DirectoryStructure.Subdirectories.GetEnumerator()) {
                $subdirPath = Join-Path $this.MainOutputDirectory $subdir.Value
                if (-not (Test-Path $subdirPath)) {
                    $missingDirs += $subdir.Key
                }
            }
            
            if ($missingDirs.Count -gt 0) {
                $this.Logger.WriteWarning("Missing subdirectories: $($missingDirs -join ', ')")
                return $false
            }
            
            $this.Logger.WriteInformation("Directory structure validation passed")
            return $true
            
        } catch {
            $this.Logger.WriteError("Directory structure validation failed", $_.Exception)
            return $false
        }
    }
    
    # Get directory usage statistics
    [hashtable] GetDirectoryStatistics() {
        $stats = @{
            MainDirectory = $this.MainOutputDirectory
            TotalSize = 0
            FileCount = 0
            DirectoryCount = 0
            SubdirectoryStats = @{}
        }
        
        try {
            if (Test-Path $this.MainOutputDirectory) {
                $items = Get-ChildItem -Path $this.MainOutputDirectory -Recurse
                $stats.FileCount = ($items | Where-Object { -not $_.PSIsContainer }).Count
                $stats.DirectoryCount = ($items | Where-Object { $_.PSIsContainer }).Count
                $stats.TotalSize = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
                
                # Get statistics for each subdirectory
                foreach ($subdir in $this.DirectoryStructure.Subdirectories.GetEnumerator()) {
                    $subdirPath = Join-Path $this.MainOutputDirectory $subdir.Value
                    if (Test-Path $subdirPath) {
                        $subdirItems = Get-ChildItem -Path $subdirPath -Recurse
                        $stats.SubdirectoryStats[$subdir.Key] = @{
                            Path = $subdirPath
                            FileCount = ($subdirItems | Where-Object { -not $_.PSIsContainer }).Count
                            Size = ($subdirItems | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
                        }
                    }
                }
            }
        } catch {
            $this.Logger.WriteWarning("Failed to calculate directory statistics: $($_.Exception.Message)")
        }
        
        return $stats
    }
}