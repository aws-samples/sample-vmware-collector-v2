#
# ConnectionPoolManager.ps1 - Advanced connection pooling for multiple vCenter environments
#
# Implements connection pooling, load balancing, and failover capabilities for enterprise
# environments with multiple vCenter servers or distributed deployments.
#

class ConnectionPoolManager {
    [hashtable] $ConnectionPools
    [hashtable] $PoolStatistics
    [hashtable] $LoadBalancingConfig
    [ILogger] $Logger
    [int] $MaxConnectionsPerPool
    [int] $ConnectionTimeout
    [bool] $EnableLoadBalancing
    [bool] $EnableFailover
    
    # Constructor
    ConnectionPoolManager([ILogger] $logger) {
        $this.Logger = $logger
        $this.ConnectionPools = @{}
        $this.PoolStatistics = @{}
        $this.MaxConnectionsPerPool = 5
        $this.ConnectionTimeout = 300  # 5 minutes
        $this.EnableLoadBalancing = $true
        $this.EnableFailover = $true
        
        $this.LoadBalancingConfig = @{
            Algorithm = 'RoundRobin'  # RoundRobin, LeastConnections, WeightedRoundRobin
            HealthCheckInterval = 60  # seconds
            FailoverThreshold = 3     # failed attempts before failover
            RetryInterval = 30        # seconds between retries
        }
        
        $this.Logger.WriteInformation("ConnectionPoolManager initialized with max $($this.MaxConnectionsPerPool) connections per pool")
    }
    
    # Create or get connection pool for vCenter
    [hashtable] GetConnectionPool([string] $vCenterServer) {
        if (-not $this.ConnectionPools.ContainsKey($vCenterServer)) {
            $this.CreateConnectionPool($vCenterServer)
        }
        
        return $this.ConnectionPools[$vCenterServer]
    }
    
    # Create new connection pool
    [void] CreateConnectionPool([string] $vCenterServer) {
        $pool = @{
            Server = $vCenterServer
            Connections = @()
            ActiveConnections = 0
            MaxConnections = $this.MaxConnectionsPerPool
            CreatedTime = Get-Date
            LastHealthCheck = Get-Date
            IsHealthy = $true
            FailedAttempts = 0
        }
        
        $this.ConnectionPools[$vCenterServer] = $pool
        $this.PoolStatistics[$vCenterServer] = @{
            TotalConnectionsCreated = 0
            TotalConnectionsDestroyed = 0
            TotalRequestsServed = 0
            AverageResponseTime = 0.0
            HealthChecksPassed = 0
            HealthChecksFailed = 0
        }
        
        $this.Logger.WriteInformation("Created connection pool for vCenter: $vCenterServer")
    }
    
    # Get optimized connection from pool
    [object] GetOptimizedConnection([string] $vCenterServer, [PSCredential] $credential) {
        try {
            $pool = $this.GetConnectionPool($vCenterServer)
            
            # Check pool health
            if (-not $pool.IsHealthy -and $this.EnableFailover) {
                $this.Logger.WriteWarning("Connection pool for $vCenterServer is unhealthy, attempting recovery")
                $this.RecoverConnectionPool($vCenterServer)
            }
            
            # Find available connection or create new one
            $connection = $this.FindAvailableConnection($pool) ?? $this.CreateNewConnection($vCenterServer, $credential, $pool)
            
            if ($connection) {
                $pool.ActiveConnections++
                $this.PoolStatistics[$vCenterServer].TotalRequestsServed++
                $this.Logger.WriteDebug("Provided connection for $vCenterServer (Active: $($pool.ActiveConnections))")
            }
            
            return $connection
            
        } catch {
            $this.Logger.WriteError("Failed to get optimized connection for $vCenterServer", $_.Exception)
            throw
        }
    }
    
    # Find available connection in pool
    [object] FindAvailableConnection([hashtable] $pool) {
        foreach ($conn in $pool.Connections) {
            if ($conn.IsAvailable -and $conn.IsConnected) {
                # Test connection health
                if ($this.TestConnectionHealth($conn)) {
                    $conn.IsAvailable = $false
                    $conn.LastUsed = Get-Date
                    return $conn.Connection
                } else {
                    # Remove unhealthy connection
                    $this.RemoveConnection($pool, $conn)
                }
            }
        }
        
        return $null
    }
    
    # Create new connection
    [object] CreateNewConnection([string] $vCenterServer, [PSCredential] $credential, [hashtable] $pool) {
        try {
            if ($pool.Connections.Count -ge $pool.MaxConnections) {
                $this.Logger.WriteWarning("Connection pool for $vCenterServer is at maximum capacity")
                return $null
            }
            
            # Create new PowerCLI connection
            $connection = Connect-VIServer -Server $vCenterServer -Credential $credential -Force -ErrorAction Stop
            
            $connectionWrapper = @{
                Connection = $connection
                CreatedTime = Get-Date
                LastUsed = Get-Date
                IsAvailable = $false
                IsConnected = $true
                UsageCount = 0
                Server = $vCenterServer
            }
            
            $pool.Connections += $connectionWrapper
            $this.PoolStatistics[$vCenterServer].TotalConnectionsCreated++
            
            $this.Logger.WriteInformation("Created new connection for $vCenterServer (Pool size: $($pool.Connections.Count))")
            
            return $connection
            
        } catch {
            $pool.FailedAttempts++
            $this.Logger.WriteError("Failed to create new connection for $vCenterServer", $_.Exception)
            
            if ($pool.FailedAttempts -ge $this.LoadBalancingConfig.FailoverThreshold) {
                $pool.IsHealthy = $false
            }
            
            throw
        }
    }
    
