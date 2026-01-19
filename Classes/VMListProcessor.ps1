#
# VMListProcessor.ps1 - Advanced VM list processing with fuzzy matching
#
# Implements CSV and TXT file format detection, fuzzy matching for VM name variations,
# and comprehensive unmatched VM reporting and processing summary.
#

# Import required interfaces
if (Test-Path "$PSScriptRoot\Interfaces.ps1") {
    . "$PSScriptRoot\Interfaces.ps1"
}

class VMListProcessor {
    [ILogger] $Logger
    [hashtable] $ProcessingStatistics
    [hashtable] $FuzzyMatchingConfig
    [array] $SupportedFormats = @('.csv', '.txt', '.tsv')
    
    # Constructor
    VMListProcessor([ILogger] $logger) {
        $this.Logger = $logger
        $this.ProcessingStatistics = @{
            TotalVMsInFile = 0
            SuccessfullyMatched = 0
            NotFound = 0
            DuplicatesFound = 0
            InvalidEntries = 0
            ProcessingTimeSeconds = 0
            FileFormat = ""
            ColumnUsed = ""
            SuccessRate = 0.0
        }
        
        $this.FuzzyMatchingConfig = @{
            EnableExactMatch = $true
            EnableCaseInsensitiveMatch = $true
            EnablePartialMatch = $true
            EnableCleanedMatch = $true
            EnableLevenshteinMatch = $true
            LevenshteinThreshold = 2
            MinimumMatchConfidence = 0.7
            MaxPartialMatches = 5
        }
    }
    
    # Main method to process VM list file
    [hashtable] ProcessVMListFile([string] $filePath, [array] $allVMs) {
        $startTime = Get-Date
        
        try {
            $this.Logger.WriteInformation("Starting VM list processing for file: $filePath")
            
            # Validate file exists and format
            $this.ValidateInputFile($filePath)
            
            # Detect file format and read VM names
            $vmNames = $this.ReadVMNamesFromFile($filePath)
            $this.ProcessingStatistics.TotalVMsInFile = $vmNames.Count
            
            # Perform fuzzy matching
            $matchingResults = $this.PerformFuzzyMatching($vmNames, $allVMs)
            
            # Generate reports
            $this.GenerateProcessingReports($filePath, $matchingResults)
            
            # Calculate final statistics
            $endTime = Get-Date
            $this.ProcessingStatistics.ProcessingTimeSeconds = ($endTime - $startTime).TotalSeconds
            $this.ProcessingStatistics.SuccessRate = if ($this.ProcessingStatistics.TotalVMsInFile -gt 0) {
                [Math]::Round(($this.ProcessingStatistics.SuccessfullyMatched / $this.ProcessingStatistics.TotalVMsInFile) * 100, 2)
            } else { 0.0 }
            
            $this.Logger.WriteInformation("VM list processing completed. Success rate: $($this.ProcessingStatistics.SuccessRate)%")
            
            return @{
                MatchedVMs = $matchingResults.MatchedVMs
                UnmatchedNames = $matchingResults.UnmatchedNames
                ProcessingStatistics = $this.ProcessingStatistics
                MatchingDetails = $matchingResults.MatchingDetails
            }
            
        } catch {
            $this.Logger.WriteError("Failed to process VM list file: $filePath", $_.Exception)
            throw
        }
    }
    
    # Validate input file
    [void] ValidateInputFile([string] $filePath) {
        if (-not (Test-Path $filePath)) {
            throw "VM list file not found: $filePath"
        }
        
        $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
        if ($extension -notin $this.SupportedFormats) {
            $this.Logger.WriteWarning("Unsupported file format: $extension. Supported formats: $($this.SupportedFormats -join ', ')")
        }
        
        $fileInfo = Get-Item $filePath
        if ($fileInfo.Length -eq 0) {
            throw "VM list file is empty: $filePath"
        }
        
        $this.Logger.WriteInformation("File validation passed: $filePath ($($fileInfo.Length) bytes)")
    }
    
