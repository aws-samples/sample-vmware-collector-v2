#
# ConnectionManager.ps1 - VCF PowerCLI Connection Management
#
# Manages vCenter connections using VMware VCF PowerCLI with enterprise-grade
# reliability, SSL handling, and automatic reconnection capabilities.
#

# Import base interface
if (Test-Path "$PSScriptRoot\Interfaces.ps1") {
    . "$PSScriptRoot\Interfaces.ps1"
} else {
    # Define minimal interface if not found
    class IConnectionManager {
        [void] Connect() { throw "Connect method must be implemented" }
        [void] EnsureConnection() { throw "EnsureConnection method must be implemented" }
        [void] Disconnect() { throw "Disconnect method must be implemented" }
        [bool] TestConnection() { throw "TestConnection method must be implemented" }
        [void] ConfigureSSL([bool] $DisableSSL) { throw "ConfigureSSL method must be implemented" }
    }
}

class ConnectionManager : IConnectionManager {
    # Connection Properties
    [string] $VCenterAddress
    [PSCredential] $Credentials
    [bool] $IsConnected
    [bool] $DisableSSL
    [int] $RetryAttempts
    [int] $RetryDelaySeconds
    [datetime] $LastConnectionTime
    [object] $VIServerConnection
    [hashtable] $ConnectionStatistics
    
    # VCF PowerCLI specific properties
    [string] $PowerCLIVersion
    [bool] $VCFPowerCLILoaded
    [hashtable] $PowerCLIConfiguration
    
    # Connection pooling and session management properties
    [hashtable] $ConnectionPool
    [int] $MaxPoolSize
    [int] $ConnectionTimeoutSeconds
    [int] $SessionTimeoutMinutes
    [datetime] $LastActivityTime
    [bool] $AutoReconnectEnabled
    [hashtable] $SessionState
    
    # Constructor
    ConnectionManager([string] $vCenterAddress, [PSCredential] $credentials) {
        $this.VCenterAddress = $vCenterAddress
        $this.Credentials = $credentials
        $this.IsConnected = $false
        $this.DisableSSL = $false
        $this.RetryAttempts = 3
        $this.RetryDelaySeconds = 5
        $this.ConnectionStatistics = @{
            ConnectionAttempts = 0
            SuccessfulConnections = 0
            FailedConnections = 0
            ReconnectionAttempts = 0
            LastConnectionDuration = 0
            PoolHits = 0
            PoolMisses = 0
        }
        $this.PowerCLIConfiguration = @{
            InvalidCertificateAction = 'Ignore'
            ParticipateInCEIP = $false
            Scope = 'Session'
        }
        
        # Initialize connection pooling and session management
        $this.ConnectionPool = @{}
        $this.MaxPoolSize = 5
        $this.ConnectionTimeoutSeconds = 300  # 5 minutes
        $this.SessionTimeoutMinutes = 60     # 1 hour
        $this.AutoReconnectEnabled = $true
        $this.LastActivityTime = Get-Date
        $this.SessionState = @{
            SessionId = [System.Guid]::NewGuid().ToString()
            CreatedTime = Get-Date
            LastAccessTime = Get-Date
            IsActive = $false
            ConnectionCount = 0
        }
        
        $this.InitializeVCFPowerCLI()
    }
    
