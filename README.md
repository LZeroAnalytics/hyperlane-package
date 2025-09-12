# Hyperlane Kurtosis Package

Launch Hyperlane offchain infrastructure on any EVM chain via external RPCs. Supports Warp Routes 2.0 (HWR 2.0). No observability stack.

Key features
- Multi-chain via args.yaml (N>=2); defaults: Ethereum + Arbitrum mainnets
- Secrets passed via args.yaml and injected into services
- Orchestrates Hyperlane CLI for core deploy and HWR 2.0 warp routes
- Launches validator(s) and relayer; local checkpoint syncer by default (S3/GCS optional)
- No public RPC fallbacks: agents and CLI use only the RPCs you provide
- No custom rebalancer bundled: reuse Hyperlane’s official rebalancer and CLI

Usage
- kurtosis clean -a
- kurtosis run --enclave hyperlane ./hyperlane-package --args-file ./hyperlane-package/config/config.yaml
- View logs:
  - kurtosis service logs hyperlane hyperlane-cli
  - kurtosis service logs hyperlane relayer
  - kurtosis service logs hyperlane validator-ethereum
  - kurtosis service logs hyperlane validator-arbitrum

Configuration
Args schema overview
- chains[]:
  - name (string), rpc_url (string), chain_id (int), deploy_core (bool), existing_addresses (object: mailbox, igp, validatorAnnounce, ism)
- agents:
  - deployer: { key }
  - relayer: { key, allow_local_checkpoint_syncers }
  - validators[]: { chain, signing_key, checkpoint_syncer: { type: local|s3|gcs, params: {...} } }
- warp_routes[]:
  - symbol, decimals, topology { chain: collateral|synthetic }, token_addresses { chain: token }, owner
  - mode: lock_release | lock_mint | burn_mint
  - initialLiquidity[]: for lock_release native, list of { chain, amount } amounts in wei to seed release side
- send_test:
  - enabled, origin, destination, amount (wei)
- global:
  - registry_mode: local|public, agent_image_tag, cli_version
  - ism: { type: messageIdMultisigIsm|merkleRootMultisigIsm|trustedRelayer|aggregation|routing|pausableIsm, validators: [...], threshold: N }

- See ./config/schema.yaml for full schema
Agent keys in args.yaml
- agents.deployer.key: used by hyperlane-cli for core/warp operations
- agents.relayer.key: used by relayer
- agents.validators[].signing_key: per-chain validators

- Default example: ./config/config.yaml

Providing RPCs and secrets
- rpc_url values are consumed by the CLI service via CHAIN_RPCS. No chain containers are started; only your external RPCs are used.
- Do not commit secrets. Create a local override file and pass it with --args-file.

Local override example (do not commit)
- Save this as ~/local.args.yaml and customize keys:
  chains:
    - name: ethereum
      rpc_url: https://65d1c7945fa54cfe8325e61562fe97f3-rpc.network.bloctopus.io/
      chain_id: 1
      deploy_core: true
    - name: arbitrum
      rpc_url: https://d88be824605745c0a09b1111da4727fd-rpc.network.bloctopus.io/
      chain_id: 42161
      deploy_core: true

  agents:
    deployer:
      key: 0xYOUR_PRIVATE_KEY
    relayer:
      key: 0xYOUR_PRIVATE_KEY
      allow_local_checkpoint_syncers: true
    validators:
      - chain: ethereum
        signing_key: 0xYOUR_PRIVATE_KEY
        checkpoint_syncer: { type: local, params: { path: /validator-checkpoints } }
      - chain: arbitrum
        signing_key: 0xYOUR_PRIVATE_KEY
        checkpoint_syncer: { type: local, params: { path: /validator-checkpoints } }

  warp_routes:
    - symbol: TEST
      decimals: 18
      topology:
        ethereum: collateral
        arbitrum: synthetic
      mode: lock_release
      initialLiquidity:
        - chain: ethereum
          amount: "10000000000000000"
        - chain: arbitrum
          amount: "10000000000000000"
      owner: 0xOWNER_EOA

  send_test:
    enabled: true
    origin: ethereum
    destination: arbitrum
    amount: "1"

  global:
    registry_mode: local
    agent_image_tag: agents-v1.4.0
    cli_version: latest
    ism:
      type: multisig
      validators: ["0xYOUR_VALIDATOR_ADDRESS"]
      threshold: 1

Run with:
- kurtosis clean -a
- kurtosis run --enclave hyperlane ./hyperlane-package --args-file ~/local.args.yaml

