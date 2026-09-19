#!/usr/bin/env bash
set -e

# ==============================================================================
# Supabase Loopback Proxy Utility for Spliqo
# Forwards container localhost (127.0.0.1) requests to host-running Supabase.
# In Codespaces or Cloud Supabase mode, exits cleanly without error spam.
# ==============================================================================

HOST_IP=$(getent ahostsv4 host.docker.internal 2>/dev/null | awk '{ print $1 }' | head -n 1)
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(ip route 2>/dev/null | awk '/default/ { print $3 }' | head -n 1)
fi
[ -z "$HOST_IP" ] && HOST_IP="172.17.0.1"

PORTS=(54320 54321 54322 54323 54324 54327 54329)

case "${1:-start}" in
  stop)
    pkill -f "socat.*bind=127.0.0.1" 2>/dev/null || true
    echo "🛑 Supabase loopback proxy stopped."
    ;;

  status)
    echo "📡 Target Host IP: $HOST_IP"
    for p in "${PORTS[@]}"; do
      if ss -tlpn 2>/dev/null | grep -q "127.0.0.1:$p"; then
        echo "  Port $p: PROXIED -> $HOST_IP:$p"
      else
        echo "  Port $p: NOT RUNNING"
      fi
    done
    ;;

  start)
    # Check if host Supabase is responding on the primary API gateway (54321) or DB (54322)
    HOST_RESPONDING=false
    if timeout 1 bash -c "cat < /dev/null > /dev/tcp/$HOST_IP/54321" 2>/dev/null || \
       timeout 1 bash -c "cat < /dev/null > /dev/tcp/$HOST_IP/54322" 2>/dev/null; then
        HOST_RESPONDING=true
    fi

    if [ "$HOST_RESPONDING" = false ]; then
        echo "ℹ️ Host Supabase is not actively listening on $HOST_IP:54321. Skipping loopback proxy (Cloud Supabase active or local Supabase stopped)."
        exit 0
    fi

    for p in "${PORTS[@]}"; do
      if ! ss -tlpn 2>/dev/null | grep -q "127.0.0.1:$p"; then
        setsid -f socat TCP-LISTEN:$p,fork,reuseaddr,bind=127.0.0.1 TCP:$HOST_IP:$p 2>/dev/null || true
      fi
    done
    echo "✅ Supabase loopback proxy active (Forwarding 127.0.0.1 -> $HOST_IP)."
    ;;

  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac

