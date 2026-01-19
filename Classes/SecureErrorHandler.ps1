#
# SecureErrorHandler.ps1 - Secure error handling and logging
#

class SecureErrorHandler {
    [ILogger] $Logger
    [bool] $DebugMode
    [hashtable] $SensitivePatterns
    
    SecureErrorHandler([ILogger] $Logger, [bool] $DebugMode = $false) {
        $this.Logger = $Logger
        $this.DebugMode = $DebugMode
        
        # Patterns that should be sanitized from error messages
        $this.SensitivePatterns = @{
            'Password' = '(?i)(password|pwd|pass)\s*[=:]\s*[^\s;,]+'
            'ConnectionString' = '(?i)(server|host|database|uid|pwd)\s*=\s*[^;,]+'
            'IPAddress' = '\b(?:\d{1,3}\.){3}\d{1,3}\b'
            'Path' = '[a-zA-Z]:\\(?:[^<>:"|?*\r\n]+\\)*[^<>:"|?*\r\n]*'
            'Username' = '(?i)(user|username|uid)\s*[=:]\s*[^\s;,]+'
        }
    }
    
    # Handle exceptions securely
    [void] HandleException([System.Exception] $Exception, [string] $Context, [bool] $ShowToUser = $true) {
        $sanitizedMessage = $this.SanitizeErrorMessage($Exception.Message)
        $userMessage = "Operation failed in $Context. Check logs for details."
        
        if ($ShowToUser) {
            Write-Host $userMessage -ForegroundColor Red
        }
        
        # Log detailed error securely
        $this.Logger.WriteError("$Context failed: $sanitizedMessage", $Exception)
        
        # Log full details only in debug mode
        if ($this.DebugMode) {
            $this.Logger.WriteDebug("Full exception details: $($Exception.ToString())")
        }
    }
    
    # Handle connection errors specifically
    [void] HandleConnectionError([System.Exception] $Exception, [string] $ServerType, [string] $ServerAddress) {
        $userMessage = "Failed to connect to $ServerType server. Please check connectivity and credentials."
        Write-Host $userMessage -ForegroundColor Red
        
        # Log sanitized details
        $sanitizedAddress = $this.SanitizeServerAddress($ServerAddress)
        $sanitizedError = $this.SanitizeErrorMessage($Exception.Message)
        
        $this.Logger.WriteError("$ServerType connection failed to $sanitizedAddress`: $sanitizedError", $Exception)
    }
    
    # Handle file operation errors
    [void] HandleFileError([System.Exception] $Exception, [string] $Operation, [string] $FilePath) {
        $userMessage = "File operation '$Operation' failed. Check permissions and path."
        Write-Host $userMessage -ForegroundColor Red
        
        # Log with sanitized path
        $sanitizedPath = $this.SanitizeFilePath($FilePath)
        $sanitizedError = $this.SanitizeErrorMessage($Exception.Message)
        
        $this.Logger.WriteError("File $Operation failed for $sanitizedPath`: $sanitizedError", $Exception)
    }    
 
   # Sanitize error messages
    [string] SanitizeErrorMessage([string] $ErrorMessage) {
        if ([string]::IsNullOrEmpty($ErrorMessage)) {
            return ""
        }
        
        $sanitized = $ErrorMessage
        
        # Remove sensitive patterns
        foreach ($patternName in $this.SensitivePatterns.Keys) {
            $pattern = $this.SensitivePatterns[$patternName]
            $sanitized = $sanitized -replace $pattern, "[$patternName Hidden]"
        }
        
        return $sanitized
    }
    
    # Sanitize server addresses for logging
    [string] SanitizeServerAddress([string] $ServerAddress) {
        if ([string]::IsNullOrEmpty($ServerAddress)) {
            return ""
        }
        
        # Keep domain but hide specific server names
        if ($ServerAddress -match '\.') {
            $parts = $ServerAddress.Split('.')
            if ($parts.Length -gt 1) {
                return "***.$($parts[-1])"  # Show only TLD
            }
        }
        
        return "***"
    }
    
    # Sanitize file paths for logging
    [string] SanitizeFilePath([string] $FilePath) {
        if ([string]::IsNullOrEmpty($FilePath)) {
            return ""
        }
        
        # Show only filename and extension
        $fileName = Split-Path $FilePath -Leaf
        return "***\$fileName"
    }
    
    # Create user-friendly error message
    [string] CreateUserFriendlyMessage([string] $Operation, [string] $ErrorType) {
        switch ($ErrorType.ToLower()) {
            'connection' { return "Connection failed for $Operation. Please check network connectivity and credentials." }
            'authentication' { return "Authentication failed for $Operation. Please verify your credentials." }
            'permission' { return "Permission denied for $Operation. Please check file/folder permissions." }
            'notfound' { return "Resource not found for $Operation. Please verify the path or name." }
            'timeout' { return "Operation timed out for $Operation. Please try again or increase timeout values." }
            'validation' { return "Input validation failed for $Operation. Please check your parameters." }
            default { return "An error occurred during $Operation. Please check the logs for more information." }
        }
        # Explicit return for PowerShell strict mode
        return "An error occurred during $Operation. Please check the logs for more information."
    }
}