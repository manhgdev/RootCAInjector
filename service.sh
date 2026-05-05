#!/system/bin/sh
MODDIR=${0%/*}
APEX_CERT_DIR=/apex/com.android.conscrypt/cacerts
APEX_CERT_DIR_2=/apex/com.android.conscrypt@*/cacerts
SYS_CERT_DIR=/system/etc/security/cacerts
MODULE_CERT_DIR=${MODDIR}${SYS_CERT_DIR}

log() {
    echo "$(date '+%m-%d %H:%M:%S ')" "$@" >> $MODDIR/log.txt
}

has_mount() {
  local pid="$1"
  local apex_dir="$2"
  [ -z "$apex_dir" ] && apex_dir="$APEX_CERT_DIR"
  grep -q " $apex_dir " "/proc/$pid/mountinfo" 2>/dev/null
}

get_apex_cert_dir() {
  # Check for Android 17+ new apex paths
  if [ -d "/apex/com.android.conscrypt/cacerts/" ]; then
    echo "$APEX_CERT_DIR"
  elif ls $APEX_CERT_DIR_2 >/dev/null 2>&1; then
    # Handle versioned apex paths
    ls -d $APEX_CERT_DIR_2 2>/dev/null | head -1
  else
    echo ""
  fi
}

inject_into_pid() {
    local pid="$1"
    local target_dir="$2"
    [ -z "$target_dir" ] && target_dir="$APEX_CERT_DIR"
    
    /system/bin/nsenter --mount=/proc/$pid/ns/mnt -- /bin/mount --rbind $SYS_CERT_DIR $target_dir 2>/dev/null || \
    /system/bin/nsenter -t $pid -m /bin/mount --rbind $SYS_CERT_DIR $target_dir 2>/dev/null || \
    log "Failed to inject into $pid"
}

get_zygote_children() {
    local zygote_pid="$1"
    local children=""
    
    # Try modern ps command first
    children=$(ps -P $zygote_pid -o pid 2>/dev/null | grep -v PID | grep -v $zygote_pid)
    
    # Fallback to old style ps
    if [ -z "$children" ]; then
        children=$(ps | awk -v PPID=$zygote_pid '$3==PPID { print $2 }')
    fi
    
    # Alternative: use /proc directly
    if [ -z "$children" ]; then
        for pid_dir in /proc/[0-9]*; do
            if [ -f "$pid_dir/status" ]; then
                local ppid=$(grep "PPid:" "$pid_dir/status" 2>/dev/null | awk '{print $2}')
                if [ "$ppid" = "$zygote_pid" ]; then
                    local child_pid=$(basename "$pid_dir")
                    children="$children $child_pid"
                fi
            fi
        done
    fi
    
    echo "$children"
}

monitor_zygote(){
    (
    local active_apex_dir=$(get_apex_cert_dir)
    [ -z "$active_apex_dir" ] && active_apex_dir="$APEX_CERT_DIR"
    
    log "Using APEX cert dir: $active_apex_dir"
    
    while true; do
        # Collect all zygote PIDs (both 32- and 64-bit, and webview zygote)
        zygote_pids=""
        for name in zygote zygote64 webview_zygote; do
            for p in $(pidof $name 2>/dev/null); do
                zygote_pids="$zygote_pids $p"
            done
        done

        for zp in $zygote_pids; do
            [ -z "$zp" ] && continue
            
            # Check if zygote is still alive
            [ -d "/proc/$zp" ] || continue
            
            # Check if our bind isn't present, re-apply it
            if ! has_mount "$zp" "$active_apex_dir"; then
                # Get active children
                children=$(get_zygote_children "$zp")
                
                # After a crash, zygote is a bit unstable, so waiting to settle.
                local child_count=$(echo "$children" | wc -w)
                if [ "$child_count" -lt 3 ]; then
                    /system/bin/sleep 1s
                    continue
                fi

                log "Injecting into zygote ($zp)"
                inject_into_pid "$zp" "$active_apex_dir"

                for child_pid in $children; do
                    [ -z "$child_pid" ] && continue
                    if ! has_mount "$child_pid" "$active_apex_dir"; then
                        if [ -d "/proc/$child_pid" ]; then
                            log "  Injecting into child $child_pid"
                            inject_into_pid "$child_pid" "$active_apex_dir"
                        fi
                    fi
                done
            fi
        done
        sleep 3
    done
    )&
}

main(){
    log "RootCAInjector - service.sh starting"
    log "Android version: $(getprop ro.build.version.release)"
    log "SDK: $(getprop ro.build.version.sdk)"

    # Wait for device to finish booting
    while [ "$(getprop sys.boot_completed)" != 1 ]; do
        /system/bin/sleep 1s
    done
    
    log "Boot completed"

    # Detect active APEX cert directory
    local active_apex_dir=$(get_apex_cert_dir)
    
    # In conscrypt mode, copy conscrypt certs and inject into zygote
    if [ -n "$active_apex_dir" ] && [ -d "$active_apex_dir" ]; then
        log "Grabbing apex certs from: $active_apex_dir"
        
        # Ensure module cert directory exists
        mkdir -p $MODULE_CERT_DIR
        
        # Copy system certs first
        if [ -d "$SYS_CERT_DIR" ]; then
            cp $SYS_CERT_DIR/* $MODULE_CERT_DIR/ 2>/dev/null
        fi
        
        # Copy apex certs
        cp $active_apex_dir/* $MODULE_CERT_DIR/ 2>/dev/null
        
        # Create tmpfs mount on system cert directory
        mount -t tmpfs tmpfs $SYS_CERT_DIR
        
        # Copy all certs to system location
        cp $MODULE_CERT_DIR/* $SYS_CERT_DIR/

        # Fix permissions - Android 17 compatible
        chown root:root $SYS_CERT_DIR/* 2>/dev/null || true
        chmod 644 $SYS_CERT_DIR/* 2>/dev/null || true
        chcon u:object_r:system_security_cacerts_file:s0 $SYS_CERT_DIR/* 2>/dev/null || true
        
        # Also fix directory permissions
        chmod 755 $SYS_CERT_DIR
        chcon u:object_r:system_security_cacerts_file:s0 $SYS_CERT_DIR 2>/dev/null || true

        # Start zygote monitoring
        monitor_zygote
        log "Started zygote monitor"
    else
        # /system certs are automatically mounted by Magisk due to collection in post-fs-data
        log "No conscrypt/apex detected, using system mount only"
    fi

    log "RootCAInjector finished injecting certs"
}
main