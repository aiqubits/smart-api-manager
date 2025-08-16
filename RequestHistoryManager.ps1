# RequestHistoryManager.ps1 - Request history management module
# 请求历史管理模块，负责管理独立的请求历史文件

class RequestHistoryModel {
    [array]$RequestHistory

    RequestHistoryModel() {
        $this.RequestHistory = @()
    }
}

function Read-RequestHistoryFile {
    <#
    .SYNOPSIS
    读取请求历史文件
    
    .DESCRIPTION
    从JSON文件中读取请求历史数据并返回解析后的对象
    
    .PARAMETER HistoryPath
    请求历史文件路径
    
    .OUTPUTS
    Parsed request history object or $null if failed
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath
    )
    
    try {
        if (-not (Test-Path $HistoryPath)) {
            Write-Host "[WARN] Request history file not found: $HistoryPath" -ForegroundColor Yellow
            return $null
        }
        
        # Check file size and permissions
        $fileInfo = Get-Item $HistoryPath
        if ($fileInfo.Length -eq 0) {
            Write-Host "[WARN] Request history file is empty: $HistoryPath" -ForegroundColor Yellow
            return $null
        }
        
        # Attempt to read file with error recovery
        $jsonContent = $null
        try {
            $jsonContent = Get-Content -Path $HistoryPath -Raw -Encoding UTF8 -ErrorAction Stop
        }
        catch [System.UnauthorizedAccessException] {
            Write-Host "[ERROR] Access denied reading request history file: $HistoryPath" -ForegroundColor Red
            return $null
        }
        catch [System.IO.IOException] {
            Write-Host "[ERROR] IO error reading request history file: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
        
        if ([string]::IsNullOrWhiteSpace($jsonContent)) {
            Write-Host "[WARN] Request history file content is empty or whitespace: $HistoryPath" -ForegroundColor Yellow
            return $null
        }
        
        # Attempt JSON parsing with corruption detection
        $historyData = $null
        try {
            $historyData = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        }
        catch [System.ArgumentException] {
            Write-Host "[ERROR] Request history file contains invalid JSON format: $HistoryPath" -ForegroundColor Red
            Write-Host "[ERROR] JSON parsing error: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
        
        # Validate basic structure
        if ($null -eq $historyData) {
            Write-Host "[ERROR] Request history file parsing resulted in null data: $HistoryPath" -ForegroundColor Red
            return $null
        }
        
        Write-Host "[OK] Request history file loaded successfully from: $HistoryPath" -ForegroundColor Green
        return $historyData
    }
    catch {
        Write-Host "[ERROR] Unexpected error reading request history file: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[ERROR] Exception type: $($_.Exception.GetType().Name)" -ForegroundColor Red
        return $null
    }
}

function Write-RequestHistoryFile {
    <#
    .SYNOPSIS
    写入请求历史文件
    
    .DESCRIPTION
    将请求历史数据对象序列化为JSON并写入文件
    
    .PARAMETER HistoryPath
    请求历史文件路径
    
    .PARAMETER HistoryData
    要写入的请求历史数据对象
    
    .PARAMETER Config
    Configuration object containing maxHistoryFileSizeMB setting
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        $HistoryData,
        
        [Parameter(Mandatory=$false)]
        $Config = $null
    )
    
    try {
        # Validate input data before writing
        if ($null -eq $HistoryData) {
            Write-Host "[ERROR] Cannot write null data to request history file" -ForegroundColor Red
            return $false
        }

        # Check file size and rotate if necessary
        if (Test-Path $HistoryPath) {
            $fileInfo = Get-Item $HistoryPath
            $fileSizeBytes = $fileInfo.Length
            
            # Get max file size from config or use default
            $maxSizeMB = if ($Config -and $Config.PSObject.Properties['maxHistoryFileSizeMB']) { 
                $Config.maxHistoryFileSizeMB 
            } else { 
                2  # Default 2MB
            }
            $maxSizeBytes = $maxSizeMB * 1024 * 1024
            
            if ($fileSizeBytes -gt $maxSizeBytes) {
                Write-Host "[INFO] Request history file size ($([math]::Round($fileSizeBytes/1MB, 2))MB) exceeds limit ($($maxSizeMB)MB), rotating file..." -ForegroundColor Yellow
                
                # Generate rotation filename
                $timestamp = Get-Date -Format "yyyy-MM-dd-HH"
                $directory = Split-Path $HistoryPath -Parent
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($HistoryPath)
                $rotatedPath = Join-Path $directory "$baseName-$timestamp.json"
                
                # Handle duplicate names by adding sequence number
                $counter = 1
                while (Test-Path $rotatedPath) {
                    $rotatedPath = Join-Path $directory "$baseName-$timestamp-$('{0:D3}' -f $counter).json"
                    $counter++
                }
                
                try {
                    # Rename current file
                    Move-Item $HistoryPath $rotatedPath -Force -ErrorAction Stop
                    Write-Host "[OK] Rotated file to: $rotatedPath" -ForegroundColor Green
                    
                    # Create new empty file with proper structure
                    $emptyHistoryData = @{ requestHistory = @() }
                    $emptyJson = $emptyHistoryData | ConvertTo-Json -Depth 10
                    Set-Content -Path $HistoryPath -Value $emptyJson -Encoding UTF8 -ErrorAction Stop
                    Write-Host "[OK] Created new empty request history file" -ForegroundColor Green
                }
                catch {
                    Write-Host "[ERROR] File rotation failed: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "[WARN] Continuing with original file" -ForegroundColor Yellow
                    # Continue with normal operation using the original large file
                }
            }
        }
        
        # Create backup of existing file if it exists
        $backupPath = $null
        if (Test-Path $HistoryPath) {
            $backupPath = "$HistoryPath.backup"
            try {
                Copy-Item $HistoryPath $backupPath -Force -ErrorAction Stop
                Write-Host "[INFO] Created backup of existing file: $backupPath" -ForegroundColor Gray
            }
            catch {
                Write-Host "[WARN] Could not create backup file: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        # Serialize to JSON with error handling
        $jsonContent = $null
        try {
            $jsonContent = $HistoryData | ConvertTo-Json -Depth 10 -ErrorAction Stop
        }
        catch {
            Write-Host "[ERROR] Failed to serialize data to JSON: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
        
        if ([string]::IsNullOrWhiteSpace($jsonContent)) {
            Write-Host "[ERROR] JSON serialization resulted in empty content" -ForegroundColor Red
            return $false
        }
        
        # Ensure directory exists
        $directory = Split-Path $HistoryPath -Parent
        if (-not [string]::IsNullOrEmpty($directory) -and -not (Test-Path $directory)) {
            try {
                New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
                Write-Host "[INFO] Created directory: $directory" -ForegroundColor Gray
            }
            catch {
                Write-Host "[ERROR] Failed to create directory: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }
        
        # Write file with comprehensive error handling
        try {
            Set-Content -Path $HistoryPath -Value $jsonContent -Encoding UTF8 -ErrorAction Stop
        }
        catch [System.UnauthorizedAccessException] {
            Write-Host "[ERROR] Access denied writing to request history file: $HistoryPath" -ForegroundColor Red
            return $false
        }
        catch [System.IO.DirectoryNotFoundException] {
            Write-Host "[ERROR] Directory not found for request history file: $HistoryPath" -ForegroundColor Red
            return $false
        }
        catch [System.IO.IOException] {
            Write-Host "[ERROR] IO error writing request history file: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
        
        # Verify write was successful by reading back
        try {
            $verifyContent = Get-Content -Path $HistoryPath -Raw -Encoding UTF8 -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($verifyContent)) {
                Write-Host "[ERROR] File write verification failed - file is empty" -ForegroundColor Red
                
                # Restore backup if available
                if ($backupPath -and (Test-Path $backupPath)) {
                    try {
                        Copy-Item $backupPath $HistoryPath -Force
                        Write-Host "[INFO] Restored backup file due to write failure" -ForegroundColor Yellow
                    }
                    catch {
                        Write-Host "[ERROR] Failed to restore backup: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                return $false
            }
        }
        catch {
            Write-Host "[WARN] Could not verify file write: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        # Clean up backup on successful write
        if ($backupPath -and (Test-Path $backupPath)) {
            try {
                Remove-Item $backupPath -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-Host "[WARN] Could not remove backup file: $backupPath" -ForegroundColor Yellow
            }
        }
        
        Write-Host "[OK] Request history file written successfully to: $HistoryPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[ERROR] Unexpected error writing request history file: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[ERROR] Exception type: $($_.Exception.GetType().Name)" -ForegroundColor Red
        return $false
    }
}

function Initialize-RequestHistoryFile {
    <#
    .SYNOPSIS
    初始化请求历史文件
    
    .DESCRIPTION
    创建一个新的请求历史文件，包含默认的空结构
    
    .PARAMETER HistoryPath
    请求历史文件路径
    
    .PARAMETER Config
    Configuration object containing maxHistoryFileSizeMB setting
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory=$false)]
        $Config = $null
    )
    
    try {
        $initialHistoryData = @{
            requestHistory = @()
        }
        
        $result = Write-RequestHistoryFile -HistoryPath $HistoryPath -HistoryData $initialHistoryData -Config $Config
        
        if ($result) {
            Write-Host "[OK] Request history file initialized successfully" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Failed to initialize request history file" -ForegroundColor Red
        }
        
        return $result
    }
    catch {
        Write-Host "[ERROR] Error initializing request history file: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-RequestHistoryEntryStructure {
    <#
    .SYNOPSIS
    验证请求历史记录条目结构
    
    .DESCRIPTION
    检查请求历史记录条目是否具有正确的结构和必需的字段
    
    .PARAMETER Entry
    要验证的请求历史记录条目
    
    .OUTPUTS
    Boolean indicating if entry structure is valid
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Entry
    )
    
    try {
        $isValid = $true
        $errors = @()
        
        # Check required properties (works for both hashtables and PSObjects)
        $requiredProperties = @('timestamp', 'status', 'responseCode', 'responseData')
        
        foreach ($property in $requiredProperties) {
            $hasProperty = $false
            
            # Check if it's a hashtable
            if ($Entry -is [hashtable]) {
                $hasProperty = $Entry.ContainsKey($property)
            }
            # Check if it's a PSObject
            elseif ($Entry.PSObject.Properties[$property]) {
                $hasProperty = $true
            }
            
            if (-not $hasProperty) {
                $errors += "Missing required property: $property"
                $isValid = $false
            }
        }
        
        # Validate timestamp format
        $timestamp = if ($Entry -is [hashtable]) { $Entry['timestamp'] } else { $Entry.timestamp }
        if ($timestamp) {
            try {
                [DateTime]::Parse($timestamp) | Out-Null
            }
            catch {
                $errors += "Invalid timestamp format: $timestamp"
                $isValid = $false
            }
        }
        
        # Validate status is not empty
        $status = if ($Entry -is [hashtable]) { $Entry['status'] } else { $Entry.status }
        if ($status -ne $null -and [string]::IsNullOrWhiteSpace($status)) {
            $errors += "Status cannot be empty"
            $isValid = $false
        }
        
        # Validate responseCode is numeric
        $responseCode = if ($Entry -is [hashtable]) { $Entry['responseCode'] } else { $Entry.responseCode }
        if ($responseCode -ne $null) {
            try {
                [int]$responseCode | Out-Null
            }
            catch {
                $errors += "ResponseCode must be numeric: $responseCode"
                $isValid = $false
            }
        }
        
        # Validate responseData exists (can be empty hashtable)
        $responseData = if ($Entry -is [hashtable]) { $Entry['responseData'] } else { $Entry.responseData }
        if ($null -eq $responseData) {
            $errors += "ResponseData cannot be null"
            $isValid = $false
        }
        
        if (-not $isValid) {
            Write-Host "[WARN] Request history entry validation failed:" -ForegroundColor Yellow
            foreach ($errMsg in $errors) {
                Write-Host "  - $errMsg" -ForegroundColor Yellow
            }
        }
        
        return $isValid
    }
    catch {
        Write-Host "[ERROR] Error validating request history entry structure: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Add-RequestHistoryEntry {
    <#
    .SYNOPSIS
    添加请求历史记录
    
    .DESCRIPTION
    向请求历史文件中添加新的请求历史记录
    
    .PARAMETER HistoryPath
    请求历史文件路径
    
    .PARAMETER Status
    请求状态
    
    .PARAMETER ResponseCode
    响应代码
    
    .PARAMETER ResponseData
    响应数据
    
    .PARAMETER Timestamp
    时间戳
    
    .PARAMETER Config
    Configuration object containing maxHistoryFileSizeMB setting
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory=$true)]
        [string]$Status,
        
        [Parameter(Mandatory=$true)]
        [int]$ResponseCode,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$ResponseData,
        
        [Parameter(Mandatory=$false)]
        [string]$Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"),
        
        [Parameter(Mandatory=$false)]
        $Config = $null
    )
    
    try {
        # Validate input parameters
        if ([string]::IsNullOrWhiteSpace($Status)) {
            Write-Host "[ERROR] Status cannot be empty" -ForegroundColor Red
            return $false
        }
        
        if ($null -eq $ResponseData) {
            Write-Host "[ERROR] ResponseData cannot be null" -ForegroundColor Red
            return $false
        }
        
        # Validate timestamp format
        try {
            [DateTime]::Parse($Timestamp) | Out-Null
        }
        catch {
            Write-Host "[ERROR] Invalid timestamp format: $Timestamp" -ForegroundColor Red
            return $false
        }
        
        $historyData = Read-RequestHistoryFile -HistoryPath $HistoryPath
        if ($null -eq $historyData) {
            Write-Host "[WARN] Could not read request history file, initializing new one" -ForegroundColor Yellow
            $initResult = Initialize-RequestHistoryFile -HistoryPath $HistoryPath -Config $Config
            if (-not $initResult) {
                return $false
            }
            $historyData = Read-RequestHistoryFile -HistoryPath $HistoryPath
        }
        
        # Ensure requestHistory exists
        if (-not $historyData.PSObject.Properties['requestHistory']) {
            $historyData | Add-Member -MemberType NoteProperty -Name 'requestHistory' -Value @()
        }
        
        # Create new history entry
        $historyEntry = @{
            timestamp = $Timestamp
            status = $Status
            responseCode = $ResponseCode
            responseData = $ResponseData
        }
        
        # Validate the entry structure before adding
        if (-not (Test-RequestHistoryEntryStructure -Entry $historyEntry)) {
            Write-Host "[ERROR] Request history entry validation failed" -ForegroundColor Red
            return $false
        }
        
        # Add to history (convert to array if needed)
        if ($historyData.requestHistory -is [array]) {
            $historyData.requestHistory += $historyEntry
        } else {
            $historyData.requestHistory = @($historyEntry)
        }
        
        # Save updated history data
        $result = Write-RequestHistoryFile -HistoryPath $HistoryPath -HistoryData $historyData -Config $Config
        
        if ($result) {
            Write-Host "[OK] Request history entry added successfully" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Failed to add request history entry" -ForegroundColor Red
        }
        
        return $result
    }
    catch {
        Write-Host "[ERROR] Error adding request history entry: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-RequestHistoryByDate {
    <#
    .SYNOPSIS
    按日期获取请求历史记录
    
    .DESCRIPTION
    从请求历史文件中获取指定日期的请求历史记录
    
    .PARAMETER HistoryPath
    请求历史文件路径
    
    .PARAMETER Date
    要筛选的日期 (格式: yyyy-MM-dd)
    
    .OUTPUTS
    Array of request history entries for the specified date
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory=$true)]
        [string]$Date
    )
    
    try {
        # Validate date format
        try {
            $parsedDate = [DateTime]::ParseExact($Date, "yyyy-MM-dd", $null)
        }
        catch {
            Write-Host "[ERROR] Invalid date format. Expected yyyy-MM-dd, got: $Date" -ForegroundColor Red
            return @()
        }
        
        $historyData = Read-RequestHistoryFile -HistoryPath $HistoryPath
        if ($null -eq $historyData) {
            Write-Host "[WARN] Could not read request history file" -ForegroundColor Yellow
            return @()
        }
        
        # Ensure requestHistory exists
        if (-not $historyData.PSObject.Properties['requestHistory']) {
            Write-Host "[WARN] No requestHistory property found in history file" -ForegroundColor Yellow
            return @()
        }
        
        # Filter entries by date
        $filteredEntries = @()
        $invalidEntries = 0
        
        foreach ($entry in $historyData.requestHistory) {
            if ($entry.PSObject.Properties['timestamp']) {
                try {
                    $entryDate = [DateTime]::Parse($entry.timestamp).ToString("yyyy-MM-dd")
                    if ($entryDate -eq $Date) {
                        # Validate entry structure before including
                        if (Test-RequestHistoryEntryStructure -Entry $entry) {
                            $filteredEntries += $entry
                        } else {
                            $invalidEntries++
                        }
                    }
                }
                catch {
                    Write-Host "[WARN] Invalid timestamp format in entry: $($entry.timestamp)" -ForegroundColor Yellow
                    $invalidEntries++
                }
            } else {
                Write-Host "[WARN] Entry missing timestamp property" -ForegroundColor Yellow
                $invalidEntries++
            }
        }
        
        if ($invalidEntries -gt 0) {
            Write-Host "[WARN] Skipped $invalidEntries invalid entries" -ForegroundColor Yellow
        }
        
        Write-Host "[OK] Found $($filteredEntries.Count) valid entries for date: $Date" -ForegroundColor Green
        return $filteredEntries
    }
    catch {
        Write-Host "[ERROR] Error filtering request history by date: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Test-RequestHistoryFileFormat {
    <#
    .SYNOPSIS
    验证请求历史文件格式
    
    .DESCRIPTION
    检查请求历史文件是否具有正确的格式和必需的字段，包括深度内容验证
    
    .PARAMETER HistoryPath
    请求历史文件路径
    
    .PARAMETER ValidateEntries
    是否验证所有历史记录条目的结构
    
    .OUTPUTS
    Hashtable with validation details: @{ IsValid = $bool; Issues = @(); EntryCount = $int; ValidEntries = $int }
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory=$false)]
        [bool]$ValidateEntries = $true
    )
    
    $result = @{
        IsValid = $true
        Issues = @()
        EntryCount = 0
        ValidEntries = 0
    }
    
    try {
        # First check for corruption
        $corruptionCheck = Test-RequestHistoryFileCorruption -HistoryPath $HistoryPath
        if ($corruptionCheck.IsCorrupted) {
            $result.IsValid = $false
            $result.Issues += $corruptionCheck.Issues
            return $result
        }
        
        $historyData = Read-RequestHistoryFile -HistoryPath $HistoryPath
        if ($null -eq $historyData) {
            $result.IsValid = $false
            $result.Issues += "Cannot read request history file"
            return $result
        }
        
        # Check required properties
        if (-not $historyData.PSObject.Properties['requestHistory']) {
            $result.IsValid = $false
            $result.Issues += "Missing requestHistory property"
        } else {
            # Validate that requestHistory is an array or null
            if ($historyData.requestHistory -isnot [array] -and $null -ne $historyData.requestHistory) {
                $result.IsValid = $false
                $result.Issues += "requestHistory should be an array or null"
            } else {
                # Count entries
                if ($historyData.requestHistory -is [array]) {
                    $result.EntryCount = $historyData.requestHistory.Count
                } elseif ($null -ne $historyData.requestHistory) {
                    $result.EntryCount = 1
                }
                
                # Validate individual entries if requested
                if ($ValidateEntries -and $result.EntryCount -gt 0) {
                    $validCount = 0
                    $invalidCount = 0
                    
                    $entriesToCheck = if ($historyData.requestHistory -is [array]) { 
                        $historyData.requestHistory 
                    } else { 
                        @($historyData.requestHistory) 
                    }
                    
                    foreach ($entry in $entriesToCheck) {
                        if (Test-RequestHistoryEntryStructure -Entry $entry) {
                            $validCount++
                        } else {
                            $invalidCount++
                        }
                    }
                    
                    $result.ValidEntries = $validCount
                    
                    if ($invalidCount -gt 0) {
                        $result.IsValid = $false
                        $result.Issues += "Found $invalidCount invalid entries out of $($result.EntryCount) total"
                    }
                }
            }
        }
        
        # Check for unexpected properties (potential data corruption)
        $expectedProperties = @('requestHistory')
        foreach ($property in $historyData.PSObject.Properties) {
            if ($property.Name -notin $expectedProperties) {
                $result.Issues += "Unexpected property found: $($property.Name)"
                # This is a warning, not necessarily invalid
            }
        }
        
        # Log results
        if ($result.IsValid) {
            Write-Host "[OK] Request history file format validation passed" -ForegroundColor Green
            Write-Host "[INFO] Total entries: $($result.EntryCount), Valid entries: $($result.ValidEntries)" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Request history file format validation failed" -ForegroundColor Red
            foreach ($issue in $result.Issues) {
                Write-Host "[ERROR] - $issue" -ForegroundColor Red
            }
        }
        
        return $result
    }
    catch {
        $result.IsValid = $false
        $result.Issues += "Unexpected error during format validation: $($_.Exception.Message)"
        Write-Host "[ERROR] Error validating request history file format: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[ERROR] Exception type: $($_.Exception.GetType().Name)" -ForegroundColor Red
        return $result
    }
}

