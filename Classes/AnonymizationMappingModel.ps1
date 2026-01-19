#
# AnonymizationMappingModel.ps1 - Data anonymization mapping system
#
# Implements consistent name mapping for servers, hosts, and IP addresses with subnet preservation.
# Provides reversible mapping functionality for secure data sharing with external vendors.
#

using module .\Interfaces.ps1

class AnonymizationMappingModel : IVMwareDataModel {
    [string] $OriginalValue
    [string] $AnonymizedValue
    [string] $ValueType
    [datetime] $CreatedDate
    [string] $MappingId
    [hashtable] $Metadata
    
    # Constructor
    AnonymizationMappingModel() : base() {
        $this.CreatedDate = Get-Date
        $this.MappingId = [System.Guid]::NewGuid().ToString()
        $this.Metadata = @{}
    }
    
    AnonymizationMappingModel([string] $OriginalValue, [string] $AnonymizedValue, [string] $ValueType) : base() {
        $this.OriginalValue = $OriginalValue
        $this.AnonymizedValue = $AnonymizedValue
        $this.ValueType = $ValueType
        $this.CreatedDate = Get-Date
        $this.MappingId = [System.Guid]::NewGuid().ToString()
        $this.Metadata = @{}
    }
    
    # Validate mapping data
    [bool] ValidateData() {
        $isValid = $true
        
        if ([string]::IsNullOrEmpty($this.OriginalValue)) {
            Write-Warning "OriginalValue is required for anonymization mapping"
            $isValid = $false
        }
        
        if ([string]::IsNullOrEmpty($this.AnonymizedValue)) {
            Write-Warning "AnonymizedValue is required for anonymization mapping"
            $isValid = $false
        }
        
        if ([string]::IsNullOrEmpty($this.ValueType)) {
            Write-Warning "ValueType is required for anonymization mapping"
            $isValid = $false
        }
        
        # Validate value type
        $validTypes = @('ServerName', 'HostName', 'IPAddress', 'DNSName', 'DatastoreName', 'ClusterName', 'NetworkName', 'DatacenterName', 'ResourcePoolName', 'FolderName', 'CustomField', 'VMPathName', 'Annotation')
        if ($this.ValueType -notin $validTypes) {
            Write-Warning "ValueType must be one of: $($validTypes -join ', ')"
            $isValid = $false
        }
        
        return $isValid
    }
    
    # Convert to hashtable
    [hashtable] ToHashtable() {
        return @{
            OriginalValue = $this.OriginalValue
            AnonymizedValue = $this.AnonymizedValue
            ValueType = $this.ValueType
            CreatedDate = $this.CreatedDate
            MappingId = $this.MappingId
            Metadata = $this.Metadata
        }
    }
    
    # String representation
    [string] ToString() {
        return "$($this.ValueType): $($this.OriginalValue) -> $($this.AnonymizedValue)"
    }
}

class AnonymizationEngine : IAnonymizer {
    [hashtable] $AnonymizationMappings
    [hashtable] $IPSubnetMappings
    [hashtable] $CountersByType
    [string] $MappingFilePath
    [ILogger] $Logger
    
    # Constructor
    AnonymizationEngine() {
        $this.AnonymizationMappings = @{}
        $this.IPSubnetMappings = @{}
        $this.CountersByType = @{
            ServerName = 1
            HostName = 1
            IPAddress = 1
            DNSName = 1
            DatastoreName = 1
            ClusterName = 1
            NetworkName = 1
            DatacenterName = 1
            ResourcePoolName = 1
            FolderName = 1
            CustomField = 1
            VMPathName = 1
            Annotation = 1
        }
    }
    
    AnonymizationEngine([ILogger] $Logger) {
        $this.AnonymizationMappings = @{}
        $this.IPSubnetMappings = @{}
        $this.CountersByType = @{
            ServerName = 1
            HostName = 1
            IPAddress = 1
            DNSName = 1
            DatastoreName = 1
            ClusterName = 1
            NetworkName = 1
            DatacenterName = 1
            ResourcePoolName = 1
            FolderName = 1
            CustomField = 1
            VMPathName = 1
            Annotation = 1
        }
        $this.Logger = $Logger
    }
    
    # Main anonymization method for VM data array
    [array] AnonymizeVMData([array] $VMData) {
        $this.WriteLog("Starting anonymization of $($VMData.Count) VM records", "Information")
        
        $anonymizedData = @()
        $processedCount = 0
        
        foreach ($vm in $VMData) {
            $anonymizedVM = $this.AnonymizeVMRecord($vm)
            $anonymizedData += $anonymizedVM
            $processedCount++
            
            if ($processedCount % 100 -eq 0) {
                $this.WriteLog("Anonymized $processedCount of $($VMData.Count) VM records", "Information")
            }
        }
        
        $this.WriteLog("Completed anonymization of $($VMData.Count) VM records", "Information")
        return $anonymizedData
    }
    
