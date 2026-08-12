<#
.SYNOPSIS
    PC Check Report - A comprehensive hardware and software audit tool.
.DESCRIPTION
    This script gathers detailed system information (CPU, RAM, GPU, Storage, Battery, Network, etc.)
    and generates a clean, modern, single-file HTML report with Dark/Light mode support.
.NOTES
    File Name      : pc-check.ps1
    Author         : Hansoy
    Copyright      : (c) 2026 Hansoy. All rights reserved.
    License        : MIT License
    GitHub         : https://github.com/Hans930v/pc-check
    
    Transparency   : This script was collaboratively "vibe coded" with the assistance of AI.
#>

# --- Self-elevate if not already admin ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  if ($PSCommandPath) {
    # If run as a .ps1 file, elevate the file
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
  }
  else {
    # If run via a one-liner (iex), tell them to restart their console as Admin
    Write-Host "Administrator privileges required. Please right-click PowerShell, select 'Run as Administrator', and paste the command again." -ForegroundColor Red
    Start-Sleep -Seconds 5
  }
  exit
}

$ErrorActionPreference = "SilentlyContinue"
$desktop = "$env:USERPROFILE\Desktop"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$htmlPath = "$desktop\pc-check-$timestamp.html"
$tempBattery = "$env:TEMP\battery-report-$timestamp.html"
$tempBatteryXml = "$env:TEMP\battery-report-$timestamp.xml"

function Write-Step($msg) {
  Write-Host "$msg [DONE]" -ForegroundColor Green
}

Write-Host "Starting PC Check..." -ForegroundColor Cyan

# --- Gather data ---
Write-Host "Collecting CPU info..." -ForegroundColor Yellow
$cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, @{N = "MaxClock(GHz)"; E = { [math]::Round($_.MaxClockSpeed / 1000, 2) } }
Write-Step "CPU info"

Write-Host "Generating battery report..." -ForegroundColor Yellow
powercfg /batteryreport /output "$tempBattery" | Out-Null
powercfg /batteryreport /output "$tempBatteryXml" /xml | Out-Null
Write-Step "Battery info"

$batteryHtml = $null
if (Test-Path $tempBattery) {
  $batteryHtml = Get-Content $tempBattery -Raw
  $batteryHtml = $batteryHtml -replace '&', '&amp;' -replace '"', '&quot;'
  Remove-Item $tempBattery -Force
}

$batteryHealthStr = "Unknown"
$batteryHealthWarning = $false
if (Test-Path $tempBatteryXml) {
  try {
    [xml]$battXml = Get-Content $tempBatteryXml -Raw
    $designCap = [double]$battXml.BatteryReport.Batteries.Battery.DesignCapacity
    $fullCap = [double]$battXml.BatteryReport.Batteries.Battery.FullChargeCapacity
    if ($designCap -gt 0) {
      $healthPct = [math]::Round(($fullCap / $designCap) * 100, 1)
      $batteryHealthStr = "$healthPct% (Design: $([math]::Round($designCap/1000,1)) Wh, Current Full: $([math]::Round($fullCap/1000,1)) Wh)"
      if ($healthPct -lt 70) { $batteryHealthWarning = $true }
    }
  }
  catch {
    $batteryHealthStr = "Could not parse (device may have no battery)"
  }
  Remove-Item $tempBatteryXml -Force -ErrorAction SilentlyContinue
}
Write-Step "Battery report loaded"

Write-Host "Collecting system info..." -ForegroundColor Yellow
$sysInfo = systeminfo | Select-String "OS Name", "OS Version", "System Manufacturer", "System Model", "BIOS Version", "Original Install Date"
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$lastBoot = $os.LastBootUpTime
$uptime = (Get-Date) - $lastBoot
$uptimeStr = "{0}d {1}h {2}m (since $lastBoot)" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
Write-Step "System info"

