#
# InputValidator.ps1 - Comprehensive input validation
#

class InputValidator {
    [hashtable] $ValidationRules
    
    InputValidator() {
        $this.ValidationRules = @{
            IPAddress = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
            Hostname = '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'
            VMName = '^[a-zA-Z0-9][a-zA-Z0-9\-_\.]{0,62}[a-zA-Z0-9]$'
            Username = '^[a-zA-Z0-9][a-zA-Z0-9\-_\.\\@]{0,127}$'
            # Support Windows (C:\path), Unix (/path), and relative (path/file) paths
            FilePath = '^([a-zA-Z]:\\(?:[^<>:"|?*\r\n]+\\)*[^<>:"|?*\r\n]*|/?[^<>"|?*\r\n]+(/[^<>"|?*\r\n]+)*|[^<>:"|?*\r\n/\\]+)$'
        }
    }
    
    # Validate and sanitize file path
    [string] ValidateFilePath([string] $FilePath, [bool] $MustExist = $true) {
        if ([string]::IsNullOrEmpty($FilePath)) {
            throw "File path cannot be empty"
        }
        
        # Check for path traversal
        if ($FilePath.Contains('..') -or $FilePath.Contains('~') -or $FilePath.StartsWith('\\')) {
            throw "Invalid file path: potential path traversal detected"
        }
        
        # Validate path format
        if (-not ($FilePath -match $this.ValidationRules.FilePath)) {
            throw "Invalid file path format"
        }
        
        # Check path length
        if ($FilePath.Length -gt 260) {
            throw "File path too long (max 260 characters)"
        }
        
        # Resolve to absolute path if it exists
        if ($MustExist) {
            try {
                $resolvedPath = Resolve-Path $FilePath -ErrorAction Stop
                return $resolvedPath.Path
            } catch {
                throw "File not found: $FilePath"
            }
        } else {
            # For output paths, validate parent directory exists
            $parentDir = Split-Path $FilePath -Parent
            if ($parentDir -and -not (Test-Path $parentDir)) {
                throw "Parent directory does not exist: $parentDir"
            }
            return $FilePath
        }
    }
    
    # Validate IP address
    [string] ValidateIPAddress([string] $IPAddress) {
        if ([string]::IsNullOrEmpty($IPAddress)) {
            return ""
        }
        
        # Check format
        if (-not ($IPAddress -match $this.ValidationRules.IPAddress)) {
            throw "Invalid IP address format: $IPAddress"
        }
        
        # Additional validation for private/public ranges if needed
        return $IPAddress.Trim()
    }
    
    # Validate hostname/FQDN
    [string] ValidateHostname([string] $Hostname) {
        if ([string]::IsNullOrEmpty($Hostname)) {
            throw "Hostname cannot be empty"
        }
        
        # Check format
        if (-not ($Hostname -match $this.ValidationRules.Hostname)) {
            throw "Invalid hostname format: $Hostname"
        }
        
        # Check length
        if ($Hostname.Length -gt 253) {
            throw "Hostname too long (max 253 characters)"
        }
        
        return $Hostname.Trim().ToLower()
    }    
  
  # Validate VM name for file operations
    [string] ValidateVMName([string] $VMName) {
        if ([string]::IsNullOrEmpty($VMName)) {
            throw "VM name cannot be empty"
        }
        
        # Check for dangerous characters
        $dangerousChars = @('<', '>', ':', '"', '|', '?', '*', '/', '\', "`0")
        foreach ($char in $dangerousChars) {
            if ($VMName.Contains($char)) {
                throw "VM name contains invalid character: $char"
            }
        }
        
        # Check length
        if ($VMName.Length -gt 64) {
            throw "VM name too long (max 64 characters)"
        }
        
        # Sanitize for file operations
        $sanitized = $VMName -replace '[^\w\-\.]', '_'
        return $sanitized
    }
    
    # Validate username
    [string] ValidateUsername([string] $Username) {
        if ([string]::IsNullOrEmpty($Username)) {
            throw "Username cannot be empty"
        }
        
        # Check format
        if (-not ($Username -match $this.ValidationRules.Username)) {
            throw "Invalid username format: $Username"
        }
        
        # Check length
        if ($Username.Length -gt 128) {
            throw "Username too long (max 128 characters)"
        }
        
        return $Username.Trim()
    }
    
    # Validate port number
    [int] ValidatePort([int] $Port, [bool] $AllowZero = $true) {
        if ($AllowZero -and $Port -eq 0) {
            return $Port
        }
        
        if ($Port -lt 1 -or $Port -gt 65535) {
            throw "Port number must be between 1 and 65535"
        }
        
        return $Port
    }
    
    # Validate numeric range
    [int] ValidateNumericRange([int] $Value, [int] $Min, [int] $Max, [string] $ParameterName) {
        if ($Value -lt $Min -or $Value -gt $Max) {
            throw "$ParameterName must be between $Min and $Max"
        }
        return $Value
    }
    
    # Sanitize string for logging (remove sensitive patterns)
    [string] SanitizeForLogging([string] $Input) {
        if ([string]::IsNullOrEmpty($Input)) {
            return ""
        }
        
        # Remove potential passwords, tokens, keys
        $sanitized = $Input -replace '(?i)(password|pwd|pass|token|key|secret)\s*[=:]\s*[^\s;,]+', '$1=***'
        
        # Remove potential connection strings
        $sanitized = $sanitized -replace '(?i)(server|host|database)\s*=\s*[^;,]+', '$1=***'
        
        return $sanitized
    }
}