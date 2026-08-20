$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║           YÊU CẦU QUYỀN QUẢN TRỊ       ║" -ForegroundColor Red
    Write-Host "║     Vui lòng chạy script này bằng quyền Administrator!      ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Red
    exit
}

Write-Host "Code gốc được viết bởi lily<3" -ForegroundColor Cyan
Write-Host ""

try {
    $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $bootTime
    Write-Host "THỜI GIAN KHỞI ĐỘNG HỆ THỐNG" -ForegroundColor Cyan
    Write-Host ("  Lần khởi động gần nhất: {0}" -f $bootTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
    Write-Host ("  Thời gian hoạt động: {0} days, {1:D2}:{2:D2}:{3:D2}" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds) -ForegroundColor White
} catch {
    Write-Host "Không thể lấy thông tin thời gian khởi động" -ForegroundColor Red
}

$drives = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -ne 5 }
if ($drives) {
    Write-Host "`nỔ ĐĨA ĐANG KẾT NỐI" -ForegroundColor Cyan
    foreach ($drive in $drives) {
        Write-Host ("  {0}: {1}" -f $drive.DeviceID, $drive.FileSystem) -ForegroundColor Green
    }
}

Write-Host "`nTRẠNG THÁI SERVICES" -ForegroundColor Cyan

$services = @(
    @{Name = "SysMain"; DisplayName = "SysMain"},
    @{Name = "PcaSvc"; DisplayName = "PcaSvc"},
    @{Name = "DPS"; DisplayName = "DPS"},
    @{Name = "EventLog"; DisplayName = "EventLog"},
    @{Name = "Schedule"; DisplayName = "Schedule"},
    @{Name = "Bam"; DisplayName = "Bam"},
    @{Name = "Dusmsvc"; DisplayName = "Dusmsvc"},
    @{Name = "Appinfo"; DisplayName = "Appinfo"},
    @{Name = "CDPSvc"; DisplayName = "CDPSvc"},
    @{Name = "DcomLaunch"; DisplayName = "DcomLaunch"},
    @{Name = "PlugPlay"; DisplayName = "PlugPlay"},
    @{Name = "wsearch"; DisplayName = "wsearch"}
)

# ===== TÍNH NĂNG MỚI: tự xử lý service bị Disabled / Stopped bằng SC =====
$restoredServices = @()
$failedServices = @()

foreach ($svc in $services) {
    $svcInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue

    if (-not $svcInfo) {
        Write-Host ("  [N/A] Không tìm thấy service: {0}" -f $svc.Name) -ForegroundColor Yellow
        $failedServices += $svc.Name
        continue
    }

    $wasDisabled = ($svcInfo.StartMode -eq "Disabled")
    $wasStopped  = ($svcInfo.State -ne "Running")

    # Service bị Disabled: phải đổi Startup Type trước khi start.
    if ($wasDisabled) {
        Write-Host ("  [FIX] {0} đang Disabled -> chuyển sang Automatic..." -f $svc.Name) -ForegroundColor Magenta

        # Lưu ý: cú pháp chuẩn của sc.exe là "start= auto" (có khoảng trắng sau dấu =).
        Write-Host ('  [SC] sc config "{0}" start= auto' -f $svc.Name) -ForegroundColor Yellow
        & sc.exe config "$($svc.Name)" start= auto | Out-Host
        $configExitCode = $LASTEXITCODE

        if ($configExitCode -eq 0) {
            Write-Host ("  [OK] {0} đã chuyển sang Automatic." -f $svc.Name) -ForegroundColor Green
        } else {
            Write-Host ("  [LOI] Không thể đổi {0} sang Automatic. Mã lỗi: {1}" -f $svc.Name, $configExitCode) -ForegroundColor Red
            $failedServices += $svc.Name
            continue
        }
    }

    # Kiểm tra lại trạng thái sau khi xử lý Startup Type.
    $svcInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue

    # Service không Running thì start.
    if ($svcInfo -and $svcInfo.State -ne "Running") {
        Write-Host ('  [SC] sc start "{0}"' -f $svc.Name) -ForegroundColor Yellow
        & sc.exe start "$($svc.Name)" | Out-Host
        $startExitCode = $LASTEXITCODE

        if ($startExitCode -eq 0) {
            Write-Host ("  [OK] {0} đã được start." -f $svc.Name) -ForegroundColor Green
        } else {
            Write-Host ("  [LOI] Không thể start {0}. Mã lỗi: {1}" -f $svc.Name, $startExitCode) -ForegroundColor Red
        }
    }

    # Xác nhận trạng thái cuối cùng.
    $finalInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue

    if ($finalInfo -and $finalInfo.State -eq "Running") {
        # Chỉ thông báo ở phần tổng kết nếu service ban đầu bị tắt/dừng.
        if ($wasDisabled -or $wasStopped) {
            $restoredServices += $svc.Name
        }
    } else {
        $failedServices += $svc.Name
    }
}