Write-Host "Collecting RAM info..." -ForegroundColor Yellow
$ramObjects = Get-CimInstance -ClassName Win32_PhysicalMemory
$totalRamBytes = ($ramObjects | Measure-Object -Property Capacity -Sum).Sum
$totalRamStr = if ($totalRamBytes) { "$([math]::Round($totalRamBytes / 1GB, 1)) GB" } else { "Unknown" }
$ram = $ramObjects | Select-Object BankLabel, @{N = "Capacity(GB)"; E = { [math]::Round($_.Capacity / 1GB, 1) } }, Speed, DeviceLocator
Write-Step "RAM info"

Write-Host "Collecting storage info..." -ForegroundColor Yellow
$storage = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, @{N = "Size(GB)"; E = { [math]::Round($_.Size / 1GB, 1) } }
$totalStorage = 0
foreach ($s in $storage) { if ($s.'Size(GB)' -is [double] -or $s.'Size(GB)' -is [int]) { $totalStorage += $s.'Size(GB)' } }
$totalStorageStr = if ($totalStorage -gt 0) { "$([math]::Round($totalStorage, 1)) GB" } else { "Unknown" }
Write-Step "Storage info"

Write-Host "Collecting storage reliability..." -ForegroundColor Yellow
$reliability = Get-PhysicalDisk | Get-StorageReliabilityCounter | Select-Object DeviceId, Wear, Temperature, ReadErrorsUncorrected, PowerOnHours
$diskWarnings = @()
foreach ($r in $reliability) {
  if ($r.ReadErrorsUncorrected -gt 0) { $diskWarnings += "Disk $($r.DeviceId): $($r.ReadErrorsUncorrected) uncorrected read errors" }
  if ($r.Wear -ne $null -and $r.Wear -gt 80) { $diskWarnings += "Disk $($r.DeviceId): $($r.Wear)% wear (SSD nearing end of life)" }
}
foreach ($s in $storage) {
  if ($s.HealthStatus -and $s.HealthStatus -ne "Healthy") { $diskWarnings += "$($s.FriendlyName): reports HealthStatus '$($s.HealthStatus)'" }
}
Write-Step "Storage reliability"

Write-Host "Collecting volume info..." -ForegroundColor Yellow
$volumes = Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, @{N = "Free(GB)"; E = { [math]::Round($_.SizeRemaining / 1GB, 1) } }, @{N = "Total(GB)"; E = { [math]::Round($_.Size / 1GB, 1) } }
$totalVolSpace = 0; $totalVolFree = 0
foreach ($v in $volumes) {
  if ($v.'Total(GB)' -is [double] -or $v.'Total(GB)' -is [int]) { $totalVolSpace += $v.'Total(GB)' }
  if ($v.'Free(GB)' -is [double] -or $v.'Free(GB)' -is [int]) { $totalVolFree += $v.'Free(GB)' }
}
$totalVolSpaceStr = if ($totalVolSpace -gt 0) { "$([math]::Round($totalVolSpace, 1)) GB" } else { "Unknown" }
$totalVolFreeStr = if ($totalVolFree -gt 0) { "$([math]::Round($totalVolFree, 1)) GB" } else { "Unknown" }
Write-Step "Volume info"

Write-Host "Collecting GPU info..." -ForegroundColor Yellow
$gpu = Get-CimInstance -ClassName Win32_VideoController | ForEach-Object {
  $name = $_.Name; $vramGB = "Unknown"
  $regBase = "HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
  $match = Get-ChildItem $regBase -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } | Where-Object { $_.DriverDesc -eq $name -and $_."HardwareInformation.qwMemorySize" } | Select-Object -First 1
  if ($match) { $vramGB = [math]::Round($match."HardwareInformation.qwMemorySize" / 1GB, 1) }
  elseif ($_.AdapterRAM -gt 0) { $vramGB = [math]::Round($_.AdapterRAM / 1GB, 1) }
  [PSCustomObject]@{ Name = $name; DriverVersion = $_.DriverVersion; "VRAM(GB)" = $vramGB }
}
$totalVram = 0
foreach ($g in $gpu) { if ($g.'VRAM(GB)' -is [double] -or $g.'VRAM(GB)' -is [int]) { $totalVram += $g.'VRAM(GB)' } }
$totalVramStr = if ($totalVram -gt 0) { "$([math]::Round($totalVram, 1)) GB" } else { "Unknown" }

