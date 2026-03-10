#!/bin/bash
INTERFACE="wg0"
THRESHOLD=300 # 5 minutes
CURRENT_TIME=$(date +%s)
RESTART_NEEDED=true

# Get all latest handshake timestamps for the interface
HANDSHAKES=$(wg show $INTERFACE latest-handshakes | awk '{print $2}')

for HANDSHAKE in $HANDSHAKES; do
    # If even ONE peer has a recent handshake, the interface is working
    if [ "$HANDSHAKE" -ne 0 ]; then
        DIFF=$((CURRENT_TIME - HANDSHAKE))
        if [ $DIFF -lt $THRESHOLD ]; then
            RESTART_NEEDED=false
            break
        fi
    fi
done

# Only restart if NO peers have communicated within the threshold
if [ "$RESTART_NEEDED" = true ]; then
    echo "No active handshakes found. Restarting $INTERFACE..."
    # systemctl restart wg-quick@$INTERFACE
    sudo ip addr flush dev wlan0
    sudo systemctl restart networking
    sudo wg-quick down wg0 && sudo wg-quick up wg0
fi
