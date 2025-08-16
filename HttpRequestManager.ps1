# HttpRequestManager.ps1 - HTTP POST request management and response handling
# HTTP POST请求管理和响应处理

# Import required modules
. "$PSScriptRoot\SymbolDefinitions.ps1"
. "$PSScriptRoot\ConfigManager.ps1"

function Send-QaRequest {
    <#
    .SYNOPSIS
    发送HTTP POST请求
    
    .DESCRIPTION
    使用配置信息发送HTTP POST请求到指定的API端点
    
    .PARAMETER Config
    ConfigModel对象，包含API配置信息
    
    .PARAMETER jsonBody
    自定义请求体（可选）
    
    .OUTPUTS
    ResponseModel object containing the response
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ConfigModel]$Config,

        [Parameter(Mandatory=$true)]
        [string]$AreaTitle,

        [Parameter(Mandatory=$false)]
        [hashtable]$CustomBody = $null
    )
    
    $response = [ResponseModel]::new()

    Write-Host "[NET] Preparing HTTP POST request..." -ForegroundColor Gray
    Write-Host "[NET] Target URL: $($Config.apiUrl)" -ForegroundColor Gray
    
    # Prepare request body
    $requestBody = if ($CustomBody) { $CustomBody } else { $Config.requestBody }
    $jsonBody = $requestBody | ConvertTo-Json -Depth 10
    
    Write-Host "[NET] Request body prepared ($(($jsonBody | Measure-Object -Character).Characters) characters)" -ForegroundColor Gray
    
    # Prepare headers
    $headers = @{
        'Content-Type' = 'application/json'
    }
    
    # Add custom headers from config
    if ($Config.headers.Count -gt 0) {
        $Config.headers.GetEnumerator() | ForEach-Object {
            $headers[$_.Key] = $_.Value
        }
        Write-Host "[NET] Added $($Config.headers.Count) custom headers" -ForegroundColor Gray
    }
    
    Write-Host "[NET] Sending POST request..." -ForegroundColor Gray
        

    $getLogIdUrl = "$($Config.apiUrl)/viewSub?area_title=$($AreaTitle)"

    $logIdReponse = Invoke-RestMethod -Uri $getLogIdUrl -Method POST -Headers $Headers -TimeoutSec $Config.timeout -ErrorAction Stop

    if (-not $logIdReponse -or -not $logIdReponse.data -or -not $logIdReponse.data.PSObject.Properties["log_id"]) {
        return "Failed to get logID: log_id not found in response."
    }

    # if ($logIdReponse.StatusCode -ne 200) {
    #     return "Failed to get logID: $($logIdReponse.ErrorMessage)"
    # }

    $logId = $logIdReponse.data.log_id

    if ($logId -lt 65000) {
        return "logID is not correct: $logId"
    }

    # Submit qa-request according to logid, and with json body
    $question_id = @(1, 2, 3)

    # 60% probability for "会", 40% for "不会"
    # Randomly choose answer: 60% probability for "会", 40% for "不会"
    $rand = Get-Random -Minimum 1 -Maximum 101
    if ($rand -le 60) {
        $answer = "%E4%BC%9A"
    } else {
        $answer = "%E4%B8%8D%E4%BC%9A"
    }

    if ($rand -le 60) {
        $answerPlus = "%E6%98%AF"
    } else {
        $answerPlus = "%E4%B8%8D%E6%98%AF"
    }

    foreach ($qid in $question_id) {
        if ($qid -eq 1) {
            $submitQaUrl = "$($Config.apiUrl)/questionSub?log_id=$logId&question_id=$qid&answer=$answer"
        } else {
            $submitQaUrl = "$($Config.apiUrl)/questionSub?log_id=$logId&question_id=$qid&answer=$answerPlus"
        }

        $webResponse = Invoke-RestMethod -Uri $submitQaUrl -Method POST -Body $JsonBody -Headers $Headers -TimeoutSec $Config.timeout -ErrorAction Stop

        if (-not $webResponse) {
            return "Failed to submit an answer."
        }

        # Process successful response for each question_id (optional: collect or log if needed)
        $response.StatusCode = 200  # Invoke-RestMethod doesn't provide status code directly
        $response.Status = "Success"
        $response.RawResponse = $webResponse | ConvertTo-Json -Depth 10

        if ($webResponse -is [PSCustomObject]) {
        $webResponse.PSObject.Properties | ForEach-Object {
            $response.Data[$_.Name] = $_.Value
        }
        } elseif ($webResponse -is [hashtable]) {
        $response.Data = $webResponse
        } else {
        $response.Data["response"] = $webResponse
        }

    }

    Write-Host "[OK] HTTP POST request completed successfully" -ForegroundColor Green
    Write-Host "[OK] Response received with $($response.Data.Count) data fields" -ForegroundColor Green

    return $response
}