    # Anonymize individual VM record
    [object] AnonymizeVMRecord([object] $VMRecord) {
        $anonymizedVM = $VMRecord.PSObject.Copy()
        
        # Anonymize server/VM names
        if (![string]::IsNullOrEmpty($anonymizedVM.Name)) {
            $anonymizedVM.Name = $this.AnonymizeValue($anonymizedVM.Name, "ServerName")
        }
        
        # Anonymize DNS names
        if (![string]::IsNullOrEmpty($anonymizedVM.DNSName)) {
            $anonymizedVM.DNSName = $this.AnonymizeValue($anonymizedVM.DNSName, "DNSName")
        }
        
        # Anonymize IP addresses
        if (![string]::IsNullOrEmpty($anonymizedVM.IPAddress)) {
            $anonymizedVM.IPAddress = $this.AnonymizeValue($anonymizedVM.IPAddress, "IPAddress")
        }
        
        # Anonymize host names
        if (![string]::IsNullOrEmpty($anonymizedVM.HostName)) {
            $anonymizedVM.HostName = $this.AnonymizeValue($anonymizedVM.HostName, "HostName")
        }
        
        # Anonymize cluster names
        if (![string]::IsNullOrEmpty($anonymizedVM.ClusterName)) {
            $anonymizedVM.ClusterName = $this.AnonymizeValue($anonymizedVM.ClusterName, "ClusterName")
        }
        
        # Anonymize datastore names
        if (![string]::IsNullOrEmpty($anonymizedVM.DatastoreName)) {
            $anonymizedVM.DatastoreName = $this.AnonymizeValue($anonymizedVM.DatastoreName, "DatastoreName")
        }
        
        # Anonymize network names
        if (![string]::IsNullOrEmpty($anonymizedVM.NetworkName)) {
            $anonymizedVM.NetworkName = $this.AnonymizeValue($anonymizedVM.NetworkName, "NetworkName")
        }
        
        # Anonymize network adapter names
        for ($i = 1; $i -le 4; $i++) {
            $networkField = "NetworkAdapter$i"
            if (![string]::IsNullOrEmpty($anonymizedVM.$networkField)) {
                $anonymizedVM.$networkField = $this.AnonymizeValue($anonymizedVM.$networkField, "NetworkName")
            }
        }
        
        # Anonymize datacenter names
        if (![string]::IsNullOrEmpty($anonymizedVM.DatacenterName)) {
            $anonymizedVM.DatacenterName = $this.AnonymizeValue($anonymizedVM.DatacenterName, "DatacenterName")
        }
        
        # Anonymize resource pool names
        if (![string]::IsNullOrEmpty($anonymizedVM.ResourcePoolName)) {
            $anonymizedVM.ResourcePoolName = $this.AnonymizeValue($anonymizedVM.ResourcePoolName, "ResourcePoolName")
        }
        
        # Anonymize folder names
        if (![string]::IsNullOrEmpty($anonymizedVM.FolderName)) {
            $anonymizedVM.FolderName = $this.AnonymizeValue($anonymizedVM.FolderName, "FolderName")
        }
        
        # Anonymize custom fields
        if (![string]::IsNullOrEmpty($anonymizedVM.CustomField1)) {
            $anonymizedVM.CustomField1 = $this.AnonymizeValue($anonymizedVM.CustomField1, "CustomField")
        }
        if (![string]::IsNullOrEmpty($anonymizedVM.CustomField2)) {
            $anonymizedVM.CustomField2 = $this.AnonymizeValue($anonymizedVM.CustomField2, "CustomField")
        }
        
        # Anonymize VM path names
        if (![string]::IsNullOrEmpty($anonymizedVM.VMPathName)) {
            $anonymizedVM.VMPathName = $this.AnonymizeValue($anonymizedVM.VMPathName, "VMPathName")
        }
        if (![string]::IsNullOrEmpty($anonymizedVM.VMConfigFile)) {
            $anonymizedVM.VMConfigFile = $this.AnonymizeValue($anonymizedVM.VMConfigFile, "VMPathName")
        }
        
        # Anonymize annotations/notes
        if (![string]::IsNullOrEmpty($anonymizedVM.Annotation)) {
            $anonymizedVM.Annotation = $this.AnonymizeValue($anonymizedVM.Annotation, "Annotation")
        }
        if (![string]::IsNullOrEmpty($anonymizedVM.Notes)) {
            $anonymizedVM.Notes = $this.AnonymizeValue($anonymizedVM.Notes, "Annotation")
        }
        
        # Note: Performance metrics and technical specifications are preserved as per requirements
        # Preserved fields include: NumCPUs, MemoryMB, TotalStorageGB, HardwareVersion, 
        # MaxCpuUsagePct, AvgCpuUsagePct, MaxRamUsagePct, AvgRamUsagePct, PowerState,
        # ConnectionState, GuestState, VMwareToolsStatus, OperatingSystem, etc.
        
        return $anonymizedVM
    }
    
