# Agent Infrastructure Module - Manages agent configuration generator service

constants_module = import_module("../config/constants.star")
get_constants = constants_module.get_constants
DEFAULT_AGENT_TAG = "agents-v1.4.0"  # Fallback default

helpers_module = import_module("../utils/helpers.star")
log_info = helpers_module.log_info
create_persistent_directory = helpers_module.create_persistent_directory

constants = get_constants()

# ============================================================================
# AGENT CONFIG GENERATOR SERVICE
# ============================================================================


def build_agent_config_service(plan, chains, configs_dir, validators = None, global_settings = None):
    """
    Build and deploy the agent configuration generator service

    Args:
        plan: Kurtosis plan object
        chains: List of chain configurations
        configs_dir: Configs directory artifact
        validators: List of validator configurations (optional)
        global_settings: Global configuration including ISM settings (optional)
    """
    # log_info("Setting up agent configuration generator")

    # First ensure addresses are available for chains that need them
    chains_needing_addresses = []
    for chain in chains:
        if getattr(chain, "deploy_core", False):
            chains_needing_addresses.append(getattr(chain, "name", ""))

    if len(chains_needing_addresses) > 0:
        # Wait for addresses to be available
        plan.exec(
            service_name="hyperlane-cli",
            recipe=ExecRecipe(
                command=[
                    "sh",
                    "-c",
                    """
                    echo "Checking for deployed addresses before generating agent config..."
                    chains_to_check='%s'
                    all_found=true
                    
                    for chain in $chains_to_check; do
                        addr_file="/configs/registry/chains/$chain/addresses.yaml"
                        if [ ! -f "$addr_file" ]; then
                            echo "WARNING: Addresses not found for $chain at $addr_file"
                            all_found=false
                        else
                            echo "Found addresses for $chain"
                            # Show mailbox address for verification
                            grep "^mailbox:" "$addr_file" || true
                        fi
                    done
                    
                    if [ "$all_found" = "false" ]; then
                        echo "WARNING: Some addresses are missing, config may use defaults"
                    fi
                """
                    % " ".join(chains_needing_addresses),
                ],
            ),
        )

    # Generate YAML content for agent config including validators and ISM
    yaml_content = generate_chains_yaml(chains, validators, global_settings)

    # Create template files
    files_artifact = create_config_templates(plan, yaml_content)

    # Use pre-built agent config image
    agent_cfg_image = "fravlaca/agent-config-gen:latest"

    # Add the service to the plan
    plan.add_service(
        name="agent-config-gen",
        config=ServiceConfig(
            image=agent_cfg_image,
            env_vars={
                "ENABLE_PUBLIC_FALLBACK": "false",
                "DEBUG": "1",  # Enable debug logging
            },
            files={
                "/seed": files_artifact,
                constants.CONFIGS_DIR: configs_dir,
            },
            cmd=["/seed/args.yaml", "/configs/agent-config.json"],
        ),
    )


def create_agent_config_artifacts(plan, chains, validators = None, global_settings = None):
    """
    Create agent configuration artifacts (no service needed, just files)

    Args:
        plan: Kurtosis plan object
        chains: List of chain configurations
        validators: List of validator configurations (optional)
        global_settings: Global configuration including ISM settings (optional)

    Returns:
        Files artifact with agent configuration
    """
    # log_info("Creating agent configuration artifacts")

    # Generate YAML content for agent config including validators and ISM
    yaml_content = generate_chains_yaml(chains, validators, global_settings)

    # Create configuration files as artifacts
    return create_config_templates(plan, yaml_content)


# ============================================================================
# CONFIGURATION GENERATION
# ============================================================================


def generate_chains_yaml(chains, validators = None, global_settings = None):
    """
    Generate YAML content for chains configuration

    Args:
        chains: List of chain configurations
        validators: List of validator configurations (optional)
        global_settings: Global configuration including ISM settings (optional)

    Returns:
        YAML content as string
    """
    yaml_content = "chains:\n"

    for chain in chains:
        yaml_content += "  - name: {}\n".format(getattr(chain, "name", ""))
        yaml_content += "    rpc_url: {}\n".format(getattr(chain, "rpc_url", ""))

        # Add existing addresses if available
        existing = getattr(chain, "existing_addresses", {})
        if existing:
            yaml_content += "    existing_addresses:\n"
            for key, value in existing.items():
                yaml_content += "      {}: {}\n".format(key, value)
        else:
            yaml_content += "    existing_addresses: {}\n"

    # Add validators section if provided
    if validators and len(validators) > 0:
        yaml_content += "\nvalidators:\n"
        for validator in validators:
            yaml_content += "  - chain: {}\n".format(getattr(validator, "chain", ""))
            yaml_content += "    signing_key: {}\n".format(getattr(validator, "signing_key", ""))
            
            # Add checkpoint syncer configuration
            syncer = getattr(validator, "checkpoint_syncer", None)
            if syncer:
                yaml_content += "    checkpoint_syncer:\n"
                yaml_content += "      type: {}\n".format(getattr(syncer, "type", "localStorage"))
                params = getattr(syncer, "params", None)
                if params:
                    yaml_content += "      params:\n"
                    if hasattr(params, "path"):
                        yaml_content += "        path: {}\n".format(params.path)
                    if hasattr(params, "bucket"):
                        yaml_content += "        bucket: {}\n".format(params.bucket)
                    if hasattr(params, "region"):
                        yaml_content += "        region: {}\n".format(params.region)
                    if hasattr(params, "prefix"):
                        yaml_content += "        prefix: {}\n".format(params.prefix)

    # Add ISM configuration if provided
    if global_settings and hasattr(global_settings, "ism"):
        ism = global_settings.ism
        if ism and hasattr(ism, "type"):
            yaml_content += "\ndefault_ism:\n"
            yaml_content += "  type: {}\n".format(ism.type)
            
            # Add ISM-specific configuration based on type
            if ism.type == "messageIdMultisigIsm" or ism.type == "merkleRootMultisigIsm" or ism.type == "multisig":
                validators_list = getattr(ism, "validators", [])
                threshold = getattr(ism, "threshold", 1)
                
                yaml_content += "  validators:\n"
                for validator_addr in validators_list:
                    yaml_content += "    - {}\n".format(validator_addr)
                yaml_content += "  threshold: {}\n".format(threshold)
                
            elif ism.type == "trustedRelayer":
                relayer = getattr(ism, "relayer", "")
                if relayer:
                    yaml_content += "  relayer: {}\n".format(relayer)

    return yaml_content


def create_config_templates(plan, yaml_content):
    """
    Create configuration template files

    Args:
        plan: Kurtosis plan object
        yaml_content: YAML content for chains configuration

    Returns:
        Files artifact with templates
    """
    return plan.render_templates(
        config={
            "args.yaml": struct(template=yaml_content, data=struct()),
            "agent-config.json": struct(template="{}", data=struct()),
        },
        name="agent-config-seed",
        description="Seed files for agent configuration generator",
    )


# ============================================================================
# AGENT IMAGE MANAGEMENT
# ============================================================================


def get_agent_image(agent_tag):
    """
    Get the full agent Docker image name

    Args:
        agent_tag: Agent image tag

    Returns:
        Full agent image name with tag
    """
    return "{}:{}".format(constants.AGENT_IMAGE_BASE, agent_tag)
