<#
.SYNOPSIS
    PC Check Report v2.2 - Comprehensive used-PC hardware and software audit tool.

.DESCRIPTION
    Collects hardware, storage, battery, security, Windows, network and event-log
    information and produces a self-contained HTML report.

    The tool also provides:
      - Hardware Condition score
      - Hardware Capability score
      - Usage suitability estimates
      - Buyer Verdict
      - Data confidence indicators
      - Categorized hardware/system warnings

    IMPORTANT:
      Scores are estimates. This tool does NOT perform synthetic benchmarks,
      stress tests, SMART vendor-specific diagnostics, or physical inspection.

.NOTES
    File Name  : pc-check.ps1
    Author     : Hansoy
    Copyright  : (c) 2026 Hansoy.
    License    : MIT License
    GitHub     : https://github.com/Hans930v/pc-check

    Requires:
      - Windows PowerShell 5.1+
      - Windows 10/11
      - Administrator privileges recommended
#>

# ============================================================
# CONFIGURATION
# ============================================================

 $ErrorActionPreference = "Continue"

# ============================================================
# SELF-ELEVATE & TEMPORARY EXECUTION POLICY BYPASS
# ============================================================

# Check if we are running as Administrator
 $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
 $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Check if Execution Policy is already Bypassed or Unrestricted for this process
 $policy = Get-ExecutionPolicy -Scope Process
 $isBypassed = ($policy -eq 'Bypass' -or $policy -eq 'Unrestricted')

# If running via irm | iex, $PSCommandPath is empty, and execution policy is inherently bypassed.
# We only need to force-bypass if we are running as a .ps1 file.
 $needsBypass = $false
if ($PSCommandPath -and -not $isBypassed) {
    $needsBypass = $true
}

# If we are missing Admin rights OR need Execution Bypass, relaunch the script with both.
if (-not $isAdmin -or $needsBypass) {
    if ($PSCommandPath) {
        Write-Host "Launching with Administrator privileges and ExecutionPolicy Bypass..." -ForegroundColor Yellow
        Start-Process powershell.exe `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
            -Verb RunAs
    }
    else {
        Write-Host ""
        Write-Host "Administrator privileges are required to run this tool." -ForegroundColor Yellow
        Write-Host "Please right-click PowerShell, select 'Run as Administrator'," -ForegroundColor Red
        Write-Host "and paste the one-liner command again." -ForegroundColor Red
        Start-Sleep -Seconds 5
    }

    exit
}

# ============================================================
# PATHS
# ============================================================

# Find the directory where this script is currently running from (e.g., your USB drive)
 $scriptPath = $PSCommandPath
if (-not $scriptPath) {
    $scriptPath = $MyInvocation.MyCommand.Path
}

if ($scriptPath) {
    $scriptDir = Split-Path -Parent $scriptPath
    # If the script is already inside a "PC-Diagnose" folder, just use that folder.
    # Otherwise, create a "PC-Diagnose" folder next to the script.
    if ((Split-Path -Leaf $scriptDir) -ieq "PC-Diagnose") {
        $outputDir = $scriptDir
    } else {
        $outputDir = Join-Path $scriptDir "PC-Diagnose"
    }
} else {
    # Fallback if run via one-liner (irm | iex) where $PSCommandPath is empty
    $outputDir = [Environment]::GetFolderPath("Desktop")
    if (-not $outputDir) { $outputDir = "$env:USERPROFILE\Desktop" }
    Write-Host "Running via one-liner. Saving to Desktop: $outputDir" -ForegroundColor Yellow
}

# Ensure the directory exists.
if (-not (Test-Path $outputDir)) {
    try {
        New-Item -ItemType Directory -Path $outputDir -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $outputDir = [Environment]::GetFolderPath("Desktop")
        if (-not $outputDir) { $outputDir = "$env:USERPROFILE\Desktop" }
        Write-Host "Warning: Could not create folder on USB. Saving to $outputDir instead." -ForegroundColor Yellow
    }
}

 $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Fetch Manufacturer and Model early to include in the filename
 $brand = "UnknownBrand"
 $model = "UnknownModel"
 $computerSystem = $null

try {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($computerSystem.Manufacturer) {
        $brand = $computerSystem.Manufacturer
    }
    if ($computerSystem.Model) {
        $model = $computerSystem.Model
    }
} catch {}

# Clean up brand and model for a safe filename (keeps spaces, removes slashes/colons/etc.)
 $invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''
 $regex = "[{0}]" -f [System.Text.RegularExpressions.Regex]::Escape($invalidChars)
 $brand = ($brand -replace $regex, '').Trim()
 $model = ($model -replace $regex, '').Trim()

# Fallbacks if they end up empty after cleaning
if ([string]::IsNullOrWhiteSpace($brand)) { $brand = "UnknownBrand" }
if ([string]::IsNullOrWhiteSpace($model)) { $model = "UnknownModel" }

# Example: "Dell Inc. Inspiron 5402 PC Check 2026-08-15_14-30-00.html"
 $fileName = "${brand} ${model} PC Check ${timestamp}.html"
 $htmlPath = Join-Path $outputDir $fileName

 $tempBatteryHtml = Join-Path $env:TEMP "battery-report-$timestamp.html"
 $tempBatteryXml = Join-Path $env:TEMP "battery-report-$timestamp.xml"

# ============================================================
# HELPER FUNCTIONS
# ============================================================

function Write-Step {
    param(
        [string]$Message,
        [ValidateSet("Green", "Yellow", "Red", "Cyan", "White")]
        [string]$Color = "Green"
    )

    Write-Host "$Message [DONE]" -ForegroundColor $Color
}

function Write-Check {
    param(
        [string]$Message
    )

    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
}

function ConvertTo-HtmlSafe {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-SafeValue {
    param(
        [object]$Value,
        [string]$Fallback = "Unknown"
    )

    if ($null -eq $Value) {
        return $Fallback
    }

    $text = [string]$Value

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Fallback
    }

    return $text
}

function To-HtmlTable {
    param(
        [AllowNull()]
        [object]$Data
    )

    if ($null -eq $Data) {
        return "<p class='muted'>No data available.</p>"
    }

    $array = @($Data)

    if ($array.Count -eq 0) {
        return "<p class='muted'>No data available or not applicable to this device.</p>"
    }

    try {
        $html = $array | ConvertTo-Html -Fragment

        if ($html -is [array]) {
            return ($html -join "`n")
        }

        return [string]$html
    }
    catch {
        return "<p class='muted'>Unable to format this data.</p>"
    }
}

function Get-ScoreRating {
    param(
        [int]$Score
    )

    if ($Score -ge 85) { return "Excellent" }
    elseif ($Score -ge 70) { return "Good" }
    elseif ($Score -ge 50) { return "Fair" }
    return "Poor"
}

function Get-ScoreClass {
    param(
        [int]$Score
    )

    # Keep visual thresholds aligned with Get-ScoreRating.
    if ($Score -ge 70) { return "rating-good" }
    elseif ($Score -ge 50) { return "rating-fair" }
    return "rating-poor"
}

function Get-ConfidenceRating {
    param(
        [int]$Confidence
    )

    if ($Confidence -ge 85) { return "High" }
    elseif ($Confidence -ge 65) { return "Medium" }
    return "Low"
}

function Get-Suitability {
    param(
        [string]$Name,
        [int]$Score,
        [string]$Reason
    )

    $Score = [Math]::Max(0, [Math]::Min(100, $Score))

    [PSCustomObject]@{
        Profile = $Name
        Score   = "$Score/100"
        Rating  = Get-ScoreRating $Score
        Reason  = $Reason
    }
}

function Add-Issue {
    param(
        [System.Collections.ArrayList]$List,
        [string]$Category,
        [string]$Severity,
        [string]$Message
    )

    [void]$List.Add(
        [PSCustomObject]@{
            Category = $Category
            Severity = $Severity
            Message  = $Message
        }
    )
}

# ============================================================
# START
# ============================================================

Clear-Host

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "          PC CHECK REPORT v2.2" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Starting PC Check..." -ForegroundColor Cyan
Write-Host "Report will be saved to:" -ForegroundColor DarkGray
Write-Host $htmlPath -ForegroundColor Gray
Write-Host ""

# ============================================================
# DATA COLLECTION
# ============================================================

 $collectionWarnings = New-Object System.Collections.ArrayList

# ------------------------------------------------------------
# CPU
# ------------------------------------------------------------

Write-Check "Collecting CPU information..."

 $cpu = @()

try {
    $cpu = @(
        Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop |
        Select-Object `
            Name,
            Manufacturer,
            NumberOfCores,
            NumberOfLogicalProcessors,
            @{N = "MaxClock(GHz)"; E = {
                if ($_.MaxClockSpeed) {
                    [math]::Round($_.MaxClockSpeed / 1000, 2)
                }
                else {
                    "Unknown"
                }
            }
        }
    )
}
catch {
    [void]$collectionWarnings.Add("CPU information could not be retrieved.")
}

 $cpuCores = 0
 $cpuThreads = 0

if ($cpu.Count -gt 0) {
    $cpuCores = [int](($cpu | Measure-Object -Property NumberOfCores -Sum).Sum)
    $cpuThreads = [int](($cpu | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum)
}

Write-Step "CPU information"

# ------------------------------------------------------------
# SYSTEM
# ------------------------------------------------------------

Write-Check "Collecting system information..."

 $os = $null

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
}
catch {
    [void]$collectionWarnings.Add("Operating system information could not be retrieved.")
}

# $computerSystem was already retrieved in the PATHS section for the filename!
if (-not $computerSystem) {
    [void]$collectionWarnings.Add("Computer system information could not be retrieved.")
}

 $sysInfo = @()

if ($os -and $computerSystem) {

    $installDate = "Unknown"

    try {
        if ($os.InstallDate) {
            $installDate = $os.InstallDate.ToString("yyyy-MM-dd")
        }
    }
    catch {}

    $sysInfo = @(
        [PSCustomObject]@{
            Property = "Manufacturer"
            Value    = Get-SafeValue $computerSystem.Manufacturer
        }

        [PSCustomObject]@{
            Property = "Model"
            Value    = Get-SafeValue $computerSystem.Model
        }

        [PSCustomObject]@{
            Property = "Operating System"
            Value    = Get-SafeValue $os.Caption
        }

        [PSCustomObject]@{
            Property = "OS Version"
            Value    = Get-SafeValue $os.Version
        }

        [PSCustomObject]@{
            Property = "Build"
            Value    = Get-SafeValue $os.BuildNumber
        }

        [PSCustomObject]@{
            Property = "Original Install Date"
            Value    = $installDate
        }
    )
}

 $lastBoot = $null
 $uptime = $null
 $uptimeStr = "Unknown"

if ($os) {
    try {
        $lastBoot = $os.LastBootUpTime

        if ($lastBoot) {
            $uptime = (Get-Date) - $lastBoot

            $uptimeStr = "{0}d {1}h {2}m (since {3})" -f `
                $uptime.Days,
            $uptime.Hours,
            $uptime.Minutes,
            $lastBoot
        }
    }
    catch {}
}

