#
# CollectionSummaryReporter.ps1 - Collection Summary Reporting Engine
#
# Generates comprehensive collection summary reports with statistics tracking,
# performance metrics, and validation results reporting.
#

using module .\Interfaces.ps1

class CollectionSummaryReporter {
    [hashtable] $CollectionStatistics
    [hashtable] $PerformanceMetrics
    [hashtable] $ValidationResults
    [array] $Errors
    [array] $Warnings
    [ILogger] $Logger
    [datetime] $StartTime
    [datetime] $EndTime
    [string] $Timestamp
    
    # Constructor
    CollectionSummaryReporter([ILogger] $Logger) {
        $this.Logger = $Logger
        $this.StartTime = Get-Date
        $this.Timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $this.InitializeStatistics()
    }
    
    # Initialize statistics tracking structures
    [void] InitializeStatistics() {
        $this.CollectionStatistics = @{
            TotalVMsProcessed = 0
            SuccessfulVMs = 0
            FailedVMs = 0
            PoweredOnVMs = 0
            PoweredOffVMs = 0
            TemplateVMs = 0
            VMsWithPerformanceData = 0
            VMsWithoutPerformanceData = 0
            TotalDataPoints = 0
            CollectionPeriodDays = 0
            OutputFormatsGenerated = @()
            FilesCreated = @()
            AnonymizationEnabled = $false
            AnonymizedFiles = @()
        }
        
        $this.PerformanceMetrics = @{
            TotalExecutionTime = [TimeSpan]::Zero
            ConnectionTime = [TimeSpan]::Zero
            DataCollectionTime = [TimeSpan]::Zero
            PerformanceCollectionTime = [TimeSpan]::Zero
            OutputGenerationTime = [TimeSpan]::Zero
            AnonymizationTime = [TimeSpan]::Zero
            ArchiveCreationTime = [TimeSpan]::Zero
            AverageVMProcessingTime = [TimeSpan]::Zero
            PeakMemoryUsage = 0
            TotalAPICallsMade = 0
            ThreadsUsed = 0
            FastModeEnabled = $false
            OptimizationStatistics = @{}
        }
        
        $this.ValidationResults = @{
            DataValidationPassed = $false
            OutputValidationPassed = $false
            FileIntegrityPassed = $false
            ValidationErrors = @()
            ValidationWarnings = @()
            DataQualityScore = 0.0
            ComplianceScore = 0.0
            ValidationDetails = @{}
        }
        
        $this.Errors = @()
        $this.Warnings = @()
    }
    
    # Start collection timing
    [void] StartCollection() {
        $this.StartTime = Get-Date
        $this.Logger.WriteInformation("Collection started at: $($this.StartTime)")
    }
    
    # End collection timing
    [void] EndCollection() {
        $this.EndTime = Get-Date
        $this.PerformanceMetrics.TotalExecutionTime = $this.EndTime - $this.StartTime
        $this.Logger.WriteInformation("Collection completed at: $($this.EndTime)")
        $this.Logger.WriteInformation("Total execution time: $($this.PerformanceMetrics.TotalExecutionTime)")
    }
    
    # Update VM processing statistics
    [void] UpdateVMStatistics([object] $VMData, [bool] $Success, [bool] $HasPerformanceData) {
        $this.CollectionStatistics.TotalVMsProcessed++
        
        if ($Success) {
            $this.CollectionStatistics.SuccessfulVMs++
        } else {
            $this.CollectionStatistics.FailedVMs++
        }
        
        if ($VMData.PowerState -eq "PoweredOn") {
            $this.CollectionStatistics.PoweredOnVMs++
        } else {
            $this.CollectionStatistics.PoweredOffVMs++
        }
        
        if ($VMData.TemplateFlag) {
            $this.CollectionStatistics.TemplateVMs++
        }
        
        if ($HasPerformanceData) {
            $this.CollectionStatistics.VMsWithPerformanceData++
            $this.CollectionStatistics.TotalDataPoints += $VMData.PerformanceDataPoints
        } else {
            $this.CollectionStatistics.VMsWithoutPerformanceData++
        }
    }
    
