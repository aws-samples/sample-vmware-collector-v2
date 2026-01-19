#
# DatabaseDetectionConfig.ps1 - Configuration management for multi-database detection
#
# Extends SQLDetectionConfig to support multiple database types with individual settings
#

class DatabaseDetectionConfig {
    [hashtable] $DatabaseConfigs
    [hashtable] $Credentials
    [int] $ConnectionTimeout
    [string[]] $ExcludeVMPatterns
    [string[]] $IncludeVMPatterns
    
    DatabaseDetectionConfig() {
        $this.ConnectionTimeout = 5
        $this.ExcludeVMPatterns = @()
        $this.IncludeVMPatterns = @()
        
        # Initialize default database configurations
        $this.DatabaseConfigs = @{
            'SQLServer' = @{
                Enabled = $false
                Ports = @(1433, 1434, 2433, 3433)
                DefaultDatabase = 'master'
            }
            'PostgreSQL' = @{
                Enabled = $false
                Ports = @(5432, 5433, 5434)
                DefaultDatabase = 'postgres'
            }
            'Oracle' = @{
                Enabled = $false
                Ports = @(1521, 1522, 1526, 1527)
                DefaultDatabase = 'XE'
            }
            'MySQL' = @{
                Enabled = $false
                Ports = @(3306, 3307, 33060)
                DefaultDatabase = 'mysql'
            }
            'MariaDB' = @{
                Enabled = $false
                Ports = @(3306, 3307)
                DefaultDatabase = 'mysql'
            }
        }
        
        # Initialize default credentials
        $this.Credentials = @{
            'SQLServer' = @{
                UseWindowsAuth = $true
                Username = ""
                Password = ""
            }
            'PostgreSQL' = @{
                Username = "postgres"
                Password = ""
            }
            'Oracle' = @{
                Username = "system"
                Password = ""
                ServiceName = "XE"
            }
            'MySQL' = @{
                Username = "root"
                Password = ""
            }
            'MariaDB' = @{
                Username = "root"
                Password = ""
            }
        }
    }
    
    # Create configuration from parameters (maintains backward compatibility)
    static [DatabaseDetectionConfig] FromParameters([hashtable] $Parameters) {
        $config = [DatabaseDetectionConfig]::new()
        
        # Legacy SQL Server parameters (backward compatibility)
        if ($Parameters.ContainsKey('EnableSQLDetection')) {
            $config.DatabaseConfigs.SQLServer.Enabled = $Parameters.EnableSQLDetection
        }
        
        if ($Parameters.ContainsKey('SQLAuthMode')) {
            $config.Credentials.SQLServer.UseWindowsAuth = ($Parameters.SQLAuthMode -eq 'Windows')
        }
        
        if ($Parameters.ContainsKey('SQLUsername')) {
            $config.Credentials.SQLServer.Username = $Parameters.SQLUsername
        }
        
        if ($Parameters.ContainsKey('SQLPassword')) {
            $config.Credentials.SQLServer.Password = $Parameters.SQLPassword
        }
        
        # New database-specific parameters
        foreach ($dbType in @('PostgreSQL', 'Oracle', 'MySQL', 'MariaDB')) {
            $enableKey = "Enable$($dbType)Detection"
            if ($Parameters.ContainsKey($enableKey)) {
                $config.DatabaseConfigs.$dbType.Enabled = $Parameters.$enableKey
            }
            
            $usernameKey = "$($dbType)Username"
            if ($Parameters.ContainsKey($usernameKey)) {
                $config.Credentials.$dbType.Username = $Parameters.$usernameKey
            }
            
            $passwordKey = "$($dbType)Password"
            if ($Parameters.ContainsKey($passwordKey)) {
                $config.Credentials.$dbType.Password = $Parameters.$passwordKey
            }
        }
        
        # Oracle-specific service name
        if ($Parameters.ContainsKey('OracleServiceName')) {
            $config.Credentials.Oracle.ServiceName = $Parameters.OracleServiceName
        }
        
        # Connection timeout
        if ($Parameters.ContainsKey('DatabaseConnectionTimeout')) {
            $config.ConnectionTimeout = $Parameters.DatabaseConnectionTimeout
        }
        
        return $config
    }
    
