#!/usr/bin/env bash
set -euo pipefail

# This is specific to each chain.
__daemon_version_number=$(echo "$DAEMON_VERSION" | sed 's/^v//')
__daemon_download_url=https://github.com/allora-network/allora-chain/releases/download/$DAEMON_VERSION/allora-chain_${__daemon_version_number}_linux_amd64
__config_url="https://raw.githubusercontent.com/allora-network/networks/refs/heads/main/${NETWORK}"
__genesis_url="${__config_url}/genesis.json"
__seeds_url="${__config_url}/seeds.txt"
__peers_url="${__config_url}/peers.txt"
__denom="uallo"

# Common cosmovisor paths.
__cosmovisor_path=/cosmos/cosmovisor
__genesis_path=$__cosmovisor_path/genesis
__current_path=$__cosmovisor_path/current
__upgrades_path=$__cosmovisor_path/upgrades

if [[ ! -f /cosmos/.initialized ]]; then
  echo "Initializing!"

  echo "Downloading binary..."
  wget $__daemon_download_url -O $__genesis_path/bin/$DAEMON_NAME
  chmod a+x $__genesis_path/bin/$DAEMON_NAME

  # Point to current.
  ln -s -f $__genesis_path $__current_path

  # Create base config.
  echo "Running init..."
  $__genesis_path/bin/$DAEMON_NAME init $MONIKER --chain-id $NETWORK --home /cosmos --default-denom $__denom --overwrite

  echo "Downloading genesis file"
  wget $__genesis_url -O /cosmos/config/genesis.json

  $__genesis_path/bin/$DAEMON_NAME --home=/cosmos config set client chain-id ${NETWORK}
  $__genesis_path/bin/$DAEMON_NAME --home=/cosmos config set client keyring-backend test

  # Always bring the latest config files.
  wget $__config_url/app.toml -O /cosmos/config/app.toml
  wget $__config_url/config.toml -O /cosmos/config/config.toml

  # Don't enable statesync by default.
  dasel put -f /cosmos/config/config.toml -v false statesync.enable

  if [ -n "$SNAPSHOT" ]; then
    echo "Downloading snapshot..."
    curl -o - -L $SNAPSHOT | lz4 -c -d - | tar --exclude='data/priv_validator_state.json' -x -C /cosmos
  else
    echo "No snapshot URL defined."
  fi

  # Check whether we should rapid sync
  if [ -n "${RAPID_SYNC_URL}" ]; then
    echo "Configuring rapid state sync"
    # Get the latest height
    LATEST=$(curl -s "${RAPID_SYNC_URL}/block" | jq -r '.result.block.header.height')
    echo "LATEST=$LATEST"

    # Calculate the snapshot height
    SNAPSHOT_HEIGHT=$((LATEST - 2000));
    echo "SNAPSHOT_HEIGHT=$SNAPSHOT_HEIGHT"

    # Get the snapshot hash
    SNAPSHOT_HASH=$(curl -s $RAPID_SYNC_URL/block\?height\=$SNAPSHOT_HEIGHT | jq -r '.result.block_id.hash')
    echo "SNAPSHOT_HASH=$SNAPSHOT_HASH"

    dasel put -f /cosmos/config/config.toml -v true statesync.enable
    dasel put -f /cosmos/config/config.toml -v "${RAPID_SYNC_URL},${RAPID_SYNC_URL}" statesync.rpc_servers
    dasel put -f /cosmos/config/config.toml -v $SNAPSHOT_HEIGHT statesync.trust_height
    dasel put -f /cosmos/config/config.toml -v $SNAPSHOT_HASH statesync.trust_hash
  else 
    echo "No rapid sync url defined."
  fi

  touch /cosmos/.initialized
else
  echo "Already initialized!"
fi

# Handle updates and upgrades.
__should_update=0

compare_versions() {
    current=$1
    new=$2

    # Extract major, minor, and patch versions
    major_current=$(echo "$current" | cut -d. -f1 | sed 's/v//')
    major_new=$(echo "$new" | cut -d. -f1 | sed 's/v//')

    minor_current=$(echo "$current" | cut -d. -f2)
    minor_new=$(echo "$new" | cut -d. -f2)

    patch_current=$(echo "$current" | cut -d. -f3)
    patch_new=$(echo "$new" | cut -d. -f3)

    # Compare major versions
    if [ "$major_current" -lt "$major_new" ]; then
        __should_update=2
        return
    elif [ "$major_current" -gt "$major_new" ]; then
        __should_update=0
        return
    fi

    # Compare minor versions
    if [ "$minor_current" -lt "$minor_new" ]; then
        __should_update=2
        return
    elif [ "$minor_current" -gt "$minor_new" ]; then
        __should_update=0
        return
    fi

    # Compare patch versions
    if [ "$patch_current" -lt "$patch_new" ]; then
        __should_update=1
        return
    elif [ "$patch_current" -gt "$patch_new" ]; then
        __should_update=0
        return
    fi

    # Versions are the same
    __should_update=0
}

