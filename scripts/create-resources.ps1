# create-resources.ps1
# Zweck:    Legt die Azure-Ressourcen fuer pslinter an:
#           Resource Group, Storage Account, Function App (Consumption,
#           Windows, PS 7.4), Application Insights wird von New-AzFunctionApp
#           automatisch angelegt.
# Ausfuehren in Cloud Shell NACH erfolgreichem check-account.ps1 und
# NACHDEM die Resource Provider auf 'Registered' sind (~1-3 Min).
# Aufruf:   ./create-resources.ps1
#           Optional: ./create-resources.ps1 -AppName 'pslinter-api-cr'

param(
    [string]$ResourceGroup = 'pslinter-rg',
    [string]$Location      = 'westeurope',
    [string]$AppName       = 'pslinter-api'
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$text) {
    Write-Host ""
    Write-Host "==> $text" -ForegroundColor Cyan
}

function Test-FunctionAppNameAvailable([string]$name) {
    $ctxSub = (Get-AzContext).Subscription.Id
    $payload = @{ name = $name; type = 'Microsoft.Web/sites' } | ConvertTo-Json -Compress
    $path = "/subscriptions/$ctxSub/providers/Microsoft.Web/checknameavailability?api-version=2022-03-01"
    $r = Invoke-AzRestMethod -Method POST -Path $path -Payload $payload
    return (($r.Content | ConvertFrom-Json).nameAvailable)
}

# --- 0. Resource Provider Status ---
Write-Step "Resource Provider Status"
foreach ($ns in 'Microsoft.Web','Microsoft.Storage','Microsoft.Insights') {
    $s = (Get-AzResourceProvider -ProviderNamespace $ns | Select-Object -First 1).RegistrationState
    if ($s -ne 'Registered') {
        Write-Host "   $ns : $s - bitte warten und Skript neu starten." -ForegroundColor Red
        return
    }
    Write-Host "   $ns : Registered" -ForegroundColor Green
}

# --- 1. Resource Group ---
Write-Step "Resource Group '$ResourceGroup' in '$Location'"
$rg = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
if ($rg) {
    Write-Host "   Bereits vorhanden." -ForegroundColor Green
} else {
    New-AzResourceGroup -Name $ResourceGroup -Location $Location | Out-Null
    Write-Host "   Angelegt." -ForegroundColor Green
}

# --- 2. Storage Account ---
Write-Step "Storage Account"
$existingSto = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue |
    Where-Object { $_.StorageAccountName -like 'pslinter*' } | Select-Object -First 1
if ($existingSto) {
    $storageName = $existingSto.StorageAccountName
    Write-Host "   Bereits vorhanden: $storageName" -ForegroundColor Green
} else {
    do {
        $suffix = -join (1..6 | ForEach-Object { [char](Get-Random -Minimum 97 -Maximum 123) })
        $storageName = "pslinter$suffix"
        $avail = Get-AzStorageAccountNameAvailability -Name $storageName
    } until ($avail.NameAvailable)
    Write-Host "   Name: $storageName"
    New-AzStorageAccount `
        -ResourceGroupName $ResourceGroup `
        -Name              $storageName `
        -Location          $Location `
        -SkuName           Standard_LRS `
        -Kind              StorageV2 `
        -AllowBlobPublicAccess $false | Out-Null
    Write-Host "   Angelegt." -ForegroundColor Green
}

# --- 3. Function App Name-Check ---
Write-Step "Function App Name-Verfuegbarkeit pruefen: '$AppName'"
$existingFn = Get-AzFunctionApp -ResourceGroupName $ResourceGroup -Name $AppName -ErrorAction SilentlyContinue
if ($existingFn) {
    Write-Host "   '$AppName' existiert bereits in '$ResourceGroup'." -ForegroundColor Green
} else {
    if (-not (Test-FunctionAppNameAvailable -name $AppName)) {
        $orig = $AppName
        for ($i = 0; $i -lt 20; $i++) {
            $try = "$orig-" + (Get-Random -Minimum 100 -Maximum 999)
            if (Test-FunctionAppNameAvailable -name $try) { $AppName = $try; break }
        }
        if ($AppName -eq $orig) {
            Write-Host "   '$orig' ist vergeben, kein freier Ersatz gefunden. Skript mit -AppName neu starten." -ForegroundColor Red
            return
        }
        Write-Host "   '$orig' vergeben. Nutze stattdessen: $AppName" -ForegroundColor Yellow
    } else {
        Write-Host "   '$AppName' ist frei." -ForegroundColor Green
    }

    # --- 4. Function App anlegen ---
    Write-Step "Function App '$AppName' anlegen (Consumption, Windows, PS 7.4) - 2-4 Min"
    New-AzFunctionApp `
        -ResourceGroupName    $ResourceGroup `
        -Name                 $AppName `
        -Location             $Location `
        -StorageAccountName   $storageName `
        -OSType               Windows `
        -Runtime              PowerShell `
        -RuntimeVersion       '7.4' `
        -FunctionsVersion     4 | Out-Null
    Write-Host "   Function App angelegt." -ForegroundColor Green
}

# --- 5. Zusammenfassung ---
Write-Host ""
Write-Host "==================================================" -ForegroundColor White
Write-Host "  Fertig - Ressourcen stehen" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor White
Write-Host ("  Resource Group: {0}" -f $ResourceGroup)
Write-Host ("  Storage:        {0}" -f $storageName)
Write-Host ("  Function App:   {0}" -f $AppName)
Write-Host ("  URL:            https://{0}.azurewebsites.net" -f $AppName)
Write-Host ""

if ($AppName -ne 'pslinter-api') {
    Write-Host "  ACHTUNG: App-Name weicht vom Default ab!" -ForegroundColor Yellow
    Write-Host "  In .github/workflows/deploy.yml muss AZURE_FUNCTIONAPP_NAME auf '$AppName' gesetzt werden." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  Naechster Schritt: Publish Profile holen und als GitHub-Secret setzen."
Write-Host "  Dafuer laeuft gleich: ./get-publish-profile.ps1"
Write-Host ""
