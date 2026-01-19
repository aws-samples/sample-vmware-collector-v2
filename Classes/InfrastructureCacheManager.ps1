#
# InfrastructureCacheManager.ps1 - Manages infrastructure data caching
#
# Replicates infrastructure caching logic from vmware-collector.ps1
#

using module .\Interfaces.ps1

class InfrastructureCacheManager {
    [ILogger] $Logger
    [hashtable] $HostCache
    [hashtable] $ClusterCache
    [hashtable] $DatastoreCache
    [hashtable] $ResourcePoolCache
    [hashtable] $VMInfraCache
    [bool] $CacheInitialized
    [string] $DatacenterName
    
    InfrastructureCacheManager([ILogger] $Logger) {
        $this.Logger = $Logger
        $this.InitializeCaches()
    }
    
    # Initialize all cache hashtables
    [void] InitializeCaches() {
        $this.HostCache = @{}
        $this.ClusterCache = @{}
        $this.DatastoreCache = @{}
        $this.ResourcePoolCache = @{}
        $this.VMInfraCache = @{}
        $this.CacheInitialized = $false
        $this.DatacenterName = "Unknown"
    }
    
    # Cache all infrastructure data (replicates vmware-collector.ps1 caching logic)
    [hashtable] CacheAllInfrastructure() {
        try {
            $this.Logger.WriteInformation("Pre-caching infrastructure data...")
            $cacheStartTime = Get-Date
            
            # Get datacenter name for fallback
            try { 
                $this.DatacenterName = (Get-Datacenter)[0].Name 
            } catch { 
                $this.DatacenterName = "Unknown" 
            }
            
            # Cache all hosts
            $this.CacheHosts()
            
            # Cache all clusters
            $this.CacheClusters()
            
            # Cache all datastores
            $this.CacheDatastores()
            
            # Cache all resource pools
            $this.CacheResourcePools()
            
            $cacheTime = (Get-Date) - $cacheStartTime
            $this.Logger.WriteInformation("Infrastructure caching completed in $($cacheTime.TotalSeconds.ToString('F1')) seconds")
            
            $this.CacheInitialized = $true
            
            return @{
                Success = $true
                CacheTime = $cacheTime
                HostCount = $this.HostCache.Count
                ClusterCount = $this.ClusterCache.Count
                DatastoreCount = $this.DatastoreCache.Count
                ResourcePoolCount = $this.ResourcePoolCache.Count
            }
            
        } catch {
            $this.Logger.WriteError("Infrastructure caching failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
            }
        }
    }
    
    # Cache host information
    [void] CacheHosts() {
        $this.Logger.WriteDebug("Caching host information...")
        $allHosts = Get-VMHost
        $hostCount = 0
        
        foreach ($vmHost in $allHosts) {
            $hostCount++
            if ($allHosts.Count -gt 10) {
                $hostPercent = [math]::Round(($hostCount / $allHosts.Count) * 100, 1)
                Write-Progress -Activity "Caching Infrastructure Data" -Status "Caching host $hostCount of $($allHosts.Count) ($hostPercent%) - $($vmHost.Name)" -PercentComplete $hostPercent
            }
            
            $clusterName = ""
            try { $clusterName = (Get-Cluster -VMHost $vmHost).Name } catch { $clusterName = "" }
            
            $datacenterNameHost = $this.DatacenterName
            try { $datacenterNameHost = (Get-Datacenter -VMHost $vmHost).Name } catch { $datacenterNameHost = $this.DatacenterName }
            
            $this.HostCache[$vmHost.Id] = @{
                Name = $vmHost.Name
                Cluster = $clusterName
                Datacenter = $datacenterNameHost
            }
        }
        
        if ($allHosts.Count -gt 10) {
            Write-Progress -Activity "Caching Infrastructure Data" -Completed
        }
        
        $this.Logger.WriteDebug("Cached $($this.HostCache.Count) hosts")
    }
    
    # Cache cluster information
    [void] CacheClusters() {
        $this.Logger.WriteDebug("Caching cluster information...")
        $allClusters = Get-Cluster
        
        foreach ($cluster in $allClusters) {
            $datacenterNameCluster = $this.DatacenterName
            try { $datacenterNameCluster = (Get-Datacenter -Cluster $cluster).Name } catch { $datacenterNameCluster = $this.DatacenterName }
            
            $this.ClusterCache[$cluster.Id] = @{
                Name = $cluster.Name
                Datacenter = $datacenterNameCluster
            }
        }
        
        $this.Logger.WriteDebug("Cached $($this.ClusterCache.Count) clusters")
    }
    
    # Cache datastore information
    [void] CacheDatastores() {
        $this.Logger.WriteDebug("Caching datastore information...")
        $allDatastores = Get-Datastore
        
        foreach ($datastore in $allDatastores) {
            $this.DatastoreCache[$datastore.Id] = $datastore.Name
        }
        
        $this.Logger.WriteDebug("Cached $($this.DatastoreCache.Count) datastores")
    }
    