    # Return connection to pool
    [void] ReturnConnection([string] $vCenterServer, [object] $connection) {
        try {
            $pool = $this.ConnectionPools[$vCenterServer]
            if (-not $pool) { return }
            
            $connectionWrapper = $pool.Connections | Where-Object { $_.Connection -eq $connection }
            if ($connectionWrapper) {
                $connectionWrapper.IsAvailable = $true
                $connectionWrapper.UsageCount++
                $pool.ActiveConnections = [Math]::Max(0, $pool.ActiveConnections - 1)
                
                $this.Logger.WriteDebug("Returned connection for $vCenterServer (Active: $($pool.ActiveConnections))")
            }
            
        } catch {
            $this.Logger.WriteError("Failed to return connection for $vCenterServer", $_.Exception)
        }
    }
    
    # Test connection health
    [bool] TestConnectionHealth([hashtable] $connectionWrapper) {
        try {
            # Simple health check - try to get server info
            $serverInfo = Get-VIServer -Server $connectionWrapper.Connection -ErrorAction Stop
            return $serverInfo.IsConnected
            
        } catch {
            $this.Logger.WriteDebug("Connection health check failed for $($connectionWrapper.Server)")
            return $false
        }
    }
    
    # Remove unhealthy connection
    [void] RemoveConnection([hashtable] $pool, [hashtable] $connectionWrapper) {
        try {
            if ($connectionWrapper.Connection) {
                Disconnect-VIServer -Server $connectionWrapper.Connection -Confirm:$false -Force -ErrorAction SilentlyContinue
            }
            
            $pool.Connections = $pool.Connections | Where-Object { $_ -ne $connectionWrapper }
            $this.PoolStatistics[$pool.Server].TotalConnectionsDestroyed++
            
            $this.Logger.WriteDebug("Removed unhealthy connection from pool for $($pool.Server)")
            
        } catch {
            $this.Logger.WriteError("Failed to remove connection from pool", $_.Exception)
        }
    }
    
    # Recover connection pool
    [void] RecoverConnectionPool([string] $vCenterServer) {
        try {
            $pool = $this.ConnectionPools[$vCenterServer]
            
            # Remove all unhealthy connections
            $unhealthyConnections = $pool.Connections | Where-Object { -not $this.TestConnectionHealth($_) }
            foreach ($conn in $unhealthyConnections) {
                $this.RemoveConnection($pool, $conn)
            }
            
            # Reset failure count and mark as healthy
            $pool.FailedAttempts = 0
            $pool.IsHealthy = $true
            $pool.LastHealthCheck = Get-Date
            
            $this.Logger.WriteInformation("Recovered connection pool for $vCenterServer")
            
        } catch {
            $this.Logger.WriteError("Failed to recover connection pool for $vCenterServer", $_.Exception)
        }
    }
    
    # Get pool statistics
    [hashtable] GetPoolStatistics() {
        $overallStats = @{
            TotalPools = $this.ConnectionPools.Count
            TotalConnections = 0
            ActiveConnections = 0
            HealthyPools = 0
            PoolDetails = @{}
        }
        
        foreach ($server in $this.ConnectionPools.Keys) {
            $pool = $this.ConnectionPools[$server]
            $stats = $this.PoolStatistics[$server]
            
            $overallStats.TotalConnections += $pool.Connections.Count
            $overallStats.ActiveConnections += $pool.ActiveConnections
            if ($pool.IsHealthy) { $overallStats.HealthyPools++ }
            
            $overallStats.PoolDetails[$server] = @{
                ConnectionCount = $pool.Connections.Count
                ActiveConnections = $pool.ActiveConnections
                IsHealthy = $pool.IsHealthy
                FailedAttempts = $pool.FailedAttempts
                Statistics = $stats
            }
        }
        
        return $overallStats
    }
    
    # Cleanup all pools
    [void] Cleanup() {
        try {
            foreach ($server in $this.ConnectionPools.Keys) {
                $pool = $this.ConnectionPools[$server]
                
                foreach ($connectionWrapper in $pool.Connections) {
                    if ($connectionWrapper.Connection) {
                        Disconnect-VIServer -Server $connectionWrapper.Connection -Confirm:$false -Force -ErrorAction SilentlyContinue
                    }
                }
                
                $pool.Connections.Clear()
            }
            
            $this.ConnectionPools.Clear()
            $this.PoolStatistics.Clear()
            
            $this.Logger.WriteInformation("Connection pool manager cleanup completed")
            
        } catch {
            $this.Logger.WriteError("Failed to cleanup connection pools", $_.Exception)
        }
    }
}