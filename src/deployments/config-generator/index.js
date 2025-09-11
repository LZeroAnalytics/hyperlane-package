#!/usr/bin/env node
/**
 * Agent Config Generator
 * Generates agent configuration for Hyperlane validators and relayers
 * based on deployed contract addresses and chain configurations
 */

import fs from 'fs';
import path from 'path';
import https from 'https';
import YAML from 'yaml';

// ============================================================================
// CONSTANTS
// ============================================================================

const REGISTRY_BASE_URL = 'https://raw.githubusercontent.com/hyperlane-xyz/hyperlane-registry/main/chains';
const CONFIGS_DIR = '/configs';
const REGISTRY_DIR = '/configs/registry/chains';
const DEFAULT_TIMEOUT = 5000;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Logger utility with different log levels
 */
const logger = {
  info: (msg) => console.log(`[INFO] ${msg}`),
  error: (msg) => console.error(`[ERROR] ${msg}`),
  debug: (msg) => process.env.DEBUG && console.log(`[DEBUG] ${msg}`),
};

/**
 * Safely read and parse a file
 */
function readFile(filePath, format = 'json') {
  try {
    if (!fs.existsSync(filePath)) {
      return null;
    }
    const content = fs.readFileSync(filePath, 'utf8');
    return format === 'yaml' ? YAML.parse(content) : JSON.parse(content);
  } catch (error) {
    logger.debug(`Failed to read ${filePath}: ${error.message}`);
    return null;
  }
}

/**
 * Write JSON output with proper formatting
 */
function writeJsonFile(filePath, data) {
  try {
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
    logger.info(`Successfully wrote config to ${filePath}`);
  } catch (error) {
    logger.error(`Failed to write to ${filePath}: ${error.message}`);
    throw error;
  }
}

/**
 * Parse command line arguments or configuration file
 */
function parseInput(inputPath) {
  const raw = fs.readFileSync(path.resolve(inputPath), 'utf8');
  
  // Try YAML first, then JSON
  try {
    return YAML.parse(raw);
  } catch (yamlError) {
    try {
      return JSON.parse(raw);
    } catch (jsonError) {
      throw new Error('Failed to parse input as YAML or JSON');
    }
  }
}

// ============================================================================
// NETWORK OPERATIONS
// ============================================================================

/**
 * Fetch YAML configuration from a URL with timeout and error handling
 */
function fetchYaml(url) {
  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      logger.debug(`Request to ${url} timed out`);
      resolve(null);
    }, DEFAULT_TIMEOUT);

    https
      .get(url, (res) => {
        clearTimeout(timeout);
        
        if (res.statusCode !== 200) {
          res.resume();
          logger.debug(`Request to ${url} returned status ${res.statusCode}`);
          return resolve(null);
        }
        
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          try {
            resolve(YAML.parse(data));
          } catch (error) {
            logger.debug(`Failed to parse YAML from ${url}: ${error.message}`);
            resolve(null);
          }
        });
      })
      .on('error', (error) => {
        clearTimeout(timeout);
        logger.debug(`Request to ${url} failed: ${error.message}`);
        resolve(null);
      });
  });
}

// ============================================================================
// CORE ADDRESS RESOLUTION
// ============================================================================

/**
 * Read core contract addresses from various possible locations
 */