    # Initialize VCF PowerCLI
    [void] InitializeVCFPowerCLI() {
        try {
            # Check if VCF PowerCLI modules are available
            $vcfModules = @(
                'VMware.Vcf.SddcManager',
                'VMware.Sdk.Vcf.SddcManager', 
                'VMware.VimAutomation.Core',
                'VMware.VimAutomation.Common'
            )
            
            $missingModules = @()
            foreach ($moduleName in $vcfModules) {
                if (-not (Get-Module -Name $moduleName -ListAvailable)) {
                    $missingModules += $moduleName
                }
            }
            
            if ($missingModules.Count -gt 0) {
                throw "Required VCF PowerCLI modules are not installed: $($missingModules -join ', '). Please install VMware VCF PowerCLI."
            }
            
            # Import VCF PowerCLI modules if not already loaded
            foreach ($moduleName in $vcfModules) {
                if (-not (Get-Module -Name $moduleName)) {
                    try {
                        Import-Module $moduleName -Force -ErrorAction Stop
                        Write-Verbose "VCF PowerCLI module '$moduleName' imported successfully"
                    }
                    catch {
                        Write-Warning "Failed to import module '$moduleName': $($_.Exception.Message)"
                    }
                }
            }
            
            # Get VCF PowerCLI version from the main VCF module
            $vcfModule = Get-Module -Name VMware.Vcf.SddcManager -ErrorAction SilentlyContinue
            if (-not $vcfModule) {
                $vcfModule = Get-Module -Name VMware.Sdk.Vcf.SddcManager -ErrorAction SilentlyContinue
            }
            if (-not $vcfModule) {
                $vcfModule = Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue
            }
            
            if ($vcfModule) {
                $this.PowerCLIVersion = $vcfModule.Version.ToString()
                $this.VCFPowerCLILoaded = $true
                Write-Verbose "VCF PowerCLI initialized successfully. Version: $($this.PowerCLIVersion)"
            }
            else {
                throw "No VCF PowerCLI modules could be loaded"
            }
        }
        catch {
            $this.VCFPowerCLILoaded = $false
            throw "Failed to initialize VCF PowerCLI: $($_.Exception.Message)"
        }
    }
    
    # Configure VCF PowerCLI settings
    [void] ConfigurePowerCLI() {
        try {
            # Set PowerCLI configuration for VCF PowerCLI
            Set-PowerCLIConfiguration -InvalidCertificateAction $this.PowerCLIConfiguration.InvalidCertificateAction -Confirm:$false -Scope $this.PowerCLIConfiguration.Scope -ErrorAction Stop
            Set-PowerCLIConfiguration -ParticipateInCEIP $this.PowerCLIConfiguration.ParticipateInCEIP -Confirm:$false -Scope $this.PowerCLIConfiguration.Scope -ErrorAction Stop
            
            Write-Verbose "VCF PowerCLI configuration applied successfully"
        }
        catch {
            Write-Warning "Failed to configure VCF PowerCLI settings: $($_.Exception.Message)"
        }
    }
    
    # Main connection method
    [void] Connect() {
        if (-not $this.VCFPowerCLILoaded) {
            throw "VCF PowerCLI is not properly initialized"
        }
        
        $this.ConnectionStatistics.ConnectionAttempts++
        $connectionStart = Get-Date
        
        try {
            Write-Verbose "Attempting to connect to vCenter: $($this.VCenterAddress) using VCF PowerCLI"
            
            # Configure PowerCLI settings
            $this.ConfigurePowerCLI()
            
            # Attempt connection using VCF PowerCLI Connect-VIServer
            $this.VIServerConnection = Connect-VIServer -Server $this.VCenterAddress -Credential $this.Credentials -ErrorAction Stop
            
            # Verify connection
            if ($this.VIServerConnection -and $this.VIServerConnection.IsConnected) {
                $this.IsConnected = $true
                $this.LastConnectionTime = Get-Date
                $this.ConnectionStatistics.SuccessfulConnections++
                $this.ConnectionStatistics.LastConnectionDuration = ((Get-Date) - $connectionStart).TotalSeconds
                
                Write-Verbose "Successfully connected to vCenter using VCF PowerCLI: $($this.VCenterAddress)"
                Write-Verbose "Connection established in $($this.ConnectionStatistics.LastConnectionDuration) seconds"
            }
            else {
                throw "Connection established but verification failed"
            }
        }
        catch {
            $this.ConnectionStatistics.FailedConnections++
            $this.HandleConnectionFailure($_)
            throw "Failed to connect to vCenter server '$($this.VCenterAddress)' using VCF PowerCLI: $($_.Exception.Message)"
        }
    }
    