$displays = Get-CimInstance -ClassName Win32_VideoController | Select-Object Name, @{N = "Resolution"; E = { "$($_.CurrentHorizontalResolution) x $($_.CurrentVerticalResolution)" } }, @{N = "RefreshRate(Hz)"; E = { $_.CurrentRefreshRate } }
Write-Step "GPU & Display info"

Write-Host "Checking Windows activation & BIOS..." -ForegroundColor Yellow
$activation = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
# Clean up BIOS date to only show YYYY-MM-DD
$bios = Get-CimInstance -ClassName Win32_BIOS | Select-Object @{N = "ReleaseDate"; E = { if ($_.ReleaseDate) { $_.ReleaseDate.ToString("yyyy-MM-dd") } else { "Unknown" } } }
Write-Step "Activation & BIOS"

Write-Host "Checking Windows Update status..." -ForegroundColor Yellow
$updates = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5 HotFixID, Description, InstalledOn
$lastUpdateDate = ($updates | Select-Object -First 1).InstalledOn
$updateWarning = $false
if ($lastUpdateDate) {
  $daysSinceUpdate = (New-TimeSpan -Start $lastUpdateDate -End (Get-Date)).Days
  if ($daysSinceUpdate -gt 90) { $updateWarning = $true }
}
else { $daysSinceUpdate = "Unknown" }
Write-Step "Windows Update status"

Write-Host "Collecting startup programs..." -ForegroundColor Yellow
$startupPrograms = Get-CimInstance -ClassName Win32_StartupCommand | Select-Object Name, Command, Location
$startupCount = ($startupPrograms | Measure-Object).Count
Write-Step "Startup programs"

Write-Host "Checking antivirus status..." -ForegroundColor Yellow
$avStatus = $null
try {
  $mp = Get-MpComputerStatus
  $avStatus = [PSCustomObject]@{
    "Real-Time Protection" = $mp.RealTimeProtectionEnabled
    "Antivirus Enabled"    = $mp.AntivirusEnabled
    "Signature Age (days)" = $mp.AntivirusSignatureAge
    "Last Scan"            = $mp.QuickScanEndTime
  }
}
catch { $avStatus = $null }
Write-Step "Antivirus status"

Write-Host "Checking TPM status..." -ForegroundColor Yellow
$tpm = $null
try {
  $tpmInfo = Get-Tpm
  $tpm = [PSCustomObject]@{ "TPM Present" = $tpmInfo.TpmPresent; "TPM Ready" = $tpmInfo.TpmReady; "TPM Enabled" = $tpmInfo.TpmEnabled }
}
catch { $tpm = $null }
Write-Step "TPM status"

Write-Host "Collecting network adapter info..." -ForegroundColor Yellow
$netAdapters = Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed
Write-Step "Network adapters"