function readCoreAddresses(chainName) {
  const addresses = {
    mailbox: '',
    igp: '',
    validatorAnnounce: '',
    ism: '',
    merkleTreeHook: '',
  };

  // Try JSON format in configs directory
  const jsonPath = path.resolve(CONFIGS_DIR, `addresses-${chainName}.json`);
  const jsonData = readFile(jsonPath, 'json');
  
  if (jsonData) {
    addresses.mailbox = jsonData.mailbox || jsonData.Mailbox || '';
    addresses.igp = jsonData.interchainGasPaymaster || jsonData.igp || '';
    addresses.validatorAnnounce = jsonData.validatorAnnounce || jsonData.ValidatorAnnounce || '';
    addresses.ism = jsonData.interchainSecurityModule || jsonData.defaultIsm || jsonData.ism || '';
    addresses.merkleTreeHook = jsonData.merkleTreeHook || jsonData.MerkleTreeHook || '';
    
    if (addresses.mailbox) {
      logger.debug(`Found addresses for ${chainName} in JSON format`);
      return addresses;
    }
  }

  // Try YAML format in registry directory
  const yamlPath = path.resolve(REGISTRY_DIR, chainName, 'addresses.yaml');
  const yamlData = readFile(yamlPath, 'yaml');
  
  if (yamlData) {
    addresses.mailbox = yamlData.mailbox || '';
    addresses.igp = yamlData.interchainGasPaymaster || '';
    addresses.validatorAnnounce = yamlData.validatorAnnounce || '';
    // Check for ISM in multiple possible fields
    addresses.ism = yamlData.defaultIsm || yamlData.interchainSecurityModule || yamlData.ism || '';
    addresses.merkleTreeHook = yamlData.merkleTreeHook || '';
    
    if (addresses.mailbox) {
      logger.debug(`Found addresses for ${chainName} in YAML format`);
      if (addresses.ism) {
        logger.debug(`Found ISM address for ${chainName}: ${addresses.ism}`);
      }
      if (addresses.merkleTreeHook) {
        logger.debug(`Found merkleTreeHook address for ${chainName}: ${addresses.merkleTreeHook}`);
      }
      return addresses;
    }
  }

  return addresses;
}

/**
 * Fetch addresses from public registry if enabled
 */
async function fetchPublicAddresses(chainName) {
  if (process.env.ENABLE_PUBLIC_FALLBACK !== 'true') {
    return null;
  }

  const url = `${REGISTRY_BASE_URL}/${chainName}/addresses.yaml`;
  logger.debug(`Fetching public registry for ${chainName} from ${url}`);
  
  const doc = await fetchYaml(url);
  
  if (doc && typeof doc === 'object') {
    return {
      mailbox: doc.mailbox || '',
      igp: doc.interchainGasPaymaster || '',
      validatorAnnounce: doc.validatorAnnounce || '',
      ism: doc.interchainSecurityModule || '',
      merkleTreeHook: doc.merkleTreeHook || '',
    };
  }
  
  return null;
}

// ============================================================================
// CONFIGURATION BUILDER
// ============================================================================

/**
 * Build configuration for a single chain
 */
async function buildChainConfig(chain) {
  const config = {
    connection: { url: chain.rpc_url },
    mailbox: '',
    igp: '',
    validatorAnnounce: '',
    ism: '',
    merkleTreeHook: '',
  };

  // Start with existing addresses from input
  const existing = chain.existing_addresses || {};
  config.mailbox = existing.mailbox || '';
  config.igp = existing.igp || '';
  config.validatorAnnounce = existing.validatorAnnounce || '';
  config.ism = existing.ism || '';
  config.merkleTreeHook = existing.merkleTreeHook || '';

  // Override with deployed addresses if available
  const deployed = readCoreAddresses(chain.name);
  config.mailbox = deployed.mailbox || config.mailbox;
  config.igp = deployed.igp || config.igp;
  config.validatorAnnounce = deployed.validatorAnnounce || config.validatorAnnounce;
  config.ism = deployed.ism || config.ism;
  config.merkleTreeHook = deployed.merkleTreeHook || config.merkleTreeHook;

  // Check if we need to fetch from public registry
  const needsPublic = !config.mailbox || !config.igp || !config.validatorAnnounce || !config.ism;
  
  if (needsPublic) {
    const publicAddresses = await fetchPublicAddresses(chain.name);
    if (publicAddresses) {
      config.mailbox = config.mailbox || publicAddresses.mailbox;
      config.igp = config.igp || publicAddresses.igp;
      config.validatorAnnounce = config.validatorAnnounce || publicAddresses.validatorAnnounce;
      config.ism = config.ism || publicAddresses.ism;
      config.merkleTreeHook = config.merkleTreeHook || publicAddresses.merkleTreeHook;
    }
  }

  // Log missing addresses
  if (!config.mailbox) {
    logger.error(`Missing mailbox address for ${chain.name}`);
  }
  if (!config.igp) {
    logger.error(`Missing IGP address for ${chain.name}`);
  }

  return config;
}

