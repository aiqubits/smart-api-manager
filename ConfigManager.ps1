# ConfigManager.ps1 - Configuration management module
# 配置管理模块，负责读取、验证和管理配置文件

# Import symbol definitions
. "$PSScriptRoot\SymbolDefinitions.ps1"

# Configuration model class
class ConfigModel {
    [string]$apiUrl
    [int]$maxDailyRequests
    [int]$timeout
    [hashtable]$headers
    [hashtable]$requestBody
    [string[]]$receiveEMailList
    [hashtable]$emailSettings
    [int]$maxHistoryFileSizeMB
    [int]$randomNumber

    ConfigModel() {
        $this.headers = @{}
        $this.requestBody = @{}
        $this.emailSettings = @{}
        $this.receiveEMailList = @()
    }
}

function Read-Config {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )
    
    try {
        Write-Host "[CHECK] Reading configuration file: $ConfigPath" -ForegroundColor Gray
        
        if (-not (Test-Path $ConfigPath)) {
            Write-Host "[ERROR] Configuration file not found: $ConfigPath" -ForegroundColor Red
            return $null
        }
        
        $jsonContent = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        $configData = $jsonContent | ConvertFrom-Json
        
        Write-Host "[OK] Configuration file parsed successfully" -ForegroundColor Green
        
        # Validate and create ConfigModel
        $config = [ConfigModel]::new()
        
        Write-Host "[CHECK] Validating configuration..." -ForegroundColor Gray
        $validationResult = Test-ConfigValidation -ConfigData $configData -Config $config
        
        if ($validationResult.IsValid) {
            Write-Host "[OK] Configuration validation passed" -ForegroundColor Green
            return $config
        } else {
            Write-Host "[ERROR] Configuration validation failed" -ForegroundColor Red
            $validationResult.Errors | ForEach-Object {
                Write-Host "  - $_" -ForegroundColor Red
            }
            return $null
        }
    }
    catch {
        Write-Host "[ERROR] Error reading configuration: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Test-ConfigValidation {
    param(
        [Parameter(Mandatory=$true)]
        $ConfigData,
        
        [Parameter(Mandatory=$true)]
        [ConfigModel]$Config
    )
    
    $result = @{
        IsValid = $true
        Errors = @()
        Warnings = @()
        FieldsProcessed = 0
        DefaultsApplied = 0
    }
    
    try {
        Write-Host "[CHECK] Validating configuration fields..." -ForegroundColor Gray
        
        # Validate apiUrl
        Write-Host "  Checking apiUrl..." -ForegroundColor Gray
        if ($configData.PSObject.Properties['apiUrl']) {
            if ([string]::IsNullOrWhiteSpace($configData.apiUrl)) {
                $result.Errors += "apiUrl cannot be empty"
                $result.IsValid = $false
            } else {
                try {
                    $uri = [System.Uri]::new($configData.apiUrl)
                    if ($uri.Scheme -notin @('http', 'https')) {
                        $result.Errors += "apiUrl must use http or https protocol"
                        $result.IsValid = $false
                    } else {
                        $Config.apiUrl = $configData.apiUrl
                        Write-Host "    [OK] Valid API URL: $($configData.apiUrl)" -ForegroundColor Green
                        $result.FieldsProcessed++
                    }
                } catch {
                    $result.Errors += "apiUrl is not a valid URL: $($_.Exception.Message)"
                    $result.IsValid = $false
                }
            }
        } else {
            $result.Errors += "apiUrl is required"
            $result.IsValid = $false
        }
        
        # Validate maxDailyRequests
        Write-Host "  Checking maxDailyRequests..." -ForegroundColor Gray
        if ($configData.PSObject.Properties['maxDailyRequests']) {
            if ($configData.maxDailyRequests -is [int] -and $configData.maxDailyRequests -gt 0) {
                $Config.maxDailyRequests = $configData.maxDailyRequests
                Write-Host "    [OK] Valid maxDailyRequests: $($configData.maxDailyRequests)" -ForegroundColor Green
                $result.FieldsProcessed++
            } else {
                $result.Errors += "maxDailyRequests must be a positive integer"
                $result.IsValid = $false
            }
        } else {
            $Config.maxDailyRequests = 100  # Default value
            Write-Host "    [WARN] Using default maxDailyRequests: 100" -ForegroundColor Yellow
            $result.DefaultsApplied++
            $result.FieldsProcessed++
        }
        
        # Validate timeout
        Write-Host "  Checking timeout..." -ForegroundColor Gray
        if ($configData.PSObject.Properties['timeout']) {
            if ($configData.timeout -is [int] -and $configData.timeout -gt 0) {
                $Config.timeout = $configData.timeout
                Write-Host "    [OK] Valid timeout: $($configData.timeout) seconds" -ForegroundColor Green
                $result.FieldsProcessed++
            } else {
                $result.Errors += "timeout must be a positive integer"
                $result.IsValid = $false
            }
        } else {
            $Config.timeout = 30  # Default value
            Write-Host "    [WARN] Using default timeout: 30 seconds" -ForegroundColor Yellow
            $result.DefaultsApplied++
            $result.FieldsProcessed++
        }
        
        # Validate headers
        Write-Host "  Checking headers..." -ForegroundColor Gray
        if ($configData.PSObject.Properties['headers']) {
            if ($configData.headers -is [PSCustomObject]) {
                $headerCount = 0
                $configData.headers.PSObject.Properties | ForEach-Object {
                    $Config.headers[$_.Name] = $_.Value
                    $headerCount++
                }
                Write-Host "    [OK] Processed $headerCount headers" -ForegroundColor Green
                $result.FieldsProcessed++
            } else {
                $result.Errors += "headers must be an object"
                $result.IsValid = $false
            }
        } else {
            Write-Host "    [WARN] No headers specified" -ForegroundColor Yellow
            $result.FieldsProcessed++
        }
        
        # Validate requestBody
        Write-Host "  Checking requestBody..." -ForegroundColor Gray
        if ($configData.PSObject.Properties['requestBody']) {
            if ($configData.requestBody -is [PSCustomObject]) {
                $bodyFieldCount = 0
                $configData.requestBody.PSObject.Properties | ForEach-Object {
                    $Config.requestBody[$_.Name] = $_.Value
                    $bodyFieldCount++
                }
                Write-Host "    [OK] Processed requestBody with $bodyFieldCount fields" -ForegroundColor Green
                $result.FieldsProcessed++
            } else {
                $result.Errors += "requestBody must be an object"
                $result.IsValid = $false
            }
        } else {
            Write-Host "    [WARN] No requestBody specified" -ForegroundColor Yellow
            $result.FieldsProcessed++
        }
        
        # Validate receiveEMailList (optional, array of emails)
        Write-Host "  Checking receiveEMailList..." -ForegroundColor Gray
        $emails = @()
        if ($configData.PSObject.Properties['receiveEMailList']) {
            if ($configData.receiveEMailList -is [System.Collections.IEnumerable] -and $configData.receiveEMailList -isnot [string]) {
                foreach ($email in $configData.receiveEMailList) {
                    if ($email -match '^[^@]+@[^@]+\.[^@]+$') {
                        $emails += $email
                    } else {
                        $result.Warnings += "Invalid email address in receiveEMailList: $email"
                    }
                }
                $Config.receiveEMailList = $emails
                Write-Host "    [OK] Valid email list: $($emails -join ', ')" -ForegroundColor Green
                $result.FieldsProcessed++
            } elseif ($configData.receiveEMailList -is [string]) {
                # 兼容字符串
                if ($configData.receiveEMailList -match '^[^@]+@[^@]+\.[^@]+$') {
                    $Config.receiveEMailList = @($configData.receiveEMailList)
                    Write-Host "    [OK] Valid email (string): $($configData.receiveEMailList)" -ForegroundColor Green
                    $result.FieldsProcessed++
                } else {
                    $result.Errors += "receiveEMailList is not a valid email address"
                    $result.IsValid = $false
                }
            } else {
                $result.Errors += "receiveEMailList must be an array of email addresses or a string"
                $result.IsValid = $false
            }
        } elseif ($configData.PSObject.Properties['receiveEMail']) {
            # 兼容旧字段
            if (-not [string]::IsNullOrWhiteSpace($configData.receiveEMail)) {
                if ($configData.receiveEMail -match '^[^@]+@[^@]+\.[^@]+$') {
                    $Config.receiveEMailList = @($configData.receiveEMail)
                    Write-Host "    [OK] (Compat) Valid email from receiveEMail: $($configData.receiveEMail)" -ForegroundColor Green
                    $result.FieldsProcessed++
                } else {
                    $result.Errors += "receiveEMail is not a valid email address"
                    $result.IsValid = $false
                }
            } else {
                $result.Warnings += "receiveEMail is empty"
            }
        } else {
            Write-Host "    [WARN] No receiveEMailList specified" -ForegroundColor Yellow
            $result.FieldsProcessed++
        }
        
        # Validate emailSettings (optional)
        Write-Host "  Checking emailSettings..." -ForegroundColor Gray
        if ($configData.PSObject.Properties['emailSettings']) {
            if ($configData.emailSettings -is [PSCustomObject]) {
                $emailFieldCount = 0
                $configData.emailSettings.PSObject.Properties | ForEach-Object {
                    $Config.emailSettings[$_.Name] = $_.Value
                    $emailFieldCount++
                }
                Write-Host "    [OK] Processed emailSettings with $emailFieldCount fields" -ForegroundColor Green
                $result.FieldsProcessed++
            } else {
                $result.Errors += "emailSettings must be an object"
                $result.IsValid = $false
            }
        } else {
            Write-Host "    [WARN] No emailSettings specified" -ForegroundColor Yellow
            $result.FieldsProcessed++
        }

        # Validate maxHistoryFileSizeMB (optional)
        Write-Host "  Checking maxHistoryFileSizeMB..." -ForegroundColor Gray
        if ($configData.PSObject.Properties['maxHistoryFileSizeMB']) {
            if ($configData.maxHistoryFileSizeMB -is [int] -and $configData.maxHistoryFileSizeMB -gt 0) {
                $Config.maxHistoryFileSizeMB = $configData.maxHistoryFileSizeMB
                Write-Host "    [OK] Valid maxHistoryFileSizeMB: $($configData.maxHistoryFileSizeMB)MB" -ForegroundColor Green
                $result.FieldsProcessed++
            } else {
                $result.Errors += "maxHistoryFileSizeMB must be a positive integer"
                $result.IsValid = $false
            }
        } else {
            $Config.maxHistoryFileSizeMB = 2  # Default value in MB
            Write-Host "    [WARN] Using default maxHistoryFileSizeMB: 2MB" -ForegroundColor Yellow
            $result.DefaultsApplied++
            $result.FieldsProcessed++
        }
        
        # Validate randomNumber (optional)
        Write-Host "  Checking randomNumber..." -ForegroundColor Gray
        if ($configData.PSObject.Properties['randomNumber']) {
            if ($configData.randomNumber -is [int] -and $configData.randomNumber -gt 0) {
                $Config.randomNumber = $configData.randomNumber
                Write-Host "    [OK] Valid randomNumber: $($configData.randomNumber)" -ForegroundColor Green
                $result.FieldsProcessed++
            } else {
                $result.Errors += "randomNumber must not be a negative integer"
                $result.IsValid = $false
            }
        } else {
            $Config.randomNumber = 0  # Default value 0
            Write-Host "    [WARN] Using default randomNumber: 0" -ForegroundColor Yellow
            $result.DefaultsApplied++
            $result.FieldsProcessed++
        }
        
        # Display validation summary
        Write-Host "[INFO] Validation Summary:" -ForegroundColor Cyan
        Write-Host "  Fields Processed: $($result.FieldsProcessed)" -ForegroundColor Gray
        Write-Host "  Defaults Applied: $($result.DefaultsApplied)" -ForegroundColor Gray
        Write-Host "  Errors: $($result.Errors.Count)" -ForegroundColor $(if($result.Errors.Count -eq 0){'Green'}else{'Red'})
        Write-Host "  Warnings: $($result.Warnings.Count)" -ForegroundColor $(if($result.Warnings.Count -eq 0){'Green'}else{'Yellow'})
        
        return $result
    }
    catch {
        $result.Errors += "Unexpected error during validation: $($_.Exception.Message)"
        $result.IsValid = $false
        Write-Host "[ERROR] Validation error: $($_.Exception.Message)" -ForegroundColor Red
        return $result
    }
}

