FROM pihole/pihole:2026.02.0@sha256:ee348529cea9601df86ad94d62a39cad26117e1eac9e82d8876aa0ec7fe1ba27

COPY install.sh docker.sh pihole-updatelists.* /tmp/pihole-updatelists/

RUN apk add --no-cache php php-pdo_sqlite php-curl php-openssl php-intl php-pcntl php-posix && \
    bash /tmp/pihole-updatelists/install.sh docker && \
    rm -fr /tmp/pihole-updatelists
#
