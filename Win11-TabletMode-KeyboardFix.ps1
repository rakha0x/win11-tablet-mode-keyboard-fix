# Win11-TabletMode-KeyboardFix.ps1 — fix dead keyboard/touchpad on 2-in-1 laptops stuck in tablet mode, touch-taskbar on/off, and copy diagnostics.
# Double-click Run-Win11-TabletMode-KeyboardFix.bat and a window appears, just press buttons.
# PowerShell 5.1 compatible (ships with Windows 11). Admin is ONLY required for the Fix Keyboard button.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$advPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$expPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Dw([string]$Path, [string]$Name) {
  try { (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name }
  catch { $null }
}

function Get-SensorState {
  $patterns = @('*Integrated Sensor*', '*Intel*Sensor*', '*ISH*', '*Sensor Hub*', '*Accelerometer*')
  $seen = @{}
  $results = @()
  foreach ($p in $patterns) {
    try {
      $found = Get-PnpDevice -FriendlyName $p -ErrorAction SilentlyContinue
      if ($found) {
        foreach ($d in $found) {
          if ($d.InstanceId -and -not $seen.ContainsKey($d.InstanceId)) {
            $seen[$d.InstanceId] = $true
            $results += $d
          }
        }
      }
    } catch {}
  }
  if ($results.Count -eq 0) { return $null }
  return $results
}

function Get-ProblemCode([string]$InstanceId) {
  try {
    if ([string]::IsNullOrWhiteSpace($InstanceId)) { return $null }
    $prop = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop
    if ($null -ne $prop) {
      $val = if ($prop -is [array]) { $prop[0].Data } else { $prop.Data }
      if ($null -ne $val) { return [int]$val }
    }
    return $null
  } catch {
    return $null
  }
}
function Get-ToolDiagnostics {
  $lines = @()
  $lines += ('Timestamp: {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date))

  # 1. OS caption + build
  try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $caption = if ($os.Caption) { $os.Caption.Trim() } else { 'Windows' }
    $build = if ($os.BuildNumber) { $os.BuildNumber } else { 'Unknown' }
    $lines += "OS: $caption (Build $build)"
  } catch {
    $lines += "OS: Error ($($_.Exception.Message))"
  }

  # 2. Admin status
  try {
    $isAdmin = if (Test-Admin) { 'yes' } else { 'no' }
    $lines += "Admin: $isAdmin"
  } catch {
    $lines += "Admin: Error ($($_.Exception.Message))"
  }

  # 3. Sensors
  try {
    $sensorDevs = Get-SensorState
    if ($sensorDevs) {
      foreach ($s in $sensorDevs) {
        $code = Get-ProblemCode $s.InstanceId
        $codeStr = if ($null -ne $code) { $code } else { 'none' }
        $name = if ($s.FriendlyName) { $s.FriendlyName } elseif ($s.Name) { $s.Name } else { $s.InstanceId }
        $status = if ($s.Status) { $s.Status } else { 'Unknown' }
        $lines += "SENSOR: $name | Status=$status | Code=$codeStr"
      }
    } else {
      $lines += "SENSOR: none found"
    }
  } catch {
    $lines += "SENSOR: Error ($($_.Exception.Message))"
  }

  # 4. Raw registry posture and taskbar values
  try {
    $slate = Get-Dw 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'ConvertibleSlateMode'
    $slateStr = if ($null -ne $slate) { $slate } else { 'null' }
    $lines += "ConvertibleSlateMode: $slateStr"

    $pos = Get-Dw $expPath 'TabletPostureTaskbar'
    $posStr = if ($null -ne $pos) { $pos } else { 'null' }
    $lines += "TabletPostureTaskbar: $posStr"

    $exp = Get-Dw $advPath 'ExpandableTaskbar'
    $expStr = if ($null -ne $exp) { $exp } else { 'null' }
    $lines += "ExpandableTaskbar: $expStr"
  } catch {
    $lines += "Registry: Error ($($_.Exception.Message))"
  }

  # 5. Keyboard devices
  try {
    $kbDevs = @(Get-PnpDevice -Class Keyboard -ErrorAction Stop)
    if ($kbDevs.Count -gt 0) {
      foreach ($k in $kbDevs) {
        $code = Get-ProblemCode $k.InstanceId
        $codeStr = if ($null -ne $code) { $code } else { 'none' }
        $name = if ($k.FriendlyName) { $k.FriendlyName } elseif ($k.Name) { $k.Name } else { $k.InstanceId }
        $status = if ($k.Status) { $k.Status } else { 'Unknown' }
        $lines += "KEYBOARD: $name | Status=$status | Code=$codeStr"
      }
    } else {
      $lines += "KEYBOARD: none found"
    }
  } catch {
    $lines += "KEYBOARD: Error ($($_.Exception.Message))"
  }

  # 6. GPIO / Lid / Serial IO devices
  try {
    $gpioPatterns = @('*GPIO*', '*Lid*', '*Serial IO*')
    $seenGpio = @{}
    $gpioDevs = @()
    foreach ($p in $gpioPatterns) {
      try {
        $found = @(Get-PnpDevice -FriendlyName $p -ErrorAction SilentlyContinue)
        foreach ($d in $found) {
          $key = if ($d.InstanceId) { $d.InstanceId } else { $d.FriendlyName }
          if ($key -and -not $seenGpio.ContainsKey($key)) {
            $seenGpio[$key] = $true
            $gpioDevs += $d
          }
        }
      } catch {}
    }
    if ($gpioDevs.Count -gt 0) {
      foreach ($g in $gpioDevs) {
        $code = Get-ProblemCode $g.InstanceId
        $codeStr = if ($null -ne $code) { $code } else { 'none' }
        $name = if ($g.FriendlyName) { $g.FriendlyName } elseif ($g.Name) { $g.Name } else { $g.InstanceId }
        $status = if ($g.Status) { $g.Status } else { 'Unknown' }
        $lines += "GPIO/LID: $name | Status=$status | Code=$codeStr"
      }
    } else {
      $lines += "GPIO/LID: none found"
    }
  } catch {
    $lines += "GPIO/LID: Error ($($_.Exception.Message))"
  }

  return [string[]]$lines
}


