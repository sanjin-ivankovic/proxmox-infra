FROM pihole/pihole:2026.11.0@sha256:66c798d79a95c2691f280329c3611dba1746117c61c9f331907ca35a06a52778

# pihole-updatelists at a pinned upstream commit. The project tags no releases,
# so Renovate tracks master by commit (renovate.json); the clone is checked
# against the full hash, which content-addresses the source.
# Renovate: the jacklul/pihole-updatelists rule in renovate.json.
ARG PIHOLE_UPDATELISTS_REF=30a93dd2d1c6611e15e3a6a916934c0834dae017

RUN apk add --no-cache php php-pdo_sqlite php-curl php-openssl php-intl php-pcntl php-posix

# install.sh detects the Pi-hole version with `pihole version`, which since
# 2026.10.0 writes a temp file in /etc/pihole as the pihole user; the build-time
# /etc/pihole is not writable by it. Upstream's own Dockerfile does the same.
RUN chown -R pihole:pihole /etc/pihole/

# The repo's docker.sh (the container hook) replaces upstream's before the
# installer copies it to /usr/bin/pihole-updatelists.sh.
COPY docker.sh /tmp/docker.sh

RUN apk add --no-cache --virtual .fetch git && \
    git init -q /tmp/pihole-updatelists && \
    cd /tmp/pihole-updatelists && \
    git fetch -q --depth 1 https://github.com/jacklul/pihole-updatelists "${PIHOLE_UPDATELISTS_REF}" && \
    git checkout -q FETCH_HEAD && \
    test "$(git rev-parse HEAD)" = "${PIHOLE_UPDATELISTS_REF}" && \
    cp /tmp/docker.sh docker.sh && \
    bash install.sh docker && \
    cd / && rm -fr /tmp/pihole-updatelists /tmp/docker.sh && \
    apk del .fetch

# Fail the build, not the node, when a Pi-hole bump breaks the updater.
RUN php /usr/local/sbin/pihole-updatelists --help >/dev/null && \
    grep -q 'UPDATELISTS_ON_START' /usr/bin/pihole-updatelists.sh && \
    grep -q 'pihole-updatelists' /crontab.txt
