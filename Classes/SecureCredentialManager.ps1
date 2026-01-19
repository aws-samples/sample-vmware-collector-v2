#
# SecureCredentialManager.ps1 - Secure credential handling
#

class SecureCredentialManager {
    [hashtable] $SecureCredentials
    [bool] $DebugMode
    
    SecureCredentialManager([bool] $DebugMode = $false) {
        $this.SecureCredentials = @{}
        $this.DebugMode = $DebugMode
    }
    
    # Store credentials securely
    [void] StoreCredential([string] $Key, [string] $Username, [string] $Password) {
        try {
            $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)
            $this.SecureCredentials[$Key] = $credential
            
            # Clear the plaintext password from memory immediately
            $Password = $null
            [System.GC]::Collect()
            
            if ($this.DebugMode) {
                Write-Debug "Stored secure credential for key: $Key, username: $Username"
            }
        } catch {
            throw "Failed to store secure credential: $($_.Exception.Message)"
        }
    }
    
    # Retrieve credential securely
    [System.Management.Automation.PSCredential] GetCredential([string] $Key) {
        if (-not $this.SecureCredentials.ContainsKey($Key)) {
            throw "Credential not found for key: $Key"
        }
        return $this.SecureCredentials[$Key]
    }
    
    # Get plaintext password (use sparingly and clear immediately)
    [string] GetPlaintextPassword([string] $Key) {
        $credential = $this.GetCredential($Key)
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    
    # Clear all credentials from memory
    [void] ClearAllCredentials() {
        # Create a copy of keys to avoid enumeration issues
        $keys = @($this.SecureCredentials.Keys)
        foreach ($key in $keys) {
            $this.SecureCredentials[$key] = $null
        }
        $this.SecureCredentials.Clear()
        [System.GC]::Collect()
        
        if ($this.DebugMode) {
            Write-Debug "All credentials cleared from memory"
        }
    }
    
    # Create database connection string without exposing password
    [string] CreateSQLConnectionString([string] $Server, [string] $Database, [string] $CredentialKey, [bool] $UseWindowsAuth = $false) {
        if ($UseWindowsAuth) {
            return "Server=$Server;Database=$Database;Integrated Security=true;Connection Timeout=30;"
        } else {
            $credential = $this.GetCredential($CredentialKey)
            $password = $this.GetPlaintextPassword($CredentialKey)
            $connectionString = "Server=$Server;Database=$Database;User Id=$($credential.UserName);Password=$password;Connection Timeout=30;"
            
            # Clear password from memory immediately
            $password = $null
            [System.GC]::Collect()
            
            return $connectionString
        }
    }
}