function Test-RequestHistoryFileCorruption {
    <#
    .SYNOPSIS
    检测请求历史文件是否损坏
    
    .DESCRIPTION
    检查请求历史文件的完整性，包括JSON格式、结构和内容验证
    
    .PARAMETER HistoryPath
    请求历史文件路径
    
    .OUTPUTS
    Hashtable with corruption details: @{ IsCorrupted = $bool; Issues = @(); CanRecover = $bool }
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath
    )
    
    $result = @{
        IsCorrupted = $false
        Issues = @()
        CanRecover = $true
        RecoverableEntries = 0
    }
    
    try {
        # Check if file exists
        if (-not (Test-Path $HistoryPath)) {
            $result.Issues += "File does not exist"
            $result.IsCorrupted = $true
            return $result
        }
        
        # Check file size
        $fileInfo = Get-Item $HistoryPath
        if ($fileInfo.Length -eq 0) {
            $result.Issues += "File is empty"
            $result.IsCorrupted = $true
            return $result
        }
        
        # Check file permissions
        try {
            $testRead = Get-Content -Path $HistoryPath -TotalCount 1 -ErrorAction Stop
        }
        catch [System.UnauthorizedAccessException] {
            $result.Issues += "Access denied - insufficient permissions"
            $result.IsCorrupted = $true
            $result.CanRecover = $false
            return $result
        }
        
        # Read and parse JSON
        $jsonContent = $null
        try {
            $jsonContent = Get-Content -Path $HistoryPath -Raw -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            $result.Issues += "Cannot read file content: $($_.Exception.Message)"
            $result.IsCorrupted = $true
            $result.CanRecover = $false
            return $result
        }
        
        if ([string]::IsNullOrWhiteSpace($jsonContent)) {
            $result.Issues += "File content is empty or whitespace"
            $result.IsCorrupted = $true
            return $result
        }
        
        # Test JSON parsing
        $historyData = $null
        try {
            $historyData = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $result.Issues += "Invalid JSON format: $($_.Exception.Message)"
            $result.IsCorrupted = $true
            
            # Try to recover partial JSON
            if ($jsonContent -match '\{.*"requestHistory".*\[') {
                $result.Issues += "Partial JSON structure detected - may be recoverable"
            } else {
                $result.CanRecover = $false
            }
            return $result
        }
        
        # Validate structure
        if ($null -eq $historyData) {
            $result.Issues += "Parsed data is null"
            $result.IsCorrupted = $true
            return $result
        }
        
        if (-not $historyData.PSObject.Properties['requestHistory']) {
            $result.Issues += "Missing requestHistory property"
            $result.IsCorrupted = $true
            return $result
        }
        
        # Validate requestHistory is array
        if ($historyData.requestHistory -isnot [array] -and $null -ne $historyData.requestHistory) {
            $result.Issues += "requestHistory is not an array"
            $result.IsCorrupted = $true
            # Can recover by converting to array
        }
        
        # Validate individual entries
        $validEntries = 0
        $invalidEntries = 0
        
        if ($historyData.requestHistory -is [array]) {
            foreach ($entry in $historyData.requestHistory) {
                if (Test-RequestHistoryEntryStructure -Entry $entry) {
                    $validEntries++
                } else {
                    $invalidEntries++
                }
            }
        } elseif ($null -ne $historyData.requestHistory) {
            if (Test-RequestHistoryEntryStructure -Entry $historyData.requestHistory) {
                $validEntries = 1
            } else {
                $invalidEntries = 1
            }
        }
        
        $result.RecoverableEntries = $validEntries
        
        if ($invalidEntries -gt 0) {
            $result.Issues += "Found $invalidEntries invalid entries out of $($validEntries + $invalidEntries) total"
            $result.IsCorrupted = $true
        }
        
        # Check for duplicate entries (same timestamp)
        if ($validEntries -gt 1) {
            $timestamps = @()
            foreach ($entry in $historyData.requestHistory) {
                if ($entry.PSObject.Properties['timestamp']) {
                    $timestamps += $entry.timestamp
                }
            }
            $uniqueTimestamps = $timestamps | Select-Object -Unique
            if ($timestamps.Count -ne $uniqueTimestamps.Count) {
                $result.Issues += "Found duplicate timestamp entries"
                $result.IsCorrupted = $true
            }
        }
        
        return $result
    }
    catch {
        $result.Issues += "Unexpected error during corruption check: $($_.Exception.Message)"
        $result.IsCorrupted = $true
        $result.CanRecover = $false
        return $result
    }
}

