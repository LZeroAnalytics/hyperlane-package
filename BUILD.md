# Building Hyperlane Package Docker Images

## Prerequisites

- Docker installed and running
- Node.js 20+ (for local testing)
- Foundry toolkit (for cast commands)

## Docker Images

This package uses two main Docker images:

1. **hyperlane-cli** - Contains Hyperlane CLI and deployment scripts
2. **agent-config-gen** - Generates agent configuration from deployed contracts

## Versioning Strategy

We use semantic versioning for Docker images:
- **v1.0.0** - Current stable version
- **latest** - Points to the most recent stable version

The Hyperlane CLI npm package version is pinned to **16.2.0** for stability.

## Building Images

### Quick Build (Recommended)

```bash
# Build all images with proper versions
./build.sh
```

### Manual Build

```bash
# Build hyperlane-cli with specific version
docker build \
  -t hyperlane-cli:v1.0.0 \
  -t hyperlane-cli:latest \
  --build-arg CLI_VERSION=16.2.0 \
  -f src/deployments/hyperlane-deployer/Dockerfile \
  src/deployments/hyperlane-deployer/

# Build agent-config-gen
docker build \
  -t agent-config-gen:v1.0.0 \
  -t agent-config-gen:latest \
  -f src/deployments/config-generator/Dockerfile \
  src/deployments/config-generator/
```

## Version Configuration

In your deployment config (`config/core-contracts-n-infra.yaml`):

```yaml
global:
  registry_mode: local
  agent_image_tag: agents-v1.4.0  # Hyperlane agent version
  cli_version: 16.2.0              # Hyperlane CLI npm version
```

## Image Contents

### hyperlane-cli:v1.0.0

- Base: node:20-bullseye
- Includes:
  - Hyperlane CLI v16.2.0
  - Foundry (cast, forge, anvil)
  - Deployment scripts
  - Common utilities

### agent-config-gen:v1.0.0

- Base: node:20-bullseye
- Includes:
  - Node.js config generator
  - YAML parser
  - Registry integration

## Troubleshooting

### Build Fails

If the build fails, check:
1. Docker daemon is running
2. Sufficient disk space
3. Network connectivity for npm packages

### Wrong Version Used

Ensure you've:
1. Built images with `./build.sh`
2. Updated config files to use correct versions
3. Removed old images: `docker rmi hyperlane-cli:old-tag`

## CI/CD Integration

For CI/CD pipelines, tag images with commit SHA:

```bash
VERSION="v1.0.0-$(git rev-parse --short HEAD)"
docker build -t hyperlane-cli:${VERSION} ...
```

## Updates

When updating Hyperlane CLI version:

1. Update `CLI_VERSION` in `src/deployments/hyperlane-deployer/Dockerfile`
2. Update `cli_version` in config files
3. Rebuild images with `./build.sh`
4. Test deployment thoroughly

## Security Notes

- Never use `latest` tags in production
- Pin all dependency versions
- Scan images for vulnerabilities: `docker scan hyperlane-cli:v1.0.0`
- Use minimal base images when possible