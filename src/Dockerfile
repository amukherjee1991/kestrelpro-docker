# syntax=docker/dockerfile:1
# kestrelpro:begin pinned FTL + local fork contexts
# FTL_SOURCE=pinned downloads one FTL release and checks its SHA-256 (see pinned-ftl-install).
# The web fork and the engine come from named build contexts:
#   docker buildx build src --build-context kestrelpro-web=../web --build-context kestrelpro-engine=../engine
ARG FTL_SOURCE=pinned
# kestrelpro:end
# Pull Stable images
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS base

ARG TARGETPLATFORM
ARG WEB_BRANCH="development"
ARG CORE_BRANCH="development"
ARG FTL_BRANCH="development"
ARG PIHOLE_DOCKER_TAG="dev-localbuild"
ARG PADD_BRANCH="development"

ARG CORE_FORK="pi-hole"
ARG WEB_FORK="pi-hole"
ARG PADD_FORK="pi-hole"

ARG PIHOLE_UID=1000
ARG PIHOLE_GID=1000

ENV DNSMASQ_USER=pihole
ENV FTL_CMD=no-daemon

RUN apk add --no-cache \
    bash \
    bash-completion \
    bind-tools \
    binutils \
    coreutils \
    curl \
    git \
    # Install grep to avoid issues in pihole -w/b with the default busybox grep
    grep \
    iproute2 \
    jq \
    libcap \
    logrotate \
    ncurses \
    procps-ng \
    psmisc \
    shadow \
    sudo \
    tzdata \
    unzip \
    wget

ADD --link https://ftl.pi-hole.net/macvendor.db /macvendor.db

# Add PADD to the container, too.
ADD --link --chmod=0755 https://raw.githubusercontent.com/${PADD_FORK}/PADD/${PADD_BRANCH}/padd.sh /usr/local/bin/padd

# download a the main repos from github
# if the branch is master we clone the latest tag as sometimes the master branch contains meta changes that have not been tagged
# (we need to create a new "master" branch to avoid the "detached HEAD" state for the version check to work correctly)

RUN clone_repo() { \
        FORK="$1"; \
        REPO="$2"; \
        BRANCH="$3"; \
        DEST="$4"; \
        CLONE_BRANCH="$BRANCH"; \
        if [ "$BRANCH" = "master" ]; then \
            CLONE_BRANCH=$(curl -fsSL "https://api.github.com/repos/${FORK}/${REPO}/releases/latest" | jq -r .tag_name); \
            if [ -z "$CLONE_BRANCH" ] || [ "$CLONE_BRANCH" = "null" ]; then \
                echo "Failed to resolve latest release tag for ${FORK}/${REPO}"; \
                exit 1; \
            fi; \
        fi; \
        git clone --branch "$CLONE_BRANCH" --single-branch --depth 1 "https://github.com/${FORK}/${REPO}.git" "$DEST"; \
        cd "$DEST"; \
        # kestrelpro: also name the branch when a tag was cloned directly (detached HEAD)
        if [ "$BRANCH" = "master" ] || ! git symbolic-ref -q HEAD >/dev/null; then git checkout -b master; fi; \
    }; \
    clone_repo "${CORE_FORK}" "pi-hole" "${CORE_BRANCH}" "/etc/.pihole"

# kestrelpro:begin web fork from the kestrelpro-web build context instead of a GitHub clone
COPY --from=kestrelpro-web . /var/www/html/admin
# kestrelpro:end


