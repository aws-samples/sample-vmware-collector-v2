#
# ConfigurationValidator.ps1 - Secure configuration validation
#

class ConfigurationValidator {
    [hashtable] $AllowedDatabaseTypes
    [hashtable] $RequiredFields
    [int] $MaxCredentialSets
    
    ConfigurationValidator() {
        $this.AllowedDatabaseTypes = @{
            'SQLServer' = $true
            'PostgreSQL' = $true
            'Oracle' = $true
            'MySQL' = $true
            'MariaDB' = $true
        }
        
        $this.RequiredFields = @{
            'SQLServer' = @('Username', 'Password', 'AuthMode', 'Description', 'Priority')
            'PostgreSQL' = @('Username', 'Password', 'Description', 'Priority')
            'Oracle' = @('Username', 'Password', 'Description', 'Priority')
            'MySQL' = @('Username', 'Password', 'Description', 'Priority')
            'MariaDB' = @('Username', 'Password', 'Description', 'Priority')
        }
        
        $this.MaxCredentialSets = 10  # Prevent DoS through large configs
    }
    
    # Validate JSON configuration file securely
    [hashtable] ValidateConfigurationFile([string] $FilePath) {
        # Validate file path first
        $validatedPath = $this.ValidateFilePath($FilePath)
        
        # Check file permissions
        $this.ValidateFilePermissions($validatedPath)
        
        # Read and validate file size
        $fileInfo = Get-Item $validatedPath
        if ($fileInfo.Length -gt 1MB) {
            throw "Configuration file too large (max 1MB allowed)"
        }
        
        # Read file content safely
        try {
            $jsonContent = Get-Content $validatedPath -Raw -ErrorAction Stop
        } catch {
            throw "Failed to read configuration file: $($_.Exception.Message)"
        }
        
        # Validate JSON structure
        $configObject = $this.ValidateJSONStructure($jsonContent)
        
        # Validate configuration content
        $validatedConfig = $this.ValidateConfigurationContent($configObject)
        
        return $validatedConfig
    }
    
    # Validate file path for security
    [string] ValidateFilePath([string] $FilePath) {
        if ([string]::IsNullOrEmpty($FilePath)) {
            throw "File path cannot be empty"
        }
        
        # Check for path traversal attempts
        if ($FilePath.Contains('..') -or $FilePath.Contains('~')) {
            throw "Invalid file path: path traversal detected"
        }
        
        # Resolve to absolute path
        try {
            $resolvedPath = Resolve-Path $FilePath -ErrorAction Stop
            return $resolvedPath.Path
        } catch {
            throw "File not found or inaccessible: $FilePath"
        }
    }    

    # Validate file permissions
    [void] ValidateFilePermissions([string] $FilePath) {
        # Check if Get-Acl is available (Windows PowerShell 5.1 or PowerShell Core on Windows)
        if (-not (Get-Command Get-Acl -ErrorAction SilentlyContinue)) {
            # Fallback: just check if file exists and is readable
            if (-not (Test-Path $FilePath -PathType Leaf)) {
                throw "Configuration file not found or not accessible"
            }
            return
        }
        
        try {
            $acl = Get-Acl $FilePath -ErrorAction Stop
            
            # Check if file is readable by current user
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $hasReadAccess = $false
            
            foreach ($access in $acl.Access) {
                if ($access.IdentityReference.Value -eq $currentUser.Name -and 
                    $access.FileSystemRights -match "Read") {
                    $hasReadAccess = $true
                    break
                }
            }
            
            if (-not $hasReadAccess) {
                throw "Insufficient permissions to read configuration file"
            }
            
            # Warn about overly permissive permissions
            foreach ($access in $acl.Access) {
                if ($access.IdentityReference.Value -eq "Everyone" -or 
                    $access.IdentityReference.Value -eq "Users") {
                    Write-Warning "Configuration file has overly permissive permissions"
                    break
                }
            }
            
        } catch {
            throw "Failed to validate file permissions: $($_.Exception.Message)"
        }
    }
    