/**
 * Build complete agent configuration
 */
async function buildAgentConfig(args) {
  const chains = args.chains || [];
  const config = { 
    chains: {},
    defaultism: {},
    // Add validator configuration if validators are present
    validator: {},
    checkpointSyncer: {},
    // Add ISM configuration
    ism: {}
  };

  logger.info(`Building agent config for ${chains.length} chains`);

  // Process default ISM configuration if provided
  if (args.default_ism) {
    logger.info(`Processing default ISM configuration: ${JSON.stringify(args.default_ism)}`);
    config.ism = args.default_ism;
    
    // Add to defaultism for backwards compatibility
    if (args.default_ism.type && args.default_ism.validators && args.default_ism.threshold) {
      for (const chain of chains) {
        config.defaultism[chain.name] = {
          type: args.default_ism.type,
          validators: args.default_ism.validators,
          threshold: args.default_ism.threshold
        };
        logger.debug(`Set default ISM for ${chain.name}: ${JSON.stringify(config.defaultism[chain.name])}`);
      }
    }
  }

  // Process each chain
  for (const chain of chains) {
    logger.debug(`Processing chain: ${chain.name}`);
    const chainConfig = await buildChainConfig(chain);
    config.chains[chain.name] = chainConfig;
    
    // Add ISM to defaultism configuration for relayer
    if (chainConfig.ism) {
      config.defaultism[chain.name] = chainConfig.ism;
      logger.debug(`Added ISM for ${chain.name} to defaultism config: ${chainConfig.ism}`);
    }
  }

  // Add validator configuration if validators are defined
  if (args.validators && args.validators.length > 0) {
    // Use the first validator's configuration as default
    const validator = args.validators[0];
    config.validator = {
      type: "hexKey",
      key: validator.signing_key || process.env.VALIDATOR_KEY || ""
    };

    // Configure checkpoint syncer
    const syncerConfig = validator.checkpoint_syncer || {};
    if (syncerConfig.type === "s3") {
      config.checkpointSyncer = {
        type: "s3",
        bucket: syncerConfig.params?.bucket || "",
        region: syncerConfig.params?.region || "",
        prefix: syncerConfig.params?.prefix || ""
      };
    } else {
      // Default to localStorage
      config.checkpointSyncer = {
        type: "localStorage",
        path: syncerConfig.params?.path || "/data/validator-checkpoints"
      };
    }

    // Set origin chain name if specified
    if (validator.chain) {
      config.originChainName = validator.chain;
    }
  } else {
    // Provide minimal validator config to prevent errors
    config.validator = {
      type: "hexKey",
      key: process.env.VALIDATOR_KEY || ""
    };
    config.checkpointSyncer = {
      type: "localStorage",
      path: "/data/validator-checkpoints"
    };
  }

  return config;
}

// ============================================================================
// MAIN EXECUTION
// ============================================================================

async function main() {
  const [,, inputPath, outputPath] = process.argv;

  // Validate arguments
  if (!inputPath || !outputPath) {
    console.error('Usage: agent-config-gen <input-args.(yaml|json)> <output-agent-config.json>');
    process.exit(1);
  }

  try {
    // Parse input
    logger.info(`Reading configuration from ${inputPath}`);
    const args = parseInput(inputPath);

    // Build configuration
    const config = await buildAgentConfig(args);

    // Write output
    writeJsonFile(path.resolve(outputPath), config);
    
    logger.info('Agent configuration generated successfully');
  } catch (error) {
    logger.error(`Failed to generate agent config: ${error.message}`);
    
    // Write empty config as fallback
    try {
      writeJsonFile(path.resolve(outputPath), { chains: {} });
    } catch (writeError) {
      logger.error(`Failed to write fallback config: ${writeError.message}`);
    }
    
    process.exit(1);
  }
}

// Run the main function
main().catch((error) => {
  logger.error(`Unexpected error: ${error.message}`);
  process.exit(1);
});