# ===== TỔNG KẾT SERVICE =====
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "         TỔNG KẾT TRẠNG THÁI SERVICES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Loại bỏ tên trùng nếu có.
$restoredServices = @($restoredServices | Select-Object -Unique)
$failedServices = @($failedServices | Select-Object -Unique)

if ($restoredServices.Count -gt 0) {
    Write-Host ""
    Write-Host "CÁC SERVICES ĐÃ ĐƯỢC BẬT LẠI:" -ForegroundColor Yellow
    foreach ($serviceName in $restoredServices) {
        Write-Host ("  [+] {0}" -f $serviceName) -ForegroundColor Green
    }
}

if ($failedServices.Count -eq 0) {
    Write-Host ""
    Write-Host "[OK] TẤT CẢ SERVICES ĐỀU HOẠT ĐỘNG BÌNH THƯỜNG." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "CÁC SERVICES CHƯA HOẠT ĐỘNG BÌNH THƯỜNG:" -ForegroundColor Red
    foreach ($serviceName in $failedServices) {
        Write-Host ("  [!] {0}" -f $serviceName) -ForegroundColor Red
    }
}

Write-Host "========================================" -ForegroundColor Cyan
# ===== HẾT PHẦN THÊM =====

foreach ($svc in $services) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            $displayName = $service.DisplayName
            if ($displayName.Length -gt 40) {
                $displayName = $displayName.Substring(0, 37) + "..."
            }
            Write-Host ("  {0,-12} {1,-40}" -f $svc.Name, $displayName) -ForegroundColor Green -NoNewline
            
            if ($svc.Name -eq "Bam") {
                Write-Host " | Đã bật" -ForegroundColor Yellow
            } else {
                try {
                    $process = Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" | Select-Object ProcessId
                    if ($process.ProcessId -gt 0) {
                        $proc = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
                        if ($proc) {
                            Write-Host (" | {0}" -f $proc.StartTime.ToString("HH:mm:ss")) -ForegroundColor Yellow
                        } else {
                            Write-Host " | Không có dữ liệu" -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host " | Không có dữ liệu" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host " | Không có dữ liệu" -ForegroundColor Yellow
                }
            }
        } else {
            $displayName = $service.DisplayName
            if ($displayName.Length -gt 40) {
                $displayName = $displayName.Substring(0, 37) + "..."
            }
            Write-Host ("  {0,-12} {1,-40} {2}" -f $svc.Name, $displayName, $service.Status) -ForegroundColor Red
        }
    } else {
        Write-Host ("  {0,-12} {1,-40} {2}" -f $svc.Name, "Không tìm thấy", "Đã dừng") -ForegroundColor Yellow
    }
}

Write-Host "`nREGISTRY" -ForegroundColor Cyan

