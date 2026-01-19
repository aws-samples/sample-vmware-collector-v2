class SQLServerDetectorRealistic {
    [hashtable] $Credentials
    [bool] $EnableSQLDetection
    [string] $DetectionMethod  # "Direct", "PowerShellRemoting", "VMwareTools", "PatternOnly"
    
    SQLServerDetectorRealistic([hashtable] $Credentials, [string] $DetectionMethod = "Direct") {
        $this.Credentials = $Credentials
        $this.EnableSQLDetection = $true
        $this.DetectionMethod = $DetectionMethod
    }
    
    [PSCustomObject] DetectSQLServer([object] $VM) {
        if (-not $this.EnableSQLDetection) {
            return $this.GetPatternBasedDetection($VM)
        }
        
        # Try different detection methods in order of preference
        switch ($this.DetectionMethod) {
            "Direct" { 
                return $this.TryDirectSQLConnection($VM) 
            }
            "PowerShellRemoting" { 
                return $this.TryPowerShellRemoting($VM) 
            }
            "VMwareTools" { 
                return $this.TryVMwareTools($VM) 
            }
            default { 
                return $this.GetPatternBasedDetection($VM) 
            }
        }
        
        # Fallback return (should never reach here due to switch default)
        return $this.GetPatternBasedDetection($VM)
    }
    
    # Method 1: Direct SQL Connection (original approach)
    [PSCustomObject] TryDirectSQLConnection([object] $VM) {
        try {
            $ipAddress = $this.GetVMIPAddress($VM)
            if (-not $ipAddress) {
                return $this.GetPatternBasedDetection($VM)
            }
            
            # Test if SQL Server port is accessible
            if (-not $this.TestSQLConnection($ipAddress, 1433)) {
                return $this.GetPatternBasedDetection($VM)
            }
            
            # Try to query SQL Server directly
            $sqlQuery = "SELECT SERVERPROPERTY('Edition') AS Edition, SERVERPROPERTY('ProductVersion') AS ProductVersion"
            
            if ($this.Credentials.UseWindowsAuth) {
                $result = Invoke-SqlCmd -ServerInstance $ipAddress -Database "master" -Query $sqlQuery -TrustServerCertificate -ConnectionTimeout 5 -ErrorAction Stop
            } else {
                $result = Invoke-SqlCmd -ServerInstance $ipAddress -Database "master" -Query $sqlQuery -Username $this.Credentials.Username -Password $this.Credentials.Password -TrustServerCertificate -ConnectionTimeout 5 -ErrorAction Stop
            }
            
            return $this.ProcessSQLResult($result, "Direct SQL Connection")
            
        } catch {
            Write-Debug "Direct SQL connection failed for $($VM.Name): $_"
            return $this.GetPatternBasedDetection($VM)
        }
    }
    
    # Method 2: PowerShell Remoting
    [PSCustomObject] TryPowerShellRemoting([object] $VM) {
        try {
            $vmName = $VM.Name
            $ipAddress = $this.GetVMIPAddress($VM)
            
            if (-not $ipAddress -and -not $vmName) {
                return $this.GetPatternBasedDetection($VM)
            }
            
            # Try to connect via PowerShell remoting
            $target = if ($ipAddress) { $ipAddress } else { $vmName }
            
            $scriptBlock = {
                try {
                    # Check if SQL Server is installed locally
                    $sqlServices = Get-Service -Name "*SQL*" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "MSSQLSERVER|MSSQL\$" }
                    if (-not $sqlServices) {
                        return $null
                    }
                    
                    # Try to query local SQL Server
                    $result = Invoke-SqlCmd -ServerInstance "localhost" -Database "master" -Query "SELECT SERVERPROPERTY('Edition') AS Edition, SERVERPROPERTY('ProductVersion') AS ProductVersion" -TrustServerCertificate -ConnectionTimeout 5 -ErrorAction Stop
                    return $result
                } catch {
                    return $null
                }
            }
            
            if ($this.Credentials.Username -and $this.Credentials.Password) {
                $securePassword = ConvertTo-SecureString $this.Credentials.Password -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential($this.Credentials.Username, $securePassword)
                $result = Invoke-Command -ComputerName $target -ScriptBlock $scriptBlock -Credential $credential -ErrorAction Stop
            } else {
                $result = Invoke-Command -ComputerName $target -ScriptBlock $scriptBlock -ErrorAction Stop
            }
            
            if ($result) {
                return $this.ProcessSQLResult($result, "PowerShell Remoting")
            } else {
                return $this.GetPatternBasedDetection($VM)
            }
            
        } catch {
            Write-Debug "PowerShell remoting failed for $($VM.Name): $_"
            return $this.GetPatternBasedDetection($VM)
        }
    }
    
    # Method 3: VMware Tools (requires guest credentials)
    [PSCustomObject] TryVMwareTools([object] $VM) {
        try {
            if (-not $this.Credentials.GuestUsername -or -not $this.Credentials.GuestPassword) {
                return $this.GetPatternBasedDetection($VM)
            }
            
            # Use VMware Tools to execute command in guest
            $sqlCheckScript = @"
try {
    `$services = Get-Service -Name "*SQL*" -ErrorAction SilentlyContinue | Where-Object { `$_.Name -match "MSSQLSERVER|MSSQL\$" }
    if (`$services) {
        `$result = Invoke-SqlCmd -ServerInstance "localhost" -Database "master" -Query "SELECT SERVERPROPERTY('Edition') AS Edition, SERVERPROPERTY('ProductVersion') AS ProductVersion" -TrustServerCertificate -ConnectionTimeout 5 -ErrorAction Stop
        Write-Output "`$(`$result.Edition)|`$(`$result.ProductVersion)"
    } else {
        Write-Output "NO_SQL"
    }
} catch {
    Write-Output "ERROR: `$_"
}
"@
            
            $result = Invoke-VMScript -VM $VM -ScriptText $sqlCheckScript -GuestUser $this.Credentials.GuestUsername -GuestPassword $this.Credentials.GuestPassword -ScriptType PowerShell -ErrorAction Stop
            
            if ($result.ScriptOutput -and $result.ScriptOutput -ne "NO_SQL" -and -not $result.ScriptOutput.StartsWith("ERROR:")) {
                $parts = $result.ScriptOutput.Split("|")
                $mockResult = [PSCustomObject]@{
                    Edition = $parts[0]
                    ProductVersion = if ($parts.Length -gt 1) { $parts[1] } else { "" }
                }
                return $this.ProcessSQLResult($mockResult, "VMware Tools")
            } else {
                return $this.GetPatternBasedDetection($VM)
            }
            
        } catch {
            Write-Debug "VMware Tools method failed for $($VM.Name): $_"
            return $this.GetPatternBasedDetection($VM)
        }
    }
    
    # Fallback: Pattern-based detection (your existing method)
    [PSCustomObject] GetPatternBasedDetection([object] $VM) {
        $sqlEdition = ""
        $vmName = $VM.Name
        $osName = $VM.Guest.OSFullName
        
        if ($vmName -match "sql|database" -or $osName -match "sql") {
            $sqlEdition = "SQL Server Standard Edition"  # Default assumption
        }
        
        return [PSCustomObject]@{
            HasSQLServer = ($sqlEdition -ne "")
            Edition = $sqlEdition
            EditionCategory = $sqlEdition
            ProductVersion = ""
            IsClustered = $false
            ServerInstance = ""
            DetectionMethod = "Pattern Matching"
        }
    }
    
    # Helper method to process SQL query results
    [PSCustomObject] ProcessSQLResult([object] $Result, [string] $Method) {
        $editionCategory = ""
        if ($Result.Edition -like "*Enterprise*") {
            $editionCategory = "SQL Server Enterprise Edition"
        } elseif ($Result.Edition -like "*Standard*") {
            $editionCategory = "SQL Server Standard Edition"
        } elseif ($Result.Edition -like "*Developer*") {
            $editionCategory = "SQL Server Developer Edition"
        } elseif ($Result.Edition -like "*Express*") {
            $editionCategory = "SQL Server Express Edition"
        } else {
            $editionCategory = $Result.Edition
        }
        
        return [PSCustomObject]@{
            HasSQLServer = $true
            Edition = $Result.Edition
            EditionCategory = $editionCategory
            ProductVersion = $Result.ProductVersion
            IsClustered = $false  # Could be enhanced
            ServerInstance = ""
            DetectionMethod = $Method
        }
    }
    
    # Helper methods (same as before)
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
    
    [bool] TestSQLConnection([string] $Server, [int] $Port) {
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connect = $tcpClient.BeginConnect($Server, $Port, $null, $null)
            $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)
            
            if ($wait) {
                $tcpClient.EndConnect($connect)
                $tcpClient.Close()
                return $true
            } else {
                $tcpClient.Close()
                return $false
            }
        } catch {
            return $false
        }
    }
}