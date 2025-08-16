# smart-api.ps1 - Main control script for PowerShell API Manager
# author: aiqubit@hotmail.com from openpick.org

param(
    [string]$ConfigPath = "config.json",
    [string]$DataPath = "data.json",
    [string]$RequestHistoryPath = "requestHistory.json",
    [hashtable]$CustomRequestBody = $null,
    [switch]$TestMode,
    [switch]$SkipLimitCheck,
    [switch]$Verbose,
    [switch]$SingleMode
)

# Set console encoding to UTF-8 for proper character display
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # For older PowerShell versions
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        chcp 65001 | Out-Null
    }
} catch {
    Write-Warning "Could not set UTF-8 encoding. Some characters may not display correctly."
}

# Define display symbols that work in all PowerShell environments
$script:Symbols = @{
    Success = "[OK]"
    Error = "[ERROR]"
    Warning = "[WARN]"
    Info = "[INFO]"
    Process = "[PROC]"
    Check = "[CHECK]"
    Save = "[SAVE]"
    Send = "[SEND]"
    Config = "[CONFIG]"
    Data = "[DATA]"
    Network = "[NET]"
    Email = "[EMAIL]"
    Test = "[TEST]"
    Complete = "[DONE]"
    Start = "[START]"
    Stop = "[STOP]"
}

# Set error action preference
$ErrorActionPreference = "Stop"

# Import required modules - load type definitions first
try {
    . "$PSScriptRoot\SymbolDefinitions.ps1"
    . "$PSScriptRoot\ConfigManager.ps1"
    . "$PSScriptRoot\DataManager.ps1" 
    . "$PSScriptRoot\DailyLimitManager.ps1"
    . "$PSScriptRoot\HttpRequestManager.ps1"
    . "$PSScriptRoot\EmailManager.ps1"
    . "$PSScriptRoot\RequestHistoryManager.ps1"
    Write-Host "All required modules loaded successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to import required modules: $($_.Exception.Message)"
    exit 1
}