$settings = @(
    @{ Name = "CMD"; Path = "HKCU:\Software\Policies\Microsoft\Windows\System"; Key = "DisableCMD"; Warning = "Đã tắt"; Safe = "Khả dụng" },
    @{ Name = "Ghi log PowerShell"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"; Key = "EnableScriptBlockLogging"; Warning = "Đã tắt"; Safe = "Đã bật" },
    @{ Name = "Bộ nhớ đệm hoạt động"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Key = "EnableActivityFeed"; Warning = "Đã tắt"; Safe = "Đã bật" },
    @{ Name = "Prefetch Đã bật"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Key = "EnablePrefetcher"; Warning = "Đã tắt"; Safe = "Đã bật" }
)

foreach ($s in $settings) {
    $status = Get-ItemProperty -Path $s.Path -Name $s.Key -ErrorAction SilentlyContinue
    Write-Host "  " -NoNewline
    if ($status -and $status.$($s.Key) -eq 0) {
        Write-Host "$($s.Name): " -NoNewline -ForegroundColor White
        Write-Host "$($s.Warning)" -ForegroundColor Red
    } else {
        Write-Host "$($s.Name): " -NoNewline -ForegroundColor White
        Write-Host "$($s.Safe)" -ForegroundColor Green
    }
}

function Check-EventLog {
    param ($logName, $eventID, $message)
    $event = Get-WinEvent -LogName $logName -FilterXPath "*[System[EventID=$eventID]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($event) {
        Write-Host "  $message at: " -NoNewline -ForegroundColor White
        Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow
    } else {
        Write-Host "  $message - Không tìm thấy bản ghi" -ForegroundColor Green
    }
}

function Check-RecentEventLog {
    param ($logName, $eventIDs, $message)
    $event = Get-WinEvent -LogName $logName -FilterXPath "*[System[EventID=$($eventIDs -join ' or EventID=')]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($event) {
        Write-Host "  $message (ID: $($event.Id)) at: " -NoNewline -ForegroundColor White
        Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow
    } else {
        Write-Host "  $message - Không tìm thấy bản ghi" -ForegroundColor Green
    }
}

function Check-DeviceDeleted {
    try {
        $event = Get-WinEvent -LogName "Microsoft-Windows-Kernel-PnP/Configuration" -FilterXPath "*[System[EventID=400]]" -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($event) {
            Write-Host "  Cấu hình thiết bị thay đổi lúc: " -NoNewline -ForegroundColor White
            Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow
            return
        }
    } catch {}

    try {
        $event = Get-WinEvent -FilterHashtable @{LogName="System"; ID=225} -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($event) {
            Write-Host "  Thiết bị bị gỡ lúc: " -NoNewline -ForegroundColor White
            Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow
            return
        }
    } catch {}

    try {
        $events = Get-WinEvent -LogName "System" | Where-Object {$_.Id -eq 225 -or $_.Id -eq 400} | Sort-Object TimeCreated -Descending | Select-Object -First 1
        if ($events) {
            Write-Host "  Lần thay đổi thiết bị gần nhất lúc: " -NoNewline -ForegroundColor White
            Write-Host $events.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow
            return
        }
    } catch {}

    Write-Host "  Thay đổi thiết bị - Không tìm thấy bản ghi" -ForegroundColor Green
}

Write-Host "`nNHẬT KÝ SỰ KIỆN" -ForegroundColor Cyan

Check-EventLog "Application" 3079 "USN Journal đã bị xóa"
Check-RecentEventLog "System" @(104, 1102) "Event Logs đã bị xóa"
Check-EventLog "System" 1074 "Lần tắt máy gần nhất"
Check-EventLog "Security" 4616 "Thời gian hệ thống đã thay đổi"
Check-EventLog "System" 6005 "Service Event Log đã khởi động"
Check-DeviceDeleted


