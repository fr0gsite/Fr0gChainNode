#!/usr/bin/env bash

# Paths
: "${BASE:=/usr/node/chaindata}"
: "${DATA_DIR:="$BASE/data"}"
: "${BLOCK_DIR:="$BASE/blocks"}"
: "${CONFIG_DIR:="$BASE/config"}"
: "${CERTS_DIR:="$BASE/certs"}"
: "${LOGFILE:="$BASE/nodeos.log"}"

# Keys and Account
: "${PUBKEY:=""}"
: "${PRIVKEY:=""}"
: "${ACCOUNT_NAME:=""}"

# Network
: "${HTTP_PORT:=8888}"
: "${P2P_PORT:=9010}"
: "${HTTP_IP:="$(hostname -i)"}"
: "${P2P_IP:="$(hostname -i)"}"
: "${FQDN:=""}"

# Optional node to connect to after startup
: "${CONNECT_TO_NODE:=""}"

# Force SSL/TLS? true/false
# (Default logic: if certificate is found, we enable SSL,
#  otherwise HTTP; you could force SSL here statically)
: "${FORCE_HTTPS:=""}"

# Plugins (true/false) that can be enabled or disabled as needed
: "${ENABLE_PRODUCER_PLUGIN:="true"}"
: "${ENABLE_PRODUCER_API_PLUGIN:="true"}"
: "${ENABLE_CHAIN_API_PLUGIN:="true"}"
: "${ENABLE_HTTP_PLUGIN:="true"}"
: "${ENABLE_HISTORY_PLUGIN:="false"}"
: "${ENABLE_HISTORY_API_PLUGIN:="false"}"
: "${ENABLE_NET_API_PLUGIN:="true"}"

# If you want to use a custom genesis.json
: "${GENESIS_JSON:="genesis.json"}"

# Build HTTP and P2P addresses
P2P_ADDRESS="$P2P_IP:$P2P_PORT"
HTTP_ADDRESS="$HTTP_IP:$HTTP_PORT"
FQDN_WITH_PORT="$FQDN:$HTTP_PORT"

echo "======================================================================"
echo "Node Configuration:"
echo "  BASE:          $BASE"
echo "  PUBKEY:        $PUBKEY"
echo "  PRIVKEY:       [hidden]"
echo "  PRODUCER_NAME: $ACCOUNT_NAME"
echo "  HTTP_ADDRESS:  $HTTP_ADDRESS"
echo "  P2P_ADDRESS:   $P2P_ADDRESS"
echo "  FQDN:          $FQDN_WITH_PORT"
echo "======================================================================"

##
# 2. Prepare log file (delete existing if present, create new one)
##
if [ -f "$LOGFILE" ]; then
    rm "$LOGFILE"
fi
touch "$LOGFILE"

##
# 3. Create/open/unlock wallet and import private key
##
echo "=== Preparing Wallet ==="
if [ ! -f "filewithwalletpassword" ]; then
    touch filewithwalletpassword
    cleos wallet create -f filewithwalletpassword
fi

cleos wallet open
cleos wallet unlock --password "$(cat filewithwalletpassword)"

# Only import if PRIVKEY is not empty
if [ -n "$PRIVKEY" ]; then
    cleos wallet import --private-key "$PRIVKEY"
fi

##
# 4. Build nodeos arguments step by step
##
eosargs=()

# Helper function to set plugins only when the corresponding
# ENABLE_* value is set to "true"
add_plugin_if_enabled() {
    local envvar="$1"
    local plugin="$2"

    # ${!envvar} expands the value of the variable whose name is in $envvar
    if [ "${!envvar}" = "true" ]; then
        eosargs+=(--plugin "eosio::$plugin")
    fi
}