function Write-Log([string]$msg) {
  $txtLog.AppendText(('[{0:HH:mm:ss}] {1}' -f (Get-Date), $msg) + "`r`n")
}

# ---------- Form ----------
$frm = New-Object Windows.Forms.Form
$frm.Text = 'Win11 Tablet Mode Keyboard Fix'
$frm.Size = New-Object Drawing.Size(480, 682)

$frm.StartPosition = 'CenterScreen'
$frm.FormBorderStyle = 'FixedDialog'
$frm.MaximizeBox = $false
$frm.Font = New-Object Drawing.Font('Segoe UI', 9)

$y = 12
$lblTitle = New-Object Windows.Forms.Label
$lblTitle.Text = 'Win11 Tablet Mode Keyboard Fix — no terminal needed'
$lblTitle.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object Drawing.Point(14, $y)
$frm.Controls.Add($lblTitle)
$y += 32

$lblAdmin = New-Object Windows.Forms.Label
$lblAdmin.AutoSize = $true
$lblAdmin.Location = New-Object Drawing.Point(14, $y)
$frm.Controls.Add($lblAdmin)
$y += 24

function Update-AdminLabel {
  if (Test-Admin) { $lblAdmin.Text = 'Mode: Administrator (all buttons work)'; $lblAdmin.ForeColor = [Drawing.Color]::Green }
  else { $lblAdmin.Text = 'Mode: standard — the Fix Keyboard button needs admin'; $lblAdmin.ForeColor = [Drawing.Color]::DarkOrange }
}

$grp = New-Object Windows.Forms.GroupBox
$grp.Text = 'Status (auto-detected)'
$grp.Location = New-Object Drawing.Point(14, $y)
$grp.Size = New-Object Drawing.Size(438, 110)
$frm.Controls.Add($grp)

$lblSensor = New-Object Windows.Forms.Label
$lblSensor.AutoSize = $true
$lblSensor.Location = New-Object Drawing.Point(12, 24)
$grp.Controls.Add($lblSensor)

$lblSlate = New-Object Windows.Forms.Label
$lblSlate.AutoSize = $true
$lblSlate.Location = New-Object Drawing.Point(12, 48)
$grp.Controls.Add($lblSlate)

$lblTaskbar = New-Object Windows.Forms.Label
$lblTaskbar.AutoSize = $true
$lblTaskbar.Location = New-Object Drawing.Point(12, 72)
$grp.Controls.Add($lblTaskbar)

