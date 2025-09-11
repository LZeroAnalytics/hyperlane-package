# ISM Configuration Module - Handles ISM type selection and configuration generation

helpers_module = import_module("../utils/helpers.star")
safe_get = helpers_module.safe_get

# ============================================================================
# ISM TYPE CONSTANTS
# ============================================================================

ISM_TYPE_TRUSTED_RELAYER = "trustedRelayer"
ISM_TYPE_MULTISIG = "multisig"
ISM_TYPE_AGGREGATION = "aggregation"
ISM_TYPE_ROUTING = "routing"
ISM_TYPE_MERKLE_ROOT = "merkleRoot"
ISM_TYPE_MESSAGE_ID_MULTISIG = "messageIdMultisig"
ISM_TYPE_PAUSABLE = "pausable"

# ============================================================================
# ISM CONFIGURATION BUILDERS
# ============================================================================


def build_ism_config(ism_settings, deployer_address):
    """
    Build ISM configuration based on type

    Args:
        ism_settings: ISM configuration from user
        deployer_address: Default address to use if not specified

    Returns:
        ISM configuration dictionary for deployment
    """
    ism_type = safe_get(ism_settings, "type", ISM_TYPE_TRUSTED_RELAYER)

    if ism_type == ISM_TYPE_TRUSTED_RELAYER:
        return build_trusted_relayer_ism(ism_settings, deployer_address)
    elif ism_type == ISM_TYPE_MULTISIG:
        return build_multisig_ism(ism_settings, deployer_address)
    elif ism_type == ISM_TYPE_AGGREGATION:
        return build_aggregation_ism(ism_settings, deployer_address)
    elif ism_type == ISM_TYPE_ROUTING:
        return build_routing_ism(ism_settings, deployer_address)
    elif ism_type == ISM_TYPE_MERKLE_ROOT:
        return build_merkle_root_ism(ism_settings, deployer_address)
    elif ism_type == ISM_TYPE_MESSAGE_ID_MULTISIG:
        return build_message_id_multisig_ism(ism_settings, deployer_address)
    elif ism_type == ISM_TYPE_PAUSABLE:
        return build_pausable_ism(ism_settings, deployer_address)
    else:
        # Default to trusted relayer for unknown types
        return build_trusted_relayer_ism(ism_settings, deployer_address)


def build_trusted_relayer_ism(ism_settings, deployer_address):
    """
    Build trusted relayer ISM configuration

    Args:
        ism_settings: ISM configuration
        deployer_address: Default relayer address

    Returns:
        Trusted relayer ISM configuration
    """
    relayer = safe_get(ism_settings, "relayer", deployer_address)

    return {
        "type": "trustedRelayerIsm",
        "relayer": relayer if relayer else deployer_address,
    }


def build_multisig_ism(ism_settings, deployer_address):
    """
    Build multisig ISM configuration

    Args:
        ism_settings: ISM configuration
        deployer_address: Default validator address

    Returns:
        Multisig ISM configuration
    """
    validators = safe_get(ism_settings, "validators", [])
    threshold = safe_get(ism_settings, "threshold", 1)

    # If no validators specified, use deployer as single validator
    if len(validators) == 0:
        validators = [deployer_address]

    return {"type": "multisig", "validators": validators, "threshold": threshold}


def build_aggregation_ism(ism_settings, deployer_address):
    """
    Build aggregation ISM configuration

    Args:
        ism_settings: ISM configuration
        deployer_address: Default address for sub-ISMs

    Returns:
        Aggregation ISM configuration
    """
    modules = safe_get(ism_settings, "modules", [])
    threshold = safe_get(ism_settings, "threshold", 1)

    # Build each sub-module
    built_modules = []
    for module in modules:
        built_modules.append(build_ism_config(module, deployer_address))

    # If no modules specified, create a default setup
    if len(built_modules) == 0:
        built_modules = [build_trusted_relayer_ism({}, deployer_address)]

    return {"type": "aggregation", "modules": built_modules, "threshold": threshold}


