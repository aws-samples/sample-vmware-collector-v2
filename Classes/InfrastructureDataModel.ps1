#
# InfrastructureDataModel.ps1 - Infrastructure data models for hosts, clusters, and datacenters
#
# Implements data structures for VMware infrastructure components to support
# relationship mapping and infrastructure-based aggregations.
#

# Import base interface
if (Test-Path "$PSScriptRoot\Interfaces.ps1") {
    . "$PSScriptRoot\Interfaces.ps1"
} else {
    # Define minimal interface if not found
    class IVMwareDataModel {
        [bool] ValidateData() { throw "ValidateData method must be implemented by derived class" }
        [hashtable] ToHashtable() { throw "ToHashtable method must be implemented by derived class" }
        [string] ToString() { throw "ToString method must be implemented by derived class" }
    }
}

class InfrastructureDataModel : IVMwareDataModel {
    [string] $Name                    # Infrastructure component name
    [string] $Type                    # Type: Host, Cluster, Datacenter, Datastore, Network
    [string] $Id                      # Unique identifier
    [datetime] $CollectionDate        # When data was collected
    
    # Constructor
    InfrastructureDataModel() {
        $this.CollectionDate = Get-Date
    }
    
    # Base validation
    [bool] ValidateData() {
        $isValid = $true
        
        if ([string]::IsNullOrEmpty($this.Name)) {
            Write-Warning "Infrastructure component Name is required"
            $isValid = $false
        }
        
        if ([string]::IsNullOrEmpty($this.Type)) {
            Write-Warning "Infrastructure component Type is required"
            $isValid = $false
        }
        
        return $isValid
    }
    
    # Convert to hashtable
    [hashtable] ToHashtable() {
        return @{
            Name = $this.Name
            Type = $this.Type
            Id = $this.Id
            CollectionDate = $this.CollectionDate
        }
    }
    
    # String representation
    [string] ToString() {
        return "InfrastructureDataModel: Name='$($this.Name)', Type='$($this.Type)'"
    }
}

class HostDataModel : InfrastructureDataModel {
    # Host-specific properties
    [string] $ClusterName             # Parent cluster name
    [string] $DatacenterName          # Parent datacenter name
    [string] $ConnectionState         # Host connection state
    [string] $PowerState              # Host power state
    [string] $Version                 # ESXi version
    [string] $Build                   # ESXi build number
    [int] $NumCpuCores                # Total CPU cores
    [int] $NumCpuThreads              # Total CPU threads
    [int] $CpuMhz                     # CPU speed in MHz
    [double] $MemoryTotalGB           # Total memory in GB
    [double] $MemoryUsageGB           # Used memory in GB
    [int] $NumVMs                     # Number of VMs on host
    [array] $VMList                   # List of VM names on this host
    [array] $DatastoreList            # List of accessible datastores
    [array] $NetworkList              # List of available networks
    
    # Constructor
    HostDataModel() : base() {
        $this.Type = "Host"
        $this.VMList = @()
        $this.DatastoreList = @()
        $this.NetworkList = @()
        $this.NumVMs = 0
    }
    
    # Host-specific validation
    [bool] ValidateData() {
        $isValid = ([InfrastructureDataModel]$this).ValidateData()
        
        if ($this.NumCpuCores -le 0) {
            Write-Warning "Host NumCpuCores must be greater than 0"
            $isValid = $false
        }
        
        if ($this.MemoryTotalGB -le 0) {
            Write-Warning "Host MemoryTotalGB must be greater than 0"
            $isValid = $false
        }
        
        if ($this.NumVMs -ne $this.VMList.Count) {
            Write-Warning "Host NumVMs ($($this.NumVMs)) does not match VMList count ($($this.VMList.Count))"
            $isValid = $false
        }
        
        return $isValid
    }
    