function Update-Status {
  $devs = Get-SensorState
  $bad = @($devs | Where-Object { $_.Status -ne 'OK' })
  if (-not $devs) { $lblSensor.Text = 'Sensor: not found'; $lblSensor.ForeColor = [Drawing.Color]::Gray }
  elseif ($bad.Count -eq 0) { $lblSensor.Text = 'Sensor: OK — keyboard should work'; $lblSensor.ForeColor = [Drawing.Color]::Green }
  else {
    $code = Get-ProblemCode $bad[0].InstanceId
    $codeSuffix = if ($null -ne $code) { " (Code $code)" } else { '' }
    $lblSensor.Text = 'Sensor: ' + $bad[0].Status + $codeSuffix + ' — keyboard may be dead!'
    $lblSensor.ForeColor = [Drawing.Color]::Red
  }

  $slate = Get-Dw 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'ConvertibleSlateMode'
  if ($slate -eq 0) { $lblSlate.Text = 'Windows posture: TABLET (built-in keyboard disabled)'; $lblSlate.ForeColor = [Drawing.Color]::Red }
  elseif ($slate -eq 1) { $lblSlate.Text = 'Windows posture: LAPTOP (normal)'; $lblSlate.ForeColor = [Drawing.Color]::Green }
  else { $lblSlate.Text = 'Windows posture: unreadable'; $lblSlate.ForeColor = [Drawing.Color]::Gray }

  $pos = Get-Dw $expPath 'TabletPostureTaskbar'
  if ($pos -eq 1) { $lblTaskbar.Text = 'Taskbar: forced TABLET'; $lblTaskbar.ForeColor = [Drawing.Color]::Blue }
  elseif ($pos -eq 0) { $lblTaskbar.Text = 'Taskbar: forced DESKTOP'; $lblTaskbar.ForeColor = [Drawing.Color]::Blue }
  else { $lblTaskbar.Text = 'Taskbar: AUTO (follows posture)'; $lblTaskbar.ForeColor = [Drawing.Color]::Gray }
}
$y += 118

$btnRefresh = New-Object Windows.Forms.Button
$btnRefresh.Text = 'Refresh Status'
$btnRefresh.Location = New-Object Drawing.Point(14, $y)
$btnRefresh.Size = New-Object Drawing.Size(438, 32)
$btnRefresh.Add_Click({ try { Update-Status; Write-Log 'Status refreshed.' } catch { Write-Log ('FAILED (refresh): ' + $_.Exception.Message) } })
$frm.Controls.Add($btnRefresh)
$y += 42