    # Read VM names from file with format detection
    [array] ReadVMNamesFromFile([string] $filePath) {
        $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
        $vmNames = @()
        
        try {
            switch ($extension) {
                '.csv' { $vmNames = $this.ReadCSVFile($filePath) }
                '.tsv' { $vmNames = $this.ReadTSVFile($filePath) }
                default { $vmNames = $this.ReadTextFile($filePath) }
            }
            
            # Remove duplicates and sanitize
            $originalCount = $vmNames.Count
            $vmNames = $vmNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | 
                       ForEach-Object { $this.SanitizeVMName($_) } | 
                       Sort-Object -Unique
            
            $duplicatesRemoved = $originalCount - $vmNames.Count
            if ($duplicatesRemoved -gt 0) {
                $this.ProcessingStatistics.DuplicatesFound = $duplicatesRemoved
                $this.Logger.WriteInformation("Removed $duplicatesRemoved duplicate entries")
            }
            
            $this.Logger.WriteInformation("Successfully read $($vmNames.Count) unique VM names from file")
            return $vmNames
            
        } catch {
            $this.Logger.WriteError("Failed to read VM names from file: $filePath", $_.Exception)
            throw
        }
    }
    
    # Read CSV file with column detection
    [array] ReadCSVFile([string] $filePath) {
        $this.ProcessingStatistics.FileFormat = "CSV"
        
        try {
            # Try to import as CSV
            $csvData = Import-Csv $filePath -ErrorAction Stop
            
            if ($csvData.Count -eq 0) {
                throw "CSV file contains no data rows"
            }
            
            # Get column headers
            $headers = $csvData[0].PSObject.Properties.Name
            $this.Logger.WriteInformation("CSV headers detected: $($headers -join ', ')")
            
            # Find VM name column using priority order
            $vmColumnName = $this.DetectVMNameColumn($headers)
            $this.ProcessingStatistics.ColumnUsed = $vmColumnName
            
            # Extract VM names from the detected column
            $vmNames = $csvData | ForEach-Object { 
                $value = $_.$vmColumnName
                if ($value -and $value.ToString().Trim()) {
                    $value.ToString().Trim()
                }
            } | Where-Object { $_ }
            
            $this.Logger.WriteInformation("Using column '$vmColumnName' for VM names, extracted $($vmNames.Count) entries")
            return $vmNames
            
        } catch {
            $this.Logger.WriteWarning("Failed to parse as CSV, falling back to text format: $($_.Exception.Message)")
            return $this.ReadTextFile($filePath)
        }
    }
    
    # Read TSV file
    [array] ReadTSVFile([string] $filePath) {
        $this.ProcessingStatistics.FileFormat = "TSV"
        
        try {
            $csvData = Import-Csv $filePath -Delimiter "`t" -ErrorAction Stop
            
            if ($csvData.Count -eq 0) {
                throw "TSV file contains no data rows"
            }
            
            $headers = $csvData[0].PSObject.Properties.Name
            $vmColumnName = $this.DetectVMNameColumn($headers)
            $this.ProcessingStatistics.ColumnUsed = $vmColumnName
            
            $vmNames = $csvData | ForEach-Object { 
                $value = $_.$vmColumnName
                if ($value -and $value.ToString().Trim()) {
                    $value.ToString().Trim()
                }
            } | Where-Object { $_ }
            
            $this.Logger.WriteInformation("TSV format detected, using column '$vmColumnName', extracted $($vmNames.Count) entries")
            return $vmNames
            
        } catch {
            $this.Logger.WriteWarning("Failed to parse as TSV, falling back to text format: $($_.Exception.Message)")
            return $this.ReadTextFile($filePath)
        }
    }
    
