#
# Interfaces.ps1 - Core interfaces for VMware vCenter Inventory & Performance Collector
#
# Defines the contract interfaces that all components must implement to ensure
# consistent behavior and enable dependency injection and testing.
#

# Base interface for all VMware data models
class IVMwareDataModel {
    [bool] ValidateData() {
        throw "ValidateData method must be implemented by derived class"
    }
    
    [hashtable] ToHashtable() {
        throw "ToHashtable method must be implemented by derived class"
    }
    
    [string] ToString() {
        throw "ToString method must be implemented by derived class"
    }
}

# Interface for connection management
class IConnectionManager {
    [void] Connect() {
        throw "Connect method must be implemented"
    }
    
    [void] EnsureConnection() {
        throw "EnsureConnection method must be implemented"
    }
    
    [void] Disconnect() {
        throw "Disconnect method must be implemented"
    }
    
    [bool] TestConnection() {
        throw "TestConnection method must be implemented"
    }
    
    [void] ConfigureSSL([bool] $DisableSSL) {
        throw "ConfigureSSL method must be implemented"
    }
}

# Interface for data collection
class IDataCollector {
    [array] CollectAllData([array] $VMList) {
        throw "CollectAllData method must be implemented"
    }
    
    [object] CollectVMData([object] $VM) {
        throw "CollectVMData method must be implemented"
    }
    
    [hashtable] CollectInfrastructureData() {
        throw "CollectInfrastructureData method must be implemented"
    }
    
    [array] GetVMList() {
        throw "GetVMList method must be implemented"
    }
}

# Interface for performance metrics processing
class IPerformanceProcessor {
    [hashtable] CalculateVMMetrics([object] $VM, [array] $CpuStats, [array] $MemStats) {
        throw "CalculateVMMetrics method must be implemented"
    }
    
    [array] GenerateDailyStats([object] $VM, [array] $CpuStats, [array] $MemStats) {
        throw "GenerateDailyStats method must be implemented"
    }
    
    [hashtable] CollectBulkPerformanceData([array] $VMs, [datetime] $StartDate, [datetime] $EndDate) {
        throw "CollectBulkPerformanceData method must be implemented"
    }
    
    [double] CalculateMemoryUtilization([double] $ConsumedMB, [double] $AllocatedMB) {
        throw "CalculateMemoryUtilization method must be implemented"
    }
}

# Interface for output format generators
class IOutputGenerator {
    [void] GenerateOutput([array] $VMData, [string] $OutputPath) {
        throw "GenerateOutput method must be implemented"
    }
    
    [bool] ValidateOutput([string] $FilePath) {
        throw "ValidateOutput method must be implemented"
    }
    
    [string] GetOutputFileName([string] $Timestamp) {
        throw "GetOutputFileName method must be implemented"
    }
    
    [hashtable] GetFormatSpecification() {
        throw "GetFormatSpecification method must be implemented"
    }
}

# Interface for data anonymization
class IAnonymizer {
    [array] AnonymizeVMData([array] $VMData) {
        throw "AnonymizeVMData method must be implemented"
    }
    
    [string] AnonymizeValue([string] $OriginalValue, [string] $ValueType) {
        throw "AnonymizeValue method must be implemented"
    }
    
    [hashtable] GetMappingTable() {
        throw "GetMappingTable method must be implemented"
    }
    
    [void] ExportMappingFile([string] $FilePath) {
        throw "ExportMappingFile method must be implemented"
    }
}

# Interface for logging
class ILogger {
    [void] WriteLog([string] $Message, [string] $Level) {
        throw "WriteLog method must be implemented"
    }
    
    [void] WriteError([string] $Message, [Exception] $Exception) {
        throw "WriteError method must be implemented"
    }
    
    [void] WriteWarning([string] $Message) {
        throw "WriteWarning method must be implemented"
    }
    
    [void] WriteInformation([string] $Message) {
        throw "WriteInformation method must be implemented"
    }
    
    [void] WriteDebug([string] $Message) {
        throw "WriteDebug method must be implemented"
    }
    
    [void] WriteVerbose([string] $Message) {
        throw "WriteVerbose method must be implemented"
    }
}

# Interface for progress tracking
class IProgressTracker {
    [void] StartProgress([string] $Activity, [int] $TotalItems) {
        throw "StartProgress method must be implemented"
    }
    
    [void] UpdateProgress([int] $CurrentItem, [string] $CurrentOperation) {
        throw "UpdateProgress method must be implemented"
    }
    
    [void] CompleteProgress() {
        throw "CompleteProgress method must be implemented"
    }
    
    [hashtable] GetProgressStatistics() {
        throw "GetProgressStatistics method must be implemented"
    }
}

# Interface for validation
class IValidator {
    [bool] ValidateVMData([object] $VMData) {
        throw "ValidateVMData method must be implemented"
    }
    
    [bool] ValidateOutputFile([string] $FilePath, [string] $Format) {
        throw "ValidateOutputFile method must be implemented"
    }
    
    [array] GetValidationErrors() {
        throw "GetValidationErrors method must be implemented"
    }
    
    [hashtable] GetValidationReport() {
        throw "GetValidationReport method must be implemented"
    }
}

# Interface for file management
class IFileManager {
    [void] CreateOutputDirectory([string] $BasePath, [string] $Timestamp) {
        throw "CreateOutputDirectory method must be implemented"
    }
    
    [void] OrganizeOutputFiles([hashtable] $Files, [string] $OutputPath) {
        throw "OrganizeOutputFiles method must be implemented"
    }
    
    [void] CreateArchive([string] $SourcePath, [string] $ArchivePath) {
        throw "CreateArchive method must be implemented"
    }
    
    [hashtable] GetFileOrganizationStructure() {
        throw "GetFileOrganizationStructure method must be implemented"
    }
}

# Interface for optimization engine
class IOptimizationEngine {
    [void] ConfigureOptimization([hashtable] $Settings) {
        throw "ConfigureOptimization method must be implemented"
    }
    
    [void] EnableFastMode([bool] $Enable) {
        throw "EnableFastMode method must be implemented"
    }
    
    [void] SetThreadPoolSize([int] $ThreadCount) {
        throw "SetThreadPoolSize method must be implemented"
    }
    
    [hashtable] GetOptimizationStatistics() {
        throw "GetOptimizationStatistics method must be implemented"
    }
}