    # Convert to hashtable with host-specific properties
    [hashtable] ToHashtable() {
        $baseHashtable = ([InfrastructureDataModel]$this).ToHashtable()
        
        $hostProperties = @{
            ClusterName = $this.ClusterName
            DatacenterName = $this.DatacenterName
            ConnectionState = $this.ConnectionState
            PowerState = $this.PowerState
            Version = $this.Version
            Build = $this.Build
            NumCpuCores = $this.NumCpuCores
            NumCpuThreads = $this.NumCpuThreads
            CpuMhz = $this.CpuMhz
            MemoryTotalGB = $this.MemoryTotalGB
            MemoryUsageGB = $this.MemoryUsageGB
            NumVMs = $this.NumVMs
            VMList = $this.VMList
            DatastoreList = $this.DatastoreList
            NetworkList = $this.NetworkList
        }
        
        foreach ($property in $hostProperties.GetEnumerator()) {
            $baseHashtable[$property.Key] = $property.Value
        }
        
        return $baseHashtable
    }
    
    # Add VM to host
    [void] AddVM([string] $vmName) {
        if (-not [string]::IsNullOrEmpty($vmName) -and $vmName -notin $this.VMList) {
            $this.VMList += $vmName
            $this.NumVMs = $this.VMList.Count
        }
    }
    
    # Remove VM from host
    [void] RemoveVM([string] $vmName) {
        $this.VMList = $this.VMList | Where-Object { $_ -ne $vmName }
        $this.NumVMs = $this.VMList.Count
    }
    
    # Calculate memory utilization percentage
    [double] GetMemoryUtilizationPercent() {
        if ($this.MemoryTotalGB -gt 0) {
            return [Math]::Round(($this.MemoryUsageGB / $this.MemoryTotalGB) * 100, 2)
        }
        return 0.0
    }
    
    # Get host capacity summary
    [hashtable] GetCapacitySummary() {
        return @{
            TotalCpuCores = $this.NumCpuCores
            TotalMemoryGB = $this.MemoryTotalGB
            UsedMemoryGB = $this.MemoryUsageGB
            MemoryUtilizationPct = $this.GetMemoryUtilizationPercent()
            VMCount = $this.NumVMs
            DatastoreCount = $this.DatastoreList.Count
            NetworkCount = $this.NetworkList.Count
        }
    }
}

class ClusterDataModel : InfrastructureDataModel {
    # Cluster-specific properties
    [string] $DatacenterName          # Parent datacenter name
    [bool] $DRSEnabled                # DRS enabled status
    [bool] $HAEnabled                 # HA enabled status
    [string] $DRSAutomationLevel      # DRS automation level
    [int] $NumHosts                   # Number of hosts in cluster
    [int] $NumVMs                     # Total number of VMs in cluster
    [array] $HostList                 # List of host names in cluster
    [array] $VMList                   # List of VM names in cluster
    [double] $TotalCpuCores           # Aggregated CPU cores from all hosts
    [double] $TotalMemoryGB           # Aggregated memory from all hosts
    [double] $UsedMemoryGB            # Aggregated used memory from all hosts
    
    # Constructor
    ClusterDataModel() : base() {
        $this.Type = "Cluster"
        $this.HostList = @()
        $this.VMList = @()
        $this.NumHosts = 0
        $this.NumVMs = 0
        $this.DRSEnabled = $false
        $this.HAEnabled = $false
    }
    
    # Cluster-specific validation
    [bool] ValidateData() {
        $isValid = ([InfrastructureDataModel]$this).ValidateData()
        
        if ($this.NumHosts -ne $this.HostList.Count) {
            Write-Warning "Cluster NumHosts ($($this.NumHosts)) does not match HostList count ($($this.HostList.Count))"
            $isValid = $false
        }
        
        if ($this.NumVMs -ne $this.VMList.Count) {
            Write-Warning "Cluster NumVMs ($($this.NumVMs)) does not match VMList count ($($this.VMList.Count))"
            $isValid = $false
        }
        
        return $isValid
    }
    
    # Convert to hashtable with cluster-specific properties
    [hashtable] ToHashtable() {
        $baseHashtable = ([InfrastructureDataModel]$this).ToHashtable()
        
        $clusterProperties = @{
            DatacenterName = $this.DatacenterName
            DRSEnabled = $this.DRSEnabled
            HAEnabled = $this.HAEnabled
            DRSAutomationLevel = $this.DRSAutomationLevel
            NumHosts = $this.NumHosts
            NumVMs = $this.NumVMs
            HostList = $this.HostList
            VMList = $this.VMList
            TotalCpuCores = $this.TotalCpuCores
            TotalMemoryGB = $this.TotalMemoryGB
            UsedMemoryGB = $this.UsedMemoryGB
        }
        
        foreach ($property in $clusterProperties.GetEnumerator()) {
            $baseHashtable[$property.Key] = $property.Value
        }
        
        return $baseHashtable
    }
    
