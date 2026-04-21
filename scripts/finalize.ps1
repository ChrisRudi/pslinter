# finalize.ps1
# Zweck:    Nach erfolgreichem create-resources.ps1:
#           1. Application Insights (+ Log Analytics Workspace) anlegen
#              und an Function App binden (Monitoring).
#           2. Publish Profile XML fuer GitHub Secret ausgeben.
# Aufruf:   ./finalize.ps1
#           Optional: ./finalize.ps1 -AppName 'pslinter-api-cr'

param(
    [string]$ResourceGroup = 'pslinter-rg',
    [string]$Location      = 'westeurope',
    [string]$AppName       = 'pslinter-api',
    [string]$InsightsName  = 'pslinter-api-insights',
    [string]$WorkspaceName = 'pslinter-la'
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$text) {
    Write-Host ""
    Write-Host "==> $text" -ForegroundColor Cyan
}

# --- 1. Log Analytics Workspace (Voraussetzung fuer modernes App Insights) ---
Write-Step "Log Analytics Workspace '$WorkspaceName'"
$ws = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $WorkspaceName -ErrorAction SilentlyContinue
if ($ws) {
    Write-Host "   Bereits vorhanden." -ForegroundColor Green
} else {
    $ws = New-AzOperationalInsightsWorkspace `
        -ResourceGroupName $ResourceGroup `
        -Name              $WorkspaceName `
        -Location          $Location `
        -Sku               PerGB2018
    Write-Host "   Angelegt." -ForegroundColor Green
}

# --- 2. Application Insights ---
Write-Step "Application Insights '$InsightsName'"
$ai = Get-AzApplicationInsights -ResourceGroupName $ResourceGroup -Name $InsightsName -ErrorAction SilentlyContinue
if ($ai) {
    Write-Host "   Bereits vorhanden." -ForegroundColor Green
} else {
    $ai = New-AzApplicationInsights `
        -ResourceGroupName  $ResourceGroup `
        -Name               $InsightsName `
        -Location           $Location `
        -Kind               web `
        -WorkspaceResourceId $ws.ResourceId
    Write-Host "   Angelegt." -ForegroundColor Green
}

# --- 3. Function App mit AI verbinden ---
Write-Step "Function App '$AppName' mit App Insights verbinden"
Update-AzFunctionAppSetting `
    -ResourceGroupName $ResourceGroup `
    -Name              $AppName `
    -AppSetting        @{
        'APPLICATIONINSIGHTS_CONNECTION_STRING' = $ai.ConnectionString
        'APPINSIGHTS_INSTRUMENTATIONKEY'        = $ai.InstrumentationKey
    } `
    -Force | Out-Null
Write-Host "   Connection String hinterlegt." -ForegroundColor Green

# --- 4. Publish Profile holen ---
Write-Step "Publish Profile fuer '$AppName' holen"
$profileFile = Join-Path $PWD "$AppName.PublishSettings"
$profileXml  = Get-AzWebAppPublishingProfile `
    -ResourceGroupName $ResourceGroup `
    -Name              $AppName `
    -OutputFile        $profileFile
Write-Host "   Gespeichert als: $profileFile" -ForegroundColor Green

# --- 5. Ausgabe + Anleitung ---
Write-Host ""
Write-Host "==================================================" -ForegroundColor White
Write-Host "  PUBLISH PROFILE (XML) - zum Kopieren" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor White
Write-Host ""
Get-Content -Raw -Path $profileFile
Write-Host ""
Write-Host "==================================================" -ForegroundColor White
Write-Host "  Naechster Schritt: GitHub Secret anlegen" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor White
Write-Host ""
Write-Host "  1. Oeffne: https://github.com/ChrisRudi/pslinter/settings/secrets/actions"
Write-Host "  2. Klick:  'New repository secret'"
Write-Host "  3. Name:   AZURE_FUNCTIONAPP_PUBLISH_PROFILE"
Write-Host "  4. Secret: den XML-Block oben KOMPLETT einfuegen"
Write-Host "            (von <publishData> bis </publishData>)"
Write-Host "  5. Speichern -> 'Add secret'"
Write-Host ""
Write-Host "  Danach auf Branch 'main' mergen / pushen -> Deploy startet automatisch."
Write-Host ""
