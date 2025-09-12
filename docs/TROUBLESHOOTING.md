# Hyperlane Kurtosis Package Troubleshooting Guide

This guide covers common issues and solutions when deploying Hyperlane using the Kurtosis package.

## Common Issues and Solutions

### 1. gRPC Marshaling Errors with Invalid UTF-8

**Error:**
```
rpc error: code = InvalidArgument desc = grpc: error marshaling request: proto: invalid UTF-8 in string field
```

**Cause:** Special characters or complex command strings in validator service configuration causing UTF-8 encoding issues.

**Solution:**
- This has been fixed in the current version by simplifying validator command structure
- Validator services now use direct argument lists instead of complex shell commands
- If you encounter this on older versions, update to the latest package version

**Prevention:**
- Avoid special characters in configuration values
- Use simple command structures in service definitions
- Test configurations with basic ASCII characters first

### 2. Validator Permission Issues

**Error:**
```
Permission denied (os error 13)
Error: Could not write to /data/validator-checkpoints/metadata_latest.json
```

**Cause:** Validators trying to write to directories they don't have permission to access.

**Solution:**
- This has been fixed by changing checkpoint paths from `/data/validator-checkpoints` to `/tmp/validator-checkpoints`
- For manual fixes, ensure the checkpoint directory is writable by the container user

**Alternative Solutions:**
```bash
# Option 1: Use temporary directory (recommended)
"checkpoint_syncer": {
  "type": "local",
  "params": {
    "path": "/tmp/validator-checkpoints"
  }
}

# Option 2: Use S3 storage
"checkpoint_syncer": {
  "type": "s3",
  "params": {
    "bucket": "your-checkpoint-bucket",
    "region": "us-east-1"
  }
}
```

### 3. ISM Configuration Not Applied

**Error:**
- Messages fail to send with ISM-related errors
- Agent config shows empty ISM configuration
- Cross-chain messages are rejected

**Symptoms:**
```json
// In agent-config.json
{
  "ism": "",
  "defaultism": {}
}
```

**Solution:**
- Ensure ISM configuration is in the `global` section of your config file:
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

- Verify the agent-config-gen service processed the ISM configuration:
```bash
kurtosis service logs hyperlane agent-config-gen
```

**Validation:**
Check that ISM appears in the generated config:
```bash
kurtosis service exec hyperlane hyperlane-cli "cat /configs/agent-config.json"
```

### 4. Validator Services Not Starting

**Symptoms:**
- Validators show as "STOPPED" in service list
- No validator checkpoint files being created
- Relayer can't find validator signatures

**Common Causes and Solutions:**

**A. Missing Private Keys:**
```json
// Ensure validator signing keys are provided
{
  "agents": {
    "validators": [
      {
        "chain": "sepolia",
        "signing_key": "0xYOUR_ACTUAL_PRIVATE_KEY"  // Not placeholder
      }
    ]
  }
}
```

**B. Invalid Chain Configuration:**
```json
// Ensure chain names match exactly
{
  "chains": [
    {"name": "sepolia"}  // Must match validator chain
  ],
  "agents": {
    "validators": [
      {"chain": "sepolia"}  // Exact match required
    ]
  }
}
```

**C. Check validator logs:**
```bash
kurtosis service logs hyperlane validator-sepolia
kurtosis service logs hyperlane validator-basesepolia
```

### 5. Contract Deployment Failures

**Error:**
```
Error: Insufficient funds for gas * price + value
```

**Solution:**
- Ensure deployer account has sufficient ETH on all chains
- Check current gas prices and adjust accordingly
- For testnets, get ETH from faucets:
  - Sepolia: https://faucets.chain.link/sepolia
  - Base Sepolia: https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet

**Error:**
```
Error: RPC URL not reachable
```

**Solution:**
- Verify RPC URLs are correct and accessible
- Test RPC connectivity:
```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  YOUR_RPC_URL
```

### 6. Message Sending Failures

**Error:**
```
Error: execution reverted: ISM verification failed
```

**Causes and Solutions:**

**A. ISM Configuration Mismatch:**
- Ensure ISM validators match the actual validator addresses
- Verify threshold is achievable with available validators

**B. Validator Not Signing:**
- Check validator service is running and healthy
- Verify validator has the correct private key
- Check validator logs for signing activity

**C. Test message sending:**
```bash
# Test with Hyperlane CLI
kurtosis service exec hyperlane hyperlane-cli \
  "hyperlane send message \
   --origin sepolia \
   --destination basesepolia \
   --body 'Test message' \
   --registry /configs/registry"
```

### 7. Agent Configuration Issues

**Error:**
```
Error: agent-config.json not found or empty
```

**Solution:**
- Check if agent-config-gen service completed successfully:
```bash
kurtosis service logs hyperlane agent-config-gen
```

- Verify input configuration file is valid JSON/YAML
- Ensure all required fields are present in the configuration

**Manual regeneration:**
```bash
# Restart the agent config generation
kurtosis service remove hyperlane agent-config-gen
# Re-run deployment to regenerate config
```

### 8. Network Connectivity Issues

**Error:**
```
Error: Network timeout or connection refused
```

**Solutions:**
- Check firewall rules and network connectivity
- Verify RPC endpoints are accessible from your network
- Test with different RPC providers if issues persist
- For local development, ensure Docker networking is working

### 9. Service Startup Timeouts

**Error:**
```
Error: Service startup timeout
```

**Solutions:**
- Increase timeout values in service configuration
- Check system resources (CPU, memory, disk space)
- Verify all dependent services are healthy
- Check for port conflicts

**Resource recommendations:**
- Memory: At least 4GB RAM
- CPU: 2+ cores recommended
- Disk: 10GB+ free space

## Diagnostic Commands

### Check Service Status
```bash
kurtosis enclave inspect hyperlane
```

### View Service Logs
```bash
# All services
kurtosis service logs hyperlane <service-name>

# Specific services
kurtosis service logs hyperlane validator-sepolia
kurtosis service logs hyperlane relayer
kurtosis service logs hyperlane hyperlane-cli
```

### Check Generated Configuration
```bash
kurtosis service exec hyperlane hyperlane-cli "cat /configs/agent-config.json"
```

### Verify Contract Addresses
```bash
kurtosis service exec hyperlane hyperlane-cli "find /configs -name '*.yaml' -exec cat {} \;"
```

### Test Message Sending
```bash
# Using the updated test script
node test-message.js
```

## Getting Help

1. **Check service logs** first - they usually contain the root cause
2. **Verify configuration** against working examples
3. **Test components individually** - RPC connectivity, contract deployment, etc.
4. **Check resource usage** - ensure adequate CPU, memory, and disk space

## Reporting Issues

When reporting issues, please include:
1. Full error messages and stack traces
2. Your configuration file (with private keys redacted)
3. Service logs from the failing components
4. Output from `kurtosis enclave inspect hyperlane`
5. Your system specifications and Docker version

## Version-Specific Fixes

### Latest Version Improvements
- ✅ Fixed UTF-8 marshaling errors in validator services
- ✅ Resolved validator permission issues with checkpoint directories
- ✅ Implemented complete ISM configuration support
- ✅ Enhanced agent configuration generation with ISM settings
- ✅ Improved error handling and logging throughout the system

If you're using an older version and encountering these issues, please update to the latest version.