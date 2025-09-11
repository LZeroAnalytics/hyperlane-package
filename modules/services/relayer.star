# Relayer Service Module - Builds and manages the relayer service

constants_module = import_module("../config/constants.star")
get_constants = constants_module.get_constants

helpers_module = import_module("../utils/helpers.star")
log_info = helpers_module.log_info

constants = get_constants()

# ============================================================================
# RELAYER SERVICE BUILDER
# ============================================================================


def build_relayer_service(
    plan,
    chains,
    relay_chains,
    relayer_key,
    allow_local_sync,
    agent_image,
    configs_dir,
    checkpoints_dir,
):
    """
    Build and deploy the relayer service

    Args:
        plan: Kurtosis plan object
        chains: List of chain configurations
        relay_chains: Comma-separated list of chain names
        relayer_key: Relayer private key
        allow_local_sync: Whether to allow local checkpoint syncers
        agent_image: Docker image for the agent
        configs_dir: Configs directory artifact
    """
    # log_info("Setting up relayer for chains: {}".format(relay_chains))

    # Build environment variables
    env_vars = build_relayer_env(relay_chains, relayer_key, allow_local_sync)

    # Build command
    command = build_relayer_command(chains, relay_chains, relayer_key, allow_local_sync)

    # Add the service to the plan
    plan.add_service(
        name="relayer",
        config=ServiceConfig(
            image=agent_image,
            env_vars=env_vars,
            files={
                constants.CONFIGS_DIR: configs_dir,
                constants.VALIDATOR_CHECKPOINTS_DIR: checkpoints_dir,
            },
            cmd=["sh", "-lc", command],
        ),
    )


# ============================================================================
# ENVIRONMENT CONFIGURATION
# ============================================================================


def build_relayer_env(relay_chains, relayer_key, allow_local_sync):
    """
    Build environment variables for relayer service

    Args:
        relay_chains: Comma-separated list of chain names
        relayer_key: Relayer private key
        allow_local_sync: Whether to allow local checkpoint syncers

    Returns:
        Dictionary of environment variables
    """
    return {
        "RELAYER_KEY": relayer_key,
        "ALLOW_LOCAL": "true" if allow_local_sync else "false",
        "RELAY_CHAINS": relay_chains,
        "CONFIG_FILES": "/configs/agent-config.json",
        "RUST_LOG": "debug",
    }


# ============================================================================
# COMMAND BUILDING
# ============================================================================


def build_relayer_command(chains, relay_chains, relayer_key, allow_local_sync):
    """
    Build the relayer startup command

    Args:
        chains: List of chain configurations
        relay_chains: Comma-separated list of chain names
        relayer_key: Relayer private key
        allow_local_sync: Whether to allow local checkpoint syncers

    Returns:
        Relayer command string
    """
    # Create directories
    mkdir_cmd = "mkdir -p {} {}".format(
        constants.RELAYER_DB_DIR, constants.VALIDATOR_CHECKPOINTS_DIR
    )

    # Validate config before starting
    validate_cmd = "if [ ! -f /configs/agent-config.json ]; then echo 'ERROR: Agent config not found at /configs/agent-config.json'; exit 1; fi; if ! grep -q '\"mailbox\".*\"0x[a-fA-F0-9]' /configs/agent-config.json; then echo 'ERROR: No valid mailbox addresses found in agent config'; cat /configs/agent-config.json; exit 1; fi; echo 'Starting relayer with config:'; grep -E '\"mailbox\"|\"url\"' /configs/agent-config.json | head -10"

    # Build the complete command with address extraction and relayer execution in one shell
    full_cmd = build_full_relayer_command(
        chains, relay_chains, relayer_key, allow_local_sync
    )

    # Combine all commands - execute directly
    return "{} && {} && {}".format(mkdir_cmd, validate_cmd, full_cmd)


def build_full_relayer_command(chains, relay_chains, relayer_key, allow_local_sync):
    """
    Build the full relayer command using config file directly

    Args:
        chains: List of chain configurations
        relay_chains: Comma-separated list of chain names
        relayer_key: Relayer private key
        allow_local_sync: Whether to allow local checkpoint syncers

    Returns:
        Complete relayer command
    """
    # Use the agent config file directly
    cmd = "/app/relayer"
    cmd += " --relayChains {}".format(relay_chains)
    cmd += " --defaultSigner.key {}".format(relayer_key)
    cmd += " --db {}".format(constants.RELAYER_DB_DIR)
    cmd += " --config /configs/agent-config.json"

    # The ISM configuration will be read from the deployed contracts
    # No need to override ISM type - it will use what was deployed

    # Add local sync option if enabled
    if allow_local_sync:
        cmd += " --allowLocalCheckpointSyncers true"

    return cmd


# This function is no longer needed, replaced by build_full_relayer_command

# ============================================================================
# HEALTH CHECKS
# ============================================================================


def get_relayer_health_check():
    """
    Get health check configuration for the relayer

    Returns:
        Health check configuration
    """
    return struct(
        interval="30s",
        timeout="10s",
        retries=3,
        command=["sh", "-c", "ps aux | grep -v grep | grep relayer"],
    )
