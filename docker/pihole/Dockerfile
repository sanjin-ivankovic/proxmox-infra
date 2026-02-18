FROM pihole/pihole:2025.11.1@sha256:91dc91ddd413bf461c283204558f8f21839851e9824799075a7ceff7c77eea40

COPY install.sh docker.sh pihole-updatelists.* /tmp/pihole-updatelists/

RUN apk add --no-cache php php-pdo_sqlite php-curl php-openssl php-intl php-pcntl php-posix && \
    bash /tmp/pihole-updatelists/install.sh docker && \
    rm -fr /tmp/pihole-updatelists
#
