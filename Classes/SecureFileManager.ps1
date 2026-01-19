#
# SecureFileManager.ps1 - Secure file operations
#

class SecureFileManager {
    [ILogger] $Logger
    [InputValidator] $InputValidator
    
    SecureFileManager([ILogger] $Logger) {
        $this.Logger = $Logger
        . "$PSScriptRoot\InputValidator.ps1"
        $this.InputValidator = [InputValidator]::new()
    }
    
    # Create directory securely
    [string] CreateSecureDirectory([string] $DirectoryPath) {
        # Validate path
        $validatedPath = $this.InputValidator.ValidateFilePath($DirectoryPath, $false)
        
        try {
            # Create directory atomically
            $null = New-Item -ItemType Directory -Path $validatedPath -Force -ErrorAction Stop
            
            # Set secure permissions immediately
            $this.SetSecureDirectoryPermissions($validatedPath)
            
            $this.Logger.WriteInformation("Created secure directory: $validatedPath")
            return $validatedPath
            
        } catch {
            throw "Failed to create secure directory '$validatedPath': $($_.Exception.Message)"
        }
    }
    
    # Set secure permissions on directory
    [void] SetSecureDirectoryPermissions([string] $DirectoryPath) {
        # Check if Get-Acl is available (Windows PowerShell 5.1 or PowerShell Core on Windows)
        if (-not (Get-Command Get-Acl -ErrorAction SilentlyContinue)) {
            $this.Logger.WriteDebug("Get-Acl not available on this platform, skipping ACL operations")
            return
        }
        
        try {
            $acl = Get-Acl $DirectoryPath
            
            # Remove inherited permissions
            $acl.SetAccessRuleProtection($true, $false)
            
            # Add current user full control
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $currentUser, 
                "FullControl", 
                "ContainerInherit,ObjectInherit", 
                "None", 
                "Allow"
            )
            $acl.SetAccessRule($accessRule)
            
            # Add SYSTEM full control
            $systemAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "NT AUTHORITY\SYSTEM", 
                "FullControl", 
                "ContainerInherit,ObjectInherit", 
                "None", 
                "Allow"
            )
            $acl.SetAccessRule($systemAccessRule)
            
            # Apply permissions
            Set-Acl $DirectoryPath $acl
            
            $this.Logger.WriteDebug("Set secure permissions on directory: $DirectoryPath")
            
        } catch {
            $this.Logger.WriteWarning("Failed to set secure permissions on '$DirectoryPath': $($_.Exception.Message)")
        }
    }    

    # Write file securely
    [void] WriteFileSecurely([string] $FilePath, [string] $Content) {
        # Validate path
        $validatedPath = $this.InputValidator.ValidateFilePath($FilePath, $false)
        
        # Create parent directory if needed
        $parentDir = Split-Path $validatedPath -Parent
        if ($parentDir -and -not (Test-Path $parentDir)) {
            $this.CreateSecureDirectory($parentDir)
        }
        
        try {
            # Write to temporary file first (atomic operation)
            $tempFile = "$validatedPath.tmp"
            Set-Content -Path $tempFile -Value $Content -Encoding UTF8 -ErrorAction Stop
            
            # Set secure permissions on temp file
            $this.SetSecureFilePermissions($tempFile)
            
            # Move temp file to final location (atomic)
            Move-Item $tempFile $validatedPath -Force -ErrorAction Stop
            
            $this.Logger.WriteDebug("Wrote file securely: $validatedPath")
            
        } catch {
            # Clean up temp file if it exists
            if (Test-Path "$validatedPath.tmp") {
                Remove-Item "$validatedPath.tmp" -Force -ErrorAction SilentlyContinue
            }
            throw "Failed to write file securely '$validatedPath': $($_.Exception.Message)"
        }
    }
    
    # Set secure permissions on file
    [void] SetSecureFilePermissions([string] $FilePath) {
        # Check if Get-Acl is available (Windows PowerShell 5.1 or PowerShell Core on Windows)
        if (-not (Get-Command Get-Acl -ErrorAction SilentlyContinue)) {
            $this.Logger.WriteDebug("Get-Acl not available on this platform, skipping ACL operations")
            return
        }
        
        try {
            $acl = Get-Acl $FilePath
            
            # Remove inherited permissions
            $acl.SetAccessRuleProtection($true, $false)
            
            # Add current user full control
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $currentUser, 
                "FullControl", 
                "Allow"
            )
            $acl.SetAccessRule($accessRule)
            
            # Add SYSTEM full control
            $systemAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "NT AUTHORITY\SYSTEM", 
                "FullControl", 
                "Allow"
            )
            $acl.SetAccessRule($systemAccessRule)
            
            # Apply permissions
            Set-Acl $FilePath $acl
            
        } catch {
            $this.Logger.WriteWarning("Failed to set secure permissions on '$FilePath': $($_.Exception.Message)")
        }
    }
    
    # Read file securely
    [string] ReadFileSecurely([string] $FilePath) {
        # Validate path
        $validatedPath = $this.InputValidator.ValidateFilePath($FilePath, $true)
        
        # Check file size to prevent DoS
        $fileInfo = Get-Item $validatedPath
        if ($fileInfo.Length -gt 100MB) {
            throw "File too large to read securely (max 100MB): $validatedPath"
        }
        
        try {
            $content = Get-Content $validatedPath -Raw -ErrorAction Stop
            $this.Logger.WriteDebug("Read file securely: $validatedPath")
            return $content
        } catch {
            throw "Failed to read file securely '$validatedPath': $($_.Exception.Message)"
        }
    }
    
    # Delete file securely
    [void] DeleteFileSecurely([string] $FilePath) {
        if (-not (Test-Path $FilePath)) {
            return
        }
        
        try {
            # Overwrite file content before deletion (basic secure delete)
            $fileInfo = Get-Item $FilePath
            $randomData = [byte[]]::new($fileInfo.Length)
            (New-Object System.Random).NextBytes($randomData)
            [System.IO.File]::WriteAllBytes($FilePath, $randomData)
            
            # Delete file
            Remove-Item $FilePath -Force -ErrorAction Stop
            
            $this.Logger.WriteDebug("Deleted file securely: $FilePath")
            
        } catch {
            $this.Logger.WriteWarning("Failed to delete file securely '$FilePath': $($_.Exception.Message)")
        }
    }
}