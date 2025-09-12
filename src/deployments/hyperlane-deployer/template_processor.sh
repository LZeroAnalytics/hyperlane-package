#!/bin/bash
# Template processor script for Hyperlane deployment
# This script provides functions for processing template files

# Function to generate ISM configuration from template
generate_ism_from_template() {
    local ism_type="$1"
    local deployer_address="$2"
    local template_dir="$3"
    
    # Handle different ISM types
    case "$ism_type" in
        "multisig"|"messageIdMultisig")
            # Get validators and threshold from environment
            local validators="${ISM_VALIDATORS:-$deployer_address}"
            local threshold="${ISM_THRESHOLD:-1}"
            
            # Convert comma-separated validators to JSON array
            local validators_json=$(echo "$validators" | awk -F',' '{
                printf "["
                for(i=1; i<=NF; i++) {
                    gsub(/^[ \t]+|[ \t]+$/, "", $i)
                    printf "\"%s\"", $i
                    if(i<NF) printf ", "
                }
                printf "]"
            }')
            
            cat <<EOF
{
  "type": "messageIdMultisigIsm",
  "validators": $validators_json,
  "threshold": $threshold
}
EOF
            ;;
            
        "merkleRootMultisig"|"merkleRootMultisigIsm")
            # Get validators and threshold from environment
            local validators="${ISM_VALIDATORS:-$deployer_address}"
            local threshold="${ISM_THRESHOLD:-1}"
            
            # Convert comma-separated validators to JSON array
            local validators_json=$(echo "$validators" | awk -F',' '{
                printf "["
                for(i=1; i<=NF; i++) {
                    gsub(/^[ \t]+|[ \t]+$/, "", $i)
                    printf "\"%s\"", $i
                    if(i<NF) printf ", "
                }
                printf "]"
            }')
            
            cat <<EOF
{
  "type": "merkleRootMultisigIsm",
  "validators": $validators_json,
  "threshold": $threshold
}
EOF
            ;;
            
        "trustedRelayer")
            local relayer="${ISM_RELAYER:-$deployer_address}"
            cat <<EOF
{
  "type": "trustedRelayerIsm",
  "relayer": "$relayer"
}
EOF
            ;;
            
        "pausable")
            local owner="${ISM_OWNER:-$deployer_address}"
            local pauser="${ISM_PAUSER:-$owner}"
            cat <<EOF
{
  "type": "pausableIsm",
  "owner": "$owner",
  "pauser": "$pauser"
}
EOF
            ;;
            
        *)
            # Default to trusted relayer
            cat <<EOF
{
  "type": "trustedRelayerIsm",
  "relayer": "$deployer_address"
}
EOF
            ;;
    esac
}

# Function to generate core config from template
generate_core_config_from_template() {
    local deployer_address="$1"
    local ism_config="$2"
    local template_file="$3"
    local output_file="$4"
    
    # If template doesn't exist, create a basic core config
    if [ ! -f "$template_file" ]; then
        echo "Template file not found: $template_file, creating basic config"
        cat > "$output_file" <<EOF
{
  "owner": "$deployer_address",
  "defaultIsm": $ism_config,
  "defaultHook": {
    "type": "merkleTreeHook"
  },
  "requiredHook": {
    "type": "pausableHook",
    "paused": false,
    "owner": "$deployer_address"
  }
}
EOF
    else
        # Process the template
        cp "$template_file" "$output_file"
        
        # Replace variables
        sed -i "s/{{DEPLOYER_ADDRESS}}/$deployer_address/g" "$output_file"
        sed -i "s/{{ISM_CONFIG}}/$ism_config/g" "$output_file"
    fi
    
    echo "Generated core config at: $output_file"
}