    # Read text file (one VM name per line)
    [array] ReadTextFile([string] $filePath) {
        $this.ProcessingStatistics.FileFormat = "Text"
        $this.ProcessingStatistics.ColumnUsed = "Line-by-line"
        
        try {
            $vmNames = Get-Content $filePath -ErrorAction Stop | 
                       Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | 
                       ForEach-Object { $_.Trim() }
            
            $this.Logger.WriteInformation("Text format detected, read $($vmNames.Count) lines")
            return $vmNames
            
        } catch {
            $this.Logger.WriteError("Failed to read text file: $filePath", $_.Exception)
            throw
        }
    }
    
    # Detect VM name column from headers
    [string] DetectVMNameColumn([array] $headers) {
        # Priority order for VM name columns
        $priorityColumns = @(
            'VM Name', 'VMName', 'VM_Name',
            'Server Name', 'ServerName', 'Server_Name',
            'Virtual Machine', 'VirtualMachine', 'Virtual_Machine',
            'Machine Name', 'MachineName', 'Machine_Name',
            'Name', 'VM', 'Server', 'Host', 'Hostname',
            'Computer', 'ComputerName', 'Computer_Name'
        )
        
        # Try exact matches first
        foreach ($priority in $priorityColumns) {
            $match = $headers | Where-Object { $_ -eq $priority }
            if ($match) {
                $this.Logger.WriteInformation("Found exact column match: $match")
                return $match
            }
        }
        
        # Try case-insensitive matches
        foreach ($priority in $priorityColumns) {
            $match = $headers | Where-Object { $_ -ieq $priority }
            if ($match) {
                $this.Logger.WriteInformation("Found case-insensitive column match: $match")
                return $match
            }
        }
        
        # Try partial matches
        foreach ($priority in $priorityColumns) {
            $match = $headers | Where-Object { $_ -like "*$priority*" -or $priority -like "*$_*" }
            if ($match) {
                $this.Logger.WriteInformation("Found partial column match: $match (matched against $priority)")
                return $match
            }
        }
        
        # Default to first column
        $firstColumn = $headers[0]
        $this.Logger.WriteWarning("No standard VM name column found, using first column: $firstColumn")
        return $firstColumn
    }
    
    # Perform fuzzy matching with multiple algorithms
    [hashtable] PerformFuzzyMatching([array] $vmNames, [array] $allVMs) {
        $matchedVMs = @()
        $unmatchedNames = @()
        $matchingDetails = @()
        
        $this.Logger.WriteInformation("Starting fuzzy matching for $($vmNames.Count) VM names against $($allVMs.Count) vCenter VMs")
        
        foreach ($vmName in $vmNames) {
            $matchResult = $this.FindBestVMMatch($vmName, $allVMs)
            
            if ($matchResult.VM) {
                $matchedVMs += $matchResult.VM
                $this.ProcessingStatistics.SuccessfullyMatched++
                
                $matchingDetails += [PSCustomObject]@{
                    InputName = $vmName
                    MatchedName = $matchResult.VM.Name
                    MatchType = $matchResult.MatchType
                    Confidence = $matchResult.Confidence
                    Status = 'Matched'
                }
                
                $this.Logger.WriteDebug("Matched '$vmName' to '$($matchResult.VM.Name)' (Type: $($matchResult.MatchType), Confidence: $($matchResult.Confidence))")
            } else {
                $unmatchedNames += $vmName
                $this.ProcessingStatistics.NotFound++
                
                $matchingDetails += [PSCustomObject]@{
                    InputName = $vmName
                    MatchedName = ''
                    MatchType = 'None'
                    Confidence = 0.0
                    Status = 'Not Found'
                    PossibleMatches = $matchResult.PossibleMatches -join '; '
                }
                
                $this.Logger.WriteWarning("Could not find match for '$vmName'")
                if ($matchResult.PossibleMatches.Count -gt 0) {
                    $this.Logger.WriteInformation("Possible matches for '$vmName': $($matchResult.PossibleMatches -join ', ')")
                }
            }
        }
        
        return @{
            MatchedVMs = $matchedVMs
            UnmatchedNames = $unmatchedNames
            MatchingDetails = $matchingDetails
        }
    }
    
