# DataManager.ps1 - Data file management and persistence
# 数据文件管理和持久化

class DataModel {
    [hashtable]$DailyRequestStatus

    DataModel() {
        $this.DailyRequestStatus = @{}
    }
}

function Read-DataFile {
    <#
    .SYNOPSIS
    读取数据文件
    
    .DESCRIPTION
    从JSON文件中读取数据并返回解析后的对象
    
    .PARAMETER DataPath
    数据文件路径
    
    .OUTPUTS
    Parsed data object or $null if failed
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataPath
    )
    
    try {
        if (-not (Test-Path $DataPath)) {
            Write-Host "[WARN] Data file not found: $DataPath" -ForegroundColor Yellow
            return $null
        }
        
        $jsonContent = Get-Content -Path $DataPath -Raw -Encoding UTF8
        $data = $jsonContent | ConvertFrom-Json
        
        Write-Host "[OK] Data file loaded successfully from: $DataPath" -ForegroundColor Green
        return $data
    }
    catch {
        Write-Host "[ERROR] Error reading data file: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Write-DataFile {
    <#
    .SYNOPSIS
    写入数据文件
    
    .DESCRIPTION
    将数据对象序列化为JSON并写入文件
    
    .PARAMETER DataPath
    数据文件路径
    
    .PARAMETER Data
    要写入的数据对象
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataPath,
        
        [Parameter(Mandatory=$true)]
        $Data
    )
    
    try {
        $jsonContent = $Data | ConvertTo-Json -Depth 10
        Set-Content -Path $DataPath -Value $jsonContent -Encoding UTF8
        
        return $true
    }
    catch {
        Write-Host "[ERROR] Error writing data file: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-DataFileFormat {
    <#
    .SYNOPSIS
    验证数据文件格式
    
    .DESCRIPTION
    检查数据文件是否具有正确的格式和必需的字段
    
    .PARAMETER DataPath
    数据文件路径
    
    .OUTPUTS
    Boolean indicating if format is valid
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataPath
    )
    
    try {
        $data = Read-DataFile -DataPath $DataPath
        if ($null -eq $data) {
            return $false
        }
        
        $hasValidFormat = $true
        
        if (-not $data.PSObject.Properties['dailyRequestStatus']) {
            Write-Host "[WARN] Missing dailyRequestStatus property" -ForegroundColor Yellow
            $hasValidFormat = $false
        } else {
            # 验证数组格式
            $dailyStatusArray = Get-DailyRequestStatusArray -Data $data
            if ($dailyStatusArray.Count -eq 0) {
                Write-Host "[WARN] dailyRequestStatus is empty or invalid format" -ForegroundColor Yellow
                $hasValidFormat = $false
            } else {
                # 验证数组中每个元素的格式
                foreach ($record in $dailyStatusArray) {
                    if (-not ($record.PSObject.Properties['requestDate'] -and 
                             $record.PSObject.Properties['totalRequests'] -and 
                             $record.PSObject.Properties['successfulRequests'])) {
                        Write-Host "[WARN] Invalid record format in dailyRequestStatus array" -ForegroundColor Yellow
                        $hasValidFormat = $false
                        break
                    }
                }
            }
        }
        
        if ($hasValidFormat) {
            Write-Host "[OK] Data file format validation passed" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Data file format validation failed" -ForegroundColor Red
        }
        
        return $hasValidFormat
    }
    catch {
        Write-Host "[ERROR] Error validating data file format: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Initialize-DataFile {
    <#
    .SYNOPSIS
    初始化数据文件
    
    .DESCRIPTION
    创建一个新的数据文件，包含默认结构
    
    .PARAMETER DataPath
    数据文件路径
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataPath
    )
    
    try {
        # 使用新的数组格式初始化
        $initialData = @{
            dailyRequestStatus = @(
                @{
                    requestDate = Get-Date -Format "yyyy-MM-dd"
                    totalRequests = 0
                    successfulRequests = 0
                }
            )
        }
        
        $result = Write-DataFile -DataPath $DataPath -Data $initialData
        
        if ($result) {
            Write-Host "[OK] Data file initialized successfully with array format" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Failed to initialize data file" -ForegroundColor Red
        }
        
        return $result
    }
    catch {
        Write-Host "[ERROR] Error initializing data file: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Repair-DataFile {
    <#
    .SYNOPSIS
    修复数据文件
    
    .DESCRIPTION
    尝试修复损坏或格式不正确的数据文件
    
    .PARAMETER DataPath
    数据文件路径
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataPath
    )
    
    try {
        Write-Host "[PROC] Attempting to repair data file..." -ForegroundColor Yellow
        
        # Try to read existing data
        $existingData = Read-DataFile -DataPath $DataPath
        
        # Create repaired structure with array format
        $repairedData = @{
            dailyRequestStatus = @(
                @{
                    requestDate = Get-Date -Format "yyyy-MM-dd"
                    totalRequests = 0
                    successfulRequests = 0
                }
            )
        }
        
        # Preserve existing data if possible
        if ($null -ne $existingData) {
            if ($existingData.PSObject.Properties['dailyRequestStatus']) {
                $raw = $existingData.dailyRequestStatus
                if ($raw -is [Array]) {
                    $repairedData.dailyRequestStatus = $raw
                    Write-Host "[INFO] Preserved existing array data during repair" -ForegroundColor Gray
                } elseif ($raw -is [PSCustomObject] -or $raw -is [hashtable]) {
                    # 强制转为数组格式
                    $repairedData.dailyRequestStatus = @($raw)
                    Write-Host "[INFO] Converted object to array format during repair" -ForegroundColor Yellow
                }
            }
        }
        
        # Write repaired data
        $result = Write-DataFile -DataPath $DataPath -Data $repairedData
        
        if ($result) {
            Write-Host "[OK] Data file repaired successfully with array format" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Failed to repair data file" -ForegroundColor Red
        }
        
        return $result
    }
    catch {
        Write-Host "[ERROR] Error repairing data file: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}



function Show-DataFileSummary {
    <#
    .SYNOPSIS
    显示数据文件摘要
    
    .DESCRIPTION
    显示数据文件的摘要信息
    
    .PARAMETER DataPath
    数据文件路径
    
    .PARAMETER RequestHistoryPath
    请求历史文件路径（可选）
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataPath,
        
        [Parameter(Mandatory=$false)]
        [string]$RequestHistoryPath
    )
    
    try {
        $data = Read-DataFile -DataPath $DataPath
        if ($null -eq $data) {
            Write-Host "[ERROR] Could not read data file for summary" -ForegroundColor Red
            return
        }
        
        Write-Host "[INFO] Data File Summary:" -ForegroundColor Cyan
        
        $dailyStatusArray = Get-DailyRequestStatusArray -Data $data
        if ($dailyStatusArray.Count -gt 0) {
            Write-Host "  Daily Status Records: $($dailyStatusArray.Count) days" -ForegroundColor Gray
            
            # 显示最近几天的记录
            $recentRecords = $dailyStatusArray | Sort-Object requestDate -Descending | Select-Object -First 3
            foreach ($record in $recentRecords) {
                Write-Host "    $($record.requestDate): Total=$($record.totalRequests), Successful=$($record.successfulRequests)" -ForegroundColor Gray
            }
            
            # 显示今日记录
            $today = Get-Date -Format "yyyy-MM-dd"
            $todayRecord = Find-TodayRecord -DailyStatusArray $dailyStatusArray -TargetDate $today
            if ($todayRecord) {
                Write-Host "  Today ($today):" -ForegroundColor Yellow
                Write-Host "    Total Requests: $($todayRecord.totalRequests)" -ForegroundColor Gray
                Write-Host "    Successful Requests: $($todayRecord.successfulRequests)" -ForegroundColor Gray
            } else {
                Write-Host "  Today ($today): No records yet" -ForegroundColor Gray
            }
        } else {
            Write-Host "  Daily Status: No records found" -ForegroundColor Yellow
        }
        
        # Read request history count from separate file if provided
        if ($RequestHistoryPath -and (Test-Path $RequestHistoryPath)) {
            try {
                $historyData = Read-DataFile -DataPath $RequestHistoryPath
                if ($null -ne $historyData -and $historyData.PSObject.Properties['requestHistory']) {
                    $historyCount = if ($historyData.requestHistory -is [array]) { $historyData.requestHistory.Count } else { 1 }
                    Write-Host "  Request History: $historyCount entries" -ForegroundColor Gray
                } else {
                    Write-Host "  Request History: 0 entries (invalid format)" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "  Request History: Unable to read history file (corrupted)" -ForegroundColor Yellow
            }
        } elseif ($RequestHistoryPath) {
            Write-Host "  Request History: 0 entries (file not found)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "[ERROR] Error showing data file summary: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-DailyRequestStatusArray {
    <#
    .SYNOPSIS
    获取每日请求状态数组
    
    .DESCRIPTION
    从数据对象中获取每日请求状态数组
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Data
    )
    
    if ($null -eq $Data.dailyRequestStatus) {
        return @()
    }
    
    # 直接返回数组格式
    if ($Data.dailyRequestStatus -is [Array]) {
        return $Data.dailyRequestStatus
    }
    
    return @()
}

function Find-TodayRecord {
    <#
    .SYNOPSIS
    从数组中查找今日记录
    #>
    param(
        [Parameter(Mandatory=$true)]
        [Array]$DailyStatusArray,
        
        [string]$TargetDate = (Get-Date -Format "yyyy-MM-dd")
    )
    
    return $DailyStatusArray | Where-Object { $_.requestDate -eq $TargetDate } | Select-Object -First 1
}

function Update-DailyStatusArray {
    <#
    .SYNOPSIS
    更新数组中的今日记录
    #>
    param(
        [Parameter(Mandatory=$true)]
        [Array]$DailyStatusArray,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$TodayRecord
    )
    
    $today = $TodayRecord.requestDate
    $existingIndex = -1
    
    for ($i = 0; $i -lt $DailyStatusArray.Count; $i++) {
        if ($DailyStatusArray[$i].requestDate -eq $today) {
            $existingIndex = $i
            break
        }
    }
    
    if ($existingIndex -ge 0) {
        # 更新现有记录
        $DailyStatusArray[$existingIndex] = $TodayRecord
    } else {
        # 添加新记录
        $DailyStatusArray += $TodayRecord
    }
    
    return $DailyStatusArray
}

# Functions are available when dot-sourced