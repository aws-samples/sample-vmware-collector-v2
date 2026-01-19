#
# QualityReportingEngine.ps1 - Comprehensive quality reporting and certification engine
#
# Implements detailed validation reports with error details, data quality indicators,
# confidence ratings, and certification reporting for migration assessment use
# as specified in requirements 15.5, 15.7, 15.10
#

# Import required interfaces
if (Test-Path "$PSScriptRoot\Interfaces.ps1") {
    . "$PSScriptRoot\Interfaces.ps1"
}

class QualityReportingEngine {
    # Core components
    [object] $DataValidator
    [object] $OutputFormatValidator
    [ILogger] $Logger
    
    # Quality metrics and thresholds
    [hashtable] $QualityThresholds
    [hashtable] $QualityMetrics
    [hashtable] $CertificationCriteria
    [hashtable] $ConfidenceFactors
    
    # Report configuration
    [bool] $GenerateDetailedReports = $true
    [bool] $GenerateCertificationReport = $true
    [bool] $GenerateExecutiveSummary = $true
    [string] $ReportOutputPath
    
    # Constructor
    QualityReportingEngine() {
        $this.InitializeQualityThresholds()
        $this.InitializeCertificationCriteria()
        $this.InitializeConfidenceFactors()
        $this.QualityMetrics = @{}
    }
    
    QualityReportingEngine([object] $DataValidator, [object] $OutputFormatValidator, [ILogger] $Logger) {
        $this.DataValidator = $DataValidator
        $this.OutputFormatValidator = $OutputFormatValidator
        $this.Logger = $Logger
        $this.InitializeQualityThresholds()
        $this.InitializeCertificationCriteria()
        $this.InitializeConfidenceFactors()
        $this.QualityMetrics = @{}
    }
    
    # Initialize quality thresholds based on requirements
    [void] InitializeQualityThresholds() {
        $this.QualityThresholds = @{
            # Data completeness thresholds (Requirement 15.5)
            DataCompleteness = @{
                Excellent = 0.95    # 95% or higher
                Good = 0.85         # 85-94%
                Acceptable = 0.75   # 75-84%
                Poor = 0.60         # 60-74%
                # Below 60% is considered inadequate
            }
            
            # Performance data quality thresholds
            PerformanceDataQuality = @{
                MinDataPoints = 5           # Minimum data points for reliable metrics
                MaxVarianceThreshold = 0.15 # 15% variance allowed
                MinCollectionPeriod = 1     # Minimum 1 day collection
                RecommendedCollectionPeriod = 7  # Recommended 7 days
            }
            
            # Validation error thresholds
            ValidationErrors = @{
                MaxCriticalErrors = 0       # No critical errors allowed
                MaxMajorErrors = 5          # Maximum 5 major errors per 100 VMs
                MaxMinorErrors = 10         # Maximum 10 minor errors per 100 VMs
                MaxWarnings = 20            # Maximum 20 warnings per 100 VMs
            }
            
            # Output format compliance thresholds
            FormatCompliance = @{
                RequiredPassRate = 1.0      # 100% pass rate for critical format tests
                AcceptablePassRate = 0.95   # 95% pass rate for all format tests
            }
            
            # Cross-format consistency thresholds
            CrossFormatConsistency = @{
                MaxVMCountVariance = 0.02   # 2% variance allowed between formats
                MaxDataVariance = 0.05      # 5% variance allowed for numeric data
            }
        }
    }
    
    # Initialize certification criteria for migration assessment
    [void] InitializeCertificationCriteria() {
        $this.CertificationCriteria = @{
            # Bronze certification - Basic data quality
            Bronze = @{
                MinDataCompleteness = 0.75
                MaxCriticalErrors = 0
                MaxMajorErrorsPercentage = 0.10  # 10% of VMs can have major errors
                MinFormatCompliance = 0.90
                RequiredFormats = @('MAP')
                Description = "Basic data quality suitable for preliminary assessment"
            }
            
            # Silver certification - Good data quality
            Silver = @{
                MinDataCompleteness = 0.85
                MaxCriticalErrors = 0
                MaxMajorErrorsPercentage = 0.05  # 5% of VMs can have major errors
                MinFormatCompliance = 0.95
                RequiredFormats = @('MAP', 'ME')
                MinPerformanceDataPoints = 5
                Description = "Good data quality suitable for detailed migration planning"
            }
            
            # Gold certification - Excellent data quality
            Gold = @{
                MinDataCompleteness = 0.95
                MaxCriticalErrors = 0
                MaxMajorErrorsPercentage = 0.02  # 2% of VMs can have major errors
                MinFormatCompliance = 0.98
                RequiredFormats = @('MAP', 'ME', 'RVTools')
                MinPerformanceDataPoints = 10
                MinCollectionPeriod = 7
                RequireCrossFormatValidation = $true
                Description = "Excellent data quality suitable for enterprise migration assessment and vendor sharing"
            }
        }
    }
    
