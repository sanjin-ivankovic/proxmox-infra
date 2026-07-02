# Rebuild bump 2026-05-19: post-Harbor-wipe, repopulate :<semver> tag.
FROM pihole/pihole:2026.06.0@sha256:8ea95136e7c8c15b42d88eadf1a3875421aa1be30ad39e50f661188cc986fb27

COPY install.sh docker.sh pihole-updatelists.* /tmp/pihole-updatelists/

RUN apk add --no-cache php php-pdo_sqlite php-curl php-openssl php-intl php-pcntl php-posix && \
    bash /tmp/pihole-updatelists/install.sh docker && \
    rm -fr /tmp/pihole-updatelists
#