    # Cache resource pool information
    [void] CacheResourcePools() {
        $this.Logger.WriteDebug("Caching resource pool information...")
        
        try {
            $allResourcePools = Get-ResourcePool
            foreach ($rp in $allResourcePools) {
                $this.ResourcePoolCache[$rp.Id] = $rp.Name
            }
            $this.Logger.WriteDebug("Cached $($this.ResourcePoolCache.Count) resource pools")
        } catch {
            $this.Logger.WriteDebug("Warning: Could not cache resource pools: $_")
        }
    }
    
    # Filter infrastructure data to only include items related to filtered VMs
    [hashtable] FilterInfrastructureForVMs([array] $FilteredVMs) {
        try {
            $this.Logger.WriteInformation("Filtering infrastructure data to match VM selection...")
            $infraFilterStartTime = Get-Date
            
            # Get unique hosts used by filtered VMs
            $filteredHostIds = @()
            $filteredHostNames = @()
            foreach ($vm in $FilteredVMs) {
                if ($vm.VMHostId -and $vm.VMHostId -notin $filteredHostIds) {
                    $filteredHostIds += $vm.VMHostId
                    if ($this.HostCache[$vm.VMHostId]) {
                        $filteredHostNames += $this.HostCache[$vm.VMHostId].Name
                    }
                }
            }
            
            # Get unique clusters used by filtered VMs
            $filteredClusterNames = @()
            foreach ($vm in $FilteredVMs) {
                try {
                    $vmCluster = Get-Cluster -VM $vm -ErrorAction SilentlyContinue
                    if ($vmCluster -and $vmCluster.Name -notin $filteredClusterNames) {
                        $filteredClusterNames += $vmCluster.Name
                    }
                } catch { }
            }
            
            # Get unique datastores used by filtered VMs
            $filteredDatastoreIds = @()
            $filteredDatastoreNames = @()
            foreach ($vm in $FilteredVMs) {
                if ($vm.DatastoreIdList) {
                    foreach ($datastoreId in $vm.DatastoreIdList) {
                        if ($datastoreId -notin $filteredDatastoreIds) {
                            $filteredDatastoreIds += $datastoreId
                            if ($this.DatastoreCache[$datastoreId]) {
                                $filteredDatastoreNames += $this.DatastoreCache[$datastoreId]
                            }
                        }
                    }
                }
            }
            
            # Filter the cached infrastructure data to only include relevant items
            $filteredHostCache = @{}
            foreach ($hostId in $filteredHostIds) {
                if ($this.HostCache[$hostId]) {
                    $filteredHostCache[$hostId] = $this.HostCache[$hostId]
                }
            }
            
            $filteredDatastoreCache = @{}
            foreach ($datastoreId in $filteredDatastoreIds) {
                if ($this.DatastoreCache[$datastoreId]) {
                    $filteredDatastoreCache[$datastoreId] = $this.DatastoreCache[$datastoreId]
                }
            }
            
            # Update the caches to only contain filtered data
            $this.HostCache = $filteredHostCache
            $this.DatastoreCache = $filteredDatastoreCache
            
            $infraFilterTime = (Get-Date) - $infraFilterStartTime
            
            $this.Logger.WriteInformation("Infrastructure filtering completed:")
            $this.Logger.WriteInformation("  - Hosts: $($filteredHostNames.Count) ($(($filteredHostNames | Sort-Object -Unique) -join ', '))")
            $this.Logger.WriteInformation("  - Clusters: $($filteredClusterNames.Count) ($(($filteredClusterNames | Sort-Object -Unique) -join ', '))")
            $this.Logger.WriteInformation("  - Datastores: $($filteredDatastoreNames.Count) ($(($filteredDatastoreNames | Sort-Object -Unique) -join ', '))")
            
            return @{
                Success = $true
                FilterTime = $infraFilterTime
                FilteredHosts = $filteredHostNames
                FilteredClusters = $filteredClusterNames
                FilteredDatastores = $filteredDatastoreNames
            }
            
        } catch {
            $this.Logger.WriteError("Infrastructure filtering failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
            }
        }
    }
    
