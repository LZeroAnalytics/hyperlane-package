#!/usr/bin/env bash
# Deploy Hyperlane core contracts to specified chains

# Source common utilities - use absolute path in container
if [ -f "/usr/local/bin/common.sh" ]; then
    source "/usr/local/bin/common.sh"
elif [ -f "../../utils/shell/common.sh" ]; then
    # Fallback for local development
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/../../utils/shell/common.sh"
else
    echo "ERROR: Could not find common.sh"
    exit 1
fi

# Source template processor
if [ -f "/usr/local/bin/template_processor.sh" ]; then
    source "/usr/local/bin/template_processor.sh"
elif [ -f "../../utils/shell/template_processor.sh" ]; then
    # Fallback for local development
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/../../utils/shell/template_processor.sh"
else
    echo "ERROR: Could not find template_processor.sh"
    exit 1
fi

# ============================================================================
# MAIN DEPLOYMENT LOGIC
# ============================================================================

deploy_core_to_chain() {
    local chain_name="$1"
    local rpc_url="$2"
    local chain_id="$3"
    local stamp_file="${CONFIGS_DIR}/.done-core-${chain_name}"
    
    # Check if already deployed
    if check_stamp_file "$stamp_file"; then
        log_info "Core already deployed for ${chain_name}, skipping"
        return 0
    fi
    
    # Setup registry directory for this chain
    local reg_chain_dir="${REGISTRY_DIR}/chains/${chain_name}"
    ensure_directories "$reg_chain_dir"
    
    # Create chain metadata
    create_chain_metadata "$chain_name" "$rpc_url" "$chain_id" "$reg_chain_dir"
    
    # Initialize core configuration
    local core_cfg="${CONFIGS_DIR}/core-${chain_name}.yaml"
    if ! initialize_core_config "$core_cfg"; then
        log_error "Failed to initialize core config for ${chain_name}"
        exit $ERROR_DEPLOYMENT_FAILED
    fi
    
    # Deploy core contracts with retry logic
    if deploy_core_with_retry "$chain_name" "$core_cfg"; then
        # Copy deployment artifacts
        copy_deployment_artifacts "$chain_name" "$reg_chain_dir"
        create_stamp_file "$stamp_file"
        log_info "Successfully deployed core contracts to ${chain_name}"
        # Display the deployed contract addresses
        display_deployed_addresses "$chain_name"
    else
        log_error "Failed to deploy core contracts to ${chain_name}"
        exit $ERROR_DEPLOYMENT_FAILED
    fi
}

create_chain_metadata() {
    local chain_name="$1"
    local rpc_url="$2"
    local chain_id="$3"
    local output_dir="$4"
    
    cat > "${output_dir}/metadata.yaml" <<EOF
name: ${chain_name}
protocol: ethereum
chainId: ${chain_id}
domainId: ${chain_id}
rpcUrls:
  - http: ${rpc_url}
nativeToken:
  name: Ether
  symbol: ETH
  decimals: 18
EOF
    
    log_debug "Created metadata for ${chain_name}"
}


initialize_core_config() {
    local config_file="$1"

    # Reuse existing init output if present to avoid redundant work
    if [ -f "$config_file" ]; then
        log_debug "Reusing existing ${config_file}"
        return 0
    fi

    log_info "Initializing core config"
    
    # Try to run hyperlane core init with proper flags
    # Use -o to specify output location, --registry to use local registry
    # Provide empty input for owner address prompt (will use default from key)
    if echo "" | hyperlane core init -y -o "$config_file" --registry /configs/registry 2>&1 | grep -v "TypeError: fetch failed" > /dev/null; then
        if [ -f "$config_file" ]; then
            log_info "Successfully created core config with hyperlane core init"
            return 0
        fi
    fi
    
    # Fallback: Create a valid core config manually
    log_info "Creating core config with ISM type: ${ISM_TYPE:-trustedRelayer}"
    
    # Get the deployer address from the HYP_KEY
    # Using cast to derive address from private key
    local DEPLOYER_ADDRESS=""
    if [ -n "$HYP_KEY" ]; then
        DEPLOYER_ADDRESS=$(cast wallet address "$HYP_KEY" 2>/dev/null || echo "")
        log_info "Derived deployer address: $DEPLOYER_ADDRESS"
    fi
    
    # Use default address if derivation failed
    if [ -z "$DEPLOYER_ADDRESS" ]; then
        DEPLOYER_ADDRESS="0xe1A74e1FCB254CB1e5eb1245eaAe034A4D7dD538"
        log_info "Using default deployer address: $DEPLOYER_ADDRESS"
    fi
    
    # Set template directory based on environment
    local template_dir="${TEMPLATE_DIR:-/templates}"
    if [ ! -d "$template_dir" ]; then
        # Try relative path for local development
        template_dir="${SCRIPT_DIR}/../../templates"
    fi
    
    # Generate ISM configuration from template
    local ism_type="${ISM_TYPE:-trustedRelayer}"
    local ism_config=$(generate_ism_from_template "$ism_type" "$DEPLOYER_ADDRESS" "${template_dir}/ism")
    
    # Generate core configuration from template
    generate_core_config_from_template "$DEPLOYER_ADDRESS" "$ism_config" "${template_dir}/core-config.json" "$config_file"
    
    if [ -f "$config_file" ]; then
        log_debug "Created core config with ISM type: ${ISM_TYPE:-trustedRelayer}"
        return 0
    else
        log_error "Failed to create core config file"
        return 1
    fi
}