$btnFix = New-Object Windows.Forms.Button
$btnFix.Text = 'Fix Keyboard (enable sensor)'
$btnFix.Location = New-Object Drawing.Point(14, $y)
$btnFix.Size = New-Object Drawing.Size(438, 36)
$btnFix.BackColor = [Drawing.Color]::LightGreen
$btnFix.Add_Click({
  if (-not (Test-Admin)) {
    $r = [Windows.Forms.MessageBox]::Show('Admin rights required. Relaunch this tool as admin now?', 'Admin Required', 'YesNo', 'Warning')
    if ($r -eq 'Yes') {
      Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSCommandPath" -Verb RunAs
      $frm.Close()
    }
    return
  }
  try {
    $candidates = Get-SensorState
    if (-not $candidates) {
      Write-Log 'No sensor device found matching known patterns.'
      Write-Log 'Guidance (no sensor found): In Device Manager, select View > Show hidden devices. Look under Sensors for disabled or disconnected hardware. If missing, reinstall the vendor sensor driver.'
      Update-Status
      return
    }

    foreach ($d in $candidates) {
      $code = Get-ProblemCode $d.InstanceId
      $codeStr = if ($null -ne $code) { $code } else { 'none' }
      $name = if ($d.FriendlyName) { $d.FriendlyName } else { $d.InstanceId }
      Write-Log ('{0} | Status={1} | Code={2}' -f $name, $d.Status, $codeStr)
    }

    $nonOk = @($candidates | Where-Object { $_.Status -ne 'OK' })
    if ($nonOk.Count -gt 0) {
      foreach ($d in $nonOk) {
        try {
          $name = if ($d.FriendlyName) { $d.FriendlyName } else { $d.InstanceId }
          Write-Log ('Enabling: ' + $name + ' ...')
          Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
        } catch {
          Write-Log ('FAILED to enable ' + $name + ': ' + $_.Exception.Message)
        }
      }
      Start-Sleep 3
    } else {
      Write-Log 'All candidate sensors already report Status=OK.'
    }

    $afterDevs = Get-SensorState
    if (-not $afterDevs) {
      Write-Log 'No sensor device found after refresh.'
      Write-Log 'Guidance (no sensor found): In Device Manager, select View > Show hidden devices. Look under Sensors for disabled or disconnected hardware. If missing, reinstall the vendor sensor driver.'
      Update-Status
      return
    }

    foreach ($d in $afterDevs) {
      $code = Get-ProblemCode $d.InstanceId
      $codeStr = if ($null -ne $code) { $code } else { 'none' }
      $name = if ($d.FriendlyName) { $d.FriendlyName } else { $d.InstanceId }
      Write-Log ('After: {0} | Status={1} | Code={2}' -f $name, $d.Status, $codeStr)
    }
    Update-Status

    $afterBad = @($afterDevs | Where-Object { $_.Status -ne 'OK' })
    if ($afterBad.Count -gt 0) {
      $hasCode10 = $false
      $hasCode22 = $false
      foreach ($b in $afterBad) {
        $c = Get-ProblemCode $b.InstanceId
        if ($c -eq 10) { $hasCode10 = $true }
        if ($c -eq 22) { $hasCode22 = $true }
      }
      if ($hasCode10) {
        Write-Log 'Guidance (Code 10): Driver failed to start.'
        Write-Log 'Vendor-driver reinstall steps: 1) Download the sensor driver (Intel ISH / HID Sensor) from your PC maker support site (Lenovo/Dell/HP/ASUS). 2) In Device Manager, right-click sensor > Uninstall device (check Attempt to remove driver). 3) Run the downloaded installer and reboot.'
      }
      if ($hasCode22) {
        Write-Log 'Guidance (Code 22): Sensor is still disabled after enable attempt.'
        Write-Log 'Next steps: 1) Reboot Windows. 2) If still disabled, perform EC reset: shut down, disconnect AC adapter, hold power button for 30-60 seconds, then power back on.'
      }
      if (-not $hasCode10 -and -not $hasCode22) {
        Write-Log ('Guidance: Sensor is still non-OK (Status: ' + $afterBad[0].Status + '). Try rebooting or checking Device Manager.')
      }
    } else {
      $slate = Get-Dw 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'ConvertibleSlateMode'
      if ($slate -eq 0) {
        Write-Log 'Guidance (Sensor OK yet TABLET): All sensors report OK, but Windows posture is still TABLET (ConvertibleSlateMode = 0) — built-in keyboard remains disabled.'
        Write-Log 'Hardware posture sensor reports tablet or EC posture is desynced. Point at BIOS/EC/reboot: 1) Reboot laptop. 2) Update/reflash BIOS. 3) Perform EC reset (shut down, unplug AC, hold power button 30-60s).'
      } else {
        Write-Log 'Done. Sensor is OK — test your keyboard/touchpad now.'
      }
    }
  } catch { Write-Log ('FAILED: ' + $_.Exception.Message) }
})
$frm.Controls.Add($btnFix)
$y += 44

$lblTask = New-Object Windows.Forms.Label
$lblTask.Text = 'Touch taskbar (no admin needed):'
$lblTask.AutoSize = $true
$lblTask.Location = New-Object Drawing.Point(14, $y)
$frm.Controls.Add($lblTask)
$y += 22

$btnOn = New-Object Windows.Forms.Button
$btnOn.Text = 'Tablet ON'
$btnOn.Location = New-Object Drawing.Point(14, $y)
$btnOn.Size = New-Object Drawing.Size(140, 32)
$frm.Controls.Add($btnOn)

$btnOff = New-Object Windows.Forms.Button
$btnOff.Text = 'Tablet OFF'
$btnOff.Location = New-Object Drawing.Point(160, $y)
$btnOff.Size = New-Object Drawing.Size(140, 32)
$frm.Controls.Add($btnOff)