function Repair-RequestHistoryFile {
    <#
    .SYNOPSIS
    修复请求历史文件
    
    .DESCRIPTION
    尝试修复损坏或格式不正确的请求历史文件，包括数据恢复和结构修复
    
    .PARAMETER HistoryPath
    请求历史文件路径
    
    .PARAMETER CreateBackup
    是否创建修复前的备份文件
    
    .OUTPUTS
    Boolean indicating success
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory=$false)]
        [bool]$CreateBackup = $true
    )
    
    try {
        Write-Host "[PROC] Starting comprehensive repair of request history file..." -ForegroundColor Yellow
        
        # First, check corruption status
        $corruptionCheck = Test-RequestHistoryFileCorruption -HistoryPath $HistoryPath
        
        if (-not $corruptionCheck.IsCorrupted) {
            Write-Host "[OK] File is not corrupted, no repair needed" -ForegroundColor Green
            return $true
        }
        
        Write-Host "[WARN] File corruption detected:" -ForegroundColor Yellow
        foreach ($issue in $corruptionCheck.Issues) {
            Write-Host "  - $issue" -ForegroundColor Yellow
        }
        
        if (-not $corruptionCheck.CanRecover) {
            Write-Host "[ERROR] File cannot be recovered, will create new empty file" -ForegroundColor Red
            return Initialize-RequestHistoryFile -HistoryPath $HistoryPath
        }
        
        # Create backup if requested and file exists
        if ($CreateBackup -and (Test-Path $HistoryPath)) {
            $backupPath = "$HistoryPath.corrupt.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            try {
                Copy-Item $HistoryPath $backupPath -Force
                Write-Host "[INFO] Created corruption backup: $backupPath" -ForegroundColor Gray
            }
            catch {
                Write-Host "[WARN] Could not create backup: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        # Attempt to read and recover data
        $recoveredEntries = @()
        
        if (Test-Path $HistoryPath) {
            try {
                $jsonContent = Get-Content -Path $HistoryPath -Raw -Encoding UTF8 -ErrorAction Stop
                
                # Try to parse JSON
                $existingData = $null
                try {
                    $existingData = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    Write-Host "[WARN] Cannot parse JSON, attempting manual recovery..." -ForegroundColor Yellow
                    
                    # Try to extract valid JSON fragments
                    if ($jsonContent -match '"requestHistory"\s*:\s*\[(.*)\]') {
                        Write-Host "[INFO] Found requestHistory array pattern, attempting entry recovery..." -ForegroundColor Gray
                        # This is a simplified recovery - in practice, you might want more sophisticated parsing
                    }
                }
                
                # If we have parsed data, extract valid entries
                if ($null -ne $existingData) {
                    if ($existingData.PSObject.Properties['requestHistory']) {
                        $historyArray = $existingData.requestHistory
                        
                        # Convert single entry to array if needed
                        if ($historyArray -isnot [array] -and $null -ne $historyArray) {
                            $historyArray = @($historyArray)
                        }
                        
                        # Validate and recover entries
                        if ($historyArray -is [array]) {
                            foreach ($entry in $historyArray) {
                                if (Test-RequestHistoryEntryStructure -Entry $entry) {
                                    $recoveredEntries += $entry
                                } else {
                                    Write-Host "[WARN] Skipping invalid entry during recovery" -ForegroundColor Yellow
                                }
                            }
                        }
                    }
                }
            }
            catch {
                Write-Host "[WARN] Error during data recovery: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        # Create repaired structure
        $repairedData = @{
            requestHistory = $recoveredEntries
        }
        
        Write-Host "[INFO] Recovered $($recoveredEntries.Count) valid entries" -ForegroundColor Gray
        
        # Write repaired data
        $result = Write-RequestHistoryFile -HistoryPath $HistoryPath -HistoryData $repairedData
        
        if ($result) {
            # Verify repair was successful
            $verifyCheck = Test-RequestHistoryFileCorruption -HistoryPath $HistoryPath
            if (-not $verifyCheck.IsCorrupted) {
                Write-Host "[OK] Request history file repaired successfully" -ForegroundColor Green
                Write-Host "[INFO] Repair summary: $($recoveredEntries.Count) entries recovered" -ForegroundColor Green
            } else {
                Write-Host "[WARN] File repaired but still has issues:" -ForegroundColor Yellow
                foreach ($issue in $verifyCheck.Issues) {
                    Write-Host "  - $issue" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "[ERROR] Failed to write repaired data" -ForegroundColor Red
        }
        
        return $result
    }
    catch {
        Write-Host "[ERROR] Unexpected error during file repair: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[ERROR] Exception type: $($_.Exception.GetType().Name)" -ForegroundColor Red
        
        # As last resort, try to create new empty file
        Write-Host "[PROC] Attempting to create new empty file as last resort..." -ForegroundColor Yellow
        return Initialize-RequestHistoryFile -HistoryPath $HistoryPath
    }
}

function Invoke-RequestHistoryRecovery {
    <#
    .SYNOPSIS
    执行请求历史文件的完整恢复流程
    
    .DESCRIPTION
    检测并修复请求历史文件的各种问题，包括缺失文件、损坏文件和格式错误
    
    .PARAMETER HistoryPath
    请求历史文件路径
    
    .PARAMETER ForceRecovery
    强制执行恢复，即使文件看起来正常
    
    .OUTPUTS
    Hashtable with recovery results: @{ Success = $bool; Action = $string; Message = $string; EntriesRecovered = $int }
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory=$false)]
        [bool]$ForceRecovery = $false
    )
    
    $result = @{
        Success = $false
        Action = "None"
        Message = ""
        EntriesRecovered = 0
    }
    
    try {
        Write-Host "[PROC] Starting request history recovery process..." -ForegroundColor Yellow
        
        # Step 1: Check if file exists
        if (-not (Test-Path $HistoryPath)) {
            Write-Host "[INFO] Request history file does not exist, creating new file..." -ForegroundColor Gray
            $success = Initialize-RequestHistoryFile -HistoryPath $HistoryPath
            if ($success) {
                $result.Success = $true
                $result.Action = "Created"
                $result.Message = "Created new request history file"
                Write-Host "[OK] New request history file created successfully" -ForegroundColor Green
            } else {
                $result.Message = "Failed to create new request history file"
                Write-Host "[ERROR] Failed to create new request history file" -ForegroundColor Red
            }
            return $result
        }
        
        # Step 2: Check for corruption
        $corruptionCheck = Test-RequestHistoryFileCorruption -HistoryPath $HistoryPath
        
        if (-not $corruptionCheck.IsCorrupted -and -not $ForceRecovery) {
            Write-Host "[OK] Request history file is healthy, no recovery needed" -ForegroundColor Green
            $result.Success = $true
            $result.Action = "None"
            $result.Message = "File is healthy"
            $result.EntriesRecovered = $corruptionCheck.RecoverableEntries
            return $result
        }
        
        # Step 3: Attempt repair
        Write-Host "[PROC] File issues detected, attempting repair..." -ForegroundColor Yellow
        $repairSuccess = Repair-RequestHistoryFile -HistoryPath $HistoryPath -CreateBackup $true
        
        if ($repairSuccess) {
            # Verify repair
            $postRepairCheck = Test-RequestHistoryFileCorruption -HistoryPath $HistoryPath
            if (-not $postRepairCheck.IsCorrupted) {
                $result.Success = $true
                $result.Action = "Repaired"
                $result.Message = "File successfully repaired"
                $result.EntriesRecovered = $postRepairCheck.RecoverableEntries
                Write-Host "[OK] Request history file recovery completed successfully" -ForegroundColor Green
            } else {
                $result.Success = $false
                $result.Action = "PartialRepair"
                $result.Message = "File partially repaired but still has issues"
                $result.EntriesRecovered = $postRepairCheck.RecoverableEntries
                Write-Host "[WARN] File partially repaired but still has issues" -ForegroundColor Yellow
            }
        } else {
            $result.Success = $false
            $result.Action = "Failed"
            $result.Message = "File repair failed"
            Write-Host "[ERROR] Request history file repair failed" -ForegroundColor Red
        }
        
        return $result
    }
    catch {
        $result.Success = $false
        $result.Action = "Error"
        $result.Message = "Unexpected error during recovery: $($_.Exception.Message)"
        Write-Host "[ERROR] Unexpected error during recovery: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[ERROR] Exception type: $($_.Exception.GetType().Name)" -ForegroundColor Red
        return $result
    }
}

function Get-RequestHistoryHealthStatus {
    <#
    .SYNOPSIS
    获取请求历史文件的健康状态报告
    
    .DESCRIPTION
    生成请求历史文件的详细健康状态报告，包括文件状态、条目统计和潜在问题
    
    .PARAMETER HistoryPath
    请求历史文件路径
    
    .OUTPUTS
    Hashtable with health status details
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath
    )
    
    $status = @{
        FileExists = $false
        FileSize = 0
        IsReadable = $false
        IsWritable = $false
        IsCorrupted = $false
        HasValidFormat = $false
        TotalEntries = 0
        ValidEntries = 0
        InvalidEntries = 0
        Issues = @()
        LastModified = $null
        Recommendations = @()
    }
    
    try {
        # Check file existence
        if (Test-Path $HistoryPath) {
            $status.FileExists = $true
            
            # Get file info
            $fileInfo = Get-Item $HistoryPath
            $status.FileSize = $fileInfo.Length
            $status.LastModified = $fileInfo.LastWriteTime
            
            # Test readability
            try {
                $testContent = Get-Content -Path $HistoryPath -TotalCount 1 -ErrorAction Stop
                $status.IsReadable = $true
            }
            catch {
                $status.Issues += "File is not readable: $($_.Exception.Message)"
            }
            
            # Test writability
            try {
                $testFile = "$HistoryPath.writetest"
                "test" | Out-File -FilePath $testFile -ErrorAction Stop
                Remove-Item $testFile -ErrorAction SilentlyContinue
                $status.IsWritable = $true
            }
            catch {
                $status.Issues += "File is not writable: $($_.Exception.Message)"
            }
            
            # Check corruption
            $corruptionCheck = Test-RequestHistoryFileCorruption -HistoryPath $HistoryPath
            $status.IsCorrupted = $corruptionCheck.IsCorrupted
            if ($corruptionCheck.IsCorrupted) {
                $status.Issues += $corruptionCheck.Issues
            }
            
            # Check format
            $formatCheck = Test-RequestHistoryFileFormat -HistoryPath $HistoryPath -ValidateEntries $true
            $status.HasValidFormat = $formatCheck.IsValid
            $status.TotalEntries = $formatCheck.EntryCount
            $status.ValidEntries = $formatCheck.ValidEntries
            $status.InvalidEntries = $status.TotalEntries - $status.ValidEntries
            
            if (-not $formatCheck.IsValid) {
                $status.Issues += $formatCheck.Issues
            }
        } else {
            $status.Issues += "File does not exist"
        }
        
        # Generate recommendations
        if (-not $status.FileExists) {
            $status.Recommendations += "Create new request history file using Initialize-RequestHistoryFile"
        } elseif ($status.IsCorrupted) {
            $status.Recommendations += "Run Repair-RequestHistoryFile to fix corruption"
        } elseif ($status.InvalidEntries -gt 0) {
            $status.Recommendations += "Run Repair-RequestHistoryFile to clean up invalid entries"
        } elseif (-not $status.IsWritable) {
            $status.Recommendations += "Check file permissions and disk space"
        } elseif ($status.FileSize -eq 0) {
            $status.Recommendations += "Initialize empty file with proper structure"
        }
        
        if ($status.TotalEntries -gt 10000) {
            $status.Recommendations += "Consider archiving old entries to improve performance"
        }
        
        return $status
    }
    catch {
        $status.Issues += "Error getting health status: $($_.Exception.Message)"
        return $status
    }
}

# Functions are available when dot-sourced