    # Core anonymization method for individual values
    [string] AnonymizeValue([string] $OriginalValue, [string] $ValueType) {
        if ([string]::IsNullOrEmpty($OriginalValue)) {
            return $OriginalValue
        }
        
        # Check if we already have a mapping for this value
        $mappingKey = "$ValueType`:$OriginalValue"
        if ($this.AnonymizationMappings.ContainsKey($mappingKey)) {
            return $this.AnonymizationMappings[$mappingKey].AnonymizedValue
        }
        
        # Generate new anonymized value based on type
        $anonymizedValue = switch ($ValueType) {
            "ServerName" { $this.AnonymizeServerName($OriginalValue) }
            "HostName" { $this.AnonymizeHostName($OriginalValue) }
            "IPAddress" { $this.AnonymizeIPAddress($OriginalValue) }
            "DNSName" { $this.AnonymizeDNSName($OriginalValue) }
            "DatastoreName" { $this.AnonymizeDatastoreName($OriginalValue) }
            "ClusterName" { $this.AnonymizeClusterName($OriginalValue) }
            "NetworkName" { $this.AnonymizeNetworkName($OriginalValue) }
            "DatacenterName" { $this.AnonymizeDatacenterName($OriginalValue) }
            "ResourcePoolName" { $this.AnonymizeResourcePoolName($OriginalValue) }
            "FolderName" { $this.AnonymizeFolderName($OriginalValue) }
            "CustomField" { $this.AnonymizeCustomField($OriginalValue) }
            "VMPathName" { $this.AnonymizeVMPathName($OriginalValue) }
            "Annotation" { $this.AnonymizeAnnotation($OriginalValue) }
            default { 
                $this.WriteLog("Unknown value type: $ValueType", "Warning")
                $OriginalValue 
            }
        }
        
        # Store the mapping
        $this.AddMapping($OriginalValue, $anonymizedValue, $ValueType)
        
        return $anonymizedValue
    }
    
    # Anonymize server names with consistent patterns
    [string] AnonymizeServerName([string] $ServerName) {
        $counter = $this.CountersByType["ServerName"]
        $anonymizedName = "mocked-server-$counter"
        $this.CountersByType["ServerName"] = $counter + 1
        
        $this.WriteLog("Anonymized server name: $ServerName -> $anonymizedName", "Debug")
        return $anonymizedName
    }
    
    # Anonymize host names with consistent patterns
    [string] AnonymizeHostName([string] $HostName) {
        $counter = $this.CountersByType["HostName"]
        $anonymizedName = "mocked-host-$counter"
        $this.CountersByType["HostName"] = $counter + 1
        
        $this.WriteLog("Anonymized host name: $HostName -> $anonymizedName", "Debug")
        return $anonymizedName
    }
    
    # Anonymize IP addresses while preserving subnet relationships
    [string] AnonymizeIPAddress([string] $IPAddress) {
        if (![System.Net.IPAddress]::TryParse($IPAddress, [ref]$null)) {
            $this.WriteLog("Invalid IP address format: $IPAddress", "Warning")
            return $IPAddress
        }
        
        # Extract subnet (first 3 octets) and host part (last octet)
        $octets = $IPAddress.Split('.')
        if ($octets.Count -ne 4) {
            $this.WriteLog("Invalid IP address format: $IPAddress", "Warning")
            return $IPAddress
        }
        
        $subnet = "$($octets[0]).$($octets[1]).$($octets[2])"
        $hostPart = $octets[3]
        
        # Check if we have a mapping for this subnet
        if (!$this.IPSubnetMappings.ContainsKey($subnet)) {
            # Generate new anonymized subnet
            $counter = $this.CountersByType["IPAddress"]
            $anonymizedSubnet = "10.0.$counter"
            $this.IPSubnetMappings[$subnet] = $anonymizedSubnet
            $this.CountersByType["IPAddress"] = $counter + 1
        }
        
        $anonymizedSubnet = $this.IPSubnetMappings[$subnet]
        $anonymizedIP = "$anonymizedSubnet.$hostPart"
        
        $this.WriteLog("Anonymized IP address: $IPAddress -> $anonymizedIP (subnet preserved)", "Debug")
        return $anonymizedIP
    }
    
