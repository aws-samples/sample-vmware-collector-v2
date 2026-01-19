#
# SimpleLogger.ps1 - Simple logging implementation
#
# Implements ILogger interface for basic logging functionality
#

# Dependencies: Interfaces.ps1 (loaded by module)

class SimpleLogger : ILogger {
    [bool] $LoggingEnabled
    [string] $LogFilePath
    
    SimpleLogger([bool] $EnableLogging) {
        $this.LoggingEnabled = $EnableLogging
        if ($EnableLogging) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $this.LogFilePath = "VMware_Collection_$timestamp.log"
        }
    }
    
    SimpleLogger([bool] $EnableLogging, [string] $LogFilePath) {
        $this.LoggingEnabled = $EnableLogging
        $this.LogFilePath = $LogFilePath
    }
    
    # Write log message
    [void] WriteLog([string] $Message, [string] $Level) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "$timestamp [$Level] $Message"
        
        # Always write to console for important messages
        switch ($Level.ToUpper()) {
            "ERROR" { 
                Write-Host $logMessage -ForegroundColor Red 
            }
            "WARNING" { 
                Write-Host $logMessage -ForegroundColor Yellow 
            }
            "INFORMATION" { 
                Write-Host $logMessage -ForegroundColor Green 
            }
            "DEBUG" { 
                if ($this.LoggingEnabled) {
                    Write-Host $logMessage -ForegroundColor Gray 
                }
            }
            default { 
                Write-Host $logMessage -ForegroundColor White 
            }
        }
        
        # Write to log file if logging is enabled
        if ($this.LoggingEnabled -and $this.LogFilePath) {
            try {
                Add-Content -Path $this.LogFilePath -Value $logMessage -ErrorAction SilentlyContinue
            } catch {
                # Ignore file logging errors
            }
        }
    }
    
    # Convenience methods
    [void] WriteError([string] $Message, [System.Exception] $Exception) {
        $fullMessage = if ($Exception) { "$Message - Exception: $($Exception.Message)" } else { $Message }
        $this.WriteLog($fullMessage, "ERROR")
    }
    
    [void] WriteWarning([string] $Message) {
        $this.WriteLog($Message, "WARNING")
    }
    
    [void] WriteInformation([string] $Message) {
        $this.WriteLog($Message, "INFORMATION")
    }
    
    [void] WriteDebug([string] $Message) {
        $this.WriteLog($Message, "DEBUG")
    }
}