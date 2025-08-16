# DailyLimitManager.ps1 - Daily request limit control logic
# 每日请求限制控制逻辑

# Import required modules
try {
    . "$PSScriptRoot\ConfigManager.ps1"
    . "$PSScriptRoot\DataManager.ps1"
} catch {
    Write-Warning "Failed to import required modules: $($_.Exception.Message)"
}

function Get-TodayRequestRecord {
    <#
    .SYNOPSIS
    读取今日发送记录的函数
    
    .DESCRIPTION
    从data.json文件中读取今日的请求发送记录，包括总请求数和成功请求数
    
    .PARAMETER DataPath
    数据文件路径 (默认为data.json)
    
    .OUTPUTS
    Hashtable containing today's request statistics
    #>
    param(
        [string]$DataPath = "data.json"
    )
    
    try {
        $data = Read-DataFile -DataPath $DataPath
        if ($null -eq $data) {
            Write-Host "[WARN] Could not read data file, returning empty record" -ForegroundColor Yellow
            return @{
                requestDate = (Get-Date -Format "yyyy-MM-dd")
                totalRequests = 0
                successfulRequests = 0
            }
        }
        
        $today = Get-Date -Format "yyyy-MM-dd"
        
        # 获取数组
        $dailyStatusArray = Get-DailyRequestStatusArray -Data $data
        $todayRecord = Find-TodayRecord -DailyStatusArray $dailyStatusArray -TargetDate $today
        
        if ($null -eq $todayRecord) {
            Write-Host "[INFO] No record for today, creating new record" -ForegroundColor Gray
            return @{
                requestDate = $today
                totalRequests = 0
                successfulRequests = 0
            }
        }
        
        return @{
            requestDate = $todayRecord.requestDate
            totalRequests = $todayRecord.totalRequests
            successfulRequests = $todayRecord.successfulRequests
        }
    }
    catch {
        Write-Host "[ERROR] Error reading today's request record: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            requestDate = (Get-Date -Format "yyyy-MM-dd")
            totalRequests = 0
            successfulRequests = 0
        }
    }
}