    # Ensure connection is active
    [void] EnsureConnection() {
        if (-not $this.TestConnection()) {
            Write-Verbose "Connection lost, attempting to reconnect..."
            $this.ConnectionStatistics.ReconnectionAttempts++
            $this.RetryConnection($this.RetryAttempts)
        }
    }
    
    # Test connection status
    [bool] TestConnection() {
        try {
            if (-not $this.IsConnected -or -not $this.VIServerConnection) {
                return $false
            }
            
            # Test connection by attempting a simple operation
            $null = Get-VIServer -Server $this.VCenterAddress -ErrorAction Stop
            return $true
        }
        catch {
            Write-Verbose "Connection test failed: $($_.Exception.Message)"
            $this.IsConnected = $false
            return $false
        }
    }
    
    # Disconnect from vCenter
    [void] Disconnect() {
        try {
            if ($this.IsConnected -and $this.VIServerConnection) {
                Disconnect-VIServer -Server $this.VIServerConnection -Confirm:$false -ErrorAction Stop
                Write-Verbose "Disconnected from vCenter: $($this.VCenterAddress)"
            }
        }
        catch {
            Write-Warning "Error during disconnect: $($_.Exception.Message)"
        }
        finally {
            $this.IsConnected = $false
            $this.VIServerConnection = $null
        }
    }
    
    # Configure SSL settings
    [void] ConfigureSSL([bool] $DisableSSL) {
        $this.DisableSSL = $DisableSSL
        
        if ($DisableSSL) {
            $this.PowerCLIConfiguration.InvalidCertificateAction = 'Ignore'
            Write-Verbose "SSL certificate validation disabled"
        }
        else {
            $this.PowerCLIConfiguration.InvalidCertificateAction = 'Prompt'
            Write-Verbose "SSL certificate validation enabled"
        }
        
        # Apply configuration if already connected
        if ($this.VCFPowerCLILoaded) {
            $this.ConfigurePowerCLI()
        }
    }
    
    # Retry connection with exponential backoff
    [void] RetryConnection([int] $MaxAttempts) {
        $attempt = 1
        $delay = $this.RetryDelaySeconds
        
        while ($attempt -le $MaxAttempts) {
            try {
                Write-Verbose "Connection retry attempt $attempt of $MaxAttempts"
                $this.Connect()
                return  # Success, exit retry loop
            }
            catch {
                Write-Warning "Connection attempt $attempt failed: $($_.Exception.Message)"
                
                if ($attempt -eq $MaxAttempts) {
                    throw "Failed to establish connection after $MaxAttempts attempts"
                }
                
                Write-Verbose "Waiting $delay seconds before retry..."
                Start-Sleep -Seconds $delay
                
                # Exponential backoff
                $delay = $delay * 2
                $attempt++
            }
        }
    }
    
    # Handle connection failures
    [void] HandleConnectionFailure([object] $Exception) {
        $errorMessage = if ($Exception -is [System.Management.Automation.ErrorRecord]) {
            $Exception.Exception.Message
        } elseif ($Exception -is [System.Exception]) {
            $Exception.Message
        } else {
            $Exception.ToString()
        }
        
        # Provide specific guidance based on error type
        if ($errorMessage -match "certificate") {
            Write-Warning "SSL Certificate issue detected. Consider using -DisableSSL parameter for lab environments."
        }
        elseif ($errorMessage -match "authentication|credential") {
            Write-Warning "Authentication failed. Please verify credentials and permissions."
        }
        elseif ($errorMessage -match "network|timeout|connection") {
            Write-Warning "Network connectivity issue. Please verify vCenter address and network connectivity."
        }
        
        $this.LogConnectionEvent("Connection failed: $errorMessage", "Error")
    }
    