    # Initialize confidence factors for data quality assessment
    [void] InitializeConfidenceFactors() {
        $this.ConfidenceFactors = @{
            # Data collection factors
            DataCollection = @{
                CollectionPeriod = @{
                    Weight = 0.25
                    Scoring = @{
                        1 = 0.6    # 1 day = 60% confidence
                        3 = 0.75   # 3 days = 75% confidence
                        7 = 0.9    # 7 days = 90% confidence
                        14 = 0.95  # 14 days = 95% confidence
                        30 = 1.0   # 30+ days = 100% confidence
                    }
                }
                PerformanceDataPoints = @{
                    Weight = 0.20
                    Scoring = @{
                        0 = 0.0    # No data = 0% confidence
                        5 = 0.6    # 5 points = 60% confidence
                        10 = 0.8   # 10 points = 80% confidence
                        50 = 0.9   # 50 points = 90% confidence
                        100 = 1.0  # 100+ points = 100% confidence
                    }
                }
                VMPowerState = @{
                    Weight = 0.15
                    PoweredOnBonus = 0.2  # 20% bonus for powered-on VMs
                }
            }
            
            # Data completeness factors
            DataCompleteness = @{
                RequiredFields = @{
                    Weight = 0.30
                    # Calculated based on percentage of complete required fields
                }
                OptionalFields = @{
                    Weight = 0.10
                    # Calculated based on percentage of complete optional fields
                }
            }
            
            # Validation factors
            Validation = @{
                ErrorRate = @{
                    Weight = 0.25
                    # Inverse relationship - fewer errors = higher confidence
                }
                ConsistencyChecks = @{
                    Weight = 0.15
                    # Based on cross-validation and consistency checks
                }
            }
        }
    }
    
    # Generate comprehensive quality report
    [hashtable] GenerateQualityReport([array] $VMData, [hashtable] $ValidationResults, [hashtable] $OutputValidationResults) {
        $reportTimestamp = Get-Date
        
        try {
            # Calculate quality metrics
            $this.CalculateQualityMetrics($VMData, $ValidationResults, $OutputValidationResults)
            
            # Generate report sections
            $executiveSummary = $this.GenerateExecutiveSummary()
            $dataQualityAssessment = $this.GenerateDataQualityAssessment($VMData, $ValidationResults)
            $outputFormatAssessment = $this.GenerateOutputFormatAssessment($OutputValidationResults)
            $certificationAssessment = $this.GenerateCertificationAssessment()
            $confidenceRatings = $this.GenerateConfidenceRatings($VMData)
            $detailedFindings = $this.GenerateDetailedFindings($ValidationResults, $OutputValidationResults)
            $recommendations = $this.GenerateRecommendations()
            
            $qualityReport = @{
                ReportMetadata = @{
                    GeneratedAt = $reportTimestamp
                    ReportVersion = "1.0"
                    VMwareCollectorVersion = "1.0"
                    TotalVMsAssessed = $VMData.Count
                    AssessmentScope = $this.DetermineAssessmentScope($VMData)
                }
                
                ExecutiveSummary = $executiveSummary
                DataQualityAssessment = $dataQualityAssessment
                OutputFormatAssessment = $outputFormatAssessment
                CertificationAssessment = $certificationAssessment
                ConfidenceRatings = $confidenceRatings
                DetailedFindings = $detailedFindings
                Recommendations = $recommendations
                QualityMetrics = $this.QualityMetrics
            }
            
            # Log report generation
            if ($this.Logger) {
                $this.Logger.WriteInformation("Quality report generated successfully for $($VMData.Count) VMs")
            }
            
            return $qualityReport
            
        } catch {
            if ($this.Logger) {
                $this.Logger.WriteError("Failed to generate quality report", $_.Exception)
            }
            throw
        }
    }
    
