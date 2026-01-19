#
# VMDataModel.ps1 - Complete VM data model with 47+ fields
#
# Implements the comprehensive VM data structure as specified in the requirements
# with exact field definitions, validation, and default value handling.
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

class VMDataModel : IVMwareDataModel {
    # Basic Information (9 fields)
    [string] $Name                    # VM.Name from Get-VM
    [string] $DNSName                 # VM.Guest.HostName from Get-VM
    [string] $IPAddress               # VM.Guest.IPAddress[0] from Get-VM
    [string] $OperatingSystem         # VM.Guest.OSFullName from Get-VM
    [string] $OSVersion               # Derived from OperatingSystem or VMView.Config.GuestId
    [string] $GuestId                 # VMView.Config.GuestId from Get-View
    [string] $PowerState              # VM.PowerState.ToString() from Get-VM
    [string] $ConnectionState         # VMView.Runtime.ConnectionState.ToString()
    [string] $GuestState              # VMView.Guest.GuestState.ToString()
    
    # Hardware Configuration (4 fields)
    [int] $NumCPUs                    # VM.NumCpu from Get-VM
    [double] $MemoryMB                # VM.MemoryMB from Get-VM
    [double] $TotalStorageGB          # Calculated from VM storage or VM.UsedSpaceGB
    [string] $HardwareVersion         # VMView.Config.Version from Get-View
    
    # Performance Metrics (6 fields)
    [double] $MaxCpuUsagePct          # Maximum CPU usage % over collection period
    [double] $AvgCpuUsagePct          # Average CPU usage % over collection period
    [double] $MaxRamUsagePct          # Maximum memory usage % over collection period
    [double] $AvgRamUsagePct          # Average memory usage % over collection period
    [int] $PerformanceDataPoints      # Count of actual performance data points
    [string] $PerformanceCollectionPeriod  # Description of collection period
    
    # Infrastructure Details (6 fields)
    [string] $HostName                # VM.VMHost.Name from Get-VM
    [string] $ClusterName             # VM.VMHost.Parent.Name from Get-VM
    [string] $DatacenterName          # Derived from VM location hierarchy
    [string] $DatastoreName           # Primary datastore from VM.DatastoreIdList
    [string] $NetworkName             # Primary network from VM network adapters
    [string] $ResourcePoolName        # VM.ResourcePool.Name from Get-VM
    
    # VM Configuration (6 fields)
    [string] $VMwareToolsStatus       # VM.ExtensionData.Guest.ToolsStatus
    [string] $VMwareToolsVersion      # VM.ExtensionData.Guest.ToolsVersion
    [string] $VMPathName              # VMView.Config.Files.VmPathName
    [string] $VMConfigFile            # Same as VMPathName
    [bool] $TemplateFlag              # VM.ExtensionData.Config.Template
    [string] $StorageFormat           # Derived from VM disk configuration
    
    # Storage Information (3 fields)
    [double] $StorageCommittedGB      # VM.ProvisionedSpaceGB from Get-VM
    [double] $StorageUncommittedGB    # TotalStorageGB - StorageCommittedGB
    [string] $DiskMode                # Derived from VM disk configuration
    
    # Network Information (5 fields)
    [string] $NetworkAdapter1         # First network adapter name
    [string] $NetworkAdapter2         # Second network adapter name (if exists)
    [string] $NetworkAdapter3         # Third network adapter name (if exists)
    [string] $NetworkAdapter4         # Fourth network adapter name (if exists)
    [string] $MACAddress              # Primary network adapter MAC address
    
    # Resource Management (6 fields)
    [int] $CPUReservation             # VM CPU reservation in MHz
    [int] $CPULimit                   # VM CPU limit in MHz
    [int] $MemoryReservation          # VM memory reservation in MB
    [int] $MemoryLimit                # VM memory limit in MB
    [string] $CPUShares               # VM CPU shares setting
    [string] $MemoryShares            # VM memory shares setting
    
    # Metadata (8 fields)
    [string] $VMId                    # VM.Id from Get-VM
    [string] $VMUuid                  # VMView.Config.Uuid from Get-View
    [string] $InstanceUuid            # VMView.Config.InstanceUuid from Get-View
    [string] $BiosUuid                # VMView.Config.Hardware.SystemInfo.Uuid
    [datetime] $CreationDate          # Derived from VM creation timestamp
    [datetime] $LastModified          # Derived from VM modification timestamp
    [string] $Annotation              # VM.Notes from Get-VM
    [string] $Notes                   # Same as Annotation
    
    # Snapshot Information (3 fields)
    [int] $SnapshotCount              # Count of VM snapshots
    [double] $SnapshotSizeGB          # Total size of all snapshots in GB
    [string] $SnapshotCreated         # Creation date of most recent snapshot
    
    # Additional Fields (6 fields)
    [string] $FolderName              # VM.Folder.Name from Get-VM
    [string] $CustomField1            # User-defined custom field 1
    [string] $CustomField2            # User-defined custom field 2
    [string] $CustomField3            # User-defined custom field 3
    [string] $Environment             # Derived from VM location or custom attributes
    [string] $Application             # Derived from VM name patterns or custom attributes
    [string] $Owner                   # Derived from VM custom attributes
    [datetime] $CollectionDate        # Timestamp when data was collected
    
