# pslinter

PowerShell-Linter als HTTP-API auf Azure Functions (PS 7.4, Consumption
Plan, Windows). Engine: PSScriptAnalyzer. Zielgruppe: AI-Coding-Agenten
wie Claude Code, die keine PowerShell-Runtime in ihrer Sandbox haben
und PS-Code trotzdem vor der Auslieferung validieren wollen.

Setup-Anleitung: siehe [pslinter-setup.md](./pslinter-setup.md).

## Endpoint

```
POST https://pslinter-api.azurewebsites.net/api/lint?code=FUNCTION_KEY
```

- **Auth:** Function Key via Query-Param `?code=...`
- **Request-Body:** Raw PowerShell-Code, `Content-Type: text/plain`
- **Query-Parameter** (alle optional, CSV bei Arrays):
  - `IncludeRule` - nur diese Regeln anwenden
  - `ExcludeRule` - diese Regeln unterdruecken
  - `Severity` - `Error`, `Warning`, `Information`
  - `Settings` - PSSA-Preset (z. B. `PSGallery`) oder Pfad

## Response

JSON-Array von PSSA-DiagnosticRecords:

```json
[
  {
    "RuleName": "PSAvoidUsingCmdletAliases",
    "Severity": "Warning",
    "Line": 1,
    "Column": 18,
    "Message": "'%' is an alias of 'ForEach-Object'. ...",
    "ScriptName": ""
  }
]
```

Sauberer Code -> leeres Array `[]`.
Syntax-Fehler im Input -> Record im Array, **HTTP 200** (tolerant).
**HTTP 500** nur bei Runtime-Fehlern (z. B. fehlendes Modul).

## Beispiele

### curl

```bash
curl -X POST "https://pslinter-api.azurewebsites.net/api/lint?code=KEY" \
     -H "Content-Type: text/plain" \
     --data-binary 'Get-ChildItem | % { $_.Name }'
```

### PowerShell

```powershell
$key = 'KEY'
$url = "https://pslinter-api.azurewebsites.net/api/lint?code=$key"
Invoke-RestMethod -Uri $url -Method Post -ContentType 'text/plain' `
    -Body 'Get-ChildItem | % { $_.Name }'
```

### Mit PSSA-Parametern

```powershell
$qs = 'Severity=Warning,Error&ExcludeRule=PSAvoidUsingWriteHost'
$url = "https://pslinter-api.azurewebsites.net/api/lint?code=$key&$qs"
Invoke-RestMethod -Uri $url -Method Post -ContentType 'text/plain' `
    -Body (Get-Content .\skript.ps1 -Raw)
```

## Hinweis fuer AI-Agenten

- Auth ausschliesslich via `?code=` (kein Header).
- Request-Body ist der rohe PowerShell-Code, kein JSON-Wrapper.
- Response ist immer ein JSON-Array, auch bei 0 Issues (`[]`).
- Serverseitig wird der Input-Code **nie geloggt**, nur Metadaten
  (Timestamp, Dauer, Issue-Count).

## Projekt-Struktur

```
lint/
  function.json             HTTP-Trigger (POST, authLevel function)
  run.ps1                   Endpoint-Logik
host.json                   Functions-Runtime-Config, managed deps an
requirements.psd1           Managed Dependencies (PSScriptAnalyzer)
profile.ps1                 PS-Startup (bewusst leer)
.funcignore                 Package-Ausschluesse beim Deploy
.github/workflows/
  deploy.yml                Push main -> Azure/functions-action@v1
  update-pssa.yml           Woechentlicher PSSA-Version-Check (PR)
pslinter-setup.md           Komplette Aufbau-Anleitung
```