    # Update performance timing metrics
    [void] UpdatePerformanceMetrics([string] $Phase, [TimeSpan] $Duration) {
        switch ($Phase.ToLower()) {
            "connection" { $this.PerformanceMetrics.ConnectionTime = $Duration }
            "datacollection" { $this.PerformanceMetrics.DataCollectionTime = $Duration }
            "performancecollection" { $this.PerformanceMetrics.PerformanceCollectionTime = $Duration }
            "outputgeneration" { $this.PerformanceMetrics.OutputGenerationTime = $Duration }
            "anonymization" { $this.PerformanceMetrics.AnonymizationTime = $Duration }
            "archivecreation" { $this.PerformanceMetrics.ArchiveCreationTime = $Duration }
        }
        
        # Calculate average VM processing time
        if ($this.CollectionStatistics.TotalVMsProcessed -gt 0) {
            $totalProcessingTime = $this.PerformanceMetrics.DataCollectionTime + $this.PerformanceMetrics.PerformanceCollectionTime
            $this.PerformanceMetrics.AverageVMProcessingTime = [TimeSpan]::FromMilliseconds($totalProcessingTime.TotalMilliseconds / $this.CollectionStatistics.TotalVMsProcessed)
        }
    }
    
    # Update validation results
    [void] UpdateValidationResults([hashtable] $ValidationData) {
        $this.ValidationResults.DataValidationPassed = $ValidationData.DataValidationPassed
        $this.ValidationResults.OutputValidationPassed = $ValidationData.OutputValidationPassed
        $this.ValidationResults.FileIntegrityPassed = $ValidationData.FileIntegrityPassed
        
        if ($ValidationData.ContainsKey('ValidationErrors')) {
            $this.ValidationResults.ValidationErrors = $ValidationData.ValidationErrors
        }
        
        if ($ValidationData.ContainsKey('ValidationWarnings')) {
            $this.ValidationResults.ValidationWarnings = $ValidationData.ValidationWarnings
        }
        
        if ($ValidationData.ContainsKey('DataQualityScore')) {
            $this.ValidationResults.DataQualityScore = $ValidationData.DataQualityScore
        }
        
        if ($ValidationData.ContainsKey('ComplianceScore')) {
            $this.ValidationResults.ComplianceScore = $ValidationData.ComplianceScore
        }
        
        if ($ValidationData.ContainsKey('ValidationDetails')) {
            $this.ValidationResults.ValidationDetails = $ValidationData.ValidationDetails
        }
    }
    
    # Add error to tracking
    [void] AddError([string] $ErrorMessage, [string] $Source = "", [Exception] $Exception = $null) {
        $errorEntry = @{
            Timestamp = Get-Date
            Message = $ErrorMessage
            Source = $Source
            Exception = if ($Exception) { $Exception.ToString() } else { "" }
        }
        $this.Errors += $errorEntry
        $this.Logger.WriteError($ErrorMessage, $Exception)
    }
    
    # Add warning to tracking
    [void] AddWarning([string] $WarningMessage, [string] $Source = "") {
        $warningEntry = @{
            Timestamp = Get-Date
            Message = $WarningMessage
            Source = $Source
        }
        $this.Warnings += $warningEntry
        $this.Logger.WriteWarning($WarningMessage)
    }
    
    # Update file creation tracking
    [void] UpdateFileCreation([string] $FileName, [string] $Format, [long] $FileSize, [bool] $Anonymized = $false) {
        $fileEntry = @{
            FileName = $FileName
            Format = $Format
            Size = $FileSize
            Created = Get-Date
            Anonymized = $Anonymized
        }
        
        $this.CollectionStatistics.FilesCreated += $fileEntry
        
        if ($Anonymized) {
            $this.CollectionStatistics.AnonymizedFiles += $fileEntry
        }
        
        if ($Format -notin $this.CollectionStatistics.OutputFormatsGenerated) {
            $this.CollectionStatistics.OutputFormatsGenerated += $Format
        }
    }
    