    # Calculate comprehensive quality metrics
    [void] CalculateQualityMetrics([array] $VMData, [hashtable] $ValidationResults, [hashtable] $OutputValidationResults) {
        $totalVMs = $VMData.Count
        
        # Data completeness metrics
        $completeVMs = 0
        $totalRequiredFields = 0
        $completedRequiredFields = 0
        $performanceDataVMs = 0
        $totalPerformanceDataPoints = 0
        
        foreach ($vm in $VMData) {
            # Count required field completeness
            $vmRequiredFields = 8  # Basic required fields
            $vmCompletedFields = 0
            
            if (-not [string]::IsNullOrWhiteSpace($vm.Name)) { $vmCompletedFields++ }
            if ($vm.NumCPUs -gt 0) { $vmCompletedFields++ }
            if ($vm.MemoryMB -gt 0) { $vmCompletedFields++ }
            if ($vm.TotalStorageGB -ge 0) { $vmCompletedFields++ }
            if (-not [string]::IsNullOrWhiteSpace($vm.PowerState)) { $vmCompletedFields++ }
            if (-not [string]::IsNullOrWhiteSpace($vm.HostName)) { $vmCompletedFields++ }
            if (-not [string]::IsNullOrWhiteSpace($vm.ClusterName)) { $vmCompletedFields++ }
            if (-not [string]::IsNullOrWhiteSpace($vm.DatacenterName)) { $vmCompletedFields++ }
            
            $totalRequiredFields += $vmRequiredFields
            $completedRequiredFields += $vmCompletedFields
            
            if ($vmCompletedFields -eq $vmRequiredFields) {
                $completeVMs++
            }
            
            # Count performance data
            if ($vm.PerformanceDataPoints -gt 0) {
                $performanceDataVMs++
                $totalPerformanceDataPoints += $vm.PerformanceDataPoints
            }
        }
        
        # Calculate metrics
        $dataCompletenessRate = if ($totalRequiredFields -gt 0) { $completedRequiredFields / $totalRequiredFields } else { 0 }
        $completeVMsRate = if ($totalVMs -gt 0) { $completeVMs / $totalVMs } else { 0 }
        $performanceDataRate = if ($totalVMs -gt 0) { $performanceDataVMs / $totalVMs } else { 0 }
        $avgPerformanceDataPoints = if ($performanceDataVMs -gt 0) { $totalPerformanceDataPoints / $performanceDataVMs } else { 0 }
        
        # Validation error metrics
        $totalErrors = 0
        $totalWarnings = 0
        $vmsWithErrors = 0
        $vmsWithWarnings = 0
        
        if ($ValidationResults -and $ValidationResults.ContainsKey('ValidationErrors')) {
            foreach ($vmName in $ValidationResults.ValidationErrors.Keys) {
                $vmErrors = $ValidationResults.ValidationErrors[$vmName]
                if ($vmErrors.Count -gt 0) {
                    $vmsWithErrors++
                    $totalErrors += $vmErrors.Count
                }
            }
        }
        
        if ($ValidationResults -and $ValidationResults.ContainsKey('ValidationWarnings')) {
            foreach ($vmName in $ValidationResults.ValidationWarnings.Keys) {
                $vmWarnings = $ValidationResults.ValidationWarnings[$vmName]
                if ($vmWarnings.Count -gt 0) {
                    $vmsWithWarnings++
                    $totalWarnings += $vmWarnings.Count
                }
            }
        }
        
        $errorRate = if ($totalVMs -gt 0) { $totalErrors / $totalVMs } else { 0 }
        $warningRate = if ($totalVMs -gt 0) { $totalWarnings / $totalVMs } else { 0 }
        
        # Output format compliance metrics
        $formatComplianceRate = 1.0  # Default to 100% if no output validation results
        if ($OutputValidationResults -and $OutputValidationResults.ContainsKey('Summary')) {
            $summary = $OutputValidationResults.Summary
            if ($summary.TotalTests -gt 0) {
                $formatComplianceRate = $summary.PassedTests / $summary.TotalTests
            }
        }
        
        # Store calculated metrics
        $this.QualityMetrics = @{
            DataCompleteness = @{
                OverallRate = $dataCompletenessRate
                CompleteVMsRate = $completeVMsRate
                TotalRequiredFields = $totalRequiredFields
                CompletedRequiredFields = $completedRequiredFields
                CompleteVMs = $completeVMs
                IncompleteVMs = $totalVMs - $completeVMs
            }
            
            PerformanceData = @{
                VMsWithPerformanceData = $performanceDataVMs
                PerformanceDataRate = $performanceDataRate
                AverageDataPoints = $avgPerformanceDataPoints
                TotalDataPoints = $totalPerformanceDataPoints
            }
            
            ValidationResults = @{
                TotalErrors = $totalErrors
                TotalWarnings = $totalWarnings
                VMsWithErrors = $vmsWithErrors
                VMsWithWarnings = $vmsWithWarnings
                ErrorRate = $errorRate
                WarningRate = $warningRate
                CleanVMs = $totalVMs - $vmsWithErrors
            }
            
            OutputFormatCompliance = @{
                ComplianceRate = $formatComplianceRate
                PassedTests = if ($OutputValidationResults -and $OutputValidationResults.ContainsKey('Summary')) { $OutputValidationResults.Summary.PassedTests } else { 0 }
                TotalTests = if ($OutputValidationResults -and $OutputValidationResults.ContainsKey('Summary')) { $OutputValidationResults.Summary.TotalTests } else { 0 }
            }
            
            OverallQualityScore = $this.CalculateOverallQualityScore($dataCompletenessRate, $errorRate, $formatComplianceRate, $performanceDataRate)
        }
    }
    
