# setup-budget.ps1
# Zweck:    Legt Budget-Alert fuer die pslinter-Resource-Group an.
#           Mail-Notification an Action Group bei 80% und 100% Verbrauch.
# Ausfuehren in Cloud Shell.
# Aufruf:   ./setup-budget.ps1 -Email deine@mail.de
#           Optional: -Amount 5 -BudgetName pslinter-budget

param(
    [Parameter(Mandatory = $true)]
    [string]$Email,
    [string]$ResourceGroup    = 'pslinter-rg',
    [decimal]$Amount          = 1,
    [string]$ActionGroupName  = 'pslinter-alert-group',
    [string]$BudgetName       = 'pslinter-budget'
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$text) {
    Write-Host ""
    Write-Host "==> $text" -ForegroundColor Cyan
}

$subId = (Get-AzContext).Subscription.Id
$mgmt  = 'https://management.azure.com'
$base  = "/subscriptions/$subId/resourceGroups/$ResourceGroup"

# --- 1. Action Group ---
Write-Step "Action Group '$ActionGroupName' (Mail an $Email)"

$agUri  = "$mgmt$base/providers/Microsoft.Insights/actionGroups/${ActionGroupName}?api-version=2023-01-01"
$agBody = @{
    location   = 'global'
    properties = @{
        groupShortName = 'pslinter'
        enabled        = $true
        emailReceivers = @(
            @{
                name                 = 'admin-email'
                emailAddress         = $Email
                useCommonAlertSchema = $true
            }
        )
    }
} | ConvertTo-Json -Depth 6 -Compress

$agRes = Invoke-AzRestMethod -Uri $agUri -Method PUT -Payload $agBody
if ($agRes.StatusCode -ge 400) {
    throw "Action Group fehlgeschlagen: HTTP $($agRes.StatusCode) $($agRes.Content)"
}
Write-Host "   Angelegt/aktualisiert." -ForegroundColor Green

$agResourceId = "$base/providers/Microsoft.Insights/actionGroups/$ActionGroupName"

# --- 2. Budget ---
# StartDate muss erster Tag des aktuellen Monats sein (Azure-Constraint).
$now       = Get-Date
$startDate = (Get-Date -Year $now.Year -Month $now.Month -Day 1 `
              -Hour 0 -Minute 0 -Second 0).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
$endDate   = (Get-Date -Year ($now.Year + 5) -Month $now.Month -Day 1 `
              -Hour 0 -Minute 0 -Second 0).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

Write-Step "Budget '$BudgetName' = $Amount / Monat, Scope RG '$ResourceGroup'"

$budgetUri  = "$mgmt$base/providers/Microsoft.Consumption/budgets/${BudgetName}?api-version=2023-05-01"
$budgetBody = @{
    properties = @{
        category      = 'Cost'
        amount        = $Amount
        timeGrain     = 'Monthly'
        timePeriod    = @{
            startDate = $startDate
            endDate   = $endDate
        }
        notifications = @{
            'Actual_GreaterThan_80_Percent' = @{
                enabled              = $true
                operator             = 'GreaterThan'
                threshold            = 80
                thresholdType        = 'Actual'
                contactEmails        = @($Email)
                contactGroups        = @($agResourceId)
                notificationLanguage = 'de-de'
            }
            'Actual_GreaterThan_100_Percent' = @{
                enabled              = $true
                operator             = 'GreaterThan'
                threshold            = 100
                thresholdType        = 'Actual'
                contactEmails        = @($Email)
                contactGroups        = @($agResourceId)
                notificationLanguage = 'de-de'
            }
        }
    }
} | ConvertTo-Json -Depth 8 -Compress

$budgetRes = Invoke-AzRestMethod -Uri $budgetUri -Method PUT -Payload $budgetBody
if ($budgetRes.StatusCode -ge 400) {
    throw "Budget fehlgeschlagen: HTTP $($budgetRes.StatusCode) $($budgetRes.Content)"
}
Write-Host "   Angelegt/aktualisiert." -ForegroundColor Green

# --- 3. Zusammenfassung ---
Write-Host ""
Write-Host "==================================================" -ForegroundColor White
Write-Host "  Budget-Alert aktiv" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor White
Write-Host "  Betrag:       $Amount / Monat (Subscription-Waehrung)"
Write-Host "  Scope:        Resource Group $ResourceGroup"
Write-Host "  Trigger:      80% und 100% Actual"
Write-Host "  Mail an:      $Email"
Write-Host "  Action Group: $ActionGroupName"
Write-Host ""
Write-Host "  Portal-Check: Subscriptions -> Budgets -> $BudgetName"
Write-Host ""
Write-Host "  Wenn die Mail kommt, 1. Function App stoppen:" -ForegroundColor Yellow
Write-Host "     Stop-AzFunctionApp -ResourceGroupName $ResourceGroup -Name pslinter-api -Force" -ForegroundColor Yellow
Write-Host ""