    # Validate JSON structure safely
    [PSObject] ValidateJSONStructure([string] $JsonContent) {
        if ([string]::IsNullOrEmpty($JsonContent)) {
            throw "Configuration file is empty"
        }
        
        # Check for suspicious content patterns
        $suspiciousPatterns = @(
            '\$\(',           # PowerShell command substitution
            'Invoke-',        # PowerShell Invoke commands
            'iex\s*\(',      # Invoke-Expression
            'cmd\s*/c',      # Command execution
            '&\s*\(',        # PowerShell call operator
            'Start-Process', # Process execution
            'New-Object.*ComObject' # COM object creation
        )
        
        foreach ($pattern in $suspiciousPatterns) {
            if ($JsonContent -match $pattern) {
                throw "Configuration file contains suspicious content: $pattern"
            }
        }
        
        # Parse JSON safely
        try {
            $configObject = $JsonContent | ConvertFrom-Json -ErrorAction Stop
            return $configObject
        } catch {
            throw "Invalid JSON format: $($_.Exception.Message)"
        }
    }
    
    # Validate configuration content
    [hashtable] ValidateConfigurationContent([PSObject] $ConfigObject) {
        $validatedConfig = @{}
        
        # Validate each database type
        foreach ($dbType in $ConfigObject.PSObject.Properties.Name) {
            if (-not $this.AllowedDatabaseTypes.ContainsKey($dbType)) {
                Write-Warning "Unknown database type '$dbType' ignored"
                continue
            }
            
            $dbConfig = $ConfigObject.$dbType
            if (-not $dbConfig) {
                continue
            }
            
            # Validate credential sets
            if ($dbConfig -is [array]) {
                if ($dbConfig.Count -gt $this.MaxCredentialSets) {
                    throw "Too many credential sets for $dbType (max $($this.MaxCredentialSets) allowed)"
                }
                
                $validatedCredentials = @()
                foreach ($credential in $dbConfig) {
                    $validatedCredential = $this.ValidateCredentialSet($credential, $dbType)
                    $validatedCredentials += $validatedCredential
                }
                
                $validatedConfig[$dbType] = $validatedCredentials
            } else {
                throw "Invalid configuration format for $dbType"
            }
        }
        
        return $validatedConfig
    }
    
    # Validate individual credential set
    [hashtable] ValidateCredentialSet([PSObject] $Credential, [string] $DatabaseType) {
        $validatedCredential = @{}
        $fieldsTable = $this.RequiredFields
        $fieldsList = $fieldsTable[$DatabaseType]
        
        # Check required fields
        foreach ($field in $fieldsList) {
            if (-not $Credential.PSObject.Properties.Name.Contains($field)) {
                throw "Missing required field '$field' for $DatabaseType credential"
            }
            
            $value = $Credential.$field
            if ([string]::IsNullOrEmpty($value)) {
                throw "Empty value for required field '$field' in $DatabaseType credential"
            }
            
            # Validate field content
            switch ($field) {
                'Username' {
                    if ($value.Length -gt 128) {
                        throw "Username too long (max 128 characters)"
                    }
                    if ($value -match '[<>"|&]') {
                        throw "Username contains invalid characters"
                    }
                }
                'Password' {
                    if ($value.Length -gt 256) {
                        throw "Password too long (max 256 characters)"
                    }
                }
                'Priority' {
                    if (-not ($value -is [int]) -or $value -lt 1 -or $value -gt 100) {
                        throw "Priority must be an integer between 1 and 100"
                    }
                }
                'AuthMode' {
                    if ($DatabaseType -eq 'SQLServer' -and $value -notin @('Windows', 'SQL')) {
                        throw "Invalid AuthMode for SQL Server: must be 'Windows' or 'SQL'"
                    }
                }
                'Description' {
                    if ($value.Length -gt 256) {
                        throw "Description too long (max 256 characters)"
                    }
                }
            }
            
            $validatedCredential[$field] = $value
        }
        
        return $validatedCredential
    }
}