    # Check if any database detection is enabled
    [bool] IsAnyDatabaseDetectionEnabled() {
        foreach ($dbConfig in $this.DatabaseConfigs.Values) {
            if ($dbConfig.Enabled) {
                return $true
            }
        }
        return $false
    }
    
    # Check if VM should be scanned for databases
    [bool] ShouldScanVM([object] $VM) {
        if (-not $this.IsAnyDatabaseDetectionEnabled()) {
            return $false
        }
        
        $vmName = $VM.Name
        
        # Check exclude patterns first
        foreach ($pattern in $this.ExcludeVMPatterns) {
            if ($vmName -like $pattern) {
                return $false
            }
        }
        
        # If include patterns are specified, VM must match one
        if ($this.IncludeVMPatterns.Count -gt 0) {
            $matched = $false
            foreach ($pattern in $this.IncludeVMPatterns) {
                if ($vmName -like $pattern) {
                    $matched = $true
                    break
                }
            }
            return $matched
        }
        
        return $true
    }
    
    # Get enabled database types
    [string[]] GetEnabledDatabaseTypes() {
        $enabled = @()
        foreach ($dbType in $this.DatabaseConfigs.Keys) {
            if ($this.DatabaseConfigs.$dbType.Enabled) {
                $enabled += $dbType
            }
        }
        return $enabled
    }
    
    # Get configuration summary for logging
    [string] GetConfigurationSummary() {
        $enabled = $this.GetEnabledDatabaseTypes()
        if ($enabled.Count -eq 0) {
            return "Database detection disabled"
        }
        
        return "Database detection enabled for: $($enabled -join ', ')"
    }
    
    # Validate configuration
    [hashtable] ValidateConfiguration() {
        $issues = @{
            Errors = @()
            Warnings = @()
        }
        
        foreach ($dbType in $this.DatabaseConfigs.Keys) {
            if ($this.DatabaseConfigs.$dbType.Enabled) {
                $creds = $this.Credentials.$dbType
                
                # Check for missing credentials
                switch ($dbType) {
                    'SQLServer' {
                        if (-not $creds.UseWindowsAuth -and (-not $creds.Username -or -not $creds.Password)) {
                            $issues.Warnings += "SQL Server configured for SQL Auth but missing username/password"
                        }
                    }
                    'PostgreSQL' {
                        if (-not $creds.Username) {
                            $issues.Warnings += "PostgreSQL enabled but no username specified (using default: postgres)"
                            $this.Credentials.PostgreSQL.Username = "postgres"
                        }
                    }
                    'Oracle' {
                        if (-not $creds.Username -or -not $creds.ServiceName) {
                            $issues.Warnings += "Oracle enabled but missing username or service name"
                        }
                    }
                    'MySQL' {
                        if (-not $creds.Username) {
                            $issues.Warnings += "MySQL enabled but no username specified (using default: root)"
                            $this.Credentials.MySQL.Username = "root"
                        }
                    }
                    'MariaDB' {
                        if (-not $creds.Username) {
                            $issues.Warnings += "MariaDB enabled but no username specified (using default: root)"
                            $this.Credentials.MariaDB.Username = "root"
                        }
                    }
                }
            }
        }
        
        return $issues
    }
    
    # Export configuration for external tools
    [hashtable] ExportConfiguration() {
        return @{
            DatabaseConfigs = $this.DatabaseConfigs.Clone()
            EnabledTypes = $this.GetEnabledDatabaseTypes()
            ConnectionTimeout = $this.ConnectionTimeout
            ExcludeVMPatterns = $this.ExcludeVMPatterns
            IncludeVMPatterns = $this.IncludeVMPatterns
            Summary = $this.GetConfigurationSummary()
        }
    }
}