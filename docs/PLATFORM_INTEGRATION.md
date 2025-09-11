# Hyperlane Platform Integration

## Overview

This document describes the integration between the Hyperlane Kurtosis package and the LZero Analytics platform. The integration allows the platform to deploy Hyperlane cross-chain messaging infrastructure and display deployed contract addresses in the UI.

## Key Changes

### 1. Contract Address Tracking

The package now tracks and returns all contract addresses (both deployed and pre-existing) through the Starlark output. This enables the platform to display these addresses in the UI.

#### Modified Files:
- `modules/contracts/core.star`: Enhanced to track and return contract addresses
- `main.star`: Updated to include contract addresses in the return struct

### 2. Address Collection Flow

```
┌─────────────────┐
│   User Config   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  deploy_core:   │────►│ Deploy Contracts │
│     true        │     │  & Capture       │
└─────────────────┘     └──────────────────┘
         │                       │
         │                       ▼
         │              ┌──────────────────┐
         │              │ Parse Registry   │
         │              │   YAML Files     │
         │              └──────────────────┘
         │                       │
┌─────────────────┐             │
│  deploy_core:   │             │
│     false       │             │
└────────┬────────┘             │
         │                       │
         ▼                       ▼
┌─────────────────┐     ┌──────────────────┐
│ Use Existing    │────►│ Contract Address │
│   Addresses     │     │   Dictionary     │
└─────────────────┘     └──────────────────┘
                                 │
                                 ▼
                        ┌──────────────────┐
                        │  Return in       │
                        │ Starlark Output  │
                        └──────────────────┘
```

### 3. Output Structure

The package now returns a comprehensive output structure:

```javascript
{
  chains: 2,
  validators: 2,
  warp_routes: 0,
  test_enabled: false,
  contracts_addresses: {
    "sepolia": {
      "mailbox": "0x39853Ad90a07997715DCf6E95D444Bad7595c148",
      "merkleTreeHook": "0xD7845b96389F20702542f0F681eA421E27843846",
      "proxyAdmin": "0xA7340f966CaC5340388Ded369fE6D1FF87e601a8",
      "validatorAnnounce": "0x2d0482B81d921A9B8cB4Bd31AdE171F6140178E4",
      "testRecipient": "0x856c0163ED757E6A2b785EcA52473A5179d9DC37",
      // ... more contracts
    },
    "basesepolia": {
      // ... contracts for base sepolia
    }
  },
  deployment_info: {
    "deployer_address": "0x...",
    "relayer_address": "0x...",
    "validators": ["0x...", "0x..."]
  }
}
```

## Configuration Examples

### Deploying New Contracts

```json
{
  "chains": [
    {
      "name": "sepolia",
      "rpc_url": "https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY",
      "chain_id": 11155111,
      "deploy_core": true  // Will deploy new contracts
    }
  ]
}
```

### Using Existing Contracts

```json
{
  "chains": [
    {
      "name": "sepolia",
      "rpc_url": "https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY",
      "chain_id": 11155111,
      "deploy_core": false,  // Will use existing contracts
      "existing_addresses": {
        "mailbox": "0x39853Ad90a07997715DCf6E95D444Bad7595c148",
        "merkleTreeHook": "0xD7845b96389F20702542f0F681eA421E27843846",
        // ... other contract addresses
      }
    }
  ]
}
```

## Platform Integration Points

### Backend (network-service)

The backend already has infrastructure to:
1. Run Kurtosis packages via `RunPackage()` API
2. Store package output in `Status.Execution.Output`
3. Support Hyperlane configuration types

### Frontend (lzero-dashboard)

The frontend can display contract addresses by:
1. Accessing `networkResult.value?.status?.execution?.output`
2. Parsing `contracts_addresses` field
3. Displaying addresses with copy functionality (similar to Chainlink integration)

## Testing

Two test configurations are provided:
- `examples/multisig-config.json`: Deploys new contracts
- `examples/existing-contracts-config.json`: Uses pre-existing contracts

## Benefits

1. **Flexibility**: Supports both new deployments and existing infrastructure
2. **Transparency**: All contract addresses are visible in the UI
3. **Compatibility**: Follows existing platform patterns
4. **No Additional Endpoints**: Contract data is included in package output