function Initialize-SmartApi {
    <#
    .SYNOPSIS
    程序启动时的配置和数据文件检查
    
    .DESCRIPTION
    检查并初始化配置文件和数据文件，确保程序运行环境正常
    
    .OUTPUTS
    Hashtable containing initialization results
    #>
    
    Write-Host "`n$($script:Symbols.Start) Initializing Smart API Manager..." -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    
    $initResult = @{
        ConfigValid = $false
        DataFileReady = $false
        CanProceed = $false
        Config = $null
        Errors = @()
    }
    
    try {
        # Step 1: Check and load configuration file
        Write-Host "`n$($script:Symbols.Config) Step 1: Configuration File Check" -ForegroundColor Yellow
        Write-Host "Checking configuration file: $ConfigPath" -ForegroundColor Gray
        
        $config = Read-Config -ConfigPath $ConfigPath
        if ($null -eq $config) {
            $initResult.Errors += "Failed to load configuration file"
            Write-Host "$($script:Symbols.Error) Configuration check failed" -ForegroundColor Red
        } else {
            $initResult.ConfigValid = $true
            $initResult.Config = $config
            Write-Host "$($script:Symbols.Success) Configuration loaded successfully" -ForegroundColor Green
            
            if ($Verbose) {
                Show-ConfigSummary -Config $config
            }
        }
        
        # Step 2: Check and initialize data file
        Write-Host "`n$($script:Symbols.Data) Step 2: Data File Check" -ForegroundColor Yellow
        Write-Host "Checking data file: $DataPath" -ForegroundColor Gray
        
        # Ensure data file exists and is properly formatted
        if (-not (Test-Path $DataPath)) {
            Write-Host "Data file not found, creating new one..." -ForegroundColor Yellow
            $dataInitResult = Initialize-DataFile -DataPath $DataPath
            if (-not $dataInitResult) {
                $initResult.Errors += "Failed to initialize data file"
                Write-Host "$($script:Symbols.Error) Data file initialization failed" -ForegroundColor Red
            } else {
                Write-Host "$($script:Symbols.Success) Data file created successfully" -ForegroundColor Green
                $initResult.DataFileReady = $true
            }
        } else {
            # Validate existing data file
            $dataValidResult = Test-DataFileFormat -DataPath $DataPath
            if (-not $dataValidResult) {
                Write-Host "Data file format invalid, attempting repair..." -ForegroundColor Yellow
                $repairResult = Repair-DataFile -DataPath $DataPath
                if (-not $repairResult) {
                    $initResult.Errors += "Failed to repair data file"
                    Write-Host "$($script:Symbols.Error) Data file repair failed" -ForegroundColor Red
                } else {
                    Write-Host "$($script:Symbols.Success) Data file repaired successfully" -ForegroundColor Green
                    $initResult.DataFileReady = $true
                }
            } else {
                Write-Host "$($script:Symbols.Success) Data file validation passed" -ForegroundColor Green
                $initResult.DataFileReady = $true
                
                if ($Verbose) {
                    Show-DataFileSummary -DataPath $DataPath -RequestHistoryPath $RequestHistoryPath
                }
            }
        }
        
        # Step 2.1: Check and initialize request history file
        Write-Host "`n$($script:Symbols.Data) Step 2.1: Request History File Check" -ForegroundColor Yellow
        Write-Host "Checking request history file: $RequestHistoryPath" -ForegroundColor Gray
        
        # Ensure request history file exists and is properly formatted
        if (-not (Test-Path $RequestHistoryPath)) {
            Write-Host "Request history file not found, creating new one..." -ForegroundColor Yellow
            $historyInitResult = Initialize-RequestHistoryFile -HistoryPath $RequestHistoryPath -Config $config
            if (-not $historyInitResult) {
                $initResult.Errors += "Failed to initialize request history file"
                Write-Host "$($script:Symbols.Error) Request history file initialization failed" -ForegroundColor Red
                $initResult.DataFileReady = $false
            } else {
                Write-Host "$($script:Symbols.Success) Request history file created successfully" -ForegroundColor Green
            }
        } else {
            # Validate existing request history file
            $historyValidResult = Test-RequestHistoryFileFormat -HistoryPath $RequestHistoryPath
            if (-not $historyValidResult) {
                Write-Host "Request history file format invalid, attempting repair..." -ForegroundColor Yellow
                $historyRepairResult = Repair-RequestHistoryFile -HistoryPath $RequestHistoryPath
                if (-not $historyRepairResult) {
                    $initResult.Errors += "Failed to repair request history file"
                    Write-Host "$($script:Symbols.Error) Request history file repair failed" -ForegroundColor Red
                    $initResult.DataFileReady = $false
                } else {
                    Write-Host "$($script:Symbols.Success) Request history file repaired successfully" -ForegroundColor Green
                }
            } else {
                Write-Host "$($script:Symbols.Success) Request history file validation passed" -ForegroundColor Green
            }
        }
        
        # Step 3: Overall initialization result
        $initResult.CanProceed = $initResult.ConfigValid -and $initResult.DataFileReady
        
        Write-Host "`n$($script:Symbols.Info) Initialization Summary:" -ForegroundColor Cyan
        Write-Host "Configuration: $(if($initResult.ConfigValid){"$($script:Symbols.Success) Ready"}else{"$($script:Symbols.Error) Failed"})" -ForegroundColor $(if($initResult.ConfigValid){'Green'}else{'Red'})
        Write-Host "Data File: $(if($initResult.DataFileReady){"$($script:Symbols.Success) Ready"}else{"$($script:Symbols.Error) Failed"})" -ForegroundColor $(if($initResult.DataFileReady){'Green'}else{'Red'})
        Write-Host "Can Proceed: $(if($initResult.CanProceed){"$($script:Symbols.Success) Yes"}else{"$($script:Symbols.Error) No"})" -ForegroundColor $(if($initResult.CanProceed){'Green'}else{'Red'})
        
        if ($initResult.Errors.Count -gt 0) {
            Write-Host "`n$($script:Symbols.Error) Initialization Errors:" -ForegroundColor Red
            $initResult.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
        
        Write-Host "=================================`n" -ForegroundColor Cyan
        
        return $initResult
    }
    catch {
        $initResult.Errors += "Unexpected error during initialization: $($_.Exception.Message)"
        Write-Host "$($script:Symbols.Error) Initialization failed with error: $($_.Exception.Message)" -ForegroundColor Red
        return $initResult
    }
}

function Update-RequestStatistics {
    <#
    .SYNOPSIS
    更新每日请求统计数据（总数和成功数）
    
    .DESCRIPTION
    根据请求结果更新data.json中的每日统计信息
    
    .PARAMETER IsSuccessful
    请求是否成功
    
    .PARAMETER IncrementTotal
    是否增加总请求数
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [bool]$IsSuccessful = $false,
        [bool]$IncrementTotal = $true
    )
    
    try {
        $updateSuccess = $true
        
        # Update total requests count
        if ($IncrementTotal) {
            $totalResult = Update-DailyRequestStatus -DataPath $DataPath -IncrementTotal
            if (-not $totalResult) {
                Write-Host "$($script:Symbols.Warning) Warning: Failed to update total request count" -ForegroundColor Yellow
                $updateSuccess = $false
            } else {
                Write-Host "$($script:Symbols.Info) Total request count updated" -ForegroundColor Gray
            }
        }
        
        # Update successful requests count if applicable
        if ($IsSuccessful) {
            $successResult = Update-DailyRequestStatus -DataPath $DataPath -IncrementSuccessful
            if (-not $successResult) {
                Write-Host "$($script:Symbols.Warning) Warning: Failed to update successful request count" -ForegroundColor Yellow
                $updateSuccess = $false
            } else {
                Write-Host "$($script:Symbols.Info) Successful request count updated" -ForegroundColor Gray
            }
        }
        
        return $updateSuccess
    }
    catch {
        Write-Host "$($script:Symbols.Error) Error updating request statistics: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Save-RequestToHistory {
    <#
    .SYNOPSIS
    实现请求历史记录的追加功能
    
    .DESCRIPTION
    将POST请求结果写入requestHistory.json的历史记录中，包括成功和失败的请求
    
    .PARAMETER Response
    ResponseModel object containing request results
    
    .PARAMETER IncludeFullData
    Whether to include full response data
    
    .PARAMETER Config
    Configuration object containing maxHistoryFileSizeMB setting
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Response,
        
        [bool]$IncludeFullData = $false,
        
        [Parameter(Mandatory=$false)]
        $Config = $null
    )
    
    try {
        # Validate Response parameter using shared validation function
        if (-not (Test-ResponseModelObject -Object $Response)) {
            Write-Host "$($script:Symbols.Error) Invalid Response parameter: Expected valid ResponseModel object" -ForegroundColor Red
            return $false
        }
        
        Write-Host "$($script:Symbols.Save) Saving request to history..." -ForegroundColor Gray
        
        # Determine what data to include based on success and settings
        $includeFullData = $IncludeFullData -and ($Response.Status -eq "Success")
        
        # Format response for storage
        $formattedResponse = Format-ResponseForStorage -Response $Response -IncludeFullData $includeFullData
        
        # Add additional metadata
        $formattedResponse["requestTimestamp"] = $Response.Timestamp
        $formattedResponse["persistedAt"] = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        
        # Add to request history using RequestHistoryManager
        $historyResult = Add-RequestHistoryEntry -HistoryPath $RequestHistoryPath -Status $Response.Status -ResponseCode $Response.StatusCode -ResponseData $formattedResponse -Timestamp $Response.Timestamp -Config $Config
        
        if ($historyResult) {
            $dataType = if ($includeFullData) { "full data" } else { "summary" }
            Write-Host "$($script:Symbols.Success) Request saved to history ($dataType)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "$($script:Symbols.Error) Failed to save request to history" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "$($script:Symbols.Error) Error saving request to history: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Invoke-DataPersistence {
    <#
    .SYNOPSIS
    集成数据持久化功能的主函数
    
    .DESCRIPTION
    处理所有数据持久化操作，包括统计更新和历史记录保存
    
    .PARAMETER Response
    ResponseModel object
    
    .PARAMETER RequestWasSent
    Whether the request was actually sent
    
    .PARAMETER ResponseWasValid
    Whether the response was valid
    
    .PARAMETER Config
    Configuration object containing maxHistoryFileSizeMB setting
    
    .OUTPUTS
    Hashtable with persistence results
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Response,
        
        [bool]$RequestWasSent = $false,
        [bool]$ResponseWasValid = $false,
        
        [Parameter(Mandatory=$false)]
        $Config = $null
    )
    
    $persistenceResult = @{
        StatisticsUpdated = $false
        HistorySaved = $false
        Success = $false
        Errors = @()
    }
    
    try {
        # Validate Response parameter using shared validation function
        if (-not (Test-ResponseModelObject -Object $Response)) {
            $persistenceResult.Errors += "Invalid Response parameter: Expected valid ResponseModel object"
            Write-Host "$($script:Symbols.Error) Invalid Response parameter: Expected valid ResponseModel object" -ForegroundColor Red
            return $persistenceResult
        }
        
        Write-Host "`n$($script:Symbols.Save) Data Persistence Operations" -ForegroundColor Yellow
        
        # Determine if this was a successful request
        $isSuccessful = $RequestWasSent -and $ResponseWasValid -and ($Response.Status -eq "Success")
        
        # Update request statistics
        Write-Host "$($script:Symbols.Info) Updating request statistics..." -ForegroundColor Gray
        $statsResult = Update-RequestStatistics -IsSuccessful $isSuccessful -IncrementTotal $RequestWasSent
        $persistenceResult.StatisticsUpdated = $statsResult
        
        if (-not $statsResult) {
            $persistenceResult.Errors += "Failed to update request statistics"
        }
        
        # Save to request history
        Write-Host "$($script:Symbols.Save) Saving to request history..." -ForegroundColor Gray
        $historyResult = Save-RequestToHistory -Response $Response -IncludeFullData $isSuccessful -Config $Config
        $persistenceResult.HistorySaved = $historyResult
        
        if (-not $historyResult) {
            $persistenceResult.Errors += "Failed to save request to history"
        }
        
        # Overall success
        $persistenceResult.Success = $persistenceResult.StatisticsUpdated -and $persistenceResult.HistorySaved
        
        # Display results
        Write-Host "Statistics Updated: $(if($persistenceResult.StatisticsUpdated){"$($script:Symbols.Success) Yes"}else{"$($script:Symbols.Error) No"})" -ForegroundColor $(if($persistenceResult.StatisticsUpdated){'Green'}else{'Red'})
        Write-Host "History Saved: $(if($persistenceResult.HistorySaved){"$($script:Symbols.Success) Yes"}else{"$($script:Symbols.Error) No"})" -ForegroundColor $(if($persistenceResult.HistorySaved){'Green'}else{'Red'})
        Write-Host "Persistence Success: $(if($persistenceResult.Success){"$($script:Symbols.Success) Complete"}else{"$($script:Symbols.Error) Failed"})" -ForegroundColor $(if($persistenceResult.Success){'Green'}else{'Red'})
        
        return $persistenceResult
    }
    catch {
        $persistenceResult.Errors += "Unexpected error in data persistence: $($_.Exception.Message)"
        Write-Host "$($script:Symbols.Error) Data persistence error: $($_.Exception.Message)" -ForegroundColor Red
        return $persistenceResult
    }
}

function Invoke-BatchRequests {
    <#
    .SYNOPSIS
    执行批量请求，基于maxDailyRequests配置
    
    .DESCRIPTION
    根据配置文件中的maxDailyRequests值和当前已发送的请求数，计算并执行剩余的批量请求
    
    .PARAMETER Config
    Configuration object
    
    .PARAMETER CustomBody
    Optional custom request body
    
    .PARAMETER RequestDelay
    请求之间的延迟时间（秒）
    
    .OUTPUTS
    Hashtable containing batch execution results
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ConfigModel]$Config,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$CustomBody = $null,
        
        [int]$RequestDelay = 1
    )
    
    Write-Host "$($script:Symbols.Process) Starting Batch Request Execution..." -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    
    $batchResult = @{
        TotalRequests = 0
        SuccessfulRequests = 0
        FailedRequests = 0
        Responses = @()
        Success = $false
        Errors = @()
    }
    
    try {
        # 获取今日已发送的请求记录
        $todayRecord = Get-TodayRequestRecord -DataPath $DataPath

        $randNum = Get-Random -Minimum 0 -Maximum $Config.randomNumber
        $maxRequestNum = $Config.maxDailyRequests - $randNum

        $remainingRequests = $maxRequestNum - $todayRecord.totalRequests
        
        Write-Host "$($script:Symbols.Info) Batch Request Planning:" -ForegroundColor Cyan
        Write-Host "  Max Daily Requests: $($Config.maxDailyRequests)" -ForegroundColor Gray
        Write-Host "  Today's Total: $($todayRecord.totalRequests)" -ForegroundColor Gray
        Write-Host "  Remaining Requests: $remainingRequests" -ForegroundColor Gray

        if ($remainingRequests -le 0) {
            Write-Host "$($script:Symbols.Warning) No remaining requests for today" -ForegroundColor Yellow
            $batchResult.Success = $true
            return $batchResult
        }
        
        # 执行批量请求
        Write-Host "$($script:Symbols.Send) Executing $remainingRequests batch requests..." -ForegroundColor Yellow
        
        for ($i = 1; $i -le $remainingRequests; $i++) {
            Write-Host "`n$($script:Symbols.Network) Request $i of $remainingRequests" -ForegroundColor Cyan
            
            # 发送单个请求
            if ($TestMode) {
                Write-Host "$($script:Symbols.Test) Test mode: Using test endpoint functionality" -ForegroundColor Cyan
                $testResults = Test-ApiEndpoint -Config $Config -TestBody $CustomBody
                $response = $testResults.Details["Response"]
                $requestSent = $testResults.RequestTest
            } else {
                $response = Send-PostRequestWithRetry -Config $Config -CustomBody $CustomBody -MaxRetries 3
                $requestSent = ($response.Status -eq "Success")
            }
            
            # 处理响应为空的情况
            if ($null -eq $response) {
                Write-Host "$($script:Symbols.Error) No response received (connection failed)" -ForegroundColor Red
                $response = [ResponseModel]::new()
                $response.Status = "ConnectionFailed"
                $response.StatusCode = 0
                $response.ErrorMessage = "Connection to API endpoint failed"
                $requestSent = $false
            }
            
            # 验证响应
            $validationResult = Test-ResponseValidation -Response $response
            $responseValid = $validationResult.IsValid
            
            # 更新统计
            $batchResult.TotalRequests++
            if ($requestSent -and $responseValid) {
                $batchResult.SuccessfulRequests++
                Write-Host "$($script:Symbols.Success) Request $i completed successfully" -ForegroundColor Green
            } else {
                $batchResult.FailedRequests++
                Write-Host "$($script:Symbols.Error) Request $i failed" -ForegroundColor Red
                if ($response.ErrorMessage) {
                    $batchResult.Errors += "Request $i : $($response.ErrorMessage)"
                }
            }
            
            # 保存响应到结果集
            $batchResult.Responses += $response
            
            # 数据持久化
            $persistenceResult = Invoke-DataPersistence -Response $response -RequestWasSent $requestSent -ResponseWasValid $responseValid -Config $Config
            if (-not $persistenceResult.Success) {
                Write-Host "$($script:Symbols.Warning) Data persistence failed for request $i" -ForegroundColor Yellow
            }
            
            # 请求间延迟（除了最后一个请求）
            if ($i -lt $remainingRequests -and $RequestDelay -gt 0) {
                Write-Host "$($script:Symbols.Info) Waiting $RequestDelay seconds before next request..." -ForegroundColor Gray
                Start-Sleep -Seconds $RequestDelay
            }
        }
        
        # 批量执行结果
        $batchResult.Success = $batchResult.TotalRequests -gt 0
        
        Write-Host "`n$($script:Symbols.Info) Batch Execution Summary:" -ForegroundColor Cyan
        Write-Host "  Total Requests: $($batchResult.TotalRequests)" -ForegroundColor Gray
        Write-Host "  Successful: $($batchResult.SuccessfulRequests)" -ForegroundColor Green
        Write-Host "  Failed: $($batchResult.FailedRequests)" -ForegroundColor Red
        Write-Host "  Success Rate: $(if($batchResult.TotalRequests -gt 0){[math]::Round(($batchResult.SuccessfulRequests / $batchResult.TotalRequests) * 100, 2)}else{0})%" -ForegroundColor Gray
        
        Write-Host "======================================`n" -ForegroundColor Cyan
        
        return $batchResult
    }
    catch {
        $batchResult.Errors += "Unexpected error in batch execution: $($_.Exception.Message)"
        Write-Host "$($script:Symbols.Error) Batch execution failed: $($_.Exception.Message)" -ForegroundColor Red
        return $batchResult
    }
}

