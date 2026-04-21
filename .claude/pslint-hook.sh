#!/usr/bin/env bash
# pslint-hook.sh - PostToolUse-Hook fuer .ps1/.psm1/.psd1. Schickt
# Datei an die oeffentliche pslinter-API, bei Issues Exit 2 damit
# Claude sie sieht und fixen kann.
# Deps: curl, jq. Kein Key noetig (authLevel=anonymous). Rate-Limit
# serverseitig: 200 Requests pro UTC-Tag.

set -u

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // .tool_response.file_path // empty')"

case "$file" in
    *.ps1|*.psm1|*.psd1) ;;
    *) exit 0 ;;
esac

[ -f "$file" ] || exit 0

url='https://pslinter-api.azurewebsites.net/api/lint'
# In der Claude-Code-Web-Sandbox macht der Egress-Proxy TLS-Inspection
# mit einer eigenen CA. Wenn ein Trust-Bundle per Env exportiert wird,
# nutzen wir das; sonst fallen wir in der Sandbox auf -k zurueck, da der
# MITM-Proxy ohnehin Anthropic-intern ist.
tls_flags=()
if [ "${IS_SANDBOX:-}" = "yes" ]; then
    for var in SSL_CERT_FILE CURL_CA_BUNDLE REQUESTS_CA_BUNDLE NODE_EXTRA_CA_CERTS; do
        val="$(eval "printf '%s' \"\${$var:-}\"")"
        if [ -n "$val" ] && [ -f "$val" ]; then
            tls_flags=(--cacert "$val")
            break
        fi
    done
    [ "${#tls_flags[@]}" -eq 0 ] && tls_flags=(-k)
fi

response="$(curl -sS "${tls_flags[@]}" --fail-with-body --max-time 30 -X POST "$url" \
    -H 'Content-Type: text/plain' \
    --data-binary "@$file" 2>&1)" || {
    printf 'pslint-hook: API-Call fehlgeschlagen: %s\n' "$response" >&2
    exit 0
}

count="$(printf '%s' "$response" | jq 'if type == "array" then length else -1 end' 2>/dev/null || echo -1)"
if [ "$count" = "-1" ]; then
    printf 'pslint-hook: ungueltige API-Antwort: %s\n' "$response" >&2
    exit 0
fi
if [ "$count" = "0" ]; then
    exit 0
fi

printf 'pslinter hat %s Issue(s) in %s gefunden:\n' "$count" "$file" >&2
printf '%s' "$response" | jq -r '
    .[] |
    "  [\(.Severity)] \(.RuleName) @ Zeile \(.Line):\(.Column)\n      \(.Message)"
' >&2
exit 2