$btnAuto = New-Object Windows.Forms.Button
$btnAuto.Text = 'Auto'
$btnAuto.Location = New-Object Drawing.Point(306, $y)
$btnAuto.Size = New-Object Drawing.Size(146, 32)
$frm.Controls.Add($btnAuto)
$y += 40

$btnEc = New-Object Windows.Forms.Button
$btnEc.Text = 'EC Reset Guide (needs physical power-hold)'
$btnEc.Location = New-Object Drawing.Point(14, $y)
$btnEc.Size = New-Object Drawing.Size(438, 32)
$frm.Controls.Add($btnEc)
$y += 42

$btnDiag = New-Object Windows.Forms.Button
$btnDiag.Text = 'Copy Diagnostics'
$btnDiag.Location = New-Object Drawing.Point(14, $y)
$btnDiag.Size = New-Object Drawing.Size(438, 32)
$frm.Controls.Add($btnDiag)
$y += 42

function Set-Taskbar([string]$mode) {
  try {
    New-Item -Path $advPath -Force | Out-Null
    New-Item -Path $expPath -Force | Out-Null
    if ($mode -eq 'on') {
      New-ItemProperty -Path $advPath -Name 'ExpandableTaskbar' -Value 1 -PropertyType DWord -Force | Out-Null
      New-ItemProperty -Path $expPath -Name 'TabletPostureTaskbar' -Value 1 -PropertyType DWord -Force | Out-Null
      Write-Log 'Taskbar: forced to TABLET.'
    } elseif ($mode -eq 'off') {
      New-ItemProperty -Path $advPath -Name 'ExpandableTaskbar' -Value 0 -PropertyType DWord -Force | Out-Null
      New-ItemProperty -Path $expPath -Name 'TabletPostureTaskbar' -Value 0 -PropertyType DWord -Force | Out-Null
      Write-Log 'Taskbar: forced to DESKTOP.'
    } else {
      New-ItemProperty -Path $advPath -Name 'ExpandableTaskbar' -Value 1 -PropertyType DWord -Force | Out-Null
      Remove-ItemProperty -Path $expPath -Name 'TabletPostureTaskbar' -ErrorAction SilentlyContinue
      Write-Log 'Taskbar: back to AUTO.'
    }
  } catch {
    Write-Log ('FAILED (taskbar): ' + $_.Exception.Message)
    Write-Log 'Registry terkunci (biasanya Explorer sedang menahan key) — tutup semua Explorer, jalankan tool sebagai admin, lalu ulangi.'
    return
  }
  try {
    $r = [Windows.Forms.MessageBox]::Show('Restart Explorer to apply immediately? (taskbar will flicker briefly)', 'Restart Explorer', 'YesNo', 'Question')
    if ($r -eq 'Yes') { Stop-Process -Name explorer -Force; Start-Sleep -Seconds 2; Write-Log 'Explorer restarted.' }
  } catch {
    Write-Log ('Registry tersimpan, tapi restart Explorer gagal: ' + $_.Exception.Message)
    Write-Log 'Restart manual: Task Manager > Windows Explorer > Restart.'
  }
  Update-Status
}
$btnOn.Add_Click({ try { Set-Taskbar 'on' } catch { Write-Log ('FAILED (taskbar): ' + $_.Exception.Message) } })
$btnOff.Add_Click({ try { Set-Taskbar 'off' } catch { Write-Log ('FAILED (taskbar): ' + $_.Exception.Message) } })
$btnAuto.Add_Click({ try { Set-Taskbar 'auto' } catch { Write-Log ('FAILED (taskbar): ' + $_.Exception.Message) } })

