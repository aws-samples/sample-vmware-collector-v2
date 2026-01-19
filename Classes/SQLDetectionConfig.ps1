class SQLDetectionConfig {
    [bool] $EnableSQLDetection
    [bool] $UseWindowsAuth
    [string] $Username
    [string] $Password
    [int] $ConnectionTimeout
    [string[]] $ExcludeVMPatterns
    [string[]] $IncludeVMPatterns
    
    SQLDetectionConfig() {
        $this.EnableSQLDetection = $false
        $this.UseWindowsAuth = $true
        $this.Username = ""
        $this.Password = ""
        $this.ConnectionTimeout = 5
        $this.ExcludeVMPatterns = @()
        $this.IncludeVMPatterns = @()
    }
    
    # Create from parameters
    static [SQLDetectionConfig] FromParameters([hashtable] $Parameters) {
        $config = [SQLDetectionConfig]::new()
        
        if ($Parameters.ContainsKey('EnableSQLDetection')) {
            $config.EnableSQLDetection = $Parameters.EnableSQLDetection
        }
        
        if ($Parameters.ContainsKey('SQLAuthMode')) {
            $config.UseWindowsAuth = ($Parameters.SQLAuthMode -eq 'Windows')
        }
        
        if ($Parameters.ContainsKey('SQLUsername')) {
            $config.Username = $Parameters.SQLUsername
        }
        
        if ($Parameters.ContainsKey('SQLPassword')) {
            $config.Password = $Parameters.SQLPassword
        }
        
        if ($Parameters.ContainsKey('SQLConnectionTimeout')) {
            $config.ConnectionTimeout = $Parameters.SQLConnectionTimeout
        }
        
        return $config
    }
    
    # Check if VM should be scanned for SQL
    [bool] ShouldScanVM([object] $VM) {
        if (-not $this.EnableSQLDetection) {
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
    
    # Get credentials hashtable for SQL detector
    [hashtable] GetCredentials() {
        return @{
            UseWindowsAuth = $this.UseWindowsAuth
            Username = $this.Username
            Password = $this.Password
        }
    }
}