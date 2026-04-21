# pslinter

PowerShell-Linter als oeffentliche HTTP-API auf Azure Functions
(PS 7.4, Consumption Plan, Windows). Engine: PSScriptAnalyzer.
Primaer fuer AI-Coding-Agenten wie Claude Code, die keine
PowerShell-Runtime in ihrer Sandbox haben und PS-Code vor der
Auslieferung validieren wollen.

Setup-Anleitung: siehe [pslinter-setup.md](./pslinter-setup.md).

## Endpoint

```
POST https://pslinter-api.azurewebsites.net/api/lint
```

- **Auth:** keine (anonym). Serverseitiges Rate Limit siehe unten.
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
**HTTP 500** nur bei Runtime-Fehlern (JSON-Body mit Error-Details).
**HTTP 429** beim Ueberschreiten des Tageslimits.

## Rate Limit

200 Aufrufe pro UTC-Tag pro PowerShell-Worker. Soft Cap: bei
Cold Starts wird der In-Memory-Counter zurueckgesetzt, das
tatsaechliche Limit liegt daher etwas hoeher. Als Hard-Stop
zaehlt der Azure-Budget-Alert (1 EUR/Monat).

HTTP 429 Response:

```json
{
  "error": "Tageslimit von 200 Aufrufen ueberschritten",
  "limit": 200,
  "windowUtc": "2026-04-21",
  "retryAfter": "next UTC midnight"
}
```

## Beispiele

### curl

```bash
curl -X POST "https://pslinter-api.azurewebsites.net/api/lint" \
     -H "Content-Type: text/plain" \
     --data-binary 'Get-ChildItem | % { $_.Name }'
```

### PowerShell

```powershell
Invoke-RestMethod `
    -Uri 'https://pslinter-api.azurewebsites.net/api/lint' `
    -Method Post `
    -ContentType 'text/plain' `
    -Body 'Get-ChildItem | % { $_.Name }'
```

### Mit PSSA-Parametern

```powershell
$qs  = 'Severity=Warning,Error&ExcludeRule=PSAvoidUsingWriteHost'
$url = "https://pslinter-api.azurewebsites.net/api/lint?$qs"
Invoke-RestMethod -Uri $url -Method Post -ContentType 'text/plain' `
    -Body (Get-Content .\skript.ps1 -Raw)
```

## Hinweis fuer AI-Agenten

- Keine Authentifizierung. Request-Body = roher PowerShell-Code.
- Response immer JSON-Array, auch bei 0 Issues (`[]`).
- Serverseitig wird der Input-Code **nie geloggt**, nur Metadaten
  (Timestamp, Dauer, Issue-Count).
- Bei 429 warten bis zum naechsten UTC-Tag.

## Claude Code Integration

Das Repo bringt einen fertig konfigurierten PostToolUse-Hook mit,
der `.ps1`/`.psm1`/`.psd1`-Dateien nach jedem Write/Edit automatisch
an den Endpoint schickt und Lint-Issues in den Claude-Transcript
einspielt. Konfiguration in `.claude/settings.json`, Script in
`.claude/pslint-hook.sh`. Einziges Setup: Claude-Code-Session einmal
neu starten, damit die Sandbox-Allowlist fuer
`pslinter-api.azurewebsites.net` greift.

## Projekt-Struktur

```
lint/
  function.json             HTTP-Trigger (POST, authLevel anonymous)
  run.ps1                   Endpoint-Logik + Rate Limit
host.json                   Functions-Runtime-Config
requirements.psd1           Managed-Deps-Marker (deaktiviert)
profile.ps1                 PS-Startup (leer)
.funcignore                 Package-Ausschluesse beim Deploy
.claude/
  settings.json             Claude-Code-Hook + Sandbox-Allowlist
  pslint-hook.sh            Shell-Hook fuer PostToolUse
.github/workflows/
  deploy.yml                Push main -> Save-Module + Azure-Deploy
  update-pssa.yml           Woechentlicher PSSA-Version-Check (PR)
scripts/
  check-account.ps1         Azure-Account-Voraussetzungen pruefen
  create-resources.ps1      RG + Storage + Function App anlegen
  finalize.ps1              App Insights + Publish Profile
  setup-budget.ps1          Action Group + Budget-Alert
pslinter-setup.md           Komplette Aufbau-Anleitung
```