Write-Host "Collecting Event logs..." -ForegroundColor Yellow
$criticals = Get-WinEvent -FilterHashtable @{LogName = 'System'; Level = 1; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, ProviderName, Message
$criticalCount = ($criticals | Measure-Object).Count
$errorEvents = Get-WinEvent -FilterHashtable @{LogName = 'System'; Level = 2; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue
$errorCount = ($errorEvents | Measure-Object).Count
$errorGroups = $errorEvents | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object Count, Name
$eventWarning = ($criticalCount -gt 0 -or $errorCount -gt 20)
Write-Step "Event logs"

Write-Host "Building HTML report..." -ForegroundColor Yellow

function ToHtmlTable($data) {
  if (-not $data) { return "<p class='muted'>No data returned (may need admin rights, or not applicable to this device).</p>" }
  return ($data | ConvertTo-Html -Fragment) -join "`n"
}

# --- Build HTML fragments ---
if ($batteryHtml) {
  $batterySection = @"
<div class="card">
  <h2>Battery Report</h2>
  <div class="summary $(if ($batteryHealthWarning) { 'warning' } else { 'ok' })">Battery Health: $batteryHealthStr</div>
  <p class="muted small">Full charge history embedded below. Not applicable on desktop PCs.</p>
  <iframe srcdoc="$batteryHtml" style="width:100%; height:1000px; border:1px solid var(--border-color); border-radius:8px; background:#fff;"></iframe>
</div>
"@
}
else {
  $batterySection = "<div class='card'><h2>Battery Report</h2><p class='muted'>No battery report generated (device may not have a battery).</p></div>"
}

$diskWarningSection = ""
if ($diskWarnings.Count -gt 0) {
  $diskWarningSection = @"
<div class="warningbox">
<b>Disk Health Warnings:</b><ul>$(($diskWarnings | ForEach-Object { "<li>$_</li>" }) -join "`n")</ul>
</div>
"@
}

$updateWarningNote = if ($updateWarning) { " <span class='flag'>(over 90 days ago - check for pending updates)</span>" } else { "" }
$eventWarningNote = if ($eventWarning) { " <span class='flag'>(worth investigating below)</span>" } else { "" }

$criticalBlocks = if ($criticals) {
  ($criticals | ForEach-Object { "<div class='eventblock'><b>$($_.TimeCreated)</b> - $($_.ProviderName) (ID $($_.Id))<pre>$($_.Message)</pre></div>" }) -join "`n"
}
else {
  "<p class='muted'>No Critical events in the last 30 days.</p>"
}

# --- Main HTML Layout ---
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PC Check Report</title>
<style>
  :root {
    --bg-color: #f4f7f6; --card-bg: #ffffff; --text-color: #333333;
    --heading-color: #1a5276; --border-color: #dddddd; --table-stripe: #f9f9f9;
    --summary-bg: #e8f8f5; --summary-border: #1abc9c; --summary-text: #117a65;
    --warning-bg: #fdecea; --warning-border: #e74c3c; --warning-text: #c0392b;
    --button-bg: #1a5276; --button-text: #ffffff;
  }
  [data-theme="dark"] {
    --bg-color: #121212; --card-bg: #1e1e1e; --text-color: #e0e0e0;
    --heading-color: #5dade2; --border-color: #333333; --table-stripe: #252525;
    --summary-bg: #1c2833; --summary-border: #1abc9c; --summary-text: #76d7c4;
    --warning-bg: #2e1a1a; --warning-border: #e74c3c; --warning-text: #f1948a;
    --button-bg: #5dade2; --button-text: #121212;
  }
  body { font-family: Segoe UI, Arial, sans-serif; margin: 0; padding: 40px; background-color: var(--bg-color); color: var(--text-color); transition: background 0.3s; }
  .container { max-width: 1200px; margin: 0 auto; }
  .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
  h1 { color: var(--heading-color); margin: 0; border-bottom: 2px solid var(--heading-color); padding-bottom: 8px; }
  h2 { color: var(--heading-color); margin-top: 0; margin-bottom: 15px; font-size: 20px; }
  h3 { color: var(--heading-color); margin-top: 15px; margin-bottom: 5px; font-size: 16px; }
  .meta { color: var(--text-color); opacity: 0.7; font-size: 13px; margin-bottom: 30px; }
  .card { background: var(--card-bg); padding: 25px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); margin-bottom: 25px; border: 1px solid var(--border-color); }
  .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 25px; }
  @media (max-width: 900px) { .grid-2 { grid-template-columns: 1fr; } }
  
  /* Fixed table layout to prevent long paths from breaking the design */
  table { border-collapse: collapse; width: 100%; margin-top: 5px; table-layout: fixed; }
  th, td { border: 1px solid var(--border-color); padding: 8px 12px; text-align: left; font-size: 14px; word-wrap: break-word; overflow-wrap: break-word; vertical-align: top; }
  /* Give the first column (usually Name/Device) more room to prevent crowding */
  th:first-child, td:first-child { width: 40%; }
  th { background-color: var(--heading-color); color: #fff; }
  tr:nth-child(even) { background-color: var(--table-stripe); }
  
  .muted { color: var(--text-color); opacity: 0.6; font-style: italic; }
  .small { font-size: 12px; }
  .summary { background: var(--summary-bg); border-left: 4px solid var(--summary-border); padding: 10px 15px; margin-bottom: 15px; font-weight: bold; color: var(--summary-text); border-radius: 4px; }
  .summary.warning { background: var(--warning-bg); border-left: 4px solid var(--warning-border); color: var(--warning-text); }
  .warningbox { background: var(--warning-bg); border-left: 4px solid var(--warning-border); color: var(--warning-text); padding: 15px; margin-top: 15px; border-radius: 4px; }
  .flag { color: var(--warning-border); font-weight: bold; }
  .eventblock { background: var(--table-stripe); border-left: 3px solid var(--warning-border); padding: 12px; margin-top: 12px; border-radius: 4px; font-size: 13px; }
  .eventblock pre { white-space: pre-wrap; margin: 6px 0 0 0; font-family: inherit; word-wrap: break-word; }
  pre { background: var(--table-stripe); padding: 15px; border-radius: 5px; border: 1px solid var(--border-color); white-space: pre-wrap; word-wrap: break-word; }
  .toggle-btn { background: var(--button-bg); color: var(--button-text); border: none; padding: 8px 16px; border-radius: 20px; cursor: pointer; font-weight: bold; font-size: 14px; }
  
  /* Footer styles */
  .footer { text-align: center; margin-top: 40px; padding-top: 20px; border-top: 1px solid var(--border-color); color: var(--text-color); opacity: 0.7; font-size: 12px; }
  .footer a { color: var(--heading-color); text-decoration: none; }
</style>
</head>
<body>
<script>
  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }
  const savedTheme = localStorage.getItem('theme') || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  setTheme(savedTheme);