    # Generate comprehensive summary report
    [string] GenerateSummaryReport([string] $OutputPath = "") {
        try {
            $reportContent = $this.BuildReportContent()
            
            # Determine output file path
            if ([string]::IsNullOrEmpty($OutputPath)) {
                $fileName = "Collection_Summary_$($this.Timestamp).txt"
                $OutputPath = Join-Path (Get-Location) $fileName
            }
            
            # Write report to file
            $reportContent | Out-File -FilePath $OutputPath -Encoding UTF8
            
            $this.Logger.WriteInformation("Collection summary report generated: $OutputPath")
            return $OutputPath
            
        } catch {
            $this.Logger.WriteError("Failed to generate summary report", $_.Exception)
            throw
        }
    }
    
    # Build the complete report content
    [string] BuildReportContent() {
        $report = @()
        
        # Header
        $report += "=" * 80
        $report += "VMware vCenter Inventory & Performance Collector - Collection Summary"
        $report += "=" * 80
        $report += ""
        $report += "Generated: $(Get-Date)"
        $report += "Collection Period: $($this.StartTime) to $($this.EndTime)"
        $report += "Total Execution Time: $($this.PerformanceMetrics.TotalExecutionTime)"
        $report += ""
        
        # Collection Statistics
        $report += "COLLECTION STATISTICS"
        $report += "-" * 40
        $report += "Total VMs Processed: $($this.CollectionStatistics.TotalVMsProcessed)"
        $report += "Successful VMs: $($this.CollectionStatistics.SuccessfulVMs)"
        $report += "Failed VMs: $($this.CollectionStatistics.FailedVMs)"
        $report += "Success Rate: $($this.CalculateSuccessRate())%"
        $report += ""
        $report += "VM Power States:"
        $report += "  - Powered On: $($this.CollectionStatistics.PoweredOnVMs)"
        $report += "  - Powered Off: $($this.CollectionStatistics.PoweredOffVMs)"
        $report += "  - Templates: $($this.CollectionStatistics.TemplateVMs)"
        $report += ""
        $report += "Performance Data:"
        $report += "  - VMs with Performance Data: $($this.CollectionStatistics.VMsWithPerformanceData)"
        $report += "  - VMs without Performance Data: $($this.CollectionStatistics.VMsWithoutPerformanceData)"
        $report += "  - Total Data Points Collected: $($this.CollectionStatistics.TotalDataPoints)"
        $report += "  - Collection Period: $($this.CollectionStatistics.CollectionPeriodDays) days"
        $report += ""
        
        # Performance Metrics
        $report += "PERFORMANCE METRICS"
        $report += "-" * 40
        $report += "Connection Time: $($this.PerformanceMetrics.ConnectionTime)"
        $report += "Data Collection Time: $($this.PerformanceMetrics.DataCollectionTime)"
        $report += "Performance Collection Time: $($this.PerformanceMetrics.PerformanceCollectionTime)"
        $report += "Output Generation Time: $($this.PerformanceMetrics.OutputGenerationTime)"
        if ($this.CollectionStatistics.AnonymizationEnabled) {
            $report += "Anonymization Time: $($this.PerformanceMetrics.AnonymizationTime)"
        }
        $report += "Archive Creation Time: $($this.PerformanceMetrics.ArchiveCreationTime)"
        $report += ""
        $report += "Average VM Processing Time: $($this.PerformanceMetrics.AverageVMProcessingTime)"
        $report += "Peak Memory Usage: $([math]::Round($this.PerformanceMetrics.PeakMemoryUsage / 1MB, 2)) MB"
        $report += "Total API Calls Made: $($this.PerformanceMetrics.TotalAPICallsMade)"
        $report += "Threads Used: $($this.PerformanceMetrics.ThreadsUsed)"
        $report += "Fast Mode Enabled: $($this.PerformanceMetrics.FastModeEnabled)"
        $report += ""
        
        # Output Files
        $report += "OUTPUT FILES GENERATED"
        $report += "-" * 40
        $report += "Formats Generated: $($this.CollectionStatistics.OutputFormatsGenerated -join ', ')"
        $report += "Total Files Created: $($this.CollectionStatistics.FilesCreated.Count)"
        if ($this.CollectionStatistics.AnonymizationEnabled) {
            $report += "Anonymized Files: $($this.CollectionStatistics.AnonymizedFiles.Count)"
        }
        $report += ""
        
        foreach ($file in $this.CollectionStatistics.FilesCreated) {
            $sizeStr = if ($file.Size -gt 1MB) { "$([math]::Round($file.Size / 1MB, 2)) MB" } else { "$([math]::Round($file.Size / 1KB, 2)) KB" }
            $anonymizedStr = if ($file.Anonymized) { " (Anonymized)" } else { "" }
            $report += "  - $($file.FileName) [$($file.Format)] - $sizeStr$anonymizedStr"
        }
        $report += ""
        
        # Validation Results
        $report += "VALIDATION RESULTS"
        $report += "-" * 40
        $report += "Data Validation: $(if ($this.ValidationResults.DataValidationPassed) { 'PASSED' } else { 'FAILED' })"
        $report += "Output Validation: $(if ($this.ValidationResults.OutputValidationPassed) { 'PASSED' } else { 'FAILED' })"
        $report += "File Integrity: $(if ($this.ValidationResults.FileIntegrityPassed) { 'PASSED' } else { 'FAILED' })"
        $report += "Data Quality Score: $($this.ValidationResults.DataQualityScore)/100"
        $report += "Compliance Score: $($this.ValidationResults.ComplianceScore)/100"
        $report += ""
        
        if ($this.ValidationResults.ValidationErrors.Count -gt 0) {
            $report += "Validation Errors: $($this.ValidationResults.ValidationErrors.Count)"
            foreach ($error in $this.ValidationResults.ValidationErrors) {
                $report += "  - $error"
            }
            $report += ""
        }
        
        if ($this.ValidationResults.ValidationWarnings.Count -gt 0) {
            $report += "Validation Warnings: $($this.ValidationResults.ValidationWarnings.Count)"
            foreach ($warning in $this.ValidationResults.ValidationWarnings) {
                $report += "  - $warning"
            }
            $report += ""
        }
        
        # Errors and Warnings
        if ($this.Errors.Count -gt 0) {
            $report += "ERRORS ENCOUNTERED"
            $report += "-" * 40
            $report += "Total Errors: $($this.Errors.Count)"
            foreach ($error in $this.Errors) {
                $report += "[$($error.Timestamp)] $($error.Source): $($error.Message)"
            }
            $report += ""
        }
        
        if ($this.Warnings.Count -gt 0) {
            $report += "WARNINGS"
            $report += "-" * 40
            $report += "Total Warnings: $($this.Warnings.Count)"
            foreach ($warning in $this.Warnings) {
                $report += "[$($warning.Timestamp)] $($warning.Source): $($warning.Message)"
            }
            $report += ""
        }
        
        # Recommendations
        $report += "RECOMMENDATIONS"
        $report += "-" * 40
        $report += $this.GenerateRecommendations()
        $report += ""
        
        # Footer
        $report += "=" * 80
        $report += "End of Collection Summary Report"
        $report += "=" * 80
        
        return ($report -join "`n")
    }
    