Write-Step "System information"

# ------------------------------------------------------------
# RAM
# ------------------------------------------------------------

Write-Check "Collecting RAM information..."

 $ramObjects = @()

try {
    $ramObjects = @(
        Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop
    )
}
catch {
    [void]$collectionWarnings.Add("RAM information could not be retrieved.")
}

 $totalRamBytes = 0

if ($ramObjects.Count -gt 0) {
    $totalRamBytes = ($ramObjects | Measure-Object -Property Capacity -Sum).Sum
}

 $totalRamGB = 0

if ($totalRamBytes -gt 0) {
    $totalRamGB = [math]::Round($totalRamBytes / 1GB, 1)
}

 $totalRamStr = if ($totalRamGB -gt 0) {
    "$totalRamGB GB"
}
else {
    "Unknown"
}

 $ram = @()

if ($ramObjects.Count -gt 0) {
    $ram = @(
        $ramObjects | Select-Object `
            BankLabel,
            DeviceLocator,
            Manufacturer,
            PartNumber,
            @{N = "Capacity(GB)"; E = {
                if ($_.Capacity) {
                    [math]::Round($_.Capacity / 1GB, 1)
                }
                else {
                    "Unknown"
                }
            }
        },
        Speed
    )
}

 $ramSlotCount = $ramObjects.Count

Write-Step "RAM information"

# ------------------------------------------------------------
# BATTERY
# ------------------------------------------------------------

Write-Check "Generating battery report..."

 $batteryHtml = $null
 $batteryHealthStr = "Not applicable / Unknown"
 $batteryHealthWarning = $false
 $batteryHealthPct = $null
 $batteryPresent = $false

try {
    $batteryDevices = @(Get-CimInstance Win32_Battery -ErrorAction Stop)

    if ($batteryDevices.Count -gt 0) {
        $batteryPresent = $true
    }
}
catch {}

try {
    & powercfg.exe /batteryreport /output "$tempBatteryHtml" | Out-Null
}
catch {
    [void]$collectionWarnings.Add("HTML battery report could not be generated.")
}

try {
    & powercfg.exe /batteryreport /output "$tempBatteryXml" /xml | Out-Null
}
catch {
    [void]$collectionWarnings.Add("XML battery report could not be generated.")
}

if (Test-Path $tempBatteryHtml) {

    try {
        $batteryHtml = Get-Content $tempBatteryHtml -Raw -ErrorAction Stop

        Remove-Item $tempBatteryHtml -Force -ErrorAction SilentlyContinue
    }
    catch {
        $batteryHtml = $null
    }
}

if (Test-Path $tempBatteryXml) {

    try {

        [xml]$battXml = Get-Content $tempBatteryXml -Raw -ErrorAction Stop

        $batteryNodes = @(
            $battXml.BatteryReport.Batteries.Battery
        )

        if ($batteryNodes.Count -gt 0) {

            $designCap = 0
            $fullCap = 0

            try {
                $designCap = [double]$batteryNodes[0].DesignCapacity
                $fullCap = [double]$batteryNodes[0].FullChargeCapacity
            }
            catch {}

            if ($designCap -gt 0 -and $fullCap -gt 0) {

                $batteryPresent = $true

                $batteryHealthPct = [math]::Round(
                    ($fullCap / $designCap) * 100,
                    1
                )

                $designWh = [math]::Round($designCap / 1000, 1)
                $fullWh = [math]::Round($fullCap / 1000, 1)

                $batteryHealthStr = "$batteryHealthPct% " +
                "(Design: $designWh Wh, Current Full: $fullWh Wh)"

                if ($batteryHealthPct -lt 70) {
                    $batteryHealthWarning = $true
                }
            }
        }
    }
    catch {
        $batteryHealthStr = "Could not parse battery health data."
    }

    Remove-Item $tempBatteryXml -Force -ErrorAction SilentlyContinue
}

if (-not $batteryPresent) {
    $batteryHealthStr = "N/A - No battery detected"
    $batteryHealthPct = $null
}

Write-Step "Battery information"

# ------------------------------------------------------------
# STORAGE
# ------------------------------------------------------------

Write-Check "Collecting storage information..."

 $storage = @()

try {

    $storage = @(
        Get-PhysicalDisk -ErrorAction Stop |
        Select-Object `
            FriendlyName,
            DeviceId,
            MediaType,
            BusType,
            OperationalStatus,
            @{N = "Size(GB)"; E = {
                if ($_.Size) {
                    [math]::Round($_.Size / 1GB, 1)
                }
                else {
                    "Unknown"
                }
            }
        }
    )
}
catch {
    [void]$collectionWarnings.Add("Physical storage information could not be retrieved.")
}

 $totalStorage = 0

foreach ($s in $storage) {

    $size = $s.'Size(GB)'

    if ($size -is [double] -or $size -is [int] -or $size -is [decimal]) {
        $totalStorage += $size
    }
}

 $totalStorageStr = if ($totalStorage -gt 0) {
    "$([math]::Round($totalStorage, 1)) GB"
}
else {
    "Unknown"
}

# ------------------------------------------------------------
# STORAGE HEALTH / SMART TELEMETRY
# ------------------------------------------------------------

# Deliberately do not call Get-StorageReliabilityCounter or infer SSD health.
# Windows/controller support is inconsistent, so unavailable counters must not
# affect the condition score or create false health warnings.

Write-Step "Storage inventory (SMART health not assessed)"

# ------------------------------------------------------------
# VOLUMES
# ------------------------------------------------------------

Write-Check "Collecting volume information..."

 $volumes = @()

try {

    $volumes = @(
        Get-Volume -ErrorAction Stop |
        Where-Object { $_.DriveLetter } |
        Select-Object `
            DriveLetter,
            FileSystem,
            @{N = "Free(GB)"; E = {
                if ($null -ne $_.SizeRemaining) {
                    [math]::Round($_.SizeRemaining / 1GB, 1)
                }
                else {
                    "Unknown"
                }
            }
        },
        @{N = "Total(GB)"; E = {
                if ($null -ne $_.Size) {
                    [math]::Round($_.Size / 1GB, 1)
                }
                else {
                    "Unknown"
                }
            }
        }
    )
}
catch {
    [void]$collectionWarnings.Add("Volume information could not be retrieved.")
}

 $totalFreeGB = 0
 $totalVolGB = 0
foreach ($v in $volumes) {
    if ($v.'Free(GB)' -is [double] -or $v.'Free(GB)' -is [int]) { $totalFreeGB += $v.'Free(GB)' }
    if ($v.'Total(GB)' -is [double] -or $v.'Total(GB)' -is [int]) { $totalVolGB += $v.'Total(GB)' }
}
 $totalFreeStr = if ($totalFreeGB -gt 0) { "$([math]::Round($totalFreeGB,1)) GB" } else { "Unknown" }
 $totalVolSpaceStr = if ($totalVolGB -gt 0) { "$([math]::Round($totalVolGB,1)) GB" } else { "Unknown" }

# ------------------------------------------------------------
# GPU
# ------------------------------------------------------------

Write-Check "Collecting GPU and display information..."

 $gpu = @()

try {

    $videoControllers = @(
        Get-CimInstance Win32_VideoController -ErrorAction Stop
    )

    foreach ($video in $videoControllers) {

        $name = Get-SafeValue $video.Name
        $vramGB = "Unknown"
        $vendor = "Unknown"

        if ($video.AdapterCompatibility) {
            $vendor = $video.AdapterCompatibility
        }

        try {

            $regBase =
            "HKLM:\SYSTEM\CurrentControlSet\Control\Class\" +
            "{4d36e968-e325-11ce-bfc1-08002be10318}"

            $match = Get-ChildItem $regBase -ErrorAction SilentlyContinue |
            ForEach-Object {
                Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            } |
            Where-Object {
                $_.DriverDesc -and
                ($_.DriverDesc.Trim() -ieq $name.Trim()) -and
                $_."HardwareInformation.qwMemorySize"
            } |
            Select-Object -First 1

            if ($match) {

                $memoryBytes = [double]$match."HardwareInformation.qwMemorySize"

                if ($memoryBytes -gt 0) {
                    $vramGB = [math]::Round($memoryBytes / 1GB, 1)
                }
            }
        }
        catch {}

        $gpu += [PSCustomObject]@{
            Name           = $name
            Manufacturer   = $vendor
            DriverVersion  = Get-SafeValue $video.DriverVersion
            'VRAM(GB)'     = $vramGB
            VideoProcessor = Get-SafeValue $video.VideoProcessor
            DriverDate     = Get-SafeValue $video.DriverDate
        }
    }
}
catch {
    [void]$collectionWarnings.Add("GPU information could not be retrieved.")
}

# Use the maximum reported VRAM on a single adapter. VRAM across multiple GPUs
# is not generally a single shared pool and must not be added for suitability.
 $totalVram = 0
 $knownGpuCount = 0

foreach ($g in $gpu) {
    if ($g.'VRAM(GB)' -is [double] -or
        $g.'VRAM(GB)' -is [int] -or
        $g.'VRAM(GB)' -is [decimal]) {

        if ([double]$g.'VRAM(GB)' -gt 0) {
            $knownGpuCount++
            if ([double]$g.'VRAM(GB)' -gt $totalVram) {
                $totalVram = [double]$g.'VRAM(GB)'
            }
        }
    }
}

 $totalVramGB = if ($totalVram -gt 0) {
    [math]::Round($totalVram, 1)
}
else {
    0
}

 $totalVramStr = if ($totalVramGB -gt 0) {
    "$totalVramGB GB"
}
else {
    "Unknown"
}

 $displays = @()

try {

    $displays = @(
        Get-CimInstance Win32_VideoController -ErrorAction Stop |
        Select-Object `
            Name,
            @{N = "Resolution"; E = {
                if ($_.CurrentHorizontalResolution -and
                    $_.CurrentVerticalResolution) {

                    "$($_.CurrentHorizontalResolution) x $($_.CurrentVerticalResolution)"
                }
                else {
                    "Unknown"
                }
            }
        },
        @{N = "RefreshRate(Hz)"; E = {
                if ($_.CurrentRefreshRate) {
                    $_.CurrentRefreshRate
                }
                else {
                    "Unknown"
                }
            }
        }
    )
}
catch {}