RUN cd /etc/.pihole && \
    install -Dm755 -d /opt/pihole && \
    install -Dm755 -t /opt/pihole gravity.sh && \
    install -Dm755 -t /opt/pihole ./advanced/Scripts/*.sh && \
    install -Dm755 -t /opt/pihole ./advanced/Scripts/COL_TABLE && \
    install -Dm755 -d /etc/pihole && \
    install -Dm755 -d /var/log/pihole && \
    install -Dm755 -d /var/lib/logrotate && \
    install -Dm755 -t /usr/local/bin pihole && \
    install -Dm644 ./advanced/bash-completion/pihole.bash /etc/bash_completion.d/pihole && \
    install -Dm644 ./advanced/bash-completion/pihole-ftl.bash /etc/bash_completion.d/pihole-FTL && \
    install -T -m 0755 ./advanced/Templates/pihole-FTL-prestart.sh /opt/pihole/pihole-FTL-prestart.sh && \
    install -T -m 0755 ./advanced/Templates/pihole-FTL-poststop.sh /opt/pihole/pihole-FTL-poststop.sh && \
    install -T -m 644 ./advanced/Templates/logrotate /etc/logrotate.d/pihole && \
    addgroup -S pihole -g ${PIHOLE_GID} && adduser -S pihole -G pihole -u ${PIHOLE_UID}

# updatecheck.sh hands over to the unprivileged "pihole" user when started as
# root (GHSA-xch2-4qxw-g5vj). git refuses to read the root-owned repos above as
# another user ("dubious ownership"), which would make `pihole -v` show N/A for
# the local Core/Web versions, so trust them system-wide. The image is built
# as root and the paths are fixed, so no validation of the paths is needed here.
RUN git config --system --add safe.directory /etc/.pihole && \
    git config --system --add safe.directory /var/www/html/admin && \
    chmod a+r /etc/gitconfig

COPY --chmod=0755 bash_functions.sh /usr/bin/bash_functions.sh
COPY --chmod=0755 prefix-time.sh /usr/bin/prefix-time.sh
COPY --chmod=0755 start.sh /usr/bin/start.sh
COPY crontab.txt /crontab.txt

# kestrelpro:begin review engine (runs next to FTL, supervised by kestrelpro.sh)
ARG KESTREL_UID=1001
RUN apk add --no-cache python3 py3-flask py3-requests py3-waitress su-exec && \
    adduser -S -D -H -h /etc/kestrel -G pihole -u ${KESTREL_UID} kestrel
COPY --from=kestrelpro-engine kestrel_engine /opt/kestrel-engine/kestrel_engine
COPY --from=kestrelpro-engine static /opt/kestrel-engine/static
COPY --chmod=0755 kestrelpro.sh /usr/bin/kestrelpro.sh
ENV KESTREL_ENGINE=on \
    DB_PATH=/etc/kestrel/kestrel.db \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
EXPOSE 8090
# kestrelpro:end

# For nightly images, we install gdb and screen for ease of debugging (this is
# not included in the default image to keep it small), and also prepare the
# system for a core dump. Furthermore, we already add the required signal
# instructions to the gdb config file
RUN if [ "${PIHOLE_DOCKER_TAG}" = "nightly" ]; then \
        apk add --no-cache gdb screen && \
        echo "ulimit -c unlimited" >> /etc/profile && \
        echo "handle SIGHUP nostop SIGPIPE nostop SIGTERM nostop SIG32 nostop SIG33 nostop SIG34 nostop SIG35 nostop SIG36 nostop SIG37 nostop SIG38 nostop SIG39 nostop SIG40 nostop SIG41 nostop" > /root/.gdbinit; \
    fi; \
    echo "${PIHOLE_DOCKER_TAG}" > /pihole.docker.tag

EXPOSE 53 53/udp
EXPOSE 67/udp
EXPOSE 80
EXPOSE 123/udp
EXPOSE 443

## Buildkit can do some fancy stuff and we can use it to either download FTL from ftl.pi-hole.net or use a local copy

FROM base AS remote-ftl-install
# Default stage if FTL_SOURCE is not explicitly set to "local"
# Download the latest version of pihole-FTL for the correct architecture
RUN if   [ "$TARGETPLATFORM" = "linux/amd64" ];    then FTLARCH=amd64; \
    elif [ "$TARGETPLATFORM" = "linux/386" ];      then FTLARCH=386; \
    elif [ "$TARGETPLATFORM" = "linux/arm/v6" ];   then FTLARCH=armv6; \
    elif [ "$TARGETPLATFORM" = "linux/arm/v7" ];   then FTLARCH=armv7; \
    # Note for the future, "linux/arm6/v8" is not a valid value for TARGETPLATFORM, despite the CI platform name being that.
    elif [ "$TARGETPLATFORM" = "linux/arm64" ];    then FTLARCH=arm64; \
    elif [ "$TARGETPLATFORM" = "linux/riscv64" ];  then FTLARCH=riscv64; \
    else FTLARCH=amd64; fi \
    && echo "Arch: ${TARGETPLATFORM}, FTLARCH: ${FTLARCH}" \
    && if [ "${FTL_BRANCH}" = "master" ]; then URL="https://github.com/pi-hole/ftl/releases/latest/download"; else URL="https://ftl.pi-hole.net/${FTL_BRANCH}"; fi \
    && curl -fsSL "${URL}/pihole-FTL-${FTLARCH}" -o /usr/bin/pihole-FTL \
    && chmod +x /usr/bin/pihole-FTL \
    && readelf -h /usr/bin/pihole-FTL || (echo "Error with downloaded FTL binary" && exit 1) \
    && /usr/bin/pihole-FTL  -vv

FROM base AS local-ftl-install
# pihole-FTL must be built from source and copied to the src directory first!
COPY --chmod=0755 pihole-FTL /usr/bin/pihole-FTL
RUN  readelf -h /usr/bin/pihole-FTL || (echo "Error with local FTL binary" && exit 1)

# kestrelpro:begin pinned FTL: one release, checked against a SHA-256 recorded here
FROM base AS pinned-ftl-install
ARG TARGETPLATFORM
ARG FTL_VERSION=v6.8
ARG FTL_SHA256_AMD64=1f511e7053a5ddfae1db1f439ebb986dd8025bf7223e1f70fb8087d9c0fd2b0e
RUN if [ -n "$TARGETPLATFORM" ] && [ "$TARGETPLATFORM" != "linux/amd64" ]; then \
        echo "FTL_SOURCE=pinned has a checksum for linux/amd64 only (got $TARGETPLATFORM)"; exit 1; \
    fi \
    && curl -fsSL "https://github.com/pi-hole/FTL/releases/download/${FTL_VERSION}/pihole-FTL-amd64" -o /usr/bin/pihole-FTL \
    && echo "${FTL_SHA256_AMD64}  /usr/bin/pihole-FTL" | sha256sum -c - \
    && chmod +x /usr/bin/pihole-FTL \
    && readelf -h /usr/bin/pihole-FTL >/dev/null \
    && /usr/bin/pihole-FTL -vv
# kestrelpro:end

# Use the appropriate FTL Install stage based on the FTL_SOURCE build-arg
FROM ${FTL_SOURCE}-ftl-install AS final

HEALTHCHECK CMD dig -p $(pihole-FTL --config dns.port) +short +norecurse +retry=0 @127.0.0.1 pi.hole || exit 1

ENTRYPOINT ["start.sh"]