    # Calculate success rate percentage
    [double] CalculateSuccessRate() {
        if ($this.CollectionStatistics.TotalVMsProcessed -eq 0) {
            return 0.0
        }
        return [math]::Round(($this.CollectionStatistics.SuccessfulVMs / $this.CollectionStatistics.TotalVMsProcessed) * 100, 2)
    }
    
    # Generate recommendations based on collection results
    [string] GenerateRecommendations() {
        $recommendations = @()
        
        # Performance recommendations
        if ($this.PerformanceMetrics.TotalExecutionTime.TotalMinutes -gt 60) {
            $recommendations += "- Consider enabling FastMode for faster collection in large environments"
            $recommendations += "- Increase thread count if system resources allow"
        }
        
        if ($this.CollectionStatistics.VMsWithoutPerformanceData -gt ($this.CollectionStatistics.TotalVMsProcessed * 0.1)) {
            $recommendations += "- High number of VMs without performance data - consider extending collection period"
        }
        
        # Data quality recommendations
        if ($this.ValidationResults.DataQualityScore -lt 90) {
            $recommendations += "- Data quality score is below 90% - review validation errors and warnings"
        }
        
        if ($this.Errors.Count -gt 0) {
            $recommendations += "- Review and address errors encountered during collection"
        }
        
        # Success rate recommendations
        $successRate = $this.CalculateSuccessRate()
        if ($successRate -lt 95) {
            $recommendations += "- Success rate is below 95% - investigate failed VM collections"
        }
        
        # Memory usage recommendations
        if ($this.PerformanceMetrics.PeakMemoryUsage -gt 4GB) {
            $recommendations += "- High memory usage detected - consider processing VMs in smaller batches"
        }
        
        if ($recommendations.Count -eq 0) {
            $recommendations += "- Collection completed successfully with no specific recommendations"
        }
        
        return ($recommendations -join "`n")
    }
    