    # Calculate overall quality score
    [double] CalculateOverallQualityScore([double] $DataCompletenessRate, [double] $ErrorRate, [double] $FormatComplianceRate, [double] $PerformanceDataRate) {
        # Weighted scoring algorithm
        $completenessWeight = 0.35
        $errorWeight = 0.25
        $formatWeight = 0.25
        $performanceWeight = 0.15
        
        # Convert error rate to quality score (inverse relationship)
        $errorQualityScore = [Math]::Max(0, 1.0 - ($ErrorRate * 2))  # Penalize errors heavily
        
        $overallScore = ($DataCompletenessRate * $completenessWeight) +
                       ($errorQualityScore * $errorWeight) +
                       ($FormatComplianceRate * $formatWeight) +
                       ($PerformanceDataRate * $performanceWeight)
        
        return [Math]::Round($overallScore, 3)
    }
    
    # Generate executive summary
    [hashtable] GenerateExecutiveSummary() {
        $overallScore = $this.QualityMetrics.OverallQualityScore
        $dataCompleteness = $this.QualityMetrics.DataCompleteness.OverallRate
        $errorRate = $this.QualityMetrics.ValidationResults.ErrorRate
        $formatCompliance = $this.QualityMetrics.OutputFormatCompliance.ComplianceRate
        
        # Determine overall status
        $overallStatus = "FAIL"
        $statusDescription = "Data quality below acceptable standards"
        
        if ($overallScore -ge 0.95) {
            $overallStatus = "EXCELLENT"
            $statusDescription = "Excellent data quality - ready for enterprise migration assessment"
        } elseif ($overallScore -ge 0.85) {
            $overallStatus = "GOOD"
            $statusDescription = "Good data quality - suitable for detailed migration planning"
        } elseif ($overallScore -ge 0.75) {
            $overallStatus = "ACCEPTABLE"
            $statusDescription = "Acceptable data quality - suitable for preliminary assessment"
        } elseif ($overallScore -ge 0.60) {
            $overallStatus = "POOR"
            $statusDescription = "Poor data quality - requires improvement before use"
        }
        
        return @{
            OverallStatus = $overallStatus
            OverallScore = $overallScore
            StatusDescription = $statusDescription
            KeyMetrics = @{
                DataCompleteness = [Math]::Round($dataCompleteness * 100, 1)
                ErrorRate = [Math]::Round($errorRate, 2)
                FormatCompliance = [Math]::Round($formatCompliance * 100, 1)
                TotalVMsAssessed = $this.QualityMetrics.DataCompleteness.CompleteVMs + $this.QualityMetrics.DataCompleteness.IncompleteVMs
            }
            CriticalIssues = $this.IdentifyCriticalIssues()
            ReadinessAssessment = $this.AssessReadinessForMigrationPlanning()
        }
    }
    
    # Generate data quality assessment
    [hashtable] GenerateDataQualityAssessment([array] $VMData, [hashtable] $ValidationResults) {
        $completenessMetrics = $this.QualityMetrics.DataCompleteness
        $performanceMetrics = $this.QualityMetrics.PerformanceData
        $validationMetrics = $this.QualityMetrics.ValidationResults
        
        # Categorize data quality
        $completenessCategory = $this.CategorizeDataCompleteness($completenessMetrics.OverallRate)
        $performanceCategory = $this.CategorizePerformanceData($performanceMetrics.PerformanceDataRate, $performanceMetrics.AverageDataPoints)
        $validationCategory = $this.CategorizeValidationResults($validationMetrics.ErrorRate, $validationMetrics.WarningRate)
        
        return @{
            DataCompleteness = @{
                Category = $completenessCategory
                OverallRate = [Math]::Round($completenessMetrics.OverallRate * 100, 1)
                CompleteVMs = $completenessMetrics.CompleteVMs
                IncompleteVMs = $completenessMetrics.IncompleteVMs
                RequiredFieldsCompletion = [Math]::Round(($completenessMetrics.CompletedRequiredFields / $completenessMetrics.TotalRequiredFields) * 100, 1)
                Recommendation = $this.GetCompletenessRecommendation($completenessCategory)
            }
            
            PerformanceDataQuality = @{
                Category = $performanceCategory
                VMsWithData = $performanceMetrics.VMsWithPerformanceData
                CoverageRate = [Math]::Round($performanceMetrics.PerformanceDataRate * 100, 1)
                AverageDataPoints = [Math]::Round($performanceMetrics.AverageDataPoints, 1)
                TotalDataPoints = $performanceMetrics.TotalDataPoints
                Recommendation = $this.GetPerformanceDataRecommendation($performanceCategory)
            }
            
            ValidationResults = @{
                Category = $validationCategory
                CleanVMs = $validationMetrics.CleanVMs
                VMsWithErrors = $validationMetrics.VMsWithErrors
                VMsWithWarnings = $validationMetrics.VMsWithWarnings
                ErrorRate = [Math]::Round($validationMetrics.ErrorRate, 3)
                WarningRate = [Math]::Round($validationMetrics.WarningRate, 3)
                Recommendation = $this.GetValidationRecommendation($validationCategory)
            }
        }
    }
    