    # Find best VM match using multiple algorithms
    [hashtable] FindBestVMMatch([string] $targetName, [array] $allVMs) {
        $bestMatch = $null
        $bestMatchType = 'None'
        $bestConfidence = 0.0
        $possibleMatches = @()
        
        # Algorithm 1: Exact match
        if ($this.FuzzyMatchingConfig.EnableExactMatch) {
            $exactMatch = $allVMs | Where-Object { $_.Name -ceq $targetName }
            if ($exactMatch) {
                return @{
                    VM = $exactMatch
                    MatchType = 'Exact'
                    Confidence = 1.0
                    PossibleMatches = @()
                }
            }
        }
        
        # Algorithm 2: Case-insensitive match
        if ($this.FuzzyMatchingConfig.EnableCaseInsensitiveMatch) {
            $caseInsensitiveMatch = $allVMs | Where-Object { $_.Name -ieq $targetName }
            if ($caseInsensitiveMatch) {
                return @{
                    VM = $caseInsensitiveMatch
                    MatchType = 'Case-Insensitive'
                    Confidence = 0.95
                    PossibleMatches = @()
                }
            }
        }
        
        # Algorithm 3: Partial/Contains match
        if ($this.FuzzyMatchingConfig.EnablePartialMatch) {
            $partialMatches = $allVMs | Where-Object { 
                $_.Name -like "*$targetName*" -or $targetName -like "*$($_.Name)*" 
            }
            
            if ($partialMatches.Count -eq 1) {
                return @{
                    VM = $partialMatches[0]
                    MatchType = 'Partial'
                    Confidence = 0.85
                    PossibleMatches = @()
                }
            } elseif ($partialMatches.Count -gt 1 -and $partialMatches.Count -le $this.FuzzyMatchingConfig.MaxPartialMatches) {
                $possibleMatches += $partialMatches | ForEach-Object { $_.Name }
            }
        }
        
        # Algorithm 4: Cleaned name match (remove common prefixes/suffixes)
        if ($this.FuzzyMatchingConfig.EnableCleanedMatch) {
            $cleanedTarget = $this.CleanVMNameForMatching($targetName)
            $cleanedMatches = $allVMs | Where-Object { 
                $cleanedVMName = $this.CleanVMNameForMatching($_.Name)
                $cleanedVMName -eq $cleanedTarget
            }
            
            if ($cleanedMatches.Count -eq 1) {
                return @{
                    VM = $cleanedMatches[0]
                    MatchType = 'Cleaned'
                    Confidence = 0.80
                    PossibleMatches = @()
                }
            } elseif ($cleanedMatches.Count -gt 1) {
                $possibleMatches += $cleanedMatches | ForEach-Object { $_.Name }
            }
        }
        
        # Algorithm 5: Levenshtein distance match
        if ($this.FuzzyMatchingConfig.EnableLevenshteinMatch) {
            $levenshteinMatches = @()
            
            foreach ($vm in $allVMs) {
                $distance = $this.CalculateLevenshteinDistance($targetName.ToLower(), $vm.Name.ToLower())
                if ($distance -le $this.FuzzyMatchingConfig.LevenshteinThreshold) {
                    $confidence = 1.0 - ($distance / [Math]::Max($targetName.Length, $vm.Name.Length))
                    if ($confidence -ge $this.FuzzyMatchingConfig.MinimumMatchConfidence) {
                        $levenshteinMatches += @{
                            VM = $vm
                            Distance = $distance
                            Confidence = $confidence
                        }
                    }
                }
            }
            
            if ($levenshteinMatches.Count -gt 0) {
                # Sort by confidence (highest first)
                $bestLevenshteinMatch = $levenshteinMatches | Sort-Object Confidence -Descending | Select-Object -First 1
                
                if ($bestLevenshteinMatch.Confidence -gt $bestConfidence) {
                    $bestMatch = $bestLevenshteinMatch.VM
                    $bestMatchType = 'Levenshtein'
                    $bestConfidence = $bestLevenshteinMatch.Confidence
                }
            }
        }
        
        # Return best match if confidence is above threshold
        if ($bestMatch -and $bestConfidence -ge $this.FuzzyMatchingConfig.MinimumMatchConfidence) {
            return @{
                VM = $bestMatch
                MatchType = $bestMatchType
                Confidence = $bestConfidence
                PossibleMatches = $possibleMatches
            }
        }
        
        # No good match found
        return @{
            VM = $null
            MatchType = 'None'
            Confidence = 0.0
            PossibleMatches = $possibleMatches
        }
    }
    
