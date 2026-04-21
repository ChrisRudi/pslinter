# pslinter — Komplette Anleitung

PowerShell-Linter als HTTP-API auf Azure Functions. Alles in einer
Datei: Account-Pruefung, Azure-Setup, GitHub-Setup, CI/CD, Dependabot,
Budget-Alert, Code-Generierung via Claude Code, erster Test.

---

## Inhalt

- Projekt-Zusammenfassung
- Entscheidungsmatrix
- Phase 0 — Account-Pruefung
- Phase 1 — GitHub-Repo anlegen
- Phase 2 — Azure-Ressourcen anlegen
- Phase 3 — GitHub Actions einrichten
- Phase 4 — Code mit Claude Code generieren
- Phase 5 — Erster Deploy + Test
- Phase 6 — Auto-Update PSScriptAnalyzer
- Phase 7 — Budget-Alert
- Anhang A — Test-Calls
- Anhang B — Fehlerbehebung

---

## Projekt-Zusammenfassung

**Zweck:** HTTP-API fuer PowerShell-Linting via PSScriptAnalyzer.
Primaerer Use Case: AI-Coding-Agenten wie Claude Code, die keine
PowerShell-Runtime in ihrer Sandbox haben und PS-Code trotzdem vor
der Auslieferung validieren wollen.

**Endpoint:** `POST /api/lint`
**Auth:** Azure Function Key (`?code=xxx`)
**Request:** Query-Params (PSSA-native) + Raw-Body als PowerShell-Code
**Response:** JSON mit PSSA-DiagnosticRecord-Struktur
**Hosting:** Azure Functions, Consumption Plan, PowerShell 7.4
**Deploy:** GitHub Actions, Push auf `main` -> Production

---

## Entscheidungsmatrix

| ID | Thema | Entscheidung |
|---|---|---|
| P0-A | Lokale Tools | Keine — Claude Code + Azure Portal only |
| P2-A | Azure-Setup | Azure Portal (Klick-Assistent) |
| P2-B | Region | `westeurope` |
| P3-A | Deploy | GitHub Actions |
| P3-B | Branches | Nur `main`, Push = Deploy |
| P6-A | PSSA-Updates | Cron-Workflow, PR bei neuer Version |
| P7-A | Budget | 1 EUR/Monat + Mail-Alert |
| P7-B | Logging | Nur Metadaten, nie Input-Code |
| F1 | Function-App | `pslinter-api` |
| F2 | Repo | `pslinter` |
| — | Endpoint | `POST /api/lint` |
| — | Auth | Azure Function Key |
| — | Request-Format | Query-Params + Raw-Body |
| — | Response-Format | PSSA-DiagnosticRecord-JSON |
| — | Fehlerverhalten | Tolerant — Syntax-Fehler als Issue (HTTP 200) |

---

## Phase 0 — Account-Pruefung

**Ziel:** Sicherstellen, dass dein Azure-Account alle benoetigten
Features freigeschaltet hat, bevor wir Ressourcen anlegen.

### 0.1 Login

1. Gehe zu https://portal.azure.com
2. Melde dich mit dem Account an, den du nutzen willst (Schul-Account)

### 0.2 Subscription-Typ pruefen

1. Oben in der Suchleiste: **Subscriptions** eingeben, anklicken
2. Du siehst eine Liste deiner Subscriptions
3. Notiere dir:
   - **Name** der Subscription
   - **Subscription ID** (GUID)
   - **Offer / Typ** (z. B. "Azure for Students", "Free Trial",
     "Pay-As-You-Go")

**Bewertung:**
- "Azure for Students" — hat ein hartes Limit (meist 100 USD/Jahr),
  stoppt automatisch. Gut.
- "Free Trial" — 200 USD fuer 30 Tage, danach Pay-as-you-Go. Achtung.
- "Pay-As-You-Go" — keine automatische Grenze, Budget-Alert wird
  wichtiger.

### 0.3 Berechtigungen pruefen

1. In der Subscription-Detail-Seite links: **Access control (IAM)**
2. Reiter **Role assignments**
3. Suche deinen Account
4. Du brauchst mindestens die Rolle **Contributor** oder **Owner**

Wenn du nur **Reader** bist, kannst du keine Ressourcen anlegen.
Wende dich an den Admin deines Schul-Accounts.