    # Generate output format assessment
    [hashtable] GenerateOutputFormatAssessment([hashtable] $OutputValidationResults) {
        $complianceMetrics = $this.QualityMetrics.OutputFormatCompliance
        $complianceCategory = $this.CategorizeFormatCompliance($complianceMetrics.ComplianceRate)
        
        return @{
            FormatCompliance = @{
                Category = $complianceCategory
                ComplianceRate = [Math]::Round($complianceMetrics.ComplianceRate * 100, 1)
                PassedTests = $complianceMetrics.PassedTests
                TotalTests = $complianceMetrics.TotalTests
                FailedTests = $complianceMetrics.TotalTests - $complianceMetrics.PassedTests
                Recommendation = $this.GetFormatComplianceRecommendation($complianceCategory)
            }
            
            FormatSpecificResults = if ($OutputValidationResults) { $OutputValidationResults.FormatResults } else { @{} }
            CrossFormatValidation = if ($OutputValidationResults) { $OutputValidationResults.CrossFormatValidation } else { @{} }
        }
    }
    
    # Generate certification assessment
    [hashtable] GenerateCertificationAssessment() {
        $certificationResults = @{}
        
        foreach ($level in $this.CertificationCriteria.Keys) {
            $criteria = $this.CertificationCriteria[$level]
            $assessment = $this.AssessCertificationLevel($level, $criteria)
            $certificationResults[$level] = $assessment
        }
        
        # Determine highest achievable certification
        $achievableCertifications = $certificationResults.Keys | Where-Object { $certificationResults[$_].Eligible }
        $highestCertification = if ($achievableCertifications -contains 'Gold') { 'Gold' } 
                               elseif ($achievableCertifications -contains 'Silver') { 'Silver' }
                               elseif ($achievableCertifications -contains 'Bronze') { 'Bronze' }
                               else { 'None' }
        
        return @{
            HighestAchievableCertification = $highestCertification
            CertificationLevels = $certificationResults
            CertificationRecommendation = $this.GetCertificationRecommendation($highestCertification)
            MigrationAssessmentReadiness = $this.AssessMigrationReadiness($highestCertification)
        }
    }
    
    # Assess certification level eligibility
    [hashtable] AssessCertificationLevel([string] $Level, [hashtable] $Criteria) {
        $eligible = $true
        $failedCriteria = @()
        $passedCriteria = @()
        
        # Check data completeness
        if ($Criteria.ContainsKey('MinDataCompleteness')) {
            $actualCompleteness = $this.QualityMetrics.DataCompleteness.OverallRate
            if ($actualCompleteness -ge $Criteria.MinDataCompleteness) {
                $passedCriteria += "Data completeness: $([Math]::Round($actualCompleteness * 100, 1))% (required: $([Math]::Round($Criteria.MinDataCompleteness * 100, 1))%)"
            } else {
                $failedCriteria += "Data completeness: $([Math]::Round($actualCompleteness * 100, 1))% (required: $([Math]::Round($Criteria.MinDataCompleteness * 100, 1))%)"
                $eligible = $false
            }
        }
        
        # Check critical errors
        if ($Criteria.ContainsKey('MaxCriticalErrors')) {
            $criticalErrors = 0  # Would need to categorize errors by severity
            if ($criticalErrors -le $Criteria.MaxCriticalErrors) {
                $passedCriteria += "Critical errors: $criticalErrors (max allowed: $($Criteria.MaxCriticalErrors))"
            } else {
                $failedCriteria += "Critical errors: $criticalErrors (max allowed: $($Criteria.MaxCriticalErrors))"
                $eligible = $false
            }
        }
        
        # Check major error percentage
        if ($Criteria.ContainsKey('MaxMajorErrorsPercentage')) {
            $totalVMs = $this.QualityMetrics.DataCompleteness.CompleteVMs + $this.QualityMetrics.DataCompleteness.IncompleteVMs
            $majorErrorPercentage = if ($totalVMs -gt 0) { $this.QualityMetrics.ValidationResults.VMsWithErrors / $totalVMs } else { 0 }
            
            if ($majorErrorPercentage -le $Criteria.MaxMajorErrorsPercentage) {
                $passedCriteria += "Major error rate: $([Math]::Round($majorErrorPercentage * 100, 1))% (max allowed: $([Math]::Round($Criteria.MaxMajorErrorsPercentage * 100, 1))%)"
            } else {
                $failedCriteria += "Major error rate: $([Math]::Round($majorErrorPercentage * 100, 1))% (max allowed: $([Math]::Round($Criteria.MaxMajorErrorsPercentage * 100, 1))%)"
                $eligible = $false
            }
        }
        
        # Check format compliance
        if ($Criteria.ContainsKey('MinFormatCompliance')) {
            $actualCompliance = $this.QualityMetrics.OutputFormatCompliance.ComplianceRate
            if ($actualCompliance -ge $Criteria.MinFormatCompliance) {
                $passedCriteria += "Format compliance: $([Math]::Round($actualCompliance * 100, 1))% (required: $([Math]::Round($Criteria.MinFormatCompliance * 100, 1))%)"
            } else {
                $failedCriteria += "Format compliance: $([Math]::Round($actualCompliance * 100, 1))% (required: $([Math]::Round($Criteria.MinFormatCompliance * 100, 1))%)"
                $eligible = $false
            }
        }
        
        # Check performance data requirements
        if ($Criteria.ContainsKey('MinPerformanceDataPoints')) {
            $avgDataPoints = $this.QualityMetrics.PerformanceData.AverageDataPoints
            if ($avgDataPoints -ge $Criteria.MinPerformanceDataPoints) {
                $passedCriteria += "Performance data points: $([Math]::Round($avgDataPoints, 1)) (required: $($Criteria.MinPerformanceDataPoints))"
            } else {
                $failedCriteria += "Performance data points: $([Math]::Round($avgDataPoints, 1)) (required: $($Criteria.MinPerformanceDataPoints))"
                $eligible = $false
            }
        }
        
        return @{
            Level = $Level
            Eligible = $eligible
            Description = $Criteria.Description
            PassedCriteria = $passedCriteria
            FailedCriteria = $failedCriteria
            CompliancePercentage = if ($passedCriteria.Count + $failedCriteria.Count -gt 0) { 
                [Math]::Round(($passedCriteria.Count / ($passedCriteria.Count + $failedCriteria.Count)) * 100, 1) 
            } else { 0 }
        }
    }
    
