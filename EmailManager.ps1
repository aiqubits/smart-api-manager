# EmailManager.ps1 - Email functionality for Smart API Manager
# 邮件发送功能模块，用于发送每日报告到配置文件中的邮件地址

function Send-DailyReport {
    <#
    .SYNOPSIS
    发送每日报告到配置文件中的邮件地址
    
    .DESCRIPTION
    每次运行 smart-api.ps1 完成时，发送本次报告到配置文件中的邮件地址
    邮件内容包括请求历史记录和本次请求统计数据
    
    .PARAMETER Config
    Configuration object containing email settings
    
    .PARAMETER DataPath
    Path to the data.json file
    
    .PARAMETER RequestHistoryPath
    Path to the requestHistory.json file
    
    .PARAMETER WorkflowResult
    Results from the main workflow execution
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ConfigModel]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$DataPath,
        
        [Parameter(Mandatory = $true)]
        [string]$RequestHistoryPath,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$WorkflowResult = $null
    )
    
    try {
        Write-Host "`n[EMAIL] Preparing Daily Report Email..." -ForegroundColor Yellow
        
        # Validate email configuration
        if (-not $Config.receiveEMailList -or $Config.receiveEMailList.Count -eq 0) {
            Write-Host "[WARN] No email address configured in config file" -ForegroundColor Yellow
            return $false
        }
        
        if (-not $Config.emailSettings) {
            Write-Host "[WARN] Email settings not configured in config file" -ForegroundColor Yellow
            return $false
        }
        
        # Read current data for report
        $data = Read-DataFile -DataPath $DataPath
        if (-not $data) {
            Write-Host "[ERROR] Failed to read data file for email report" -ForegroundColor Red
            return $false
        }
        
        # Read request history data separately with error handling
        $historyData = Read-RequestHistoryFile -HistoryPath $RequestHistoryPath
        if (-not $historyData) {
            Write-Host "[WARN] Failed to read request history file, attempting to initialize or repair" -ForegroundColor Yellow
            
            # Try to initialize if file doesn't exist
            if (-not (Test-Path $RequestHistoryPath)) {
                Write-Host "[INFO] Request history file doesn't exist, creating new one" -ForegroundColor Gray
                $initResult = Initialize-RequestHistoryFile -HistoryPath $RequestHistoryPath
                if ($initResult) {
                    $historyData = Read-RequestHistoryFile -HistoryPath $RequestHistoryPath
                }
            }
            else {
                # Try to repair corrupted file
                Write-Host "[INFO] Request history file exists but corrupted, attempting repair" -ForegroundColor Gray
                $repairResult = Repair-RequestHistoryFile -HistoryPath $RequestHistoryPath
                if ($repairResult) {
                    $historyData = Read-RequestHistoryFile -HistoryPath $RequestHistoryPath
                }
            }
            
            # Fallback to empty history if all else fails
            if (-not $historyData) {
                Write-Host "[WARN] Could not recover request history file, using empty history for email report" -ForegroundColor Yellow
                $historyData = @{ requestHistory = @() }
            }
        }
        
        Write-Host "[INFO] Data and request history loaded for email report" -ForegroundColor Gray
        
        # Generate email content with separate history data and config
        $emailContent = New-EmailReport -Data $data -HistoryData $historyData -Config $Config -WorkflowResult $WorkflowResult
        
        # Send email
        $emailResult = Send-EmailReport -Config $Config -EmailContent $emailContent
        
        if ($emailResult) {
            Write-Host "[OK] Daily report email sent successfully to $($Config.receiveEMailList -join ', ')" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "[ERROR] Failed to send daily report email" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "[ERROR] Error sending daily report: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function New-EmailReport {
    <#
    .SYNOPSIS
    生成邮件报告内容
    
    .DESCRIPTION
    根据数据文件、请求历史数据和工作流结果生成HTML格式的邮件报告
    
    .PARAMETER Data
    DataModel object from data.json file
    
    .PARAMETER HistoryData
    Request history data from requestHistory.json file
    
    .PARAMETER Config
    Configuration object containing maxDailyRequests limit
    
    .PARAMETER WorkflowResult
    Results from workflow execution
    
    .OUTPUTS
    String containing HTML email content
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        
        [Parameter(Mandatory = $true)]
        $HistoryData,
        
        [Parameter(Mandatory = $true)]
        [ConfigModel]$Config,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$WorkflowResult = $null
    )

    $currentDate = Get-Date -Format "yyyy-MM-dd"
    $currentTime = Get-Date -Format "HH:mm:ss"
    $currentUtcDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
    Write-Host "[DEBUG] Current date: $currentDate, Current UTC date: $currentUtcDate" -ForegroundColor Cyan
    # 获取今日统计数据
    $dailyStatusArray = Get-DailyRequestStatusArray -Data $Data
    $todayRecord = Find-TodayRecord -DailyStatusArray $dailyStatusArray -TargetDate $currentDate
    Write-Host "[DEBUG] Today's record: $($todayRecord | ConvertTo-Json -Depth 10)" -ForegroundColor Cyan
    # 如果没有今日记录，使用默认值
    if ($null -eq $todayRecord) {
        $todayRecord = @{
            requestDate        = $currentDate
            totalRequests      = 0
            successfulRequests = 0
        }
    }
    
    # Get request history from separate history data parameter
    $requestHistory = @()
    if ($HistoryData -and $HistoryData.PSObject.Properties['requestHistory']) {
        $requestHistory = $HistoryData.requestHistory
    }
    elseif ($HistoryData -and $HistoryData.requestHistory) {
        $requestHistory = $HistoryData.requestHistory
    }
    # Ensure $requestHistory is always an array
    if ($null -eq $requestHistory) {
        $requestHistory = @()
    }
    elseif ($requestHistory -isnot [System.Collections.IEnumerable] -or $requestHistory -is [string]) {
        $requestHistory = @($requestHistory)
    }

    # Filter today's requests (compare date part of timestamp string directly, no timezone conversion)
    $todayRequests = $requestHistory | Where-Object {
        try {
            $datePart = $_.timestamp.Substring(0, 10)
            $datePart -eq $currentDate
        }
        catch {
            Write-Host "[WARN] Failed to parse timestamp: $($_.timestamp)" -ForegroundColor Yellow
            $false
        }
    } | Sort-Object {
        try {
            $_.timestamp
        }
        catch {
            ""
        }
    } -Descending

    Write-Host "[DEBUG] Current local date: $currentDate" -ForegroundColor Cyan
    Write-Host "[DEBUG] Current UTC date: $currentUtcDate" -ForegroundColor Cyan
    Write-Host "[DEBUG] Total request history entries: $($requestHistory.Count)" -ForegroundColor Cyan
    
    # Debug: Show first few timestamps for verification
    if ($requestHistory.Count -gt 0) {
        Write-Host "[DEBUG] Sample timestamps from history:" -ForegroundColor Cyan
        $requestHistory | Select-Object -First 3 | ForEach-Object {
            try {
                $utcTime = [DateTime]::Parse($_.timestamp, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $localTime = $utcTime.ToLocalTime()
                # Write-Host "  UTC: $($_.timestamp) -> Local: $($localTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
            }
            catch {
                Write-Host "  Failed to parse: $($_.timestamp)" -ForegroundColor Red
            }
        }
    }

    Write-Host "[INFO] Found $($todayRequests.Count) requests for today ($currentDate)" -ForegroundColor Green
    
    # Calculate statistics
    $todayTotal = $todayRequests.Count
    $todaySuccessful = ($todayRequests | Where-Object { $_.status -eq "Success" }).Count
    $todayFailed = $todayTotal - $todaySuccessful
    $maxDailyLimit = $Config.maxDailyRequests
    
    Write-Host "[STATS] Today's Summary: Total=$todayTotal, Successful=$todaySuccessful, Failed=$todayFailed, Limit=$maxDailyLimit" -ForegroundColor Cyan
    # Generate HTML content
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #4CAF50; color: white; padding: 15px; border-radius: 5px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .stats { display: flex; justify-content: space-around; flex-wrap: wrap; }
        .stat-item { text-align: center; padding: 10px; min-width: 120px; }
        .success { color: #4CAF50; }
        .error { color: #f44336; }
        .warning { color: #ff9800; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .status-success { background-color: #d4edda; }
        .status-error { background-color: #f8d7da; }
        .status-warning { background-color: #fff3cd; }
    </style>
</head>
<body>
    <div class="header">
        <h1>[REPORT] QrCode-DING Manager Daily Report</h1>
        <p>Report Date: $currentDate | Generated at: $currentTime</p>
    </div>
    
    <div class="section">
        <h2>[STATS] Today's Statistics</h2>
        <div class="stats">
            <div class="stat-item">
                <h3>$todayTotal</h3>
                <p>Total</p>
            </div>
            <div class="stat-item success">
                <h3>$todaySuccessful</h3>
                <p>Successful</p>
            </div>
            <div class="stat-item error">
                <h3>$todayFailed</h3>
                <p>Failed</p>
            </div>
        </div>
    </div>
"@

    # Add current execution result if available
    if ($WorkflowResult) {
        $executionStatus = if ($WorkflowResult.Success) { "[OK] Success" } else { "[ERROR] Failed" }
        $statusClass = if ($WorkflowResult.Success) { "success" } else { "error" }
        
        $htmlContent += @"
    <div class="section">
        <h2>[PROC] Current Execution Result</h2>
        <p class="$statusClass"><strong>Status:</strong> $executionStatus</p>
        <ul>
            <li>Limit Check: $(if($WorkflowResult.LimitCheckPassed){'[OK] Passed'}else{'[ERROR] Failed'})</li>
            <li>Request Sent: $(if($WorkflowResult.RequestSent){'[OK] Success'}else{'[ERROR] Failed'})</li>
            <li>Response Processed: $(if($WorkflowResult.ResponseProcessed){'[OK] Valid'}else{'[ERROR] Invalid'})</li>
            <li>Data Persisted: $(if($WorkflowResult.DataPersisted){'[OK] Saved'}else{'[ERROR] Failed'})</li>
        </ul>
"@
        
        if ($WorkflowResult.Errors -and $WorkflowResult.Errors.Count -gt 0) {
            $htmlContent += "<h4 class='error'>Errors:</h4><ul>"
            foreach ($errMsg in $WorkflowResult.Errors) {
                $htmlContent += "<li class='error'>$errMsg</li>"
            }
            $htmlContent += "</ul>"
        }
        
        $htmlContent += "</div>"
    }
    
    # Add request history table
    $htmlContent += @"
    <div class="section">
        <h2>[HISTORY] Today's Request History</h2>
"@
    
    if ($todayRequests.Count -gt 0) {
        $htmlContent += @"
        <table>
            <thead>
                <tr>
                    <th>Time</th>
                    <th>Status</th>
                    <th>Response Code</th>
                    <th>Submit Count</th>
                    <th>Details</th>
                </tr>
            </thead>
            <tbody>
"@
        
        # Calculate cumulative HTTP POST success count for each request (from earliest to latest)
        $sortedRequests = $todayRequests | Sort-Object { 
            try {
                $utcTime = [DateTime]::Parse($_.timestamp, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $utcTime.ToLocalTime()
            }
            catch {
                [DateTime]::MinValue
            }
        }
        $httpPostCountAtTime = @{}
        $cumulativeHttpPosts = 0

        # Each successful script execution represents 4 successful HTTP POST requests
        # (1 for logId + 3 for question submissions)
        $httpPostsPerExecution = 4
        
        foreach ($request in $sortedRequests) {
            if ($request.status -eq "Success") {
                $cumulativeHttpPosts += $httpPostsPerExecution
            }
            # If failed, we don't add any HTTP POST count since we can't determine partial success
            $httpPostCountAtTime[$request.timestamp] = $cumulativeHttpPosts
        }
        
        foreach ($request in $todayRequests) {
            try {
                $utcTime = [DateTime]::Parse($request.timestamp, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $localTime = $utcTime.ToLocalTime().AddHours(-8)
                $time = $localTime.ToString("HH:mm:ss")
            }
            catch {
                $time = "Invalid Time"
                Write-Host "[WARN] Failed to parse timestamp for display: $($request.timestamp)" -ForegroundColor Yellow
            }
            $statusClass = switch ($request.status) {
                "Success" { "status-success" }
                "ConnectionFailed" { "status-error" }
                default { "status-warning" }
            }
            
            $details = ""
            if ($request.responseData -and $request.responseData.errorMessage) {
                $details = $request.responseData.errorMessage
            }
            elseif ($request.status -eq "Success") {
                $details = "Request completed successfully"
            }
            
            # Show HTTP POST count for this execution
            $currentExecutionHttpPosts = if ($request.status -eq "Success") { $httpPostsPerExecution } else { 0 }
            $totalHttpPosts = $httpPostCountAtTime[$request.timestamp] / $currentExecutionHttpPosts
            $httpPostDisplay = "($totalHttpPosts / $maxDailyLimit)"
            
            $htmlContent += @"
                <tr class="$statusClass">
                    <td>$time</td>
                    <td>$($request.status)</td>
                    <td>$($request.responseCode)</td>
                    <td>$httpPostDisplay</td>
                    <td>$details</td>
                </tr>
"@
        }
        
        $htmlContent += @"
            </tbody>
        </table>
"@
    }
    else {
        $htmlContent += "<p>No requests made today.</p>"
    }
    
    $htmlContent += @"
    </div>
    
    <div class="section">
        <h2>[INFO] Host Information</h2>
        <ul>
            <li><strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</li>
            <li><strong>PowerShell Version:</strong> $($PSVersionTable.PSVersion)</li>
            <li><strong>Machine:</strong> $env:COMPUTERNAME</li>
            <li><strong>User:</strong> $env:USERNAME</li>
        </ul>
    </div>
    
    <div class="section" style="background-color: #f8f9fa; text-align: center;">
        <p><em>System Developer VX: 309026152</em></p>
        </br>
        <img src="https://gitee.com/aiqubit/public-data/raw/master/qrcode/dc47035c85ee6728866b7de890844724.jpg" alt="wechat-qrcode" style="width: 150px; height: 200px;">
    </div>
</body>
</html>
"@
    
    return $htmlContent
}

function Send-EmailReport {
    <#
    .SYNOPSIS
    发送HTML邮件报告
    
    .DESCRIPTION
    使用SMTP发送HTML格式的邮件报告
    
    .PARAMETER Config
    Configuration object with email settings
    
    .PARAMETER EmailContent
    HTML content for the email
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ConfigModel]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$EmailContent
    )
    
    try {
        Write-Host "[EMAIL] Sending email report..." -ForegroundColor Gray
        
        # Validate email settings
        $emailSettings = $Config.emailSettings
        if (-not $emailSettings.smtpServer -or -not $emailSettings.senderEmail) {
            Write-Host "[ERROR] Invalid email settings in configuration" -ForegroundColor Red
            return $false
        }
        
        # Create email message
        $message = New-Object System.Net.Mail.MailMessage
        $message.From = $emailSettings.senderEmail
        foreach ($to in $Config.receiveEMailList) {
            if ($to) { $message.To.Add($to) }
        }
        $message.Subject = "$($emailSettings.subject) - $(Get-Date -Format 'yyyy-MM-dd')"
        $message.Body = $EmailContent
        $message.IsBodyHtml = $true
        
        # Create SMTP client
        $smtpClient = New-Object System.Net.Mail.SmtpClient
        $smtpClient.Host = $emailSettings.smtpServer
        $smtpClient.Port = $emailSettings.smtpPort
        $smtpClient.EnableSsl = $emailSettings.enableSsl
        
        # Set credentials if provided
        if ($emailSettings.senderPassword) {
            $credentials = New-Object System.Net.NetworkCredential($emailSettings.senderEmail, $emailSettings.senderPassword)
            $smtpClient.Credentials = $credentials
        }
        
        # Send email
        $smtpClient.Send($message)
        
        # Cleanup
        $message.Dispose()
        $smtpClient.Dispose()
        
        Write-Host "[OK] Email sent successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[ERROR] Failed to send email: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-EmailConfiguration {
    <#
    .SYNOPSIS
    测试邮件配置是否正确
    
    .DESCRIPTION
    验证邮件配置并发送测试邮件
    
    .PARAMETER Config
    Configuration object
    
    .OUTPUTS
    Boolean indicating if configuration is valid
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ConfigModel]$Config
    )
    
    try {
        Write-Host "[TEST] Testing email configuration..." -ForegroundColor Yellow
        
        # Check required fields
        if (-not $Config.receiveEMailList -or $Config.receiveEMailList.Count -eq 0) {
            Write-Host "[ERROR] receiveEMailList not configured" -ForegroundColor Red
            return $false
        }
        
        if (-not $Config.emailSettings) {
            Write-Host "[ERROR] emailSettings not configured" -ForegroundColor Red
            return $false
        }
        
        $emailSettings = $Config.emailSettings
        $requiredFields = @('smtpServer', 'smtpPort', 'senderEmail', 'subject')
        
        foreach ($field in $requiredFields) {
            if (-not $emailSettings.$field) {
                Write-Host "[ERROR] Email setting '$field' is missing" -ForegroundColor Red
                return $false
            }
        }
        
        Write-Host "[OK] Email configuration validation passed" -ForegroundColor Green
        Write-Host "  [EMAIL] Recipients: $($Config.receiveEMailList -join ', ')" -ForegroundColor Gray
        Write-Host "  [NET] SMTP Server: $($emailSettings.smtpServer):$($emailSettings.smtpPort)" -ForegroundColor Gray
        Write-Host "  [INFO] Sender: $($emailSettings.senderEmail)" -ForegroundColor Gray
        
        return $true
    }
    catch {
        Write-Host "[ERROR] Email configuration teled: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}