### 0.4 Resource Provider pruefen

1. In der Subscription-Seite links: **Resource providers**
2. Suche nach `Microsoft.Web`, `Microsoft.Storage`, `Microsoft.Insights`
3. Status muss bei allen **Registered** sein. Falls **NotRegistered**:
   anklicken, oben **Register** klicken

### 0.5 Consumption Plan verfuegbar?

Schul-Accounts sind manchmal auf bestimmte Service-Typen limitiert.
Test ohne tatsaechlich etwas anzulegen:

1. Oben Suchleiste: **Function App** eingeben, anklicken
2. Oben links **Create** -> **Function App**
3. Falls gefragt: Hosting-Option **Consumption** (nicht "Flex
   Consumption" oder "Premium")
4. Unter **Region**: pruefe ob **West Europe** auswaehlbar ist
5. **Wichtig: diesen Dialog danach mit "Cancel" verlassen** —
   wir legen die Function erst in Phase 2 richtig an

**Falls Consumption Plan nicht verfuegbar ist:** Schul-Account reicht
nicht fuer dieses Projekt. Optionen:
- Eigenen Azure Free-Tier-Account anlegen
  (https://azure.microsoft.com/de-de/free/)
- Anderen Hosting-Weg waehlen (nicht Teil dieser Anleitung)

### 0.6 Bestehende Budget-Limits pruefen

1. Subscription-Seite links: **Budgets**
2. Wenn ein Budget existiert: notiere Hoehe und was passiert bei
   Ueberschreitung
3. Bei Schul-Accounts oft ein fest eingebautes Limit, das du nicht
   aendern kannst — das ist gut

### Pruefungs-Checkliste

```
[ ] Login am Portal erfolgreich
[ ] Subscription-Typ notiert
[ ] Subscription ID notiert
[ ] Rolle mindestens Contributor
[ ] Resource Provider Microsoft.Web registered
[ ] Resource Provider Microsoft.Storage registered
[ ] Resource Provider Microsoft.Insights registered
[ ] Consumption Plan in West Europe verfuegbar
[ ] Bestehende Budget-Limits bekannt
```

Alle Haken gesetzt -> weiter zu Phase 1.

---

## Phase 1 — GitHub-Repo anlegen

**Ziel:** Leeres Repository, in das spaeter Code + Workflow kommen.

1. Gehe zu https://github.com/new
2. **Owner:** ChrisRudi
3. **Repository name:** `pslinter`
4. **Description:**
   `PowerShell linter as HTTP API (PSScriptAnalyzer on Azure Functions)`
5. **Public** oder **Private:** deine Wahl
   - Public: Code sichtbar, URL + Function-Key bleiben geheim
   - Private: nur du siehst alles
6. **Add a README file:** haken setzen (initialer Commit noetig)
7. **Add .gitignore:** keinen auswaehlen (Claude Code erzeugt eigenen)
8. **License:** deine Wahl (bei public: MIT empfohlen, sonst leer)
9. **Create repository**

Notiere Clone-URL: `https://github.com/ChrisRudi/pslinter.git`

---

## Phase 2 — Azure-Ressourcen anlegen

**Ziel:** Resource Group + Function App (inkl. Storage + Application
Insights).

### 2.1 Resource Group anlegen

1. Portal-Suche: **Resource groups** -> **Create**
2. **Subscription:** deine gepruefte Subscription
3. **Resource group:** `pslinter-rg`
4. **Region:** `West Europe`
5. **Review + create** -> **Create**
6. Warte ~10 Sekunden bis die Ressource erscheint

### 2.2 Function App anlegen

1. Portal-Suche: **Function App** -> oben **Create** -> **Function App**
2. **Hosting option:** `Consumption` waehlen, **Select**
3. **Basics-Reiter** ausfuellen:
   - **Subscription:** deine
   - **Resource Group:** `pslinter-rg`
   - **Function App name:** `pslinter-api`
     - Falls rot markiert (Name vergeben): versuche
       `pslinter-api-cr`, `pslinter-api-rudi`, oder
       `pslinter-api-<zahl>`. **Finalen Namen notieren!**
   - **Runtime stack:** `PowerShell Core`
   - **Version:** `7.4` (oder hoechste verfuegbare 7.x)
   - **Region:** `West Europe`
   - **Operating System:** `Windows`
4. **Storage-Reiter:**
   - **Storage account:** akzeptiere den vorgeschlagenen Namen
     oder setze `pslinterstorage<zahl>`
   - Rest Defaults
5. **Networking-Reiter:** alles Default (public access)
6. **Monitoring-Reiter:**
   - **Enable Application Insights:** `Yes`
   - **Application Insights:** `Create new` -> Name
     `pslinter-api-insights`
   - **Region:** `West Europe`
7. **Deployment-Reiter:** **Continuous deployment:** `Disable`
   (wir machen das selbst in Phase 3)
8. **Tags-Reiter:** leer lassen
9. **Review + create** -> **Create**
10. Dauer: 2-4 Minuten. Status-Benachrichtigung oben rechts abwarten.

### 2.3 Function App pruefen

1. Nach erfolgreicher Anlage: **Go to resource**
2. Oben siehst du:
   - **Default domain:** `pslinter-api.azurewebsites.net`
   - **Status:** Running
3. Klicke auf die Default-Domain — generische Azure-Willkommensseite
   erscheint. Das ist korrekt.

**Notiere:**
- Function-App-Name: `___________________`
- Default-Domain: `https://___________________.azurewebsites.net`
- Resource Group: `pslinter-rg`

---

## Phase 3 — GitHub Actions einrichten

**Ziel:** Jeder Push auf `main` deployt automatisch zur Azure
Function App.

### 3.1 Publish Profile aus Azure holen

1. In der Function App: oben **Get publish profile** (Download-Button)
2. Datei wird heruntergeladen: `pslinter-api.PublishSettings`
3. Oeffne die Datei in einem Text-Editor
4. **Gesamten Inhalt kopieren** (langer XML-Block mit mehreren
   `<publishProfile>`-Eintraegen)

Behandle diese Datei wie ein Passwort: nicht committen, nicht teilen.

### 3.2 GitHub Secret setzen

1. Gehe zu `https://github.com/ChrisRudi/pslinter`
2. **Settings** -> links **Secrets and variables** -> **Actions**
3. **New repository secret**
4. **Name:** `AZURE_FUNCTIONAPP_PUBLISH_PROFILE`
5. **Secret:** XML-Inhalt aus 3.1 einfuegen
6. **Add secret**

### 3.3 Verifikation

Der eigentliche Workflow wird in Phase 4 durch Claude Code erzeugt.
Nach dem ersten Push (Phase 5) siehst du im Repo unter **Actions**
den Workflow-Lauf.

---

## Phase 4 — Code mit Claude Code generieren

**Ziel:** Alle Code-Dateien erstellen und committen.

### 4.1 Projekt in Claude Code oeffnen

1. Lokal: Repo klonen
   ```
   git clone https://github.com/ChrisRudi/pslinter.git
   cd pslinter
   ```
2. Claude Code starten im Repo-Verzeichnis

### 4.2 Prompt an Claude Code

Kopiere den folgenden Prompt 1:1 in Claude Code:

```
Erstelle das Repo "pslinter" gemaess folgender Spezifikation.

PROJEKT
PowerShell-Linter als HTTP-API auf Azure Functions
(PS 7.4, Consumption Plan, Windows). PSScriptAnalyzer als Engine.

ENDPOINT
POST /api/lint
Auth: Function Key (?code=xxx)
Request: Query-Params (IncludeRule, ExcludeRule, Severity, Settings -
alle optional, Komma-separiert bei Arrays) + Raw-Body als PS-Code
Response: JSON-Array von PSSA-DiagnosticRecords
(RuleName, Severity, Line, Column, Message, ScriptName)

FEHLERVERHALTEN
Syntax-Fehler im Input -> Issue im Array, HTTP 200.
Nur Runtime-Fehler (fehlende Module etc) -> HTTP 500.

LOGGING
Nur Metadaten (Timestamp, Dauer, IssueCount, TargetVersion).
NIE den Input-Code loggen.

DATEIEN
- lint/function.json (HTTP-Trigger, POST, authLevel function)
- lint/run.ps1 (Logik, Header mit Dateiname + Kurzdoku)
- host.json (PS 7.4, managed deps aktiv)
- requirements.psd1 (PSScriptAnalyzer gepinnt auf neueste 1.x)
- profile.ps1 (minimal)
- .funcignore
- .gitignore (Azure Functions)
- .github/workflows/deploy.yml
  (Push main -> Azure/functions-action@v1,
   Function-App-Name aus Env, Publish-Profile aus Secret
   AZURE_FUNCTIONAPP_PUBLISH_PROFILE)
- .github/workflows/update-pssa.yml
  (woechentlich Mo 06:00 UTC + workflow_dispatch,
   Find-Module PSScriptAnalyzer -> Version vergleichen mit
   requirements.psd1 -> bei Abweichung PR oeffnen)
- README.md (Kurzbeschreibung, Endpoint, Request/Response-Beispiele,
  curl + PowerShell, AI-Agent-Hinweis)

CODING-REGELN
- Windows-1252 fuer Code, UTF-8 fuer JSON/YAML/Web, keine Emojis
- Zeile 1: Dateiname als Kommentar
- Zeile 2ff: Kurzdoku-Header (Zweck, Inputs, Outputs, Deps)
- Nur notwendiger Code, kein Defensive-Coding
- Kein leerer Catch, keine bare catches
- Kommentare: Warum, nicht Was
- PowerShell-Ziel: 7.4 (Runtime), Code-Input kann 5.1 sein -
  Settings-Param regelt das im PSSA-Aufruf

DEPLOYMENT
Function-App-Name in deploy.yml: pslinter-api
(falls abweichend in Phase 2.2 gewaehlt: anpassen)
```

### 4.3 Commit und Push

```
git add .
git commit -m "initial: pslinter function + workflows"
git push origin main
```

GitHub Actions startet automatisch.

---

## Phase 5 — Erster Deploy + Test

### 5.1 Deploy-Lauf beobachten

1. Repo oeffnen: `https://github.com/ChrisRudi/pslinter/actions`
2. Neuester Workflow-Lauf "initial: pslinter function + workflows"
3. Status abwarten:
   - Build: ~30 Sek
   - Deploy zu Azure: 1-2 Min
4. Gruener Haken = erfolgreich

Fehler? Siehe Anhang B.

### 5.2 Function Key holen

1. Azure Portal -> Function App `pslinter-api`
2. Links **Functions** -> Function `lint` anklicken
3. Links **Function Keys**
4. **default**-Key kopieren

### 5.3 Test-Call (siehe Anhang A)

Wenn Test-Call erfolgreich: **Phase 5 abgeschlossen**. Service lebt.

---

## Phase 6 — Auto-Update PSScriptAnalyzer

**Ziel:** Wenn neue PSSA-Version in der PowerShell Gallery erscheint,
wird automatisch ein PR geoeffnet.

### 6.1 Mechanismus

Der Workflow `.github/workflows/update-pssa.yml` (in Phase 4 erstellt)
laeuft woechentlich Montag 06:00 UTC:

1. Aktuelle Version aus `requirements.psd1` parsen
2. Neueste Version via `Find-Module PSScriptAnalyzer` aus PSGallery
3. Bei Abweichung: `requirements.psd1` aktualisieren + PR oeffnen
4. Du reviewst + mergest den PR
5. Merge triggert Production-Deploy via `deploy.yml`

### 6.2 Manueller Trigger

Du kannst den Update-Check auch manuell ausloesen:

1. Repo -> **Actions** -> **update-pssa**
2. **Run workflow** -> **Run workflow**

### 6.3 Bemerkung zu Dependabot

Dependabot unterstuetzt keine PowerShell Gallery nativ. Deshalb der
eigene Cron-Workflow. Fuer GitHub-Action-Updates (z. B.
`actions/checkout`) kann optional zusaetzlich Dependabot aktiviert
werden — nicht Teil der ersten Iteration.

---

## Phase 7 — Budget-Alert

**Ziel:** Bei 1 EUR Kosten pro Monat bekommst du eine Mail.
(Automatischer Stopp ist in Azure komplex und wird v1 ausgeklammert.
Bei Schul-Account greift ohnehin das eingebaute Jahreslimit.)

### 7.1 Action Group anlegen

1. Portal-Suche: **Monitor** -> links **Alerts** -> oben
   **Action groups**
2. **Create**
3. **Basics:**
   - **Subscription:** deine
   - **Resource group:** `pslinter-rg`
   - **Action group name:** `pslinter-alert-group`
   - **Display name:** `pslinter` (max 12 Zeichen)
   - **Region:** `Global`
4. **Notifications-Reiter:**
   - **Notification type:** `Email/SMS message/Push/Voice`
   - **Name:** `admin-email`
   - Haken bei **Email** -> deine Mail-Adresse
   - **OK**
5. **Actions-Reiter:** leer lassen
6. **Review + create** -> **Create**

### 7.2 Budget anlegen

1. Portal-Suche: **Subscriptions** -> deine Subscription anklicken
2. Links **Budgets** -> oben **Add**
3. **Scope:** Resource Group `pslinter-rg` (oder Subscription)
4. **Create budget:**
   - **Name:** `pslinter-budget`
   - **Reset period:** `Monthly`
   - **Creation date:** heute
   - **Expiration date:** in 5 Jahren
   - **Amount:** `1` (EUR)
5. **Next**
6. **Alert conditions:**
   - Zeile 1: **Type:** Actual, **% of budget:** 80,
     **Action group:** `pslinter-alert-group`
   - Zeile 2: **Type:** Actual, **% of budget:** 100,
     **Action group:** `pslinter-alert-group`
   - **Alert recipients:** deine Mail
7. **Create**

### 7.3 Was bei Alert tun?

Wenn die Mail kommt:
1. Function App -> oben **Stop**
2. Application Insights -> **Failures** / **Performance** pruefen
3. Auf Missbrauch reagieren (Function Key neu generieren via
   **Function Keys** -> **Revoke** + **Create new**)

---

## Anhang A — Test-Calls

Nach erfolgreichem Deploy (Phase 5).

### A.1 Aus PowerShell

```powershell
$key  = "DEIN_FUNCTION_KEY"
$url  = "https://pslinter-api.azurewebsites.net/api/lint?code=$key"
$body = 'Get-ChildItem | % { $_.Name }'

Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "text/plain"
```

Erwartetes Ergebnis: JSON mit mindestens einem Issue fuer den
Alias `%`.

### A.2 Aus curl

```bash
curl -X POST "https://pslinter-api.azurewebsites.net/api/lint?code=DEIN_KEY" \
     -H "Content-Type: text/plain" \
     --data-binary 'Get-ChildItem | % { $_.Name }'
```

### A.3 Mit PSSA-Parametern

```powershell
$key  = "DEIN_FUNCTION_KEY"
$url  = "https://pslinter-api.azurewebsites.net/api/lint?code=$key&Severity=Warning,Error&ExcludeRule=PSAvoidUsingWriteHost"
$body = Get-Content .\mein-script.ps1 -Raw

Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "text/plain"
```

---

## Anhang B — Fehlerbehebung

### "Function app name is not available"
Name weltweit vergeben. Waehle anderen, z. B. `pslinter-api-cr`,
`pslinter-api-rudi`, `pslinter-api-<zahl>`. Finalen Namen in
`deploy.yml` eintragen.

### "Subscription is not allowed to create resources in this region"
Schul-Account-Einschraenkung. Probiere andere Region
(`germanywestcentral`) oder wechsle zu eigenem Free-Tier-Account.

### GitHub Actions schlaegt fehl mit "No credentials found"
Secret `AZURE_FUNCTIONAPP_PUBLISH_PROFILE` nicht gesetzt oder
falscher Name. Phase 3.2 wiederholen.

### GitHub Actions schlaegt fehl mit Bitness-Fehler
Function App -> **Configuration** -> **General settings** ->
**Platform** auf `64-bit` setzen.

### Test-Call liefert HTTP 401
Function Key fehlt oder falsch. Key aus Phase 5.2 neu kopieren.

### Test-Call liefert HTTP 500
Application Insights im Portal -> **Failures** -> Fehler-Details
pruefen.

### Function laeuft, aber PSScriptAnalyzer nicht gefunden
`requirements.psd1` nicht committet oder falsch. In Function App ->
**Advanced Tools (Kudu)** -> **Debug console** -> Pfad
`D:\home\data\ManagedDependencies\` pruefen.

### Cold Start dauert sehr lange
Erster Request nach Idle: 10-30 Sek (Modul wird geladen). Danach
schnell. Fuer Claude-Code-Workflow akzeptabel.
