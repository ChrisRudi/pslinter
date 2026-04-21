# profile.ps1
# Zweck: Startup-Logik der Function App. Stellt sicher, dass
#        PSScriptAnalyzer importiert ist. Managed Dependencies via
#        requirements.psd1 laden Drittanbieter-Module auf dieser
#        Runtime nicht zuverlaessig. Daher expliziter Install-Module
#        beim Cold Start (einmal ~30-90 Sek, danach gecacht).

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Install-Module -Name PSScriptAnalyzer `
        -Repository PSGallery `
        -Scope       CurrentUser `
        -Force `
        -AllowClobber `
        -AcceptLicense
}
Import-Module -Name PSScriptAnalyzer
