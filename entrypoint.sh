#!/usr/bin/env bash
set -euo pipefail

# Paths
WHITELIST_DIR=/etc/postfix/whitelist
WHITELIST_FILE=/etc/postfix/allowed_senders
MAIN_CF_TEMPLATE=/etc/postfix/main.cf.template
MAIN_CF=/etc/postfix/main.cf

# Function to create allowed_senders from configmap contents.
generate_allowed_senders() {
  echo "Generating $WHITELIST_FILE from ConfigMap(s)..."
  # Ensure file is writable
  : > "$WHITELIST_FILE"

  # If the configmap was mounted as a directory (many keys), process each file
  if [ -d "$WHITELIST_DIR" ]; then
    for f in "$WHITELIST_DIR"/*; do
      [ -f "$f" ] || continue
      echo "  reading $f"
      while IFS= read -r line || [ -n "$line" ]; do
        # strip space
        addr="$(echo "$line" | awk '{$1=$1};1')"
        # skip empty and comments
        if [ -n "$addr" ] && [[ ! "$addr" =~ ^# ]]; then
          echo "${addr} OK" >> "$WHITELIST_FILE"
        fi
      done < "$f"
    done
  fi

  # Also support mounting a single file directly (example uses key allowed-senders)
  if [ -f "${WHITELIST_DIR}/allowed-senders" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      addr="$(echo "$line" | awk '{$1=$1};1')"
      if [ -n "$addr" ] && [[ ! "$addr" =~ ^# ]]; then
        echo "${addr} OK" >> "$WHITELIST_FILE"
      fi
    done < "${WHITELIST_DIR}/allowed-senders"
  fi

  # If nothing was written, create a safe default that rejects everything
  if [ ! -s "$WHITELIST_FILE" ]; then
    echo "# No allowed senders provided by ConfigMap; nobody allowed to send" > "$WHITELIST_FILE"
  fi

  # Build postfix db
  postmap hash:"$WHITELIST_FILE"
  echo "Created ${WHITELIST_FILE}.db"
}

# Render main.cf from template (template is basic — we allow env overrides via postconf below)
render_main_cf() {
  if [ -f "$MAIN_CF_TEMPLATE" ]; then
    cp "$MAIN_CF_TEMPLATE" "$MAIN_CF"
  fi
}

# Allow simple runtime configuration via env vars:
# RELAYHOST - set relayhost (example: [smtp.relay]:587)
# MYHOSTNAME - set myhostname
apply_runtime_postconf() {
  if [ -n "${RELAYHOST:-}" ]; then
    echo "Setting relayhost=$RELAYHOST"
    postconf -e "relayhost = ${RELAYHOST}"
  fi

  if [ -n "${MYHOSTNAME:-}" ]; then
    echo "Setting myhostname=$MYHOSTNAME"
    postconf -e "myhostname = ${MYHOSTNAME}"
  fi

  # Allow overriding mynetworks if provided
  if [ -n "${MYNETWORKS:-}" ]; then
    echo "Setting mynetworks=$MYNETWORKS"
    postconf -e "mynetworks = ${MYNETWORKS}"
  fi
}

# Ensure directories exist
mkdir -p /var/spool/postfix /var/log/postfix /etc/postfix

# Render and generate
render_main_cf
generate_allowed_senders
apply_runtime_postconf

# Fix ownership/permissions commonly required by postfix
chown -R root:root /etc/postfix
chmod 644 /etc/postfix/allowed_senders*
# start postfix in foreground
echo "Starting postfix (foreground)..."
exec /usr/sbin/postfix start-fg