Write-Step "GPU and display information"

# ------------------------------------------------------------
# BIOS
# ------------------------------------------------------------

Write-Check "Collecting BIOS information..."

 $bios = @()

try {

    $biosObj = Get-CimInstance Win32_BIOS -ErrorAction Stop

    $biosReleaseDate = "Unknown"

    if ($biosObj.ReleaseDate) {

        try {
            $biosReleaseDate = $biosObj.ReleaseDate.ToString("yyyy-MM-dd")
        }
        catch {}
    }

    $bios = @(
        [PSCustomObject]@{
            Manufacturer = Get-SafeValue $biosObj.Manufacturer
            Version      = Get-SafeValue $biosObj.SMBIOSBIOSVersion
            ReleaseDate  = $biosReleaseDate
            SerialNumber = Get-SafeValue $biosObj.SerialNumber
        }
    )
}
catch {
    [void]$collectionWarnings.Add("BIOS information could not be retrieved.")
}

Write-Step "BIOS information"

# ------------------------------------------------------------
# WINDOWS ACTIVATION
# ------------------------------------------------------------

Write-Check "Checking Windows activation..."

 $activation = @()

try {

    $activation = @(
        & cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /xpr 2>&1 |
        ForEach-Object {
            [string]$_
        }
    )
}
catch {
    $activation = @("Unable to query Windows activation status.")
}

Write-Step "Windows activation"

# ------------------------------------------------------------
# WINDOWS UPDATE
# ------------------------------------------------------------

Write-Check "Checking Windows Update status..."

 $updates = @()
 $lastUpdateDate = $null
 $daysSinceUpdate = $null
 $updateWarning = $false

try {

    $updates = @(
        Get-HotFix -ErrorAction Stop |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 5 HotFixID, Description, InstalledOn
    )

    if ($updates.Count -gt 0) {
        $lastUpdateDate = $updates[0].InstalledOn

        if ($lastUpdateDate) {

            $daysSinceUpdate = (
                New-TimeSpan `
                    -Start ([datetime]$lastUpdateDate) `
                    -End (Get-Date)
            ).Days

            if ($daysSinceUpdate -gt 90) {
                $updateWarning = $true
            }
        }
    }
}
catch {
    [void]$collectionWarnings.Add("Windows Update history could not be retrieved.")
}

if ($null -eq $daysSinceUpdate) {
    $daysSinceUpdate = "Unknown"
}

Write-Step "Windows Update status"

# ------------------------------------------------------------
# STARTUP PROGRAMS
# ------------------------------------------------------------

Write-Check "Collecting startup programs..."

 $startupPrograms = @()

try {

    $startupPrograms = @(
        Get-CimInstance Win32_StartupCommand -ErrorAction Stop |
        Select-Object Name, Command, Location
    )
}
catch {
    [void]$collectionWarnings.Add("Startup programs could not be retrieved.")
}

 $startupCount = $startupPrograms.Count

Write-Step "Startup programs"

# ------------------------------------------------------------
# WINDOWS DEFENDER
# ------------------------------------------------------------

Write-Check "Checking antivirus status..."

 $avStatus = $null

try {

    $mp = Get-MpComputerStatus -ErrorAction Stop

    $avStatus = [PSCustomObject]@{
        'Real-Time Protection' = $mp.RealTimeProtectionEnabled
        'Antivirus Enabled'    = $mp.AntivirusEnabled
        'Signature Age (days)' = $mp.AntivirusSignatureAge
        'Last Quick Scan'      = $mp.QuickScanEndTime
        'Last Full Scan'       = $mp.FullScanEndTime
    }
}
catch {
    [void]$collectionWarnings.Add("Microsoft Defender status could not be retrieved.")
}

Write-Step "Antivirus status"

# ------------------------------------------------------------
# TPM
# ------------------------------------------------------------

Write-Check "Checking TPM status..."

 $tpm = $null

try {

    $tpmInfo = Get-Tpm -ErrorAction Stop

    $tpm = [PSCustomObject]@{
        'TPM Present' = $tpmInfo.TpmPresent
        'TPM Ready'   = $tpmInfo.TpmReady
        'TPM Enabled' = $tpmInfo.TpmEnabled
        'TPM Version' = Get-SafeValue $tpmInfo.ManufacturerVersion
        Manufacturer  = Get-SafeValue $tpmInfo.ManufacturerIdTxt
    }
}
catch {
    [void]$collectionWarnings.Add("TPM information could not be retrieved.")
}

Write-Step "TPM status"

# ------------------------------------------------------------
# NETWORK
# ------------------------------------------------------------

Write-Check "Collecting network adapter information..."

 $netAdapters = @()