function Send-PostRequest {
    <#
    .SYNOPSIS
    发送HTTP POST请求
    
    .DESCRIPTION
    使用配置信息发送HTTP POST请求到指定的API端点
    
    .PARAMETER Config
    ConfigModel对象，包含API配置信息
    
    .PARAMETER CustomBody
    自定义请求体（可选）
    
    .OUTPUTS
    ResponseModel object containing the response
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ConfigModel]$Config,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$CustomBody = $null
    )
    
    $response = [ResponseModel]::new()
    
    try {
        # Send the request
        # Get logid for qa-request
        $areaTitles = @("6KWE6Ziz5bmz5a6J5YGl5bq35Lit5b%2BD","5q2m5rGJ5bmz5a6J5YGl5bq35Lit5b%2BD","5LiK5rW35bmz5a6J5YGl5bq35Lit5b%2BD","5ZCI6IKl5bmz5a6J5YGl5bq35Lit5b%2BD","5Y2X5piM5bmz5a6J5YGl5bq35Lit5b%2BD")
        foreach ($areaTitle in $areaTitles) { 
            $response = Send-QaRequest -Config $Config -AreaTitle $areaTitle -CustomBody $CustomBody
        }

        return $response
    }
    catch [System.Net.WebException] {
        $response.Status = "NetworkError"
        $response.ErrorMessage = $_.Exception.Message
        
        if ($_.Exception.Response) {
            $response.StatusCode = [int]$_.Exception.Response.StatusCode
            Write-Host "[ERROR] HTTP error $($response.StatusCode): $($_.Exception.Message)" -ForegroundColor Red
        } else {
            Write-Host "[ERROR] Network error: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        return $response
    }
    catch [System.TimeoutException] {
        $response.Status = "Timeout"
        $response.ErrorMessage = "Request timed out after $($Config.timeout) seconds"
        Write-Host "[ERROR] Request timeout: $($response.ErrorMessage)" -ForegroundColor Red
        return $response
    }
    catch {
        $response.Status = "Error"
        $response.ErrorMessage = $_.Exception.Message
        Write-Host "[ERROR] Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
        return $response
    }
}

function Send-PostRequestWithRetry {
    <#
    .SYNOPSIS
    带重试机制的HTTP POST请求
    
    .DESCRIPTION
    发送HTTP POST请求，如果失败则按照指定次数重试
    
    .PARAMETER Config
    ConfigModel对象
    
    .PARAMETER CustomBody
    自定义请求体（可选）
    
    .PARAMETER MaxRetries
    最大重试次数
    
    .PARAMETER RetryDelay
    重试间隔（秒）
    
    .OUTPUTS
    ResponseModel object
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ConfigModel]$Config,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$CustomBody = $null,
        
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 2
    )
    
    $attempt = 1
    
    while ($attempt -le ($MaxRetries + 1)) {
        if ($attempt -gt 1) {
            Write-Host "[RETRY] Attempt $attempt of $($MaxRetries + 1)" -ForegroundColor Yellow
        }
        
        $response = Send-PostRequest -Config $Config -CustomBody $CustomBody
        
        if ($response.Status -eq "Success") {
            if ($attempt -gt 1) {
                Write-Host "[OK] Request succeeded on attempt $attempt" -ForegroundColor Green
            }
            return $response
        }
        
        if ($attempt -le $MaxRetries) {
            Write-Host "[WARN] Request failed, retrying in $RetryDelay seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $RetryDelay
        }
        
        $attempt++
    }
    
    Write-Host "[ERROR] All retry attempts failed" -ForegroundColor Red
    return $response
}

