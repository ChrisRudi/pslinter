# run.ps1
# Zweck:  HTTP-Endpoint fuer PowerShell-Linting via PSScriptAnalyzer.
# Input:  HTTP POST. Raw-Body = PS-Code. Query-Params: IncludeRule,
#         ExcludeRule, Severity, Settings (alle optional, CSV bei Arrays).
# Output: JSON-Array von PSSA-DiagnosticRecords (RuleName, Severity,
#         Line, Column, Message, ScriptName). HTTP 200 auch bei Syntax-
#         Fehlern (tolerant als Issue). HTTP 500 mit JSON-Errorobjekt bei
#         Runtime-Fehlern.
# Deps:   PSScriptAnalyzer (im Modules-Ordner mitgeliefert durch deploy.yml).

using namespace System.Net

param($Request, $TriggerMetadata)

function Split-Csv([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return @() }
    $value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

try {
    $started = Get-Date
    $code    = [string]$Request.Body

    # Soft Rate Limit: 100 Requests pro UTC-Tag pro PowerShell-Worker.
    # $script:-Scope persistiert zwischen Invocations derselben Instance;
    # Cold Start resettet den Counter. Fair-Use-Guard, kein Hard Cap.
    if (-not $script:pslintUsage) { $script:pslintUsage = @{} }
    $dayKey = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    foreach ($stale in @($script:pslintUsage.Keys | Where-Object { $_ -ne $dayKey })) {
        $script:pslintUsage.Remove($stale)
    }
    $count = ($script:pslintUsage[$dayKey] ?? 0) + 1
    $script:pslintUsage[$dayKey] = $count

    if ($count -gt 100) {
        Write-Warning "rate-limit $dayKey count=$count"
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::TooManyRequests
            Headers    = @{
                'Content-Type'   = 'application/json'
                'Retry-After'    = '3600'
            }
            Body       = (@{
                error      = 'daily limit exceeded'
                limit      = 100
                windowUtc  = $dayKey
                retryAfter = 'next UTC midnight'
            } | ConvertTo-Json)
        })
        return
    }

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
        type            = $_.Exception.GetType().FullName
        message         = $_.Exception.Message
        scriptLine      = $_.InvocationInfo.ScriptLineNumber
        positionMessage = $_.InvocationInfo.PositionMessage
        stackTrace      = $_.ScriptStackTrace
    }
    Write-Error ("lint-error: {0}" -f ($err | ConvertTo-Json -Depth 4 -Compress))

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Headers    = @{ 'Content-Type' = 'application/json' }
        Body       = ($err | ConvertTo-Json -Depth 4)
    })
}
