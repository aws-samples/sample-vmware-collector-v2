#
# DatabaseDetector.ps1 - Unified database detection for multiple database engines
#
# Extends the existing SQL Server detection to support Oracle, MySQL, MariaDB, and PostgreSQL
# Maintains the same architecture patterns as SQLServerDetector for consistency
#

class DatabaseDetector {
    [hashtable] $Credentials
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
        'PostgreSQL' = @"
SELECT version() as version,
       current_setting('server_version') as product_version,
       current_setting('shared_preload_libraries') as extensions,
       current_database() as database_name
"@
        'Oracle' = @"
SELECT banner as version,
       version as product_version,
       'Oracle Database' as edition_category
FROM v`$version 
WHERE banner LIKE 'Oracle%'
"@
        'MySQL' = @"
SELECT VERSION() as version,
       @@version_comment as edition,
       @@hostname as hostname,
       'MySQL' as engine_type
"@
        'MariaDB' = @"
SELECT VERSION() as version,
       @@version_comment as edition,
       @@hostname as hostname,
       'MariaDB' as engine_type
"@
    }
    
    DatabaseDetector([hashtable] $Credentials, [hashtable] $DatabaseConfigs, [object] $Logger) {
        $this.Credentials = $Credentials
        $this.DatabaseConfigs = $DatabaseConfigs
        $this.ConnectionTimeout = 5
        $this.Logger = $Logger
    }
    
    # Main method to detect all enabled databases on a VM
    [PSCustomObject] DetectDatabases([object] $VM) {
        $databaseInfo = $this.GetDefaultDatabaseInfo()
        
        try {
            # Get VM IP address
            $ipAddress = $this.GetVMIPAddress($VM)
            if (-not $ipAddress) {
                return $databaseInfo
            }
            
            $this.Logger.WriteDebug("Scanning VM $($VM.Name) at $ipAddress for databases")
            
            # Check each enabled database type
            foreach ($dbType in $this.DatabaseConfigs.Keys) {
                if ($this.DatabaseConfigs[$dbType].Enabled) {
                    $this.Logger.WriteDebug("Checking for $dbType on $($VM.Name)")
                    $detection = $this.DetectSpecificDatabase($ipAddress, $dbType)
                    
                    if ($detection.Found) {
                        $databaseInfo.$dbType = $detection
                        $this.Logger.WriteInformation("Found $dbType on $($VM.Name): $($detection.ProductVersion)")
                    }
                }
            }
        }
        catch {
            $this.Logger.WriteDebug("Database detection failed for VM $($VM.Name): $_")
        }
        
        return $databaseInfo
    }
    
    # Detect specific database type
    [PSCustomObject] DetectSpecificDatabase([string] $IPAddress, [string] $DatabaseType) {
        $ports = [DatabaseDetector]::DatabasePorts[$DatabaseType]
        
        foreach ($port in $ports) {
            if ($this.TestDatabaseConnection($IPAddress, $port, $DatabaseType)) {
                $this.Logger.WriteDebug("$DatabaseType responding on $IPAddress`:$port")
                