prepare_chain() {
    # Pass genesis.json if present
    if [ -f "$GENESIS_JSON" ]; then
        eosargs+=(--genesis-json "$GENESIS_JSON")
    fi

    if [ -n "$PUBKEY" ] && [ -n "$PRIVKEY" ]; then
        eosargs+=(--signature-provider "$PUBKEY=KEY:$PRIVKEY")
    fi

    # Enable plugins based on environment variables
    add_plugin_if_enabled ENABLE_PRODUCER_PLUGIN    "producer_plugin"
    add_plugin_if_enabled ENABLE_PRODUCER_API_PLUGIN "producer_api_plugin"
    add_plugin_if_enabled ENABLE_CHAIN_API_PLUGIN   "chain_api_plugin"
    add_plugin_if_enabled ENABLE_HTTP_PLUGIN        "http_plugin"
    add_plugin_if_enabled ENABLE_HISTORY_PLUGIN     "history_plugin"
    add_plugin_if_enabled ENABLE_HISTORY_API_PLUGIN "history_api_plugin"
    add_plugin_if_enabled ENABLE_NET_API_PLUGIN     "net_api_plugin"

    # Standard arguments
    eosargs+=(--data-dir "$DATA_DIR")
    eosargs+=(--blocks-dir "$BLOCK_DIR")
    eosargs+=(--config-dir "$CONFIG_DIR")

    # Set producer name only if specified
    if [ -n "$ACCOUNT_NAME" ]; then
        eosargs+=(--producer-name "$ACCOUNT_NAME")
    fi

    # HTTP/HTTPS logic
    if [ -f "$CERTS_DIR/fullchain.pem" ] && [ -z "$FORCE_HTTPS" ] || [ "$FORCE_HTTPS" = "true" ]; then
        echo "HTTPS active (certificates found or forced)"
        eosargs+=(--https-server-address "$HTTP_ADDRESS")
        eosargs+=(--https-certificate-chain-file "$CERTS_DIR/fullchain.pem")
        eosargs+=(--https-private-key-file "$CERTS_DIR/privkey.pem")
        eosargs+=(--http-alias "$HTTP_ADDRESS")
        eosargs+=(--http-alias "$FQDN_WITH_PORT")
    else
        echo "HTTP active (no certificates found or FORCE_HTTPS=false)"
        eosargs+=(--http-server-address "$HTTP_ADDRESS")
    fi

    # P2P
    eosargs+=(--p2p-listen-endpoint "$P2P_ADDRESS")

    # Various other useful default options
    eosargs+=(--access-control-allow-origin="*")
    eosargs+=(--contracts-console)
    eosargs+=(--http-validate-host=false)
    eosargs+=(--verbose-http-errors)
    eosargs+=(--enable-stale-production)
}

##
# 5. Start nodeos
##
start_chain() {
    echo "=== Starting nodeos ==="
    nodeos "${eosargs[@]}" >> "$LOGFILE" 2>&1 &
    echo $! > "$BASE/eosd.pid"
    sleep 2
    echo "=== nodeos Log Excerpt ==="
    cat "$LOGFILE"
}

prepare_chain
sleep 10
start_chain
sleep 5

##
# 6. Wait until nodeos is running (regularly call /v1/chain/get_info)
#    and restart if needed when the node doesn't start correctly
##
TRY_COUNTER=0

while true; do
    if [ -f "$CERTS_DIR/fullchain.pem" ] && [ -z "$FORCE_HTTPS" ] || [ "$FORCE_HTTPS" = "true" ]; then
        GET_INFO=$(curl -s "https://$FQDN_WITH_PORT/v1/chain/get_info")
    else
        GET_INFO=$(curl -s "http://$HTTP_ADDRESS/v1/chain/get_info")
    fi

    sleep 2
    if [[ -n "$GET_INFO" ]]; then
        echo "*** Node running: get_info successful ***"
        break
    else
        TRY_COUNTER=$((TRY_COUNTER + 1))
        echo "*** Node not starting *** Attempt: $TRY_COUNTER"
    fi

    if (( TRY_COUNTER > 10 )); then
        echo "*** Restarting Node ***"
        pkill -f nodeos
        start_chain
        sleep 5
        TRY_COUNTER=0
    fi
done

##
# 7. Optional: Connect to another node
#    (CLEOS commands)
##
if [ -n "$CONNECT_TO_NODE" ]; then
    echo "*** cleos net connect to $CONNECT_TO_NODE ***"
    if [ -f "$CERTS_DIR/fullchain.pem" ] && [ -z "$FORCE_HTTPS" ] || [ "$FORCE_HTTPS" = "true" ]; then
        cleos -u "https://$FQDN_WITH_PORT" net connect "$CONNECT_TO_NODE" >> "$LOGFILE"
    else
        cleos -u "http://$HTTP_ADDRESS" net connect "$CONNECT_TO_NODE" >> "$LOGFILE"
    fi
fi

echo "=== Following Log Output ==="
tail -F "$LOGFILE"