    # Build VM-to-infrastructure mappings
    [hashtable] BuildVMInfrastructureMappings([array] $VMs) {
        try {
            $this.Logger.WriteInformation("Building VM-to-infrastructure mappings...")
            $mappingStartTime = Get-Date
            $mappingVMCount = 0
            $totalVMs = $VMs.Count
            
            foreach ($vm in $VMs) {
                $mappingVMCount++
                if ($totalVMs -gt 50) {
                    $mappingPercent = [math]::Round(($mappingVMCount / $totalVMs) * 100, 1)
                    Write-Progress -Activity "Building Infrastructure Mappings" -Status "Processing VM $mappingVMCount of $totalVMs ($mappingPercent%) - $($vm.Name)" -PercentComplete $mappingPercent
                }
                
                $vmHostInfo = if ($vm.VMHostId -and $this.HostCache[$vm.VMHostId]) { 
                    $this.HostCache[$vm.VMHostId] 
                } else { 
                    @{ Name = ""; Cluster = ""; Datacenter = $this.DatacenterName } 
                }
                
                # Get cluster info (try from host first, then direct lookup)
                $clusterName = $vmHostInfo.Cluster
                if (-not $clusterName) {
                    try {
                        $vmCluster = Get-Cluster -VM $vm -ErrorAction SilentlyContinue
                        $clusterName = if ($vmCluster) { $vmCluster.Name } else { "" }
                    } catch { $clusterName = "" }
                }
                
                # Get resource pool using cache
                $resourcePoolName = ""
                try {
                    $vmResourcePool = Get-ResourcePool -VM $vm -ErrorAction SilentlyContinue
                    $resourcePoolName = if ($vmResourcePool -and $this.ResourcePoolCache[$vmResourcePool.Id]) { 
                        $this.ResourcePoolCache[$vmResourcePool.Id] 
                    } else { "" }
                } catch { $resourcePoolName = "" }
                
                # Get datastores using cache
                $datastoreNames = @()
                try {
                    foreach ($datastoreId in $vm.DatastoreIdList) {
                        if ($this.DatastoreCache[$datastoreId]) {
                            $datastoreNames += $this.DatastoreCache[$datastoreId]
                        }
                    }
                } catch { }
                
                $folderName = ""
                try { $folderName = $vm.Folder.Name } catch { $folderName = "" }
                
                $this.VMInfraCache[$vm.Id] = @{
                    HostName = $vmHostInfo.Name
                    ClusterName = $clusterName
                    DatacenterName = $vmHostInfo.Datacenter
                    ResourcePoolName = $resourcePoolName
                    FolderName = $folderName
                    DatastoreNames = $datastoreNames -join ", "
                }
            }
            
            if ($totalVMs -gt 50) {
                Write-Progress -Activity "Building Infrastructure Mappings" -Completed
            }
            
            $mappingTime = (Get-Date) - $mappingStartTime
            $this.Logger.WriteInformation("Built infrastructure mappings in $($mappingTime.TotalSeconds.ToString('F1')) seconds")
            
            return @{
                Success = $true
                MappingTime = $mappingTime
                MappingCount = $this.VMInfraCache.Count
            }
            
        } catch {
            $this.Logger.WriteError("VM infrastructure mapping failed: $($_.Exception.Message)", $_.Exception)
            return @{
                Success = $false
                ErrorMessage = $_.Exception.Message
            }
        }
    }
    
    # Get cached infrastructure information for a VM
    [hashtable] GetVMInfraInfo([object] $VM) {
        # Return cached info if available
        if ($this.VMInfraCache.ContainsKey($VM.Id)) {
            return $this.VMInfraCache[$VM.Id]
        }
        
        # Fallback to direct lookup if not cached
        $this.Logger.WriteDebug("VM $($VM.Name) not found in cache, using direct lookup")
        try {
            $hostName = if ($VM.VMHost) { $VM.VMHost.Name } else { "" }
            $clusterName = ""
            $vmDatacenterName = ""
            
            try {
                $cluster = Get-Cluster -VM $VM -ErrorAction SilentlyContinue
                $clusterName = if ($cluster) { $cluster.Name } else { "" }
            } catch { }
            
            try {
                $datacenter = Get-Datacenter -VM $VM -ErrorAction SilentlyContinue
                $vmDatacenterName = if ($datacenter) { $datacenter.Name } else { "" }
            } catch { }
            
            return @{
                HostName = $hostName
                ClusterName = $clusterName
                DatacenterName = $vmDatacenterName
                ResourcePoolName = ""
                FolderName = ""
                DatastoreNames = ""
            }
        } catch {
            $this.Logger.WriteDebug("Error getting infrastructure info for VM $($VM.Name): $_")
            return @{
                HostName = ""
                ClusterName = ""
                DatacenterName = ""
                ResourcePoolName = ""
                FolderName = ""
                DatastoreNames = ""
            }
        }
    }
    
    # Clear all caches
    [void] ClearAllCaches() {
        $this.HostCache.Clear()
        $this.ClusterCache.Clear()
        $this.DatastoreCache.Clear()
        $this.ResourcePoolCache.Clear()
        $this.VMInfraCache.Clear()
        $this.CacheInitialized = $false
        $this.Logger.WriteDebug("All infrastructure caches cleared")
    }
    
    # Get cache statistics
    [hashtable] GetCacheStatistics() {
        return @{
            HostCacheCount = $this.HostCache.Count
            ClusterCacheCount = $this.ClusterCache.Count
            DatastoreCacheCount = $this.DatastoreCache.Count
            ResourcePoolCacheCount = $this.ResourcePoolCache.Count
            VMInfraCacheCount = $this.VMInfraCache.Count
            CacheInitialized = $this.CacheInitialized
            DatacenterName = $this.DatacenterName
        }
    }
}