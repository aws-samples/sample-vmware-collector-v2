# ME Format Validator
# Provides comprehensive validation for Migration Evaluator format compliance

class MEFormatValidator {
    [ILogger] $Logger
    [hashtable] $ValidationResults
    
    # Constructor
    MEFormatValidator() {
        $this.ValidationResults = @{}
    }
    
    MEFormatValidator([ILogger] $Logger) {
        $this.Logger = $Logger
        $this.ValidationResults = @{}
    }
    
    # Main validation method
    [hashtable] ValidateMEWorkbook([string] $FilePath, [array] $OriginalVMData) {
        try {
            $this.WriteLog("Starting comprehensive ME workbook validation: $FilePath", "Info")
            
            $this.ValidationResults.Clear()
            $this.ValidationResults.IsValid = $true
            $this.ValidationResults.Errors = @()
            $this.ValidationResults.Warnings = @()
            $this.ValidationResults.ValidationDetails = @{}
            
            # Basic file validation
            $this.ValidateFileExists($FilePath)
            
            # Validate workbook structure
            $this.ValidateWorkbookStructure($FilePath)
            
            # Validate worksheet content
            $this.ValidateWorksheetContent($FilePath, $OriginalVMData)
            
            # Validate unique identifiers consistency
            $this.ValidateUniqueIdentifierConsistency($FilePath)
            
            # Validate decimal formatting
            $this.ValidateDecimalFormatting($FilePath)
            
            # Validate data accuracy
            $this.ValidateDataAccuracy($FilePath, $OriginalVMData)
            
            $this.WriteLog("ME workbook validation completed. Valid: $($this.ValidationResults.IsValid)", "Info")
            return $this.ValidationResults
        }
        catch {
            $this.ValidationResults.IsValid = $false
            $this.ValidationResults.Errors += "Validation failed: $($_.Exception.Message)"
            $this.WriteLog("ME workbook validation failed: $($_.Exception.Message)", "Error")
            return $this.ValidationResults
        }
    }
    
    # Validate file exists and is accessible
    [void] ValidateFileExists([string] $FilePath) {
        if (-not (Test-Path $FilePath)) {
            $this.AddError("ME workbook file does not exist: $FilePath")
            return
        }
        
        $fileInfo = Get-Item $FilePath
        if ($fileInfo.Length -eq 0) {
            $this.AddError("ME workbook file is empty: $FilePath")
            return
        }
        
        if ($fileInfo.Extension -ne ".xlsx") {
            $this.AddError("ME workbook file must have .xlsx extension: $FilePath")
            return
        }
        
        $this.WriteLog("File validation passed: $FilePath", "Info")
    }
    