try {

    $netAdapters = @(
        Get-NetAdapter -ErrorAction Stop |
        Select-Object `
            Name,
            InterfaceDescription,
            Status,
            LinkSpeed,
            MacAddress
    )
}
catch {
    [void]$collectionWarnings.Add("Network adapter information could not be retrieved.")
}

Write-Step "Network adapters"

# ============================================================
# EVENT LOG ANALYSIS
# ============================================================

Write-Check "Collecting and categorizing System event logs..."

 $errorEvents = @()

try {

    $errorEvents = @(
        Get-WinEvent -FilterHashtable @{
            LogName   = "System"
            Level     = 1, 2
            StartTime = (Get-Date).AddDays(-30)
        } -ErrorAction Stop
    )
}
catch {
    [void]$collectionWarnings.Add(
        "System event logs could not be fully retrieved."
    )
}

 $criticals = @(
    $errorEvents | Where-Object { $_.Level -eq 1 }
)

 $criticalCount = $criticals.Count
 $errorCount = $errorEvents.Count

# Group by provider + event ID + level. This is used for the bottom summary,
# so repeated copies of the same event do not look like separate fault types.
 $eventGroups = @(
    $errorEvents |
    Group-Object { "{0}|{1}|{2}" -f $_.ProviderName, $_.Id, $_.Level } |
    Sort-Object Count -Descending
)

 $wheaErrors = @(
    $errorEvents |
    Where-Object {
        $_.ProviderName -match "WHEA|Hal"
    }
)

 $diskErrors = @(
    $errorEvents |
    Where-Object {
        $_.ProviderName -match "disk|volmgr|stornvme|storahci"
    }
)

 $driverErrors = @(
    $errorEvents |
    Where-Object {
        $_.ProviderName -match "nvlddmkm|amdkmdag|igfx|Display|video"
    }
)

 $eventWarning = (
    $criticalCount -gt 0 -or
    $errorCount -gt 20
)

Write-Step "Event logs"

# ============================================================
# ISSUE ANALYSIS
# ============================================================

 $issues = New-Object System.Collections.ArrayList

# Consolidate event-log findings into one issue so overlapping categories do not
# inflate the issue count. Specific event patterns and occurrences are detailed
# in the grouped summary near the bottom of the report.
if ($eventGroups.Count -gt 0) {
    if ($wheaErrors.Count -ge 5) {
        $eventLogSeverity = "High"
    }
    elseif ($criticalCount -gt 0 -or $wheaErrors.Count -gt 0 -or $driverErrors.Count -gt 0 -or $errorCount -gt 20) {
        $eventLogSeverity = "Medium"
    }
    else {
        $eventLogSeverity = "Low"
    }

    $eventLogMessage = "$errorCount Critical/Error event record(s) across $($eventGroups.Count) distinct provider/ID/level patterns. Category matches may overlap; review the grouped details rather than treating every record as a separate fault."
    Add-Issue `
        -List $issues `
        -Category "System Logs" `
        -Severity $eventLogSeverity `
        -Message $eventLogMessage
}

if ($batteryHealthWarning) {

    Add-Issue `
        -List $issues `
        -Category "Battery" `
        -Severity "Medium" `
        -Message "Battery health is below 70% of its original design capacity."
}

if ($updateWarning) {

    Add-Issue `
        -List $issues `
        -Category "Windows" `
        -Severity "Low" `
        -Message "The most recent installed Windows update is more than 90 days old."
}

if ($avStatus) {

    if ($avStatus.'Real-Time Protection' -eq $false) {

        Add-Issue `
            -List $issues `
            -Category "Security" `
            -Severity "Medium" `
            -Message "Microsoft Defender real-time protection is disabled."
    }

    if ($avStatus.'Antivirus Enabled' -eq $false) {

        Add-Issue `
            -List $issues `
            -Category "Security" `
            -Severity "Medium" `
            -Message "Windows reports that antivirus protection is disabled."
    }
}

if ($tpm) {

    if ($tpm.'TPM Present' -eq $false) {

        Add-Issue `
            -List $issues `
            -Category "Security" `
            -Severity "Low" `
            -Message "No TPM was detected."
    }
}

# ============================================================
# HARDWARE CONDITION SCORE
# ============================================================

Write-Check "Calculating Hardware Condition..."

 $condScore = 100
 $condReasons = New-Object System.Collections.ArrayList

# Storage SMART/wear is intentionally excluded because Windows does not expose
# reliable counters for every drive/controller. Storage is inventoried below.

if ($wheaErrors.Count -ge 5) {
    $condScore -= 15
    [void]$condReasons.Add(
        "Repeated WHEA/HAL events were recorded. Investigate the event details; this is not proof of a specific failed component."
    )
}
elseif ($wheaErrors.Count -ge 3) {
    $condScore -= 8
    [void]$condReasons.Add(
        "Multiple WHEA/HAL events were recorded. Review timestamps and event details."
    )
}
elseif ($wheaErrors.Count -gt 0) {
    [void]$condReasons.Add(
        "WHEA/HAL event(s) exist and should be reviewed, but isolated log entries do not prove a hardware fault."
    )
}

if ($batteryHealthWarning) {
    $condScore -= 10
    [void]$condReasons.Add(
        "Battery health is below 70% of its original design capacity."
    )
}

# Generic critical System events can result from shutdowns, software, or power
# interruptions. Report them, but do not automatically treat them as hardware damage.
if ($criticalCount -gt 0) {
    [void]$condReasons.Add(
        "$criticalCount critical System event(s) were recorded; inspect the grouped event summary before drawing conclusions."
    )
}

if ($driverErrors.Count -ge 10) {
    $condScore -= 3
    [void]$condReasons.Add(
        "Repeated graphics/display driver errors were detected. Check whether they recur during normal use."
    )
}
elseif ($driverErrors.Count -gt 0) {
    [void]$condReasons.Add(
        "Graphics/display driver error events were detected; review the details, as these do not automatically indicate hardware failure."
    )
}

# Stale Windows update history is a software-maintenance finding, not a direct
# measure of physical hardware condition, so it is not deducted from this score.
if ($updateWarning) {
    [void]$condReasons.Add(
        "Windows update history is more than 90 days old; review update status separately from hardware condition."
    )
}

 $condScore = [Math]::Max(0, [Math]::Min(100, $condScore))

if ($condReasons.Count -eq 0) {
    [void]$condReasons.Add(
        "No major issues were detected by the limited automated checks. This does not replace physical inspection or stress testing."
    )
}

 $condRating = Get-ScoreRating $condScore

 $conditionConfidence = 100

if ($storage.Count -eq 0) {
    $conditionConfidence -= 20
}

if ($cpu.Count -eq 0) {
    $conditionConfidence -= 10
}

if ($ram.Count -eq 0) {
    $conditionConfidence -= 10
}

if ($null -eq $os) {
    $conditionConfidence -= 10
}

if ($errorEvents.Count -eq 0 -and $collectionWarnings.Count -gt 0) {
    $conditionConfidence -= 10
}

 $conditionConfidence = [Math]::Max(
    0,
    [Math]::Min(100, $conditionConfidence)
)

 $conditionConfidenceRating = Get-ConfidenceRating $conditionConfidence

Write-Step "Hardware Condition"

# ============================================================
# HARDWARE CAPABILITY SCORE
# ============================================================

Write-Check "Calculating Hardware Capability..."

 $perfScore = 100
 $perfReasons = New-Object System.Collections.ArrayList

if ($totalRamGB -gt 0) {
    if ($totalRamGB -lt 4) {
        $perfScore -= 40
        [void]$perfReasons.Add("Very low system RAM (<4 GB).")
    }
    elseif ($totalRamGB -lt 8) {
        $perfScore -= 30
        [void]$perfReasons.Add("Low system RAM (<8 GB).")
    }
    elseif ($totalRamGB -lt 16) {
        $perfScore -= 10
        [void]$perfReasons.Add("Moderate system RAM (8-15 GB).")
    }
}
else {
    [void]$perfReasons.Add("RAM capacity could not be determined; no RAM deduction was applied.")
}

if ($cpuCores -gt 0) {
    if ($cpuCores -lt 2) {
        $perfScore -= 30
        [void]$perfReasons.Add("Very low CPU core count.")
    }
    elseif ($cpuCores -lt 4) {
        $perfScore -= 20
        [void]$perfReasons.Add("Low CPU core count (<4).")
    }
    elseif ($cpuCores -lt 6) {
        $perfScore -= 5
        [void]$perfReasons.Add("Moderate CPU core count.")
    }
}
else {
    [void]$perfReasons.Add("CPU core count could not be determined; no CPU deduction was applied.")
}

if ($knownGpuCount -eq 0) {

    [void]$perfReasons.Add(
        "Dedicated GPU VRAM could not be determined."
    )
}
elseif ($totalVramGB -lt 2) {

    $perfScore -= 20

    [void]$perfReasons.Add(
        "Very limited reported GPU memory."
    )
}
elseif ($totalVramGB -lt 4) {

    $perfScore -= 10

    [void]$perfReasons.Add(
        "Limited reported GPU memory (<4 GB)."
    )
}

 $hasHdd = @(
    $storage |
    Where-Object {
        $_.MediaType -eq "HDD"
    }
).Count -gt 0

 $hasSsd = @(
    $storage |
    Where-Object {
        $_.MediaType -eq "SSD"
    }
).Count -gt 0

if ($storage.Count -eq 0) {
    [void]$perfReasons.Add("Storage devices could not be inventoried; no storage-type deduction was applied.")
}
elseif ($hasHdd -and -not $hasSsd) {
    $perfScore -= 15
    [void]$perfReasons.Add("System storage appears to consist of HDD storage.")
}
elseif (-not $hasHdd -and -not $hasSsd) {
    [void]$perfReasons.Add("Storage media type was not identified; no storage-type deduction was applied.")
}

 $perfScore = [Math]::Max(0, [Math]::Min(100, $perfScore))

if ($perfReasons.Count -eq 0) {

    [void]$perfReasons.Add(
        "Hardware specifications appear balanced for general use."
    )
}

 $perfRating = Get-ScoreRating $perfScore

 $capabilityConfidence = 100

if ($cpuCores -eq 0) {
    $capabilityConfidence -= 25
}

if ($totalRamGB -eq 0) {
    $capabilityConfidence -= 20
}

if ($knownGpuCount -eq 0) {
    # Missing GPU-memory data can materially affect gaming, CAD and AI estimates.
    $capabilityConfidence -= 25
}

if ($storage.Count -eq 0) {
    $capabilityConfidence -= 10
}
elseif (-not $hasSsd -and -not $hasHdd) {
    # Drive inventory may be available even when the media type is not identified.
    $capabilityConfidence -= 10
}

 $capabilityConfidence = [Math]::Max(
    0,
    [Math]::Min(100, $capabilityConfidence)
)

 $capabilityConfidenceRating = Get-ConfidenceRating $capabilityConfidence

Write-Step "Hardware Capability"

# ============================================================
# USAGE SUITABILITY
# ============================================================

Write-Check "Calculating usage suitability..."

 $usageScores = @()

 $gamingScore = $perfScore
 $gamingReasons = @()

if ($knownGpuCount -eq 0) {
    $gamingReasons += "GPU memory could not be determined; no VRAM adjustment was applied."
}
elseif ($totalVramGB -ge 8) {
    $gamingScore += 10
    $gamingReasons += "At least 8 GB reported on one GPU adapter."
}
elseif ($totalVramGB -lt 4) {
    $gamingScore -= 10
    $gamingReasons += "Less than 4 GB reported GPU memory on the largest detected adapter."
}
else {
    $gamingReasons += "GPU memory may be adequate for lighter gaming; actual GPU performance is not benchmarked."
}

if ($cpuCores -ge 6) {
    $gamingScore += 5
}

 $gamingScore = [Math]::Max(0, [Math]::Min(100, $gamingScore))

 $engScore = $perfScore
 $engReasons = @()

if ($totalRamGB -ge 32) {
    $engScore += 10
    $engReasons += "32+ GB RAM is beneficial for heavier projects."
}
elseif ($totalRamGB -ge 16) {
    $engScore += 5
    $engReasons += "16+ GB RAM is suitable for many workloads."
}
elseif ($totalRamGB -gt 0) {
    $engScore -= 5
    $engReasons += "Less than 16 GB RAM may limit larger projects."
}
else {
    $engReasons += "RAM capacity is unavailable; no RAM adjustment was applied."
}

if ($cpuCores -ge 8) {
    $engScore += 5
}

 $engScore = [Math]::Max(0, [Math]::Min(100, $engScore))

 $progScore = $perfScore
 $progReasons = @()

if ($totalRamGB -ge 16) {
    $progScore += 5
    $progReasons += "16+ GB RAM is favorable for development environments."
}

if ($hasSsd) {
    $progScore += 5
    $progReasons += "SSD storage is present."
}
elseif ($hasHdd) {
    $progScore -= 10
    $progReasons += "HDD storage may slow builds and application startup."
}

 $progScore = [Math]::Max(0, [Math]::Min(100, $progScore))

 $contentScore = $perfScore
 $contentReasons = @()

if ($cpuThreads -ge 16) {
    $contentScore += 10
    $contentReasons += "High logical processor count."
}
elseif ($cpuThreads -ge 8) {
    $contentScore += 5
    $contentReasons += "Adequate logical processor count."
}
elseif ($cpuThreads -gt 0) {
    $contentReasons += "Lower thread count may limit heavier editing workloads."
}
else {
    $contentReasons += "Logical processor count is unavailable; no thread-count conclusion was applied."
}

if ($totalRamGB -ge 32) {
    $contentScore += 5
    $contentReasons += "32+ GB RAM is favorable."
}

 $contentScore = [Math]::Max(0, [Math]::Min(100, $contentScore))

 $aiScore = 30
 $aiReasons = @()

if ($knownGpuCount -eq 0) {
    $aiScore = 30
    $aiReasons += "GPU memory could not be determined; this is a low-confidence baseline, not a measured AI capability score."
}
elseif ($totalVramGB -ge 16) {
    $aiScore = 90
    $aiReasons += "16+ GB reported on one GPU adapter."
}
elseif ($totalVramGB -ge 12) {
    $aiScore = 80
    $aiReasons += "12+ GB reported on one GPU adapter."
}
elseif ($totalVramGB -ge 8) {
    $aiScore = 70
    $aiReasons += "8+ GB reported on one GPU adapter."
}
elseif ($totalVramGB -ge 6) {
    $aiScore = 55
    $aiReasons += "6+ GB reported on one GPU adapter."
}
elseif ($totalVramGB -ge 4) {
    $aiScore = 40
    $aiReasons += "4+ GB reported on one GPU adapter."
}
else {
    $aiScore = 20
    $aiReasons += "Less than 4 GB reported GPU memory on the largest detected adapter."
}

if ($totalRamGB -ge 32) {

    $aiScore += 5
    $aiReasons += "32+ GB system RAM."
}
elseif ($totalRamGB -gt 0 -and $totalRamGB -lt 16) {
    $aiScore -= 5
    $aiReasons += "Less than 16 GB system RAM."
}
elseif ($totalRamGB -eq 0) {
    $aiReasons += "System RAM capacity is unavailable; no RAM adjustment was applied."
}

 $aiScore = [Math]::Max(0, [Math]::Min(100, $aiScore))

 $bizScore = $condScore
 $bizReasons = @()

if ($totalRamGB -ge 8) {
    $bizScore += 5
    $bizReasons += "At least 8 GB RAM."
}
elseif ($totalRamGB -gt 0) {
    $bizScore -= 10
    $bizReasons += "Less than 8 GB RAM."
}
else {
    $bizReasons += "RAM capacity is unavailable; no RAM adjustment was applied."
}

if ($batteryHealthWarning) {
    $bizScore -= 5
    $bizReasons += "Battery degradation detected."
}

 $bizScore = [Math]::Max(0, [Math]::Min(100, $bizScore))

 $basicScore = 60
 $basicReasons = @()

if ($totalRamGB -gt 0) {
    if ($totalRamGB -ge 16) {
        $basicScore += 20
        $basicReasons += "16+ GB RAM."
    }
    elseif ($totalRamGB -ge 8) {
        $basicScore += 15
        $basicReasons += "8+ GB RAM."
    }
    elseif ($totalRamGB -ge 4) {
        $basicScore += 5
        $basicReasons += "4+ GB RAM."
    }
    else {
        $basicScore -= 20
        $basicReasons += "Very limited RAM."
    }
}
else {
    $basicReasons += "RAM capacity is unavailable; no RAM adjustment was applied."
}

if ($hasSsd) {

    $basicScore += 10
    $basicReasons += "SSD storage detected."
}
elseif ($hasHdd) {

    $basicScore -= 10
    $basicReasons += "HDD storage detected."
}

if ($cpuCores -ge 4) {
    $basicScore += 5
}
elseif ($cpuCores -gt 0 -and $cpuCores -lt 2) {
    $basicScore -= 10
}
elseif ($cpuCores -eq 0) {
    $basicReasons += "CPU core count is unavailable; no CPU adjustment was applied."
}

 $basicScore = [Math]::Max(0, [Math]::Min(100, $basicScore))

# ============================================================
# SORTED BY MOST COMMON USER
# ============================================================

 $usageScores += Get-Suitability `
    "Everyday Use" `
    $basicScore `
    (($basicReasons -join " ") + " This is a general capability estimate.")

 $usageScores += Get-Suitability `
    "Business / Office" `
    $bizScore `
    (($bizReasons -join " ") + " Office application licensing still requires manual verification.")

 $usageScores += Get-Suitability `
    "Programming" `
    $progScore `
    (($progReasons -join " ") + " Compiler and IDE performance will vary by workload.")

 $usageScores += Get-Suitability `
    "Video Editing" `
    $contentScore `
    (($contentReasons -join " ") + " Codec support and GPU acceleration are not benchmarked.")

 $usageScores += Get-Suitability `
    "Gaming" `
    $gamingScore `
    (($gamingReasons -join " ") + " This is not an FPS benchmark.")

 $usageScores += Get-Suitability `
    "Engineering / CAD" `
    $engScore `
    (($engReasons -join " ") + " Actual CAD performance depends heavily on the specific application.")

 $usageScores += Get-Suitability `
    "Local AI / ML" `
    $aiScore `
    (($aiReasons -join " ") + " Actual AI compatibility depends on GPU architecture, drivers, framework support, and model size.")

Write-Step "Usage suitability"

# ============================================================
# BUYER VERDICT
# ============================================================

 $highIssues = @(
    $issues | Where-Object Severity -eq "High"
)

 $mediumIssues = @(
    $issues | Where-Object Severity -eq "Medium"
)

 $overallScore = [math]::Round(
    ($condScore * 0.60) +
    ($perfScore * 0.40)
)

if ($highIssues.Count -gt 0) {
    $buyerVerdict = "INVESTIGATE BEFORE BUYING"
    $buyerClass = "verdict-danger"
    $buyerExplanation = "Recurring potentially significant findings were detected. Review the grouped event details and verify the hardware before purchasing."
}
elseif ($condScore -lt 60) {
    $buyerVerdict = "CAUTION"
    $buyerClass = "verdict-warning"
    $buyerExplanation = "The automated condition indicators are concerning. Investigate the findings and perform physical checks before purchasing."
}
elseif ($perfScore -lt 35) {
    $buyerVerdict = "LIMITED CAPABILITY"
    $buyerClass = "verdict-neutral"
    $buyerExplanation = "No strong condition warning necessarily follows from this score, but the detected hardware has limited estimated capability. Suitability depends on your intended workload."
}
elseif ($mediumIssues.Count -gt 2) {
    $buyerVerdict = "CAUTION"
    $buyerClass = "verdict-warning"
    $buyerExplanation = "Several findings require review. Check their details and complete the manual inspection before purchasing."
}
elseif ($overallScore -ge 80 -and $condScore -ge 70) {
    $buyerVerdict = "GOOD CANDIDATE"
    $buyerClass = "verdict-good"
    $buyerExplanation = "The automated condition and capability estimates are reasonably favorable. This is not a purchase guarantee; price, workload fit and physical inspection still matter."
}
else {
    $buyerVerdict = "REVIEW REPORT"
    $buyerClass = "verdict-neutral"
    $buyerExplanation = "The automated results do not justify a strong recommendation. Review capability, condition findings, price and the intended workload."
}

# ============================================================
# HTML CONTENT
# ============================================================

 $condReasonsHtml = (
    $condReasons |
    ForEach-Object {
        "<li>$(ConvertTo-HtmlSafe $_)</li>"
    }
) -join "`n"

 $perfReasonsHtml = (
    $perfReasons |
    ForEach-Object {
        "<li>$(ConvertTo-HtmlSafe $_)</li>"
    }
) -join "`n"

 $issueHtml = ""

if ($issues.Count -gt 0) {

    $issueItems = (
        $issues |
        ForEach-Object {

            $severityClass = switch ($_.Severity) {
                "High" { "issue-high" }
                "Medium" { "issue-medium" }
                default { "issue-low" }
            }

            "<div class='issue $severityClass'><span class='issue-badge'>$(ConvertTo-HtmlSafe $_.Severity)</span><span class='issue-msg'>$(ConvertTo-HtmlSafe $_.Message)</span></div>"
        }
    ) -join "`n"

    $issueHtml = $issueItems
}
else {

    $issueHtml =
    "<div class='issue issue-good'><span class='issue-badge'>OK</span><span class='issue-msg'>No major automated issues detected.</span></div>"
}

# Group repeated event records by provider + event ID + level. This makes the
# bottom summary useful without presenting every occurrence as a separate fault.
 $eventSummaryHtml = ""

if ($eventGroups.Count -gt 0) {
    $eventPatternCards = foreach ($group in $eventGroups) {
        $groupEvents = @($group.Group | Sort-Object TimeCreated -Descending)
        $latestEvent = $groupEvents[0]
        $provider = ConvertTo-HtmlSafe (Get-SafeValue $latestEvent.ProviderName "Unknown provider")
        $eventId = ConvertTo-HtmlSafe $latestEvent.Id
        $levelLabel = if ($latestEvent.Level -eq 1) { "Critical" } else { "Error" }
        $levelClass = if ($latestEvent.Level -eq 1) { "event-level-critical" } else { "event-level-error" }
        $latestTime = ConvertTo-HtmlSafe $latestEvent.TimeCreated

        $sampleMessage = [string]$latestEvent.Message
        $sampleMessage = ($sampleMessage -replace '\s+', ' ').Trim()
        if ($sampleMessage.Length -gt 280) {
            $sampleMessage = $sampleMessage.Substring(0, 277) + "..."
        }
        $sampleMessage = ConvertTo-HtmlSafe $sampleMessage

        $occurrenceHtml = (
            $groupEvents | Select-Object -First 5 | ForEach-Object {
                $occurrenceTime = ConvertTo-HtmlSafe $_.TimeCreated
                $occurrenceMessage = [string]$_.Message
                $occurrenceMessage = ($occurrenceMessage -replace '\s+', ' ').Trim()
                if ($occurrenceMessage.Length -gt 360) {
                    $occurrenceMessage = $occurrenceMessage.Substring(0, 357) + "..."
                }
                $occurrenceMessage = ConvertTo-HtmlSafe $occurrenceMessage
                "<div class='event-occurrence'><b>$occurrenceTime</b><p>$occurrenceMessage</p></div>"
            }
        ) -join "`n"

        $moreOccurrencesNote = if ($groupEvents.Count -gt 5) {
            "<p class='muted small'>Showing the 5 most recent of $($groupEvents.Count) occurrences in this group.</p>"
        } else { "" }

        "<div class='event-pattern'><div class='event-pattern-head'><div><strong>$provider (Event ID $eventId)</strong><div class='muted small'>Level: $levelLabel &middot; Latest: $latestTime</div></div><span class='event-count $levelClass'>$($groupEvents.Count) occurrence(s)</span></div><p class='event-sample'><b>Latest message:</b> $sampleMessage</p><details><summary>Show recent occurrences</summary>$occurrenceHtml$moreOccurrencesNote</details></div>"
    }

    $eventSummaryHtml = $eventPatternCards -join "`n"
}
else {
    $eventSummaryHtml = "<p class='muted'>No Critical or Error-level System events were returned for the last 30 days. This is not a guarantee of hardware health.</p>"
}

if ($lastUpdateDate) {

    $updateDateText = ConvertTo-HtmlSafe $lastUpdateDate

    if ($daysSinceUpdate -is [int] -or
        $daysSinceUpdate -is [long]) {

        $updateSummary =
        "Last update: $updateDateText ($daysSinceUpdate days ago)"
    }
    else {
        $updateSummary =
        "Last update: $updateDateText"
    }
}
else {

    $updateSummary = "Last update: Unknown"
}

if ($batteryHtml) {

    $batteryHtmlEncoded =
    $batteryHtml `
        -replace "&", "&amp;" `
        -replace '"', "&quot;" `
        -replace "<", "&lt;" `
        -replace ">", "&gt;"

    $batterySection = @"
<div class="card">
    <div class="card-head">
        <h2>Battery Report</h2>
    </div>

    <div class="summary $(if ($batteryHealthWarning) { 'warning' } else { 'ok' })">
        Battery Health: $(ConvertTo-HtmlSafe $batteryHealthStr)
    </div>

    <p class="muted small">
        Battery health is calculated from design capacity versus current full-charge capacity.
        A battery below 70% is flagged for investigation.
    </p>

    <details>
        <summary>Show Windows Battery Report</summary>
        <iframe
            srcdoc="$batteryHtmlEncoded"
            style="width:100%; height:900px; border:1px solid var(--border-color); border-radius:10px; background:#fff;">
        </iframe>
    </details>
</div>
"@
}
else {

    $batterySection = @"
<div class="card">
    <div class="card-head">
        <h2>Battery Report</h2>
    </div>
    <p class="muted">
        No battery report available. This may be a desktop PC or the Windows
        battery reporting interface may not be available.
    </p>
</div>
"@
}

 $collectionWarningsHtml = ""
if ($collectionWarnings.Count -gt 0) {
    $warningItems = ($collectionWarnings | Select-Object -Unique | ForEach-Object { "<li>$(ConvertTo-HtmlSafe $_)</li>" }) -join "`n"
    $collectionWarningsHtml = @"
<div class="card">
    <h2>Data Collection Warnings</h2>
    <p class="muted" style="margin-top:0;">
        Some information could not be collected. Missing data is treated as unknown
        rather than automatically healthy.
    </p>
    <ul>
        $warningItems
    </ul>
</div>
"@
}

# ============================================================
# HTML REPORT
# ============================================================

 $generatedTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

 $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PC Check Report</title>
<style>

:root {
    --bg-color: #eef1f4;
    --card-bg: #ffffff;
    --text-color: #1f2530;
    --text-muted: #5b6472;
    --heading-color: #14314f;
    --accent: #2563eb;
    --border-color: #e2e6ec;
    --table-stripe: #f6f8fa;

    --summary-bg: #eafaf3;
    --summary-border: #17a673;
    --summary-text: #0e6e52;

    --warning-bg: #fff6e6;
    --warning-border: #e69b12;
    --warning-text: #8a5a06;

    --danger-bg: #fdeeee;
    --danger-border: #e0483f;
    --danger-text: #a5241c;

    --neutral-bg: #f1f4f8;
    --neutral-border: #9aa7b7;
    --neutral-text: #4b5563;

    --button-bg: #14314f;
    --button-text: #ffffff;

    --switch-off: #cfd4db;
    --radius: 14px;
    --radius-sm: 8px;
    --shadow: 0 1px 2px rgba(20,30,45,0.04), 0 8px 24px rgba(20,30,45,0.06);
}

[data-theme="dark"] {
    --bg-color: #0e1117;
    --card-bg: #171b23;
    --text-color: #e7eaef;
    --text-muted: #93a0b4;
    --heading-color: #7cb0ff;
    --accent: #5b9dff;
    --border-color: #2a3040;
    --table-stripe: #1d2230;

    --summary-bg: #10261f;
    --summary-border: #22c58f;
    --summary-text: #6fe3bd;

    --warning-bg: #2c210c;
    --warning-border: #e9a733;
    --warning-text: #ffcf7a;

    --danger-bg: #2a1414;
    --danger-border: #e0483f;
    --danger-text: #ff9c94;

    --neutral-bg: #202632;
    --neutral-border: #64748b;
    --neutral-text: #cbd5e1;

    --button-bg: #5b9dff;
    --button-text: #0e1117;

    --switch-off: #3a4052;
    --shadow: 0 1px 2px rgba(0,0,0,0.3), 0 12px 32px rgba(0,0,0,0.35);
}

* { box-sizing: border-box; }

html { scroll-behavior: smooth; }

body {
    font-family: "Segoe UI", system-ui, -apple-system, Arial, sans-serif;
    margin: 0;
    padding: 0 0 60px 0;
    background-color: var(--bg-color);
    color: var(--text-color);
    transition: background-color 0.25s ease, color 0.25s ease;
    line-height: 1.55;
    -webkit-font-smoothing: antialiased;
}

.container {
    max-width: 1180px;
    margin: 0 auto;
    padding: 0 28px;
}

/* ---------- TOP BAR ---------- */

.topbar {
    background: var(--card-bg);
    border-bottom: 1px solid var(--border-color);
    position: sticky;
    top: 0;
    z-index: 20;
}

.topbar-inner {
    max-width: 1180px;
    margin: 0 auto;
    padding: 16px 28px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 20px;
}

.brand {
    display: flex;
    flex-direction: column;
    gap: 2px;
}

.brand h1 {
    color: var(--heading-color);
    margin: 0;
    font-size: 19px;
    font-weight: 700;
    letter-spacing: -0.01em;
}

.brand .meta {
    color: var(--text-muted);
    font-size: 12.5px;
    margin: 0;
}

.theme-switch-wrapper {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 13px;
    color: var(--text-muted);
    font-weight: 600;
}

.switch {
    position: relative;
    display: inline-block;
    width: 42px;
    height: 22px;
    flex-shrink: 0;
}

.switch input { opacity: 0; width: 0; height: 0; }

.slider {
    position: absolute;
    cursor: pointer;
    inset: 0;
    background-color: var(--switch-off);
    transition: .25s;
    border-radius: 22px;
}

.slider:before {
    position: absolute;
    content: "";
    height: 16px;
    width: 16px;
    left: 3px;
    bottom: 3px;
    background-color: white;
    transition: .25s;
    border-radius: 50%;
    box-shadow: 0 1px 3px rgba(0,0,0,0.3);
}

input:checked + .slider { background-color: var(--button-bg); }
input:checked + .slider:before { transform: translateX(20px); }

/* ---------- LAYOUT ---------- */

.page-body { padding-top: 28px; }

h2 {
    color: var(--heading-color);
    margin: 0 0 16px 0;
    font-size: 17px;
    font-weight: 700;
    letter-spacing: -0.01em;
}

h3 {
    color: var(--text-muted);
    margin: 18px 0 8px 0;
    font-size: 12px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
}

.card-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 4px;
}

.meta {
    color: var(--text-muted);
    opacity: 0.9;
    font-size: 13px;
}

.card {
    background: var(--card-bg);
    padding: 28px;
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    margin-bottom: 22px;
    border: 1px solid var(--border-color);
}

.grid-2 {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 22px;
}

@media (max-width: 900px) {
    .grid-2 { grid-template-columns: 1fr; }
    .container { padding: 0 16px; }
    .topbar-inner { padding: 14px 16px; }
    .page-body { padding-top: 20px; }
}

/* ---------- TABLES ---------- */

table {
    border-collapse: collapse;
    width: 100%;
    margin-top: 6px;
    table-layout: fixed;
    font-size: 14.5px;
}

th, td {
    border: 1px solid var(--border-color);
    padding: 14px 16px;
    text-align: left;
    word-wrap: break-word;
    overflow-wrap: break-word;
    vertical-align: top;
    line-height: 1.6;
}

th {
    background-color: var(--table-stripe);
    color: var(--text-muted);
    font-size: 11.5px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    border-bottom: 2px solid var(--border-color);
    line-height: 1.3;
}

tr:nth-child(even) td { background-color: var(--table-stripe); }
tr:hover td { background-color: color-mix(in srgb, var(--accent) 6%, var(--table-stripe)); }

/* ---------- TEXT UTILITIES ---------- */

.muted { color: var(--text-muted); opacity: 0.9; font-style: normal; }
.small { font-size: 13px; }

/* ---------- SUMMARY / WARNING BOXES ---------- */

.summary {
    background: var(--summary-bg);
    border-left: 4px solid var(--summary-border);
    padding: 14px 18px;
    margin-bottom: 15px;
    font-weight: 600;
    color: var(--summary-text);
    border-radius: var(--radius-sm);
    font-size: 14.5px;
}

.summary.warning {
    background: var(--warning-bg);
    border-left-color: var(--warning-border);
    color: var(--warning-text);
}

.warningbox {
    background: var(--warning-bg);
    border-left: 4px solid var(--warning-border);
    color: var(--warning-text);
    padding: 15px 16px;
    margin-top: 15px;
    border-radius: var(--radius-sm);
    font-size: 14px;
}

.flag {
    color: var(--danger-border);
    font-weight: 700;
    font-size: 12.5px;
}

.eventblock {
    background: var(--table-stripe);
    border-left: 3px solid var(--danger-border);
    padding: 12px 14px;
    margin-top: 10px;
    border-radius: var(--radius-sm);
    font-size: 13px;
}

.eventblock pre {
    white-space: pre-wrap;
    margin: 6px 0 0 0;
    font-family: inherit;
    word-wrap: break-word;
    font-size: 12.5px;
}

.event-pattern {
    border: 1px solid var(--border-color);
    border-radius: var(--radius-sm);
    padding: 15px 16px;
    margin: 12px 0;
    background: var(--card-bg);
}

.event-pattern-head {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 12px;
}

.event-count {
    font-size: 11px;
    font-weight: 800;
    padding: 4px 9px;
    border-radius: 999px;
    white-space: nowrap;
    background: var(--table-stripe);
}

.event-level-critical { color: var(--danger-text); background: var(--danger-bg); }
.event-level-error { color: var(--warning-text); background: var(--warning-bg); }
.event-sample { margin: 10px 0 0; font-size: 13.5px; }
.event-occurrence { border-top: 1px solid var(--border-color); padding: 10px 0; font-size: 12.5px; }
.event-occurrence p { margin: 4px 0 0; overflow-wrap: anywhere; }

@media (max-width: 600px) {
    .event-pattern-head { flex-direction: column; }
}

pre {
    background: var(--table-stripe);
    padding: 14px 16px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-color);
    white-space: pre-wrap;
    word-wrap: break-word;
    font-size: 13px;
}

