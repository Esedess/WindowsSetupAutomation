# 🛠 Automatic Software Installer for Windows

Welcome! This tool will help you quickly install popular programs, activate Windows/Office, and configure the system with minimal effort and maximum automation.

---

## 📦 Main Features

- Installation of popular programs (Chrome, 7-Zip, Office, etc.)
- Activation of Windows and Office
- Configuration of UAC and firewall settings
- Auto-start after 20 seconds with progress indication
- Logging of all actions for easy tracking

---

## 🚀 Quick Start

1. **Download and extract the archive**  
   Download the tool's archive and extract it to a convenient location.
2. **Run `StartGUI.cmd`**  
   Right-click → Select "Run as Administrator."
3. **Select programs and options**  
   Check the required options in the opened window.
4. **Start the installation**  
   Click "Install Selected" or just wait 20 seconds — the script will start automatically.

> 💡 **Tip**: If you don’t want to wait for auto-start, launch the installation manually!

---

## ⚙️ Adding New Programs

Want to install something custom? Here's a step-by-step guide:

### Step 1: Prepare Files
1. Create a folder in the `apps` directory with the program's name.  
   Example: `apps/Notepad++`
2. Place the installation file inside this folder.  
   Supported formats: `.exe`, `.msi`, `.bat`.

### Step 2: Create the Installation Script
1. Create a file `ProgramName.ps1` in the program's folder.  
   Example: `apps/Notepad++/Notepad++.ps1`
2. Copy and customize this template:

```powershell
   param(
       [string]$RootPath = $PSScriptRoot,
       [string]$LogPath
   )

   $dirName = "Notepad++"          # Program name
   $installFile = "npp.8.6.7.exe"  # Exact installer filename
   $Arguments = "/S"               # Silent installation parameters

   function Write-Log {
       param($message)
       "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - [$dirName] $message" | Out-File $LogPath -Append -Encoding UTF8
   }

   try {
       Write-Log "Starting installation"
       $process = Start-Process "$RootPath\$installFile" -ArgumentList $Arguments -Verb RunAs -PassThru -Wait
       if ($process.ExitCode -eq 0) {
           Write-Log "Success! Code: $($process.ExitCode)"
       } else {
           throw "Error. Code: $($process.ExitCode)"
       }
   }
   catch {
       Write-Log "Failure: $_"
       throw
   }
```

3. Specify the correct values for `$installFile` and `$Arguments`.

### Step 3: Update Configuration
Open the `installer_config.json` file and add the program to the list:

```json
"Programs": [
    ...,
    "Notepad++"
]
```

🔍 Tip: You can find silent installation parameters in the "Installation Parameters" section below.

---

## Setting Up Auto-Run for the Script After Windows Installation

To automatically launch your script after installing Windows, you can use the [ntlite](https://www.ntlite.com/download/) program to add a startup command to your ISO that runs after the first login. This will allow the `main.ps1` script to run from a USB drive or ISO after the system installation is complete.

For a smoother automation process, it is recommended to disable UAC via NTLite and re-enable it after the installation is finished.

#### Command Example I Use:

```bash
timeout 180 && powershell -nologo -noninteractive -windowStyle hidden -noprofile -executionpolicy bypass -Command "$scriptDrive = Get-Volume -FileSystemLabel 'YOUR_LABEL'; $drive = $scriptDrive.DriveLetter; powershell  -nologo -noninteractive -windowStyle hidden -noprofile -executionpolicy bypass -file \"$drive`:\YOUR_PATH\main.ps1""
```

- Replace **YOUR_LABEL** with your USB drive or CD label.
- Replace **YOUR_PATH** with the path to `main.ps1`.

There may be other ways to enable auto-run as well.

---

## 🔄 Updating Programs

To update a program:
1. Replace the installation file in the program's folder.  
   Example: `apps/7-Zip/7z2409-x64.exe` → `7z2500-x64.exe`.

2. If necessary, update the script:  
   - Change `$installFile` to the new filename.  
   - Check `$Arguments` if the installation parameters have changed.  
   Example: `$Arguments = "/S /D=C:\Program Files\7-Zip"`.

---

## 🛠 Installation Parameters

Not sure what arguments to use? Here are some tips:

| File Type | Example Arguments      | Where to Find Info            |
|-----------|------------------------|-------------------------------|
| `.exe`    | `/SILENT`, `/VERYSILENT`| [silentinstall.org](https://silentinstall.org) |
| `.msi`    | `/qn`, `/norestart`    | Run `msiexec /?` in the command prompt |
| `.bat`    | No parameters required | —                             |

---

## ❗ Important

- **Administrator Rights**: Always run the script as an administrator.
- **Logs**: Logs are stored on the desktop in `InstallLog.txt`.  
  Path: `C:\Users\YOUR_USERNAME\Desktop\InstallLog.txt`.
- **Errors**: If something goes wrong, check the exit code in the logs.

---

## 🆘 Support

Having issues?  
- Check the logs in `InstallLog.txt`.  
- Google PowerShell errors — this often helps.  
- If you're completely stuck, contact me, and we’ll figure it out together!

---

## 🌐 Useful Links

- [Silent Install HQ](https://silentinstall.org) — Silent installation parameters.
- [PowerShell Docs](https://docs.microsoft.com/powershell) — PowerShell documentation.
- [GitHub Issues](https://github.com/Esedess/WindowsSetupAutomation/issues) — Report issues or suggest improvements.