function Show-EcResetGuide {
  $prompt = "An EC (Embedded Controller) reset clears hardware state when the posture sensor or keyboard controller is stuck.`r`n`r`n" +
            "This will schedule a FULL shutdown in 30 seconds (bypassing Fast Startup).`r`n`r`n" +
            "After shutdown, you MUST perform the physical steps (unplug power/USB, hold physical power button 15-20s).`r`n`r`n" +
            "Proceed with full shutdown now?"
  $r = [Windows.Forms.MessageBox]::Show($prompt, 'EC Reset Guide', 'YesNo', 'Question')
  if ($r -ne 'Yes') {
    Write-Log 'EC reset cancelled.'
    return
  }

  Write-Log 'EC Reset — Physical steps:'
  Write-Log '1. Save work'
  Write-Log '2. Unplug charger + all USB after dark'
  Write-Log '3. Hold PHYSICAL power button 15-20s'
  Write-Log '4. Replug charger'
  Write-Log '5. Power on'
  Write-Log '6. Reopen tool and check posture line'
  try {
    shutdown /s /t 30 /c 'EC RESET: save work, unplug charger+USB now. After screen goes dark, hold power 15-20s.'
  } catch {
    Write-Log ('FAILED (shutdown): ' + $_.Exception.Message)
  }
  Write-Log 'Abort hint: run "shutdown /a" in Command Prompt to cancel.'
}
$btnEc.Add_Click({ try { Show-EcResetGuide } catch { Write-Log ('FAILED (EC reset): ' + $_.Exception.Message) } })

function Copy-Diagnostics {
  $lines = Get-ToolDiagnostics
  $text = $lines -join "`r`n"
  $diagPath = "$env:USERPROFILE\Desktop\TabletFix-Diag.txt"

  $clipOk = $false
  $clipErr = $null
  try {
    Set-Clipboard -Value $text -ErrorAction Stop
    $clipOk = $true
  } catch {
    try {
      [Windows.Forms.Clipboard]::SetText($text)
      $clipOk = $true
    } catch {
      $clipErr = $_.Exception.Message
    }
  }

  $fileOk = $false
  $fileErr = $null
  try {
    $desktopDir = Split-Path $diagPath -Parent
    if ($desktopDir -and -not (Test-Path $desktopDir)) {
      New-Item -ItemType Directory -Path $desktopDir -Force -ErrorAction Stop | Out-Null
    }
    [System.IO.File]::WriteAllText($diagPath, ($text + "`r`n"), [System.Text.Encoding]::UTF8)
    $fileOk = $true
  } catch {
    $fileErr = $_.Exception.Message
  }

  if ($clipOk -and $fileOk) {
    Write-Log ('Diagnostics copied to clipboard and saved to: ' + $diagPath)
  } elseif ($clipOk -and -not $fileOk) {
    Write-Log ('Diagnostics copied to clipboard. (File save failed: ' + $fileErr + ')')
  } elseif (-not $clipOk -and $fileOk) {
    Write-Log ('Diagnostics saved to ' + $diagPath + '. (Clipboard failed: ' + $clipErr + ')')
  } else {
    Write-Log ('FAILED to export diagnostics. Clipboard: ' + $clipErr + ' | File: ' + $fileErr)
  }

  try {
    $sensorSummary = 'Sensor: none found'
    $devs = Get-SensorState
    if ($devs -and $devs.Count -gt 0) {
      $d0 = $devs[0]
      $c0 = Get-ProblemCode $d0.InstanceId
      $c0Str = if ($null -ne $c0) { "Code $c0" } else { 'no problem code' }
      $d0Name = if ($d0.FriendlyName) { $d0.FriendlyName } elseif ($d0.Name) { $d0.Name } else { $d0.InstanceId }
      $sensorSummary = "Sensor: $d0Name ($($d0.Status), $c0Str)"
    }

    $slate = Get-Dw 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'ConvertibleSlateMode'
    $postureSummary = if ($slate -eq 0) {
      'Posture: TABLET (0x0)'
    } elseif ($slate -eq 1) {
      'Posture: LAPTOP (0x1)'
    } elseif ($null -ne $slate) {
      "Posture: raw $slate"
    } else {
      'Posture: unreadable'
    }

    Write-Log ("Summary: $sensorSummary | $postureSummary")
  } catch {
    Write-Log ('Summary error: ' + $_.Exception.Message)
  }
}
$btnDiag.Add_Click({ try { Copy-Diagnostics } catch { Write-Log ('FAILED (copy diagnostics): ' + $_.Exception.Message) } })


$txtLog = New-Object Windows.Forms.RichTextBox
$txtLog.Location = New-Object Drawing.Point(14, $y)
$txtLog.Size = New-Object Drawing.Size(438, 130)
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object Drawing.Font('Consolas', 8.5)
$frm.Controls.Add($txtLog)

Update-AdminLabel
Update-Status
Write-Log 'Tool ready. Hit Refresh any time.'
[void]$frm.ShowDialog()