/* ---------- SCORES ---------- */

.score-row {
    display: flex;
    align-items: baseline;
    gap: 14px;
    margin-bottom: 6px;
}

.score-big {
    font-size: 42px;
    font-weight: 800;
    color: var(--heading-color);
    letter-spacing: -0.02em;
    line-height: 1;
}

.score-max { color: var(--text-muted); font-size: 16px; font-weight: 600; }

.score-rating {
    font-size: 13px;
    font-weight: 700;
    padding: 5px 13px;
    border-radius: 999px;
    display: inline-block;
    margin-bottom: 14px;
}

.rating-good { background: color-mix(in srgb, var(--summary-border) 18%, transparent); color: var(--summary-text); }
.rating-fair { background: color-mix(in srgb, var(--warning-border) 20%, transparent); color: var(--warning-text); }
.rating-poor { background: color-mix(in srgb, var(--danger-border) 18%, transparent); color: var(--danger-text); }

.score-bar-track {
    width: 100%;
    height: 8px;
    background: var(--table-stripe);
    border-radius: 999px;
    overflow: hidden;
    margin-bottom: 4px;
}

.score-bar-fill {
    height: 100%;
    border-radius: 999px;
    background: linear-gradient(90deg, var(--accent), var(--summary-border));
}

/* ---------- VERDICT ---------- */

