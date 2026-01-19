#
# LicenseDataCollector.ps1 - VMware vCenter License Information Collector
#

class LicenseDataCollector {
    [string]$VCenterServer
    [System.Collections.ArrayList]$LicenseData
    [bool]$DebugMode
    
    LicenseDataCollector([string]$vcenterServer, [bool]$debugMode = $false) {
        $this.VCenterServer = $vcenterServer
        $this.LicenseData = [System.Collections.ArrayList]::new()
        $this.DebugMode = $debugMode
    }
    
    [System.Collections.ArrayList] CollectLicenseData() {
        try {
            if ($this.DebugMode) {
                Write-Host "Starting license data collection from $($this.VCenterServer)..." -ForegroundColor Yellow
            }
            
            # Ensure we have a valid vCenter connection
            if (-not $global:DefaultVIServer -or $global:DefaultVIServer.Name -ne $this.VCenterServer) {
                throw "No valid vCenter connection found for $($this.VCenterServer)"
            }
            
            # Get the license manager from the vCenter service content
            $licenseManager = Get-View $global:DefaultVIServer.ExtensionData.Content.LicenseManager
            
            if (-not $licenseManager) {
                throw "Failed to retrieve license manager from vCenter"
            }
            
            if ($this.DebugMode) {
                Write-Host "License manager retrieved successfully" -ForegroundColor Green
            }
            
            # Get all licenses from the license manager
            $licenses = $licenseManager.Licenses
            
            if (-not $licenses -or $licenses.Count -eq 0) {
                Write-Warning "No licenses found in vCenter"
                return $this.LicenseData
            }
            
            if ($this.DebugMode) {
                Write-Host "Found $($licenses.Count) license entries" -ForegroundColor Cyan
            }
            
            # Process each license
            foreach ($license in $licenses) {
                try {
                    # Skip evaluation licenses (00000-00000-00000-00000-00000)
                    if ($license.LicenseKey -eq "00000-00000-00000-00000-00000") {
                        if ($this.DebugMode) {
                            Write-Host "Skipping evaluation license: $($license.Name)" -ForegroundColor Gray
                        }
                        continue
                    }
                    
                    # Create license data object with comprehensive information
                    $licenseInfo = [PSCustomObject]@{
                        "Name" = if ($license.Name) { $license.Name } else { "Unknown" }
                        "Key" = if ($license.LicenseKey) { $license.LicenseKey } else { "Unknown" }
                        "Total" = if ($null -ne $license.Total) { $license.Total } else { 0 }
                        "Used" = if ($null -ne $license.Used) { $license.Used } else { 0 }
                        "Available" = if ($null -ne $license.Total -and $null -ne $license.Used) { 
                            $license.Total - $license.Used 
                        } else { 0 }
                        "Edition Key" = if ($license.EditionKey) { $license.EditionKey } else { "Unknown" }
                        "Cost Unit" = if ($license.CostUnit) { $license.CostUnit } else { "Unknown" }
                        "VI SDK Server type" = "VirtualCenter"
                        "VI SDK API Version" = $global:DefaultVIServer.Version
                        "VI SDK Server" = $global:DefaultVIServer.Name
                        "Collection Timestamp" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                        "License Type" = $this.DetermineLicenseType($license.Name, $license.EditionKey)
                        "Utilization Percentage" = if ($license.Total -gt 0) { 
                            [Math]::Round(($license.Used / $license.Total) * 100, 2) 
                        } else { 0 }
                    }
                    
                    # Add additional license properties if available
                    if ($license.Properties) {
                        foreach ($property in $license.Properties) {
                            if ($property.Key -and $property.Value) {
                                $licenseInfo | Add-Member -NotePropertyName "Property_$($property.Key)" -NotePropertyValue $property.Value
                            }
                        }
                    }
                    
                    $this.LicenseData.Add($licenseInfo) | Out-Null
                    
                    if ($this.DebugMode) {
                        Write-Host "Processed license: $($license.Name) - $($license.Used)/$($license.Total) used" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Warning "Failed to process license '$($license.Name)': $($_.Exception.Message)"
                    if ($this.DebugMode) {
                        Write-Host "License processing error details: $($_.Exception)" -ForegroundColor Red
                    }
                }
            }
            
            if ($this.DebugMode) {
                Write-Host "License data collection completed. Collected $($this.LicenseData.Count) valid licenses" -ForegroundColor Green
            }
            
            return $this.LicenseData
        }
        catch {
            Write-Error "Failed to collect license data: $($_.Exception.Message)"
            if ($this.DebugMode) {
                Write-Host "License collection error details: $($_.Exception)" -ForegroundColor Red
            }
            return $this.LicenseData
        }
    }
    
    [string] DetermineLicenseType([string]$licenseName, [string]$editionKey) {
        # Determine license type based on name and edition key
        if ($licenseName -like "*vSphere*") {
            if ($licenseName -like "*Enterprise*Plus*" -or $editionKey -like "*enterpriseplus*") {
                return "vSphere Enterprise Plus"
            }
            elseif ($licenseName -like "*Enterprise*" -or $editionKey -like "*enterprise*") {
                return "vSphere Enterprise"
            }
            elseif ($licenseName -like "*Standard*" -or $editionKey -like "*standard*") {
                return "vSphere Standard"
            }
            elseif ($licenseName -like "*Essentials*Plus*" -or $editionKey -like "*essentialsplus*") {
                return "vSphere Essentials Plus"
            }
            elseif ($licenseName -like "*Essentials*" -or $editionKey -like "*essentials*") {
                return "vSphere Essentials"
            }
            else {
                return "vSphere (Other)"
            }
        }
        elseif ($licenseName -like "*vCenter*") {
            return "vCenter Server"
        }
        elseif ($licenseName -like "*vSAN*") {
            return "vSAN"
        }
        elseif ($licenseName -like "*NSX*") {
            return "NSX"
        }
        elseif ($licenseName -like "*vRealize*") {
            return "vRealize Suite"
        }
        else {
            return "Other VMware License"
        }
    }
    
    [void] ExportToCSV([string]$filePath) {
        try {
            if ($this.LicenseData.Count -eq 0) {
                Write-Warning "No license data to export"
                return
            }
            
            $this.LicenseData | Export-Csv -Path $filePath -NoTypeInformation
            Write-Host "License data exported to: $filePath" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to export license data to CSV: $($_.Exception.Message)"
        }
    }
    
    [void] ExportToExcel([string]$filePath, [string]$worksheetName = "License Information") {
        try {
            if ($this.LicenseData.Count -eq 0) {
                Write-Warning "No license data to export"
                return
            }
            
            # Check if ImportExcel module is available
            if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
                Write-Warning "ImportExcel module not available. Installing..."
                Install-Module ImportExcel -Force -Scope CurrentUser
            }
            Import-Module ImportExcel -Force
            
            $this.LicenseData | Export-Excel -Path $filePath -WorksheetName $worksheetName -AutoSize -FreezeTopRow
            Write-Host "License data exported to Excel worksheet '$worksheetName' in: $filePath" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to export license data to Excel: $($_.Exception.Message)"
        }
    }
    
    [PSCustomObject] GetLicenseSummary() {
        if ($this.LicenseData.Count -eq 0) {
            return [PSCustomObject]@{
                TotalLicenses = 0
                TotalCapacity = 0
                TotalUsed = 0
                TotalAvailable = 0
                OverallUtilization = 0
                LicenseTypes = @()
            }
        }
        
        $summary = [PSCustomObject]@{
            TotalLicenses = $this.LicenseData.Count
            TotalCapacity = ($this.LicenseData | Measure-Object Total -Sum).Sum
            TotalUsed = ($this.LicenseData | Measure-Object Used -Sum).Sum
            TotalAvailable = ($this.LicenseData | Measure-Object Available -Sum).Sum
            OverallUtilization = 0
            LicenseTypes = ($this.LicenseData | Group-Object "License Type" | Select-Object Name, Count)
        }
        
        if ($summary.TotalCapacity -gt 0) {
            $summary.OverallUtilization = [Math]::Round(($summary.TotalUsed / $summary.TotalCapacity) * 100, 2)
        }
        
        return $summary
    }
}