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
    
    # Process all chains
    for chain in chains:
        chain_name = getattr(chain, "name", "")
        deploy_core = getattr(chain, "deploy_core", False)
        existing_addresses = safe_get(chain, "existing_addresses", {})
        
        if not as_bool(deploy_core, False) and existing_addresses:
            # Use pre-existing addresses from config
            contract_addresses[chain_name] = existing_addresses

    # Get chains that need deployment  
    chains_needing_core = get_chains_needing_core(chains)
    if len(chains_needing_core) == 0:
        return contract_addresses

    # Execute deployment - this writes addresses to /configs/registry/chains/*/addresses.yaml
    execute_core_deployment(plan)
    
    # Read and store the deployed addresses for each chain
    for chain in chains_needing_core:
        chain_name = getattr(chain, "name", "")
        
        # Read the addresses YAML file and convert to JSON for extraction
        result = plan.exec(
            service_name="hyperlane-cli",
            recipe=ExecRecipe(
                command=[
                    "sh", "-c",
                    "yq -o=json '.' /configs/registry/chains/{}/addresses.yaml".format(chain_name),
                ],
                extract={
                    "mailbox": "fromjson | .mailbox",
                    "validatorAnnounce": "fromjson | .validatorAnnounce",
                    "merkleTreeHook": "fromjson | .merkleTreeHook",
                    "proxyAdmin": "fromjson | .proxyAdmin",
                    "interchainAccountRouter": "fromjson | .interchainAccountRouter",
                    "testRecipient": "fromjson | .testRecipient",
                    "domainRoutingIsmFactory": "fromjson | .domainRoutingIsmFactory",
                    "staticAggregationHookFactory": "fromjson | .staticAggregationHookFactory",
                    "staticAggregationIsmFactory": "fromjson | .staticAggregationIsmFactory",
                    "staticMerkleRootMultisigIsmFactory": "fromjson | .staticMerkleRootMultisigIsmFactory",
                    "staticMerkleRootWeightedMultisigIsmFactory": "fromjson | .staticMerkleRootWeightedMultisigIsmFactory",
                    "staticMessageIdMultisigIsmFactory": "fromjson | .staticMessageIdMultisigIsmFactory",
                    "staticMessageIdWeightedMultisigIsmFactory": "fromjson | .staticMessageIdWeightedMultisigIsmFactory",
                },
            ),
        )
        
        # Build the contract addresses dictionary from extracted values
        contract_addresses[chain_name] = {
            "mailbox": result["extract.mailbox"],
            "validatorAnnounce": result["extract.validatorAnnounce"],
            "merkleTreeHook": result["extract.merkleTreeHook"],
            "proxyAdmin": result["extract.proxyAdmin"],
            "interchainAccountRouter": result["extract.interchainAccountRouter"],
            "testRecipient": result["extract.testRecipient"],
            "domainRoutingIsmFactory": result["extract.domainRoutingIsmFactory"],
            "staticAggregationHookFactory": result["extract.staticAggregationHookFactory"],
            "staticAggregationIsmFactory": result["extract.staticAggregationIsmFactory"],
            "staticMerkleRootMultisigIsmFactory": result["extract.staticMerkleRootMultisigIsmFactory"],
            "staticMerkleRootWeightedMultisigIsmFactory": result["extract.staticMerkleRootWeightedMultisigIsmFactory"],
            "staticMessageIdMultisigIsmFactory": result["extract.staticMessageIdMultisigIsmFactory"],
            "staticMessageIdWeightedMultisigIsmFactory": result["extract.staticMessageIdWeightedMultisigIsmFactory"],
        }
    
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
