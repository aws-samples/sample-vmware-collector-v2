#
# MultiCredentialDatabaseDetector.ps1 - Enhanced database detection with multiple credential support
#
# Supports multiple credential sets per database type for environments with different authentication requirements
#

class MultiCredentialDatabaseDetector {
    [hashtable] $CredentialSets
    [hashtable] $DatabaseConfigs
    [int] $ConnectionTimeout
    [object] $Logger
    
    # Static configuration for supported databases
    static [hashtable] $DatabasePorts = @{
        'SQLServer' = @(1433, 1434, 2433, 3433)
        'Oracle' = @(1521, 1522, 1526, 1527)
        'MySQL' = @(3306, 3307, 33060)
        'MariaDB' = @(3306, 3307)
        'PostgreSQL' = @(5432, 5433, 5434)
    }
    
    # Detection queries for each database type
    static [hashtable] $DetectionQueries = @{
        'SQLServer' = @"
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
        'PostgreSQL' = "SELECT version() as version, current_setting('server_version') as product_version"
        'Oracle' = "SELECT banner as version, version as product_version FROM v`$version WHERE banner LIKE 'Oracle%'"
        'MySQL' = "SELECT VERSION() as version, @@version_comment as edition, @@hostname as hostname"
        'MariaDB' = "SELECT VERSION() as version, @@version_comment as edition, @@hostname as hostname"
    }
    
    MultiCredentialDatabaseDetector([hashtable] $CredentialSets, [hashtable] $DatabaseConfigs, [object] $Logger) {
        $this.CredentialSets = $CredentialSets
        $this.DatabaseConfigs = $DatabaseConfigs
        $this.ConnectionTimeout = 5
        $this.Logger = $Logger
    }
    
    # Main method to detect all enabled databases on a VM with multiple credential attempts
    [PSCustomObject] DetectDatabases([object] $VM) {
        $databaseInfo = $this.GetDefaultDatabaseInfo()
        
        try {
            # Get VM IP address
            $ipAddress = $this.GetVMIPAddress($VM)
            if (-not $ipAddress) {
                return $databaseInfo
            }
            
            $this.Logger.WriteDebug("Scanning VM $($VM.Name) at $ipAddress for databases with multiple credential sets")
            
            # Check each enabled database type
            foreach ($dbType in $this.DatabaseConfigs.Keys) {
                if ($this.DatabaseConfigs[$dbType].Enabled) {
                    $this.Logger.WriteDebug("Checking for $dbType on $($VM.Name)")
                    $detection = $this.DetectSpecificDatabaseWithMultipleCredentials($ipAddress, $dbType)
                    
                    if ($detection.Found) {
                        $databaseInfo.$dbType = $detection
                        $this.Logger.WriteInformation("Found $dbType on $($VM.Name): $($detection.ProductVersion) (using credential set: $($detection.CredentialSetUsed))")
                    }
                }
            }
        }
        catch {
            $this.Logger.WriteDebug("Database detection failed for VM $($VM.Name): $_")
        }
        
        return $databaseInfo
    }
    
    # Detect specific database type with multiple credential attempts
    [PSCustomObject] DetectSpecificDatabaseWithMultipleCredentials([string] $IPAddress, [string] $DatabaseType) {
        $ports = [MultiCredentialDatabaseDetector]::DatabasePorts[$DatabaseType]
        
        foreach ($port in $ports) {
            if ($this.TestDatabaseConnection($IPAddress, $port, $DatabaseType)) {
                $this.Logger.WriteDebug("$DatabaseType responding on $IPAddress`:$port")
                
                # Try each credential set for this database type
                $availableCredentialSets = $this.CredentialSets[$DatabaseType]
                if ($availableCredentialSets -and $availableCredentialSets.Count -gt 0) {
                    foreach ($credSetName in $availableCredentialSets.Keys) {
                        $credSet = $availableCredentialSets[$credSetName]
                        $this.Logger.WriteDebug("Trying credential set '$credSetName' for $DatabaseType on $IPAddress`:$port")
                        
                        $details = $this.GetDatabaseDetailsWithCredentials($IPAddress, $port, $DatabaseType, $credSet, $credSetName)
                        if ($details.Found) {
                            return $details
                        }
                    }
                }
                
                # If no credential sets work, try default/anonymous connection
                $details = $this.GetDatabaseDetailsWithCredentials($IPAddress, $port, $DatabaseType, $null, "Default")
                if ($details.Found) {
                    return $details
                }
            }
        }
        
        return $this.GetDefaultDatabaseTypeInfo($DatabaseType)
    }
    