    # Constructor with default values
    VMDataModel() {
        $this.PowerState = "Unknown"
        $this.ConnectionState = "Unknown"
        $this.GuestState = "Unknown"
        $this.VMwareToolsStatus = "Unknown"
        $this.MaxCpuUsagePct = 0.0
        $this.AvgCpuUsagePct = 0.0
        $this.MaxRamUsagePct = 0.0
        $this.AvgRamUsagePct = 0.0
        $this.PerformanceDataPoints = 0
        $this.SnapshotCount = 0
        $this.SnapshotSizeGB = 0.0
        $this.TemplateFlag = $false
        $this.CollectionDate = Get-Date
        $this.CPUReservation = 0
        $this.CPULimit = -1  # -1 indicates unlimited
        $this.MemoryReservation = 0
        $this.MemoryLimit = -1  # -1 indicates unlimited
        $this.CPUShares = "Normal"
        $this.MemoryShares = "Normal"
        $this.StorageFormat = "Unknown"
        $this.DiskMode = "Unknown"
        $this.PerformanceCollectionPeriod = "Not collected"
    }
    
    # Validation method implementation
    [bool] ValidateData() {
        $isValid = $true
        $validationErrors = @()
        
        # Check required fields
        if ([string]::IsNullOrEmpty($this.Name)) {
            $validationErrors += "VM Name is required"
            $isValid = $false
        }
        
        if ($this.NumCPUs -le 0) {
            $validationErrors += "NumCPUs must be greater than 0, got: $($this.NumCPUs)"
            $isValid = $false
        }
        
        if ($this.MemoryMB -le 0) {
            $validationErrors += "MemoryMB must be greater than 0, got: $($this.MemoryMB)"
            $isValid = $false
        }
        
        # Validate performance percentages (0-100 range)
        $performanceFields = @{
            'MaxCpuUsagePct' = $this.MaxCpuUsagePct
            'AvgCpuUsagePct' = $this.AvgCpuUsagePct
            'MaxRamUsagePct' = $this.MaxRamUsagePct
            'AvgRamUsagePct' = $this.AvgRamUsagePct
        }
        
        foreach ($field in $performanceFields.GetEnumerator()) {
            if ($field.Value -lt 0 -or $field.Value -gt 100) {
                $validationErrors += "$($field.Key) must be between 0 and 100, got: $($field.Value)"
                $isValid = $false
            }
        }
        
        # Validate storage values
        if ($this.TotalStorageGB -lt 0) {
            $validationErrors += "TotalStorageGB cannot be negative, got: $($this.TotalStorageGB)"
            $isValid = $false
        }
        
        if ($this.StorageCommittedGB -lt 0) {
            $validationErrors += "StorageCommittedGB cannot be negative, got: $($this.StorageCommittedGB)"
            $isValid = $false
        }
        
        # Log validation errors if any
        if ($validationErrors.Count -gt 0) {
            Write-Warning "VM Data validation failed for '$($this.Name)': $($validationErrors -join '; ')"
        }
        
        return $isValid
    }
    
    # Convert to hashtable for easy manipulation
    [hashtable] ToHashtable() {
        $hashtable = @{}
        
        # Get all properties using reflection
        $properties = $this.GetType().GetProperties()
        
        foreach ($property in $properties) {
            $hashtable[$property.Name] = $property.GetValue($this)
        }
        
        return $hashtable
    }
    
    # String representation
    [string] ToString() {
        return "VMDataModel: Name='$($this.Name)', PowerState='$($this.PowerState)', CPUs=$($this.NumCPUs), Memory=$($this.MemoryMB)MB, Storage=$($this.TotalStorageGB)GB"
    }
    
    # Set default performance values for powered-off VMs
    [void] SetDefaultPerformanceValues() {
        if ($this.PowerState -eq "PoweredOff") {
            $this.MaxCpuUsagePct = 25.0
            $this.AvgCpuUsagePct = 25.0
            $this.MaxRamUsagePct = 60.0
            $this.AvgRamUsagePct = 60.0
            $this.PerformanceDataPoints = 1
            $this.PerformanceCollectionPeriod = "Default values (VM powered off)"
        }
    }
    
    # Calculate storage uncommitted based on total and committed
    [void] CalculateStorageUncommitted() {
        if ($this.TotalStorageGB -gt 0 -and $this.StorageCommittedGB -gt 0) {
            $this.StorageUncommittedGB = [Math]::Max(0, $this.TotalStorageGB - $this.StorageCommittedGB)
        } else {
            $this.StorageUncommittedGB = 0
        }
    }
    
    # Get field count for validation
    [int] GetFieldCount() {
        return ($this.GetType().GetProperties() | Where-Object { $_.Name -ne 'GetType' }).Count
    }
    
    # Check if VM has performance data
    [bool] HasPerformanceData() {
        return $this.PerformanceDataPoints -gt 0 -and $this.PerformanceCollectionPeriod -ne "Not collected"
    }
    
    # Get VM size category for optimization
    [string] GetVMSizeCategory() {
        if ($this.MemoryMB -le 4096) { return "Small" }
        elseif ($this.MemoryMB -le 16384) { return "Medium" }
        elseif ($this.MemoryMB -le 65536) { return "Large" }
        else { return "XLarge" }
    }
}