    # Add host to cluster
    [void] AddHost([string] $hostName) {
        if ($hostName -notin $this.HostList) {
            $this.HostList += $hostName
            $this.NumHosts = $this.HostList.Count
        }
    }
    
    # Add VM to cluster
    [void] AddVM([string] $vmName) {
        if (-not [string]::IsNullOrEmpty($vmName) -and $vmName -notin $this.VMList) {
            $this.VMList += $vmName
            $this.NumVMs = $this.VMList.Count
        }
    }
    
    # Calculate cluster resource utilization
    [hashtable] GetResourceUtilization() {
        $memoryUtilizationPct = if ($this.TotalMemoryGB -gt 0) {
            [Math]::Round(($this.UsedMemoryGB / $this.TotalMemoryGB) * 100, 2)
        } else { 0.0 }
        
        return @{
            TotalCpuCores = $this.TotalCpuCores
            TotalMemoryGB = $this.TotalMemoryGB
            UsedMemoryGB = $this.UsedMemoryGB
            MemoryUtilizationPct = $memoryUtilizationPct
            HostCount = $this.NumHosts
            VMCount = $this.NumVMs
            AvgVMsPerHost = if ($this.NumHosts -gt 0) { [Math]::Round($this.NumVMs / $this.NumHosts, 1) } else { 0 }
        }
    }
}

class DatastoreDataModel : InfrastructureDataModel {
    # Datastore-specific properties
    [string] $DatacenterName          # Parent datacenter name
    [string] $DatastoreType           # VMFS, NFS, vSAN, etc.
    [double] $CapacityGB              # Total capacity in GB
    [double] $FreeSpaceGB             # Free space in GB
    [double] $UsedSpaceGB             # Used space in GB
    [int] $NumVMs                     # Number of VMs using this datastore
    [array] $VMList                   # List of VM names using this datastore
    [array] $HostList                 # List of hosts with access to this datastore
    [bool] $MaintenanceMode           # Maintenance mode status
    [string] $FileSystemVersion       # File system version
    
    # Constructor
    DatastoreDataModel() : base() {
        $this.Type = "Datastore"
        $this.VMList = @()
        $this.HostList = @()
        $this.NumVMs = 0
        $this.MaintenanceMode = $false
    }
    
    # Datastore-specific validation
    [bool] ValidateData() {
        $isValid = ([InfrastructureDataModel]$this).ValidateData()
        
        if ($this.CapacityGB -le 0) {
            Write-Warning "Datastore CapacityGB must be greater than 0"
            $isValid = $false
        }
        
        if ($this.FreeSpaceGB -lt 0) {
            Write-Warning "Datastore FreeSpaceGB cannot be negative"
            $isValid = $false
        }
        
        if ($this.UsedSpaceGB -lt 0) {
            Write-Warning "Datastore UsedSpaceGB cannot be negative"
            $isValid = $false
        }
        
        # Check capacity consistency
        $calculatedUsed = $this.CapacityGB - $this.FreeSpaceGB
        if ([Math]::Abs($calculatedUsed - $this.UsedSpaceGB) -gt 0.1) {
            Write-Warning "Datastore capacity inconsistency: Capacity=$($this.CapacityGB)GB, Free=$($this.FreeSpaceGB)GB, Used=$($this.UsedSpaceGB)GB"
        }
        
        return $isValid
    }
    
    # Convert to hashtable with datastore-specific properties
    [hashtable] ToHashtable() {
        $baseHashtable = ([InfrastructureDataModel]$this).ToHashtable()
        
        $datastoreProperties = @{
            DatacenterName = $this.DatacenterName
            DatastoreType = $this.DatastoreType
            CapacityGB = $this.CapacityGB
            FreeSpaceGB = $this.FreeSpaceGB
            UsedSpaceGB = $this.UsedSpaceGB
            NumVMs = $this.NumVMs
            VMList = $this.VMList
            HostList = $this.HostList
            MaintenanceMode = $this.MaintenanceMode
            FileSystemVersion = $this.FileSystemVersion
        }
        
        foreach ($property in $datastoreProperties.GetEnumerator()) {
            $baseHashtable[$property.Key] = $property.Value
        }
        
        return $baseHashtable
    }
    