    # Log connection events
    [void] LogConnectionEvent([string] $Event, [string] $Level) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] ConnectionManager: $Event"
        
        switch ($Level.ToLower()) {
            "error" { Write-Error $logMessage }
            "warning" { Write-Warning $logMessage }
            "verbose" { Write-Verbose $logMessage }
            default { Write-Information $logMessage }
        }
    }
    
    # Get connection statistics
    [hashtable] GetConnectionStatistics() {
        return @{
            VCenterAddress = $this.VCenterAddress
            IsConnected = $this.IsConnected
            PowerCLIVersion = $this.PowerCLIVersion
            VCFPowerCLILoaded = $this.VCFPowerCLILoaded
            LastConnectionTime = $this.LastConnectionTime
            ConnectionAttempts = $this.ConnectionStatistics.ConnectionAttempts
            SuccessfulConnections = $this.ConnectionStatistics.SuccessfulConnections
            FailedConnections = $this.ConnectionStatistics.FailedConnections
            ReconnectionAttempts = $this.ConnectionStatistics.ReconnectionAttempts
            LastConnectionDuration = $this.ConnectionStatistics.LastConnectionDuration
            RetryAttempts = $this.RetryAttempts
            RetryDelaySeconds = $this.RetryDelaySeconds
        }
    }
    
    # Get VCF PowerCLI information
    [hashtable] GetPowerCLIInfo() {
        try {
            # Try to get VCF modules first, fall back to core PowerCLI
            $module = Get-Module -Name VMware.Vcf.SddcManager -ErrorAction SilentlyContinue
            if (-not $module) {
                $module = Get-Module -Name VMware.Sdk.Vcf.SddcManager -ErrorAction SilentlyContinue
            }
            if (-not $module) {
                $module = Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue
            }
            
            if ($module) {
                return @{
                    Name = $module.Name
                    Version = $module.Version.ToString()
                    Path = $module.Path
                    Author = $module.Author
                    Description = $module.Description
                    LoadedCommands = if ($module.ExportedCommands) { ($module.ExportedCommands.Keys | Measure-Object).Count } else { 0 }
                    IsLoaded = $this.VCFPowerCLILoaded
                }
            }
            else {
                throw "No VCF PowerCLI modules found"
            }
        }
        catch {
            return @{
                Name = "VCF PowerCLI"
                Version = "Unknown"
                IsLoaded = $false
                Error = $_.Exception.Message
            }
        }
    }
    
    # ConnectVMwareEnvironment function - Main entry point for connection
    [void] ConnectVMwareEnvironment([string] $VCenterAddress, [PSCredential] $Credentials, [bool] $DisableSSL = $false) {
        $this.VCenterAddress = $VCenterAddress
        $this.Credentials = $Credentials
        $this.ConfigureSSL($DisableSSL)
        $this.Connect()
    }
    
    # Connection health monitoring
    [hashtable] GetConnectionHealth() {
        $health = @{
            IsConnected = $this.IsConnected
            LastConnectionTime = $this.LastConnectionTime
            ConnectionAge = if ($this.LastConnectionTime) { (Get-Date) - $this.LastConnectionTime } else { $null }
            VCenterAddress = $this.VCenterAddress
            PowerCLIVersion = $this.PowerCLIVersion
            VCFPowerCLILoaded = $this.VCFPowerCLILoaded
            ConnectionStatistics = $this.ConnectionStatistics
            HealthStatus = "Unknown"
        }
        
        try {
            if ($this.TestConnection()) {
                $health.HealthStatus = "Healthy"
                
                # Check connection age
                if ($health.ConnectionAge -and $health.ConnectionAge.TotalHours -gt 8) {
                    $health.HealthStatus = "Aging"
                }
            }
            else {
                $health.HealthStatus = "Unhealthy"
            }
        }
        catch {
            $health.HealthStatus = "Error"
            $health.LastError = $_.Exception.Message
        }
        
        return $health
    }
    
    # Session management and monitoring
    [void] MonitorConnectionState() {
        $health = $this.GetConnectionHealth()
        
        switch ($health.HealthStatus) {
            "Unhealthy" {
                Write-Warning "Connection health check failed. Attempting reconnection..."
                $this.EnsureConnection()
            }
            "Aging" {
                Write-Verbose "Connection is aging (>8 hours). Consider reconnecting for optimal performance."
            }
            "Error" {
                Write-Error "Connection monitoring detected error: $($health.LastError)"
            }
            "Healthy" {
                Write-Verbose "Connection health check passed."
            }
        }
    }
    
    # Connection timeout handling
    [void] SetConnectionTimeout([int] $TimeoutSeconds) {
        try {
            # Set VCF PowerCLI timeout configuration
            Set-PowerCLIConfiguration -WebOperationTimeoutSeconds $TimeoutSeconds -Confirm:$false -Scope Session -ErrorAction Stop
            Write-Verbose "Connection timeout set to $TimeoutSeconds seconds"
        }
        catch {
            Write-Warning "Failed to set connection timeout: $($_.Exception.Message)"
        }
    }
    
    # Advanced connection validation with detailed checks
    [hashtable] ValidateConnection() {
        $validation = @{
            IsValid = $false
            Checks = @{}
            Errors = @()
            Warnings = @()
        }
        
        try {
            # Check 1: Basic connection test
            $validation.Checks.BasicConnection = $this.TestConnection()
            if (-not $validation.Checks.BasicConnection) {
                $validation.Errors += "Basic connection test failed"
            }
            
            # Check 2: API responsiveness test
            try {
                $startTime = Get-Date
                $null = Get-VIServer -Server $this.VCenterAddress -ErrorAction Stop
                $responseTime = ((Get-Date) - $startTime).TotalMilliseconds
                $validation.Checks.APIResponsiveness = $responseTime -lt 5000  # 5 second threshold
                $validation.Checks.ResponseTimeMs = $responseTime
                
                if ($responseTime -gt 5000) {
                    $validation.Warnings += "API response time is slow: $([math]::Round($responseTime, 2))ms"
                }
            }
            catch {
                $validation.Checks.APIResponsiveness = $false
                $validation.Errors += "API responsiveness test failed: $($_.Exception.Message)"
            }
            
            # Check 3: Permission validation
            try {
                $null = Get-VM -ErrorAction Stop | Select-Object -First 1
                $validation.Checks.Permissions = $true
            }
            catch {
                $validation.Checks.Permissions = $false
                $validation.Errors += "Permission validation failed: $($_.Exception.Message)"
            }
            
            # Check 4: VCF PowerCLI module status
            $validation.Checks.VCFPowerCLILoaded = $this.VCFPowerCLILoaded
            if (-not $this.VCFPowerCLILoaded) {
                $validation.Errors += "VCF PowerCLI module is not properly loaded"
            }
            
            # Overall validation
            $validation.IsValid = $validation.Checks.BasicConnection -and 
                                 $validation.Checks.APIResponsiveness -and 
                                 $validation.Checks.Permissions -and 
                                 $validation.Checks.VCFPowerCLILoaded
        }
        catch {
            $validation.Errors += "Connection validation failed: $($_.Exception.Message)"
        }
        
        return $validation
    }
    
    # Connection pooling methods
    [object] GetPooledConnection([string] $ServerAddress) {
        $poolKey = $ServerAddress.ToLower()
        
        if ($this.ConnectionPool.ContainsKey($poolKey)) {
            $pooledConnection = $this.ConnectionPool[$poolKey]
            
            # Check if pooled connection is still valid
            if ($this.IsConnectionValid($pooledConnection)) {
                $this.ConnectionStatistics.PoolHits++
                $this.UpdateSessionActivity()
                Write-Verbose "Using pooled connection for $ServerAddress"
                return $pooledConnection
            }
            else {
                # Remove invalid connection from pool
                $this.ConnectionPool.Remove($poolKey)
                Write-Verbose "Removed invalid pooled connection for $ServerAddress"
            }
        }
        
        $this.ConnectionStatistics.PoolMisses++
        return $null
    }
    
    [void] AddToConnectionPool([string] $ServerAddress, [object] $Connection) {
        $poolKey = $ServerAddress.ToLower()
        
        # Check pool size limit
        if ($this.ConnectionPool.Count -ge $this.MaxPoolSize) {
            $this.CleanupOldestPooledConnection()
        }
        
        $pooledConnection = @{
            Connection = $Connection
            ServerAddress = $ServerAddress
            CreatedTime = Get-Date
            LastUsedTime = Get-Date
            UseCount = 1
        }
        
        $this.ConnectionPool[$poolKey] = $pooledConnection
        Write-Verbose "Added connection to pool for $ServerAddress. Pool size: $($this.ConnectionPool.Count)"
    }
    
    [bool] IsConnectionValid([hashtable] $PooledConnection) {
        try {
            if (-not $PooledConnection -or -not $PooledConnection.Connection) {
                return $false
            }
            
            # Check connection age
            $connectionAge = (Get-Date) - $PooledConnection.CreatedTime
            if ($connectionAge.TotalSeconds -gt $this.ConnectionTimeoutSeconds) {
                Write-Verbose "Pooled connection expired (age: $($connectionAge.TotalMinutes) minutes)"
                return $false
            }
            
            # Test connection
            $connection = $PooledConnection.Connection
            if ($connection.IsConnected) {
                return $true
            }
            
            return $false
        }
        catch {
            Write-Verbose "Connection validation failed: $($_.Exception.Message)"
            return $false
        }
    }
    
    [void] CleanupOldestPooledConnection() {
        if ($this.ConnectionPool.Count -eq 0) {
            return
        }
        
        $oldestKey = $null
        $oldestTime = Get-Date
        
        foreach ($key in $this.ConnectionPool.Keys) {
            $connection = $this.ConnectionPool[$key]
            if ($connection.CreatedTime -lt $oldestTime) {
                $oldestTime = $connection.CreatedTime
                $oldestKey = $key
            }
        }
        
        if ($oldestKey) {
            try {
                $connection = $this.ConnectionPool[$oldestKey]
                if ($connection.Connection) {
                    Disconnect-VIServer -Server $connection.Connection -Confirm:$false -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-Verbose "Error disconnecting oldest pooled connection: $($_.Exception.Message)"
            }
            
            $this.ConnectionPool.Remove($oldestKey)
            Write-Verbose "Removed oldest pooled connection for cleanup"
        }
    }
    
    [void] CleanupConnectionPool() {
        $keysToRemove = @()
        
        foreach ($key in $this.ConnectionPool.Keys) {
            $connection = $this.ConnectionPool[$key]
            if (-not $this.IsConnectionValid($connection)) {
                $keysToRemove += $key
            }
        }
        
        foreach ($key in $keysToRemove) {
            try {
                $connection = $this.ConnectionPool[$key]
                if ($connection.Connection) {
                    Disconnect-VIServer -Server $connection.Connection -Confirm:$false -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-Verbose "Error disconnecting invalid pooled connection: $($_.Exception.Message)"
            }
            
            $this.ConnectionPool.Remove($key)
        }
        
        if ($keysToRemove.Count -gt 0) {
            Write-Verbose "Cleaned up $($keysToRemove.Count) invalid pooled connections"
        }
    }
    
    # Session management methods
    [void] UpdateSessionActivity() {
        $this.LastActivityTime = Get-Date
        $this.SessionState.LastAccessTime = Get-Date
        $this.SessionState.IsActive = $true
    }
    
    [bool] IsSessionExpired() {
        $sessionAge = (Get-Date) - $this.SessionState.LastAccessTime
        return $sessionAge.TotalMinutes -gt $this.SessionTimeoutMinutes
    }
    
    [void] RefreshSession() {
        if ($this.IsSessionExpired()) {
            Write-Verbose "Session expired, creating new session"
            $this.SessionState = @{
                SessionId = [System.Guid]::NewGuid().ToString()
                CreatedTime = Get-Date
                LastAccessTime = Get-Date
                IsActive = $true
                ConnectionCount = $this.SessionState.ConnectionCount + 1
            }
        }
        else {
            $this.UpdateSessionActivity()
        }
    }
    
    [hashtable] GetSessionInfo() {
        return @{
            SessionId = $this.SessionState.SessionId
            CreatedTime = $this.SessionState.CreatedTime
            LastAccessTime = $this.SessionState.LastAccessTime
            IsActive = $this.SessionState.IsActive
            ConnectionCount = $this.SessionState.ConnectionCount
            SessionAge = (Get-Date) - $this.SessionState.CreatedTime
            TimeSinceLastActivity = (Get-Date) - $this.SessionState.LastAccessTime
            IsExpired = $this.IsSessionExpired()
            PoolSize = $this.ConnectionPool.Count
            MaxPoolSize = $this.MaxPoolSize
        }
    }
    
    # Automatic reconnection with session management
    [void] EnsureConnectionWithSessionManagement() {
        # Check session expiration
        if ($this.IsSessionExpired()) {
            Write-Verbose "Session expired, refreshing session and reconnecting"
            $this.RefreshSession()
            $this.Disconnect()
        }
        
        # Check connection status
        if (-not $this.TestConnection()) {
            if ($this.AutoReconnectEnabled) {
                Write-Verbose "Connection lost, attempting automatic reconnection..."
                $this.ConnectionStatistics.ReconnectionAttempts++
                $this.RetryConnection($this.RetryAttempts)
            }
            else {
                throw "Connection lost and automatic reconnection is disabled"
            }
        }
        
        $this.UpdateSessionActivity()
    }
    
    # Enhanced connection reuse
    [void] ConnectWithReuse() {
        # Try to get pooled connection first
        $pooledConnection = $this.GetPooledConnection($this.VCenterAddress)
        
        if ($pooledConnection) {
            $this.VIServerConnection = $pooledConnection.Connection
            $this.IsConnected = $true
            $this.LastConnectionTime = Get-Date
            $pooledConnection.LastUsedTime = Get-Date
            $pooledConnection.UseCount++
            Write-Verbose "Reused pooled connection to $($this.VCenterAddress)"
        }
        else {
            # Create new connection
            $this.Connect()
            
            # Add to pool if connection successful
            if ($this.IsConnected -and $this.VIServerConnection) {
                $this.AddToConnectionPool($this.VCenterAddress, $this.VIServerConnection)
            }
        }
        
        $this.UpdateSessionActivity()
    }
    
    # Connection timeout handling with automatic reconnection
    [void] HandleConnectionTimeout() {
        Write-Warning "Connection timeout detected"
        
        if ($this.AutoReconnectEnabled) {
            try {
                Write-Verbose "Attempting automatic reconnection due to timeout"
                $this.Disconnect()
                $this.ConnectWithReuse()
                Write-Verbose "Automatic reconnection successful"
            }
            catch {
                Write-Error "Automatic reconnection failed: $($_.Exception.Message)"
                throw
            }
        }
        else {
            throw "Connection timeout occurred and automatic reconnection is disabled"
        }
    }
    
    # Enhanced connection monitoring with session state
    [hashtable] GetConnectionState() {
        $sessionInfo = $this.GetSessionInfo()
        $connectionHealth = $this.GetConnectionHealth()
        
        return @{
            Connection = $connectionHealth
            Session = $sessionInfo
            Pool = @{
                Size = $this.ConnectionPool.Count
                MaxSize = $this.MaxPoolSize
                Connections = $this.ConnectionPool.Keys
            }
            Configuration = @{
                AutoReconnectEnabled = $this.AutoReconnectEnabled
                ConnectionTimeoutSeconds = $this.ConnectionTimeoutSeconds
                SessionTimeoutMinutes = $this.SessionTimeoutMinutes
                RetryAttempts = $this.RetryAttempts
                RetryDelaySeconds = $this.RetryDelaySeconds
            }
        }
    }
    
    # Cleanup resources with pool cleanup
    [void] Cleanup() {
        try {
            # Cleanup connection pool
            $this.CleanupConnectionPool()
            
            # Disconnect main connection
            $this.Disconnect()
            
            # Clear session state
            $this.SessionState.IsActive = $false
            
            Write-Verbose "ConnectionManager cleanup completed (pool size: $($this.ConnectionPool.Count))"
        }
        catch {
            Write-Warning "Error during ConnectionManager cleanup: $($_.Exception.Message)"
        }
    }
}