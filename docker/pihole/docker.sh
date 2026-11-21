#!/bin/bash

# Respect PH_VERBOSE environment variable
if [ "${PH_VERBOSE:-0}" -gt 0 ]; then
    set -x
    SCRIPT_ARGS="--verbose --debug"
fi

case $1 in
    "config")
        # Create the config file if it doesn't exist
        if [ ! -f /etc/pihole-updatelists/pihole-updatelists.conf ] && [ -f /etc/pihole-updatelists.conf ]; then
            cp /etc/pihole-updatelists.conf /etc/pihole-updatelists/pihole-updatelists.conf
            echo "  [i] Created /etc/pihole-updatelists/pihole-updatelists.conf"
        fi

        # A config bind-mounted read-only (services/pihole/) is left as is.
        for file in /etc/pihole-updatelists/*; do
            [ -w "$file" ] || continue
            chown pihole:pihole "$file"
            chmod 644 "$file"
        done
    ;;
    "cron")
        # Check if the user provided a custom crontab string
        if [ -n "$CRONTAB_STRING" ]; then
            echo "  [i] Changing pihole-updatelists schedule to: $CRONTAB_STRING"
        else # Otherwise, use the default one
            CRONTAB_STRING="$(sed -n '/pihole updateGravity/s/#\(.*\) PATH=.*/\1/p' /crontab.txt)"
        fi

        sed "/pihole-updatelists/ s|^.*PATH=|$CRONTAB_STRING PATH=|" -i /crontab.txt

        # A restart only re-reads changed list files at the next cron run. With
        # UPDATELISTS_ON_START=true, apply them once FTL answers DNS (start.sh
        # finishes its gravity checks before FTL starts; `pihole status`
        # succeeds earlier); FTL keeps serving the old gravity meanwhile. A fresh volume (no gravity.db yet)
        # already runs updatelists while building gravity, so skip it there.
        if [ "${UPDATELISTS_ON_START:-false}" = "true" ] && [ -f /etc/pihole/gravity.db ]; then
            echo "  [i] pihole-updatelists will run once FTL is up (UPDATELISTS_ON_START)"
            (
                for _ in $(seq 1 60); do
                    dig +short +time=1 +tries=1 @127.0.0.1 pi.hole >/dev/null 2>&1 && break
                    sleep 5
                done
                /usr/bin/pihole-updatelists.sh run
            ) >/proc/1/fd/1 2>&1 &
        fi
    ;;
    "run")
        shift # Skip 'run' argument
        # shellcheck disable=SC2086,SC2068
        /usr/bin/php /usr/local/sbin/pihole-updatelists --config=/etc/pihole-updatelists/pihole-updatelists.conf --env $SCRIPT_ARGS $@
        rc=$?

        # pihole-updatelists disables entries that left its sources instead
        # of deleting them. With REQUIRE_COMMENT=false the list files in Git
        # own every entry, so a disabled one is dead weight: delete it. A
        # disabled list contributes nothing to gravity, so no rebuild.
        if [ "$rc" -eq 0 ]; then
            pihole-FTL sqlite3 /etc/pihole/gravity.db \
                "DELETE FROM adlist WHERE enabled = 0; DELETE FROM domainlist WHERE enabled = 0; SELECT '  [i] Pruned ' || total_changes() || ' disabled list/domain entries';" \
                && pihole reloadlists >/dev/null
        fi
        exit "$rc"
    ;;
    *)
        echo "Usage: $0 run [ARGS]"
        exit 1
    ;;
esac