Topologies
- lock_release: native-to-native; for ETH-ETH, seed initialLiquidity on release side(s) in wei. Uses only official Hyperlane CLI.
- lock_mint: lock canonical, mint synthetic; configure topology accordingly.
- burn_mint: burn on source, mint on destination where supported; configure topology accordingly.

Seeding initial liquidity (official tooling)
- initialLiquidity is honored automatically after warp deployment when provided in args.
- The CLI service will derive route addresses via `hyperlane warp read` and seed each listed chain using:
  - `hyperlane submit --chain <chain> --to <derivedAddress> --value <amountWei> -r /configs/registry -y`
- No public RPCs are used.

Smoke tests (manual)
- Start the enclave and check:
  - hyperlane-cli: core deploy writes addresses-*.json; warp init/deploy stamps
  - agent-config-gen: writes /configs/agent-config.json from deployed addresses
  - Relayer: watches chains and runs; no CONFIG_FILES errors
  - Validators: start and write to /data/validator-checkpoints
## Warp route quick test (cross-chain send)
- Ensure your enclave is running and the TEST warp route is deployed and seeded.
- Run a small transfer from ethereum to arbitrum using only your provided RPCs:

  kurtosis service exec hyperlane hyperlane-cli "sh -lc 'hyperlane warp send --origin ethereum --destination arbitrum --warp /configs/registry/deployments/warp_routes/ETH/arbitrum-ethereum-config.yaml --amount 1 --relay -r /configs/registry -y'"

- Inspect logs to confirm relay and execution on the destination:

  kurtosis service logs hyperlane hyperlane-cli
  kurtosis service logs hyperlane relayer
  kurtosis service logs hyperlane validator-ethereum
  kurtosis service logs hyperlane validator-arbitrum

- Alternatively, you can use the helper script baked into the CLI container:

  kurtosis service exec hyperlane hyperlane-cli "sh -lc 'ORIGIN=ethereum DESTINATION=arbitrum WARP_FILE=/configs/registry/deployments/warp_routes/ETH/arbitrum-ethereum-config.yaml AMOUNT=1 /usr/local/bin/send_warp.sh'"

RPC verification
- Ensure no public RPCs are used:
  - List recent logs and grep for non-allowed domains; expect no matches:
    - kurtosis service logs hyperlane relayer | egrep -i '(ankr|llamarpc|alchemy|infura|tenderly|public|blastapi)' || true
  - Confirm only your provided RPC URLs appear:
    - kurtosis service logs hyperlane relayer | egrep -i '(65d1c7945fa54cfe8325e61562fe97f3-rpc\.network\.bloctopus\.io|d88be824605745c0a09b1111da4727fd-rpc\.network\.bloctopus\.io)'

Notes on agent-config.json generation
- Generated inside the enclave by a one-shot container (agent-config-gen) based on your args file and any deployed addresses in /configs/addresses-*.json.
- Public registry fallback is disabled; ensure deploy_core=true or provide existing_addresses when deploy_core=false.

## ISM (Interchain Security Module) Configuration

This package now supports comprehensive ISM configuration for cross-chain message security. ISMs determine how messages are verified when delivered to destination chains.

### Quick Start with Multisig ISM
```json
{
  "global": {
    "ism": {
      "type": "messageIdMultisigIsm",
      "validators": ["0xYourValidatorAddress"],
      "threshold": 1
    }
  }
}
```

### Supported ISM Types
- **multisig**: Requires M-of-N validator signatures (recommended)
- **trustedRelayer**: Trusts a single relayer (testing only)
- **aggregation**: Combines multiple ISMs with threshold
- **routing**: Different ISMs per origin domain
- **merkleRoot**: Merkle proof based verification
- **messageIdMultisig**: Message ID based multisig
- **pausable**: Pausable message verification

For detailed ISM configuration examples and documentation, see:
- [ISM Configuration Guide](./docs/ISM_CONFIGURATION.md)
- [Troubleshooting Guide](./docs/TROUBLESHOOTING.md)

## Testing Message Sending

After successful deployment, test cross-chain messaging:

```bash
# Send a test message
kurtosis service exec hyperlane hyperlane-cli \
  "hyperlane send message \
   --origin sepolia \
   --destination basesepolia \
   --body 'Hello Cross-Chain!' \
   --registry /configs/registry"

# Or use the test script
node test-message.js
```

## Troubleshooting

Common issues and solutions:

1. **UTF-8 marshaling errors**: Fixed in current version
2. **Validator permission issues**: Use `/tmp/validator-checkpoints` path
3. **ISM configuration not applied**: Ensure ISM is in `global` section
4. **Contract deployment failures**: Check account balance and RPC connectivity

For detailed troubleshooting, see [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md)