function Test-DailyLimit {
    <#
    .SYNOPSIS
    检查是否超过每日请求限制
    
    .DESCRIPTION
    检查今日已发送的请求数量是否超过配置中设定的每日限制
    
    .PARAMETER ConfigPath
    配置文件路径
    
    .PARAMETER DataPath
    数据文件路径
    
    .OUTPUTS
    Boolean indicating if within daily limit
    #>
    param(
        [string]$ConfigPath = "config.json",
        [string]$DataPath = "data.json"
    )
    
    try {
        # Read configuration
        $config = Read-Config -ConfigPath $ConfigPath
        if ($null -eq $config) {
            Write-Host "[ERROR] Could not read configuration" -ForegroundColor Red
            return $false
        }
        
        # Get today's record
        $todayRecord = Get-TodayRequestRecord -DataPath $DataPath
        
        $withinLimit = $todayRecord.totalRequests -lt $config.maxDailyRequests
        
        Write-Host "[INFO] Today's record: Total=$($todayRecord.totalRequests), Successful=$($todayRecord.successfulRequests)" -ForegroundColor Gray
        Write-Host "[INFO] Current requests: $($todayRecord.totalRequests) / $($config.maxDailyRequests)" -ForegroundColor Gray
        Write-Host "[INFO] Remaining requests: $($config.maxDailyRequests - $todayRecord.totalRequests)" -ForegroundColor Gray
        
        if ($withinLimit) {
            Write-Host "[OK] Within daily limit" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] DAILY LIMIT REACHED!" -ForegroundColor Red
        }
        
        return $withinLimit
    }
    catch {
        Write-Host "[ERROR] Error checking daily limit: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Update-DailyRequestStatus {
    <#
    .SYNOPSIS
    更新每日请求状态
    
    .DESCRIPTION
    更新data.json中的每日请求统计信息
    
    .PARAMETER DataPath
    数据文件路径
    
    .PARAMETER IncrementTotal
    是否增加总请求数
    
    .PARAMETER IncrementSuccessful
    是否增加成功请求数
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [string]$DataPath = "data.json",
        [switch]$IncrementTotal,
        [switch]$IncrementSuccessful
    )
    
    try {
        $data = Read-DataFile -DataPath $DataPath
        if ($null -eq $data) {
            Write-Host "[ERROR] Could not read data file" -ForegroundColor Red
            return $false
        }
        
        $today = Get-Date -Format "yyyy-MM-dd"
        
        # 获取当前数组
        $dailyStatusArray = Get-DailyRequestStatusArray -Data $data
        $todayRecord = Find-TodayRecord -DailyStatusArray $dailyStatusArray -TargetDate $today
        
        # 初始化或获取今日记录
        if ($null -eq $todayRecord) {
            $todayRecord = @{
                requestDate = $today
                totalRequests = 0
                successfulRequests = 0
            }
        } else {
            # 转换为可修改的哈希表
            $todayRecord = @{
                requestDate = $todayRecord.requestDate
                totalRequests = $todayRecord.totalRequests
                successfulRequests = $todayRecord.successfulRequests
            }
        }
        
        # 更新计数器
        if ($IncrementTotal) {
            $todayRecord.totalRequests++
            Write-Host "[INFO] Total requests updated: $($todayRecord.totalRequests)" -ForegroundColor Gray
        }
        
        if ($IncrementSuccessful) {
            $todayRecord.successfulRequests++
            Write-Host "[INFO] Successful requests updated: $($todayRecord.successfulRequests)" -ForegroundColor Gray
        }
        
        # 更新数组
        $updatedArray = Update-DailyStatusArray -DailyStatusArray $dailyStatusArray -TodayRecord $todayRecord
        # 强制 dailyRequestStatus 为数组格式
        if ($updatedArray -isnot [Array]) {
            $updatedArray = @($updatedArray)
        }
        $data.dailyRequestStatus = $updatedArray

        # 保存更新的数据
        $saveResult = Write-DataFile -DataPath $DataPath -Data $data
        if ($saveResult) {
            Write-Host "[OK] Daily request status updated successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[ERROR] Failed to save updated daily request status" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "[ERROR] Error updating daily request status: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Invoke-DailyLimitCheck {
    <#
    .SYNOPSIS
    执行每日限制检查的主函数
    
    .DESCRIPTION
    综合检查每日请求限制，显示详细信息
    
    .PARAMETER ConfigPath
    配置文件路径
    
    .PARAMETER DataPath
    数据文件路径
    
    .PARAMETER ShowSummary
    是否显示详细摘要
    
    .OUTPUTS
    Boolean indicating if within limit
    #>
    param(
        [string]$ConfigPath = "config.json",
        [string]$DataPath = "data.json",
        [switch]$ShowSummary
    )
    
    Write-Host "" -ForegroundColor Gray
    Write-Host "=== Daily Limit Check ===" -ForegroundColor Cyan
    Write-Host "Checking daily request limit..." -ForegroundColor Gray
    
    try {
        $result = Test-DailyLimit -ConfigPath $ConfigPath -DataPath $DataPath
        
        if ($ShowSummary) {
            $config = Read-Config -ConfigPath $ConfigPath
            $todayRecord = Get-TodayRequestRecord -DataPath $DataPath
            
            Write-Host "[INFO] Daily Limit Summary:" -ForegroundColor Cyan
            Write-Host "  Max Daily Requests: $($config.maxDailyRequests)" -ForegroundColor Gray
            Write-Host "  Today's Total: $($todayRecord.totalRequests)" -ForegroundColor Gray
            Write-Host "  Today's Successful: $($todayRecord.successfulRequests)" -ForegroundColor Gray
            Write-Host "  Remaining: $($config.maxDailyRequests - $todayRecord.totalRequests)" -ForegroundColor Gray
        }
        
        if (-not $result) {
            Write-Host "" -ForegroundColor Gray
            Write-Host "[STOP] EXECUTION STOPPED - Daily request limit reached!" -ForegroundColor Red
            $config = Read-Config -ConfigPath $ConfigPath
            $todayRecord = Get-TodayRequestRecord -DataPath $DataPath
            Write-Host "Current requests: $($todayRecord.totalRequests)" -ForegroundColor Red
            Write-Host "Maximum allowed: $($config.maxDailyRequests)" -ForegroundColor Red
            Write-Host "Please try again tomorrow or increase the limit in config.json" -ForegroundColor Yellow
        } else {
            Write-Host "[OK] Daily limit check passed" -ForegroundColor Green
            $config = Read-Config -ConfigPath $ConfigPath
            $todayRecord = Get-TodayRequestRecord -DataPath $DataPath
            Write-Host "Remaining requests today: $($config.maxDailyRequests - $todayRecord.totalRequests)" -ForegroundColor Green
        }
        
        Write-Host "========================" -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Gray
        
        return $result
    }
    catch {
        Write-Host "[ERROR] Daily limit check failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "========================" -ForegroundColor Cyan
        return $false
    }
}

# Functions are available when dot-sourced