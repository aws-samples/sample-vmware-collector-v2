#
# MultiCredentialDatabaseConfig.ps1 - Configuration for multiple database credential sets
#
# Supports multiple authentication methods per database type for complex environments
#

class MultiCredentialDatabaseConfig {
    [hashtable] $DatabaseConfigs
    [hashtable] $CredentialSets
    [int] $ConnectionTimeout
    
    MultiCredentialDatabaseConfig() {
        $this.DatabaseConfigs = @{
            SQLServer = @{ Enabled = $false }
            PostgreSQL = @{ Enabled = $false }
            Oracle = @{ Enabled = $false }
            MySQL = @{ Enabled = $false }
            MariaDB = @{ Enabled = $false }
        }
        
        $this.CredentialSets = @{
            SQLServer = @{}
            PostgreSQL = @{}
            Oracle = @{}
            MySQL = @{}
            MariaDB = @{}
        }
        
        $this.ConnectionTimeout = 5
    }
    
    # Add SQL Server credential set
    [void] AddSQLServerCredentials([string] $Name, [bool] $UseWindowsAuth, [string] $Username = "", [string] $Password = "") {
        $this.CredentialSets.SQLServer[$Name] = @{
            UseWindowsAuth = $UseWindowsAuth
            Username = $Username
            Password = $Password
        }
        $this.DatabaseConfigs.SQLServer.Enabled = $true
    }
    
    # Add PostgreSQL credential set
    [void] AddPostgreSQLCredentials([string] $Name, [string] $Username, [string] $Password, [string] $Database = "postgres") {
        $this.CredentialSets.PostgreSQL[$Name] = @{
            Username = $Username
            Password = $Password
            Database = $Database
        }
        $this.DatabaseConfigs.PostgreSQL.Enabled = $true
    }
    
    # Add Oracle credential set
    [void] AddOracleCredentials([string] $Name, [string] $Username, [string] $Password, [string] $ServiceName = "XE") {
        $this.CredentialSets.Oracle[$Name] = @{
            Username = $Username
            Password = $Password
            ServiceName = $ServiceName
        }
        $this.DatabaseConfigs.Oracle.Enabled = $true
    }
    
    # Add MySQL credential set
    [void] AddMySQLCredentials([string] $Name, [string] $Username, [string] $Password, [string] $Database = "mysql") {
        $this.CredentialSets.MySQL[$Name] = @{
            Username = $Username
            Password = $Password
            Database = $Database
        }
        $this.DatabaseConfigs.MySQL.Enabled = $true
    }
    
    # Add MariaDB credential set
    [void] AddMariaDBCredentials([string] $Name, [string] $Username, [string] $Password, [string] $Database = "mysql") {
        $this.CredentialSets.MariaDB[$Name] = @{
            Username = $Username
            Password = $Password
            Database = $Database
        }
        $this.DatabaseConfigs.MariaDB.Enabled = $true
    }
    
    # Create from JSON configuration file
    static [MultiCredentialDatabaseConfig] FromJsonFile([string] $FilePath) {
        # Use secure validator
        . "$PSScriptRoot\ConfigurationValidator.ps1"
        $validator = [ConfigurationValidator]::new()
        
        # Validate configuration file securely
        $validatedConfig = $validator.ValidateConfigurationFile($FilePath)
        
        $config = [MultiCredentialDatabaseConfig]::new()
        
        # Process validated configuration
        foreach ($dbType in $validatedConfig.Keys) {
            $config.DatabaseConfigs.$dbType.Enabled = $true
            
            foreach ($credSet in $validatedConfig[$dbType]) {
                $credSetName = if ($credSet.Description) { $credSet.Description } else { "Default" }
                
                switch ($dbType) {
                    'SQLServer' {
                        $useWindowsAuth = ($credSet.AuthMode -eq 'Windows')
                        $config.AddSQLServerCredentials($credSetName, $useWindowsAuth, $credSet.Username, $credSet.Password)
                    }
                    'PostgreSQL' {
                        $config.AddPostgreSQLCredentials($credSetName, $credSet.Username, $credSet.Password)
                    }
                    'Oracle' {
                        $config.AddOracleCredentials($credSetName, $credSet.Username, $credSet.Password)
                    }
                    'MySQL' {
                        $config.AddMySQLCredentials($credSetName, $credSet.Username, $credSet.Password)
                    }
                    'MariaDB' {
                        $config.AddMariaDBCredentials($credSetName, $credSet.Username, $credSet.Password)
                    }
                }
            }
        }
        
        return $config
    }
    
    # Export to JSON configuration file
    [void] ExportToJsonFile([string] $FilePath) {
        $exportData = @{
            ConnectionTimeout = $this.ConnectionTimeout
            SQLServer = @{
                Enabled = $this.DatabaseConfigs.SQLServer.Enabled
                CredentialSets = $this.CredentialSets.SQLServer
            }
            PostgreSQL = @{
                Enabled = $this.DatabaseConfigs.PostgreSQL.Enabled
                CredentialSets = $this.CredentialSets.PostgreSQL
            }
            Oracle = @{
                Enabled = $this.DatabaseConfigs.Oracle.Enabled
                CredentialSets = $this.CredentialSets.Oracle
            }
            MySQL = @{
                Enabled = $this.DatabaseConfigs.MySQL.Enabled
                CredentialSets = $this.CredentialSets.MySQL
            }
            MariaDB = @{
                Enabled = $this.DatabaseConfigs.MariaDB.Enabled
                CredentialSets = $this.CredentialSets.MariaDB
            }
        }
        
        $exportData | ConvertTo-Json -Depth 4 | Set-Content $FilePath
    }
    
    # Get summary of configured credential sets
    [hashtable] GetCredentialSummary() {
        $summary = @{}
        
        foreach ($dbType in @('SQLServer', 'PostgreSQL', 'Oracle', 'MySQL', 'MariaDB')) {
            $summary[$dbType] = @{
                Enabled = $this.DatabaseConfigs.$dbType.Enabled
                CredentialSetCount = $this.CredentialSets.$dbType.Count
                CredentialSetNames = @($this.CredentialSets.$dbType.Keys)
            }
        }
        
        return $summary
    }
    
    # Validate configuration
    [array] ValidateConfiguration() {
        $errors = @()
        
        foreach ($dbType in @('SQLServer', 'PostgreSQL', 'Oracle', 'MySQL', 'MariaDB')) {
            if ($this.DatabaseConfigs.$dbType.Enabled) {
                if ($this.CredentialSets.$dbType.Count -eq 0) {
                    $errors += "Database type '$dbType' is enabled but has no credential sets configured"
                }
                
                foreach ($credSetName in $this.CredentialSets.$dbType.Keys) {
                    $credSet = $this.CredentialSets.$dbType[$credSetName]
                    
                    switch ($dbType) {
                        'SQLServer' {
                            if (-not $credSet.UseWindowsAuth -and (-not $credSet.Username -or -not $credSet.Password)) {
                                $errors += "SQL Server credential set '$credSetName' requires username and password for SQL authentication"
                            }
                        }
                        { $_ -in @('PostgreSQL', 'Oracle', 'MySQL', 'MariaDB') } {
                            if (-not $credSet.Username -or -not $credSet.Password) {
                                $errors += "$dbType credential set '$credSetName' requires username and password"
                            }
                        }
                    }
                }
            }
        }
        
        return $errors
    }
}