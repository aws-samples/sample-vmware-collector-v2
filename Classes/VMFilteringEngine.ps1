#
# VMFilteringEngine.ps1 - Handles VM filtering logic
#
# Replicates VM filtering logic from vmware-collector.ps1
#

using module .\Interfaces.ps1

class VMFilteringEngine {
    [ILogger] $Logger
    
    VMFilteringEngine([ILogger] $Logger) {
        $this.Logger = $Logger
    }
    
    # Main VM filtering method
    [hashtable] FilterVMs([hashtable] $Parameters, [object] $CacheManager) {
        try {
            $this.Logger.WriteInformation("Retrieving VM inventory...")
            
            # Check if vmListFile takes precedence
            if ($Parameters.ContainsKey('vmListFile') -and -not [string]::IsNullOrEmpty($Parameters.vmListFile)) {
                return $this.FilterVMsFromFile($Parameters, $CacheManager)
            } else {
                return $this.FilterVMsWithCriteria($Parameters, $CacheManager)
            }
            
        } catch {
            $this.Logger.WriteError("VM filtering failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                FilteredVMs = @()
            }
        }
    }
    
    # Filter VMs from file list
    [hashtable] FilterVMsFromFile([hashtable] $Parameters, [object] $CacheManager) {
        try {
            $vmListFile = $Parameters.vmListFile
            
            # Warn if other filters are specified but will be ignored
            $hasOtherFilters = $Parameters.IncludeCluster -or $Parameters.ExcludeCluster -or 
                              $Parameters.IncludeDatacenter -or $Parameters.ExcludeDatacenter -or 
                              $Parameters.IncludeHost -or $Parameters.ExcludeHost -or 
                              $Parameters.IncludeEnvironment -or $Parameters.ExcludeEnvironment
            
            if ($hasOtherFilters) {
                $this.Logger.WriteWarning("VM List File takes precedence. Other filter parameters will be ignored.")
            }
            
            # Process VM list from file
            $this.Logger.WriteDebug("Processing VMs from list file: $vmListFile")
            
            $vmNames = $this.ReadVMNamesFromFile($vmListFile)
            if ($vmNames.Count -eq 0) {
                throw "No VM names found in the file"
            }
            
            # Get all VMs from vCenter
            $allVMsFromvCenter = Get-VM
            
            # Filter VMs based on the list
            $vms = @()
            $notFoundVMs = @()
            
            foreach ($vmName in $vmNames) {
                $foundVM = $allVMsFromvCenter | Where-Object { $_.Name -eq $vmName }
                if ($foundVM) {
                    $vms += $foundVM
                } else {
                    $notFoundVMs += $vmName
                }
            }
            
            $this.Logger.WriteInformation("Successfully matched $($vms.Count) VMs from the list")
            
            if ($notFoundVMs.Count -gt 0) {
                $this.Logger.WriteWarning("$($notFoundVMs.Count) VMs from the list were not found in vCenter")
                $notFoundVMs | ForEach-Object { $this.Logger.WriteDebug("  - $_") }
            }
            
            # Show power state summary
            $poweredOnCount = ($vms | Where-Object { $_.PowerState -eq "poweredOn" }).Count
            $poweredOffCount = ($vms | Where-Object { $_.PowerState -eq "poweredOff" }).Count
            $this.Logger.WriteDebug("Power state summary: $poweredOnCount powered on, $poweredOffCount powered off")
            
            return @{
                Success = $true
                FilteredVMs = $vms
                FilterMethod = "VMListFile"
                TotalMatched = $vms.Count
                NotFoundCount = $notFoundVMs.Count
                PoweredOnCount = $poweredOnCount
                PoweredOffCount = $poweredOffCount
            }
            
        } catch {
            $this.Logger.WriteError("VM filtering from file failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                FilteredVMs = @()
            }
        }
    }
    
    # Filter VMs with criteria
    [hashtable] FilterVMsWithCriteria([hashtable] $Parameters, [object] $CacheManager) {
        try {
            # Get all VMs from vCenter first
            $this.Logger.WriteDebug("Retrieving all VMs from vCenter...")
            $allVMsFromvCenter = Get-VM
            
            # Apply power state filter first
            if ($Parameters.filterVMs -eq 'Y') {
                $candidateVMs = $allVMsFromvCenter | Where-Object {$_.PowerState -eq "poweredOn"}
                $this.Logger.WriteDebug("Filtered to $($candidateVMs.Count) powered on VMs")
            } else {
                $candidateVMs = $allVMsFromvCenter
                $this.Logger.WriteDebug("Processing all $($candidateVMs.Count) VMs")
            }
            
            # Check if any advanced filters are specified
            $hasAdvancedFilters = $Parameters.IncludeCluster -or $Parameters.ExcludeCluster -or 
                                 $Parameters.IncludeDatacenter -or $Parameters.ExcludeDatacenter -or 
                                 $Parameters.IncludeHost -or $Parameters.ExcludeHost -or 
                                 $Parameters.IncludeEnvironment -or $Parameters.ExcludeEnvironment
            
            if ($hasAdvancedFilters) {
                return $this.ApplyAdvancedFilters($candidateVMs, $Parameters, $CacheManager)
            } else {
                # No advanced filters, use candidate VMs as-is
                $powerStateDesc = if($Parameters.filterVMs -eq 'Y') {'(powered on only)'} else {'(all VMs)'}
                $this.Logger.WriteInformation("Processing $($candidateVMs.Count) VMs $powerStateDesc")
                
                return @{
                    Success = $true
                    FilteredVMs = $candidateVMs
                    FilterMethod = "PowerStateOnly"
                    TotalVMs = $candidateVMs.Count
                }
            }
            
        } catch {
            $this.Logger.WriteError("VM filtering with criteria failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                FilteredVMs = @()
            }
        }
    }
    
