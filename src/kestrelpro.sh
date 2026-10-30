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