$prefetchPath = "$env:SystemRoot\Prefetch"
if (Test-Path $prefetchPath) {
    Write-Host "`nKIỂM TRA TÍNH TOÀN VẸN PREFETCH" -ForegroundColor Cyan
    
    
    $files = Get-ChildItem -Path $prefetchPath -Filter *.pf -Force -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Host "  Không tìm thấy Prefetch?? Vui lòng kiểm tra thư mục" -ForegroundColor Yellow
    } else {
        $hashTable = @{}
        $suspiciousFiles = @{}
        $totalFiles = $files.Count

        
        $hiddenFiles = @()
        $readOnlyFiles = @()
        $hiddenAndReadOnlyFiles = @()
        $invalidSignatureFiles = @()
        $errorFiles = @()

        foreach ($file in $files) {
            try {
                $isHidden = $file.Attributes -band [System.IO.FileAttributes]::Hidden
                $isReadOnly = $file.Attributes -band [System.IO.FileAttributes]::ReadOnly
                
                
                if ($isHidden -and $isReadOnly) {
                    $hiddenAndReadOnlyFiles += $file
                    if (-not $suspiciousFiles.ContainsKey($file.Name)) {
                        $suspiciousFiles[$file.Name] = "Ẩn và chỉ đọc"
                    }
                } elseif ($isHidden) {
                    $hiddenFiles += $file
                    if (-not $suspiciousFiles.ContainsKey($file.Name)) {
                        $suspiciousFiles[$file.Name] = "File ẩn"
                    }
                } elseif ($isReadOnly) {
                    $readOnlyFiles += $file
                    if (-not $suspiciousFiles.ContainsKey($file.Name)) {
                        $suspiciousFiles[$file.Name] = "File chỉ đọc"
                    }
                }

                
                $stream = [System.IO.File]::OpenRead($file.FullName)
                $reader = New-Object System.IO.BinaryReader($stream)
                $signature = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(3))
                $reader.Close()
                $stream.Close()

                if ($signature -ne "MAM") {
                    $invalidSignatureFiles += $file
                    if (-not $suspiciousFiles.ContainsKey($file.Name)) {
                        $suspiciousFiles[$file.Name] = "Chữ ký không hợp lệ: $signature"
                    } else {
                        
                        $suspiciousFiles[$file.Name] += ", Chữ ký không hợp lệ: $signature"
                    }
                }

                
                $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue
                if ($hash) {
                    if ($hashTable.ContainsKey($hash.Hash)) {
                        $hashTable[$hash.Hash].Add($file.Name)
                    } else {
                        $hashTable[$hash.Hash] = [System.Collections.Generic.List[string]]::new()
                        $hashTable[$hash.Hash].Add($file.Name)
                    }
                }
            } catch {
                $errorFiles += $file
                if (-not $suspiciousFiles.ContainsKey($file.Name)) {
                    $suspiciousFiles[$file.Name] = "Lỗi khi phân tích file: $($_.Exception.Message)"
                }
            }
        }

        
        if ($hiddenAndReadOnlyFiles.Count -gt 0) {
            Write-Host "  File ẩn & chỉ đọc: $($hiddenAndReadOnlyFiles.Count) được tìm thấy" -ForegroundColor Yellow
            foreach ($file in $hiddenAndReadOnlyFiles) {
                Write-Host ("    {0}" -f $file.Name) -ForegroundColor White
            }
        }

        if ($hiddenFiles.Count -gt 0) {
            Write-Host "  File ẩn: $($hiddenFiles.Count) được tìm thấy" -ForegroundColor Yellow
            foreach ($file in $hiddenFiles) {
                Write-Host ("    {0}" -f $file.Name) -ForegroundColor White
            }
        } else {
            Write-Host "  File ẩn: Không có" -ForegroundColor Green
        }

        if ($readOnlyFiles.Count -gt 0) {
            Write-Host "  File chỉ đọc: $($readOnlyFiles.Count)" -ForegroundColor Yellow
            foreach ($file in $readOnlyFiles) {
                Write-Host ("    {0}" -f $file.Name) -ForegroundColor White
            }
        } else {
            Write-Host "  File chỉ đọc: Không có" -ForegroundColor Green
        }

        if ($invalidSignatureFiles.Count -gt 0) {
            Write-Host "  Chữ ký không hợp lệ: $($invalidSignatureFiles.Count)" -ForegroundColor Yellow
            foreach ($file in $invalidSignatureFiles) {
                Write-Host ("    {0}" -f $file.Name) -ForegroundColor White
            }
        } else {
            Write-Host "  Chữ ký file: Tất cả đều hợp lệ" -ForegroundColor Green
        }

        
        $repeatedHashes = $hashTable.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($repeatedHashes) {
            Write-Host "  File trùng lặp: $($repeatedHashes.Count) sets được tìm thấy" -ForegroundColor Yellow
            foreach ($entry in $repeatedHashes) {
                foreach ($file in $entry.Value) {
                    if (-not $suspiciousFiles.ContainsKey($file)) {
                        $suspiciousFiles[$file] = "File trùng lặp"
                    }
                }
                Write-Host ("    Nhóm file trùng lặp: {0}" -f ($entry.Value -join ", ")) -ForegroundColor White
            }
        } else {
            Write-Host "  Duplicates: Không có" -ForegroundColor Green
        }

        
        if ($suspiciousFiles.Count -gt 0) {
            Write-Host "`n  PHÁT HIỆN FILE ĐÁNG NGỜ: $($suspiciousFiles.Count)/$totalFiles" -ForegroundColor Yellow
            foreach ($entry in $suspiciousFiles.GetEnumerator() | Sort-Object Key) {
                Write-Host ("    {0} : {1}" -f $entry.Key, $entry.Value) -ForegroundColor White
            }
        } else {
            Write-Host "`n  Tính toàn vẹn Prefetch: Sạch ($totalFiles files checked)" -ForegroundColor Green
        }
    }
} else {
    Write-Host "`nKhông tìm thấy thư mục Prefetch?? (vui lòng kiểm tra đường dẫn)" -ForegroundColor Red
}

