# requirements.psd1
# Zweck: Managed Dependencies der Function App. Azure installiert die
#        Module automatisch beim Start (host.json managedDependency).
# Deps:  PSScriptAnalyzer aus der PowerShell Gallery, 1.x gepinnt.
#        Updates via .github/workflows/update-pssa.yml (PR-Workflow).

@{
    'PSScriptAnalyzer' = '1.23.0'
}
