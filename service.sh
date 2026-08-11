#!/system/bin/sh
MODDIR=${0%/*}
APEX_CERT_DIR=/apex/com.android.conscrypt/cacerts
APEX_CERT_DIR_2=/apex/com.android.conscrypt@*/cacerts
SYS_CERT_DIR=/system/etc/security/cacerts
MODULE_CERT_DIR=$MODDIR$SYS_CERT_DIR
EXTERNAL_CERT_DIR=/data/adb/root-ca-injector/certs
LEGACY_USER_CERT_DIR=/data/misc/keychain/cacerts-added
LIVE_CERT_DIR=

log() {
    echo "$(date '+%m-%d %H:%M:%S ')" "$@" >> "$MODDIR/log.txt"
}

is_certificate_filename() {
    case "$1" in
        ????????.[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}

copy_certificate() {
    source_cert="$1"
    destination_dir="$2"
    cert_name=${source_cert##*/}
    destination_cert="$destination_dir/$cert_name"

    [ -f "$source_cert" ] || return 0
    if ! is_certificate_filename "$cert_name"; then
        log "Ignoring CA with invalid filename: $cert_name"
        return 1
    fi

    if [ ! -e "$destination_cert" ]; then
        cp -f "$source_cert" "$destination_cert"
        return
    fi

    cmp -s "$source_cert" "$destination_cert" 2>/dev/null && return
    cert_hash=${cert_name%%.*}
    cert_index=0
    while [ -e "$destination_dir/$cert_hash.$cert_index" ]; do
        cmp -s "$source_cert" "$destination_dir/$cert_hash.$cert_index" 2>/dev/null && return
        cert_index=$((cert_index + 1))
    done
    cp -f "$source_cert" "$destination_dir/$cert_hash.$cert_index"
}

copy_certificates() {
    source_dir="$1"
    destination_dir="$2"

    [ -d "$source_dir" ] || return 0
    for cert in "$source_dir"/*; do
        [ -f "$cert" ] || continue
        copy_certificate "$cert" "$destination_dir"
    done
}

fix_user_store_permissions() {
    user_cert_dir="$1"
    user_owner=$(stat -c '%u:%g' "$user_cert_dir" 2>/dev/null)
    [ -n "$user_owner" ] && chown "$user_owner" "$user_cert_dir"/* 2>/dev/null
    chmod 644 "$user_cert_dir"/* 2>/dev/null
    restorecon -RF "$user_cert_dir" 2>/dev/null || true
}

install_external_certificates_into_user_store() {
    [ -d "$EXTERNAL_CERT_DIR" ] || return 0
    for user_cert_dir in "$LEGACY_USER_CERT_DIR" /data/misc/user/*/cacerts-added; do
        [ -d "$user_cert_dir" ] || continue
        copy_certificates "$EXTERNAL_CERT_DIR" "$user_cert_dir"
        fix_user_store_permissions "$user_cert_dir"
    done
}

fix_system_store_permissions() {
    certificate_dir="$1"
    chown root:root "$certificate_dir"/* 2>/dev/null || true
    chmod 644 "$certificate_dir"/* 2>/dev/null || true
    chcon u:object_r:system_security_cacerts_file:s0 "$certificate_dir"/* 2>/dev/null || true
    chmod 755 "$certificate_dir" 2>/dev/null || true
    chcon u:object_r:system_security_cacerts_file:s0 "$certificate_dir" 2>/dev/null || true
}

sync_external_certificates() {
    install_external_certificates_into_user_store
    copy_certificates "$EXTERNAL_CERT_DIR" "$MODULE_CERT_DIR"
    if [ -n "$LIVE_CERT_DIR" ]; then
        copy_certificates "$EXTERNAL_CERT_DIR" "$LIVE_CERT_DIR"
        fix_system_store_permissions "$LIVE_CERT_DIR"
    fi
}

external_certificate_state() {
    for cert in "$EXTERNAL_CERT_DIR"/*; do
        [ -f "$cert" ] || continue
        stat -c '%n:%s:%Y' "$cert" 2>/dev/null || ls -ln "$cert" 2>/dev/null
    done
}

monitor_external_certificates() {
    (
        previous_state=$(external_certificate_state)
        while true; do
            current_state=$(external_certificate_state)
            if [ "$current_state" != "$previous_state" ]; then
                log "External CA inbox changed; installing user and system copies"
                if sync_external_certificates; then
                    previous_state=$current_state
                    log "External CAs installed"
                else
                    log "External CA install failed; retrying"
                fi
            fi
            sleep 2
        done
    ) &
}

has_mount() {
    pid="$1"
    apex_dir="$2"
    [ -z "$apex_dir" ] && apex_dir="$APEX_CERT_DIR"
    grep -q " $apex_dir " "/proc/$pid/mountinfo" 2>/dev/null
}

get_apex_cert_dir() {
    # Check for Android 17+ new apex paths.
    if [ -d "$APEX_CERT_DIR" ]; then
        echo "$APEX_CERT_DIR"
    elif ls $APEX_CERT_DIR_2 >/dev/null 2>&1; then
        # Handle versioned APEX paths.
        ls -d $APEX_CERT_DIR_2 2>/dev/null | head -1
    else
        echo ""
    fi
}

inject_into_pid() {
    pid="$1"
    target_dir="$2"
    [ -z "$target_dir" ] && target_dir="$APEX_CERT_DIR"

    /system/bin/nsenter --mount="/proc/$pid/ns/mnt" -- /bin/mount --rbind "$SYS_CERT_DIR" "$target_dir" 2>/dev/null || \
    /system/bin/nsenter -t "$pid" -m /bin/mount --rbind "$SYS_CERT_DIR" "$target_dir" 2>/dev/null || \
    log "Failed to inject into $pid"
}

get_zygote_children() {
    zygote_pid="$1"
    children=""

    # Try modern ps command first.
    children=$(ps -P "$zygote_pid" -o pid 2>/dev/null | grep -v PID | grep -v "$zygote_pid")

    # Fallback to old style ps.
    if [ -z "$children" ]; then
        children=$(ps | awk -v PPID="$zygote_pid" '$3==PPID { print $2 }')
    fi

    # Alternative: use /proc directly.
    if [ -z "$children" ]; then
        for pid_dir in /proc/[0-9]*; do
            if [ -f "$pid_dir/status" ]; then
                ppid=$(grep "PPid:" "$pid_dir/status" 2>/dev/null | awk '{print $2}')
                if [ "$ppid" = "$zygote_pid" ]; then
                    child_pid=${pid_dir##*/}
                    children="$children $child_pid"
                fi
            fi
        done
    fi

    echo "$children"
}

monitor_zygote() {
    (
        active_apex_dir=$(get_apex_cert_dir)
        [ -z "$active_apex_dir" ] && active_apex_dir="$APEX_CERT_DIR"
        log "Using APEX cert dir: $active_apex_dir"

        while true; do
            # Collect all zygote PIDs (both 32- and 64-bit, and webview zygote).
            zygote_pids=""
            for name in zygote zygote64 webview_zygote; do
                for p in $(pidof "$name" 2>/dev/null); do
                    zygote_pids="$zygote_pids $p"
                done
            done

            for zp in $zygote_pids; do
                [ -d "/proc/$zp" ] || continue

                # Check if our bind is present, re-apply it after a zygote restart.
                if ! has_mount "$zp" "$active_apex_dir"; then
                    children=$(get_zygote_children "$zp")
                    child_count=$(echo "$children" | wc -w)
                    if [ "$child_count" -lt 3 ]; then
                        /system/bin/sleep 1s
                        continue
                    fi

                    log "Injecting into zygote ($zp)"
                    inject_into_pid "$zp" "$active_apex_dir"

                    for child_pid in $children; do
                        [ -d "/proc/$child_pid" ] || continue
                        if ! has_mount "$child_pid" "$active_apex_dir"; then
                            log "  Injecting into child $child_pid"
                            inject_into_pid "$child_pid" "$active_apex_dir"
                        fi
                    done
                fi
            done
            sleep 3
        done
    ) &
}

main() {
    log "RootCAInjector - service.sh starting"
    log "Android version: $(getprop ro.build.version.release)"
    log "SDK: $(getprop ro.build.version.sdk)"

    # Wait for the credential stores to become available.
    while [ "$(getprop sys.boot_completed)" != 1 ]; do
        /system/bin/sleep 1s
    done
    log "Boot completed"

    mkdir -p "$EXTERNAL_CERT_DIR" "$MODULE_CERT_DIR"
    sync_external_certificates

    # Detect the active Conscrypt trust store.
    active_apex_dir=$(get_apex_cert_dir)
    if [ -n "$active_apex_dir" ] && [ -d "$active_apex_dir" ]; then
        log "Grabbing APEX certs from: $active_apex_dir"
        copy_certificates "$active_apex_dir" "$MODULE_CERT_DIR"

        # On modern Android, bind the combined store into zygote namespaces.
        if mount -t tmpfs tmpfs "$SYS_CERT_DIR"; then
            LIVE_CERT_DIR=$SYS_CERT_DIR
            copy_certificates "$MODULE_CERT_DIR" "$LIVE_CERT_DIR"
            fix_system_store_permissions "$LIVE_CERT_DIR"
            monitor_zygote
            log "Started zygote monitor"
        else
            log "Failed to mount live system CA store; using Magisk mount only"
        fi
    else
        log "No Conscrypt APEX detected; using system mount only"
    fi

    # New files in the external inbox are copied to both stores immediately.
    monitor_external_certificates
    log "RootCAInjector finished injecting certs"
}
main
