# run.ps1
# Zweck:  HTTP-Endpoint fuer PowerShell-Linting via PSScriptAnalyzer.
# Input:  HTTP POST. Raw-Body = PS-Code. Query-Params: IncludeRule,
#         ExcludeRule, Severity, Settings (alle optional, CSV bei Arrays).
# Output: JSON-Array von PSSA-DiagnosticRecords (RuleName, Severity,
#         Line, Column, Message, ScriptName). HTTP 200 auch bei Syntax-
#         Fehlern (tolerant als Issue). HTTP 500 nur bei Runtime-Fehlern.
# Deps:   PSScriptAnalyzer (via requirements.psd1 als managed dependency).

using namespace System.Net

param($Request, $TriggerMetadata)

$started = Get-Date
$code    = [string]$Request.Body

function Split-Csv([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return @() }
    $value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
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

# Parser-/Syntax-Fehler werden von PSSA als Record emittiert und
# landen damit tolerant im Issue-Array (HTTP 200).
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

# Garantierte Array-Ausgabe: '@() | ConvertTo-Json -AsArray' liefert in
# manchen PS-Versionen leere Pipeline statt '[]'. Explizit handhaben.
if ($result.Count -eq 0) {
    $json = '[]'
} else {
    $json = ConvertTo-Json -InputObject $result -Depth 6 -AsArray
}

$durationMs = [int](New-TimeSpan -Start $started -End (Get-Date)).TotalMilliseconds
Write-Host ("lint ok duration_ms={0} body_len={1} issues={2}" -f $durationMs, $code.Length, $result.Count)

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Headers    = @{ 'Content-Type' = 'application/json' }
    Body       = $json
})