    # Get detailed database information with specific credentials
    [PSCustomObject] GetDatabaseDetailsWithCredentials([string] $Server, [int] $Port, [string] $DatabaseType, [hashtable] $Credentials, [string] $CredentialSetName) {
        try {
            switch ($DatabaseType) {
                'SQLServer' { return $this.GetSQLServerDetailsWithCredentials($Server, $Port, $Credentials, $CredentialSetName) }
                'PostgreSQL' { return $this.GetPostgreSQLDetailsWithCredentials($Server, $Port, $Credentials, $CredentialSetName) }
                'Oracle' { return $this.GetOracleDetailsWithCredentials($Server, $Port, $Credentials, $CredentialSetName) }
                'MySQL' { return $this.GetMySQLDetailsWithCredentials($Server, $Port, $Credentials, $CredentialSetName) }
                'MariaDB' { return $this.GetMariaDBDetailsWithCredentials($Server, $Port, $Credentials, $CredentialSetName) }
                default { return $this.GetDefaultDatabaseTypeInfo($DatabaseType) }
            }
        }
        catch {
            $this.Logger.WriteDebug("Failed to get $DatabaseType details from $Server`:$Port using credential set '$CredentialSetName' - $_")
            return $this.GetDefaultDatabaseTypeInfo($DatabaseType)
        }
        
        # Fallback return (should never reach here due to switch default)
        return $this.GetDefaultDatabaseTypeInfo($DatabaseType)
    }
    
    # SQL Server with specific credentials
    [PSCustomObject] GetSQLServerDetailsWithCredentials([string] $Server, [int] $Port, [hashtable] $Credentials, [string] $CredentialSetName) {
        $serverInstance = if ($Port -eq 1433) { $Server } else { "$Server,$Port" }
        
        try {
            $query = [MultiCredentialDatabaseDetector]::DetectionQueries['SQLServer']
            
            if ($Credentials -and $Credentials.UseWindowsAuth) {
                $result = Invoke-Sqlcmd -ServerInstance $serverInstance -Database "master" -Query $query -TrustServerCertificate -ConnectionTimeout $this.ConnectionTimeout -ErrorAction Stop
            }
            elseif ($Credentials -and $Credentials.Username) {
                $result = Invoke-Sqlcmd -ServerInstance $serverInstance -Database "master" -Query $query -Username $Credentials.Username -Password $Credentials.Password -TrustServerCertificate -ConnectionTimeout $this.ConnectionTimeout -ErrorAction Stop
            }
            else {
                # Try integrated security as fallback
                $result = Invoke-Sqlcmd -ServerInstance $serverInstance -Database "master" -Query $query -TrustServerCertificate -ConnectionTimeout $this.ConnectionTimeout -ErrorAction Stop
            }
            
            return [PSCustomObject]@{
                Found = $true
                DatabaseType = 'SQLServer'
                Edition = $result.Edition
                EditionCategory = $result.EditionCategory
                ProductVersion = $result.ProductVersion
                IsClustered = $result.IsClustered
                ServerInstance = $serverInstance
                DetectionMethod = "Direct SQL Query"
                Port = $Port
                CredentialSetUsed = $CredentialSetName
            }
        }
        catch {
            return $this.GetDefaultDatabaseTypeInfo('SQLServer')
        }
    }
    