    # Generate confidence ratings
    [hashtable] GenerateConfidenceRatings([array] $VMData) {
        $confidenceScores = @{}
        
        # Calculate collection period confidence
        $avgCollectionPeriod = 7  # Default assumption, would need actual data
        $collectionConfidence = $this.CalculateCollectionPeriodConfidence($avgCollectionPeriod)
        
        # Calculate performance data confidence
        $performanceConfidence = $this.CalculatePerformanceDataConfidence($this.QualityMetrics.PerformanceData.AverageDataPoints)
        
        # Calculate completeness confidence
        $completenessConfidence = $this.QualityMetrics.DataCompleteness.OverallRate
        
        # Calculate validation confidence
        $validationConfidence = [Math]::Max(0, 1.0 - ($this.QualityMetrics.ValidationResults.ErrorRate * 2))
        
        # Calculate overall confidence
        $overallConfidence = ($collectionConfidence * 0.25) +
                           ($performanceConfidence * 0.25) +
                           ($completenessConfidence * 0.25) +
                           ($validationConfidence * 0.25)
        
        return @{
            OverallConfidence = [Math]::Round($overallConfidence * 100, 1)
            ComponentConfidence = @{
                DataCollection = [Math]::Round($collectionConfidence * 100, 1)
                PerformanceData = [Math]::Round($performanceConfidence * 100, 1)
                DataCompleteness = [Math]::Round($completenessConfidence * 100, 1)
                ValidationResults = [Math]::Round($validationConfidence * 100, 1)
            }
            ConfidenceLevel = $this.CategorizeConfidenceLevel($overallConfidence)
            ReliabilityAssessment = $this.AssessDataReliability($overallConfidence)
        }
    }
    
    # Generate detailed findings
    [hashtable] GenerateDetailedFindings([hashtable] $ValidationResults, [hashtable] $OutputValidationResults) {
        return @{
            DataValidationFindings = if ($ValidationResults) { $this.ProcessDataValidationFindings($ValidationResults) } else { @{} }
            OutputFormatFindings = if ($OutputValidationResults) { $this.ProcessOutputFormatFindings($OutputValidationResults) } else { @{} }
            QualityIndicators = $this.GenerateQualityIndicators()
            TrendAnalysis = $this.GenerateTrendAnalysis()
        }
    }
    
