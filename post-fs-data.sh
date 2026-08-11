#!/system/bin/sh
# Build the Magisk system-store mirror before it is mounted over /system.
MODDIR=${0%/*}
SYS_CERT_DIR=/system/etc/security/cacerts
MODULE_CERT_DIR=$MODDIR$SYS_CERT_DIR
EXTERNAL_CERT_DIR=/data/adb/root-ca-injector/certs
LEGACY_USER_CERT_DIR=/data/misc/keychain/cacerts-added

log() {
    echo "$(date '+%m-%d %H:%M:%S ')" "$@" >> "$MODDIR/log.txt"
}

is_certificate_filename() {
    # Android looks up CA files by their old OpenSSL subject hash: <hash>.<n>.
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

    # The hash identifies a subject, not one unique certificate.  Retain both
    # CAs when sources use the same hash instead of overwriting one of them.
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
    # File contexts differ by Android release and user ID; ask the device
    # policy to restore the correct one instead of hard-coding a label.
    restorecon -RF "$user_cert_dir" 2>/dev/null || true
}

install_external_certificates_into_user_store() {
    [ -d "$EXTERNAL_CERT_DIR" ] || return 0

    # Current Android releases use per-user directories.  Older Conscrypt
    # releases use the shared keychain directory, so support both layouts.
    for user_cert_dir in "$LEGACY_USER_CERT_DIR" /data/misc/user/*/cacerts-added; do
        [ -d "$user_cert_dir" ] || continue
        copy_certificates "$EXTERNAL_CERT_DIR" "$user_cert_dir"
        fix_user_store_permissions "$user_cert_dir"
        log "Installed external CAs in user store: $user_cert_dir"
    done
}

collect_user_certificates() {
    copy_certificates "$LEGACY_USER_CERT_DIR" "$MODULE_CERT_DIR"
    for user_cert_dir in /data/misc/user/*/cacerts-added; do
        copy_certificates "$user_cert_dir" "$MODULE_CERT_DIR"
    done
}

main() {
    : > "$MODDIR/log.txt"
    log "RootCAInjector - post-fs-data.sh"

    mkdir -p "$MODULE_CERT_DIR" "$EXTERNAL_CERT_DIR"
    rm -f "$MODULE_CERT_DIR"/*

    # Keep the existing root store, then merge every user CA and finally the
    # external inbox.  The inbox is copied directly too, so a missing user
    # directory never prevents installation into the system trust store.
    copy_certificates "$SYS_CERT_DIR" "$MODULE_CERT_DIR"
    install_external_certificates_into_user_store
    collect_user_certificates
    copy_certificates "$EXTERNAL_CERT_DIR" "$MODULE_CERT_DIR"

    log "Prepared system and user copies of external CAs"
}
main
