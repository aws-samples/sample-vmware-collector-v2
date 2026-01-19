class SQLServerDetector {
    [hashtable] $Credentials
    [bool] $EnableSQLDetection
    [int] $ConnectionTimeout
    
    SQLServerDetector([hashtable] $Credentials, [bool] $EnableSQLDetection = $true) {
        $this.Credentials = $Credentials
        $this.EnableSQLDetection = $EnableSQLDetection
        $this.ConnectionTimeout = 5
    }
    
    # Main method to detect SQL Server on a VM
    [PSCustomObject] DetectSQLServer([object] $VM) {
        if (-not $this.EnableSQLDetection) {
            return $this.GetDefaultSQLInfo()
        }
        
        $sqlInfo = $this.GetDefaultSQLInfo()
        
        try {
            # Get VM IP address
            $ipAddress = $this.GetVMIPAddress($VM)
            if (-not $ipAddress) {
                return $sqlInfo
            }
            
            # Test for SQL Server connectivity
            $sqlInstances = $this.DiscoverSQLInstances($ipAddress)
            
            if ($sqlInstances.Count -gt 0) {
                # Get detailed info from the first accessible instance
                $detailedInfo = $this.GetSQLServerDetails($sqlInstances[0])
                if ($detailedInfo) {
                    $sqlInfo = $detailedInfo
                }
            }
        }
        catch {
            Write-Debug "SQL detection failed for VM $($VM.Name): $_"
        }
        
        return $sqlInfo
    }
    
    # Get VM IP address (similar to existing network detection)
    [string] GetVMIPAddress([object] $VM) {
        $primaryIP = ""
        
        if ($VM.Guest.IPAddress) {
            if ($VM.Guest.IPAddress -is [array]) {
                $primaryIP = ($VM.Guest.IPAddress | Where-Object { 
                    $_ -notmatch '^(127\.|::1$|fe80::)' -and $_ -ne '' 
                } | Select-Object -First 1)
            } else {
                $primaryIP = $VM.Guest.IPAddress
            }
        }
        
        return $primaryIP
    }
    
    # Discover SQL Server instances on a host
    [array] DiscoverSQLInstances([string] $IPAddress) {
        $instances = @()
        
        # Test default SQL Server port
        if ($this.TestSQLConnection($IPAddress, 1433)) {
            $instances += @{
                Server = $IPAddress
                Port = 1433
                Instance = "MSSQLSERVER"
            }
        }
        
        # Test for named instances (simplified - could be enhanced)
        $commonPorts = @(1434, 2433, 3433)
        foreach ($port in $commonPorts) {
            if ($this.TestSQLConnection($IPAddress, $port)) {
                $instances += @{
                    Server = $IPAddress
                    Port = $port
                    Instance = "Unknown"
                }
            }
        }
        
        return $instances
    }
    
    # Test SQL Server connectivity
    [bool] TestSQLConnection([string] $Server, [int] $Port) {
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connect = $tcpClient.BeginConnect($Server, $Port, $null, $null)
            $wait = $connect.AsyncWaitHandle.WaitOne($this.ConnectionTimeout * 1000, $false)
            
            if ($wait) {
                $tcpClient.EndConnect($connect)
                $tcpClient.Close()
                return $true
            } else {
                $tcpClient.Close()
                return $false
            }
        }
        catch {
            return $false
        }
    }
    
    # Get detailed SQL Server information using the same method as RDS Tools
    [PSCustomObject] GetSQLServerDetails([hashtable] $Instance) {
        $serverInstance = if ($Instance.Port -eq 1433) { 
            $Instance.Server 
        } else { 
            "$($Instance.Server),$($Instance.Port)" 
        }
        
        # SQL query to get edition and version (same as RDS Tools)
        $sqlQuery = @"
SELECT SERVERPROPERTY('Edition') AS Edition,
       SERVERPROPERTY('ProductVersion') AS ProductVersion,
       SERVERPROPERTY('IsClustered') as IsClustered,
       CASE 
           WHEN CONVERT(VARCHAR(128),SERVERPROPERTY('Edition')) LIKE 'Enterprise%' THEN 'Enterprise Edition'
           WHEN CONVERT(VARCHAR(128),SERVERPROPERTY('Edition')) LIKE 'Standard%' THEN 'Standard Edition'
           WHEN CONVERT(VARCHAR(128),SERVERPROPERTY('Edition')) LIKE 'Developer%' THEN 'Developer Edition'
           WHEN CONVERT(VARCHAR(128),SERVERPROPERTY('Edition')) LIKE 'Express%' THEN 'Express Edition'
           ELSE CONVERT(VARCHAR(128),SERVERPROPERTY('Edition'))
       END AS EditionCategory
"@
        
        try {
            # Try Windows Authentication first
            if ($this.Credentials.UseWindowsAuth) {
                $result = Invoke-Sqlcmd -ServerInstance $serverInstance -Database "master" -Query $sqlQuery -TrustServerCertificate -ConnectionTimeout $this.ConnectionTimeout -ErrorAction Stop
            }
            # Try SQL Authentication
            elseif ($this.Credentials.Username -and $this.Credentials.Password) {
                $result = Invoke-Sqlcmd -ServerInstance $serverInstance -Database "master" -Query $sqlQuery -Username $this.Credentials.Username -Password $this.Credentials.Password -TrustServerCertificate -ConnectionTimeout $this.ConnectionTimeout -ErrorAction Stop
            }
            else {
                # Try without credentials (integrated security)
                $result = Invoke-Sqlcmd -ServerInstance $serverInstance -Database "master" -Query $sqlQuery -TrustServerCertificate -ConnectionTimeout $this.ConnectionTimeout -ErrorAction Stop
            }
            
            return [PSCustomObject]@{
                HasSQLServer = $true
                Edition = $result.Edition
                EditionCategory = $result.EditionCategory
                ProductVersion = $result.ProductVersion
                IsClustered = $result.IsClustered
                ServerInstance = $serverInstance
                DetectionMethod = "Direct SQL Query"
            }
        }
        catch {
            Write-Debug "Failed to query SQL Server $serverInstance`: $_"
            return $this.GetDefaultSQLInfo()
        }
    }
    
    # Default SQL info when detection fails or is disabled
    [PSCustomObject] GetDefaultSQLInfo() {
        return [PSCustomObject]@{
            HasSQLServer = $false
            Edition = ""
            EditionCategory = ""
            ProductVersion = ""
            IsClustered = $false
            ServerInstance = ""
            DetectionMethod = "None"
        }
    }
}