    # Anonymize DNS names
    [string] AnonymizeDNSName([string] $DNSName) {
        # For DNS names, we'll use the same pattern as server names but with .local domain
        $counter = $this.CountersByType["DNSName"]
        $anonymizedName = "mocked-server-$counter.local"
        $this.CountersByType["DNSName"] = $counter + 1
        
        $this.WriteLog("Anonymized DNS name: $DNSName -> $anonymizedName", "Debug")
        return $anonymizedName
    }
    
    # Anonymize datastore names
    [string] AnonymizeDatastoreName([string] $DatastoreName) {
        $counter = $this.CountersByType["DatastoreName"]
        $anonymizedName = "mocked-datastore-$counter"
        $this.CountersByType["DatastoreName"] = $counter + 1
        
        $this.WriteLog("Anonymized datastore name: $DatastoreName -> $anonymizedName", "Debug")
        return $anonymizedName
    }
    
    # Anonymize cluster names
    [string] AnonymizeClusterName([string] $ClusterName) {
        $counter = $this.CountersByType["ClusterName"]
        $anonymizedName = "mocked-cluster-$counter"
        $this.CountersByType["ClusterName"] = $counter + 1
        
        $this.WriteLog("Anonymized cluster name: $ClusterName -> $anonymizedName", "Debug")
        return $anonymizedName
    }
    
    # Anonymize network names
    [string] AnonymizeNetworkName([string] $NetworkName) {
        $counter = $this.CountersByType["NetworkName"]
        $anonymizedName = "mocked-network-$counter"
        $this.CountersByType["NetworkName"] = $counter + 1
        
        $this.WriteLog("Anonymized network name: $NetworkName -> $anonymizedName", "Debug")
        return $anonymizedName
    }
    
    # Anonymize datacenter names
    [string] AnonymizeDatacenterName([string] $DatacenterName) {
        $counter = $this.CountersByType["DatacenterName"]
        $anonymizedName = "mocked-datacenter-$counter"
        $this.CountersByType["DatacenterName"] = $counter + 1
        
        $this.WriteLog("Anonymized datacenter name: $DatacenterName -> $anonymizedName", "Debug")
        return $anonymizedName
    }
    
    # Anonymize resource pool names
    [string] AnonymizeResourcePoolName([string] $ResourcePoolName) {
        $counter = $this.CountersByType["ResourcePoolName"]
        $anonymizedName = "mocked-resourcepool-$counter"
        $this.CountersByType["ResourcePoolName"] = $counter + 1
        
        $this.WriteLog("Anonymized resource pool name: $ResourcePoolName -> $anonymizedName", "Debug")
        return $anonymizedName
    }
    
    # Anonymize folder names
    [string] AnonymizeFolderName([string] $FolderName) {
        $counter = $this.CountersByType["FolderName"]
        $anonymizedName = "mocked-folder-$counter"
        $this.CountersByType["FolderName"] = $counter + 1
        
        $this.WriteLog("Anonymized folder name: $FolderName -> $anonymizedName", "Debug")
        return $anonymizedName
    }
    
    # Anonymize custom field values
    [string] AnonymizeCustomField([string] $CustomFieldValue) {
        if ([string]::IsNullOrEmpty($CustomFieldValue)) {
            return $CustomFieldValue
        }
        
        $counter = $this.CountersByType["CustomField"]
        $anonymizedValue = "mocked-custom-value-$counter"
        $this.CountersByType["CustomField"] = $counter + 1
        
        $this.WriteLog("Anonymized custom field: $CustomFieldValue -> $anonymizedValue", "Debug")
        return $anonymizedValue
    }
    
    # Anonymize VM path names (datastore paths)
    [string] AnonymizeVMPathName([string] $VMPathName) {
        if ([string]::IsNullOrEmpty($VMPathName)) {
            return $VMPathName
        }
        
        # VM paths typically look like: [datastore1] VM-Name/VM-Name.vmx
        # We'll anonymize the datastore and VM name parts while preserving the structure
        $counter = $this.CountersByType["VMPathName"]
        
        # Extract pattern and anonymize components
        if ($VMPathName -match '^\[([^\]]+)\]\s*(.+)$') {
            $datastoreName = $matches[1]
            $vmPath = $matches[2]
            
            # Anonymize datastore name
            $anonymizedDatastore = $this.AnonymizeValue($datastoreName, "DatastoreName")
            
            # Anonymize VM name in path
            $vmName = ($vmPath -split '/')[0]
            $anonymizedVMName = $this.AnonymizeValue($vmName, "ServerName")
            
            # Reconstruct path with anonymized components
            $anonymizedPath = "[$anonymizedDatastore] $anonymizedVMName/$anonymizedVMName.vmx"
            
            $this.WriteLog("Anonymized VM path: $VMPathName -> $anonymizedPath", "Debug")
            return $anonymizedPath
        } else {
            # Fallback for non-standard paths
            $anonymizedPath = "mocked-vmpath-$counter"
            $this.CountersByType["VMPathName"] = $counter + 1
            
            $this.WriteLog("Anonymized VM path (fallback): $VMPathName -> $anonymizedPath", "Debug")
            return $anonymizedPath
        }
    }
    