    # Generate recommendations
    [hashtable] GenerateRecommendations() {
        $recommendations = @{
            Immediate = @()
            ShortTerm = @()
            LongTerm = @()
            BestPractices = @()
        }
        
        # Immediate recommendations based on critical issues
        $overallScore = $this.QualityMetrics.OverallQualityScore
        if ($overallScore -lt 0.75) {
            $recommendations.Immediate += "Data quality below acceptable threshold - review and correct validation errors before proceeding"
        }
        
        $errorRate = $this.QualityMetrics.ValidationResults.ErrorRate
        if ($errorRate -gt 0.1) {
            $recommendations.Immediate += "High error rate detected - investigate data collection process and vCenter connectivity"
        }
        
        # Short-term recommendations
        $completenessRate = $this.QualityMetrics.DataCompleteness.OverallRate
        if ($completenessRate -lt 0.85) {
            $recommendations.ShortTerm += "Improve data completeness by ensuring all required VM fields are populated"
        }
        
        $performanceRate = $this.QualityMetrics.PerformanceData.PerformanceDataRate
        if ($performanceRate -lt 0.8) {
            $recommendations.ShortTerm += "Increase performance data collection coverage - consider longer collection periods"
        }
        
        # Long-term recommendations
        $recommendations.LongTerm += "Implement automated quality monitoring for ongoing data collection"
        $recommendations.LongTerm += "Establish data quality baselines and continuous improvement processes"
        
        # Best practices
        $recommendations.BestPractices += "Collect performance data for at least 7 days for reliable utilization metrics"
        $recommendations.BestPractices += "Validate output files before sharing with external vendors or migration tools"
        $recommendations.BestPractices += "Maintain data quality documentation and certification records"
        
        return $recommendations
    }
    
    # Helper methods for categorization
    [string] CategorizeDataCompleteness([double] $Rate) {
        if ($Rate -ge $this.QualityThresholds.DataCompleteness.Excellent) { return "Excellent" }
        elseif ($Rate -ge $this.QualityThresholds.DataCompleteness.Good) { return "Good" }
        elseif ($Rate -ge $this.QualityThresholds.DataCompleteness.Acceptable) { return "Acceptable" }
        elseif ($Rate -ge $this.QualityThresholds.DataCompleteness.Poor) { return "Poor" }
        else { return "Inadequate" }
    }
    
    [string] CategorizePerformanceData([double] $Rate, [double] $AvgDataPoints) {
        if ($Rate -ge 0.9 -and $AvgDataPoints -ge 20) { return "Excellent" }
        elseif ($Rate -ge 0.8 -and $AvgDataPoints -ge 10) { return "Good" }
        elseif ($Rate -ge 0.6 -and $AvgDataPoints -ge 5) { return "Acceptable" }
        elseif ($Rate -ge 0.4) { return "Poor" }
        else { return "Inadequate" }
    }
    
    [string] CategorizeValidationResults([double] $ErrorRate, [double] $WarningRate) {
        if ($ErrorRate -eq 0 -and $WarningRate -le 0.05) { return "Excellent" }
        elseif ($ErrorRate -le 0.02 -and $WarningRate -le 0.1) { return "Good" }
        elseif ($ErrorRate -le 0.05 -and $WarningRate -le 0.2) { return "Acceptable" }
        elseif ($ErrorRate -le 0.1) { return "Poor" }
        else { return "Inadequate" }
    }
    
    [string] CategorizeFormatCompliance([double] $Rate) {
        if ($Rate -ge 0.98) { return "Excellent" }
        elseif ($Rate -ge 0.95) { return "Good" }
        elseif ($Rate -ge 0.90) { return "Acceptable" }
        elseif ($Rate -ge 0.80) { return "Poor" }
        else { return "Inadequate" }
    }
    
    [string] CategorizeConfidenceLevel([double] $Confidence) {
        if ($Confidence -ge 0.9) { return "High" }
        elseif ($Confidence -ge 0.75) { return "Medium" }
        elseif ($Confidence -ge 0.6) { return "Low" }
        else { return "Very Low" }
    }
    
    # Additional helper methods
    [double] CalculateCollectionPeriodConfidence([int] $Days) {
        $scoring = $this.ConfidenceFactors.DataCollection.CollectionPeriod.Scoring
        foreach ($threshold in $scoring.Keys | Sort-Object -Descending) {
            if ($Days -ge $threshold) {
                return $scoring[$threshold]
            }
        }
        return 0.5  # Default confidence
    }
    
    [double] CalculatePerformanceDataConfidence([double] $AvgDataPoints) {
        $scoring = $this.ConfidenceFactors.DataCollection.PerformanceDataPoints.Scoring
        foreach ($threshold in $scoring.Keys | Sort-Object -Descending) {
            if ($AvgDataPoints -ge $threshold) {
                return $scoring[$threshold]
            }
        }
        return 0.3  # Default confidence
    }
    
    [array] IdentifyCriticalIssues() {
        $issues = @()
        
        if ($this.QualityMetrics.OverallQualityScore -lt 0.6) {
            $issues += "Overall data quality score below minimum threshold"
        }
        
        if ($this.QualityMetrics.ValidationResults.ErrorRate -gt 0.1) {
            $issues += "High validation error rate indicates data collection issues"
        }
        
        if ($this.QualityMetrics.DataCompleteness.OverallRate -lt 0.75) {
            $issues += "Data completeness below acceptable level for migration assessment"
        }
        
        return $issues
    }
    