function Show-ConfigSummary {
    param(
        [Parameter(Mandatory=$true)]
        [ConfigModel]$Config
    )
    
    Write-Host "[INFO] Configuration Summary:" -ForegroundColor Cyan
    Write-Host "  API URL: $($Config.apiUrl)" -ForegroundColor Gray
    Write-Host "  Max Daily Requests: $($Config.maxDailyRequests)" -ForegroundColor Gray
    Write-Host "  Timeout: $($Config.timeout) seconds" -ForegroundColor Gray
    Write-Host "  Randomly Number: $($Config.randomNumber)" -ForegroundColor Gray
    Write-Host "  Max History File Size: $($Config.maxHistoryFileSizeMB)MB" -ForegroundColor Gray
    Write-Host "  Headers: $($Config.headers.Count) items" -ForegroundColor Gray
    Write-Host "  Request Body Fields: $($Config.requestBody.Count) items" -ForegroundColor Gray
    
    if ($Config.receiveEMailList -and $Config.receiveEMailList.Count -gt 0) {
        Write-Host "  Email List: $($Config.receiveEMailList -join ', ')" -ForegroundColor Gray
        Write-Host "  Email Settings: $($Config.emailSettings.Count) items" -ForegroundColor Gray
    }
}

function Test-ConfigFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )
    
    try {
        $config = Read-Config -ConfigPath $ConfigPath
        return $null -ne $config
    }
    catch {
        Write-Host "[ERROR] Config test failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Functions are available when dot-sourced