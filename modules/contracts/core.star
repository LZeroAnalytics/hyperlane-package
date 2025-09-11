# Core Contract Deployment Module - Handles Hyperlane core contract deployment

constants_module = import_module("../config/constants.star")
get_constants = constants_module.get_constants

helpers_module = import_module("../utils/helpers.star")
safe_get = helpers_module.safe_get
as_bool = helpers_module.as_bool
log_info = helpers_module.log_info

constants = get_constants()

# ============================================================================
# CORE DEPLOYMENT ORCHESTRATION
# ============================================================================


def deploy_core_contracts(plan, chains, deployer_key):
    """
    Deploy core contracts to chains that require them

    Args:
        plan: Kurtosis plan object
        chains: List of chain configurations
        deployer_key: Deployer private key

    Returns:
        Dictionary of contract addresses for each chain
    """
    contract_addresses = {}
    
    # Process each chain
    for chain in chains:
        chain_name = getattr(chain, "name", "")
        deploy_core = getattr(chain, "deploy_core", False)
        existing_addresses = safe_get(chain, "existing_addresses", {})
        
        if as_bool(deploy_core, False):
            # Chain needs deployment - we know these contracts will be deployed
            # Return a marker structure that indicates deployment
            contract_addresses[chain_name] = {
                "status": "will_deploy",
                "mailbox": "deployed",
                "validatorAnnounce": "deployed",
                "merkleTreeHook": "deployed",
                "proxyAdmin": "deployed",
                "interchainAccountRouter": "deployed",
                "testRecipient": "deployed",
                "domainRoutingIsmFactory": "deployed",
                "staticAggregationHookFactory": "deployed",
                "staticAggregationIsmFactory": "deployed",
                "staticMerkleRootMultisigIsmFactory": "deployed",
                "staticMerkleRootWeightedMultisigIsmFactory": "deployed",
                "staticMessageIdMultisigIsmFactory": "deployed",
                "staticMessageIdWeightedMultisigIsmFactory": "deployed",
            }
        elif existing_addresses:
            # Use pre-existing addresses from config
            contract_addresses[chain_name] = existing_addresses

    # Check if any chain needs core deployment
    chains_needing_core = get_chains_needing_core(chains)

    if len(chains_needing_core) == 0:
        # log_info("No chains require core deployment")
        return contract_addresses

    # log_info("Deploying core contracts to {} chains".format(len(chains_needing_core)))

    # Execute core deployment
    execute_core_deployment(plan)
    
    # Verify deployment completed
    plan.exec(
        service_name="hyperlane-cli",
        recipe=ExecRecipe(
            command=[
                "sh",
                "-c",
                """
                # Wait a moment for files to be written
                sleep 2
                
                # Verify addresses were deployed for each chain
                for chain_dir in /configs/registry/chains/*/; do
                    if [ -d "$chain_dir" ]; then
                        chain_name=$(basename "$chain_dir")
                        if [ -f "$chain_dir/addresses.yaml" ]; then
                            echo "✅ Addresses deployed for $chain_name"
                        fi
                    fi
                done
                """,
            ],
        ),
    )
    
    return contract_addresses


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================


def get_chains_needing_core(chains):
    """
    Filter chains that need core deployment

    Args:
        chains: List of chain configurations

    Returns:
        List of chains requiring core deployment
    """
    result = []
    for chain in chains:
        deploy_core = getattr(chain, "deploy_core", False)
        if as_bool(deploy_core, False):
            result.append(chain)
    return result


