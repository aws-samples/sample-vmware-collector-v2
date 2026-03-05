# Accelerating VMware Cloud Migration with AWS Transform and PowerCLI

A comprehensive PowerShell script for collecting VMware vCenter inventory and performance data, optimized for AWS migration assessments and capacity planning.

## Overview

This script connects to VMware vCenter Server and collects detailed VM inventory data with historical performance metrics, generating output in three industry-standard formats for migration planning and analysis.

### Key Features

- **Comprehensive Data Collection** - 47+ fields per VM including hardware, performance, and infrastructure details
- **Performance Metrics** - Historical CPU and Memory utilization using P95 percentiles for realistic peak values
- **Multiple Output Formats** - AWS Migration Evaluator, MPA Template, and RVTools-compatible formats
- **Optimized Performance** - Intelligent caching and bulk API calls for fast collection
- **Advanced Filtering** - Filter by cluster, datacenter, host, environment, or custom VM lists
- **Data Anonymization** - Optional anonymization with reversible mapping for sensitive environments
- **SQL Server Detection** - Optional SQL Server edition detection for database workloads
- **Secure by Default** - SSL validation, secure credential handling, and comprehensive error handling

### Performance

Collection time varies by output format and environment size:

| Format | 100 VMs | 1,000 VMs | Notes |
|--------|---------|-----------|-------|
| **MPA** (default) | ~16 min | ~2.5 hours | Fastest - recommended for most use cases |
| **ME** | ~16 min | ~2.5 hours | Similar to MPA performance |
| **RVTools** | ~54 min | ~9 hours | Slowest - generates 27 detailed CSV files |
| **MPA,ME** | ~16 min | ~2.5 hours | Both formats, minimal overhead |
| **All** | ~54 min | ~9 hours | All three formats (RVTools is bottleneck) |