function Invoke-MainWorkflow {
    <#
    .SYNOPSIS
    集成每日限制检查、HTTP请求发送、响应处理的完整流程
    
    .DESCRIPTION
    执行完整的API请求工作流程，包括限制检查、请求发送和数据持久化
    支持单次请求模式和批量请求模式
    
    .PARAMETER Config
    Configuration object
    
    .PARAMETER CustomBody
    Optional custom request body
    
    .PARAMETER SingleMode
    是否启用单次请求模式（默认为批量模式）
    
    .OUTPUTS
    Hashtable containing workflow execution results
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ConfigModel]$Config,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$CustomBody = $null,
        
        [switch]$SingleMode
    )
    
    Write-Host "$($script:Symbols.Process) Starting Main Workflow..." -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    
    $workflowResult = @{
        LimitCheckPassed = $false
        RequestSent = $false
        ResponseProcessed = $false
        DataPersisted = $false
        Success = $false
        Response = $null
        BatchResult = $null
        Errors = @()
    }
    
    try {
        # Step 1: Daily Limit Check (unless skipped)
        if (-not $SkipLimitCheck) {
            Write-Host "`n$($script:Symbols.Check) Step 1: Daily Limit Check" -ForegroundColor Yellow
            
            $limitCheckResult = Invoke-DailyLimitCheck -ConfigPath $ConfigPath -DataPath $DataPath -ShowSummary $Verbose
            $workflowResult.LimitCheckPassed = $limitCheckResult
            
            if (-not $limitCheckResult) {
                $workflowResult.Errors += "Daily request limit reached"
                Write-Host "$($script:Symbols.Error) Workflow stopped due to daily limit" -ForegroundColor Red
                return $workflowResult
            }
            
            Write-Host "$($script:Symbols.Success) Daily limit check passed" -ForegroundColor Green
        } else {
            Write-Host "$($script:Symbols.Warning) Daily limit check skipped (SkipLimitCheck flag)" -ForegroundColor Yellow
            $workflowResult.LimitCheckPassed = $true
        }
        
        # Step 2: Execute Requests (Single or Batch Mode)
        Write-Host "`n$($script:Symbols.Network) Step 2: Request Execution" -ForegroundColor Yellow
        
        if (-not $SingleMode) {
            # 批量请求模式（默认模式）
            Write-Host "$($script:Symbols.Info) Batch mode (default) - executing multiple requests" -ForegroundColor Cyan
            
            # 从配置中读取请求延迟设置
            $requestDelay = if ($Config.PSObject.Properties['requestDelay']) { $Config.requestDelay } else { 1 }
            
            $batchResult = Invoke-BatchRequests -Config $Config -CustomBody $CustomBody -RequestDelay $requestDelay
            $workflowResult.BatchResult = $batchResult
            
            # 设置工作流结果基于批量执行结果
            $workflowResult.RequestSent = $batchResult.SuccessfulRequests -gt 0
            $workflowResult.ResponseProcessed = $batchResult.SuccessfulRequests -gt 0
            $workflowResult.DataPersisted = $batchResult.Success
            
            # 使用最后一个成功的响应作为主响应
            $successfulResponses = $batchResult.Responses | Where-Object { $_.Status -eq "Success" }
            if ($successfulResponses.Count -gt 0) {
                $workflowResult.Response = $successfulResponses[-1]  # 最后一个成功的响应
            } else {
                $workflowResult.Response = $batchResult.Responses[-1]  # 最后一个响应
            }
            
            # 添加批量执行的错误到工作流错误
            $batchResult.Errors | ForEach-Object { $workflowResult.Errors += $_ }
            
        } else {
            # 单次请求模式（需要显式启用）
            Write-Host "$($script:Symbols.Info) Single request mode (explicitly enabled)" -ForegroundColor Gray
            
            # Send the request
            if ($TestMode) {
                Write-Host "$($script:Symbols.Test) Test mode: Using test endpoint functionality" -ForegroundColor Cyan
                $testResults = Test-ApiEndpoint -Config $Config -TestBody $CustomBody
                $response = $testResults.Details["Response"]
                $workflowResult.RequestSent = $testResults.RequestTest
            } else {
                $response = Send-PostRequestWithRetry -Config $Config -CustomBody $CustomBody -MaxRetries 3
                $workflowResult.RequestSent = ($response.Status -eq "Success")
            }
            
            # Handle case where response is null (connection failed)
            if ($null -eq $response) {
                Write-Host "$($script:Symbols.Error) No response received (connection failed)" -ForegroundColor Red
                # Create a dummy response object for error handling
                $response = [ResponseModel]::new()
                $response.Status = "ConnectionFailed"
                $response.StatusCode = 0
                $response.ErrorMessage = "Connection to API endpoint failed"
                $workflowResult.RequestSent = $false
            }
            
            $workflowResult.Response = $response
            
            if ($workflowResult.RequestSent) {
                Write-Host "$($script:Symbols.Success) HTTP request sent successfully" -ForegroundColor Green
            } else {
                Write-Host "$($script:Symbols.Error) HTTP request failed" -ForegroundColor Red
                $errorMsg = if ($response.ErrorMessage) { $response.ErrorMessage } else { "Unknown error" }
                $workflowResult.Errors += "HTTP request failed: $errorMsg"
            }
            
            # Step 3: Process Response (单次请求模式)
            Write-Host "`n$($script:Symbols.Check) Step 3: Response Processing" -ForegroundColor Yellow
            
            $validationResult = Test-ResponseValidation -Response $response
            $workflowResult.ResponseProcessed = $validationResult.IsValid
            
            if ($workflowResult.ResponseProcessed) {
                Write-Host "$($script:Symbols.Success) Response validation passed" -ForegroundColor Green
            } else {
                Write-Host "$($script:Symbols.Error) Response validation failed" -ForegroundColor Red
                $workflowResult.Errors += "Response validation failed"
                
                if ($validationResult.Errors.Count -gt 0) {
                    $validationResult.Errors | ForEach-Object { 
                        $workflowResult.Errors += "Validation error: $_"
                    }
                }
            }
            
            # Step 4: Data Persistence (单次请求模式)
            $persistenceResult = Invoke-DataPersistence -Response $response -RequestWasSent $workflowResult.RequestSent -ResponseWasValid $workflowResult.ResponseProcessed -Config $Config
            $workflowResult.DataPersisted = $persistenceResult.Success
            
            # Add persistence errors to workflow errors
            if ($persistenceResult.Errors.Count -gt 0) {
                $persistenceResult.Errors | ForEach-Object {
                    $workflowResult.Errors += $_
                }
            }
        }
        
        # Overall workflow success
        $workflowResult.Success = $workflowResult.LimitCheckPassed -and $workflowResult.RequestSent -and $workflowResult.ResponseProcessed -and $workflowResult.DataPersisted
        
        # Display workflow summary
        Write-Host "`n$($script:Symbols.Info) Workflow Summary:" -ForegroundColor Cyan
        Write-Host "Limit Check: $(if($workflowResult.LimitCheckPassed){"$($script:Symbols.Success) Passed"}else{"$($script:Symbols.Error) Failed"})" -ForegroundColor $(if($workflowResult.LimitCheckPassed){'Green'}else{'Red'})
        
        if (-not $SingleMode -and $workflowResult.BatchResult) {
            Write-Host "Batch Execution: $(if($workflowResult.BatchResult.Success){"$($script:Symbols.Success) Complete"}else{"$($script:Symbols.Error) Failed"})" -ForegroundColor $(if($workflowResult.BatchResult.Success){'Green'}else{'Red'})
            Write-Host "  Total Requests: $($workflowResult.BatchResult.TotalRequests)" -ForegroundColor Gray
            Write-Host "  Successful: $($workflowResult.BatchResult.SuccessfulRequests)" -ForegroundColor Green
            Write-Host "  Failed: $($workflowResult.BatchResult.FailedRequests)" -ForegroundColor Red
        } else {
            Write-Host "Request Sent: $(if($workflowResult.RequestSent){"$($script:Symbols.Success) Success"}else{"$($script:Symbols.Error) Failed"})" -ForegroundColor $(if($workflowResult.RequestSent){'Green'}else{'Red'})
            Write-Host "Response Processed: $(if($workflowResult.ResponseProcessed){"$($script:Symbols.Success) Valid"}else{"$($script:Symbols.Error) Invalid"})" -ForegroundColor $(if($workflowResult.ResponseProcessed){'Green'}else{'Red'})
        }
        
        Write-Host "Data Persisted: $(if($workflowResult.DataPersisted){"$($script:Symbols.Success) Saved"}else{"$($script:Symbols.Error) Failed"})" -ForegroundColor $(if($workflowResult.DataPersisted){'Green'}else{'Red'})
        Write-Host "Overall Success: $(if($workflowResult.Success){"$($script:Symbols.Success) Complete"}else{"$($script:Symbols.Error) Failed"})" -ForegroundColor $(if($workflowResult.Success){'Green'}else{'Red'})
        
        if ($workflowResult.Errors.Count -gt 0) {
            Write-Host "`n$($script:Symbols.Error) Workflow Errors:" -ForegroundColor Red
            $workflowResult.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
        
        Write-Host "============================`n" -ForegroundColor Cyan
        
        return $workflowResult
    }
    catch {
        $workflowResult.Errors += "Unexpected error in workflow: $($_.Exception.Message)"
        Write-Host "$($script:Symbols.Error) Workflow failed with error: $($_.Exception.Message)" -ForegroundColor Red
        return $workflowResult
    }
}