    # Generate HTML report
    [string] GenerateHTMLReport([string] $OutputPath = "") {
        try {
            $htmlContent = $this.BuildHTMLReportContent()
            
            # Determine output file path
            if ([string]::IsNullOrEmpty($OutputPath)) {
                $fileName = "Collection_Summary_$($this.Timestamp).html"
                $OutputPath = Join-Path (Get-Location) $fileName
            }
            
            # Write HTML report to file
            $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8
            
            $this.Logger.WriteInformation("HTML collection summary report generated: $OutputPath")
            return $OutputPath
            
        } catch {
            $this.Logger.WriteError("Failed to generate HTML summary report", $_.Exception)
            throw
        }
    }
    
    # Build HTML report content
    [string] BuildHTMLReportContent() {
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>VMware Collection Summary Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 10px; border-radius: 5px; }
        .section { margin: 20px 0; }
        .stats-table { border-collapse: collapse; width: 100%; }
        .stats-table th, .stats-table td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        .stats-table th { background-color: #f2f2f2; }
        .success { color: green; font-weight: bold; }
        .failure { color: red; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        .recommendations { background-color: #e8f4f8; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>VMware vCenter Inventory & Performance Collector</h1>
        <h2>Collection Summary Report</h2>
        <p><strong>Generated:</strong> $(Get-Date)</p>
        <p><strong>Collection Period:</strong> $($this.StartTime) to $($this.EndTime)</p>
        <p><strong>Total Execution Time:</strong> $($this.PerformanceMetrics.TotalExecutionTime)</p>
    </div>
    
    <div class="section">
        <h3>Collection Statistics</h3>
        <table class="stats-table">
            <tr><th>Metric</th><th>Value</th></tr>
            <tr><td>Total VMs Processed</td><td>$($this.CollectionStatistics.TotalVMsProcessed)</td></tr>
            <tr><td>Successful VMs</td><td class="success">$($this.CollectionStatistics.SuccessfulVMs)</td></tr>
            <tr><td>Failed VMs</td><td class="failure">$($this.CollectionStatistics.FailedVMs)</td></tr>
            <tr><td>Success Rate</td><td>$($this.CalculateSuccessRate())%</td></tr>
            <tr><td>Powered On VMs</td><td>$($this.CollectionStatistics.PoweredOnVMs)</td></tr>
            <tr><td>Powered Off VMs</td><td>$($this.CollectionStatistics.PoweredOffVMs)</td></tr>
            <tr><td>Template VMs</td><td>$($this.CollectionStatistics.TemplateVMs)</td></tr>
        </table>
    </div>
    
    <div class="section">
        <h3>Performance Metrics</h3>
        <table class="stats-table">
            <tr><th>Phase</th><th>Duration</th></tr>
            <tr><td>Connection</td><td>$($this.PerformanceMetrics.ConnectionTime)</td></tr>
            <tr><td>Data Collection</td><td>$($this.PerformanceMetrics.DataCollectionTime)</td></tr>
            <tr><td>Performance Collection</td><td>$($this.PerformanceMetrics.PerformanceCollectionTime)</td></tr>
            <tr><td>Output Generation</td><td>$($this.PerformanceMetrics.OutputGenerationTime)</td></tr>
            <tr><td>Average VM Processing</td><td>$($this.PerformanceMetrics.AverageVMProcessingTime)</td></tr>
        </table>
    </div>
    
    <div class="section">
        <h3>Validation Results</h3>
        <table class="stats-table">
            <tr><th>Validation Type</th><th>Result</th></tr>
            <tr><td>Data Validation</td><td class="$(if ($this.ValidationResults.DataValidationPassed) { 'success' } else { 'failure' })">$(if ($this.ValidationResults.DataValidationPassed) { 'PASSED' } else { 'FAILED' })</td></tr>
            <tr><td>Output Validation</td><td class="$(if ($this.ValidationResults.OutputValidationPassed) { 'success' } else { 'failure' })">$(if ($this.ValidationResults.OutputValidationPassed) { 'PASSED' } else { 'FAILED' })</td></tr>
            <tr><td>File Integrity</td><td class="$(if ($this.ValidationResults.FileIntegrityPassed) { 'success' } else { 'failure' })">$(if ($this.ValidationResults.FileIntegrityPassed) { 'PASSED' } else { 'FAILED' })</td></tr>
            <tr><td>Data Quality Score</td><td>$($this.ValidationResults.DataQualityScore)/100</td></tr>
            <tr><td>Compliance Score</td><td>$($this.ValidationResults.ComplianceScore)/100</td></tr>
        </table>
    </div>
    
    <div class="section recommendations">
        <h3>Recommendations</h3>
        <pre>$($this.GenerateRecommendations())</pre>
    </div>
</body>
</html>
"@
        
        return $html
    }
    
    # Get summary statistics as hashtable
    [hashtable] GetSummaryStatistics() {
        return @{
            CollectionStatistics = $this.CollectionStatistics.Clone()
            PerformanceMetrics = $this.PerformanceMetrics.Clone()
            ValidationResults = $this.ValidationResults.Clone()
            ErrorCount = $this.Errors.Count
            WarningCount = $this.Warnings.Count
            SuccessRate = $this.CalculateSuccessRate()
            StartTime = $this.StartTime
            EndTime = $this.EndTime
            Timestamp = $this.Timestamp
        }
    }
    
    # Set collection configuration details
    [void] SetCollectionConfiguration([hashtable] $Config) {
        if ($Config.ContainsKey('CollectionPeriodDays')) {
            $this.CollectionStatistics.CollectionPeriodDays = $Config.CollectionPeriodDays
        }
        if ($Config.ContainsKey('AnonymizationEnabled')) {
            $this.CollectionStatistics.AnonymizationEnabled = $Config.AnonymizationEnabled
        }
        if ($Config.ContainsKey('ThreadsUsed')) {
            $this.PerformanceMetrics.ThreadsUsed = $Config.ThreadsUsed
        }
        if ($Config.ContainsKey('FastModeEnabled')) {
            $this.PerformanceMetrics.FastModeEnabled = $Config.FastModeEnabled
        }
        if ($Config.ContainsKey('TotalAPICallsMade')) {
            $this.PerformanceMetrics.TotalAPICallsMade = $Config.TotalAPICallsMade
        }
        if ($Config.ContainsKey('PeakMemoryUsage')) {
            $this.PerformanceMetrics.PeakMemoryUsage = $Config.PeakMemoryUsage
        }
    }
}