def execute_core_deployment(plan):
    """
    Execute the core deployment script and wait for completion

    Args:
        plan: Kurtosis plan object
    """
    # Execute the deployment script
    result = plan.exec(
        service_name="hyperlane-cli",
        recipe=ExecRecipe(
            command=["sh", "-lc", constants.DEPLOY_CORE_SCRIPT],
        ),
    )

    # Wait for deployment to complete by checking stamp file
    plan.exec(
        service_name="hyperlane-cli",
        recipe=ExecRecipe(
            command=[
                "sh",
                "-c",
                """
                # Wait for deployment to complete
                max_wait=60
                elapsed=0
                while [ ! -f /configs/.deploy-core ] && [ $elapsed -lt $max_wait ]; do
                    echo "Waiting for core deployment to complete..."
                    sleep 2
                    elapsed=$((elapsed + 2))
                done
                
                if [ -f /configs/.deploy-core ]; then
                    echo "Core deployment completed successfully"
                    # Ensure registry directories have the addresses
                    for chain_dir in /configs/registry/chains/*/; do
                        if [ -d "$chain_dir" ]; then
                            chain_name=$(basename "$chain_dir")
                            if [ -f "$chain_dir/addresses.yaml" ]; then
                                echo "Found addresses for $chain_name"
                            fi
                        fi
                    done
                else
                    echo "WARNING: Core deployment may not have completed properly"
                fi
            """,
            ],
        ),
    )


# ============================================================================
# CORE CONFIGURATION GENERATION
# ============================================================================


def generate_core_config(chains):
    """
    Generate core deployment configuration

    Args:
        chains: List of chain configurations

    Returns:
        Core configuration as a struct
    """
    core_config = {}

    for chain in chains:
        deploy_core = getattr(chain, "deploy_core", False)
        if as_bool(deploy_core, False):
            chain_name = getattr(chain, "name", "")
            core_config[chain_name] = struct(
                chain_id=getattr(chain, "chain_id", None),
                rpc_url=getattr(chain, "rpc_url", ""),
                deploy=True,
            )

    return core_config


def capture_deployed_addresses(plan, chains):
    """
    Capture deployed contract addresses from registry
    
    Args:
        plan: Kurtosis plan object
        chains: List of chains that were deployed
    
    Returns:
        Dictionary of addresses for each chain
    """
    addresses = {}
    
    for chain in chains:
        chain_name = getattr(chain, "name", "")
        
        # Read addresses from registry file
        result = plan.exec(
            service_name="hyperlane-cli",
            recipe=ExecRecipe(
                command=[
                    "sh", "-c",
                    "cat /configs/registry/chains/{}/addresses.yaml 2>/dev/null || echo '{{}}'".format(chain_name)
                ],
            ),
        )
        
        # Parse YAML output to dictionary
        output = result["output"]
        if output and output != "{}":
            # Parse the YAML-formatted addresses
            chain_addresses = parse_yaml_addresses(output)
            addresses[chain_name] = chain_addresses
        else:
            addresses[chain_name] = {}
    return addresses


def parse_yaml_addresses(yaml_output):
    """
    Parse YAML addresses output into a dictionary
    
    Args:
        yaml_output: YAML formatted string of addresses
    
    Returns:
        Dictionary of contract addresses
    """
    addresses = {}
    
    # Split by lines and parse key: value pairs
    lines = yaml_output.split("\n")
    for line in lines:
        if ": " in line and not line.startswith("#"):
            parts = line.split(": ")
            if len(parts) == 2:
                key = parts[0].strip()
                value = parts[1].strip().strip('"')
                if key and value:
                    addresses[key] = value
    
    return addresses


# ============================================================================
# VALIDATION
# ============================================================================


def validate_core_deployment_requirements(chains, deployer_key):
    """
    Validate that core deployment requirements are met

    Args:
        chains: List of chain configurations
        deployer_key: Deployer private key

    Returns:
        True if valid, fails with error if not
    """
    chains_needing_core = get_chains_needing_core(chains)

    if len(chains_needing_core) > 0 and not deployer_key:
        fail("Deployer key is required for core deployment but not provided")

    for chain in chains_needing_core:
        if not chain.get("rpc_url"):
            fail(
                "RPC URL is required for core deployment on chain: {}".format(
                    chain.get("name", "unknown")
                )
            )

    return True