**Recommendation:** Use MPA format (default) for fastest collection. Only use RVTools if you need the detailed CSV files.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage Examples](#usage-examples)
- [Parameters](#parameters)
- [Output Formats](#output-formats)
- [Advanced Features](#advanced-features)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [FAQ](#faq)

---

## Prerequisites

### Required Software

1. **PowerShell 5.1 or later**
   ```powershell
   $PSVersionTable.PSVersion
   ```

2. **VMware PowerCLI Module**
   ```powershell
   Install-Module -Name VMware.PowerCLI -Scope CurrentUser
   ```

3. **ImportExcel Module**
   ```powershell
   Install-Module -Name ImportExcel -Scope CurrentUser
   ```

### Required Permissions

- vCenter Server read-only access (minimum)
- View permissions on: VMs, Hosts, Clusters, Datastores
- Performance metrics read access

### Optional (for SQL Detection)

- SQL Server access (Windows or SQL Authentication)
- Network connectivity to SQL Server instances

---

## Installation

### Option 1: Download Files

1. Download the script and required classes:
   - `vmware-collector.ps1`
   - `Classes/` folder with all security classes

2. Maintain the folder structure:
   ```
   VMwareCollector/
   ├── vmware-collector.ps1
   └── Classes/
       ├── SecureCredentialManager.ps1
       ├── SecureErrorHandler.ps1
       ├── SecureFileManager.ps1
       ├── InputValidator.ps1
       ├── Interfaces.ps1
       └── SimpleLogger.ps1
   ```

### Option 2: Extract from ZIP

1. Extract `VMwareCollector_SecurityReview.zip`
2. Navigate to the extracted folder
3. Run the script from this location

---

## Quick Start

### Basic Usage

```powershell
# Navigate to script directory
cd "C:\Path\To\VMwareCollector"

# Run with basic parameters
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "readonly-user" `
    -password "YourPassword"
```

This will:
- Connect to vCenter Server
- Collect data from all powered-on VMs
- Gather 7 days of performance metrics
- Generate MPA format (default - fastest option)
- Create output in `VMware_Export_YYYYMMDD_HHMMSS/` folder

**Note:** MPA is now the default format for optimal performance. Use `-outputFormat "All"` if you need all three formats.

### Output Files

Default output (MPA format only):
```
VMware_Export_20251216_143052/
└── MPA_Template_20251216_143052.xlsx                 # Migration Portfolio Assessment
```

With all formats (`-outputFormat "All"`):
```
VMware_Export_20251216_143052/
├── ME_ConsolidatedDataImport_20251216_143052.xlsx    # AWS Migration Evaluator
├── MPA_Template_20251216_143052.xlsx                 # Migration Portfolio Assessment
└── RVTools_Export_20251216_143052.zip                # RVTools-compatible CSVs
```

---

## Usage Examples

### Example 1: Standard Collection

```powershell
# Collect 7 days of data from all powered-on VMs
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password"
```

### Example 2: Extended Collection Period

```powershell
# Collect 30 days of performance data
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -collectionDays 30
```

### Example 3: Specific Output Format

```powershell
# Generate only AWS Migration Evaluator format
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -outputFormat "ME"

# Generate both MPA and ME formats (fast)
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -outputFormat "MPA,ME"

# Generate all three formats (slower due to RVTools)
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -outputFormat "All"
```

### Example 4: With Anonymization

```powershell
# Anonymize sensitive data (server names, IPs, etc.)
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -anonymize
```

### Example 5: Fast Mode for Large Environments

```powershell
# Skip detailed analysis for maximum speed
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -fastMode `
    -skipPerformanceData
```

### Example 6: Filter by Cluster

```powershell
# Collect only from production clusters
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -IncludeCluster "PROD*,Critical*"
```

### Example 7: Specific VM List

```powershell
# Process only VMs from a CSV file
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -vmListFile "vm_list.csv"
```

### Example 8: With SQL Server Detection

```powershell
# Detect SQL Server editions (Windows Authentication)
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -enableSQLDetection

# Or with SQL Authentication
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -enableSQLDetection `
    -sqlAuthMode "SQL" `
    -sqlUsername "sa" `
    -sqlPassword "SqlPassword"
```
---

## Parameters

### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-address` | String | vCenter Server address (FQDN or IP) |
| `-username` | String | vCenter username |
| `-password` | String | vCenter password |

### Optional Parameters - General

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-collectionDays` | Int | 7 | Days of performance data (1-365) |
| `-filterVMs` | String | 'Y' | 'Y' = powered on only, 'N' = all VMs |
| `-protocol` | String | 'https' | Connection protocol ('http' or 'https') |
| `-port` | Int | 0 | Port number (0 = auto-detect: 443/80) |
| `-outputFormat` | String | 'MPA' | Output format: 'MPA' (default), 'ME', 'RVTools', 'MPA,ME', 'All' |
| `-enableLogging` | Switch | False | Enable debug logging |
| `-disableSSL` | Switch | False | Disable SSL validation (LAB ONLY) |

### Optional Parameters - Performance

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-maxParallelThreads` | Int | 20 | Parallel processing threads (1-50) |
| `-skipPerformanceData` | Switch | False | Skip performance collection (faster) |
| `-fastMode` | Switch | False | Maximum speed mode |

### Optional Parameters - Filtering

| Parameter | Type | Description |
|-----------|------|-------------|
| `-vmListFile` | String | Path to CSV/TXT file with VM names |
| `-IncludeCluster` | String | Comma-separated cluster names (wildcards supported) |
| `-ExcludeCluster` | String | Comma-separated cluster names to exclude |
| `-IncludeDatacenter` | String | Comma-separated datacenter names |
| `-ExcludeDatacenter` | String | Comma-separated datacenter names to exclude |
| `-IncludeHost` | String | Comma-separated host names |
| `-ExcludeHost` | String | Comma-separated host names to exclude |
| `-IncludeEnvironment` | String | 'Production' or 'NonProduction' |
| `-ExcludeEnvironment` | String | 'Production' or 'NonProduction' |

### Optional Parameters - SQL Detection

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-enableSQLDetection` | Switch | False | Enable SQL Server detection |
| `-sqlAuthMode` | String | 'Windows' | 'Windows' or 'SQL' authentication |
| `-sqlUsername` | String | - | SQL Server username |
| `-sqlPassword` | String | - | SQL Server password |
| `-sqlConnectionTimeout` | Int | 5 | SQL connection timeout (1-30 seconds) |

### Optional Parameters - Data Privacy

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-anonymize` | Switch | False | Anonymize sensitive data |
| `-purgeCSV` | Switch | True | Remove CSV files after ZIP creation |

---

## Output Format Options

The script supports flexible output format selection for optimal performance:

### Format Selection

| Option | Description | Performance (100 VMs) | Use Case |
|--------|-------------|----------------------|----------|
| `MPA` | MPA Template only (default) | ~16 minutes | Fastest - recommended for most assessments |
| `ME` | Migration Evaluator only | ~16 minutes | AWS ME import only |
| `RVTools` | RVTools CSV files only | ~54 minutes | RVTools compatibility only |
| `MPA,ME` | Both MPA and ME | ~16 minutes | Comprehensive analysis + AWS import |
| `All` | All three formats | ~54 minutes | Complete package (RVTools adds time) |

### Examples

```powershell
# Default: MPA only (fastest)
.\vmware-collector.ps1 -address "vcenter" -username "admin" -password "pass"

# Generate both MPA and ME formats
.\vmware-collector.ps1 ... -outputFormat "MPA,ME"

# Generate only ME format
.\vmware-collector.ps1 ... -outputFormat "ME"

# Generate all three formats
.\vmware-collector.ps1 ... -outputFormat "All"
```

**Performance Tip:** RVTools format takes 3x longer than MPA/ME due to 27 detailed CSV files and 500+ API calls. Only use it if you specifically need RVTools compatibility.

---

## Output Formats

### 1. ME Format (AWS Migration Evaluator)

**File:** `ME_ConsolidatedDataImport_YYYYMMDD_HHMMSS.xlsx`

**Purpose:** AWS Migration Evaluator import template

**Worksheets:**
- **Template** - Server inventory with performance metrics (16 columns)

**Columns (16):**
1. Server Name
2. CPU Cores
3. Memory (MB)
4. Provisioned Storage (GB)
5. Operating System
6. Is Virtual?
7. Hypervisor Name
8. Cpu String
9. Environment
10. SQL Edition
11. Application
12. Cpu Utilization Peak (%)
13. Memory Utilization Peak (%)
14. Time In-Use (%)
15. Annual Cost (USD)
16. Storage Type

**Format Notes:**
- **Utilization format:** Decimal (0.0-1.0) where 0.72 = 72%
- **P95 percentile** for peak values (realistic sustained peaks)
- **Ready for direct import** to AWS Migration Evaluator
- **CPU String:** Actual processor model from ESXi host

### 2. MPA Format (Migration Portfolio Assessment)

**File:** `MPA_Template_YYYYMMDD_HHMMSS.xlsx`

**Purpose:** AWS Migration Portfolio Assessment

**Worksheets:**
- **Servers** - Server inventory with performance metrics (20 columns)

**Columns (20):**
1. Serverid
2. isPhysical
3. hypervisor
4. HOSTNAME
5. osName
6. osVersion
7. numCpus
8. numCoresPerCpu
9. numThreadsPerCore
10. maxCpuUsagePctDec (%)
11. avgCpuUsagePctDec (%)
12. totalRAM (GB)
13. maxRamUsagePctDec (%)
14. avgRamUtlPctDec (%)
15. Uptime
16. Environment Type
17. Storage-Total Disk Size (GB)
18. Storage-Utilization %
19. Storage-Max Read IOPS Size (KB)
20. Storage-Max Write IOPS Size (KB)

**Format Notes:**
- **Utilization format:** Percentage (0.51 = 0.51%, not 51%)
- **P95 percentile** for peak values (realistic sustained peaks)
- **Ready for AWS MPA** import
- **Core provisioning data:** 100% accurate (CPUs, RAM, cores)

### 3. RVTools Format

**File:** `RVTools_Export_YYYYMMDD_HHMMSS.zip`

**Purpose:** RVTools-compatible format

**Contents (27 CSV files):**
- `RVTools_tabvInfo.csv` - VM information
- `RVTools_tabvCPU.csv` - CPU details
- `RVTools_tabvMemory.csv` - Memory details
- `RVTools_tabvDisk.csv` - Disk information
- `RVTools_tabvPartition.csv` - Partition details
- `RVTools_tabvNetwork.csv` - Network adapters
- `RVTools_tabvHost.csv` - ESXi host information
- `RVTools_tabvCluster.csv` - Cluster information
- `RVTools_tabvDatastore.csv` - Datastore details
- And 18 more CSV files...

**Format Notes:**
- Compatible with RVTools import
- Detailed infrastructure information
- Can be imported back into RVTools

---

## Advanced Features

### VM List File

Process specific VMs from a file:

**CSV Format:**
```csv
VM,Environment
WebServer01,Production
DBServer02,Production
TestVM03,Development
```

**TXT Format:**
```
WebServer01
DBServer02
TestVM03
```

**Usage:**
```powershell
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -vmListFile "vm_list.csv"
```

### Wildcard Filtering

Use wildcards for flexible filtering:

```powershell
# Include multiple clusters with wildcards
-IncludeCluster "PROD*,Critical*,Finance*"

# Exclude test hosts
-ExcludeHost "*test*,*dev*,*lab*"

# Include specific datacenters
-IncludeDatacenter "DC1,DC2"
```

### Environment Detection

Automatically detects environment based on VM names:

**Production Patterns:**
- prod, production, prd, live, lv
- p-, -p-, -p$
- master, main
- critical, crit
- primary, pri
- active, act

**Usage:**
```powershell
# Collect only production VMs
-IncludeEnvironment "Production"

# Exclude production VMs (dev/test only)
-ExcludeEnvironment "Production"
```

### Data Anonymization

Anonymizes sensitive data while preserving metrics:

**Anonymized:**
- Server names → SERVER-0001, SERVER-0002
- Host names → HOST-0001, HOST-0002
- IP addresses → 10.x.x.x range
- DNS names → Anonymized
- Cluster names → CLUSTER-0001

**Preserved:**
- CPU/Memory metrics
- Storage capacity
- Performance data
- Technical specifications

**Output:**
- Original files (anonymized data)
- Mapping file for de-anonymization

### SQL Server Detection (BETA VERSION!)

Detects SQL Server editions for licensing:

**Detection Methods:**
1. **Pattern Matching** (default) - VM name/OS patterns
2. **Direct Query** (optional) - Connects to SQL Server

**Supported Editions:**
- SQL Server Enterprise Edition
- SQL Server Standard Edition
- SQL Server Developer Edition
- SQL Server Express Edition
- SQL Server Web Edition

**Authentication:**
- Windows Authentication (current user context)
- SQL Authentication (username/password)

---

## Performance Metrics Explained

### CPU Utilization

**Metric:** `cpu.usage.average`
- Percentage of allocated vCPU capacity
- VMware standard metric

**Calculations:**
- **Peak (P95):** 95th percentile of all samples
- **Average:** Mean of all samples

**Why P95?**
- Excludes temporary spikes (top 5%)
- Realistic sustained peak usage
- Prevents over-provisioning
- AWS recommended approach

**Example:**
```
VM: WebServer01 (8 vCPU)
Samples: 2,016 (7 days × 288 samples/day)
Values: [15%, 23%, 45%, ..., 85%, 98%]

P95 = 72.3% (realistic peak)
Average = 45.2% (typical usage)
Maximum = 98% (outlier spike)

Right-sizing: 6 vCPU recommended (72.3% × 8 = 5.78)
```

### Memory Utilization

**Metric:** `mem.consumed.average`
- Actual consumed memory in KB
- Includes guest OS overhead

**Calculations:**
- **Peak (P95):** 95th percentile converted to percentage
- **Average:** Mean converted to percentage
- **Formula:** (KB / 1024) / AllocatedMemoryMB × 100

**Example:**
```
VM: WebServer01 (16 GB RAM)
Samples: 2,016 (7 days × 288 samples/day)
Values: [8 GB, 10 GB, 12 GB, ..., 14 GB, 15.8 GB]

P95 = 14.3 GB = 89.4% of 16 GB
Average = 10.5 GB = 65.6% of 16 GB

Right-sizing: 14 GB recommended
```

### Collection Intervals

Script automatically selects optimal intervals:

| Period | Interval | Samples/Day | Total Samples (7 days) |
|--------|----------|-------------|------------------------|
| ≤2 days | 5 minutes | 288 | 576-2,016 |
| 3-7 days | 30 minutes | 48 | 144-336 |
| 8-30 days | 2 hours | 12 | 96-360 |
| 31-365 days | 1 day | 1 | 7-365 |

---

## Troubleshooting

### Common Issues

#### Issue: "Failed to connect to vCenter Server"

**Possible Causes:**
- Incorrect credentials
- Network connectivity issues
- SSL certificate validation failure
- Firewall blocking connection

**Solutions:**
```powershell
# Verify credentials
Test-Connection vcenter.company.com

# Check SSL (lab only)
.\vmware-collector.ps1 ... -disableSSL

# Verify port
.\vmware-collector.ps1 ... -port 443
```

#### Issue: "No performance data collected"

**Possible Causes:**
- VMs powered off
- Statistics level too low
- No historical data available
- Date range outside available data

**Solutions:**
```powershell
# Check VM power state
Get-VM | Where-Object {$_.PowerState -eq "PoweredOff"}

# Use shorter collection period
.\vmware-collector.ps1 ... -collectionDays 1

# Skip performance data
.\vmware-collector.ps1 ... -skipPerformanceData
```

#### Issue: "Module not found: VMware.PowerCLI"

**Solution:**
```powershell
# Install PowerCLI
Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force

# Verify installation
Get-Module -ListAvailable VMware.PowerCLI
```

#### Issue: "Module not found: ImportExcel"

**Solution:**
```powershell
# Install ImportExcel
Install-Module -Name ImportExcel -Scope CurrentUser -Force

# Verify installation
Get-Module -ListAvailable ImportExcel
```

#### Issue: "Access denied to SQL Server"

**Possible Causes:**
- Incorrect SQL credentials
- Network connectivity to SQL Server
- SQL Server not listening on default port
- Firewall blocking SQL port (1433)

**Solutions:**
```powershell
# Use Windows Authentication
.\vmware-collector.ps1 ... -enableSQLDetection

# Use SQL Authentication
.\vmware-collector.ps1 ... -enableSQLDetection `
    -sqlAuthMode "SQL" `
    -sqlUsername "sa" `
    -sqlPassword "password"

# Increase timeout
.\vmware-collector.ps1 ... -sqlConnectionTimeout 10
```

#### Issue: "Script runs very slowly"

**Solutions:**
```powershell
# Use FastMode
.\vmware-collector.ps1 ... -fastMode

# Skip performance data
.\vmware-collector.ps1 ... -skipPerformanceData

# Reduce collection period
.\vmware-collector.ps1 ... -collectionDays 1

# Filter to specific VMs
.\vmware-collector.ps1 ... -vmListFile "vm_list.csv"
```

### Debug Logging

Enable detailed logging for troubleshooting:

```powershell
.\vmware-collector.ps1 `
    -address "vcenter.company.com" `
    -username "admin" `
    -password "password" `
    -enableLogging
```

Log file location: `VMware_Export_YYYYMMDD_HHMMSS/vm_collection_YYYYMMDD_HHMMSS.log`

---

## Best Practices

### Security

1. **Use Read-Only Accounts**
   ```powershell
   # Create dedicated read-only account in vCenter
   # Grant only necessary permissions
   ```

2. **Avoid Plaintext Passwords**
   ```powershell
   # Use credential prompts
   $cred = Get-Credential
   .\vmware-collector.ps1 -address "vcenter" `
       -username $cred.UserName `
       -password $cred.GetNetworkCredential().Password
   ```

3. **Enable SSL Validation**
   ```powershell
   # Only use -disableSSL in isolated lab environments
   # Install proper certificates in production
   ```

4. **Review Logs**
   ```powershell
   # Enable logging and review for issues
   -enableLogging
   ```

### Performance

1. **Use Appropriate Collection Period**
   ```powershell
   # 7 days for standard assessment
   -collectionDays 7
   
   # 30 days for detailed analysis
   -collectionDays 30
   ```

2. **Filter Unnecessary VMs**
   ```powershell
   # Use VM list file for specific VMs
   -vmListFile "production_vms.csv"
   
   # Or filter by cluster
   -IncludeCluster "PROD*"
   ```

3. **Use FastMode for Large Environments**
   ```powershell
   # Skip detailed analysis
   -fastMode -skipPerformanceData
   ```

4. **Run During Off-Peak Hours**
   - Schedule during maintenance windows
   - Avoid peak business hours
   - Consider vCenter load

### Data Quality

1. **Verify VM Power State**
   ```powershell
   # Ensure VMs are powered on for performance data
   -filterVMs 'Y'
   ```

2. **Check Statistics Level**
   ```powershell
   # Verify vCenter statistics level is 2 or higher
   Get-StatInterval
   ```

3. **Validate Output**
   - Review generated files
   - Check for missing data
   - Verify performance metrics

4. **Use Anonymization for Sensitive Data**
   ```powershell
   # Anonymize before sharing externally
   -anonymize
   ```

---

## FAQ

### General Questions

**Q: How long does the script take to run?**
A: Depends on environment size:
- Small (<1,000 VMs): 5-10 minutes
- Medium (1,000-5,000 VMs): 15-30 minutes
- Large (5,000-10,000 VMs): 30-60 minutes
- Use `-fastMode` for faster collection

**Q: Does the script make any changes to vCenter?**
A: No, the script is read-only. It only collects data and generates reports.

**Q: Can I run this on a schedule?**
A: Yes, use Windows Task Scheduler or cron to automate collection.

**Q: What permissions are required?**
A: Read-only access to vCenter with view permissions on VMs, hosts, clusters, and datastores.

### Performance Questions

**Q: Why use P95 instead of maximum?**
A: P95 excludes temporary spikes (top 5%) and represents realistic sustained peak usage, preventing over-provisioning.

**Q: Can I collect more than 365 days?**
A: No, the script limits collection to 365 days due to vCenter statistics retention.

**Q: What if VMs are powered off?**
A: Powered-off VMs use default values (25% CPU, 60% Memory) since no performance data is available.

### Output Questions

**Q: Which format should I use?**
A: 
- **MPA Format** (default) - Fastest, comprehensive migration analysis (16 min for 100 VMs)
- **ME Format** - For AWS Migration Evaluator import (16 min for 100 VMs)
- **MPA,ME** - Both formats with minimal overhead (16 min for 100 VMs)
- **RVTools Format** - For RVTools compatibility (54 min for 100 VMs - slowest)
- **All** - Generate all three formats (54 min for 100 VMs due to RVTools)

**Q: Can I import RVTools format back into RVTools?**
A: Yes, the CSV files are fully compatible with RVTools import.

**Q: What's the difference between anonymized and regular output?**
A: Anonymized output replaces server names, IPs, and hostnames with generic identifiers while preserving all metrics.

### SQL Detection Questions

**Q: Is SQL detection required?**
A: No, it's optional. The script uses pattern matching by default.

**Q: What authentication methods are supported?**
A: Windows Authentication (default) and SQL Authentication.

**Q: Does SQL detection work with Always On?**
A: Yes, the script detects Always On configuration and reports it.

### Troubleshooting Questions

**Q: Why is performance data missing?**
A: Check:
- VM power state (must be powered on)
- vCenter statistics level (must be 2+)
- Date range (must be within retention period)
- Use `-enableLogging` to debug

**Q: Why does the script fail with SSL errors?**
A: vCenter has self-signed certificates. Use `-disableSSL` in lab environments only.

**Q: Can I resume a failed collection?**
A: No, the script must be re-run. Use filtering to process specific VMs.

---

## Scheduling and Automation

The collector can be scheduled to run automatically during off-peak hours or on a recurring basis. This is useful for:
- Regular data collection for trending analysis
- Automated weekly/monthly reports
- Minimizing impact on production vCenter during business hours

### Windows Task Scheduler

**Create a Scheduled Task:**

1. **Create a PowerShell script wrapper** (`Run-VMwareCollector.ps1`):
```powershell
# Run-VMwareCollector.ps1
# Wrapper script for scheduled execution

$vCenterAddress = "vcenter.company.com"
$username = "readonly-user"
$password = "YourSecurePassword"  # Consider using encrypted credentials

# Run the collector
& "C:\Scripts\VMwareCollector\vmware-collector.ps1" `
    -address $vCenterAddress `
    -username $username `
    -password $password `
    -outputFormat "MPA" `
    -collectionDays 7 `
    -enableLogging

# Optional: Email notification on completion
# Send-MailMessage -To "admin@company.com" -Subject "VMware Collection Complete" -Body "Collection finished at $(Get-Date)"
```

2. **Create the scheduled task:**
```powershell
# Create scheduled task to run every Sunday at 2 AM
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\Scripts\Run-VMwareCollector.ps1"

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2:00AM

$principal = New-ScheduledTaskPrincipal -UserId "DOMAIN\ServiceAccount" `
    -LogonType Password -RunLevel Highest

Register-ScheduledTask -TaskName "VMware Inventory Collection" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Description "Weekly VMware inventory and performance data collection"
```

**Alternative: Using Task Scheduler GUI:**

1. Open Task Scheduler (`taskschd.msc`)
2. Create Basic Task → Name: "VMware Inventory Collection"
3. Trigger: Weekly → Select day and time (e.g., Sunday 2:00 AM)
4. Action: Start a program
   - Program: `PowerShell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "C:\Scripts\Run-VMwareCollector.ps1"`
5. Finish and enter credentials when prompted

### Linux/macOS Cron Job

**Create a cron job:**

1. **Create a wrapper script** (`run-vmware-collector.sh`):
```bash
#!/bin/bash
# run-vmware-collector.sh

VCENTER="vcenter.company.com"
USERNAME="readonly-user"
PASSWORD="YourSecurePassword"

# Run the collector using PowerShell Core (pwsh)
pwsh -File /opt/scripts/vmware-collector.ps1 \
    -address "$VCENTER" \
    -username "$USERNAME" \
    -password "$PASSWORD" \
    -outputFormat "MPA" \
    -collectionDays 7 \
    -enableLogging

# Optional: Send notification
# echo "VMware collection completed at $(date)" | mail -s "Collection Complete" admin@company.com
```

2. **Make it executable:**
```bash
chmod +x /opt/scripts/run-vmware-collector.sh
```

3. **Add to crontab:**
```bash
# Edit crontab
crontab -e

# Run every Sunday at 2:00 AM
0 2 * * 0 /opt/scripts/run-vmware-collector.sh >> /var/log/vmware-collector.log 2>&1

# Run every night at 11:00 PM
0 23 * * * /opt/scripts/run-vmware-collector.sh >> /var/log/vmware-collector.log 2>&1

# Run first day of every month at 3:00 AM
0 3 1 * * /opt/scripts/run-vmware-collector.sh >> /var/log/vmware-collector.log 2>&1
```

### Best Practices for Scheduled Execution

1. **Run During Off-Peak Hours**
   - Schedule between 10 PM - 6 AM
   - Avoid business hours to minimize vCenter load
   - Consider maintenance windows

2. **Use Service Accounts**
   - Create dedicated read-only service account
   - Use strong passwords or certificate authentication
   - Rotate credentials regularly

3. **Enable Logging**
   - Always use `-enableLogging` for scheduled runs
   - Monitor logs for failures
   - Set up log rotation

4. **Output Management**
   - Archive old collections automatically
   - Use date-stamped output directories
   - Implement retention policies (e.g., keep last 12 collections)

5. **Error Handling**
   - Add email notifications for failures
   - Monitor scheduled task execution
   - Set up alerts for missed runs

### Example: Advanced Scheduled Script with Error Handling

```powershell
# Advanced-VMwareCollector-Scheduled.ps1

param(
    [string]$vCenterAddress = "vcenter.company.com",
    [string]$EmailTo = "admin@company.com"
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "C:\Logs\VMwareCollector_$timestamp.log"

try {
    # Start logging
    Start-Transcript -Path $logFile
    
    Write-Host "Starting VMware collection at $(Get-Date)"
    
    # Run collector
    & "C:\Scripts\VMwareCollector\vmware-collector.ps1" `
        -address $vCenterAddress `
        -username "readonly-user" `
        -password "YourPassword" `
        -outputFormat "MPA" `
        -collectionDays 7 `
        -enableLogging
    
    Write-Host "Collection completed successfully at $(Get-Date)"
    
    # Send success notification
    Send-MailMessage `
        -To $EmailTo `
        -From "vmware-collector@company.com" `
        -Subject "VMware Collection Successful - $timestamp" `
        -Body "Collection completed successfully. Check output directory for results." `
        -SmtpServer "smtp.company.com"
    
} catch {
    Write-Error "Collection failed: $_"
    
    # Send failure notification
    Send-MailMessage `
        -To $EmailTo `
        -From "vmware-collector@company.com" `
        -Subject "VMware Collection FAILED - $timestamp" `
        -Body "Collection failed with error: $_`n`nCheck log: $logFile" `
        -SmtpServer "smtp.company.com" `
        -Priority High
    
    exit 1
} finally {
    Stop-Transcript
}
```

### Monitoring Scheduled Collections

**Check Task Status (Windows):**
```powershell
# View scheduled task status
Get-ScheduledTask -TaskName "VMware Inventory Collection" | Get-ScheduledTaskInfo

# View last run result
Get-ScheduledTask -TaskName "VMware Inventory Collection" | 
    Select-Object TaskName, State, LastRunTime, LastTaskResult
```

**Check Cron Job Status (Linux):**
```bash
# View cron logs
grep "vmware-collector" /var/log/syslog

# Check last execution
tail -f /var/log/vmware-collector.log
```

---

## Security & Read-Only Operations

### Script is 100% Read-Only

**This script performs NO modifications to your vCenter environment.** It is designed as a pure data collection and reporting tool for migration assessments.

#### What the Script Does (Read-Only)

- **Connects** to vCenter Server using provided credentials  
- **Reads** VM inventory data (names, configurations, hardware specs)  
- **Queries** performance metrics (CPU, memory utilization)  
- **Retrieves** infrastructure information (hosts, clusters, datastores)  
- **Collects** network and storage details  
- **Exports** data to local Excel/CSV files  

#### What the Script CANNOT Do

- **Cannot create, modify, or delete VMs**  
- **Cannot change VM configurations** (CPU, memory, disks)  
- **Cannot modify vCenter settings**  
- **Cannot alter host or cluster configurations**  
- **Cannot change network or storage settings**  
- **Cannot create or delete snapshots**  
- **Cannot power on/off VMs**  
- **Cannot modify permissions or roles**  

### PowerCLI Cmdlets Used (All Read-Only)

The script exclusively uses `Get-*` cmdlets for data retrieval:

```powershell
# VM Data Collection
Get-VM                    # Retrieve VM objects
Get-VMHost                # Retrieve ESXi host information
Get-Cluster               # Retrieve cluster information
Get-Datacenter            # Retrieve datacenter information
Get-Datastore             # Retrieve datastore information

# Performance Metrics
Get-Stat                  # Retrieve performance statistics

# Hardware Details
Get-NetworkAdapter        # Retrieve network adapter information
Get-HardDisk              # Retrieve disk information
Get-Snapshot              # Retrieve snapshot information (read-only)

# Infrastructure
Get-ResourcePool          # Retrieve resource pool information
Get-VirtualSwitch         # Retrieve virtual switch information
Get-VirtualPortGroup      # Retrieve port group information
Get-DrsRule               # Retrieve DRS rules (read-only)
```

**Note:** The only `Set-*` cmdlet used is `Set-PowerCLIConfiguration`, which configures **local PowerShell session settings only** (SSL validation, CEIP participation). This does NOT modify vCenter.

### SQL Server Detection Security

When SQL Server detection is enabled (`-enableSQLDetection`), the script performs **read-only queries** to detect database editions.

#### SQL Query Used (Read-Only)

```sql
-- This is the ONLY SQL query executed by the script
SELECT 
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('IsClustered') AS IsClustered,
    SERVERPROPERTY('IsHadrEnabled') AS IsHadrEnabled,
    @@VERSION AS VersionString
```

#### SQL Detection Safety Analysis

- **Read-Only Query** - Uses only `SELECT` statement  
- **System Functions** - `SERVERPROPERTY()` is a read-only system function  
- **No Data Access** - Queries system metadata only, not user data  
- **No Modifications** - Cannot INSERT, UPDATE, DELETE, DROP, ALTER, CREATE, or TRUNCATE  
- **No Stored Procedures** - Does not execute any stored procedures  
- **No Dynamic SQL** - No dynamic query execution  
- **Short Timeout** - 5-second connection timeout (configurable)  
- **Immediate Disconnect** - Closes connection immediately after query  

#### SQL Permissions Required (Minimal)

The SQL query requires only:
- **CONNECT** permission to master database
- **VIEW SERVER STATE** permission (to read `SERVERPROPERTY()`)

These are **minimal read-only permissions** that do not allow any data modifications.

#### SQL Detection Behavior

**What SQL Detection Does:**
1. Tests TCP connectivity to SQL Server ports (1433, 1434, etc.)
2. Attempts to connect using provided credentials
3. Executes the read-only SELECT query shown above
4. Reads the result (edition, version, clustering info)
5. Immediately closes the connection
6. Logs the detected edition in the output file

**What SQL Detection CANNOT Do:**
- Cannot modify SQL Server configuration
- Cannot create, alter, or drop databases
- Cannot create, alter, or drop tables
- Cannot modify data in any database
- Cannot create or modify users/logins
- Cannot grant or revoke permissions
- Cannot execute stored procedures
- Cannot access user data (only system metadata)

#### SQL Detection Code Snippet

Here's the actual code that performs SQL Server detection:

```powershell
function Test-SQLServerConnection {
    param(
        [string]$IPAddress,
        [hashtable]$Credentials,
        [int]$TimeoutSeconds = 5
    )
    
    try {
        # Build connection string with short timeout
        $connectionString = "Server=$IPAddress;Database=master;Connection Timeout=$TimeoutSeconds;"
        
        if ($Credentials.AuthMode -eq 'SQL') {
            $connectionString += "User Id=$($Credentials.Username);Password=$($Credentials.Password);"
        } else {
            $connectionString += "Integrated Security=true;"
        }
        
        # Create connection object
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        
        # READ-ONLY QUERY - Only retrieves system metadata
        $query = @"
SELECT 
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('IsClustered') AS IsClustered,
    SERVERPROPERTY('IsHadrEnabled') AS IsHadrEnabled,
    @@VERSION AS VersionString
"@
        
        # Execute read-only query
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $reader = $command.ExecuteReader()
        
        # Read results
        $result = @{
            Success = $true
            DatabaseType = 'SQL Server'
            Edition = ''
            Version = ''
            ProductLevel = ''
            IsClustered = $false
            IsHadrEnabled = $false
            VersionString = ''
        }
        
        if ($reader.Read()) {
            $rawEdition = $reader['Edition'].ToString()
            $result.Edition = Convert-SQLServerEdition -RawEdition $rawEdition
            $result.Version = $reader['ProductVersion'].ToString()
            $result.ProductLevel = $reader['ProductLevel'].ToString()
            $result.IsClustered = [bool]$reader['IsClustered']
            $result.IsHadrEnabled = [bool]$reader['IsHadrEnabled']
            $result.VersionString = $reader['VersionString'].ToString()
        }
        
        # Close connection immediately
        $reader.Close()
        $connection.Close()
        
        return $result
        
    } catch {
        # Return failure result - no modifications made
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
```

**Key Security Points:**
1. **Line 18-26:** The SQL query uses only `SERVERPROPERTY()` and `@@VERSION` - both are read-only system functions
2. **Line 29:** Creates a `SqlCommand` object with the read-only query
3. **Line 30:** Uses `ExecuteReader()` - designed for SELECT queries only
4. **Line 49-50:** Immediately closes reader and connection after reading results
5. **No INSERT, UPDATE, DELETE, DROP, ALTER, CREATE, TRUNCATE, or EXEC statements anywhere**

### Credential Security

The script implements secure credential handling:

**Security Features:**
- Credentials stored in memory using `SecureString`
- Plaintext passwords cleared immediately after use
- Garbage collection forced to clear memory
- No credentials written to disk or logs
- Credentials cleared on script completion

**Example:**
```powershell
# Credentials are stored securely
$global:SecureCredentialManager.StoreCredential("vCenter", $username, $password)

# Plaintext password cleared immediately
$password = $null
$sqlPassword = $null
[System.GC]::Collect()

# Credentials cleared on exit
$global:SecureCredentialManager.ClearAllCredentials()
```

### File Operations (Local Only)

All file operations are performed on the **local machine only**:

**What the Script Creates:**
- Output directory: `VMware_Export_YYYYMMDD_HHMMSS/`
- Excel files: MPA and ME templates
- CSV files: RVTools format (if requested)
- ZIP archive: Compressed CSV files
- Log file: Debug log (if enabled)
- Mapping file: Anonymization mapping (if enabled)

**What the Script Removes (Local Only):**
- Temporary CSV files after ZIP creation (if `-purgeCSV` enabled)
- Temporary directories used for anonymization

**No remote file operations** - The script does not access, modify, or delete any files on vCenter, ESXi hosts, or VMs.

### Network Security

**Connections Made:**
1. **vCenter Server** - HTTPS (port 443) or HTTP (port 80)
   - Purpose: Data collection via PowerCLI
   - Protocol: VMware vSphere API
   - Authentication: Username/password

2. **SQL Server** (optional, only if `-enableSQLDetection` enabled)
   - Purpose: Edition detection
   - Protocol: TDS (Tabular Data Stream)
   - Ports: 1433 (default), 1434, 2433, 3433
   - Authentication: Windows or SQL Authentication
   - Duration: 5 seconds maximum per connection

**No other network connections** - The script does not connect to any other systems, services, or external endpoints.

### Compliance & Audit

**Audit Trail:**
- All operations logged (if `-enableLogging` enabled)
- Connection attempts recorded
- Performance data collection tracked
- SQL detection attempts logged
- Errors and warnings captured

**Compliance:**
- Read-only operations only
- No data modification
- Secure credential handling
- Minimal permissions required
- Industry-standard approach (same as RVTools, MAP Toolkit, AWS Migration Evaluator)

### Verification

You can verify the script's read-only nature by:

1. **Review the code** - Search for any `Set-`, `New-`, `Remove-`, or `Update-` cmdlets that target vCenter objects
2. **Enable logging** - Use `-enableLogging` to see all operations performed
3. **Monitor vCenter tasks** - Check vCenter tasks during script execution (you'll see only read operations)
4. **Review permissions** - The script works with read-only vCenter accounts
5. **Test in your environment** - Run the script in your test/lab environment first to confirm no changes are made to vCenter or VMs before using in production

**Recommended Testing Approach:**
- Run the script against a test vCenter or isolated cluster
- Monitor vCenter tasks and events during execution
- Review the generated output files
- Verify that no configuration changes occurred
- Check vCenter audit logs to confirm only read operations were performed
- Once satisfied, proceed with production data collection

### Recommended Security Practices

1. **Use Read-Only Accounts**
   ```powershell
   # Create dedicated read-only service account in vCenter
   # Grant only "Read-only" role
   ```

2. **Enable SSL Validation**
   ```powershell
   # Only use -disableSSL in isolated lab environments
   # Use proper SSL certificates in production
   ```

3. **Secure Credentials**
   ```powershell
   # Avoid hardcoding passwords in scripts
   # Use credential prompts or secure credential stores
   $cred = Get-Credential
   ```

4. **Review Logs**
   ```powershell
   # Enable logging and review for any issues
   -enableLogging
   ```

5. **Limit SQL Detection**
   ```powershell
   # Only enable SQL detection when needed
   # Use least-privilege SQL accounts
   # Consider using Windows Authentication
   ```

### Summary

- **100% Read-Only** - No modifications to vCenter or SQL Server  
- **Secure** - Credentials handled securely, cleared from memory  
- **Auditable** - All operations logged (if enabled)  
- **Minimal Permissions** - Works with read-only accounts  
- **Industry Standard** - Same approach as RVTools, MAP Toolkit, AWS Migration Evaluator  
- **Transparent** - Open source, code can be reviewed  
- **Safe for Production** - Designed for production environments  

**This script is safe to run in production environments for migration assessments and capacity planning.**

---

## Version History

### Version 2.0 (Current) (https://aws.amazon.com/blogs/migration-and-modernization/accelerating-vmware-cloud-migration-with-aws-transform-and-powercli/)
- Added P95 percentile calculations for realistic peak values
- Implemented secure credential management
- Comprehensive error handling
- Optimized performance with bulk data collection
- Added infrastructure filtering
- SQL Server detection
- Added advanced filtering options
- ME (flat file), MPA, and RVTools output formats
- Anonymization support

### Version 1.0 (https://aws.amazon.com/blogs/migration-and-modernization/accelerating-migration-evaluator-discovery-for-vmware-environment/)
- Initial release
- Basic data collection


## Support

For issues, questions, or feature requests:
1. Review this README thoroughly
2. Check the Troubleshooting section
3. Enable debug logging (`-enableLogging`)
4. Contact your VMware administrator

---

**Script Version:** 2.0 
**Author:** Benoit Lotfallah  
**Last Updated:** December 16, 2025
