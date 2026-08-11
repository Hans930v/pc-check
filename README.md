# PC Check

A portable, single-file diagnostic tool for evaluating a Windows PC or laptop before buying it secondhand. It generates a single clean HTML report covering what actually matters for a resale decision — no installation required.

<table>
<tr>
<td><img src="https://github.com/user-attachments/assets/e32a7717-cbe9-43b1-bc33-8187a2766175" alt="PC Check report — dark mode" width="100%"></td>
<td><img src="https://github.com/user-attachments/assets/66261c81-4c83-4f9c-8c33-4604d1a4de12" alt="PC Check report — light mode" width="100%"></td>
</tr>
</table>

## Why

Buying a used laptop or desktop means trusting the seller's word on battery health, storage condition, and whether anything is quietly failing. This tool pulls that information directly from Windows in a couple of minutes, so either party can run it and share one report — no guesswork required.

It's **read-only**: it doesn't change settings, install anything, or modify the system in any way. Under the hood, it simply runs standard, built-in Windows PowerShell and diagnostic commands ( like `Get-CimInstance`, `systeminfo`, and `powercfg`). The script just gathers that raw data and formats it into a clean, easy-to-read HTML report.

## What it checks

- **CPU** — model, cores, threads, clock speed
- **RAM** — per-slot capacity, speed, total
- **Storage health** — attempts to read wear %, read errors, and health status via Windows Storage Reliability Counters (support varies significantly by hardware/drivers — often returns limited or no data)
- **Free space** — per drive
- **GPU / VRAM** — per-adapter, matched via registry for accurate values
- **Display** — resolution and refresh rate
- **Battery health** — design vs. current full-charge capacity (laptops only)
- **Windows activation** status
- **BIOS** release date
- **Windows Update recency** — flagged if over 90 days since last update
- **Startup program count** — flagged if unusually high
- **Antivirus / Windows Defender** status
- **TPM status** — relevant for Windows 11 eligibility
- **Network adapters**
- **System uptime**
- **Recent system errors** from Event Viewer (last 30 days) — Critical events shown in full; Errors grouped by source

The report also includes a short manual checklist for things no script can check: screen condition, hinge wear, keyboard, ports, speakers, webcam, dust buildup.

Warnings are flagged clearly wherever something's worth a second look:

<img src="https://github.com/user-attachments/assets/77be1426-213b-4724-abc6-6a87d1ab2eea" alt="Battery health warning example" width="800">

## How to run it

1. Download `PC-check.ps1`.
2. **Right-click** the file and select **Run with PowerShell**.

   <img src="https://github.com/user-attachments/assets/a1670aaa-6db4-4cf6-85bf-a87fbf54d97b" alt="Right-click menu showing Run with PowerShell" width="350">

3. Accept the UAC prompt. Administrator rights are needed for full storage and event log data — without them, some sections will show as unavailable rather than failing.
4. Wait roughly 30–60 seconds for data collection to finish. Press **Enter** when prompted, and the report will open automatically in your browser. It's also saved to your Desktop as `pc-check-[timestamp].html`.

> **Note:** If a blue or red PowerShell window flashes and disappears, Windows may be blocking the script. To fix this, open PowerShell as Administrator and run `Set-ExecutionPolicy RemoteSigned`, then try again.

### Run as a one-liner (no download required)

1. Right-click the Start menu and select **Terminal (Admin)** or **Windows PowerShell (Admin)**.

   <img src="https://github.com/user-attachments/assets/38259278-c5e0-49ed-8bca-5f78d84e7e36" alt="Start menu with Terminal (Admin) option highlighted" width="350">

2. Paste the command below and press Enter:

```powershell
irm https://raw.githubusercontent.com/Hans930v/pc-check/main/PC-check.ps1 | iex
```

3. The script will run, generate the report on your Desktop, and open it automatically.

   <img src="https://github.com/user-attachments/assets/273a09c5-4519-41ac-8945-35fb3d7a1d65" alt="One-liner running in an admin PowerShell terminal" width="800">

## Requirements

- Windows 10 or 11
- PowerShell (built in)
- Administrator rights, for complete data

## Notes

- Some fields (storage reliability counters, VRAM) may report "Unknown" — Storage Reliability Counters depend on driver support and aren't available on all hardware (especially some USB/external or older SATA drives); VRAM detection depends on registry values the GPU driver exposes.
- The battery section requires a device with a battery; on desktops, it will note that the check isn't applicable.
- Nothing is uploaded anywhere. The report is a local HTML file, and no data leaves the machine.

## Full disclosure

I am not a professional developer. This script was built entirely through conversational AI prompts — I described what I wanted the tool to check and how the report should look, and AI translated that into the PowerShell and HTML code.

## License

MIT — see [LICENSE](LICENSE).