# Upgrades overview.

# Protocol Upgrades:
# - These involve significant changes to the network, such as major or minor version releases.
# - Stored in a dedicated directory: /cosmos/cosmovisor/{upgrade_name}.
# - Cosmovisor automatically manages the switch based on the network's upgrade plan.

# Binary Updates:
# - These are smaller, incremental changes such as patch-level fixes.
# - Only the binary is replaced in the existing /cosmos/cosmovisor/{upgrade_name} directory.
# - Binary updates are applied immediately without additional actions.

# First, we get the current version and compare it with the desired version.
# Also don't know why $DAEMON_NAME writes to stderr.
__current_version=$($__current_path/bin/$DAEMON_NAME version 2>&1)

echo "Current version: ${__current_version}. Desired version: ${DAEMON_VERSION}"

compare_versions $__current_version $DAEMON_VERSION

# __should_update=0: No update needed or versions are the same.
# __should_update=1: Higher patch version.
# __should_update=2: Higher minor or major version.
if [ "$__should_update" -eq 2 ]; then
  echo "Downloading network upgrade..."
  # This is a network upgrade. We'll download the binary, put it in a new folder
  # and we'll let cosmovisor handle the upgrade just in time.
  # Thankfully, allora keeps the upgrade name the same as the version tag, so no need to query
  # the tendermint API.
  mkdir -p $__upgrades_path/$DAEMON_VERSION/bin
  wget $__daemon_download_url -O $__upgrades_path/$DAEMON_VERSION/bin/$DAEMON_NAME
  chmod +x $__upgrades_path/$DAEMON_VERSION/bin/$DAEMON_NAME
  echo "Done!"
elif [ "$__should_update" -eq 1 ]; then
  echo "Updating binary for current version."
  wget $__daemon_download_url -O $__current_path/bin/$DAEMON_NAME
  chmod +x $__upgrades_path/$DAEMON_VERSION/bin/$DAEMON_NAME
  echo "Done!"
else
  echo "No updates needed."
fi

# Get public IP address.
__public_ip=$(curl -s ifconfig.me/ip)
echo "Public ip: ${__public_ip}"

# Always update public IP address, moniker and ports.
dasel put -f /cosmos/config/config.toml -v "${__public_ip}:${CL_P2P_PORT}" p2p.external_address
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_P2P_PORT}" p2p.laddr
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_RPC_PORT}" rpc.laddr
dasel put -f /cosmos/config/config.toml -v ${MONIKER} moniker
dasel put -f /cosmos/config/config.toml -v true prometheus
dasel put -f /cosmos/config/config.toml -v ${LOG_LEVEL} log_level
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${RPC_PORT}" json-rpc.address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${WS_PORT}" json-rpc.ws-address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${CL_GRPC_PORT}" grpc.address
dasel put -f /cosmos/config/app.toml -v true telemetry.enabled
dasel put -f /cosmos/config/client.toml -v "tcp://localhost:${CL_RPC_PORT}" node

# Keep priv_validator_* files in a special folder.
dasel put -f /cosmos/config/config.toml -v "${PRIV_VALIDATOR_PATH}/priv_validator_key.json" priv_validator_key_file
dasel put -f /cosmos/config/config.toml -v "${PRIV_VALIDATOR_PATH}/priv_validator_state.json" priv_validator_state_file

_seeds=$(curl -Ls ${__seeds_url})
_peers=$(curl -Ls ${__peers_url})

# cosmovisor will create a subprocess to handle upgrades
# so we need a special way to handle SIGTERM

# Start the process in a new session, so it gets its own process group.
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
setsid "$@" --minimum-gas-prices=$MIN_GAS_PRICE --p2p.seeds=$_seeds --p2p.persistent_peers $_peers ${EXTRA_FLAGS} &
pid=$!

# Trap SIGTERM in the script and forward it to the process group
trap 'kill -TERM -$pid' TERM

# Wait for the background process to complete
wait $pid