.verdict {
    padding: 26px 28px;
    border-radius: var(--radius);
    margin-bottom: 22px;
    border: 1px solid;
    box-shadow: var(--shadow);
    position: relative;
    overflow: hidden;
}

.verdict-eyebrow {
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-size: 11.5px;
    font-weight: 700;
    opacity: 0.75;
    margin-bottom: 6px;
}

.verdict-score {
    font-size: 28px;
    font-weight: 800;
    letter-spacing: -0.01em;
    margin-bottom: 8px;
}

.verdict-footer {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 14px;
    padding-top: 14px;
    border-top: 1px solid rgba(0,0,0,0.08);
    font-size: 14px;
}

.verdict-footer strong { font-size: 16px; }

.verdict-good    { background: var(--summary-bg); border-color: var(--summary-border); color: var(--summary-text); }
.verdict-warning { background: var(--warning-bg); border-color: var(--warning-border); color: var(--warning-text); }
.verdict-danger  { background: var(--danger-bg);  border-color: var(--danger-border);  color: var(--danger-text); }
.verdict-neutral { background: var(--neutral-bg); border-color: var(--neutral-border); color: var(--neutral-text); }

/* ---------- ISSUES ---------- */

.issue {
    padding: 12px 15px;
    margin: 8px 0;
    border-left: 4px solid;
    border-radius: var(--radius-sm);
    display: flex;
    align-items: flex-start;
    gap: 10px;
    font-size: 14px;
}

