# PC Check

A portable Windows diagnostic tool for evaluating a PC or laptop **before you buy it secondhand**. The main tool is a single PowerShell script that generates a self-contained HTML report with a buyer verdict, hardware condition and capability scores, usage-suitability estimates, and the data behind those results. An optional batch launcher is also provided for users who want to view and temporarily manage the PowerShell execution policy before running the script.

<table>
<tr>
<td><img width="1917" height="918" alt="image" src="https://github.com/user-attachments/assets/5c6237c5-7832-415a-8b0d-f3c883a29668" /></td>
</tr>
</table>

## Why

Buying a used laptop or desktop usually means trusting the seller's word about its battery, hardware, Windows installation, and whether recurring system errors are present. PC Check collects information exposed by Windows and presents it in one report that a buyer or seller can review and share.

**The PowerShell script is designed to be read-only with respect to hardware configuration and personal files.** It queries built-in Windows interfaces and commands such as `Get-CimInstance`, `powercfg`, `Get-PhysicalDisk`, `Get-Volume`, and `Get-WinEvent`, then formats the results as HTML. It creates the report and temporary battery-report files, then attempts to remove those temporary files after reading them. **The report is not uploaded anywhere.**

The optional `run-pc-check.bat` launcher is different: it temporarily changes the **CurrentUser** PowerShell execution policy to `Bypass`, runs PC Check, and attempts to restore the original CurrentUser policy afterward. It does not intentionally change the other policy scopes. See [Using the batch launcher](#option-2-use-the-batch-launcher) and [Execution-policy notes](#execution-policy-notes) before using it.

## What the report tells you

- **Buyer Verdict:** one of *Good Candidate*, *Review Report*, *Caution*, *Investigate Before Buying*, or *Limited Capability*, with a short explanation. It is an automated screening result, not a purchase guarantee.
- **Hardware Condition (0-100):** a heuristic based on repeated WHEA/HAL events, battery health below 70% of design capacity, and recurring graphics/display-driver error events. Generic Critical System events and old Windows update history are reported for review, but are not automatically treated as proof of hardware damage or directly deducted as hardware-condition penalties. Storage SMART health is not assessed.
- **Hardware Capability (0-100):** a rough estimate based on detected RAM capacity, CPU core count, the largest reported VRAM value on a single GPU adapter, and whether storage appears to be HDD-only. Missing CPU, RAM, GPU-memory, or storage data is treated as unknown rather than automatically receiving a hardware deduction.
- **Overall score:** Hardware Condition (60%) and Hardware Capability (40%) combined.
- **Usage suitability:** estimates for everyday use, business/office, programming, video editing, gaming, engineering/CAD, and local AI/ML.
- **Things to Investigate:** a short list of detected findings, with severity labels.
- **Confidence ratings:** each main score includes an indication of how much supporting data was available.
- **System Errors - Last 30 Days:** counts of Critical and Error-level System events, with category counts for WHEA/HAL, disk/storage, and graphics/display-driver events.
- **Detailed System Error Summary:** a bottom-of-report breakdown that groups repeated events by provider, event ID, and level. Each group shows its occurrence count, latest timestamp, sample message, and up to five recent occurrences when expanded.
- **Data Collection Warnings:** identifies information Windows could not provide during the scan.

> **Scores are estimates, not benchmarks.** The capability and suitability estimates use hardware-specification tiers and simple rules; they do not measure actual application performance. CPU/GPU generation and architecture, cooling, power limits, drivers, configuration, and workload can make two systems with similar headline specifications perform very differently. No CPU/GPU stress tests or synthetic performance benchmarks are run.

## What it collects

| Area | Details |
|---|---|
| **System** | Manufacturer, model, operating system, version, build, original install date, and uptime |
| **CPU** | Model, manufacturer, physical cores, logical processors/threads, and reported maximum clock |
| **RAM** | Per-module bank/slot, manufacturer, part number, capacity, speed, and total capacity |
| **Storage devices** | Drive name, device ID, media type, bus type, operational status, and capacity |
| **Free space** | Per-volume drive letter, filesystem, free space, and total volume size |
| **GPU / VRAM** | Per-adapter name, manufacturer, driver version/date, video processor, and VRAM when exposed by the driver |
| **Display** | Active display resolution and refresh rate reported by Windows |
| **Battery** | Design capacity versus current full-charge capacity, plus the embedded Windows battery report when available |
| **Windows activation** | Windows activation/expiration status reported by `slmgr.vbs /xpr` |
| **BIOS** | Manufacturer, version, release date, and serial number |
| **Windows Update** | The five most recent hotfix entries available through `Get-HotFix`; the report flags the newest installed date when it is over 90 days old |
| **Startup programs** | Startup command name, command line, and location; the report flags more than 15 entries as a possible heavy startup load |
| **Security** | Microsoft Defender real-time protection, antivirus status, signature age, last quick/full scan, and TPM presence/readiness/version |
| **Network** | Adapter name, interface description, status, link speed, and MAC address |
| **Event Viewer** | Critical and Error-level events from the Windows **System** log for the last 30 days; category counts for WHEA/HAL, disk/storage, and graphics/display-driver provider matches; grouped event patterns and sample messages |

**Storage-health distinction:** PC Check inventories storage devices and volume capacity, but it does **not** read or score SSD/HDD SMART health, wear percentage, temperature, power-on hours, or remaining drive life. Windows does not expose consistent drive-health telemetry across all drive/controller combinations. Use a dedicated utility such as CrystalDiskInfo to inspect supported SMART data.

The report also includes a **manual inspection checklist** covering the screen, hinges, keyboard, touchpad, ports, audio, webcam, wireless connectivity, fans, chassis condition, battery behavior, Office licensing, and Windows edition. It recommends CrystalDiskInfo, CrystalDiskMark, and MemTest86 for additional checks.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or newer (included with Windows)
- Administrator privileges are recommended for the fullest set of checks. When launched as a `.ps1` file, the script requests elevation through UAC and relaunches itself with a process-scoped execution-policy bypass. The one-liner method must be run from an already elevated PowerShell/Terminal window.

## How to run it

### Option 1: Download and run the PowerShell script (recommended)

1. Download [`PC-check.ps1`](PC-check.ps1).
2. Right-click the file and select **Run with PowerShell**.

   <img src="https://github.com/user-attachments/assets/a1670aaa-6db4-4cf6-85bf-a87fbf54d97b" alt="Right-click menu showing Run with PowerShell" width="350">

3. Accept the UAC prompt. If the first PowerShell window closes, that is expected: once the script has started, it can launch a new elevated PowerShell process with a **process-only** execution-policy bypass.
4. Let the elevated window finish collecting information. Press **Enter** when prompted. The HTML report opens in your browser.

If Windows blocks the script before it starts because of the current execution policy, use the explicit command shown under [Troubleshooting](#troubleshooting) or use the batch launcher.

This is the simplest method and does not intentionally change the saved CurrentUser execution-policy setting. You can also read the `.ps1` file before running it.

### Option 2: Use the batch launcher

The optional [`run-pc-check.bat`](run-pc-check.bat) launcher:

1. Displays the current PowerShell execution policies for all scopes.
2. Saves the existing **CurrentUser** execution policy.
3. Temporarily sets **CurrentUser** to `Bypass`.
4. Runs `PC-check.ps1` from the same folder as the batch file.
5. Attempts to restore the original CurrentUser policy and displays the policy list again for verification.

**Run the batch file from an already elevated Command Prompt or Windows Terminal** if you want it to wait for PC Check to finish before restoring the policy. The PowerShell script can self-elevate by launching a separate process when started without administrator rights; in that situation, the batch parent process may finish and restore the policy before the elevated child process has completed. Running the batch launcher from an elevated terminal avoids that hand-off.

To use it:

1. Keep `run-pc-check.bat` and `PC-check.ps1` in the same folder.
2. Open **Command Prompt (Admin)** or **Windows Terminal (Admin)**.
3. Change directory to the folder containing the two files, then run:

   ```bat
   run-pc-check.bat
   ```

4. Review the policy list and messages. When PC Check finishes, the launcher attempts to restore the original CurrentUser policy and displays the resulting policies.

The batch file includes pauses so you can read its output. If policy restoration fails, it displays the original setting so you can restore it manually.

### Option 3: One-liner (no local script download)

1. Right-click the Start menu and select **Terminal (Admin)** or **Windows PowerShell (Admin)**. The one-liner cannot elevate itself, so the terminal must already be running as administrator.

   <img src="https://github.com/user-attachments/assets/38259278-c5e0-49ed-8bca-5f78d84e7e36" alt="Start menu with Terminal (Admin) option highlighted" width="350">

2. Paste this and press Enter:

   ```powershell
   irm https://raw.githubusercontent.com/Hans930v/pc-check/main/PC-check.ps1 | iex
   ```

3. The report is generated and opens automatically.

   <img src="https://github.com/user-attachments/assets/273a09c5-4519-41ac-8945-35fb3d7a1d65" alt="One-liner running in an admin PowerShell terminal" width="800">

> **Security tip:** Piping a remote script into `iex` executes it immediately. To inspect the code first, open the raw URL in a browser or use Option 1.

## Where the report is saved

| Method | Location |
|---|---|
| Script file (Option 1) | A `PC-Diagnose` folder next to `PC-check.ps1`. If the script is already inside a folder named `PC-Diagnose`, that folder is used. This also works from a USB drive. |
| Batch launcher (Option 2) | The same `PC-Diagnose` folder next to `PC-check.ps1`, because the batch file launches the script from its own location. |
| One-liner (Option 3) | Your Desktop |

If the output folder cannot be created, the script falls back to the Desktop. Files are named using the computer manufacturer, model, and timestamp, for example:

`Dell Inc. Inspiron 5402 PC Check 2026-08-15_14-30-00.html`

## Troubleshooting

**A PowerShell window flashes and disappears.** When the script is launched as a file without administrator rights, it starts an elevated PowerShell process and exits the initial process. Accept the UAC prompt and look for the new elevated window. If it still fails, open PowerShell and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\PC-check.ps1
```

**The one-liner says administrator rights are required.** Close the window and reopen PowerShell or Windows Terminal with **Run as administrator**, then paste the command again.

**The batch launcher reports that policy restoration failed.** Use the original CurrentUser policy printed by the batch file and restore that exact value from an elevated PowerShell window. For example, if the original value was `RemoteSigned`:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

If the original value was `Undefined`, use `Undefined` in place of `RemoteSigned`. A `MachinePolicy` or `UserPolicy` set by an organization can take precedence over CurrentUser and cannot be overridden by this launcher.

## Limitations

- **Storage health is not assessed.** PC Check does not read SMART health, SSD wear percentage, drive temperature, power-on hours, or remaining drive life. Check each drive with CrystalDiskInfo (or the drive manufacturer's own diagnostic utility) before buying. SMART information availability and interpretation can vary by drive and controller.
- **VRAM** is read from driver/registry data and may show `Unknown`, especially for integrated graphics or unsupported drivers. The capability and suitability logic uses the largest reported VRAM value on one adapter; it does not assume VRAM from multiple GPUs can be combined into one shared pool.
- **Event Viewer errors do not prove hardware failure.** Events are grouped by provider, event ID, and level to make recurring patterns easier to inspect. Category counts can overlap, and a single event can have several possible causes.
- **Battery checks** apply only when Windows exposes battery information. A battery report may be unavailable on desktops or unsupported systems.
- **Capability and suitability scores** are estimates based on detected specifications and simple thresholds, not application benchmarks. They do not validate CAD performance, gaming FPS, AI framework compatibility, or sustained performance under load.
- **A clean report is not a guarantee.** The tool does not perform stress testing or physical inspection and cannot reliably detect screen defects, damaged hinges, worn ports, liquid damage, fan noise, or every intermittent fault. Use the manual checklist and inspect the machine in person.
- **Data collection can be incomplete.** Some Windows commands return different information depending on hardware, drivers, Windows version, permissions, and controller support. Missing values are reported as unknown where possible; check the Data Collection Warnings section.
- **Execution-policy note:** the `.ps1` script uses a process-scoped bypass when it relaunches itself. The optional batch launcher temporarily changes the CurrentUser policy and attempts to restore it. If the batch file is interrupted, Windows shuts down unexpectedly, or restoration fails, verify the CurrentUser policy and restore the original value printed by the launcher.

## Full disclosure

I'm not a professional developer. This script was built with help from conversational AI: I described what to check and how the report should look, and AI assisted with the PowerShell and HTML. The scoring rules are heuristic and should be treated as a work in progress. Please review the script before running it and open an issue if you spot a bug or misleading result.

## Contributing

Bug reports and suggestions are welcome. Please open an issue and include your Windows version, the PC Check version, and which report section was affected. Do not post serial numbers, MAC addresses, or other identifying information from a report publicly.

## License

MIT. See [LICENSE](LICENSE).