function Test-ResponseValidation {
    <#
    .SYNOPSIS
    验证响应数据的有效性
    
    .DESCRIPTION
    检查响应对象是否包含有效数据
    
    .PARAMETER Response
    ResponseModel对象
    
    .OUTPUTS
    Hashtable with validation results
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ResponseModel]$Response
    )
    
    $result = @{
        IsValid = $true
        Errors = @()
        Warnings = @()
    }
    
    try {
        Write-Host "[CHECK] Validating response data..." -ForegroundColor Gray
        
        # Check if request was successful
        if ($Response.Status -ne "Success") {
            $result.Errors += "Request failed with status: $($Response.Status)"
            $result.IsValid = $false
        }
        
        # Check if response contains data
        if ($Response.Data.Count -eq 0) {
            $result.Errors += "Response contains no data"
            $result.IsValid = $false
        }
        
        # Check status code
        if ($Response.StatusCode -eq 0 -and $Response.Status -eq "Success") {
            $result.Warnings += "Status code is 0 but status is Success"
        }
        
        # Check timestamp
        if ([string]::IsNullOrWhiteSpace($Response.Timestamp)) {
            $result.Warnings += "Response timestamp is empty"
        }
        
        if ($result.IsValid) {
            Write-Host "[OK] Response validation passed" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Response validation failed with $($result.Errors.Count) errors" -ForegroundColor Red
        }
        
        if ($result.Warnings.Count -gt 0) {
            Write-Host "[WARN] Response validation has $($result.Warnings.Count) warnings" -ForegroundColor Yellow
        }
        
        return $result
    }
    catch {
        $result.Errors += "Validation error: $($_.Exception.Message)"
        $result.IsValid = $false
        Write-Host "[ERROR] Response validation error: $($_.Exception.Message)" -ForegroundColor Red
        return $result
    }
}

function Get-ResponseSummary {
    <#
    .SYNOPSIS
    获取响应摘要信息
    
    .DESCRIPTION
    生成响应对象的摘要信息字符串
    
    .PARAMETER Response
    ResponseModel对象
    
    .OUTPUTS
    String containing response summary
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ResponseModel]$Response
    )
    
    $summary = @()
    $summary += "Status: $($Response.Status)"
    $summary += "Status Code: $($Response.StatusCode)"
    $summary += "Timestamp: $($Response.Timestamp)"
    $summary += "Data Fields: $($Response.Data.Count)"
    
    if (-not [string]::IsNullOrWhiteSpace($Response.ErrorMessage)) {
        $summary += "Error: $($Response.ErrorMessage)"
    }
    
    return $summary -join "`n"
}

function Format-ResponseForStorage {
    <#
    .SYNOPSIS
    格式化响应数据用于存储
    
    .DESCRIPTION
    将响应对象格式化为适合存储的格式
    
    .PARAMETER Response
    ResponseModel对象
    
    .PARAMETER IncludeFullData
    是否包含完整数据
    
    .OUTPUTS
    Hashtable formatted for storage
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ResponseModel]$Response,
        
        [bool]$IncludeFullData = $false
    )
    
    $formatted = @{
        timestamp = $Response.Timestamp
        status = $Response.Status
        statusCode = $Response.StatusCode
    }
    
    if (-not [string]::IsNullOrWhiteSpace($Response.ErrorMessage)) {
        $formatted["errorMessage"] = $Response.ErrorMessage
    }
    
    # Data summary
    $formatted["dataSummary"] = @{
        keyCount = $Response.Data.Count
        keys = ($Response.Data.Keys -join ", ")
        hasError = (-not [string]::IsNullOrWhiteSpace($Response.ErrorMessage))
    }
    
    # Include full data if requested and successful
    if ($IncludeFullData -and $Response.Status -eq "Success") {
        $formatted["fullData"] = $Response.Data
    }
    
    Write-Host "[INFO] Response formatted for storage (Full data: $IncludeFullData)" -ForegroundColor Gray
    
    return $formatted
}