    # Validate workbook structure (5 worksheets in correct order)
    [void] ValidateWorkbookStructure([string] $FilePath) {
        try {
            # Check if ImportExcel module is available
            if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
                $this.AddError("ImportExcel module is required for validation")
                return
            }
            
            Import-Module ImportExcel -Force
            
            # Get worksheet names
            $worksheetNames = Get-ExcelSheetInfo -Path $FilePath | Select-Object -ExpandProperty Name
            
            # Expected worksheets in correct order
            $expectedWorksheets = @(
                "Physical Provisioning",
                "Glossary", 
                "Utilization",
                "Asset Ownership",
                "Virtual Provisioning"
            )
            
            # Validate worksheet count
            if ($worksheetNames.Count -ne 5) {
                $this.AddError("ME workbook must contain exactly 5 worksheets. Found: $($worksheetNames.Count)")
                return
            }
            
            # Validate worksheet names and order
            for ($i = 0; $i -lt $expectedWorksheets.Count; $i++) {
                if ($worksheetNames[$i] -ne $expectedWorksheets[$i]) {
                    $this.AddError("Worksheet $($i+1) should be '$($expectedWorksheets[$i])' but found '$($worksheetNames[$i])'")
                }
            }
            
            $this.ValidationResults.ValidationDetails.WorksheetStructure = @{
                ExpectedWorksheets = $expectedWorksheets
                ActualWorksheets = $worksheetNames
                IsValid = $this.ValidationResults.Errors.Count -eq 0
            }
            
            $this.WriteLog("Workbook structure validation completed", "Info")
        }
        catch {
            $this.AddError("Failed to validate workbook structure: $($_.Exception.Message)")
        }
    }
    
    # Validate worksheet content (column counts and headers)
    [void] ValidateWorksheetContent([string] $FilePath, [array] $OriginalVMData) {
        try {
            $worksheetSpecs = @{
                "Virtual Provisioning" = @{
                    ExpectedColumns = 13
                    Headers = @("Unique Identifier", "Human Name", "vCpu Cores", "Memory MB", "Total Storage Size GB", 
                               "Operating System", "Database Type", "Hypervisor Name", "Address", 
                               "Remote Storage Size GB", "Remote Storage Type", "Local Storage Size GB", "Local Storage Type")
                }
                "Physical Provisioning" = @{
                    ExpectedColumns = 16
                    Headers = @("Unique Identifier", "Human Name", "pCpu Cores", "Memory MB", "Total Storage Size GB",
                               "Cpu String", "Operating System", "Database Type", "Address", "Remote Storage Size GB",
                               "Remote Storage Type", "Local Storage Size GB", "Local Storage Type", "Location", "Make", "Model")
                }
                "Asset Ownership" = @{
                    ExpectedColumns = 8
                    Headers = @("Unique Identifier", "Human Name", "Environment", "Application", "SLA", "Department", "Line of Business", "In Scope")
                }
                "Utilization" = @{
                    ExpectedColumns = 12
                    Headers = @("Unique Identifier", "Human Name", "Cpu Utilization Peak (P95)", "Memory Utilization Peak (P95)",
                               "Storage Utilization Peak (P95)", "Cpu Utilization Avg (P95)", "Memory Utilization Avg (P95)",
                               "Storage Utilization Avg (P95)", "Time On Percentage", "Time In-Use Percentage", "Time Stamp Start", "Time Stamp End")
                }
                "Glossary" = @{
                    ExpectedColumns = 4
                    Headers = @("Attribute Name", "Example", "Requirement", "Notes")
                }
            }
            
            foreach ($worksheetName in $worksheetSpecs.Keys) {
                $spec = $worksheetSpecs[$worksheetName]
                $this.ValidateWorksheetColumns($FilePath, $worksheetName, $spec.ExpectedColumns, $spec.Headers)
                
                # Validate row count for data worksheets
                if ($worksheetName -ne "Glossary") {
                    $this.ValidateWorksheetRowCount($FilePath, $worksheetName, $OriginalVMData.Count)
                }
            }
            
            $this.WriteLog("Worksheet content validation completed", "Info")
        }
        catch {
            $this.AddError("Failed to validate worksheet content: $($_.Exception.Message)")
        }
    }
    
    # Validate specific worksheet columns
    [void] ValidateWorksheetColumns([string] $FilePath, [string] $WorksheetName, [int] $ExpectedColumns, [array] $ExpectedHeaders) {
        try {
            $data = Import-Excel -Path $FilePath -WorksheetName $WorksheetName -NoHeader
            
            if ($data.Count -eq 0) {
                $this.AddError("Worksheet '$WorksheetName' is empty")
                return
            }
            
            # Get first row (headers)
            $headers = $data[0].PSObject.Properties.Value
            
            # Validate column count
            if ($headers.Count -ne $ExpectedColumns) {
                $this.AddError("Worksheet '$WorksheetName' should have $ExpectedColumns columns but has $($headers.Count)")
            }
            
            # Validate header names
            for ($i = 0; $i -lt [Math]::Min($headers.Count, $ExpectedHeaders.Count); $i++) {
                if ($headers[$i] -ne $ExpectedHeaders[$i]) {
                    $this.AddError("Worksheet '$WorksheetName' column $($i+1) should be '$($ExpectedHeaders[$i])' but is '$($headers[$i])'")
                }
            }
            
            $this.WriteLog("Validated worksheet '$WorksheetName': $($headers.Count) columns", "Info")
        }
        catch {
            $this.AddError("Failed to validate worksheet '$WorksheetName': $($_.Exception.Message)")
        }
    }
    
    # Validate worksheet row count
    [void] ValidateWorksheetRowCount([string] $FilePath, [string] $WorksheetName, [int] $ExpectedVMCount) {
        try {
            $data = Import-Excel -Path $FilePath -WorksheetName $WorksheetName
            
            $expectedRows = if ($WorksheetName -eq "Physical Provisioning") {
                # Physical Provisioning has one row per host, not per VM
                # We'll validate it has at least 1 row
                1
            } else {
                $ExpectedVMCount
            }
            
            if ($WorksheetName -ne "Physical Provisioning" -and $data.Count -ne $expectedRows) {
                $this.AddWarning("Worksheet '$WorksheetName' has $($data.Count) data rows, expected $expectedRows")
            }
            
            $this.WriteLog("Validated worksheet '$WorksheetName' row count: $($data.Count) rows", "Info")
        }
        catch {
            $this.AddError("Failed to validate row count for worksheet '$WorksheetName': $($_.Exception.Message)")
        }
    }
    
    # Validate unique identifier consistency across worksheets
    [void] ValidateUniqueIdentifierConsistency([string] $FilePath) {
        try {
            $this.WriteLog("Validating unique identifier consistency", "Info")
            
            # Get unique identifiers from each worksheet
            $worksheets = @("Virtual Provisioning", "Asset Ownership", "Utilization")
            $identifierSets = @{}
            
            foreach ($worksheetName in $worksheets) {
                $data = Import-Excel -Path $FilePath -WorksheetName $worksheetName
                $identifiers = $data | ForEach-Object { $_."Unique Identifier" } | Where-Object { $_ -ne $null }
                $identifierSets[$worksheetName] = $identifiers
            }
            
            # Compare identifier sets
            $baseSet = $identifierSets["Virtual Provisioning"]
            foreach ($worksheetName in $identifierSets.Keys) {
                if ($worksheetName -eq "Virtual Provisioning") { continue }
                
                $currentSet = $identifierSets[$worksheetName]
                $differences = Compare-Object $baseSet $currentSet
                
                if ($differences) {
                    $this.AddError("Unique identifier mismatch between 'Virtual Provisioning' and '$worksheetName'")
                }
            }
            
            # Validate UUID format (32 alphanumeric characters)
            foreach ($id in $baseSet) {
                if ($id -notmatch '^[A-Z0-9]{32}$') {
                    $this.AddError("Invalid unique identifier format. Expected 32 alphanumeric characters, found: $id")
                    break
                }
            }
            
            $this.WriteLog("Unique identifier consistency validation completed", "Info")
        }
        catch {
            $this.AddError("Failed to validate unique identifier consistency: $($_.Exception.Message)")
        }
    }
    
    # Validate decimal formatting (6 decimal places for utilization values)
    [void] ValidateDecimalFormatting([string] $FilePath) {
        try {
            $this.WriteLog("Validating decimal formatting", "Info")
            
            $utilizationData = Import-Excel -Path $FilePath -WorksheetName "Utilization"
            
            $decimalColumns = @(
                "Cpu Utilization Peak (P95)",
                "Memory Utilization Peak (P95)", 
                "Storage Utilization Peak (P95)",
                "Cpu Utilization Avg (P95)",
                "Memory Utilization Avg (P95)",
                "Storage Utilization Avg (P95)"
            )
            
            foreach ($row in $utilizationData) {
                foreach ($column in $decimalColumns) {
                    $value = $row.$column
                    if ($value -ne $null) {
                        # Check if value is between 0 and 1
                        if ($value -lt 0 -or $value -gt 1) {
                            $this.AddError("Utilization value in column '$column' is out of range (0-1): $value")
                        }
                        
                        # Check decimal precision (should have up to 6 decimal places)
                        $valueStr = $value.ToString()
                        if ($valueStr.Contains('.')) {
                            $decimalPart = $valueStr.Split('.')[1]
                            if ($decimalPart.Length -gt 6) {
                                $this.AddWarning("Utilization value in column '$column' has more than 6 decimal places: $value")
                            }
                        }
                    }
                }
            }
            
            $this.WriteLog("Decimal formatting validation completed", "Info")
        }
        catch {
            $this.AddError("Failed to validate decimal formatting: $($_.Exception.Message)")
        }
    }
    
    # Validate data accuracy against original VM data
    [void] ValidateDataAccuracy([string] $FilePath, [array] $OriginalVMData) {
        try {
            $this.WriteLog("Validating data accuracy", "Info")
            
            $virtualProvisioningData = Import-Excel -Path $FilePath -WorksheetName "Virtual Provisioning"
            
            # Create lookup for original data
            $originalDataLookup = @{}
            foreach ($vm in $OriginalVMData) {
                $originalDataLookup[$vm.Name] = $vm
            }
            
            # Validate each row
            foreach ($row in $virtualProvisioningData) {
                $vmName = $row."Human Name"
                if ($originalDataLookup.ContainsKey($vmName)) {
                    $originalVM = $originalDataLookup[$vmName]
                    
                    # Validate key fields
                    if ($row."vCpu Cores" -ne $originalVM.NumCPUs) {
                        $this.AddError("CPU count mismatch for VM '$vmName': Expected $($originalVM.NumCPUs), found $($row.'vCpu Cores')")
                    }
                    
                    if ($row."Memory MB" -ne $originalVM.MemoryMB) {
                        $this.AddError("Memory mismatch for VM '$vmName': Expected $($originalVM.MemoryMB), found $($row.'Memory MB')")
                    }
                    
                    if ($row."Total Storage Size GB" -ne $originalVM.TotalStorageGB) {
                        $this.AddError("Storage mismatch for VM '$vmName': Expected $($originalVM.TotalStorageGB), found $($row.'Total Storage Size GB')")
                    }
                }
            }
            
            $this.WriteLog("Data accuracy validation completed", "Info")
        }
        catch {
            $this.AddError("Failed to validate data accuracy: $($_.Exception.Message)")
        }
    }
    
    # Add error to validation results
    [void] AddError([string] $Message) {
        $this.ValidationResults.IsValid = $false
        $this.ValidationResults.Errors += $Message
        $this.WriteLog("Validation Error: $Message", "Error")
    }
    
    # Add warning to validation results
    [void] AddWarning([string] $Message) {
        $this.ValidationResults.Warnings += $Message
        $this.WriteLog("Validation Warning: $Message", "Warning")
    }
    
    # Logging helper method
    [void] WriteLog([string] $Message, [string] $Level) {
        if ($this.Logger) {
            $this.Logger.WriteLog($Message, $Level)
        } else {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Write-Host "[$timestamp] [$Level] $Message"
        }
    }
}