    # Anonymize annotations/notes
    [string] AnonymizeAnnotation([string] $Annotation) {
        if ([string]::IsNullOrEmpty($Annotation)) {
            return $Annotation
        }
        
        # For annotations, we'll replace with generic text to avoid exposing sensitive information
        # but preserve the fact that there was an annotation
        $counter = $this.CountersByType["Annotation"]
        $anonymizedAnnotation = "Anonymized annotation $counter - original content removed for security"
        $this.CountersByType["Annotation"] = $counter + 1
        
        $this.WriteLog("Anonymized annotation: [content hidden] -> $anonymizedAnnotation", "Debug")
        return $anonymizedAnnotation
    }
    
    # Add mapping to the collection
    [void] AddMapping([string] $Original, [string] $Anonymized, [string] $Type) {
        $mappingKey = "$Type`:$Original"
        $mapping = [AnonymizationMappingModel]::new($Original, $Anonymized, $Type)
        $this.AnonymizationMappings[$mappingKey] = $mapping
        
        $this.WriteLog("Added mapping: $($mapping.ToString())", "Debug")
    }
    
    # Get anonymized value if mapping exists
    [string] GetAnonymizedValue([string] $Original, [string] $Type) {
        $mappingKey = "$Type`:$Original"
        if ($this.AnonymizationMappings.ContainsKey($mappingKey)) {
            return $this.AnonymizationMappings[$mappingKey].AnonymizedValue
        }
        return $null
    }
    
    # Check if mapping exists
    [bool] HasMapping([string] $Original, [string] $Type) {
        $mappingKey = "$Type`:$Original"
        return $this.AnonymizationMappings.ContainsKey($mappingKey)
    }
    
    # Get complete mapping table
    [hashtable] GetMappingTable() {
        $mappingTable = @{}
        
        foreach ($key in $this.AnonymizationMappings.Keys) {
            $mapping = $this.AnonymizationMappings[$key]
            $mappingTable[$key] = $mapping.ToHashtable()
        }
        
        return $mappingTable
    }
    