def build_routing_ism(ism_settings, deployer_address):
    """
    Build routing ISM configuration

    Args:
        ism_settings: ISM configuration
        deployer_address: Default address

    Returns:
        Routing ISM configuration
    """
    domains = safe_get(ism_settings, "domains", {})

    # Build ISM for each domain
    built_domains = {}
    for domain, ism_config in domains.items():
        built_domains[domain] = build_ism_config(ism_config, deployer_address)

    return {
        "type": "routing",
        "owner": safe_get(ism_settings, "owner", deployer_address),
        "domains": built_domains,
    }


def build_merkle_root_ism(ism_settings, deployer_address):
    """
    Build merkle root ISM configuration

    Args:
        ism_settings: ISM configuration
        deployer_address: Default validator

    Returns:
        Merkle root ISM configuration
    """
    validators = safe_get(ism_settings, "validators", [deployer_address])
    threshold = safe_get(ism_settings, "threshold", 1)

    return {
        "type": "merkleRootMultisig",
        "validators": validators,
        "threshold": threshold,
    }


def build_message_id_multisig_ism(ism_settings, deployer_address):
    """
    Build message ID multisig ISM configuration

    Args:
        ism_settings: ISM configuration
        deployer_address: Default validator

    Returns:
        Message ID multisig ISM configuration
    """
    validators = safe_get(ism_settings, "validators", [deployer_address])
    threshold = safe_get(ism_settings, "threshold", 1)

    return {
        "type": "messageIdMultisig",
        "validators": validators,
        "threshold": threshold,
    }


def build_pausable_ism(ism_settings, deployer_address):
    """
    Build pausable ISM configuration

    Args:
        ism_settings: ISM configuration
        deployer_address: Default owner/pauser

    Returns:
        Pausable ISM configuration
    """
    owner = safe_get(ism_settings, "owner", deployer_address)
    pauser = safe_get(ism_settings, "pauser", owner)

    return {"type": "pausable", "owner": owner, "pauser": pauser}


# ============================================================================
# ISM VALIDATION
# ============================================================================


def validate_ism_config(ism_settings):
    """
    Validate ISM configuration

    Args:
        ism_settings: ISM configuration to validate

    Returns:
        True if valid, fails with error if not
    """
    ism_type = safe_get(ism_settings, "type", ISM_TYPE_TRUSTED_RELAYER)

    if ism_type == ISM_TYPE_MULTISIG:
        validators = safe_get(ism_settings, "validators", [])
        threshold = safe_get(ism_settings, "threshold", 1)

        if threshold > len(validators):
            fail(
                "ISM threshold ({}) cannot exceed number of validators ({})".format(
                    threshold, len(validators)
                )
            )

        if threshold < 1:
            fail("ISM threshold must be at least 1")

    elif ism_type == ISM_TYPE_AGGREGATION:
        modules = safe_get(ism_settings, "modules", [])
        threshold = safe_get(ism_settings, "threshold", 1)

        if threshold > len(modules):
            fail(
                "Aggregation threshold ({}) cannot exceed number of modules ({})".format(
                    threshold, len(modules)
                )
            )

    return True


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================


def get_required_services(ism_type):
    """
    Determine which services are required for a given ISM type

    Args:
        ism_type: The ISM type

    Returns:
        Dictionary indicating which services are needed
    """
    services = {
        "validators": False,
        "relayer": True,  # Always need relayer
    }

    # ISM types that require validators
    validator_isms = [
        ISM_TYPE_MULTISIG,
        ISM_TYPE_MERKLE_ROOT,
        ISM_TYPE_MESSAGE_ID_MULTISIG,
    ]

    if ism_type in validator_isms:
        services["validators"] = True

    # Aggregation and routing might need validators depending on sub-modules
    # For simplicity, enable validators if these are used
    if ism_type in [ISM_TYPE_AGGREGATION, ISM_TYPE_ROUTING]:
        services["validators"] = True

    return services