    # PostgreSQL with specific credentials
    [PSCustomObject] GetPostgreSQLDetailsWithCredentials([string] $Server, [int] $Port, [hashtable] $Credentials, [string] $CredentialSetName) {
        if (-not $Credentials -or -not $Credentials.Username) {
            return $this.GetDefaultDatabaseTypeInfo('PostgreSQL')
        }
        
        $connectionString = "Host=$Server;Port=$Port;Database=postgres;Username=$($Credentials.Username);Password=$($Credentials.Password);Timeout=$($this.ConnectionTimeout);"
        
        try {
            # Try .NET provider first
            Add-Type -Path "$env:ProgramFiles\PostgreSQL\*\Npgsql.dll" -ErrorAction SilentlyContinue
            
            $connection = New-Object Npgsql.NpgsqlConnection($connectionString)
            $connection.Open()
            
            $command = $connection.CreateCommand()
            $command.CommandText = [MultiCredentialDatabaseDetector]::DetectionQueries['PostgreSQL']
            $command.CommandTimeout = $this.ConnectionTimeout
            
            $reader = $command.ExecuteReader()
            if ($reader.Read()) {
                $version = $reader["version"].ToString()
                $productVersion = $reader["product_version"].ToString()
                
                $reader.Close()
                $connection.Close()
                
                return [PSCustomObject]@{
                    Found = $true
                    DatabaseType = 'PostgreSQL'
                    Version = $version
                    ProductVersion = $productVersion
                    Edition = $this.ParsePostgreSQLEdition($version)
                    ServerInstance = "$Server`:$Port"
                    DetectionMethod = "Direct PostgreSQL Query"
                    Port = $Port
                    CredentialSetUsed = $CredentialSetName
                }
            }
            
            $reader.Close()
            $connection.Close()
        }
        catch {
            # Fallback to psql command
            return $this.GetPostgreSQLDetailsViaPsqlWithCredentials($Server, $Port, $Credentials, $CredentialSetName)
        }
        
        return $this.GetDefaultDatabaseTypeInfo('PostgreSQL')
    }
    
    # MySQL with specific credentials
    [PSCustomObject] GetMySQLDetailsWithCredentials([string] $Server, [int] $Port, [hashtable] $Credentials, [string] $CredentialSetName) {
        if (-not $Credentials -or -not $Credentials.Username) {
            return $this.GetDefaultDatabaseTypeInfo('MySQL')
        }
        
        $connectionString = "Server=$Server;Port=$Port;Database=mysql;Uid=$($Credentials.Username);Pwd=$($Credentials.Password);Connection Timeout=$($this.ConnectionTimeout);"
        
        try {
            Add-Type -Path "$env:ProgramFiles\MySQL\MySQL Connector Net*\Assemblies\*\MySql.Data.dll" -ErrorAction SilentlyContinue
            
            $connection = New-Object MySql.Data.MySqlClient.MySqlConnection($connectionString)
            $connection.Open()
            
            $command = $connection.CreateCommand()
            $command.CommandText = [MultiCredentialDatabaseDetector]::DetectionQueries['MySQL']
            $command.CommandTimeout = $this.ConnectionTimeout
            
            $reader = $command.ExecuteReader()
            if ($reader.Read()) {
                $version = $reader["version"].ToString()
                $edition = $reader["edition"].ToString()
                
                $reader.Close()
                $connection.Close()
                
                return [PSCustomObject]@{
                    Found = $true
                    DatabaseType = 'MySQL'
                    Version = $version
                    ProductVersion = $this.ParseMySQLVersion($version)
                    Edition = $edition
                    ServerInstance = "$Server`:$Port"
                    DetectionMethod = "Direct MySQL Query"
                    Port = $Port
                    CredentialSetUsed = $CredentialSetName
                }
            }
            
            $reader.Close()
            $connection.Close()
        }
        catch {
            return $this.GetMySQLDetailsViaMysqlWithCredentials($Server, $Port, $Credentials, $CredentialSetName)
        }
        
        return $this.GetDefaultDatabaseTypeInfo('MySQL')
    }
    