.issue-badge {
    font-size: 10.5px;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 2px 8px;
    border-radius: 999px;
    flex-shrink: 0;
    margin-top: 1px;
    background: rgba(0,0,0,0.08);
}

.issue-msg { flex: 1; }

.issue-high   { background: var(--danger-bg);  border-color: var(--danger-border);  color: var(--danger-text); }
.issue-medium { background: var(--warning-bg); border-color: var(--warning-border); color: var(--warning-text); }
.issue-low    { background: var(--table-stripe); border-color: #8a93a3; color: var(--text-color); }
.issue-good   { background: var(--summary-bg); border-color: var(--summary-border); color: var(--summary-text); }

/* ---------- STAT PILLS (used in card-head slots) ---------- */

.pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background: var(--table-stripe);
    color: var(--text-muted);
    font-size: 12.5px;
    font-weight: 700;
    padding: 5px 12px;
    border-radius: 999px;
    border: 1px solid var(--border-color);
}

/* ---------- CONFIDENCE ---------- */

.confidence {
    font-size: 13px;
    color: var(--text-muted);
    margin-bottom: 14px;
    display: flex;
    align-items: center;
    gap: 6px;
}

.confidence strong { color: var(--text-color); }

/* ---------- FOOTER ---------- */

.footer {
    text-align: center;
    margin-top: 36px;
    padding-top: 24px;
    border-top: 1px solid var(--border-color);
    color: var(--text-muted);
    font-size: 12.5px;
    line-height: 1.8;
}

.footer a { color: var(--accent); text-decoration: none; font-weight: 600; }
.footer a:hover { text-decoration: underline; }

/* ---------- DETAILS / SUMMARY ---------- */

details { margin-top: 15px; }

summary {
    cursor: pointer;
    font-weight: 700;
    color: var(--accent);
    margin-bottom: 10px;
    font-size: 13.5px;
    list-style: none;
}

summary::-webkit-details-marker { display: none; }

summary:before {
    content: "▸ ";
}

details[open] summary:before {
    content: "▾ ";
}

/* ---------- MISC LISTS ---------- */

ul { padding-left: 20px; margin: 8px 0; }
li { margin-bottom: 7px; font-size: 14.5px; line-height: 1.6; }

</style>
</head>

<body>

<script>
function setTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    const toggle = document.getElementById("themeToggle");
    if (toggle) { toggle.checked = theme === "dark"; }
}
document.addEventListener("DOMContentLoaded", function () {
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    setTheme(prefersDark ? "dark" : "light");
});
</script>

<div class="topbar">
    <div class="topbar-inner">
        <div class="brand">
            <h1>PC Check Report</h1>
            <p class="meta">Generated $(ConvertTo-HtmlSafe $generatedTime)</p>
        </div>
        <div class="theme-switch-wrapper">
            <span>Dark Mode</span>
            <label class="switch">
                <input type="checkbox" id="themeToggle" checked onchange="setTheme(this.checked ? 'dark' : 'light')">
                <span class="slider"></span>
            </label>
        </div>
    </div>
</div>

<div class="container page-body">

<!-- BUYER VERDICT -->

<div class="verdict $buyerClass">
    <div class="verdict-eyebrow">Buyer Verdict</div>
    <div class="verdict-score">$(ConvertTo-HtmlSafe $buyerVerdict)</div>
    <p style="margin:0;">$(ConvertTo-HtmlSafe $buyerExplanation)</p>
    <div class="verdict-footer">
        Overall automated score: <strong>$overallScore / 100</strong>
    </div>
</div>

<!-- SCORES -->

<div class="grid-2">

    <div class="card">
        <h2>Hardware Condition</h2>
        <div class="score-row">
            <div class="score-big">$condScore</div>
            <div class="score-max">/ 100</div>
        </div>
        <div class="score-bar-track">
            <div class="score-bar-fill" style="width:$condScore%;"></div>
        </div>
        <div class="score-rating $(Get-ScoreClass $condScore)" style="margin-top:12px;">
            $(ConvertTo-HtmlSafe $condRating)
        </div>
        <div class="confidence">
            Confidence: <strong>$conditionConfidence%</strong> ($(ConvertTo-HtmlSafe $conditionConfidenceRating))
        </div>
        <h3>Why this score</h3>
        <ul>
            $condReasonsHtml
        </ul>
    </div>

    <div class="card">
        <h2>Hardware Capability</h2>
        <div class="score-row">
            <div class="score-big">$perfScore</div>
            <div class="score-max">/ 100</div>
        </div>
        <div class="score-bar-track">
            <div class="score-bar-fill" style="width:$perfScore%;"></div>
        </div>
        <div class="score-rating $(Get-ScoreClass $perfScore)" style="margin-top:12px;">
            $(ConvertTo-HtmlSafe $perfRating)
        </div>
        <div class="confidence">
            Confidence: <strong>$capabilityConfidence%</strong> ($(ConvertTo-HtmlSafe $capabilityConfidenceRating))
        </div>
        <p class="small muted" style="margin-top:0;">
            Estimated capability, not a synthetic benchmark. Does not measure actual FPS,
            application performance, thermals, or sustained performance. This score
            reflects coarse RAM/CPU-core-count/VRAM tiers only &mdash; it does not account for
            CPU/GPU generation or architecture. VRAM is the maximum reported on a single adapter,
            not combined across adapters. Two GPUs with the same reported VRAM can differ enormously
            in real-world performance.
        </p>
        <h3>Why this score</h3>
        <ul>
            $perfReasonsHtml
        </ul>
    </div>

</div>

<p class="muted small" style="margin:-8px 0 22px;">
    Confidence reflects data availability, not validated benchmark accuracy or certainty about physical condition. This automated report cannot prove that a used PC is fault-free.
</p>

<!-- ISSUES -->

<div class="card">
    <h2>Things To Investigate</h2>
    $issueHtml
</div>

<!-- SUITABILITY -->

<div class="card">
    <h2>Usage Suitability</h2>
    <p class="muted small" style="margin-top:0;">
        Capability estimates derived from detected hardware. Not application benchmarks.
    </p>
    $(To-HtmlTable $usageScores)
</div>

<!-- SYSTEM -->

<div class="grid-2">
    <div class="card">
        <h2>System Overview</h2>
        $(To-HtmlTable $sysInfo)
        <div class="summary" style="margin-top:14px;">
            System Uptime: $(ConvertTo-HtmlSafe $uptimeStr)
        </div>
    </div>
    <div class="card">
        <h2>CPU</h2>
        $(To-HtmlTable $cpu)
    </div>
</div>

<!-- RAM + GPU -->

<div class="grid-2">
    <div class="card">
        <h2>RAM</h2>
        <div class="summary">
            Total RAM: $(ConvertTo-HtmlSafe $totalRamStr) &middot; $ramSlotCount physical module(s)
        </div>
        $(To-HtmlTable $ram)
    </div>

    <div class="card">
        <h2>GPU &amp; Display</h2>
        <div class="summary">
            Maximum reported GPU memory on one adapter: $(ConvertTo-HtmlSafe $totalVramStr)
        </div>
        <h3>Video Controllers</h3>
        $(To-HtmlTable $gpu)
        <h3>Active Video Controllers / Displays</h3>
        $(To-HtmlTable $displays)
    </div>
</div>

<!-- STORAGE -->