                # Get detailed information
                $details = $this.GetDatabaseDetails($IPAddress, $port, $DatabaseType)
                if ($details.Found) {
                    return $details
                }
            }
        }
        
        return $this.GetDefaultDatabaseTypeInfo($DatabaseType)
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
    
    # Get detailed database information
    [PSCustomObject] GetDatabaseDetails([string] $Server, [int] $Port, [string] $DatabaseType) {
        try {
            switch ($DatabaseType) {
                'SQLServer' { return $this.GetSQLServerDetails($Server, $Port) }
                'PostgreSQL' { return $this.GetPostgreSQLDetails($Server, $Port) }
                'Oracle' { return $this.GetOracleDetails($Server, $Port) }
                'MySQL' { return $this.GetMySQLDetails($Server, $Port) }
                'MariaDB' { return $this.GetMariaDBDetails($Server, $Port) }
                default { return $this.GetDefaultDatabaseTypeInfo($DatabaseType) }
            }
        }
        catch {
            $this.Logger.WriteDebug("Failed to get $DatabaseType details from $Server`:$Port - $_")
            return $this.GetDefaultDatabaseTypeInfo($DatabaseType)
        }
        
        # Fallback return (should never reach here)
        return $this.GetDefaultDatabaseTypeInfo($DatabaseType)
    }
    
    # PostgreSQL-specific detection
    [PSCustomObject] GetPostgreSQLDetails([string] $Server, [int] $Port) {
        $connectionString = "Host=$Server;Port=$Port;Database=postgres;Timeout=$($this.ConnectionTimeout);"
        
        # Add authentication
        if ($this.Credentials.PostgreSQL.Username) {
            $connectionString += "Username=$($this.Credentials.PostgreSQL.Username);Password=$($this.Credentials.PostgreSQL.Password);"
        }
        
        try {
            # Use .NET PostgreSQL provider if available
            Add-Type -Path "$env:ProgramFiles\PostgreSQL\*\Npgsql.dll" -ErrorAction SilentlyContinue
            
            $connection = New-Object Npgsql.NpgsqlConnection($connectionString)
            $connection.Open()
            
            $command = $connection.CreateCommand()
            $command.CommandText = [DatabaseDetector]::DetectionQueries['PostgreSQL']
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
                }
            }
            
            $reader.Close()
            $connection.Close()
        }
        catch {
            # Fallback to psql command if .NET provider not available
            return $this.GetPostgreSQLDetailsViaPsql($Server, $Port)
        }
        
        return $this.GetDefaultDatabaseTypeInfo('PostgreSQL')
    }
    
    # Fallback PostgreSQL detection using psql command
    [PSCustomObject] GetPostgreSQLDetailsViaPsql([string] $Server, [int] $Port) {
        try {
            $env:PGPASSWORD = $this.Credentials.PostgreSQL.Password
            $psqlCmd = "psql -h $Server -p $Port -U $($this.Credentials.PostgreSQL.Username) -d postgres -t -c `"SELECT version();`""
            
            $result = Invoke-Expression $psqlCmd 2>$null
            if ($result -and $result.Trim()) {
                $version = $result.Trim()
                
                return [PSCustomObject]@{
                    Found = $true
                    DatabaseType = 'PostgreSQL'
                    Version = $version
                    ProductVersion = $this.ParsePostgreSQLVersion($version)
                    Edition = $this.ParsePostgreSQLEdition($version)
                    ServerInstance = "$Server`:$Port"
                    DetectionMethod = "psql Command"
                    Port = $Port
                }
            }
        }
        catch {
            $this.Logger.WriteDebug("psql fallback failed: $_")
        }
        finally {
            Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
        }
        
        return $this.GetDefaultDatabaseTypeInfo('PostgreSQL')
    }
    
    # Parse PostgreSQL version information
    [string] ParsePostgreSQLVersion([string] $VersionString) {
        if ($VersionString -match 'PostgreSQL (\d+\.\d+(?:\.\d+)?)') {
            return $matches[1]
        }
        return "Unknown"
    }
    
    # Parse PostgreSQL edition information
    [string] ParsePostgreSQLEdition([string] $VersionString) {
        if ($VersionString -match 'PostgreSQL (\d+)') {
            $majorVersion = [int]$matches[1]
            if ($majorVersion -ge 10) {
                return "PostgreSQL $majorVersion"
            }
        }
        return "PostgreSQL"
    }
    
    # Parse Oracle version information
    [string] ParseOracleVersion([string] $VersionString) {
        if ($VersionString -match 'Release (\d+\.\d+\.\d+\.\d+\.\d+)') {
            return $matches[1]
        }
        if ($VersionString -match 'Oracle Database (\d+c)') {
            return $matches[1]
        }
        return "Unknown"
    }
    
    # Parse Oracle edition information
    [string] ParseOracleEdition([string] $VersionString) {
        if ($VersionString -match 'Enterprise Edition') {
            return "Enterprise Edition"
        }
        if ($VersionString -match 'Standard Edition') {
            return "Standard Edition"
        }
        if ($VersionString -match 'Express Edition') {
            return "Express Edition"
        }
        if ($VersionString -match 'Oracle Database (\d+c)') {
            return "Oracle Database $($matches[1])"
        }
        return "Oracle Database"
    }
    
    # Parse MySQL version information
    [string] ParseMySQLVersion([string] $VersionString) {
        if ($VersionString -match '^(\d+\.\d+\.\d+)') {
            return $matches[1]
        }
        return "Unknown"
    }
    
    # Parse MariaDB version information
    [string] ParseMariaDBVersion([string] $VersionString) {
        if ($VersionString -match '(\d+\.\d+\.\d+)-MariaDB') {
            return $matches[1]
        }
        if ($VersionString -match '^(\d+\.\d+\.\d+)') {
            return $matches[1]
        }
        return "Unknown"
    }
    
    # Oracle-specific detection
    [PSCustomObject] GetOracleDetails([string] $Server, [int] $Port) {
        try {
            # Try Oracle .NET provider first
            $connectionString = "Data Source=$Server`:$Port/$($this.Credentials.Oracle.ServiceName);User Id=$($this.Credentials.Oracle.Username);Password=$($this.Credentials.Oracle.Password);Connection Timeout=$($this.ConnectionTimeout);"
            
            try {
                # Use Oracle .NET provider if available
                Add-Type -Path "$env:ORACLE_HOME\ODP.NET\bin\4\Oracle.DataAccess.dll" -ErrorAction SilentlyContinue
                
                $connection = New-Object Oracle.DataAccess.Client.OracleConnection($connectionString)
                $connection.Open()
                
                $command = $connection.CreateCommand()
                $command.CommandText = [DatabaseDetector]::DetectionQueries['Oracle']
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
                        ServerInstance = "$Server`:$Port/$($this.Credentials.Oracle.ServiceName)"
                        DetectionMethod = "Direct Oracle Query"
                        Port = $Port
                    }
                }
                
                $reader.Close()
                $connection.Close()
            }
            catch {
                # Fallback to sqlplus command
                return $this.GetOracleDetailsViaSqlplus($Server, $Port)
            }
        }
        catch {
            $this.Logger.WriteDebug("Oracle detection failed: $_")
        }
        
        return $this.GetDefaultDatabaseTypeInfo('Oracle')
    }
    
    # Fallback Oracle detection using sqlplus
    [PSCustomObject] GetOracleDetailsViaSqlplus([string] $Server, [int] $Port) {
        try {
            $connectString = "$($this.Credentials.Oracle.Username)/$($this.Credentials.Oracle.Password)@$Server`:$Port/$($this.Credentials.Oracle.ServiceName)"
            $sqlplusCmd = "echo 'SELECT banner FROM v`$version WHERE banner LIKE ''Oracle%'';' | sqlplus -S $connectString"
            
            $result = Invoke-Expression $sqlplusCmd 2>$null
            if ($result -and $result.Trim() -and $result -notmatch "ERROR|ORA-") {
                $version = $result.Trim()
                
                return [PSCustomObject]@{
                    Found = $true
                    DatabaseType = 'Oracle'
                    Version = $version
                    ProductVersion = $this.ParseOracleVersion($version)
                    Edition = $this.ParseOracleEdition($version)
                    ServerInstance = "$Server`:$Port/$($this.Credentials.Oracle.ServiceName)"
                    DetectionMethod = "sqlplus Command"
                    Port = $Port
                }
            }
        }
        catch {
            $this.Logger.WriteDebug("sqlplus fallback failed: $_")
        }
        
        return $this.GetDefaultDatabaseTypeInfo('Oracle')
    }
    
    # MySQL-specific detection
    [PSCustomObject] GetMySQLDetails([string] $Server, [int] $Port) {
        try {
            $connectionString = "Server=$Server;Port=$Port;Database=mysql;Uid=$($this.Credentials.MySQL.Username);Pwd=$($this.Credentials.MySQL.Password);Connection Timeout=$($this.ConnectionTimeout);"
            
            try {
                # Use MySQL .NET Connector if available
                Add-Type -Path "$env:ProgramFiles\MySQL\MySQL Connector Net*\Assemblies\*\MySql.Data.dll" -ErrorAction SilentlyContinue
                
                $connection = New-Object MySql.Data.MySqlClient.MySqlConnection($connectionString)
                $connection.Open()
                
                $command = $connection.CreateCommand()
                $command.CommandText = [DatabaseDetector]::DetectionQueries['MySQL']
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
                    }
                }
                
                $reader.Close()
                $connection.Close()
            }
            catch {
                # Fallback to mysql command
                return $this.GetMySQLDetailsViaMysql($Server, $Port)
            }
        }
        catch {
            $this.Logger.WriteDebug("MySQL detection failed: $_")
        }
        
        return $this.GetDefaultDatabaseTypeInfo('MySQL')
    }
    
    # Fallback MySQL detection using mysql command
    [PSCustomObject] GetMySQLDetailsViaMysql([string] $Server, [int] $Port) {
        try {
            $env:MYSQL_PWD = $this.Credentials.MySQL.Password
            $mysqlCmd = "mysql -h $Server -P $Port -u $($this.Credentials.MySQL.Username) -e `"SELECT VERSION() as version, @@version_comment as edition;`""
            
            $result = Invoke-Expression $mysqlCmd 2>$null
            if ($result -and $result.Trim()) {
                $lines = $result -split "`n"
                if ($lines.Count -gt 1) {
                    $dataLine = $lines[1].Trim()
                    $parts = $dataLine -split "`t"
                    if ($parts.Count -ge 2) {
                        $version = $parts[0]
                        $edition = $parts[1]
                        
                        return [PSCustomObject]@{
                            Found = $true
                            DatabaseType = 'MySQL'
                            Version = $version
                            ProductVersion = $this.ParseMySQLVersion($version)
                            Edition = $edition
                            ServerInstance = "$Server`:$Port"
                            DetectionMethod = "mysql Command"
                            Port = $Port
                        }
                    }
                }
            }
        }
        catch {
            $this.Logger.WriteDebug("mysql fallback failed: $_")
        }
        finally {
            Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
        }
        
        return $this.GetDefaultDatabaseTypeInfo('MySQL')
    }
    
    # MariaDB-specific detection (similar to MySQL but with MariaDB identification)
    [PSCustomObject] GetMariaDBDetails([string] $Server, [int] $Port) {
        try {
            $connectionString = "Server=$Server;Port=$Port;Database=mysql;Uid=$($this.Credentials.MariaDB.Username);Pwd=$($this.Credentials.MariaDB.Password);Connection Timeout=$($this.ConnectionTimeout);"
            
            try {
                # Use MySQL .NET Connector (MariaDB is MySQL-compatible)
                Add-Type -Path "$env:ProgramFiles\MySQL\MySQL Connector Net*\Assemblies\*\MySql.Data.dll" -ErrorAction SilentlyContinue
                
                $connection = New-Object MySql.Data.MySqlClient.MySqlConnection($connectionString)
                $connection.Open()
                
                $command = $connection.CreateCommand()
                $command.CommandText = [DatabaseDetector]::DetectionQueries['MariaDB']
                $command.CommandTimeout = $this.ConnectionTimeout
                
                $reader = $command.ExecuteReader()
                if ($reader.Read()) {
                    $version = $reader["version"].ToString()
                    $edition = $reader["edition"].ToString()
                    
                    $reader.Close()
                    $connection.Close()
                    
                    # Verify it's actually MariaDB
                    if ($version -match "MariaDB") {
                        return [PSCustomObject]@{
                            Found = $true
                            DatabaseType = 'MariaDB'
                            Version = $version
                            ProductVersion = $this.ParseMariaDBVersion($version)
                            Edition = $edition
                            ServerInstance = "$Server`:$Port"
                            DetectionMethod = "Direct MariaDB Query"
                            Port = $Port
                        }
                    }
                }
                
                $reader.Close()
                $connection.Close()
            }
            catch {
                # Fallback to mysql command
                return $this.GetMariaDBDetailsViaMysql($Server, $Port)
            }
        }
        catch {
            $this.Logger.WriteDebug("MariaDB detection failed: $_")
        }
        
        return $this.GetDefaultDatabaseTypeInfo('MariaDB')
    }
    
    # Fallback MariaDB detection using mysql command
    [PSCustomObject] GetMariaDBDetailsViaMysql([string] $Server, [int] $Port) {
        try {
            $env:MYSQL_PWD = $this.Credentials.MariaDB.Password
            $mysqlCmd = "mysql -h $Server -P $Port -u $($this.Credentials.MariaDB.Username) -e `"SELECT VERSION() as version, 'MariaDB' as edition;`""
            
            $result = Invoke-Expression $mysqlCmd 2>$null
            if ($result -and $result.Trim()) {
                $lines = $result -split "`n"
                if ($lines.Count -gt 1) {
                    $dataLine = $lines[1].Trim()
                    $parts = $dataLine -split "`t"
                    if ($parts.Count -ge 1) {
                        $version = $parts[0]
                        
                        # Verify it's MariaDB
                        if ($version -match "MariaDB") {
                            return [PSCustomObject]@{
                                Found = $true
                                DatabaseType = 'MariaDB'
                                Version = $version
                                ProductVersion = $this.ParseMariaDBVersion($version)
                                Edition = "MariaDB"
                                ServerInstance = "$Server`:$Port"
                                DetectionMethod = "mysql Command"
                                Port = $Port
                            }
                        }
                    }
                }
            }
        }
        catch {
            $this.Logger.WriteDebug("MariaDB mysql fallback failed: $_")
        }
        finally {
            Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
        }
        
        return $this.GetDefaultDatabaseTypeInfo('MariaDB')
    }
    
    # SQL Server details (maintaining compatibility)
    [PSCustomObject] GetSQLServerDetails([string] $Server, [int] $Port) {
        $serverInstance = if ($Port -eq 1433) { $Server } else { "$Server,$Port" }
        
        try {
            $query = [DatabaseDetector]::DetectionQueries['SQLServer']
            
            if ($this.Credentials.SQLServer.UseWindowsAuth) {
                $result = Invoke-Sqlcmd -ServerInstance $serverInstance -Database "master" -Query $query -TrustServerCertificate -ConnectionTimeout $this.ConnectionTimeout -ErrorAction Stop
            }
            elseif ($this.Credentials.SQLServer.Username) {
                $result = Invoke-Sqlcmd -ServerInstance $serverInstance -Database "master" -Query $query -Username $this.Credentials.SQLServer.Username -Password $this.Credentials.SQLServer.Password -TrustServerCertificate -ConnectionTimeout $this.ConnectionTimeout -ErrorAction Stop
            }
            else {
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
            }
        }
        catch {
            return $this.GetDefaultDatabaseTypeInfo('SQLServer')
        }
    }
    
    # Get VM IP address (reused from existing logic)
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
        }
    }
}