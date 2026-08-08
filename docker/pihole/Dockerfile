# Rebuild bump 2026-05-19: post-Harbor-wipe, repopulate :<semver> tag.
FROM pihole/pihole:2026.07.2@sha256:f7d1be836e3bc608b56d82fc9904f5a831cdfbc0dc9c6d58f94e4c985c70038b

COPY install.sh docker.sh pihole-updatelists.* /tmp/pihole-updatelists/

RUN apk add --no-cache php php-pdo_sqlite php-curl php-openssl php-intl php-pcntl php-posix && \
    bash /tmp/pihole-updatelists/install.sh docker && \
    rm -fr /tmp/pihole-updatelists
#