try {
    
    $recycleBinPath = "$env:SystemDrive" + '\$Recycle.Bin'
    
    Write-Host "`nTHÙNG RÁC" -ForegroundColor Cyan

    if (Test-Path $recycleBinPath) {
        
        $recycleBinFolder = Get-Item -LiteralPath $recycleBinPath -Force
        
       
        $userFolders = Get-ChildItem -LiteralPath $recycleBinPath -Directory -Force -ErrorAction SilentlyContinue
        
        if ($userFolders) {
           
            $allDeletedItems = @()
            $latestModTime = $recycleBinFolder.LastWriteTime
            
            foreach ($userFolder in $userFolders) {
                
                if ($userFolder.LastWriteTime -gt $latestModTime) {
                    $latestModTime = $userFolder.LastWriteTime
                }
                
                
                $userItems = Get-ChildItem -LiteralPath $userFolder.FullName -File -Force -ErrorAction SilentlyContinue
                if ($userItems) {
                    $allDeletedItems += $userItems
                    
                    $latestFile = $userItems | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($latestFile -and $latestFile.LastWriteTime -gt $latestModTime) {
                        $latestModTime = $latestFile.LastWriteTime
                    }
                }
            }
            
            Write-Host "  Lần chỉnh sửa gần nhất: " -NoNewline -ForegroundColor White
            Write-Host $latestModTime.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor Yellow
            
            if ($allDeletedItems.Count -gt 0) {
                Write-Host "  Tổng số mục: " -NoNewline -ForegroundColor White
                Write-Host $allDeletedItems.Count -ForegroundColor Yellow
                
                
                $latestItem = $allDeletedItems | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                Write-Host "  Mục mới nhất: " -NoNewline -ForegroundColor White
                Write-Host $latestItem.Name -ForegroundColor Gray
            } else {
                Write-Host "  Trạng thái: " -NoNewline -ForegroundColor White
                Write-Host "Thư mục tồn tại nhưng đang trống" -ForegroundColor Green
            }
        } else {
            
            Write-Host "  Trạng thái: " -NoNewline -ForegroundColor White
            Write-Host "Trống" -ForegroundColor Green
            Write-Host "  Lần chỉnh sửa gần nhất: " -NoNewline -ForegroundColor White
            Write-Host $recycleBinFolder.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor Green
        }
        
        
        $clearEvent = Get-WinEvent -FilterHashtable @{LogName="System"; Id=10006} -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($clearEvent) {
            Write-Host "  Lần xóa gần nhất (Event): " -NoNewline -ForegroundColor White
            Write-Host $clearEvent.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor Red
        }
    } else {
        Write-Host "  Recycle Bin not được tìm thấy at: $recycleBinPath" -ForegroundColor Yellow
        Write-Host "  Lưu ý: Thùng rác có thể đang trống hoặc nằm trên ổ đĩa khác" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Thùng rác: Không thể truy cập (có thể do đường dẫn không hợp lệ)" -ForegroundColor Red
    Write-Host "  Lỗi: $($_.Exception.Message)" -ForegroundColor DarkRed
}

Write-Host "`nKiểm tra hoàn tất. Nếu gặp vấn đề, hãy liên hệ @mjioha" -ForegroundColor Cyan