    # Calculate utilization percentage
    [double] GetUtilizationPercent() {
        if ($this.CapacityGB -gt 0) {
            return [Math]::Round(($this.UsedSpaceGB / $this.CapacityGB) * 100, 2)
        }
        return 0.0
    }
    
    # Add VM to datastore
    [void] AddVM([string] $vmName) {
        if (-not [string]::IsNullOrEmpty($vmName) -and $vmName -notin $this.VMList) {
            $this.VMList += $vmName
            $this.NumVMs = $this.VMList.Count
        }
    }
    
    # Get datastore health status
    [hashtable] GetHealthStatus() {
        $utilizationPct = $this.GetUtilizationPercent()
        
        $healthStatus = "Healthy"
        if ($utilizationPct -gt 90) {
            $healthStatus = "Critical"
        } elseif ($utilizationPct -gt 80) {
            $healthStatus = "Warning"
        }
        
        return @{
            HealthStatus = $healthStatus
            UtilizationPct = $utilizationPct
            CapacityGB = $this.CapacityGB
            FreeSpaceGB = $this.FreeSpaceGB
            UsedSpaceGB = $this.UsedSpaceGB
            VMCount = $this.NumVMs
            HostCount = $this.HostList.Count
            MaintenanceMode = $this.MaintenanceMode
        }
    }
}

class NetworkDataModel : InfrastructureDataModel {
    # Network-specific properties
    [string] $DatacenterName          # Parent datacenter name
    [string] $NetworkType             # Standard, Distributed, etc.
    [string] $VLANId                  # VLAN identifier
    [int] $NumVMs                     # Number of VMs using this network
    [array] $VMList                   # List of VM names using this network
    [array] $HostList                 # List of hosts with access to this network
    [bool] $IsActive                  # Network active status
    [string] $SwitchName              # Associated switch name
    
    # Constructor
    NetworkDataModel() : base() {
        $this.Type = "Network"
        $this.VMList = @()
        $this.HostList = @()
        $this.NumVMs = 0
        $this.IsActive = $true
    }
    
    # Network-specific validation
    [bool] ValidateData() {
        $isValid = ([InfrastructureDataModel]$this).ValidateData()
        
        if ($this.NumVMs -ne $this.VMList.Count) {
            Write-Warning "Network NumVMs ($($this.NumVMs)) does not match VMList count ($($this.VMList.Count))"
            $isValid = $false
        }
        
        return $isValid
    }
    
    # Convert to hashtable with network-specific properties
    [hashtable] ToHashtable() {
        $baseHashtable = ([InfrastructureDataModel]$this).ToHashtable()
        
        $networkProperties = @{
            DatacenterName = $this.DatacenterName
            NetworkType = $this.NetworkType
            VLANId = $this.VLANId
            NumVMs = $this.NumVMs
            VMList = $this.VMList
            HostList = $this.HostList
            IsActive = $this.IsActive
            SwitchName = $this.SwitchName
        }
        
        foreach ($property in $networkProperties.GetEnumerator()) {
            $baseHashtable[$property.Key] = $property.Value
        }
        
        return $baseHashtable
    }
    
    # Add VM to network
    [void] AddVM([string] $vmName) {
        if (-not [string]::IsNullOrEmpty($vmName) -and $vmName -notin $this.VMList) {
            $this.VMList += $vmName
            $this.NumVMs = $this.VMList.Count
        }
    }
    
    # Remove VM from network
    [void] RemoveVM([string] $vmName) {
        $this.VMList = $this.VMList | Where-Object { $_ -ne $vmName }
        $this.NumVMs = $this.VMList.Count
    }
    
    # Get network summary
    [hashtable] GetNetworkSummary() {
        return @{
            Name = $this.Name
            Type = $this.NetworkType
            VLANId = $this.VLANId
            VMCount = $this.NumVMs
            HostCount = $this.HostList.Count
            IsActive = $this.IsActive
            SwitchName = $this.SwitchName
        }
    }
}