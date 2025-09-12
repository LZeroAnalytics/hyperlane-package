# Interchain Security Module (ISM) Configuration Guide

This guide explains how to configure Interchain Security Modules (ISMs) in the Hyperlane Kurtosis package.

## Overview

ISMs (Interchain Security Modules) are responsible for verifying the authenticity of cross-chain messages in Hyperlane. This package supports multiple ISM types, allowing you to customize security requirements for your cross-chain applications.

## ISM Types Supported

### 1. Multisig ISM (`multisig`)

The most common ISM type that requires M-of-N validator signatures to verify messages.

**Configuration:**
```json
{
  "global": {
    "ism": {
      "type": "messageIdMultisigIsm",
      "validators": [
        "0xe1A74e1FCB254CB1e5eb1245eaAe034A4D7dD538",
        "0x742d35Cc6637C0532c2fcDC2A7f2c9b8934acCDe"
      ],
      "threshold": 2
    }
  }
}
```

**Parameters:**
- `validators`: Array of validator addresses that can sign messages
- `threshold`: Minimum number of signatures required (must be ≤ number of validators)

### 2. Trusted Relayer ISM (`trustedRelayer`)

Simplest ISM type that trusts a single relayer to deliver messages without additional verification.

**Configuration:**
```json
{
  "global": {
    "ism": {
      "type": "trustedRelayer",
      "relayer": "0xe1A74e1FCB254CB1e5eb1245eaAe034A4D7dD538"
    }
  }
}
```

**Parameters:**
- `relayer`: Address of the trusted relayer (defaults to deployer address if not specified)

### 3. Aggregation ISM (`aggregation`)

Combines multiple ISMs with a threshold requirement.

**Configuration:**
```json
{
  "global": {
    "ism": {
      "type": "aggregation",
      "modules": [
        {
          "type": "messageIdMultisigIsm",
          "validators": ["0xe1A74e1FCB254CB1e5eb1245eaAe034A4D7dD538"],
          "threshold": 1
        },
        {
          "type": "trustedRelayer",
          "relayer": "0x742d35Cc6637C0532c2fcDC2A7f2c9b8934acCDe"
        }
      ],
      "threshold": 1
    }
  }
}
```

**Parameters:**
- `modules`: Array of sub-ISM configurations
- `threshold`: Number of modules that must verify the message

### 4. Routing ISM (`routing`)

Routes verification to different ISMs based on the origin domain.

**Configuration:**
```json
{
  "global": {
    "ism": {
      "type": "routing",
      "owner": "0xe1A74e1FCB254CB1e5eb1245eaAe034A4D7dD538",
      "domains": {
        "11155111": {
          "type": "messageIdMultisigIsm",
          "validators": ["0xe1A74e1FCB254CB1e5eb1245eaAe034A4D7dD538"],
          "threshold": 1
        },
        "84532": {
          "type": "trustedRelayer",
          "relayer": "0x742d35Cc6637C0532c2fcDC2A7f2c9b8934acCDe"
        }
      }
    }
  }
}
```

**Parameters:**
- `owner`: Owner address for the routing ISM
- `domains`: Mapping of domain IDs to ISM configurations

### 5. Merkle Root Multisig ISM (`merkleRoot`)

Validates messages using merkle root proofs with validator signatures.

**Configuration:**
```json
{
  "global": {
    "ism": {
      "type": "merkleRoot",
      "validators": [
        "0xe1A74e1FCB254CB1e5eb1245eaAe034A4D7dD538"
      ],
      "threshold": 1
    }
  }
}
```

**Parameters:**
- `validators`: Array of validator addresses
- `threshold`: Minimum number of signatures required

### 6. Message ID Multisig ISM (`messageIdMultisig`)

Similar to multisig but uses message ID for verification instead of merkle roots.

**Configuration:**
```json
{
  "global": {
    "ism": {
      "type": "messageIdMultisig",
      "validators": [
        "0xe1A74e1FCB254CB1e5eb1245eaAe034A4D7dD538"
      ],
      "threshold": 1
    }
  }
}
```

### 7. Pausable ISM (`pausable`)

Allows pausing message verification with designated pauser addresses.

**Configuration:**
```json
{
  "global": {
    "ism": {
      "type": "pausableIsm",
      "owner": "0xe1A74e1FCB254CB1e5eb1245eaAe034A4D7dD538",
      "pauser": "0x742d35Cc6637C0532c2fcDC2A7f2c9b8934acCDe"
    }
  }
}
```

## Complete Configuration Example

Here's a complete configuration file with multisig ISM:

```json
{
  "chains": [
    {
      "name": "sepolia",
      "rpc_url": "https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY",
      "chain_id": 11155111,
      "deploy_core": true
    },
    {
      "name": "basesepolia",
      "rpc_url": "https://base-sepolia.gateway.tenderly.co",
      "chain_id": 84532,
      "deploy_core": true
    }
  ],
  "agents": {
    "deployer": {
      "key": "0xYOUR_DEPLOYER_PRIVATE_KEY"
    },
    "relayer": {
      "key": "0xYOUR_RELAYER_PRIVATE_KEY"
    },
    "validators": [
      {
        "chain": "sepolia",
        "signing_key": "0xYOUR_VALIDATOR_PRIVATE_KEY",
        "checkpoint_syncer": {
          "type": "local",
          "params": {
            "path": "/data/validator-checkpoints"
          }
        }
      },
      {
        "chain": "basesepolia",
        "signing_key": "0xYOUR_VALIDATOR_PRIVATE_KEY",
        "checkpoint_syncer": {
          "type": "local",
          "params": {
            "path": "/data/validator-checkpoints"
          }
        }
      }
    ]
  },
  "global": {
    "ism": {
      "type": "messageIdMultisigIsm",
      "validators": ["0xYOUR_VALIDATOR_ADDRESS"],
      "threshold": 1
    },
    "cli_version": "latest",
    "agent_image_tag": "agents-v1.4.0"
  }
}
```

## Usage

1. **Copy an example configuration:**
   ```bash
   cp examples/multisig-config.json my-config.json
   ```

2. **Update the configuration:**
   - Replace placeholder private keys with your actual keys
   - Update RPC URLs with your endpoints
   - Adjust ISM validators and threshold as needed

3. **Deploy with ISM configuration:**
   ```bash
   kurtosis run --enclave hyperlane . --args-file my-config.json
   ```

## Validation Rules

The package automatically validates ISM configurations:

- **Multisig ISMs**: Threshold must be ≥ 1 and ≤ number of validators
- **Aggregation ISMs**: Threshold must be ≥ 1 and ≤ number of modules
- **All ISMs**: Required fields must be present

## Security Considerations

1. **Multisig ISM**: More secure but requires coordination between validators
2. **Trusted Relayer ISM**: Faster but less secure - only use for testing
3. **Validator Keys**: Keep validator private keys secure and use hardware security modules in production
4. **Threshold Selection**: Balance security (higher threshold) with liveness (lower threshold)

## Testing ISM Configuration

After deployment, test message sending:

```bash
# Send a test message
kurtosis service exec hyperlane hyperlane-cli \
  "hyperlane send message \
   --origin sepolia \
   --destination basesepolia \
   --body 'Hello ISM!' \
   --registry /configs/registry"
```

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common ISM configuration issues and solutions.