# Main execution block
try {
    Write-Host "Smart API Manager - PowerShell RESTful API Management Tool" -ForegroundColor Magenta
    Write-Host "==========================================================" -ForegroundColor Magenta
    Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    
    if ($TestMode) {
        Write-Host "$($script:Symbols.Test) Running in TEST MODE" -ForegroundColor Cyan
    }
    
    if ($SkipLimitCheck) {
        Write-Host "$($script:Symbols.Warning) Daily limit check is DISABLED" -ForegroundColor Yellow
    }
    
    if ($SingleMode) {
        Write-Host "$($script:Symbols.Info) Running in SINGLE REQUEST MODE" -ForegroundColor Cyan
    } else {
        Write-Host "$($script:Symbols.Info) Running in BATCH MODE (default)" -ForegroundColor Cyan
    }
    
    # Step 1: Initialize the application
    $initResult = Initialize-SmartApi
    
    if (-not $initResult.CanProceed) {
        Write-Host "$($script:Symbols.Error) Initialization failed. Cannot proceed with API requests." -ForegroundColor Red
        Write-Host "Please check the configuration and data files." -ForegroundColor Yellow
        exit 1
    }
    
    # Step 2: Execute main workflow
    $workflowResult = Invoke-MainWorkflow -Config $initResult.Config -CustomBody $CustomRequestBody -SingleMode:$SingleMode
    
    # Step 3: Send daily report email
    Write-Host "`n$($script:Symbols.Email) Step 3: Email Report" -ForegroundColor Yellow
    
    if (-not $TestMode) {
        try {
            $emailResult = Send-DailyReport -Config $initResult.Config -DataPath $DataPath -RequestHistoryPath $RequestHistoryPath -WorkflowResult $workflowResult
            if ($emailResult) {
                Write-Host "$($script:Symbols.Success) Daily report email sent successfully" -ForegroundColor Green
            } else {
                Write-Host "$($script:Symbols.Warning) Daily report email could not be sent (check email configuration)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "$($script:Symbols.Warning) Error sending daily report email: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "$($script:Symbols.Test) Test mode: Email sending skipped" -ForegroundColor Cyan
    }
    
    # Step 4: Final results and cleanup
    Write-Host "`n$($script:Symbols.Complete) Execution Complete" -ForegroundColor Magenta
    Write-Host "End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    
    if ($workflowResult.Success) {
        Write-Host "$($script:Symbols.Success) Smart API execution completed successfully!" -ForegroundColor Green
        
        if ($Verbose -and $workflowResult.Response) {
            Write-Host "`n$($script:Symbols.Info) Response Summary:" -ForegroundColor Cyan
            Write-Host (Get-ResponseSummary -Response $workflowResult.Response) -ForegroundColor Gray
        }
        
        # Show final data summary
        if ($Verbose) {
            Show-DataFileSummary -DataPath $DataPath -RequestHistoryPath $RequestHistoryPath
        }
        
        exit 0
    } else {
        Write-Host "$($script:Symbols.Error) Smart API execution failed!" -ForegroundColor Red
        
        if ($workflowResult.Errors.Count -gt 0) {
            Write-Host "`nError Details:" -ForegroundColor Red
            $workflowResult.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
        
        exit 1
    }
}
catch {
    Write-Host "$($script:Symbols.Error) Fatal error in Smart API execution: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}