# PC Check

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6" alt="Platform: Windows 10 and 11">
  <img src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE" alt="PowerShell 5.1 or newer">
  <img src="https://img.shields.io/badge/Portable-Yes-7C3AED" alt="Portable">
  <img src="https://img.shields.io/github/license/Hans930v/pc-check?color=2EA44F" alt="MIT License">
</p>

<p align="center">
  <strong>A portable Windows PC diagnostic and reporting tool for buyers and sellers evaluating used Windows PCs.</strong>
</p>

PC Check automates built-in Windows PowerShell commands and system interfaces to collect hardware, battery, storage, security, and system-event information.

Run one script and get a self-contained HTML report with condition and capability scores, usage-suitability estimates, a buyer verdict, and detailed system information.

<p align="center">
  <img src="https://github.com/user-attachments/assets/5c6237c5-7832-415a-8b0d-f3c883a29668" alt="PC Check HTML report preview" width="100%">
</p>

> [!IMPORTANT]
> **Scores are estimates, not benchmarks, and a clean report is not a guarantee.** See [Limitations](#limitations).

---

## Contents

- [Requirements](#requirements)
- [Safety and privacy](#safety-and-privacy)
  - [What the script does](#what-the-script-does)
  - [Privacy of the report](#privacy-of-the-report)
  - [Inspect the script before running](#inspect-the-script-before-running)
- [How to run it](#how-to-run-it)
- [Where the report is saved](#where-the-report-is-saved)
- [What the report tells you](#what-the-report-tells-you)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Full disclosure](#full-disclosure)
- [Contributing](#contributing)
- [License](#license)

---

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or newer (included with Windows)
- Administrator privileges are recommended for the fullest set of checks. When launched as a `.ps1` file, the script requests elevation through UAC and relaunches itself with a process-scoped execution-policy bypass. The one-liner method must be run from an already elevated PowerShell/Terminal window.

## Safety and privacy

### What the script does

The PowerShell script is designed to be **read-only with respect to hardware configuration and personal files**. It queries built-in Windows interfaces and commands such as `Get-CimInstance`, `powercfg`, `Get-PhysicalDisk`, `Get-Volume`, and `Get-WinEvent`, then formats the results as HTML. It creates the report and temporary battery-report files, then attempts to remove the temporary files after reading them.

> [!IMPORTANT]
> **The report is not uploaded anywhere.** It is generated locally and is not sent to an external server.

### Privacy of the report

The generated report includes certain identifying information, such as BIOS serial numbers and network MAC addresses. Other information, including startup command lines, file locations, and Windows event messages, may also contain personal details.

Review the report before sharing it. Avoid publishing complete diagnostic reports in public repositories or forums.

> [!WARNING]
> A diagnostic report can expose information about the computer and its user. Review it before sending it to someone else.

### Inspect the script before running

You can perform a basic text search for commands commonly associated with downloading or executing external code, modifying Windows settings, or creating scheduled tasks. This does not replace reading and understanding the script.

1. Put `PC-check.ps1` in a folder, such as `C:\Users\YourName\Downloads`.
2. Open PowerShell in that folder. Either type `powershell` in the File Explorer address bar and press Enter, or open PowerShell manually and run:

   ```powershell
   cd "C:\Users\YourName\Downloads"
   ```

   Administrator privileges are not required because this check only reads the file.

3. Confirm the script is present:

   ```powershell
   dir PC-check.ps1
   ```

4. Run the following search as a single line:

   ```powershell
   Select-String -Path .\PC-check.ps1 -Pattern 'Invoke-WebRequest|Invoke-RestMethod|\birm\b|\biwr\b|WebClient|Start-BitsTransfer|Invoke-Expression|\biex\b|EncodedCommand|FromBase64String|Add-MpPreference|Set-MpPreference|ScheduledTask|Set-ItemProperty|reg(\.exe)?\s+add|Net\.Sockets|Start-Process|New-Object\s+Net|Set-ExecutionPolicy'
   ```

**Reading the results**

- **No output:** None of the searched patterns were found.
- **Matching lines:** Each result shows the filename, line number, and matching line. Read the surrounding code to understand why it matched.

A match does not automatically mean something is malicious. `Start-Process` is expected because the script uses it for self-elevation, and some matches may appear in comments or text rather than executable code.

> [!NOTE]
> This is only a basic text-based screening step. Obfuscated or dynamically constructed commands may not match these patterns. **No output does not guarantee that a script is safe.**

**Verifying a downloaded copy**

A SHA-256 checksum can help confirm that a downloaded file matches a specific published version. When a checksum file is provided with a PC Check release, compare its expected hash with the result of:

```powershell
Get-FileHash .\PC-check.ps1 -Algorithm SHA256
```

A matching hash confirms that the file matches the published checksum. It does not prove that the script is safe. Make sure the checksum belongs to the exact release you downloaded.

---

## How to run it

Haven't inspected the script yet? See [Inspect the script before running](#inspect-the-script-before-running) above.

### Option 1: Download and run the script (recommended)

1. Download [`PC-check.ps1`](PC-check.ps1).
2. Right-click the file and select **Run with PowerShell**.

   <img src="https://github.com/user-attachments/assets/a1670aaa-6db4-4cf6-85bf-a87fbf54d97b" alt="Right-click menu showing Run with PowerShell" width="350">

3. Accept the UAC prompt. If the first PowerShell window closes, that is expected: the script launches a new elevated PowerShell process with a **process-only** execution-policy bypass.
4. Let the elevated window finish collecting information. Press **Enter** when prompted. The HTML report opens in your browser.

This is the simplest method and does not intentionally change the saved CurrentUser execution-policy setting. If Windows blocks the script before it starts, see [Troubleshooting](#troubleshooting).

### Option 2: One-liner (no local script download)

1. Right-click the Start menu and select **Terminal (Admin)** or **Windows PowerShell (Admin)**. The one-liner cannot elevate itself, so the terminal must already be running as administrator.

   <img src="https://github.com/user-attachments/assets/38259278-c5e0-49ed-8bca-5f78d84e7e36" alt="Start menu with Terminal (Admin) option highlighted" width="350">

2. Paste this and press Enter:

   ```powershell
   irm https://raw.githubusercontent.com/Hans930v/pc-check/main/PC-check.ps1 | iex
   ```

3. The report is generated and opens automatically.

   <img src="https://github.com/user-attachments/assets/273a09c5-4519-41ac-8945-35fb3d7a1d65" alt="One-liner running in an admin PowerShell terminal" width="800">

> [!CAUTION]
> Piping a remote script into `iex` executes it immediately. To inspect the code first, open the raw URL in a browser or use Option 1.

### Option 3: Batch launcher (optional)

<details>
<summary>Show batch launcher details</summary>

The optional [`run-pc-check.bat`](run-pc-check.bat) launcher:

1. Displays the current PowerShell execution policies for all scopes.
2. Saves the existing **CurrentUser** execution policy.
3. Temporarily sets **CurrentUser** to `Bypass`.
4. Runs `PC-check.ps1` from the same folder as the batch file.
5. Attempts to restore the original CurrentUser policy and displays the policy list again for verification.

It does not intentionally modify other policy scopes. If it is interrupted, or if restoration fails, the policy may remain changed.

**Run it from an already elevated Command Prompt or Windows Terminal.** If PC Check is started without administrator rights, the script self-elevates by launching a separate process. The batch parent process may then finish and restore the policy before the elevated child process has completed. Running from an elevated terminal avoids that hand-off.

To use it:

1. Keep `run-pc-check.bat` and `PC-check.ps1` in the same folder.
2. Open **Command Prompt (Admin)** or **Windows Terminal (Admin)**.
3. Change directory to the folder containing the two files, then run:

   ```bat
   run-pc-check.bat
   ```

4. Review the policy list and messages. When PC Check finishes, the launcher attempts to restore the original CurrentUser policy and displays the resulting policies.

The batch file includes pauses so you can read its output. If restoration fails, it displays the original setting so you can restore it manually (see [Troubleshooting](#troubleshooting)).

</details>

---

## Where the report is saved

| Method | Location |
|---|---|
| Script file (Option 1) | A `PC-Diagnose` folder next to `PC-check.ps1`. If the script is already inside a folder named `PC-Diagnose`, that folder is used. Also works from a USB drive. |
| One-liner (Option 2) | Your Desktop |
| Batch launcher (Option 3) | The same `PC-Diagnose` folder next to `PC-check.ps1` |

If the output folder cannot be created, the script falls back to the Desktop. Files are named using the computer manufacturer, model, and timestamp, for example:

`Dell Inc. Inspiron 5402 PC Check 2026-08-15_14-30-00.html`

---

## What the report tells you

### Buyer verdicts

The report assigns one of five verdicts:

<p align="center">
  <img src="https://img.shields.io/badge/Good%20Candidate-2EA44F?style=for-the-badge" alt="Good Candidate">
  <img src="https://img.shields.io/badge/Review%20Report-0078D4?style=for-the-badge" alt="Review Report">
  <img src="https://img.shields.io/badge/Caution-E5A000?style=for-the-badge" alt="Caution">
  <img src="https://img.shields.io/badge/Investigate%20Before%20Buying-E67E22?style=for-the-badge" alt="Investigate Before Buying">
  <img src="https://img.shields.io/badge/Limited%20Capability-D73A49?style=for-the-badge" alt="Limited Capability">
</p>

These are automated screening results, not purchase guarantees.

### Report sections

| Section | What it shows |
|---|---|
| **Buyer Verdict** | One of the five verdicts above, with a short explanation. |
| **Hardware Condition (0-100)** | Heuristic based on repeated WHEA/HAL events, battery health below 70% of design capacity, and recurring graphics/display-driver error events. Generic Critical System events and old Windows update history are reported for review but not deducted as hardware penalties. |
| **Hardware Capability (0-100)** | Rough estimate from detected RAM capacity, CPU core count, the largest reported VRAM on a single GPU adapter, and whether storage appears to be HDD-only. Missing data is treated as unknown rather than penalized. |
| **Overall score** | Hardware Condition (60%) and Hardware Capability (40%) combined. |
| **Usage suitability** | Estimates for everyday use, business/office, programming, video editing, gaming, engineering/CAD, and local AI/ML. |
| **Things to Investigate** | Short list of detected findings, with severity labels. |
| **Confidence ratings** | How much supporting data was available for each main score. |
| **System Errors (last 30 days)** | Counts of Critical and Error-level System events, with category counts for WHEA/HAL, disk/storage, and graphics/display-driver events. |
| **Detailed System Error Summary** | Repeated events grouped by provider, event ID, and level, with occurrence count, latest timestamp, sample message, and up to five recent occurrences when expanded. |
| **Data Collection Warnings** | Information Windows could not provide during the scan. |

The report also includes a **manual inspection checklist** (screen, hinges, keyboard, touchpad, ports, audio, webcam, wireless, fans, chassis condition, battery behavior, Office licensing, Windows edition) and recommends CrystalDiskInfo, CrystalDiskMark, and MemTest86 for additional checks.

<details>
<summary>Full list of what PC Check collects</summary>

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
| **Windows activation** | Activation/expiration status reported by `slmgr.vbs /xpr` |
| **BIOS** | Manufacturer, version, release date, and serial number |
| **Windows Update** | The five most recent hotfix entries from `Get-HotFix`; flags the newest installed date when it is over 90 days old |
| **Startup programs** | Startup command name, command line, and location; flags more than 15 entries as a possible heavy startup load |
| **Security** | Microsoft Defender real-time protection, antivirus status, signature age, last quick/full scan, and TPM presence/readiness/version |
| **Network** | Adapter name, interface description, status, link speed, and MAC address |
| **Event Viewer** | Critical and Error-level events from the Windows **System** log for the last 30 days; category counts for WHEA/HAL, disk/storage, and graphics/display-driver provider matches; grouped event patterns and sample messages |

</details>

---

## Limitations

### About the scores

- **Scores are estimates, not benchmarks.** Capability and suitability estimates use hardware-specification tiers and simple thresholds. They do not measure application performance, and they do not validate CAD performance, gaming FPS, AI framework compatibility, or sustained performance under load.
- CPU/GPU generation and architecture, cooling, power limits, drivers, configuration, and workload can make two systems with similar headline specifications perform very differently.
- **No stress tests or synthetic benchmarks are run.**

### About what is (and is not) checked

- **Storage health is not assessed.** PC Check inventories storage devices and volume capacity, but does not read or score SMART health, SSD/HDD wear percentage, temperature, power-on hours, or remaining drive life. Windows does not expose consistent drive-health telemetry across all drive/controller combinations. Check each drive with CrystalDiskInfo (or the manufacturer's diagnostic utility) before buying; SMART availability and interpretation vary by drive and controller.
- **VRAM** is read from driver/registry data and may show `Unknown`, especially for integrated graphics or unsupported drivers. Logic uses the largest reported VRAM on one adapter; it does not assume VRAM from multiple GPUs forms a single pool.
- **Event Viewer errors do not prove hardware failure.** Events are grouped by provider, event ID, and level to make recurring patterns easier to inspect. Category counts can overlap, and a single event can have several possible causes.
- **Battery checks** apply only when Windows exposes battery information. A report may be unavailable on desktops or unsupported systems.
- **A clean report is not a guarantee.** The tool does not perform stress testing or physical inspection and cannot reliably detect screen defects, damaged hinges, worn ports, liquid damage, fan noise, or every intermittent fault. Use the manual checklist and inspect the machine in person.
- **Data collection can be incomplete.** Results vary with hardware, drivers, Windows version, permissions, and controller support. Missing values are reported as unknown where possible; check the Data Collection Warnings section.

### About execution policy

- The `.ps1` script uses a process-scoped bypass when it relaunches itself.
- The optional batch launcher temporarily changes the CurrentUser policy and attempts to restore it. If the batch file is interrupted, Windows shuts down unexpectedly, or restoration fails, verify the CurrentUser policy and restore the original value printed by the launcher.

---

## Troubleshooting

<details>
<summary>A PowerShell window flashes and disappears</summary>

When the script is launched as a file without administrator rights, it starts an elevated PowerShell process and exits the initial process. Accept the UAC prompt and look for the new elevated window. If it still fails, open PowerShell and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\PC-check.ps1
```

</details>

<details>
<summary>The one-liner says administrator rights are required</summary>

Close the window and reopen PowerShell or Windows Terminal with **Run as administrator**, then paste the command again.

</details>

<details>
<summary>The batch launcher reports that policy restoration failed</summary>

Use the original CurrentUser policy printed by the batch file and restore that exact value from an elevated PowerShell window. For example, if the original value was `RemoteSigned`:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

If the original value was `Undefined`, use `Undefined` in place of `RemoteSigned`. A `MachinePolicy` or `UserPolicy` set by an organization can take precedence over CurrentUser and cannot be overridden by this launcher.

</details>

---

## Full disclosure

I'm not a professional developer. This script was built with help from conversational AI: I described what to check and how the report should look, and AI assisted with the PowerShell and HTML. The scoring rules are heuristic and should be treated as a work in progress. Please review the script before running it and open an issue if you spot a bug or misleading result.

## Contributing

Bug reports and suggestions are welcome. Please open an issue and include your Windows version, the PC Check version, and which report section was affected. Do not post serial numbers, MAC addresses, or other identifying information from a report publicly.

## License

MIT. See [LICENSE](LICENSE).