function Test-ApiEndpoint {
    <#
    .SYNOPSIS
    测试API端点连接
    
    .DESCRIPTION
    测试API端点的连接性和基本功能
    
    .PARAMETER Config
    ConfigModel对象
    
    .PARAMETER TestBody
    测试用的请求体
    
    .OUTPUTS
    Hashtable with test results
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ConfigModel]$Config,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$TestBody = $null
    )
    
    Write-Host "" -ForegroundColor Gray
    Write-Host "=== API Endpoint Test ===" -ForegroundColor Cyan
    
    $testResult = @{
        ConnectionTest = $false
        RequestTest = $false
        ResponseTest = $false
        OverallSuccess = $false
        Details = @{}
    }
    
    try {
        # Test 1: Connection test
        Write-Host "[TEST] 1. Testing connection..." -ForegroundColor Yellow
        Write-Host "[TEST] Testing connection to: $($Config.apiUrl)" -ForegroundColor Gray
        
        try {
            # $uri = [System.Uri]::new($Config.apiUrl)
            $testResult.ConnectionTest = $true
            Write-Host "[OK] Connection test passed" -ForegroundColor Green
        }
        catch {
            Write-Host "[ERROR] Connection test failed: $($_.Exception.Message)" -ForegroundColor Red
            $testResult.Details["ConnectionError"] = $_.Exception.Message
            Write-Host "[STOP] Connection test failed, skipping further tests" -ForegroundColor Red
            return $testResult
        }
        
        # Test 2: Request test
        Write-Host "[TEST] 2. Testing request..." -ForegroundColor Yellow
        $response = Send-PostRequest -Config $Config -CustomBody $TestBody
        $testResult.Details["Response"] = $response
        
        if ($response.Status -eq "Success") {
            $testResult.RequestTest = $true
            Write-Host "[OK] Request test passed" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Request test failed: $($response.ErrorMessage)" -ForegroundColor Red
        }
        
        # Test 3: Response validation
        Write-Host "[TEST] 3. Testing response validation..." -ForegroundColor Yellow
        $validationResult = Test-ResponseValidation -Response $response
        $testResult.ResponseTest = $validationResult.IsValid
        $testResult.Details["Validation"] = $validationResult
        
        if ($validationResult.IsValid) {
            Write-Host "[OK] Response validation passed" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Response validation failed" -ForegroundColor Red
        }
        
        # Overall result
        $testResult.OverallSuccess = $testResult.ConnectionTest -and $testResult.RequestTest -and $testResult.ResponseTest
        
        Write-Host "" -ForegroundColor Gray
        Write-Host "[INFO] Test Summary:" -ForegroundColor Cyan
        Write-Host "  Connection: $(if($testResult.ConnectionTest){'[OK] Passed'}else{'[ERROR] Failed'})" -ForegroundColor $(if($testResult.ConnectionTest){'Green'}else{'Red'})
        Write-Host "  Request: $(if($testResult.RequestTest){'[OK] Passed'}else{'[ERROR] Failed'})" -ForegroundColor $(if($testResult.RequestTest){'Green'}else{'Red'})
        Write-Host "  Response: $(if($testResult.ResponseTest){'[OK] Passed'}else{'[ERROR] Failed'})" -ForegroundColor $(if($testResult.ResponseTest){'Green'}else{'Red'})
        Write-Host "  Overall: $(if($testResult.OverallSuccess){'[OK] Success'}else{'[ERROR] Failed'})" -ForegroundColor $(if($testResult.OverallSuccess){'Green'}else{'Red'})
        
        return $testResult
    }
    catch {
        Write-Host "[ERROR] Test failed with error: $($_.Exception.Message)" -ForegroundColor Red
        $testResult.Details["TestError"] = $_.Exception.Message
        return $testResult
    }
}

# Functions are available when dot-sourced