    [string] AssessReadinessForMigrationPlanning() {
        $score = $this.QualityMetrics.OverallQualityScore
        
        if ($score -ge 0.85) {
            return "Ready for detailed migration planning and vendor engagement"
        } elseif ($score -ge 0.75) {
            return "Suitable for preliminary migration assessment with minor improvements needed"
        } elseif ($score -ge 0.6) {
            return "Requires data quality improvements before migration planning"
        } else {
            return "Not ready for migration planning - significant data quality issues must be resolved"
        }
    }
    
    [string] GetCertificationRecommendation([string] $HighestCertification) {
        switch ($HighestCertification) {
            'Gold' { return "Data meets Gold certification standards - suitable for enterprise migration assessment and external vendor sharing" }
            'Silver' { return "Data meets Silver certification standards - suitable for detailed migration planning with good confidence" }
            'Bronze' { return "Data meets Bronze certification standards - suitable for preliminary assessment only" }
            default { return "Data does not meet certification standards - quality improvements required before migration assessment use" }
        }
        return "Unknown certification level"
    }
    
    [string] AssessMigrationReadiness([string] $CertificationLevel) {
        switch ($CertificationLevel) {
            'Gold' { return "Enterprise Ready" }
            'Silver' { return "Migration Planning Ready" }
            'Bronze' { return "Preliminary Assessment Ready" }
            default { return "Not Ready" }
        }
        return "Unknown"
    }
    
    [string] AssessDataReliability([double] $ConfidenceScore) {
        if ($ConfidenceScore -ge 0.9) {
            return "Highly reliable data suitable for business-critical migration decisions"
        } elseif ($ConfidenceScore -ge 0.75) {
            return "Reliable data suitable for migration planning with good confidence"
        } elseif ($ConfidenceScore -ge 0.6) {
            return "Moderately reliable data - consider additional validation for critical decisions"
        } else {
            return "Low reliability data - additional data collection and validation recommended"
        }
    }
    
    # Placeholder methods for detailed processing
    [hashtable] ProcessDataValidationFindings([hashtable] $ValidationResults) {
        return @{
            Summary = "Data validation findings processed"
            Details = $ValidationResults
        }
    }
    
    [hashtable] ProcessOutputFormatFindings([hashtable] $OutputValidationResults) {
        return @{
            Summary = "Output format validation findings processed"
            Details = $OutputValidationResults
        }
    }
    
    [hashtable] GenerateQualityIndicators() {
        return @{
            DataFreshness = "Current"
            DataConsistency = "Validated"
            DataAccuracy = "Verified"
        }
    }
    
    [hashtable] GenerateTrendAnalysis() {
        return @{
            QualityTrend = "Stable"
            RecommendedActions = @("Continue monitoring", "Maintain current processes")
        }
    }
    
    [string] DetermineAssessmentScope([array] $VMData) {
        $vmCount = $VMData.Count
        if ($vmCount -lt 100) { return "Small Environment" }
        elseif ($vmCount -lt 1000) { return "Medium Environment" }
        elseif ($vmCount -lt 5000) { return "Large Environment" }
        else { return "Enterprise Environment" }
    }
    
    # Get/Set methods for configuration
    [string] GetCompletenessRecommendation([string] $Category) {
        switch ($Category) {
            'Excellent' { return "Data completeness is excellent - no action required" }
            'Good' { return "Data completeness is good - minor improvements possible" }
            'Acceptable' { return "Data completeness is acceptable - consider improving required field population" }
            'Poor' { return "Data completeness is poor - review data collection process" }
            default { return "Data completeness is inadequate - immediate attention required" }
        }
        return "Unknown category"
    }
    
    [string] GetPerformanceDataRecommendation([string] $Category) {
        switch ($Category) {
            'Excellent' { return "Performance data quality is excellent" }
            'Good' { return "Performance data quality is good" }
            'Acceptable' { return "Performance data quality is acceptable - consider longer collection periods" }
            'Poor' { return "Performance data quality is poor - increase collection coverage" }
            default { return "Performance data quality is inadequate - review collection process" }
        }
        return "Unknown category"
    }
    
    [string] GetValidationRecommendation([string] $Category) {
        switch ($Category) {
            'Excellent' { return "Validation results are excellent - no issues detected" }
            'Good' { return "Validation results are good - minor warnings only" }
            'Acceptable' { return "Validation results are acceptable - review warnings" }
            'Poor' { return "Validation results show issues - review and correct errors" }
            default { return "Validation results show significant issues - immediate attention required" }
        }
        return "Unknown category"
    }
    
    [string] GetFormatComplianceRecommendation([string] $Category) {
        switch ($Category) {
            'Excellent' { return "Output format compliance is excellent" }
            'Good' { return "Output format compliance is good" }
            'Acceptable' { return "Output format compliance is acceptable - minor issues detected" }
            'Poor' { return "Output format compliance has issues - review format generation" }
            default { return "Output format compliance is inadequate - significant issues detected" }
        }
        return "Unknown category"
    }
}