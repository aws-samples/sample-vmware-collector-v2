class OrchestrationEngine {
    <#
    .SYNOPSIS
    Orchestrates the complete VMware data collection workflow by coordinating all modules and components.
    
    .DESCRIPTION
    The OrchestrationEngine class manages the end-to-end workflow for VMware vCenter data collection,
    including connection management, data collection, processing, output generation, and error handling.
    It provides centralized coordination of all modules with comprehensive progress reporting and
    error recovery procedures.
    #>

    # Core Properties
    [hashtable] $Configuration
    [hashtable] $ProgressTracker
    [hashtable] $WorkflowState
    [hashtable] $ErrorLog
    [datetime] $StartTime
    [datetime] $EndTime
    [bool] $IsRunning
    
    # Component References
    [ConnectionManager] $ConnectionManager
    [object] $DataEngine
    [DataValidationEngine] $ValidationEngine
    [OutputDirectoryManager] $OutputManager
    [object] $AnonymizationEngine
    [CollectionSummaryReporter] $SummaryReporter
    [PerformanceOptimizationManager] $OptimizationManager
    [ILogger] $Logger
    
    # Workflow Results
    [array] $CollectedVMData
    [hashtable] $ValidationResults
    [hashtable] $OutputResults
    [hashtable] $AnonymizationResults
    [hashtable] $CollectionSummary

    # Constructor
    OrchestrationEngine() {
        $this.Initialize()
    }

    # Initialize the orchestration engine
    [void] Initialize() {
        $this.StartTime = Get-Date
        $this.IsRunning = $false
        $this.CollectedVMData = @()
        $this.OutputResults = @{}
        $this.AnonymizationResults = @{}
        
        $this.ProgressTracker = @{
            CurrentPhase = "Initialization"
            TotalPhases = 6
            CurrentPhaseNumber = 0
            VMsProcessed = 0
            TotalVMs = 0
            EstimatedTimeRemaining = $null
            PhaseStartTime = Get-Date
            OverallProgress = 0
        }
        
        $this.WorkflowState = @{
            ConnectionEstablished = $false
            DataCollectionCompleted = $false
            ValidationCompleted = $false
            OutputGenerationCompleted = $false
            AnonymizationCompleted = $false
            SummaryGenerated = $false
        }
        
        $this.ErrorLog = @{
            Errors = @()
            Warnings = @()
            RecoveryActions = @()
        }
    }

    # Main workflow execution method
    [hashtable] ExecuteWorkflow([hashtable] $config) {
        try {
            $this.Configuration = $config
            $this.IsRunning = $true
            $this.StartTime = Get-Date
            
            Write-Host "Starting VMware data collection workflow..." -ForegroundColor Green
            $this.LogWorkflowEvent("Workflow started", "Information")
            
            # Initialize performance optimization
            $this.InitializePerformanceOptimization()
            
            # Phase 1: Connection Management
            $this.ExecuteConnectionPhase()
            
            # Phase 2: Data Collection Setup and Execution
            $this.ExecuteDataCollectionPhase()
            
            # Phase 3: Data Validation and Processing
            $this.ExecuteValidationPhase()
            
            # Phase 4: Output Generation
            $this.ExecuteOutputGenerationPhase()
            
            # Phase 5: Data Anonymization (if requested)
            if ($this.Configuration.AnonymizeData) {
                $this.ExecuteAnonymizationPhase()
            }
            
            # Phase 6: Summary Generation and Cleanup
            $this.ExecuteSummaryPhase()
            
            $this.EndTime = Get-Date
            $this.IsRunning = $false
            
            # Return successful results
            return $this.GenerateWorkflowResults($true)
            
        }
        catch {
            $this.HandleWorkflowError($_)
            $this.EndTime = Get-Date
            $this.IsRunning = $false
            
            # Return error results
            return $this.GenerateWorkflowResults($false, $_.Exception.Message)
        }
        finally {
            $this.PerformCleanup()
        }
    }

    # Initialize performance optimization
    [void] InitializePerformanceOptimization() {
        try {
            $this.OptimizationManager = [PerformanceOptimizationManager]::new()
            
            # Configure optimization settings from configuration
            $optimizationSettings = @{
                MaxThreads = $this.Configuration.MaxThreads
                MaxMemoryGB = if ($this.Configuration.ContainsKey('MaxMemoryGB')) { $this.Configuration.MaxMemoryGB } else { 2 }
                MemoryThresholdPercent = if ($this.Configuration.ContainsKey('MemoryThresholdPercent')) { $this.Configuration.MemoryThresholdPercent } else { 80 }
                EnableBulkOperations = $this.Configuration.FastMode -or $this.Configuration.ContainsKey('EnableBulkOperations')
                EnableCaching = $true
            }
            
            $this.OptimizationManager.ConfigureOptimization($optimizationSettings)
            $this.OptimizationManager.InitializeThreadPool()
            $this.OptimizationManager.StartMonitoring()
            
            Write-Host "Performance optimization initialized: MaxThreads=$($this.Configuration.MaxThreads), MaxMemory=$($optimizationSettings.MaxMemoryGB)GB" -ForegroundColor Green
            $this.LogWorkflowEvent("Performance optimization initialized", "Information")
            
        }
        catch {
            Write-Warning "Failed to initialize performance optimization: $($_.Exception.Message)"
            $this.LogWorkflowEvent("Performance optimization initialization failed: $($_.Exception.Message)", "Warning")
        }
    }

    # Phase 1: Connection Management
    [void] ExecuteConnectionPhase() {
        $this.UpdateProgress("Connection Management", 1)
        $this.LogWorkflowEvent("Starting connection phase", "Information")
        
        try {
            # Initialize connection manager
            $this.ConnectionManager = [ConnectionManager]::new()
            $this.ConnectionManager.VCenterAddress = $this.Configuration.VCenterAddress
            $this.ConnectionManager.Credential = $this.Configuration.Credential
            $this.ConnectionManager.DisableSSL = $this.Configuration.DisableSSL
            $this.ConnectionManager.DebugMode = $this.Configuration.DebugMode
            
            # Establish connection with retry logic
            Write-Host "Connecting to vCenter: $($this.Configuration.VCenterAddress)..." -ForegroundColor Yellow
            $this.ConnectionManager.Connect()
            
            $this.WorkflowState.ConnectionEstablished = $true
            Write-Host "Connection established successfully" -ForegroundColor Green
            $this.LogWorkflowEvent("vCenter connection established", "Information")
            
        }
        catch {
            $this.LogWorkflowEvent("Connection phase failed: $($_.Exception.Message)", "Error")
            throw "Failed to establish vCenter connection: $($_.Exception.Message)"
        }
    }

    # Phase 2: Data Collection Setup and Execution
    [void] ExecuteDataCollectionPhase() {
        $this.UpdateProgress("Data Collection", 2)
        $this.LogWorkflowEvent("Starting data collection phase", "Information")
        
        try {
            # Initialize data collection engine
            try {
                $this.DataEngine = [DataCollectionEngine]::new()
            } catch {
                $this.Logger.WriteWarning("DataCollectionEngine not available, using basic collection")
                $this.DataEngine = $null
            }
            $this.DataEngine.ConnectionManager = $this.ConnectionManager
            $this.DataEngine.MaxThreads = $this.Configuration.MaxThreads
            $this.DataEngine.FastMode = $this.Configuration.FastMode
            $this.DataEngine.PoweredOnOnly = $this.Configuration.PoweredOnOnly
            $this.DataEngine.SkipPerformanceData = $this.Configuration.SkipPerformanceData
            $this.DataEngine.VMListFile = $this.Configuration.VMListFile
            $this.DataEngine.DebugMode = $this.Configuration.DebugMode
            $this.DataEngine.ProgressUpdates = $this.Configuration.ProgressUpdates
            $this.DataEngine.CollectionDays = $this.Configuration.CollectionDays
            
            # Discover VMs
            Write-Host "Discovering VMs..." -ForegroundColor Yellow
            $vmList = $this.DataEngine.GetVMList()
            $this.ProgressTracker.TotalVMs = $vmList.Count
            
            if ($vmList.Count -eq 0) {
                throw "No VMs found matching the specified criteria"
            }
            
            Write-Host "Found $($vmList.Count) VMs for collection" -ForegroundColor Green
            $this.LogWorkflowEvent("Discovered $($vmList.Count) VMs for collection", "Information")
            
            # Collect VM data with performance optimization
            Write-Host "Collecting inventory and performance data..." -ForegroundColor Yellow
            
            if ($this.OptimizationManager) {
                # Use optimized data collection
                $collectionOperation = {
                    param($dataEngine, $vmList)
                    return $dataEngine.CollectAllData($vmList)
                }
                
                $this.CollectedVMData = $this.OptimizationManager.ExecuteOptimizedOperation($collectionOperation, @{
                    dataEngine = $this.DataEngine
                    vmList = $vmList
                })
            } else {
                # Fallback to standard collection
                $this.CollectedVMData = $this.DataEngine.CollectAllData($vmList)
            }
            
            $this.ProgressTracker.VMsProcessed = $this.CollectedVMData.Count
            
            $this.WorkflowState.DataCollectionCompleted = $true
            Write-Host "Successfully collected data from $($this.CollectedVMData.Count) VMs" -ForegroundColor Green
            $this.LogWorkflowEvent("Data collection completed: $($this.CollectedVMData.Count) VMs processed", "Information")
            
        }
        catch {
            $this.LogWorkflowEvent("Data collection phase failed: $($_.Exception.Message)", "Error")
            throw "Data collection failed: $($_.Exception.Message)"
        }
    }

    # Phase 3: Data Validation and Processing
    [void] ExecuteValidationPhase() {
        $this.UpdateProgress("Data Validation", 3)
        $this.LogWorkflowEvent("Starting validation phase", "Information")
        
        try {
            # Initialize validation engine
            $this.ValidationEngine = [DataValidationEngine]::new()
            $this.ValidationEngine.DebugMode = $this.Configuration.DebugMode
            
            # Validate collected data
            Write-Host "Validating collected data..." -ForegroundColor Yellow
            $this.ValidationResults = $this.ValidationEngine.ValidateVMData($this.CollectedVMData)
            
            # Process validation results
            if ($this.ValidationResults.HasErrors) {
                $errorCount = $this.ValidationResults.ErrorCount
                $warningCount = $this.ValidationResults.WarningCount
                
                Write-Warning "Data validation found $errorCount errors and $warningCount warnings"
                $this.LogWorkflowEvent("Validation completed with $errorCount errors and $warningCount warnings", "Warning")
                
                # Log specific validation issues
                foreach ($error in $this.ValidationResults.Errors) {
                    $this.ErrorLog.Errors += $error
                    Write-Verbose "Validation Error: $($error.Message)"
                }
                
                foreach ($warning in $this.ValidationResults.Warnings) {
                    $this.ErrorLog.Warnings += $warning
                    Write-Verbose "Validation Warning: $($warning.Message)"
                }
                
                # Decide whether to continue based on error severity
                if ($this.ValidationResults.HasCriticalErrors) {
                    throw "Critical validation errors found. Cannot continue with output generation."
                }
            } else {
                Write-Host "Data validation completed successfully" -ForegroundColor Green
                $this.LogWorkflowEvent("Data validation completed successfully", "Information")
            }
            
            $this.WorkflowState.ValidationCompleted = $true
            
        }
        catch {
            $this.LogWorkflowEvent("Validation phase failed: $($_.Exception.Message)", "Error")
            throw "Data validation failed: $($_.Exception.Message)"
        }
    }

    # Phase 4: Output Generation
    [void] ExecuteOutputGenerationPhase() {
        $this.UpdateProgress("Output Generation", 4)
        $this.LogWorkflowEvent("Starting output generation phase", "Information")
        
        try {
            # Initialize output directory manager
            $this.OutputManager = [OutputDirectoryManager]::new()
            $this.OutputManager.BaseOutputPath = $this.Configuration.OutputPath
            $this.OutputManager.Timestamp = $this.Configuration.Timestamp
            $this.OutputManager.CreateDirectoryStructure()
            
            $this.OutputResults = @{}
            
            # Generate ME format if requested
            if ($this.Configuration.OutputFormat -eq 'All' -or $this.Configuration.OutputFormat -eq 'ME') {
                $this.GenerateMEOutput()
            }
            
            # Generate MAP format if requested
            if ($this.Configuration.OutputFormat -eq 'All' -or $this.Configuration.OutputFormat -eq 'MAP') {
                $this.GenerateMAPOutput()
            }
            
            # Generate RVTools format if requested
            if ($this.Configuration.OutputFormat -eq 'All' -or $this.Configuration.OutputFormat -eq 'RVTools') {
                $this.GenerateRVToolsOutput()
            }
            
            $this.WorkflowState.OutputGenerationCompleted = $true
            $this.LogWorkflowEvent("Output generation completed successfully", "Information")
            
        }
        catch {
            $this.LogWorkflowEvent("Output generation phase failed: $($_.Exception.Message)", "Error")
            throw "Output generation failed: $($_.Exception.Message)"
        }
    }

    # Phase 5: Data Anonymization
    [void] ExecuteAnonymizationPhase() {
        $this.UpdateProgress("Data Anonymization", 5)
        $this.LogWorkflowEvent("Starting anonymization phase", "Information")
        
        try {
            # Initialize anonymization engine
            try {
                $this.AnonymizationEngine = [DataAnonymizationProcessor]::new()
            } catch {
                $this.Logger.WriteWarning("DataAnonymizationProcessor not available, using basic anonymization")
                $this.AnonymizationEngine = $null
            }
            $this.AnonymizationEngine.OutputPath = $this.OutputManager.BaseOutputPath
            $this.AnonymizationEngine.Timestamp = $this.Configuration.Timestamp
            $this.AnonymizationEngine.DebugMode = $this.Configuration.DebugMode
            
            # Anonymize data
            Write-Host "Anonymizing data..." -ForegroundColor Yellow
            $anonymizedData = $this.AnonymizationEngine.AnonymizeVMData($this.CollectedVMData)
            
            # Regenerate outputs with anonymized data
            $this.RegenerateAnonymizedOutputs($anonymizedData)
            
            # Export anonymization mapping
            $mappingResult = $this.AnonymizationEngine.ExportMappingFile()
            $this.AnonymizationResults['MappingFile'] = $mappingResult
            
            $this.WorkflowState.AnonymizationCompleted = $true
            Write-Host "Data anonymization completed successfully" -ForegroundColor Green
            $this.LogWorkflowEvent("Data anonymization completed successfully", "Information")
            
        }
        catch {
            $this.LogWorkflowEvent("Anonymization phase failed: $($_.Exception.Message)", "Error")
            throw "Data anonymization failed: $($_.Exception.Message)"
        }
    }

    # Phase 6: Summary Generation and Cleanup
    [void] ExecuteSummaryPhase() {
        $this.UpdateProgress("Summary Generation", 6)
        $this.LogWorkflowEvent("Starting summary generation phase", "Information")
        
        try {
            # Initialize summary reporter
            $this.SummaryReporter = [CollectionSummaryReporter]::new()
            $this.SummaryReporter.OutputPath = $this.OutputManager.BaseOutputPath
            $this.SummaryReporter.Timestamp = $this.Configuration.Timestamp
            
            # Generate performance optimization report
            $optimizationReport = $null
            if ($this.OptimizationManager) {
                $optimizationReport = $this.OptimizationManager.GenerateOptimizationReport()
                Write-Host "Performance optimization statistics:" -ForegroundColor Yellow
                Write-Host "  Thread Utilization: $($optimizationReport.PerformanceMetrics.ThreadUtilization)" -ForegroundColor White
                Write-Host "  Memory Utilization: $($optimizationReport.PerformanceMetrics.MemoryUtilization)" -ForegroundColor White
                Write-Host "  Estimated Time Savings: $($optimizationReport.OptimizationImpact.EstimatedTimeSavings)" -ForegroundColor White
                Write-Host "  Performance Improvement: $($optimizationReport.OptimizationImpact.PerformanceImprovement)" -ForegroundColor White
            }
            
            # Generate collection summary
            Write-Host "Generating collection summary..." -ForegroundColor Yellow
            $this.CollectionSummary = @{
                StartTime = $this.StartTime
                EndTime = Get-Date
                TotalVMs = $this.ProgressTracker.TotalVMs
                VMsProcessed = $this.ProgressTracker.VMsProcessed
                Configuration = $this.Configuration
                OutputResults = $this.OutputResults
                ValidationResults = $this.ValidationResults
                AnonymizationResults = $this.AnonymizationResults
                WorkflowState = $this.WorkflowState
                ErrorLog = $this.ErrorLog
                OptimizationReport = $optimizationReport
            }
            
            $summaryResult = $this.SummaryReporter.GenerateReport($this.CollectionSummary)
            
            $this.WorkflowState.SummaryGenerated = $true
            Write-Host "Collection summary generated: $($summaryResult.FilePath)" -ForegroundColor Green
            $this.LogWorkflowEvent("Summary generation completed successfully", "Information")
            
        }
        catch {
            $this.LogWorkflowEvent("Summary generation phase failed: $($_.Exception.Message)", "Error")
            # Don't throw here as this is not critical to the main workflow
            Write-Warning "Summary generation failed: $($_.Exception.Message)"
        }
    }

    # Generate ME format output
    [void] GenerateMEOutput() {
        Write-Host "Generating Migration Evaluator (ME) format..." -ForegroundColor Yellow
        
        $meGenerator = [MEFormatGenerator]::new()
        $meGenerator.OutputPath = $this.OutputManager.MEOutputPath
        $meGenerator.Timestamp = $this.Configuration.Timestamp
        $meGenerator.DebugMode = $this.Configuration.DebugMode
        
        $meResult = $meGenerator.GenerateOutput($this.CollectedVMData)
        $this.OutputResults['ME'] = $meResult
        
        Write-Host "ME format generated: $($meResult.FilePath)" -ForegroundColor Green
        $this.LogWorkflowEvent("ME format output generated: $($meResult.FilePath)", "Information")
    }

    # Generate MAP format output
    [void] GenerateMAPOutput() {
        Write-Host "Generating Migration Portfolio Assessment (MPA) format..." -ForegroundColor Yellow
        
        $mpaGenerator = [MPAFormatGenerator]::new()
        $mpaGenerator.OutputPath = $this.OutputManager.MPAOutputPath
        $mpaGenerator.Timestamp = $this.Configuration.Timestamp
        $mpaGenerator.DebugMode = $this.Configuration.DebugMode
        
        $mapResult = $mpaGenerator.GenerateOutput($this.CollectedVMData)
        $this.OutputResults['MAP'] = $mapResult
        
        Write-Host "MAP format generated: $($mapResult.FilePath)" -ForegroundColor Green
        $this.LogWorkflowEvent("MAP format output generated: $($mapResult.FilePath)", "Information")
    }

    # Generate RVTools format output
    [void] GenerateRVToolsOutput() {
        Write-Host "Generating RVTools format..." -ForegroundColor Yellow
        
        $rvToolsGenerator = [RVToolsFormatGenerator]::new()
        $rvToolsGenerator.OutputPath = $this.OutputManager.RVToolsOutputPath
        $rvToolsGenerator.Timestamp = $this.Configuration.Timestamp
        $rvToolsGenerator.DebugMode = $this.Configuration.DebugMode
        
        $rvToolsResult = $rvToolsGenerator.GenerateOutput($this.CollectedVMData)
        $this.OutputResults['RVTools'] = $rvToolsResult
        
        Write-Host "RVTools format generated: $($rvToolsResult.FilePath)" -ForegroundColor Green
        $this.LogWorkflowEvent("RVTools format output generated: $($rvToolsResult.FilePath)", "Information")
    }

    # Regenerate outputs with anonymized data
    [void] RegenerateAnonymizedOutputs([array] $anonymizedData) {
        Write-Host "Regenerating outputs with anonymized data..." -ForegroundColor Yellow
        
        foreach ($format in $this.OutputResults.Keys) {
            Write-Host "Regenerating anonymized $format format..." -ForegroundColor Yellow
            
            try {
                switch ($format) {
                    'ME' {
                        $meGenerator = [MEFormatGenerator]::new()
                        $meGenerator.OutputPath = $this.OutputManager.MEOutputPath
                        $meGenerator.Timestamp = $this.Configuration.Timestamp
                        $meGenerator.DebugMode = $this.Configuration.DebugMode
                        $anonymizedResult = $meGenerator.GenerateAnonymizedOutput($anonymizedData)
                        $this.AnonymizationResults['ME'] = $anonymizedResult
                    }
                    'MPA' {
                        $mpaGenerator = [MPAFormatGenerator]::new()
                        $mpaGenerator.OutputPath = $this.OutputManager.MPAOutputPath
                        $mpaGenerator.Timestamp = $this.Configuration.Timestamp
                        $mpaGenerator.DebugMode = $this.Configuration.DebugMode
                        $anonymizedResult = $mpaGenerator.GenerateAnonymizedOutput($anonymizedData)
                        $this.AnonymizationResults['MAP'] = $anonymizedResult
                    }
                    'RVTools' {
                        $rvToolsGenerator = [RVToolsFormatGenerator]::new()
                        $rvToolsGenerator.OutputPath = $this.OutputManager.RVToolsOutputPath
                        $rvToolsGenerator.Timestamp = $this.Configuration.Timestamp
                        $rvToolsGenerator.DebugMode = $this.Configuration.DebugMode
                        $anonymizedResult = $rvToolsGenerator.GenerateAnonymizedOutput($anonymizedData)
                        $this.AnonymizationResults['RVTools'] = $anonymizedResult
                    }
                }
                
                Write-Host "Anonymized $format format generated successfully" -ForegroundColor Green
                $this.LogWorkflowEvent("Anonymized $format format generated successfully", "Information")
                
            }
            catch {
                $errorMsg = "Failed to generate anonymized $format format: $($_.Exception.Message)"
                Write-Warning $errorMsg
                $this.LogWorkflowEvent($errorMsg, "Warning")
                $this.ErrorLog.Warnings += @{ Message = $errorMsg; Timestamp = Get-Date }
            }
        }
    }

    # Update progress tracking
    [void] UpdateProgress([string] $phaseName, [int] $phaseNumber) {
        $this.ProgressTracker.CurrentPhase = $phaseName
        $this.ProgressTracker.CurrentPhaseNumber = $phaseNumber
        $this.ProgressTracker.PhaseStartTime = Get-Date
        $this.ProgressTracker.OverallProgress = ($phaseNumber / $this.ProgressTracker.TotalPhases) * 100
        
        if ($this.Configuration.ProgressUpdates) {
            Write-Progress -Activity "VMware Data Collection" -Status "Phase $phaseNumber/$($this.ProgressTracker.TotalPhases): $phaseName" -PercentComplete $this.ProgressTracker.OverallProgress
        }
        
        Write-Host "`n[Phase $phaseNumber/$($this.ProgressTracker.TotalPhases)] $phaseName" -ForegroundColor Cyan
    }

    # Handle workflow errors with recovery procedures
    [void] HandleWorkflowError([System.Management.Automation.ErrorRecord] $errorRecord) {
        $errorMsg = "Workflow error in phase '$($this.ProgressTracker.CurrentPhase)': $($errorRecord.Exception.Message)"
        Write-Error $errorMsg
        
        $this.ErrorLog.Errors += @{
            Phase = $this.ProgressTracker.CurrentPhase
            Message = $errorRecord.Exception.Message
            StackTrace = $errorRecord.ScriptStackTrace
            Timestamp = Get-Date
        }
        
        $this.LogWorkflowEvent($errorMsg, "Error")
        
        # Attempt recovery procedures based on the phase
        $this.AttemptErrorRecovery($errorRecord)
    }

    # Attempt error recovery based on current phase
    [void] AttemptErrorRecovery([System.Management.Automation.ErrorRecord] $errorRecord) {
        $recoveryAction = "No recovery action available"
        
        switch ($this.ProgressTracker.CurrentPhase) {
            "Connection Management" {
                $recoveryAction = "Attempting connection retry with extended timeout"
                try {
                    if ($this.ConnectionManager) {
                        $this.ConnectionManager.RetryConnection(3)
                        $recoveryAction = "Connection recovery successful"
                    }
                }
                catch {
                    $recoveryAction = "Connection recovery failed"
                }
            }
            "Data Collection" {
                $recoveryAction = "Attempting to continue with partial data collection"
                # Could implement partial collection recovery here
            }
            "Data Validation" {
                $recoveryAction = "Continuing with validation warnings"
                # Validation errors are often non-fatal
            }
            "Output Generation" {
                $recoveryAction = "Attempting to generate remaining output formats"
                # Could continue with other formats if one fails
            }
        }
        
        $this.ErrorLog.RecoveryActions += @{
            Phase = $this.ProgressTracker.CurrentPhase
            Action = $recoveryAction
            Timestamp = Get-Date
        }
        
        $this.LogWorkflowEvent("Recovery action: $recoveryAction", "Information")
    }

    # Generate final workflow results
    [hashtable] GenerateWorkflowResults([bool] $success, [string] $errorMessage = $null) {
        $duration = if ($this.EndTime) { $this.EndTime - $this.StartTime } else { (Get-Date) - $this.StartTime }
        
        $results = @{
            Success = $success
            Duration = $duration
            StartTime = $this.StartTime
            EndTime = $this.EndTime
            VMsProcessed = $this.ProgressTracker.VMsProcessed
            TotalVMs = $this.ProgressTracker.TotalVMs
            Configuration = $this.Configuration
            WorkflowState = $this.WorkflowState
            OutputResults = $this.OutputResults
            ValidationResults = $this.ValidationResults
            AnonymizationResults = $this.AnonymizationResults
            CollectionSummary = $this.CollectionSummary
            ErrorLog = $this.ErrorLog
            OutputDirectory = if ($this.OutputManager) { $this.OutputManager.BaseOutputPath } else { $null }
        }
        
        if (-not $success -and $errorMessage) {
            $results['Error'] = $errorMessage
        }
        
        return $results
    }

    # Perform cleanup operations
    [void] PerformCleanup() {
        try {
            # Cleanup performance optimization manager
            if ($this.OptimizationManager) {
                $this.OptimizationManager.Cleanup()
                $this.LogWorkflowEvent("Performance optimization manager cleaned up", "Information")
            }
            
            # Disconnect from vCenter
            if ($this.ConnectionManager -and $this.ConnectionManager.IsConnected) {
                $this.ConnectionManager.Disconnect()
                $this.LogWorkflowEvent("vCenter connection closed", "Information")
            }
            
            # Clear progress display
            if ($this.Configuration.ProgressUpdates) {
                Write-Progress -Activity "VMware Data Collection" -Completed
            }
            
            # Perform garbage collection for large datasets
            if ($this.ProgressTracker.TotalVMs -gt 1000) {
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                $this.LogWorkflowEvent("Memory cleanup performed", "Information")
            }
            
        }
        catch {
            Write-Warning "Cleanup operation failed: $($_.Exception.Message)"
        }
    }

    # Log workflow events
    [void] LogWorkflowEvent([string] $message, [string] $level) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$level] [OrchestrationEngine] $message"
        
        if ($this.Configuration.DebugMode) {
            Write-Host $logEntry -ForegroundColor Gray
        }
        
        # Could write to log file here if logger is available
        if ($this.Logger) {
            switch ($level) {
                "Information" { $this.Logger.LogInformation($message) }
                "Warning" { $this.Logger.LogWarning($message) }
                "Error" { $this.Logger.LogError($message) }
                default { $this.Logger.LogInformation($message) }
            }
        }
    }

    # Get current workflow status
    [hashtable] GetWorkflowStatus() {
        return @{
            IsRunning = $this.IsRunning
            CurrentPhase = $this.ProgressTracker.CurrentPhase
            PhaseNumber = $this.ProgressTracker.CurrentPhaseNumber
            TotalPhases = $this.ProgressTracker.TotalPhases
            OverallProgress = $this.ProgressTracker.OverallProgress
            VMsProcessed = $this.ProgressTracker.VMsProcessed
            TotalVMs = $this.ProgressTracker.TotalVMs
            ElapsedTime = if ($this.StartTime) { (Get-Date) - $this.StartTime } else { $null }
            WorkflowState = $this.WorkflowState
            ErrorCount = $this.ErrorLog.Errors.Count
            WarningCount = $this.ErrorLog.Warnings.Count
        }
    }
}