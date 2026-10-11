# PC Check

A portable, single-file diagnostic tool for evaluating a Windows PC or laptop **before you buy it secondhand**. It generates one self-contained HTML report (with dark and light modes) containing a buyer verdict, condition and capability scores, and the raw data behind them. No installation required.

<table>
<tr>
<td><img src="https://github.com/user-attachments/assets/e32a7717-cbe9-43b1-bc33-8187a2766175" alt="PC Check report, dark mode" width="100%"></td>
<td><img src="https://github.com/user-attachments/assets/66261c81-4c83-4f9c-8c33-4604d1a4de12" alt="PC Check report, light mode" width="100%"></td>
</tr>
</table>

## Why

Buying a used laptop or desktop usually means trusting the seller's word on battery health, storage condition, and whether anything is quietly failing. PC Check pulls that information straight from Windows in about a minute, so either the buyer or the seller can run it and share a single report.

**It doesn't change your system.** It runs standard built-in Windows commands (`Get-CimInstance`, `powercfg`, `Get-PhysicalDisk`, etc.) and formats the output as HTML. The only things it writes are the report and temporary battery files, which it deletes afterward. **Nothing is uploaded anywhere.**

## What the report tells you

- **Buyer Verdict:** one of *Good Candidate*, *Review Report*, *Caution*, or *Investigate Before Buying*, with a short explanation.
- **Hardware Condition (0-100):** based on storage health warnings, hardware-related WHEA/HAL events, battery wear, critical system events, graphics driver errors, and update history.
- **Hardware Capability (0-100):** based on RAM, CPU core count, GPU memory, and whether storage is HDD-only.
- **Overall score:** Condition (60%) and Capability (40%) combined.
- **Usage suitability:** estimates for everyday use, office, programming, video editing, gaming, engineering/CAD, and local AI/ML.
- **Things to Investigate:** a ranked list of detected issues.
- **Confidence ratings:** each score shows how much data was available to calculate it.

> **The scores are estimates, not benchmarks.** They use RAM, core-count, and VRAM tiers only, and don't account for CPU/GPU generation or architecture. No stress tests or synthetic benchmarks are run. Use the scores to decide what to look at more closely, not as a final verdict.

## What it collects

| Area | Details |
|---|---|
| **System** | Manufacturer, model, OS, version, build, install date, uptime |
| **CPU** | Model, cores, threads, clock speed |
| **RAM** | Per-module slot, manufacturer, part number, capacity, speed, and total |
| **Storage** | Drive type, bus, health status, size; reliability counters (wear, temperature, uncorrected read errors, power-on hours) where supported* |
| **Free space** | Per volume |
| **GPU / VRAM** | Per adapter, VRAM read from the driver registry entries |
| **Display** | Resolution and refresh rate |
| **Battery** | Design vs. current full-charge capacity, plus the full Windows battery report (laptops only) |
| **Windows activation** | Activation / license expiry status |
| **BIOS** | Manufacturer, version, release date, serial number |
| **Windows Update** | Last 5 updates; flagged if the newest is over 90 days old |
| **Startup programs** | Full list; flagged if over 15 |
| **Security** | Defender status and signature age, last scans, TPM presence/readiness/version |
| **Network** | Adapters, status, link speed, MAC address |
| **Event Viewer** | Last 30 days: Critical events in full (up to 10), total error count, plus separate counts for WHEA/HAL, disk/storage, and graphics driver errors |

\*Storage reliability data depends on hardware and driver support. See [Limitations](#limitations).

The report ends with a **manual inspection checklist** (screen, hinges, keyboard, ports, speakers, webcam, fans and dust, Office license, Windows edition) and suggestions for free external tools: CrystalDiskInfo, CrystalDiskMark, and MemTest86.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 or newer (built in)
- Administrator rights. The script asks for them automatically when run as a file.

## How to run it

### Option 1: Download and run (recommended)

1. Download [`PC-check.ps1`](PC-check.ps1).
2. Right-click the file and select **Run with PowerShell**.

   <img src="https://github.com/user-attachments/assets/a1670aaa-6db4-4cf6-85bf-a87fbf54d97b" alt="Right-click menu showing Run with PowerShell" width="350">

3. Accept the UAC prompt. The script relaunches itself as administrator with a temporary, process-only execution policy bypass, so the first window closing is normal.
4. Wait 30-60 seconds, then press **Enter** when prompted. The report opens in your browser.

Downloading first lets you read the script before running it, which is worth doing for any script you didn't write.

### Option 2: One-liner (no download)

1. Right-click the Start menu and select **Terminal (Admin)** or **Windows PowerShell (Admin)**. The one-liner can't elevate itself, so it needs an admin terminal.

   <img src="https://github.com/user-attachments/assets/38259278-c5e0-49ed-8bca-5f78d84e7e36" alt="Start menu with Terminal (Admin) option highlighted" width="350">

2. Paste this and press Enter:

```powershell
   irm https://raw.githubusercontent.com/Hans930v/pc-check/main/PC-check.ps1 | iex
```

3. The report is generated and opens automatically.

   <img src="https://github.com/user-attachments/assets/273a09c5-4519-41ac-8945-35fb3d7a1d65" alt="One-liner running in an admin PowerShell terminal" width="800">

> **Security tip:** Piping a remote script into `iex` runs it immediately. To review it first, open the URL above in your browser, or use Option 1.

### Where the report is saved

| Method | Location |
|---|---|
| File (Option 1) | A `PC-Diagnose` folder next to the script, so it works from a USB stick. If the script is already inside a folder named `PC-Diagnose`, that folder is used. |
| One-liner (Option 2) | Your Desktop |

Files are named like `Dell Inc. Inspiron 5402 PC Check 2026-08-15_14-30-00.html`. If the folder can't be created, the script falls back to the Desktop.

### Troubleshooting

**A PowerShell window flashes and disappears.** Windows may be blocking the script. Open PowerShell and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\PC-check.ps1
```

**The one-liner says administrator rights are required.** Close the window and reopen PowerShell with **Run as administrator**.

## Limitations

- **Storage health is the least reliable section.** Reliability counters aren't supported on many drives (especially USB/external and older SATA). A drive reporting 0% wear with no power-on hours is marked "unverified," since that usually means Windows couldn't read real SMART data. Check suspicious or unreadable drives with CrystalDiskInfo before buying.
- **VRAM** comes from registry values the GPU driver exposes and may show "Unknown," especially for integrated graphics.
- **Event Viewer errors don't prove hardware failure.** They're a reason to look closer.
- **Battery** checks only apply to devices with a battery.
- **A clean report isn't a guarantee.** The tool can't detect physical damage, so pair it with the manual checklist and an in-person inspection.

## Full disclosure

I'm not a professional developer. This script was built entirely through conversational AI prompts: I described what to check and how the report should look, and AI wrote the PowerShell and HTML. Because of that, please review the script before running it and open an issue if you spot a bug.

## Contributing

Bug reports and suggestions are welcome. Please open an issue and include your Windows version and which report section was affected.

## License

MIT. See [LICENSE](LICENSE).