    # Calculate Levenshtein distance between two strings
    [int] CalculateLevenshteinDistance([string] $string1, [string] $string2) {
        $len1 = $string1.Length
        $len2 = $string2.Length
        
        # Create matrix
        $matrix = New-Object 'int[,]' ($len1 + 1), ($len2 + 1)
        
        # Initialize first row and column
        for ($i = 0; $i -le $len1; $i++) { $matrix[$i, 0] = $i }
        for ($j = 0; $j -le $len2; $j++) { $matrix[0, $j] = $j }
        
        # Fill matrix
        for ($i = 1; $i -le $len1; $i++) {
            for ($j = 1; $j -le $len2; $j++) {
                $cost = if ($string1[$i - 1] -eq $string2[$j - 1]) { 0 } else { 1 }
                
                $matrix[$i, $j] = [Math]::Min(
                    [Math]::Min($matrix[$i - 1, $j] + 1, $matrix[$i, $j - 1] + 1),
                    $matrix[$i - 1, $j - 1] + $cost
                )
            }
        }
        
        return $matrix[$len1, $len2]
    }
    
    # Clean VM name for better matching
    [string] CleanVMNameForMatching([string] $vmName) {
        # Remove common prefixes, suffixes, and special characters
        $cleaned = $vmName -replace '[-_\.\s]', '' `
                           -replace '(test|prod|dev|staging|qa|uat)$', '' `
                           -replace '^(vm|server|host|machine)', '' `
                           -replace '\d+$', '' `
                           -replace '[^\w]', ''
        
        return $cleaned.ToLower().Trim()
    }
    
    # Sanitize VM name input
    [string] SanitizeVMName([string] $vmName) {
        if ([string]::IsNullOrWhiteSpace($vmName)) {
            $this.ProcessingStatistics.InvalidEntries++
            return $null
        }
        
        # Remove invalid characters and trim whitespace
        $sanitized = $vmName.Trim() -replace '[^\w\-\._\s]', ''
        
        if ([string]::IsNullOrWhiteSpace($sanitized)) {
            $this.ProcessingStatistics.InvalidEntries++
            return $null
        }
        
        return $sanitized
    }
    
    # Generate comprehensive processing reports
    [void] GenerateProcessingReports([string] $originalFilePath, [hashtable] $matchingResults) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $outputDirectory = Split-Path $originalFilePath
        
        # Generate unmatched VMs report
        if ($matchingResults.UnmatchedNames.Count -gt 0) {
            $this.GenerateUnmatchedVMsReport($matchingResults.UnmatchedNames, $outputDirectory, $timestamp)
        }
        
        # Generate detailed matching report
        $this.GenerateDetailedMatchingReport($matchingResults.MatchingDetails, $outputDirectory, $timestamp)
        
