# Claude Code Integration

Das Repo bringt einen PostToolUse-Hook mit, der `.ps1` / `.psm1` / `.psd1`
nach jedem Write/Edit an den pslinter-Endpoint schickt und Issues in den
Transcript einspielt.

- **Konfiguration:** `.claude/settings.json`
- **Script:** `.claude/pslint-hook.sh`

## Ablauf

1. Claude schreibt eine PS-Datei via Write/Edit.
2. Hook liest den Dateipfad aus dem Tool-Payload.
3. `curl POST` an `https://pslinter-api.azurewebsites.net/api/lint` mit dem
   Datei-Inhalt als `text/plain`.
4. Response ist JSON-Array:
   - Leer -> Hook Exit 0, nichts passiert.
   - Mit Issues -> Hook Exit 2, Issue-Liste geht als `<system-reminder>` an
     Claude zurueck. Claude sieht die Issues und fixt.
   - HTTP 429 (Rate Limit) -> Hook meldet den Fehler an stderr, Exit 0
     (unterbricht die Session nicht).

## Voraussetzungen im Container

- `curl`, `jq`
- Netzwerkzugang zu `pslinter-api.azurewebsites.net`

## Kompatibilitaet

| Umgebung               | Hook laeuft? | Anmerkung                                |
|------------------------|--------------|------------------------------------------|
| Claude Code CLI lokal  | ja           | Nutzt deinen regulaeren Internetzugang.  |
| Claude Code CLI in CI  | ja           | Sofern Egress nach Azure erlaubt ist.    |
| Claude Code Web        | nein*        | Egress-Gateway blockiert den Host (403). |

*Claude Code Web (`claude.ai/code`) laeuft in einer Sandbox mit einem
uebergeordneten Anthropic-Egress-Gateway. Dieser Gateway hat eine eigene
Host-Allowlist, die `pslinter-api.azurewebsites.net` nicht enthaelt. Die
Einstellung `sandbox.allowedDomains` in `.claude/settings.json` steuert nur
den Claude-Code-eigenen Sandbox-Filter, nicht den Gateway. In Web-Sessions
liefert die API deshalb HTTP 403 "Host not in allowlist". Der Hook faengt
das ab und macht Exit 0 -> keine Issue-Meldung, aber auch kein Abbruch.

## TLS in Sandboxen

Claude Code Web macht TLS-Inspection mit einer eigenen CA, die im Container
als `/usr/local/share/ca-certificates/egress-gateway-ca-production.crt`
installiert und ueber `SSL_CERT_FILE` / `REQUESTS_CA_BUNDLE` / `NODE_EXTRA_CA_CERTS`
referenziert ist. Der Hook detektiert Sandbox-Umgebungen ueber `$IS_SANDBOX`
und uebergibt automatisch das passende CA-Bundle an `curl` (Fallback: `-k`).
Relevant ist das nur, falls der Egress-Gateway den Host freigibt.

## Troubleshooting

**Hook feuert nicht nach Write.** Session nach Aenderungen an
`.claude/settings.json` neu starten - Hooks werden nur beim Session-Start
geladen.

**`API-Call fehlgeschlagen: ... 403 Host not in allowlist` an stderr.**
Du bist in einer Sandbox ohne Egress-Freigabe (typisch Claude Code Web).
Lokal ausfuehren oder Host auf der Org-Egress-Allowlist freischalten lassen.

**`HTTP 429 Tageslimit ueberschritten`.** 200 Requests pro UTC-Tag pro
Worker sind verbraucht. Morgen weitermachen oder eigene Function-App
deployen (siehe `pslinter-setup.md`).
