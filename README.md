# PC Check

A portable, single-file diagnostic tool for evaluating a Windows PC or laptop before buying it secondhand. Generates one clean HTML report covering the things that actually matter for a resale decision — no installation required.

## Why

Buying a used laptop or PC means trusting a seller's word on battery health, storage condition, and whether anything's quietly failing. This tool pulls that information straight from Windows itself in a couple of minutes, so you (or the seller/shop) can just run it and hand over — or open — one report.

It's read-only. It doesn't change any settings, install anything, or modify the system in any way — it only reads diagnostic data.

## What it checks

- CPU (model, cores, threads, clock speed)
- RAM (per-slot capacity, speed, total)
- Storage health (SMART-based health status, wear %, uncorrected read errors — flagged if concerning)
- Free space per drive
- GPU and VRAM (per-adapter, matched via registry for accurate values)
- Display resolution and refresh rate
- Battery health (design vs. current full-charge capacity, as a percentage) — laptops only
- Windows activation status
- BIOS release date
- Windows Update recency (flags if over 90 days since last update)
- Startup program count (flags if unusually high)
- Antivirus / Windows Defender status
- TPM status (relevant for Windows 11 eligibility)
- Network adapters
- System uptime
- Recent system errors from Event Viewer (last 30 days) — Critical events shown in full, Errors grouped by source

The report also includes a short manual checklist for things no script can check: screen condition, hinge wear, keyboard, ports, speakers, webcam, dust buildup.

## How to run it

1. Download `PC-check.ps1` (e.g., onto a USB drive).
2. **Right-click** `PC-check.ps1` and select **Run with PowerShell**.
3. Accept the UAC prompt (admin rights are needed for full storage and event log data — without it, some sections will show as unavailable rather than failing).
4. Wait ~30–60 seconds for the data collection to finish. Press **Enter** when prompted, and the report will open automatically in your web browser. It is also saved to your Desktop as `pc-check-[timestamp].html`.

*Note: If a blue or red PowerShell window flashes and disappears, Windows might be blocking the script. To fix this, open PowerShell as Administrator and run `Set-ExecutionPolicy RemoteSigned`, then try again.*

## Requirements

- Windows 10 or 11
- PowerShell (built in)
- Administrator rights, for complete data

## Notes

- Some fields (storage reliability counters, VRAM) may report "Unknown" on certain hardware or without admin rights — this is normal and depends on what the manufacturer's drivers expose.
- The battery report needs a device with a battery; on desktops this section will note it's not applicable.
- Nothing is uploaded anywhere — the report is a local HTML file, and no data leaves the machine.

## Full disclosure

I am not a professional developer, and this entire script was "vibe coded"—built entirely through conversational AI prompts. I literally just used prompts to make it. 

I knew what I wanted the tool to check and how the report should look, and AI helped translate those ideas into the actual PowerShell and HTML code.

## License

MIT — see [LICENSE](LICENSE).