        # Generate processing summary
        $this.GenerateProcessingSummary($originalFilePath, $outputDirectory, $timestamp)
    }
    
    # Generate unmatched VMs report
    [void] GenerateUnmatchedVMsReport([array] $unmatchedNames, [string] $outputDirectory, [string] $timestamp) {
        try {
            $reportPath = Join-Path $outputDirectory "Not_Found_VMs_Report_$timestamp.csv"
            
            $reportData = $unmatchedNames | ForEach-Object {
                [PSCustomObject]@{
                    'VM Name' = $_
                    'Status' = 'Not Found'
                    'Timestamp' = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    'Suggestions' = 'Check VM name spelling, verify VM exists in vCenter, or use partial name matching'
                }
            }
            
            $reportData | Export-Csv -Path $reportPath -NoTypeInformation
            $this.Logger.WriteInformation("Generated unmatched VMs report: $reportPath")
            
        } catch {
            $this.Logger.WriteError("Failed to generate unmatched VMs report", $_.Exception)
        }
    }
    
    # Generate detailed matching report
    [void] GenerateDetailedMatchingReport([array] $matchingDetails, [string] $outputDirectory, [string] $timestamp) {
        try {
            $reportPath = Join-Path $outputDirectory "VM_Matching_Details_$timestamp.csv"
            
            $matchingDetails | Export-Csv -Path $reportPath -NoTypeInformation
            $this.Logger.WriteInformation("Generated detailed matching report: $reportPath")
            
        } catch {
            $this.Logger.WriteError("Failed to generate detailed matching report", $_.Exception)
        }
    }
    
    # Generate processing summary
    [void] GenerateProcessingSummary([string] $originalFilePath, [string] $outputDirectory, [string] $timestamp) {
        try {
            $summaryPath = Join-Path $outputDirectory "VM_List_Processing_Summary_$timestamp.txt"
            
            $summary = @"
VM List Processing Summary
==========================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

File Information:
- Source File: $originalFilePath
- File Format: $($this.ProcessingStatistics.FileFormat)
- Column Used: $($this.ProcessingStatistics.ColumnUsed)

Processing Results:
- Total VMs in file: $($this.ProcessingStatistics.TotalVMsInFile)
- Successfully matched: $($this.ProcessingStatistics.SuccessfullyMatched)
- Not found: $($this.ProcessingStatistics.NotFound)
- Duplicates removed: $($this.ProcessingStatistics.DuplicatesFound)
- Invalid entries: $($this.ProcessingStatistics.InvalidEntries)
- Success rate: $($this.ProcessingStatistics.SuccessRate)%

Performance:
- Processing time: $($this.ProcessingStatistics.ProcessingTimeSeconds) seconds

Fuzzy Matching Configuration:
- Exact matching: $($this.FuzzyMatchingConfig.EnableExactMatch)
- Case-insensitive matching: $($this.FuzzyMatchingConfig.EnableCaseInsensitiveMatch)
- Partial matching: $($this.FuzzyMatchingConfig.EnablePartialMatch)
- Cleaned name matching: $($this.FuzzyMatchingConfig.EnableCleanedMatch)
- Levenshtein matching: $($this.FuzzyMatchingConfig.EnableLevenshteinMatch)
- Levenshtein threshold: $($this.FuzzyMatchingConfig.LevenshteinThreshold)
- Minimum confidence: $($this.FuzzyMatchingConfig.MinimumMatchConfidence)

Recommendations:
$(if ($this.ProcessingStatistics.SuccessRate -lt 80) { "- Consider reviewing unmatched VMs for spelling errors or variations" })
$(if ($this.ProcessingStatistics.DuplicatesFound -gt 0) { "- Remove duplicate entries from source file for better performance" })
$(if ($this.ProcessingStatistics.InvalidEntries -gt 0) { "- Clean up invalid entries in source file" })
"@
            
            $summary | Out-File -FilePath $summaryPath -Encoding UTF8
            $this.Logger.WriteInformation("Generated processing summary: $summaryPath")
            
        } catch {
            $this.Logger.WriteError("Failed to generate processing summary", $_.Exception)
        }
    }
    
    # Get processing statistics
    [hashtable] GetProcessingStatistics() {
        return $this.ProcessingStatistics.Clone()
    }
    
    # Configure fuzzy matching settings
    [void] ConfigureFuzzyMatching([hashtable] $config) {
        foreach ($key in $config.Keys) {
            if ($this.FuzzyMatchingConfig.ContainsKey($key)) {
                $this.FuzzyMatchingConfig[$key] = $config[$key]
                $this.Logger.WriteInformation("Updated fuzzy matching config: $key = $($config[$key])")
            }
        }
    }
}