def run(plan):
    # Test capturing addresses from a mock YAML output
    yaml_output = """domainRoutingIsmFactory: "0x24388D9D59963f255F01881De7557713CCE4F785"
interchainAccountRouter: "0x792A78aE9fA89C009B82c58A6322a5c49787468e"
mailbox: "0x96E13E8D37aD1f0420d82A38A75d28A59284fF5e"
merkleTreeHook: "0x919e0625a92105ddE5c3B66FE8568d4B75914356"
proxyAdmin: "0x55d1545F4689E497467C1e2e75eFb01cBbF52b6c"
staticAggregationHookFactory: "0xBf5EA2d51403aA5D40B84ed77A1E2cF63c186e56"
staticAggregationIsmFactory: "0x014C607C5d97DC931a97FA25A4B106810b09944f"
staticMerkleRootMultisigIsmFactory: "0x8eB0E41F4d19DEbf310335583F89Ff2355028603"
staticMerkleRootWeightedMultisigIsmFactory: "0x097C23cbCeb8e8B6C0400D8689eD4Cd33Bce09CB"
staticMessageIdMultisigIsmFactory: "0x94c5533fE70b344A3F9EE7403b306d0b822f6dDc"
staticMessageIdWeightedMultisigIsmFactory: "0xf0CAcd3F79851fB0d640D3Ae06FCdD18EFBdcff3"
testRecipient: "0x91B9c487f8c7a256906987e57e6c75F3eaB3cb6e"
validatorAnnounce: "0x93496Cf37Ec7F5B97249501f4d4E08892846b2af"
"""
    
    addresses = {}
    lines = yaml_output.split("\n")
    for line in lines:
        if ": " in line and not line.startswith("#"):
            parts = line.split(": ")
            if len(parts) == 2:
                key = parts[0].strip()
                value = parts[1].strip().strip('"')
                if key and value:
                    addresses[key] = value
    
    plan.print("Parsed addresses: {}".format(addresses))
    plan.print("Number of addresses: {}".format(len(addresses)))
    
    return struct(
        success=True,
        addresses=addresses,
        count=len(addresses)
    )