    # Apply advanced filters
    [hashtable] ApplyAdvancedFilters([array] $CandidateVMs, [hashtable] $Parameters, [object] $CacheManager) {
        try {
            $this.Logger.WriteInformation("Applying advanced filters...")
            $this.Logger.WriteDebug("Applying advanced filters to $($CandidateVMs.Count) candidate VMs")
            
            # Build temporary infrastructure cache for filtering
            $this.Logger.WriteDebug("Building temporary infrastructure cache for filtering...")
            $tempInfraCache = @{}
            $filterVMCount = 0
            
            foreach ($vm in $CandidateVMs) {
                $filterVMCount++
                if ($CandidateVMs.Count -gt 50) {
                    $filterPercent = [math]::Round(($filterVMCount / $CandidateVMs.Count) * 100, 1)
                    Write-Progress -Activity "Building Filter Cache" -Status "Processing VM $filterVMCount of $($CandidateVMs.Count) ($filterPercent%) - $($vm.Name)" -PercentComplete $filterPercent
                }
                
                $vmHostInfo = if ($vm.VMHostId -and $CacheManager.HostCache[$vm.VMHostId]) { 
                    $CacheManager.HostCache[$vm.VMHostId] 
                } else { 
                    @{ Name = ""; Cluster = ""; Datacenter = $CacheManager.DatacenterName } 
                }
                
                # Get cluster info (try from host first, then direct lookup)
                $clusterName = $vmHostInfo.Cluster
                if (-not $clusterName) {
                    try {
                        $vmCluster = Get-Cluster -VM $vm -ErrorAction SilentlyContinue
                        $clusterName = if ($vmCluster) { $vmCluster.Name } else { "" }
                    } catch { $clusterName = "" }
                }
                
                $tempInfraCache[$vm.Id] = @{
                    HostName = $vmHostInfo.Name
                    ClusterName = $clusterName
                    DatacenterName = $vmHostInfo.Datacenter
                }
            }
            
            if ($CandidateVMs.Count -gt 50) {
                Write-Progress -Activity "Building Filter Cache" -Completed
            }
            
            # Apply filters
            $vms = @()
            $filteredOutCount = 0
            
            foreach ($vm in $CandidateVMs) {
                $infraInfo = $tempInfraCache[$vm.Id]
                
                if ($this.TestVMMatchesFilters($vm, $infraInfo, $Parameters)) {
                    $vms += $vm
                } else {
                    $filteredOutCount++
                }
            }
            
            $this.Logger.WriteInformation("Advanced filtering completed: $($vms.Count) VMs match criteria, $filteredOutCount VMs filtered out")
            
            return @{
                Success = $true
                FilteredVMs = $vms
                FilterMethod = "AdvancedFilters"
                TotalMatched = $vms.Count
                FilteredOutCount = $filteredOutCount
            }
            
        } catch {
            $this.Logger.WriteError("Advanced filtering failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
                FilteredVMs = @()
            }
        }
    }
    
    # Read VM names from file
    [array] ReadVMNamesFromFile([string] $FilePath) {
        $vmNames = @()
        $fileExtension = [System.IO.Path]::GetExtension($FilePath).ToLower()
        
        if ($fileExtension -eq '.csv') {
            # Handle CSV file
            $this.Logger.WriteDebug("Reading CSV file...")
            $csvData = Import-Csv $FilePath
            
            # Try to find VM name column
            $vmColumnName = $null
            $possibleColumns = @('VM', 'Name', 'VMName', 'VirtualMachine', 'Server', 'ServerName')
            
            foreach ($col in $possibleColumns) {
                if ($csvData[0].PSObject.Properties.Name -contains $col) {
                    $vmColumnName = $col
                    break
                }
            }
            
            if (-not $vmColumnName) {
                throw "Could not find VM name column in CSV. Expected columns: VM, Name, VMName, VirtualMachine, Server, or ServerName. Available columns: $($csvData[0].PSObject.Properties.Name -join ', ')"
            }
            
            $vmNames = $csvData | ForEach-Object { $_.$vmColumnName } | Where-Object { $_ -and $_.Trim() -ne '' }
            $this.Logger.WriteDebug("Found $($vmNames.Count) VM names in CSV file using column '$vmColumnName'")
            
        } elseif ($fileExtension -eq '.txt') {
            # Handle TXT file
            $this.Logger.WriteDebug("Reading TXT file...")
            $vmNames = Get-Content $FilePath | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
            $this.Logger.WriteDebug("Found $($vmNames.Count) VM names in TXT file")
        }
        
        return $vmNames
    }
    
