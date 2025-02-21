# allora-docker

Docker compose for Allora.

Meant to be used with [central-proxy-docker](https://github.com/CryptoManufaktur-io/central-proxy-docker) for traefik
and Prometheus remote write; use `:ext-network.yml` in `COMPOSE_FILE` inside `.env` in that case.

## Quick setup

Run `cp default.env .env`, then `nano .env`, and update values like MONIKER, NETWORK, and either SNAPSHOT or RAPID_SYNC_URL if you prefer to sync using one of these methods.

If you want the consensus node RPC ports exposed locally, use `rpc-shared.yml` in `COMPOSE_FILE` inside `.env`.

- `./allorad install` brings in docker-ce, if you don't have Docker installed already.
- `docker compose run --rm create-validator-keys` creates the consensus/validator node keys
- `docker compose run --rm import-validator-keys` imports the generated consensus/validator node keys into the docker volume
- `./allorad up`

To update the software, run `./allorad update` and then `./allorad up`

## consensus

### Validator Key Generation

Run `docker compose run --rm create-validator-keys`

It is meant to be executed only once, it has no sanity checks and creates the `priv_validator_key.json`, `priv_validator_state.json` and `voter_state.json` files inside the `keys/consensus/` folder.

Remember to backup those files if you're running a validator.

You can also export the keys from the docker volume, into the `keys/consensus/` folder by running: `docker compose run --rm export-validator-keys`.

### Operator Wallet Creation

An operator wallet is needed for staking operations. We provide a simple command to generate it, so it can be done in an air-gapped environment. It is meant to be executed only once, it has no sanity checks. It creates the operator wallet and stores the result in the `keys/operator/` folder.

Make sure to backup the `keys/operator/$MONIKER.backup` file, it is the only way to recover the wallet.

Run `docker compose run --rm create-operator-wallet`

### Register Validator

This assumes an operator wallet `keys/operator/$MONIKER.info` is present, and the `priv_validator_key.json` is present in the `keys/consensus/` folder.

`docker compose run --rm register-validator`

### CLI

An image with the `allorad` binary is also avilable, e.g:

- `docker compose run --rm cli cosmos show-validator`
- `docker compose run --rm cli tx gov vote 12 yes --from YOUR-MONIKER --chain-id allora-testnet-1 --gas-adjustment 1.4 --fees 2000000uallo --keyring-backend=test --node http://allorad:26658/`

## Version

Allora Docker uses a semver scheme.

This is allora-docker v1.0.4
