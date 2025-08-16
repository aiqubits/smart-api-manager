# SymbolDefinitions.ps1 - Shared type definitions and symbols
# 共享类型定义和符号

# ResponseModel class definition - shared across all modules
class ResponseModel {
    [int]$StatusCode
    [string]$Status
    [hashtable]$Data
    [string]$Timestamp
    [string]$ErrorMessage
    [string]$RawResponse
    
    ResponseModel() {
        $this.Data = @{}
        $this.Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        $this.Status = "Unknown"
        $this.StatusCode = 0
        $this.ErrorMessage = ""
        $this.RawResponse = ""
    }
}

# Helper function to validate ResponseModel objects
function Test-ResponseModelObject {
    <#
    .SYNOPSIS
    Validates if an object is a valid ResponseModel
    
    .PARAMETER Object
    Object to validate
    
    .OUTPUTS
    Boolean indicating if object is valid ResponseModel
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Object
    )
    
    if ($null -eq $Object) {
        return $false
    }
    
    # Check for required properties
    $requiredProperties = @('Status', 'StatusCode', 'Data', 'Timestamp', 'ErrorMessage', 'RawResponse')
    
    foreach ($prop in $requiredProperties) {
        if (-not $Object.PSObject.Properties[$prop]) {
            return $false
        }
    }
    
    return $true
}

# Display symbols that work in all PowerShell environments
$script:GlobalSymbols = @{
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