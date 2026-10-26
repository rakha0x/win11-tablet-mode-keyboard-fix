# Win11-TabletMode-KeyboardFix.ps1 — fix dead keyboard/touchpad on 2-in-1 laptops stuck in tablet mode, plus touch-taskbar on/off.
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
  $devs = Get-PnpDevice -FriendlyName '*Integrated Sensor*' -ErrorAction SilentlyContinue
  if (-not $devs) { $devs = Get-PnpDevice -FriendlyName '*Intel*Sensor*' -ErrorAction SilentlyContinue }
  return $devs
}

function Write-Log([string]$msg) {
  $txtLog.AppendText(('[{0:HH:mm:ss}] {1}' -f (Get-Date), $msg) + "`r`n")
}

# ---------- Form ----------
$frm = New-Object Windows.Forms.Form
$frm.Text = 'Win11 Tablet Mode Keyboard Fix'
$frm.Size = New-Object Drawing.Size(480, 600)
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
  else { $lblSensor.Text = 'Sensor: ' + $bad[0].Status + ' — keyboard may be dead!'; $lblSensor.ForeColor = [Drawing.Color]::Red }

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
$btnRefresh.Add_Click({ Update-Status; Write-Log 'Status refreshed.' })
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
    $devs = @((Get-SensorState) | Where-Object { $_.Status -ne 'OK' })
    if ($devs.Count -eq 0) { Write-Log 'Sensor is already OK, nothing to fix.'; return }
    foreach ($d in $devs) {
      Write-Log ('Enabling: ' + $d.FriendlyName + ' ...')
      Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false
    }
    Start-Sleep -Seconds 2
    Update-Status
    Write-Log 'Done. Test your keyboard/touchpad now.'
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

function Set-Taskbar([string]$mode) {
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
  $r = [Windows.Forms.MessageBox]::Show('Restart Explorer to apply immediately? (taskbar will flicker briefly)', 'Restart Explorer', 'YesNo', 'Question')
  if ($r -eq 'Yes') { Stop-Process -Name explorer -Force; Start-Sleep -Seconds 2; Write-Log 'Explorer restarted.' }
  Update-Status
}
$btnOn.Add_Click({ Set-Taskbar 'on' })
$btnOff.Add_Click({ Set-Taskbar 'off' })
$btnAuto.Add_Click({ Set-Taskbar 'auto' })

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
