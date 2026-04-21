# check-account.ps1
# Zweck:    Prueft automatisch, ob der aktuelle Azure-Account alle
#           Voraussetzungen fuer das pslinter-Projekt erfuellt.
# Laufzeit: ~15 Sekunden.
# Ausfuehren in der Azure Cloud Shell (Portal oben rechts, PowerShell-Modus).
# Aufruf:   ./check-account.ps1

$ErrorActionPreference = 'Stop'

$results = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [ValidateSet('OK','WARN','FAIL','INFO')] [string]$Status,
        [string]$Text
    )
    $color = @{ OK='Green'; WARN='Yellow'; FAIL='Red'; INFO='Cyan' }[$Status]
    $tag   = @{ OK='[ OK ]'; WARN='[WARN]'; FAIL='[FEHL]'; INFO='[INFO]' }[$Status]
    Write-Host ("{0} {1}" -f $tag, $Text) -ForegroundColor $color
    $results.Add([pscustomobject]@{ Status = $Status; Text = $Text })
}

function Write-Section([string]$title) {
    Write-Host ""
    Write-Host "--- $title ---" -ForegroundColor White
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor White
Write-Host "  pslinter - Azure-Account-Check" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor White

# --- Subscription ---
Write-Section "Subscription"
$ctx = Get-AzContext
if (-not $ctx -or -not $ctx.Subscription) {
    Add-Check FAIL "Kein Azure-Context. In Cloud Shell sollte das nie passieren. 'Connect-AzAccount' manuell ausfuehren."
    return
}

Add-Check INFO ("Account:        {0}" -f $ctx.Account.Id)
Add-Check INFO ("Subscription:   {0}" -f $ctx.Subscription.Name)
Add-Check INFO ("Sub-ID:         {0}" -f $ctx.Subscription.Id)

$sub     = Get-AzSubscription -SubscriptionId $ctx.Subscription.Id
$quotaId = $sub.SubscriptionPolicies.QuotaId
Add-Check INFO ("QuotaId:        {0}" -f $quotaId)

switch -Wildcard ($quotaId) {
    'AzureStudents*' { Add-Check OK   "Azure for Students: hartes Jahreslimit, ideal fuer Experimente." }
    'FreeTrial*'     { Add-Check WARN "Free Trial: 200 USD / 30 Tage, danach PAYG. Budget-Alert einplanen." }
    'PayAsYouGo*'    { Add-Check WARN "Pay-As-You-Go: keine Auto-Grenze. Budget-Alert ist Pflicht." }
    'MSDN*'          { Add-Check INFO "MSDN / Visual Studio: monatliches Guthaben vorhanden." }
    'EnterpriseAgreement*' { Add-Check INFO "Enterprise Agreement: Rahmen deines Unternehmens pruefen." }
    default          { Add-Check INFO "Subscription-Typ nicht eindeutig - notfalls manuell pruefen." }
}

# --- Rolle ---
Write-Section "Rolle / Berechtigung"
$scope = "/subscriptions/$($ctx.Subscription.Id)"
$roles = @()
try {
    $roles = Get-AzRoleAssignment -SignInName $ctx.Account.Id -ErrorAction Stop |
             Where-Object { $scope.StartsWith($_.Scope) -or $_.Scope.StartsWith($scope) -or $_.Scope -eq '/' }
} catch {
    Add-Check WARN ("Rollen-Abfrage fehlgeschlagen: {0}" -f $_.Exception.Message)
}

$roleNames = @($roles.RoleDefinitionName | Sort-Object -Unique)
if ($roleNames -contains 'Owner' -or $roleNames -contains 'Contributor') {
    Add-Check OK ("Rolle ausreichend: {0}" -f ($roleNames -join ', '))
} elseif ($roleNames.Count -gt 0) {
    Add-Check FAIL ("Rolle reicht nicht: {0}. Contributor oder Owner noetig." -f ($roleNames -join ', '))
} else {
    Add-Check WARN "Keine direkte Rollenzuweisung sichtbar (evtl. via Gruppe). Ressourcen-Anlage in Schritt 2 zeigt, ob es reicht."
}

# --- Resource Providers ---
Write-Section "Resource Provider"
foreach ($ns in 'Microsoft.Web','Microsoft.Storage','Microsoft.Insights') {
    try {
        $rp = Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Select-Object -First 1
        if ($rp.RegistrationState -eq 'Registered') {
            Add-Check OK ("{0}: Registered" -f $ns)
        } else {
            Add-Check FAIL ("{0}: {1}. Fix: Register-AzResourceProvider -ProviderNamespace {0}" -f $ns, $rp.RegistrationState)
        }
    } catch {
        Add-Check FAIL ("{0}: Abfrage-Fehler ({1})" -f $ns, $_.Exception.Message)
    }
}

# --- Region ---
Write-Section "Region West Europe"
try {
    $we = Get-AzLocation -ErrorAction Stop | Where-Object { $_.Location -eq 'westeurope' }
    if ($we) {
        Add-Check OK ("Region 'westeurope' verfuegbar ({0})" -f $we.DisplayName)
    } else {
        Add-Check FAIL "Region 'westeurope' fuer deine Subscription nicht freigegeben. Alternative: 'germanywestcentral'."
    }
} catch {
    Add-Check WARN ("Regions-Abfrage fehlgeschlagen: {0}" -f $_.Exception.Message)
}

# --- Consumption Plan ---
Write-Section "Consumption Plan (Windows, West Europe)"
try {
    $fnLocs = Get-AzFunctionAppAvailableLocation -OSType Windows -PlanType Consumption -ErrorAction Stop
    $names  = @($fnLocs.Name)
    if ($names -contains 'West Europe' -or $names -contains 'westeurope') {
        Add-Check OK "Consumption Plan (Windows) in West Europe verfuegbar."
    } else {
        Add-Check FAIL ("Consumption Plan in West Europe nicht angeboten. Verfuegbar: {0}" -f ($names -join ', '))
    }
} catch {
    Add-Check WARN ("Consumption-Verfuegbarkeit nicht automatisch pruefbar ({0}). Im Portal manuell verifizieren." -f $_.Exception.Message)
}

# --- Budgets ---
Write-Section "Bestehende Budgets"
try {
    $budgets = Get-AzConsumptionBudget -ErrorAction Stop
    if ($budgets) {
        foreach ($b in $budgets) {
            Add-Check INFO ("Budget '{0}': {1} {2} pro {3}" -f $b.Name, $b.Amount, $b.Category, $b.TimeGrain)
        }
    } else {
        Add-Check INFO "Kein Budget gesetzt. Phase 7 der Anleitung legt eins an (1 EUR + Mail-Alert)."
    }
} catch {
    Add-Check WARN ("Budget-Abfrage fehlgeschlagen ({0}). Portal pruefen." -f $_.Exception.Message)
}

# --- Zusammenfassung ---
$counts = $results | Group-Object Status | ForEach-Object { @{ $_.Name = $_.Count } }
$summary = @{ OK=0; WARN=0; FAIL=0; INFO=0 }
foreach ($c in $counts) { foreach ($k in $c.Keys) { $summary[$k] = $c[$k] } }

Write-Host ""
Write-Host "==================================================" -ForegroundColor White
Write-Host "  Zusammenfassung" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor White
Write-Host ("  OK:    {0}" -f $summary.OK)   -ForegroundColor Green
Write-Host ("  WARN:  {0}" -f $summary.WARN) -ForegroundColor Yellow
Write-Host ("  FEHL:  {0}" -f $summary.FAIL) -ForegroundColor Red
Write-Host ""

if ($summary.FAIL -eq 0) {
    Write-Host "  Account-Check bestanden. Weiter zu Schritt 2 (Ressourcen anlegen)." -ForegroundColor Green
} else {
    Write-Host "  Account-Check hat Fehler. Oben die [FEHL]-Zeilen beheben, dann erneut ausfuehren." -ForegroundColor Red
}
Write-Host ""
