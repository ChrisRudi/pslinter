# run.ps1
# Zweck:  HTTP-Endpoint fuer PowerShell-Linting via PSScriptAnalyzer.
# Input:  HTTP POST. Raw-Body = PS-Code. Query-Params: IncludeRule,
#         ExcludeRule, Severity, Settings (alle optional, CSV bei Arrays).
# Output: JSON-Array von PSSA-DiagnosticRecords (RuleName, Severity,
#         Line, Column, Message, ScriptName). HTTP 200 auch bei Syntax-
#         Fehlern (tolerant als Issue). HTTP 500 mit JSON-Errorobjekt bei
#         Runtime-Fehlern (fehlende Module, Serialisierung, ...).
# Deps:   PSScriptAnalyzer (via requirements.psd1 als managed dependency).

using namespace System.Net

param($Request, $TriggerMetadata)

function Split-Csv([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return @() }
    $value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

try {
    $started = Get-Date
    $code    = [string]$Request.Body

    $psaArgs = @{ ScriptDefinition = $code }

    $includeRule = Split-Csv $Request.Query.IncludeRule
    $excludeRule = Split-Csv $Request.Query.ExcludeRule
    $severity    = Split-Csv $Request.Query.Severity
    $settings    = $Request.Query.Settings

    if ($includeRule.Count -gt 0) { $psaArgs.IncludeRule = $includeRule }
    if ($excludeRule.Count -gt 0) { $psaArgs.ExcludeRule = $excludeRule }
    if ($severity.Count    -gt 0) { $psaArgs.Severity    = $severity    }
    if ($settings)                { $psaArgs.Settings    = $settings    }

    $records = Invoke-ScriptAnalyzer @psaArgs

    $result = @(
        foreach ($r in $records) {
            [ordered]@{
                RuleName   = $r.RuleName
                Severity   = [string]$r.Severity
                Line       = $r.Line
                Column     = $r.Column
                Message    = $r.Message
                ScriptName = $r.ScriptName
            }
        }
    )

    # '@() | ConvertTo-Json -AsArray' liefert in PS 7.4 leere Pipeline statt
    # '[]' -> explizit. Fuer Count > 0 liefert Pipeline + -AsArray verlaesslich
    # ein JSON-Array (auch bei nur einem Record).
    if ($result.Count -eq 0) {
        $json = '[]'
    } else {
        $json = $result | ConvertTo-Json -Depth 6 -AsArray
    }

    $durationMs = [int](New-TimeSpan -Start $started -End (Get-Date)).TotalMilliseconds
    Write-Host ("lint ok duration_ms={0} body_len={1} issues={2}" -f $durationMs, $code.Length, $result.Count)

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers    = @{ 'Content-Type' = 'application/json' }
        Body       = $json
    })
}
catch {
    $err = [ordered]@{
        type       = $_.Exception.GetType().FullName
        message    = $_.Exception.Message
        scriptLine = $_.InvocationInfo.ScriptLineNumber
        positionMessage = $_.InvocationInfo.PositionMessage
        stackTrace = $_.ScriptStackTrace
    }
    Write-Error ("lint-error: {0}" -f ($err | ConvertTo-Json -Depth 4 -Compress))

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Headers    = @{ 'Content-Type' = 'application/json' }
        Body       = ($err | ConvertTo-Json -Depth 4)
    })
}
