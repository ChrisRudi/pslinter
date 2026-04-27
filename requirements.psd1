# requirements.psd1
# Zweck: Managed Dependencies der Function App. Azure installiert die
#        Module automatisch beim Start (host.json managedDependency).
# Deps:  PSScriptAnalyzer aus der PowerShell Gallery.
#        Managed Dependencies akzeptieren nur 'MajorVersion.*' -
#        spezifische Versionen werden stillschweigend ignoriert und das
#        Modul waere nicht verfuegbar. Deshalb '1.*', nicht '1.23.0'.
#        Minor/Patch-Updates laufen damit automatisch. Der Cron-Workflow
#        update-pssa.yml dient nur als Alarm falls Major 2.x erscheint.

@{
    'PSScriptAnalyzer' = '1.25.0'
}