    # Oracle with specific credentials
    [PSCustomObject] GetOracleDetailsWithCredentials([string] $Server, [int] $Port, [hashtable] $Credentials, [string] $CredentialSetName) {
        if (-not $Credentials -or -not $Credentials.Username) {
            return $this.GetDefaultDatabaseTypeInfo('Oracle')
        }
        
        $serviceName = if ($Credentials.ServiceName) { $Credentials.ServiceName } else { "XE" }
        $connectionString = "Data Source=$Server`:$Port/$serviceName;User Id=$($Credentials.Username);Password=$($Credentials.Password);Connection Timeout=$($this.ConnectionTimeout);"
        
        try {
            Add-Type -Path "$env:ORACLE_HOME\ODP.NET\bin\4\Oracle.DataAccess.dll" -ErrorAction SilentlyContinue
            
            $connection = New-Object Oracle.DataAccess.Client.OracleConnection($connectionString)
            $connection.Open()
            
            $command = $connection.CreateCommand()
            $command.CommandText = [MultiCredentialDatabaseDetector]::DetectionQueries['Oracle']
            $command.CommandTimeout = $this.ConnectionTimeout
            
            $reader = $command.ExecuteReader()
            if ($reader.Read()) {
                $version = $reader["version"].ToString()
                $productVersion = $reader["product_version"].ToString()
                
                $reader.Close()
                $connection.Close()
                
                return [PSCustomObject]@{
                    Found = $true
                    DatabaseType = 'Oracle'
                    Version = $version
                    ProductVersion = $productVersion
                    Edition = $this.ParseOracleEdition($version)
                    ServerInstance = "$Server`:$Port/$serviceName"
                    DetectionMethod = "Direct Oracle Query"
                    Port = $Port
                    CredentialSetUsed = $CredentialSetName
                }
            }
            
            $reader.Close()
            $connection.Close()
        }
        catch {
            return $this.GetOracleDetailsViaSqlplusWithCredentials($Server, $Port, $Credentials, $CredentialSetName)
        }
        
        return $this.GetDefaultDatabaseTypeInfo('Oracle')
    }
    
    # Test database connectivity
    [bool] TestDatabaseConnection([string] $Server, [int] $Port, [string] $DatabaseType) {
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
    
    # Helper methods for parsing versions and editions
    [string] ParsePostgreSQLEdition([string] $VersionString) {
        if ($VersionString -match 'PostgreSQL (\d+)') {
            return "PostgreSQL $($matches[1])"
        }
        return "PostgreSQL"
    }
    
    [string] ParseMySQLVersion([string] $VersionString) {
        if ($VersionString -match '^(\d+\.\d+\.\d+)') {
            return $matches[1]
        }
        return "Unknown"
    }
    
    [string] ParseOracleEdition([string] $VersionString) {
        if ($VersionString -match 'Enterprise Edition') { return "Enterprise Edition" }
        if ($VersionString -match 'Standard Edition') { return "Standard Edition" }
        if ($VersionString -match 'Express Edition') { return "Express Edition" }
        return "Oracle Database"
    }
    
    # Get VM IP address
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
    
    # Default database info structure
    [PSCustomObject] GetDefaultDatabaseInfo() {
        return [PSCustomObject]@{
            SQLServer = $this.GetDefaultDatabaseTypeInfo('SQLServer')
            PostgreSQL = $this.GetDefaultDatabaseTypeInfo('PostgreSQL')
            Oracle = $this.GetDefaultDatabaseTypeInfo('Oracle')
            MySQL = $this.GetDefaultDatabaseTypeInfo('MySQL')
            MariaDB = $this.GetDefaultDatabaseTypeInfo('MariaDB')
        }
    }
    
    # Default info for specific database type
    [PSCustomObject] GetDefaultDatabaseTypeInfo([string] $DatabaseType) {
        return [PSCustomObject]@{
            Found = $false
            DatabaseType = $DatabaseType
            Version = ""
            ProductVersion = ""
            Edition = ""
            ServerInstance = ""
            DetectionMethod = "None"
            Port = 0
            CredentialSetUsed = ""
        }
    }
}