    # Test if VM matches filters (replicates Test-VMMatchesFilters function)
    [bool] TestVMMatchesFilters([object] $VM, [hashtable] $InfraInfo, [hashtable] $Parameters) {
        try {
            # Cluster filtering
            if ($Parameters.IncludeCluster) {
                $clusterPatterns = $Parameters.IncludeCluster -split ","
                $clusterMatch = $false
                foreach ($pattern in $clusterPatterns) {
                    if ($this.TestWildcardMatch($InfraInfo.ClusterName, $pattern.Trim())) {
                        $clusterMatch = $true
                        break
                    }
                }
                if (-not $clusterMatch) { return $false }
            }
            
            if ($Parameters.ExcludeCluster) {
                $clusterPatterns = $Parameters.ExcludeCluster -split ","
                foreach ($pattern in $clusterPatterns) {
                    if ($this.TestWildcardMatch($InfraInfo.ClusterName, $pattern.Trim())) {
                        return $false
                    }
                }
            }
            
            # Datacenter filtering
            if ($Parameters.IncludeDatacenter) {
                $datacenterPatterns = $Parameters.IncludeDatacenter -split ","
                $datacenterMatch = $false
                foreach ($pattern in $datacenterPatterns) {
                    if ($this.TestWildcardMatch($InfraInfo.DatacenterName, $pattern.Trim())) {
                        $datacenterMatch = $true
                        break
                    }
                }
                if (-not $datacenterMatch) { return $false }
            }
            
            if ($Parameters.ExcludeDatacenter) {
                $datacenterPatterns = $Parameters.ExcludeDatacenter -split ","
                foreach ($pattern in $datacenterPatterns) {
                    if ($this.TestWildcardMatch($InfraInfo.DatacenterName, $pattern.Trim())) {
                        return $false
                    }
                }
            }
            
            # Host filtering
            if ($Parameters.IncludeHost) {
                $hostPatterns = $Parameters.IncludeHost -split ","
                $hostMatch = $false
                foreach ($pattern in $hostPatterns) {
                    if ($this.TestWildcardMatch($InfraInfo.HostName, $pattern.Trim())) {
                        $hostMatch = $true
                        break
                    }
                }
                if (-not $hostMatch) { return $false }
            }
            
            if ($Parameters.ExcludeHost) {
                $hostPatterns = $Parameters.ExcludeHost -split ","
                foreach ($pattern in $hostPatterns) {
                    if ($this.TestWildcardMatch($InfraInfo.HostName, $pattern.Trim())) {
                        return $false
                    }
                }
            }
            
            # Environment filtering
            if ($Parameters.IncludeEnvironment) {
                $vmEnvironment = $this.GetVMEnvironment($VM.Name)
                if ($vmEnvironment -ne $Parameters.IncludeEnvironment) {
                    return $false
                }
            }
            
            if ($Parameters.ExcludeEnvironment) {
                $vmEnvironment = $this.GetVMEnvironment($VM.Name)
                if ($vmEnvironment -eq $Parameters.ExcludeEnvironment) {
                    return $false
                }
            }
            
            return $true
            
        } catch {
            $this.Logger.WriteDebug("Error testing VM filters for $($VM.Name): $_")
            return $false
        }
    }
    
    # Test wildcard match (replicates Test-WildcardMatch function)
    [bool] TestWildcardMatch([string] $Value, [string] $Pattern) {
        if ([string]::IsNullOrEmpty($Value) -or [string]::IsNullOrEmpty($Pattern)) {
            return $false
        }
        
        # Convert wildcard pattern to regex
        $regexPattern = "^" + [regex]::Escape($Pattern).Replace('\*', '.*').Replace('\?', '.') + "$"
        return $Value -match $regexPattern
    }
    
    # Get VM environment (replicates Get-VMEnvironment function)
    [string] GetVMEnvironment([string] $VMName) {
        if ([string]::IsNullOrEmpty($VMName)) {
            return "NonProduction"
        }
        
        # Production patterns (case-insensitive)
        $productionPatterns = @(
            "prod", "production", "prd", "live", "p-", "-p-", "-prod-", 
            "critical", "crit", "business", "biz", "customer", "cust"
        )
        
        $vmNameLower = $VMName.ToLower()
        
        foreach ($pattern in $productionPatterns) {
            if ($vmNameLower.Contains($pattern)) {
                return "Production"
            }
        }
        
        return "NonProduction"
    }
}