</script>
<div class="container">

  <div class="header">
    <div>
      <h1>PC Check Report</h1>
      <div class="meta">Generated $(Get-Date -Format "yyyy-MM-dd HH:mm")</div>
    </div>
    <button class="toggle-btn" onclick="setTheme(document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark')">Toggle Theme</button>
  </div>

  <div class="grid-2">
    <div class="card">
      <h2>System Overview</h2>
      <pre>$($sysInfo -join "`n")</pre>
      <div class="summary">System Uptime: $uptimeStr</div>
    </div>
    <div class="card">
      <h2>CPU</h2>
      $(ToHtmlTable $cpu)
    </div>
  </div>

  <div class="grid-2">
    <div class="card">
      <h2>RAM Slots</h2>
      <div class="summary">Total RAM: $totalRamStr</div>
      $(ToHtmlTable $ram)
    </div>
    <div class="card">
      <h2>GPU & Display</h2>
      <div class="summary">Total GPU VRAM: $totalVramStr</div>
      <h3 class="small muted">Video Controllers</h3>
      $(ToHtmlTable $gpu)
      <h3 class="small muted">Active Displays</h3>
      $(ToHtmlTable $displays)
    </div>
  </div>

  <div class="card">
    <h2>Storage Health</h2>
    <div class="summary">Total Physical Storage: $totalStorageStr</div>
    $(ToHtmlTable $storage)
    $diskWarningSection
    <h3 class="small muted" style="margin-top:20px;">Storage Reliability (may be blank on some drives)</h3>
    $(ToHtmlTable $reliability)
    <h3 class="small muted" style="margin-top:20px;">Storage Free Space</h3>
    <div class="summary">Total Partition Space: $totalVolSpaceStr | Total Free Space: $totalVolFreeStr</div>
    $(ToHtmlTable $volumes)
  </div>

  <div class="grid-2">
    <div class="card">
      <h2>OS & Security</h2>
      <h3 class="small muted">Windows Activation</h3>
      <pre>$($activation -join "`n")</pre>
      <h3 class="small muted" style="margin-top:15px;">TPM Status</h3>
      $(if ($tpm) { ToHtmlTable $tpm } else { "<p class='muted'>Could not retrieve TPM status.</p>" })
      <h3 class="small muted" style="margin-top:15px;">Antivirus Status</h3>
      $(if ($avStatus) { ToHtmlTable $avStatus } else { "<p class='muted'>Could not retrieve Defender status.</p>" })
    </div>
    <div class="card">
      <h2>BIOS & Updates</h2>
      <h3 class="small muted">BIOS Release Date</h3>
      $(ToHtmlTable $bios)
      <h3 class="small muted" style="margin-top:15px;">Windows Update (Last 5)</h3>
      <div class="summary $(if($updateWarning){'warning'}else{'ok'})">Last update: $lastUpdateDate ($daysSinceUpdate days ago)$updateWarningNote</div>
      $(ToHtmlTable $updates)
    </div>
  </div>

  <div class="card">
    <h2>Network Adapters</h2>
    $(ToHtmlTable $netAdapters)
  </div>

  <div class="card">
    <h2>Recent System Errors (last 30 days)</h2>
    <div class="summary $(if ($eventWarning) { 'warning' } else { 'ok' })">Critical: $criticalCount | Errors: $errorCount $eventWarningNote</div>
    <h3 class="small muted">Critical Events</h3>
    $criticalBlocks
    <h3 class="small muted" style="margin-top:20px;">Error Events by Source</h3>
    <p class="small muted">Grouped by provider so recurring issues stand out. A single source accounting for most errors usually points to one misbehaving driver or service.</p>
    $(ToHtmlTable $errorGroups)
  </div>

  <div class="card">
    <h2>Startup Programs</h2>
    <div class="summary">$startupCount programs launch at startup $(if ($startupCount -gt 15) { "<span class='flag'>(heavy startup load)</span>" } else { "" })</div>
    $(ToHtmlTable $startupPrograms)
  </div>

  $batterySection

  <div class="card" style="background: var(--summary-bg); border-color: var(--summary-border);">
    <h2 style="color: var(--summary-text);">Manual checks still needed:</h2>
    <ul>
      <li>Word/Excel &gt; File &gt; Account &gt; verify Office license status</li>
      <li>Physically inspect screen for dead pixels / uniformity (laptops/monitors)</li>
      <li>Check hinge tightness and creaking (laptops only)</li>
      <li>Test all keys on keyboard</li>
      <li>Test all ports (USB, HDMI, charging)</li>
      <li>Check speaker and webcam</li>
      <li>Check case/fans for dust buildup (desktops)</li>
    </ul>
  </div>

  <div class="footer">
    PC Check v1.0 &middot; <a href="https://github.com/Hans930v/pc-check" style="color:var(--heading-color);">github.com/Hans930v/pc-check</a> &middot; MIT License<br>
    Open-source PowerShell diagnostic tool &middot; This report is read-only, nothing on this device was modified.
  </div>

</div>
</body>
</html>
"@

$html | Out-File -FilePath $htmlPath -Encoding utf8
Write-Step "HTML report built"

Write-Host ""
Write-Host "All steps complete!" -ForegroundColor Cyan
Write-Host "HTML report saved to: $htmlPath" -ForegroundColor Green

Read-Host "Press Enter to open the report and close this window"
Invoke-Item $htmlPath