<div class="card">
    <h2>Storage Devices &amp; Capacity</h2>
    <div class="summary">
        Total Physical Storage: $(ConvertTo-HtmlSafe $totalStorageStr)
        &nbsp;&middot;&nbsp;
        Free Space: $(ConvertTo-HtmlSafe $totalFreeStr) of $(ConvertTo-HtmlSafe $totalVolSpaceStr)
    </div>
    <p class="muted small" style="margin-top:0;">
        This report inventories drives, interfaces and capacity but does not assess SSD/HDD SMART health, wear percentage or remaining life. Windows storage reliability counters are inconsistent across drives and controllers, so they are intentionally excluded from scoring. Use CrystalDiskInfo to inspect supported drive telemetry separately.
    </p>
    $(To-HtmlTable $storage)
    <h3>Storage Free Space</h3>
    $(To-HtmlTable $volumes)
</div>

<!-- OS SECURITY -->

<div class="grid-2">
    <div class="card">
        <h2>OS &amp; Security</h2>
        <h3>Windows Activation</h3>
        <pre>$(ConvertTo-HtmlSafe ($activation -join "`n"))</pre>
        <h3>TPM Status</h3>
        $(if ($tpm) { To-HtmlTable $tpm } else { "<p class='muted'>Could not retrieve TPM status.</p>" })
        <h3>Antivirus Status</h3>
        $(if ($avStatus) { To-HtmlTable $avStatus } else { "<p class='muted'>Could not retrieve Microsoft Defender status.</p>" })
    </div>

    <div class="card">
        <h2>BIOS &amp; Updates</h2>
        <h3>BIOS</h3>
        $(To-HtmlTable $bios)
        <h3>Windows Update</h3>
        <div class="summary $(if($updateWarning){'warning'}else{'ok'})">
            $(ConvertTo-HtmlSafe $updateSummary)
            $(if ($updateWarning) { "<span class='flag'> &middot; over 90 days ago</span>" })
        </div>
        $(To-HtmlTable $updates)
    </div>
</div>

<!-- NETWORK -->

<div class="card">
    <h2>Network Adapters</h2>
    $(To-HtmlTable $netAdapters)
</div>

<!-- EVENTS -->

<div class="card">
    <h2>System Errors - Last 30 Days</h2>
    <div class="summary $(if ($eventWarning) { 'warning' } else { 'ok' })">
        Critical: $criticalCount &nbsp;|&nbsp; Total Error/Critical Events: $errorCount &nbsp;|&nbsp; Distinct Patterns: $($eventGroups.Count)
        $(if ($eventWarning) { "<span class='flag'> &middot; review details</span>" })
    </div>
    <p class="muted small" style="margin-top:0;">
        Category counts may overlap because one event can match more than one category. Repeated records are grouped by provider, event ID and level in the detailed summary near the bottom. Event logs are clues, not proof of a failed component.
    </p>

    <div class="grid-2">
        <div>
            <h3>Hardware Errors - WHEA</h3>
            <p class="small muted" style="margin-top:0;">
                Can indicate instability involving CPU, memory, PCIe, or another hardware component.
            </p>
            <div class="$(if ($wheaErrors.Count -gt 0) { 'warningbox' } else { 'summary' })">$($wheaErrors.Count) WHEA/HAL event(s) found.</div>
        </div>
        <div>
            <h3>Disk / Storage Errors</h3>
            <p class="small muted" style="margin-top:0;">Storage-related Windows errors.</p>
            <div class="$(if ($diskErrors.Count -gt 0) { 'warningbox' } else { 'summary' })">$($diskErrors.Count) storage-related event(s) found.</div>
        </div>
    </div>

    <h3>Graphics / Driver Errors</h3>
    <div class="summary">$($driverErrors.Count) graphics/display-related events found.</div>

    <p class="muted small" style="margin-bottom:0;">For specific event IDs, sample messages, occurrence counts and recent timestamps, see <strong>Detailed System Error Summary</strong> near the bottom of this report.</p>
</div>

<!-- STARTUP -->

<div class="card">
    <h2>Startup Programs</h2>
    <div class="summary">
        $startupCount program(s) launch at startup
        $(if ($startupCount -gt 15) { "<span class='flag'> &middot; heavy startup load</span>" })
    </div>
    $(To-HtmlTable $startupPrograms)
</div>

<!-- BATTERY -->

 $batterySection

<!-- RECOMMENDED TOOLS -->

<div class="card">
    <h2>Recommended External Tools</h2>
    <p class="muted small" style="margin-top:0;">
        This report covers what can be checked automatically and safely without installing
        anything. For a deeper check before buying, consider running these free, well-known
        third-party tools yourself.
    </p>
    <ul>
        <li><strong>CrystalDiskInfo</strong> &mdash; can read supported SMART data, drive temperature,
            and vendor-reported health information. This report intentionally does not assess SSD/HDD
            SMART health or remaining life; verify the exact drive and review its telemetry manually.</li>
        <li><strong>CrystalDiskMark</strong> &mdash; benchmarks actual sequential and random
            read/write speed of a drive, so you can confirm it performs at the speed expected
            for its type (e.g. NVMe vs SATA SSD vs HDD).</li>
        <li><strong>MemTest86</strong> &mdash; boots from USB and runs a standalone RAM
            stability test outside of Windows. Useful if you suspect memory errors, random
            crashes, or want to confirm new RAM is stable before relying on it.</li>
    </ul>
    <p class="muted small" style="margin-bottom:0;">
        These are not affiliated with this script and are not run or downloaded automatically
        &mdash; search for them directly from their official sites and verify the download
        source yourself.
    </p>
</div>

<!-- MANUAL CHECKS -->

<div class="card" style="background: var(--summary-bg); border-color: var(--summary-border);">
    <h2 style="color: var(--summary-text);">Manual Inspection Still Required</h2>
    <p style="margin-top:0;">
        Software cannot reliably detect physical damage or every functional problem.
        Perform these checks before buying a used PC.
    </p>
    <ul>
        <li>Physically inspect the screen for dead pixels, brightness issues, and uniformity.</li>
        <li>Check laptop hinges for looseness, cracking, or unusual sounds.</li>
        <li>Test every keyboard key.</li>
        <li>Test the touchpad / mouse.</li>
        <li>Test every USB port.</li>
        <li>Test HDMI / DisplayPort / USB-C video output where applicable.</li>
        <li>Test the charging port.</li>
        <li>Test speakers and microphone.</li>
        <li>Test the webcam.</li>
        <li>Check Wi-Fi and Bluetooth.</li>
        <li>Listen for abnormal fan noise, clicking, grinding, or coil whine.</li>
        <li>Inspect the chassis for cracks, dents, liquid damage, or missing screws.</li>
        <li>Check laptop battery charging behavior.</li>
        <li>Check desktop fans and heatsinks for excessive dust.</li>
        <li>Open a real Office application and verify the user's license if Office is expected.</li>
        <li>Verify that the Windows edition matches what the seller advertised.</li>
    </ul>
</div>

<!-- LIMITATIONS -->

<div class="card">
    <h2>Important Limitations</h2>
    <ul>
        <li>This tool does not perform CPU/GPU stress testing.</li>
        <li>This tool does not perform synthetic performance benchmarks.</li>
        <li>This report does not assess storage SMART health, SSD wear percentage, or remaining drive life.</li>
        <li>Windows Event Viewer errors do not automatically prove hardware failure.</li>
        <li>GPU VRAM is read from driver/registry data; if unavailable it is reported as Unknown rather than estimated.</li>
        <li>Suitability scores are estimates, not guarantees of application performance.</li>
        <li>Physical inspection is still required for a used-PC purchase.</li>
    </ul>
</div>

<!-- DETAILED EVENT SUMMARY -->

<div class="card">
    <h2>Detailed System Error Summary</h2>
    <p class="muted small" style="margin-top:0;">
        Last 30 days. Events are grouped by provider, event ID and severity to reduce repeated noise. Each group shows the occurrence count, latest timestamp and a sample message; expand it to see up to the five most recent occurrences. One event can still have multiple possible causes, so investigate the message and surrounding circumstances before concluding that hardware has failed.
    </p>
    <div class="summary">
        $($eventGroups.Count) distinct event pattern(s) &middot; $errorCount total Critical/Error event record(s)
    </div>
    $eventSummaryHtml
</div>

<!-- COLLECTION WARNINGS -->

 $collectionWarningsHtml

<!-- FOOTER -->

<div class="footer">
    PC Check v2.2 &middot;
    <a href="https://github.com/Hans930v/pc-check" target="_blank">github.com/Hans930v/pc-check</a>
    &middot; MIT License
    <br>
    Open-source PowerShell diagnostic tool. This report is designed to be read-only.
    <br>
    No hardware configuration or personal files are intentionally modified.
</div>

</div>

</body>
</html>
"@

# ============================================================
# WRITE REPORT
# ============================================================

Write-Check "Building HTML report..."

try {

    $html |
    Out-File `
        -FilePath $htmlPath `
        -Encoding utf8 `
        -Force `
        -ErrorAction Stop

    Write-Step "HTML report built"

}
catch {

    Write-Host ""
    Write-Host "FAILED to create report:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    Read-Host "Press Enter to exit"

    exit 1
}

# ============================================================
# FINISH
# ============================================================

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "          PC CHECK COMPLETE" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Buyer Verdict: " -NoNewline -ForegroundColor White
Write-Host $buyerVerdict -ForegroundColor Green

Write-Host "Condition:     " -NoNewline -ForegroundColor White
Write-Host "$condScore / 100 ($condRating)" -ForegroundColor Green

Write-Host "Capability:    " -NoNewline -ForegroundColor White
Write-Host "$perfScore / 100 ($perfRating)" -ForegroundColor Green

Write-Host ""
Write-Host "Issues detected: $($issues.Count)" -ForegroundColor Yellow
Write-Host ""

Write-Host "HTML report saved to:" -ForegroundColor Cyan
Write-Host $htmlPath -ForegroundColor Green

Write-Host ""

Read-Host "Press Enter to open the report and close this window"

try {
    Invoke-Item $htmlPath
}
catch {
    Write-Host "Could not automatically open the report." -ForegroundColor Yellow
}
