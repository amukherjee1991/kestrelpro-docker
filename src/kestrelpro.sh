#!/bin/bash
# KestrelPro: the review engine, supervised next to pihole-FTL. Sourced by start.sh.
#
# DNS never depends on anything here. FTL starts first and never waits for the engine;
# if the engine crashes it is restarted with backoff while FTL carries on, and the OOM
# killer is told to pick the engine before FTL. KESTREL_ENGINE=off gives DNS only.

KESTREL_SUPERVISOR_PID=""

# FTL's first plain-HTTP listener, e.g. "80o,443os,[::]:80o,[::]:443os" -> http://127.0.0.1:80
ftl_http_url() {
    local ports token port=""
    ports=$(getFTLConfigValue webserver.port 2>/dev/null || true)
    IFS=',' read -ra tokens <<< "${ports}"
    for token in "${tokens[@]}"; do
        token="${token##*:}"
        [[ "${token}" == *s* ]] && continue
        port=$(grep -oE '^[0-9]+' <<< "${token}" || true)
        [ -n "${port}" ] && break
    done
    echo "http://127.0.0.1:${port:-80}"
}

# Tell the admin UI where the engine is, and let the browser reach it. Runs before FTL starts.
#   KESTREL_ENGINE_URL   engine API on the admin UI's own origin, e.g. /admin/api/kestrel behind a
#                        reverse proxy. Unset: the browser calls the engine on KESTREL_ENGINE_PORT.
#   KESTREL_ENGINE_PORT  the engine's published port (default 8090).
prepare_kestrel_ui() {
    local url="${KESTREL_ENGINE_URL:-}" port="${KESTREL_ENGINE_PORT:-8090}" raw headers new
    if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
        echo "  [!] KESTREL_ENGINE_PORT must be a number, using 8090"
        port=8090
    fi
    jq -n --arg url "${url}" --argjson port "${port}" \
        '"/* Written by the container at start-up (kestrelpro.sh). */\nglobalThis.kestrelConfig = \({engineUrl: $url, enginePort: $port});"' -r \
        > /var/www/html/admin/scripts/js/kestrel/config.js

    # Cross-port: FTL's default Content-Security-Policy only allows connect-src 'self', which
    # blocks the pages' calls to the engine. Add the engine's port to connect-src.
    [ "${KESTREL_ENGINE:-on}" = "off" ] && return 0
    [ -n "${url}" ] && return 0
    # FTL prints the array unquoted: "[ Name: value, Name: value ]". Split it, and give up if
    # any element isn't a "Name: value" header (a header containing ", " would be split wrongly).
    raw=$(getFTLConfigValue webserver.headers 2>/dev/null) || return 0
    headers=$(jq -Rc 'ltrimstr("[ ") | rtrimstr(" ]") | split(", ")
                      | if all(test("^[A-Za-z0-9-]+: ")) then . else error("unparsed") end' <<< "${raw}" 2>/dev/null) || {
        echo "  [!] KestrelPro: couldn't read webserver.headers; add http://*:${port} to connect-src yourself"
        return 0
    }
    new=$(jq -c --arg needle "connect-src 'self'" --arg src "http://*:${port}" \
        'map(if startswith("Content-Security-Policy:") and (contains($src) | not)
             then sub($needle; $needle + " " + $src) else . end)' <<< "${headers}" 2>/dev/null) || return 0
    if [ -n "${new}" ] && [ "${headers}" != "${new}" ]; then
        if setFTLConfigValue webserver.headers "${new}"; then
            echo "  [i] KestrelPro: allowed the admin UI to reach the engine on port ${port} (Content-Security-Policy)"
        else
            echo "  [!] KestrelPro: couldn't update webserver.headers; set KESTREL_ENGINE_URL or allow port ${port} in connect-src"
        fi
    fi
}

start_kestrel_engine() {
    if [ "${KESTREL_ENGINE:-on}" = "off" ]; then
        echo "  [i] KestrelPro engine is off (KESTREL_ENGINE=off): DNS and admin only"
        return 0
    fi
    install -d -o kestrel -g pihole -m 0750 /etc/kestrel
    # A database copied over from the old add-on is usually owned by root.
    chown -R kestrel:pihole /etc/kestrel
    FTL_URL="${FTL_URL:-$(ftl_http_url)}"
    export FTL_URL
    echo "  [i] Starting KestrelPro engine (FTL API at ${FTL_URL})"
    supervise_kestrel_engine &
    KESTREL_SUPERVISOR_PID=$!
}

supervise_kestrel_engine() {
    local delay=2 started code engine_pid=""
    trap '[ -n "${engine_pid}" ] && kill -TERM "${engine_pid}" 2>/dev/null; wait "${engine_pid}" 2>/dev/null; exit 0' TERM
    until curl -s -o /dev/null --max-time 2 "${FTL_URL}/api/auth"; do
        sleep 2 & wait $!
    done
    while true; do
        started=$(date +%s)
        (
            cd /opt/kestrel-engine || exit 1
            printf 1000 > /proc/self/oom_score_adj
            exec nice -n 10 su-exec kestrel:pihole python3 -m kestrel_engine serve
        ) &
        engine_pid=$!
        wait "${engine_pid}"
        code=$?
        if [ $(( $(date +%s) - started )) -gt 60 ]; then
            delay=2
        else
            delay=$(( delay * 2 > 60 ? 60 : delay * 2 ))
        fi
        echo "  [!] KestrelPro engine exited with status ${code}; restarting in ${delay}s (DNS is unaffected)"
        sleep "${delay}" & wait $!
    done
}

stop_kestrel_engine() {
    [ -n "${KESTREL_SUPERVISOR_PID}" ] || return 0
    echo "  [i] Stopping KestrelPro engine"
    kill -TERM "${KESTREL_SUPERVISOR_PID}" 2>/dev/null || true
    wait "${KESTREL_SUPERVISOR_PID}" 2>/dev/null || true
    KESTREL_SUPERVISOR_PID=""
}