deploy_core_with_retry() {
    local chain_name="$1"
    local config_file="$2"
    local log_file="/tmp/deploy-${chain_name}.log"
    
    log_info "Deploying Hyperlane core to ${chain_name}"
    
    # Define the deployment command
    local deploy_cmd="hyperlane core deploy --chain '${chain_name}' -o '${config_file}' -r '${REGISTRY_DIR}' -k '${HYP_KEY}' -y 2>&1 | tee '${log_file}'"
    
    # Try deployment with retry on nonce errors
    local attempt=0
    while [ $attempt -lt $MAX_RETRY_ATTEMPTS ]; do
        attempt=$((attempt + 1))
        
        if [ $attempt -gt 1 ]; then
            log_info "🔄 Deployment attempt $attempt/$MAX_RETRY_ATTEMPTS for ${chain_name}..."
        fi
        
        if eval "$deploy_cmd"; then
            if [ $attempt -gt 1 ]; then
                log_info "✅ Deployment succeeded on attempt $attempt for ${chain_name}"
            fi
            return 0
        fi
        
        # Check for nonce errors
        if grep -q "nonce has already been used\|nonce too low" "$log_file"; then
            if [ $attempt -lt $MAX_RETRY_ATTEMPTS ]; then
                log_info "⚠️  Nonce error detected on ${chain_name}, this may indicate contracts are already deployed"
                log_info "🔄 Retrying deployment (attempt $attempt/$MAX_RETRY_ATTEMPTS)..."
                sleep $RETRY_DELAY
            fi
        else
            log_error "Deployment failed with non-recoverable error"
            cat "$log_file"
            return 1
        fi
    done
    
    log_error "Deployment failed after $MAX_RETRY_ATTEMPTS attempts"
    return 1
}

extract_ism_address() {
    local chain_name="$1"
    local target_dir="$2"
    local addresses_file="${target_dir}/addresses.yaml"
    
    # Get mailbox address
    local mailbox_addr=$(grep "^mailbox:" "$addresses_file" | cut -d' ' -f2 | tr -d '"')
    
    if [ -n "$mailbox_addr" ]; then
        # Get chain RPC URL
        local rpc_url=""
        for chain in $CHAINS; do
            if [ "$chain" = "$chain_name" ]; then
                rpc_url="${RPCS[$chain]}"
                break
            fi
        done
        
        if [ -n "$rpc_url" ]; then
            # Query defaultIsm from mailbox contract using cast
            local ism_addr=$(cast call "$mailbox_addr" "defaultIsm()(address)" --rpc-url "$rpc_url" 2>/dev/null || echo "")
            
            if [ -n "$ism_addr" ] && [ "$ism_addr" != "" ]; then
                log_debug "Found ISM address for ${chain_name}: ${ism_addr}"
                
                # Append ISM address to addresses.yaml
                echo "defaultIsm: \"${ism_addr}\"" >> "$addresses_file"
                log_info "Added ISM address to ${chain_name} registry"
            else
                log_debug "Could not extract ISM address for ${chain_name}"
            fi
        fi
    fi
}

copy_deployment_artifacts() {
    local chain_name="$1"
    local target_dir="$2"
    local addresses_file="$HOME/.hyperlane/chains/${chain_name}/addresses.yaml"
    
    if [ -f "$addresses_file" ]; then
        cp "$addresses_file" "${target_dir}/addresses.yaml" || true
        log_debug "Copied deployment artifacts for ${chain_name}"
        
        # Extract and add ISM address from mailbox contract
        extract_ism_address "$chain_name" "$target_dir"
    fi
}

display_deployed_addresses() {
    local chain_name="$1"
    local registry_file="${REGISTRY_DIR}/chains/${chain_name}/addresses.yaml"
    
    if [ -f "$registry_file" ]; then
        log_info "✅ Core contract deployments complete for ${chain_name}:"
        echo ""
        # Display the addresses with proper formatting
        while IFS=': ' read -r key value; do
            if [ -n "$key" ] && [ -n "$value" ]; then
                echo "    $key: $value"
            fi
        done < "$registry_file"
        echo ""
    else
        log_warn "Could not find deployed addresses for ${chain_name}"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Validate required environment variables
    require_env_var "CHAIN_NAMES" "CHAIN_NAMES not set"
    require_env_var "HYP_KEY" "HYP_KEY not set (agents.deployer.key). Required for core deployment."
    
    # Install CLI if needed
    ensure_hyperlane_cli
    
    # Create necessary directories
    ensure_directories "$CONFIGS_DIR" "${REGISTRY_DIR}/chains"
    
    # Parse chain configurations
    declare -A RPCS
    declare -A IDS
    parse_key_value_pairs "${CHAIN_RPCS:-}" RPCS
    parse_key_value_pairs "${CHAIN_IDS:-}" IDS
    
    # Deploy to each chain
    IFS=',' read -r -a CHAINS <<< "${CHAIN_NAMES}"
    for chain in "${CHAINS[@]}"; do
        # Validate chain name
        validate_chain_name "$chain"
        
        # Get RPC URL
        rpc="${RPCS[$chain]:-}"
        if [ -z "$rpc" ]; then
            log_error "No RPC URL provided for chain ${chain}"
            exit $ERROR_MISSING_ENV
        fi
        
        # Get or detect chain ID
        chain_id=$(get_chain_id "$chain" "$rpc" "${IDS[$chain]:-}")
        
        # Deploy core to this chain
        deploy_core_to_chain "$chain" "$rpc" "$chain_id"
    done
    
    # Mark overall deployment as complete
    create_stamp_file "${CONFIGS_DIR}/.deploy-core"
    log_info "Core deployment completed for all chains"
}

# Run main function
main "$@"