    # Export mapping file to Excel format with secure naming
    [void] ExportMappingFile([string] $FilePath) {
        try {
            $this.WriteLog("Starting export of anonymization mapping file to: $FilePath", "Information")
            
            # Validate file path
            if ([string]::IsNullOrEmpty($FilePath)) {
                throw "File path cannot be null or empty"
            }
            
            # Ensure directory exists
            $directory = Split-Path $FilePath -Parent
            if (![string]::IsNullOrEmpty($directory) -and !(Test-Path $directory)) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
                $this.WriteLog("Created directory: $directory", "Debug")
            }
            
            # Prepare mapping data for export
            $mappingData = $this.PrepareMappingDataForExport()
            
            # Validate mapping data integrity
            if (!$this.ValidateMappingIntegrity($mappingData)) {
                throw "Mapping data integrity validation failed"
            }
            
            # Export to Excel format
            $this.ExportToExcel($mappingData, $FilePath)
            
            # Apply file protection and access controls
            $this.ApplyFileProtection($FilePath)
            
            $this.WriteLog("Successfully exported anonymization mapping file: $FilePath", "Information")
        }
        catch {
            $this.WriteLog("Error exporting mapping file: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Get mapping statistics
    [hashtable] GetMappingStatistics() {
        $stats = @{
            TotalMappings = $this.AnonymizationMappings.Count
            MappingsByType = @{}
            SubnetMappings = $this.IPSubnetMappings.Count
        }
        
        foreach ($mapping in $this.AnonymizationMappings.Values) {
            if (!$stats.MappingsByType.ContainsKey($mapping.ValueType)) {
                $stats.MappingsByType[$mapping.ValueType] = 0
            }
            $stats.MappingsByType[$mapping.ValueType]++
        }
        
        return $stats
    }
    
    # Reset all mappings (useful for testing)
    [void] ResetMappings() {
        $this.AnonymizationMappings.Clear()
        $this.IPSubnetMappings.Clear()
        $this.CountersByType = @{
            ServerName = 1
            HostName = 1
            IPAddress = 1
            DNSName = 1
            DatastoreName = 1
            ClusterName = 1
            NetworkName = 1
            DatacenterName = 1
            ResourcePoolName = 1
            FolderName = 1
            CustomField = 1
            VMPathName = 1
            Annotation = 1
        }
        
        $this.WriteLog("All anonymization mappings have been reset", "Information")
    }
    
    # Prepare mapping data for Excel export
    [hashtable] PrepareMappingDataForExport() {
        $exportData = @{
            MappingData = @()
            SubnetMappings = @()
            Statistics = @()
            Metadata = @()
        }
        
        # Prepare main mapping data
        foreach ($mapping in $this.AnonymizationMappings.Values) {
            $exportData.MappingData += @{
                'Original Value' = $mapping.OriginalValue
                'Anonymized Value' = $mapping.AnonymizedValue
                'Value Type' = $mapping.ValueType
                'Created Date' = $mapping.CreatedDate.ToString('yyyy-MM-dd HH:mm:ss')
                'Mapping ID' = $mapping.MappingId
            }
        }
        
        # Prepare subnet mappings
        foreach ($subnet in $this.IPSubnetMappings.Keys) {
            $exportData.SubnetMappings += @{
                'Original Subnet' = $subnet
                'Anonymized Subnet' = $this.IPSubnetMappings[$subnet]
                'Mapping Type' = 'IP Subnet'
                'Created Date' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            }
        }
        
        # Prepare statistics
        $stats = $this.GetMappingStatistics()
        $exportData.Statistics += @{
            'Statistic' = 'Total Mappings'
            'Value' = $stats.TotalMappings
        }
        $exportData.Statistics += @{
            'Statistic' = 'Subnet Mappings'
            'Value' = $stats.SubnetMappings
        }
        
        foreach ($type in $stats.MappingsByType.Keys) {
            $exportData.Statistics += @{
                'Statistic' = "$type Mappings"
                'Value' = $stats.MappingsByType[$type]
            }
        }
        
        # Prepare metadata
        $exportData.Metadata += @{
            'Property' = 'Export Date'
            'Value' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
        $exportData.Metadata += @{
            'Property' = 'Export Version'
            'Value' = '1.0'
        }
        $exportData.Metadata += @{
            'Property' = 'Tool Name'
            'Value' = 'VMware vCenter Inventory & Performance Collector'
        }
        $exportData.Metadata += @{
            'Property' = 'Security Classification'
            'Value' = 'CONFIDENTIAL - Contains Original to Anonymized Mappings'
        }
        
        return $exportData
    }
    
    # Validate mapping data integrity
    [bool] ValidateMappingIntegrity([hashtable] $MappingData) {
        try {
            $this.WriteLog("Validating mapping data integrity", "Debug")
            
            # Check for duplicate original values within same type
            $originalValues = @{}
            foreach ($mapping in $MappingData.MappingData) {
                $key = "$($mapping.'Value Type'):$($mapping.'Original Value')"
                if ($originalValues.ContainsKey($key)) {
                    $this.WriteLog("Duplicate original value found: $key", "Error")
                    return $false
                }
                $originalValues[$key] = $true
            }
            
            # Check for duplicate anonymized values within same type
            $anonymizedValues = @{}
            foreach ($mapping in $MappingData.MappingData) {
                $key = "$($mapping.'Value Type'):$($mapping.'Anonymized Value')"
                if ($anonymizedValues.ContainsKey($key)) {
                    $this.WriteLog("Duplicate anonymized value found: $key", "Error")
                    return $false
                }
                $anonymizedValues[$key] = $true
            }
            
            # Validate subnet mappings
            foreach ($subnetMapping in $MappingData.SubnetMappings) {
                if ([string]::IsNullOrEmpty($subnetMapping.'Original Subnet') -or 
                    [string]::IsNullOrEmpty($subnetMapping.'Anonymized Subnet')) {
                    $this.WriteLog("Invalid subnet mapping found", "Error")
                    return $false
                }
            }
            
            $this.WriteLog("Mapping data integrity validation passed", "Debug")
            return $true
        }
        catch {
            $this.WriteLog("Error during mapping integrity validation: $($_.Exception.Message)", "Error")
            return $false
        }
    }
    
    # Export mapping data to Excel format
    [void] ExportToExcel([hashtable] $MappingData, [string] $FilePath) {
        try {
            $this.WriteLog("Exporting mapping data to Excel format", "Debug")
            
            # Check if ImportExcel module is available
            if (!(Get-Module -ListAvailable -Name ImportExcel)) {
                $this.WriteLog("ImportExcel module not available, using CSV export as fallback", "Warning")
                $this.ExportToCSVFallback($MappingData, $FilePath)
                return
            }
            
            # Import the ImportExcel module
            Import-Module ImportExcel -Force
            
            # Create Excel workbook with multiple worksheets
            $excelParams = @{
                Path = $FilePath
                AutoSize = $true
                AutoFilter = $true
                BoldTopRow = $true
                FreezeTopRow = $true
                WorksheetName = 'Value Mappings'
            }
            
            # Export main mapping data
            if ($MappingData.MappingData.Count -gt 0) {
                $MappingData.MappingData | Export-Excel @excelParams
            }
            
            # Export subnet mappings
            if ($MappingData.SubnetMappings.Count -gt 0) {
                $subnetParams = $excelParams.Clone()
                $subnetParams.WorksheetName = 'Subnet Mappings'
                $MappingData.SubnetMappings | Export-Excel @subnetParams
            }
            
            # Export statistics
            if ($MappingData.Statistics.Count -gt 0) {
                $statsParams = $excelParams.Clone()
                $statsParams.WorksheetName = 'Statistics'
                $MappingData.Statistics | Export-Excel @statsParams
            }
            
            # Export metadata
            if ($MappingData.Metadata.Count -gt 0) {
                $metadataParams = $excelParams.Clone()
                $metadataParams.WorksheetName = 'Metadata'
                $MappingData.Metadata | Export-Excel @metadataParams
            }
            
            $this.WriteLog("Successfully exported mapping data to Excel: $FilePath", "Debug")
        }
        catch {
            $this.WriteLog("Error exporting to Excel, falling back to CSV: $($_.Exception.Message)", "Warning")
            $this.ExportToCSVFallback($MappingData, $FilePath)
        }
    }
    
    # Fallback CSV export when Excel is not available
    [void] ExportToCSVFallback([hashtable] $MappingData, [string] $FilePath) {
        try {
            $this.WriteLog("Using CSV fallback export", "Information")
            
            # Change extension to .csv
            $csvFilePath = [System.IO.Path]::ChangeExtension($FilePath, '.csv')
            
            # Combine all data into single CSV with type indicator
            $combinedData = @()
            
            # Add mapping data
            foreach ($mapping in $MappingData.MappingData) {
                $combinedData += [PSCustomObject]@{
                    'Data Type' = 'Value Mapping'
                    'Original Value' = $mapping.'Original Value'
                    'Anonymized Value' = $mapping.'Anonymized Value'
                    'Value Type' = $mapping.'Value Type'
                    'Created Date' = $mapping.'Created Date'
                    'Mapping ID' = $mapping.'Mapping ID'
                    'Additional Info' = ''
                }
            }
            
            # Add subnet mappings
            foreach ($subnet in $MappingData.SubnetMappings) {
                $combinedData += [PSCustomObject]@{
                    'Data Type' = 'Subnet Mapping'
                    'Original Value' = $subnet.'Original Subnet'
                    'Anonymized Value' = $subnet.'Anonymized Subnet'
                    'Value Type' = $subnet.'Mapping Type'
                    'Created Date' = $subnet.'Created Date'
                    'Mapping ID' = ''
                    'Additional Info' = ''
                }
            }
            
            # Add statistics
            foreach ($stat in $MappingData.Statistics) {
                $combinedData += [PSCustomObject]@{
                    'Data Type' = 'Statistic'
                    'Original Value' = $stat.Statistic
                    'Anonymized Value' = $stat.Value
                    'Value Type' = 'Statistics'
                    'Created Date' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    'Mapping ID' = ''
                    'Additional Info' = ''
                }
            }
            
            # Add metadata
            foreach ($meta in $MappingData.Metadata) {
                $combinedData += [PSCustomObject]@{
                    'Data Type' = 'Metadata'
                    'Original Value' = $meta.Property
                    'Anonymized Value' = $meta.Value
                    'Value Type' = 'Metadata'
                    'Created Date' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    'Mapping ID' = ''
                    'Additional Info' = ''
                }
            }
            
            # Export to CSV
            $combinedData | Export-Csv -Path $csvFilePath -NoTypeInformation -Encoding UTF8
            
            $this.WriteLog("Successfully exported mapping data to CSV: $csvFilePath", "Information")
        }
        catch {
            $this.WriteLog("Error during CSV fallback export: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Apply file protection and access controls
    [void] ApplyFileProtection([string] $FilePath) {
        try {
            $this.WriteLog("Applying file protection to mapping file", "Debug")
            
            if (!(Test-Path $FilePath)) {
                $this.WriteLog("File does not exist, cannot apply protection: $FilePath", "Warning")
                return
            }
            
            # Set file attributes to read-only
            $file = Get-Item $FilePath
            $file.Attributes = $file.Attributes -bor [System.IO.FileAttributes]::ReadOnly
            
            # On Windows, try to set additional security attributes
            $isWindowsPlatform = $false
            try {
                # Check if we're on Windows
                if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
                    $isWindowsPlatform = $true
                }
            } catch {
                # Fallback to environment variable check
                $isWindowsPlatform = $env:OS -like "*Windows*"
            }
            if ($isWindowsPlatform) {
                try {
                    # Set file as hidden to reduce accidental access
                    $file.Attributes = $file.Attributes -bor [System.IO.FileAttributes]::Hidden
                    
                    # Try to set NTFS permissions (requires appropriate permissions and Get-Acl availability)
                    if (Get-Command Get-Acl -ErrorAction SilentlyContinue) {
                        $acl = Get-Acl $FilePath
                        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                            [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                            "FullControl",
                            "Allow"
                        )
                        $acl.SetAccessRule($accessRule)
                        Set-Acl -Path $FilePath -AclObject $acl
                        
                        $this.WriteLog("Applied Windows-specific file protection", "Debug")
                    } else {
                        $this.WriteLog("Get-Acl not available, skipping ACL configuration", "Debug")
                    }
                }
                catch {
                    $this.WriteLog("Could not apply advanced Windows file protection: $($_.Exception.Message)", "Debug")
                }
            }
            
            # On Unix-like systems, set restrictive permissions
            $isUnixPlatform = $false
            try {
                # Check if we're on Unix-like system
                if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Unix) {
                    $isUnixPlatform = $true
                }
            } catch {
                # Fallback to environment variable check
                $isUnixPlatform = $env:OS -notlike "*Windows*"
            }
            if ($isUnixPlatform) {
                try {
                    chmod 600 $FilePath
                    $this.WriteLog("Applied Unix-style file protection (600)", "Debug")
                }
                catch {
                    $this.WriteLog("Could not apply Unix file protection: $($_.Exception.Message)", "Debug")
                }
            }
            
            $this.WriteLog("File protection applied successfully", "Debug")
        }
        catch {
            $this.WriteLog("Error applying file protection: $($_.Exception.Message)", "Warning")
            # Don't throw here as file protection is not critical for functionality
        }
    }
    
    # Generate secure mapping filename with timestamp
    [string] GenerateSecureMappingFileName([string] $BasePath) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $fileName = "Anonymization_Mapping_$timestamp.xlsx"
        
        if (![string]::IsNullOrEmpty($BasePath)) {
            return Join-Path $BasePath $fileName
        }
        
        return $fileName
    }
    
    # Import mapping file (for de-anonymization scenarios)
    [void] ImportMappingFile([string] $FilePath) {
        try {
            $this.WriteLog("Importing anonymization mapping file from: $FilePath", "Information")
            
            if (!(Test-Path $FilePath)) {
                throw "Mapping file does not exist: $FilePath"
            }
            
            # Clear existing mappings
            $this.ResetMappings()
            
            # Determine file type and import accordingly
            $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
            
            switch ($extension) {
                ".xlsx" { $this.ImportFromExcel($FilePath) }
                ".csv" { $this.ImportFromCSV($FilePath) }
                default { throw "Unsupported mapping file format: $extension" }
            }
            
            $this.WriteLog("Successfully imported anonymization mapping file", "Information")
        }
        catch {
            $this.WriteLog("Error importing mapping file: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Import mappings from Excel file
    [void] ImportFromExcel([string] $FilePath) {
        try {
            if (!(Get-Module -ListAvailable -Name ImportExcel)) {
                throw "ImportExcel module is required to import Excel mapping files"
            }
            
            Import-Module ImportExcel -Force
            
            # Import value mappings
            $valueMappings = Import-Excel -Path $FilePath -WorksheetName 'Value Mappings'
            foreach ($mapping in $valueMappings) {
                $this.AddMapping($mapping.'Original Value', $mapping.'Anonymized Value', $mapping.'Value Type')
            }
            
            # Import subnet mappings
            try {
                $subnetMappings = Import-Excel -Path $FilePath -WorksheetName 'Subnet Mappings'
                foreach ($subnet in $subnetMappings) {
                    $this.IPSubnetMappings[$subnet.'Original Subnet'] = $subnet.'Anonymized Subnet'
                }
            }
            catch {
                $this.WriteLog("No subnet mappings found in Excel file", "Debug")
            }
            
            $this.WriteLog("Imported mappings from Excel file", "Debug")
        }
        catch {
            $this.WriteLog("Error importing from Excel: $($_.Exception.Message)", "Error")
            throw
        }
    }
    
    # Import mappings from CSV file
    [void] ImportFromCSV([string] $FilePath) {
        try {
            $csvData = Import-Csv -Path $FilePath
            
            foreach ($row in $csvData) {
                switch ($row.'Data Type') {
                    'Value Mapping' {
                        $this.AddMapping($row.'Original Value', $row.'Anonymized Value', $row.'Value Type')
                    }
                    'Subnet Mapping' {
                        $this.IPSubnetMappings[$row.'Original Value'] = $row.'Anonymized Value'
                    }
                }
            }
            
            $this.WriteLog("Imported mappings from CSV file", "Debug")
        }
        catch {
            $this.WriteLog("Error importing from CSV: $($_.Exception.Message)", "Error")
            throw
        }
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