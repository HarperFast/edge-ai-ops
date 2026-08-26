# Harper Edge AI - Script Reference

Four automation scripts for deployment, verification, benchmarking, and demonstration.

**For deployment guide and production setup**, see [DEPLOYMENT.md](DEPLOYMENT.md).

## Overview

| Script         | Purpose                        | When to Use                                 |
| -------------- | ------------------------------ | ------------------------------------------- |
| `deploy.sh`    | Deploy code to Harper instance | Deploying new code or configuration         |
| `verify.sh`    | Verify deployed system         | After deployment, in CI/CD, troubleshooting |
| `benchmark.sh` | Run performance benchmarks     | Comparing backends, performance analysis    |
| `demo.sh`      | Interactive demonstrations     | Showing features, learning the system       |

**All scripts use `.env` configuration** - no hardcoded URLs or credentials. See [DEPLOYMENT.md](DEPLOYMENT.md#environment-configuration) for setup.

## deploy.sh

Deploy code to local or remote Harper instances.

### Usage

```bash
# Full deployment (deploy + replicate + restart + verify)
./deploy.sh

# Deploy without restarting
./deploy.sh --no-restart

# Deploy without tests
./deploy.sh --no-tests

# Deploy to local instance (development)
./deploy.sh --local

# Preview what would be deployed
./deploy.sh --dry-run

# Check deployment status
./deploy.sh --status
```

### Configuration (.env)

```bash
# Remote instance
DEPLOY_REMOTE_HOST=ai-ops.example.com
DEPLOY_REMOTE_PORT=9925
DEPLOY_REMOTE_URL=https://ai-ops.example.com:9925
DEPLOY_USERNAME=HDB_ADMIN
DEPLOY_PASSWORD=your-password

# Deployment options
DEPLOY_REPLICATED=true           # Replicate across cluster
DEPLOY_RESTART=true              # Restart after deploy
DEPLOY_BACKENDS=onnx,transformers  # Auto-select backends (skip interactive)

# Authentication
MODEL_FETCH_TOKEN=your-token
```

**Key Features**: Backend selection, size optimization (<800MB check), cluster replication, automatic verification, dry-run mode.

**For deployment workflow details**, see [DEPLOYMENT.md](DEPLOYMENT.md).

## verify.sh

Verify a deployed running system (integration/smoke testing).

### Usage

```bash
# Verify local instance
./verify.sh

# Quick smoke test
./verify.sh --quick

# Full verification (includes inference tests)
./verify.sh --full

# Verify remote instance
./verify.sh --remote

# Verify with specific profile
./verify.sh --profile testing --full
```

### Configuration (.env)

```bash
# Local instance (default)
HARPER_URL=http://localhost:9926

# Remote instance
DEPLOY_REMOTE_URL=https://your-instance.com:9926
DEPLOY_USERNAME=HDB_ADMIN
DEPLOY_PASSWORD=your-password
MODEL_FETCH_TOKEN=your-token

# Backend availability
OLLAMA_HOST=http://localhost:11434

# Test configuration
TEST_PROFILE=testing  # Which profile to test
```

### Deployment Scenarios

verify.sh works with three deployment scenarios:

**1. Local dev mode (`npm run dev`)**

- App runs from project directory with `DEV_MODE=true`
- Models can be loaded from local files or fetched from HuggingFace
- Target: `http://localhost:9926` (default)
- Example: `./verify.sh --deploy --full`

**2. Local deployed (`harper deploy` to localhost)**

- App deployed to `~/hdb/components/edge-ai-ops/`
- Models must be fetched from HuggingFace (no local files available)
- Target: `http://localhost:9926` (default)
- Example: `./verify.sh --deploy --full`

**3. Remote deployed (`harper deploy` to remote host)**

- App deployed to remote HarperDB instance
- Models must be fetched from HuggingFace
- Target: `DEPLOY_REMOTE_URL` from .env
- Example: `./verify.sh --remote --deploy --full`

**Key differences**:

- `--remote` flag only changes the target URL (uses `DEPLOY_REMOTE_URL` instead of `HARPER_URL`)
- `--deploy` flag fetches and deploys profile models before verification
- In dev mode, models can use local files; in deployed scenarios, models must come from remote sources

### Verification Levels

**Quick** (`--quick`):

- Health check
- API endpoint accessibility
- ~5 seconds

**Standard** (default):

- Health check
- API endpoints
- Deployed models check
- Backend availability
- ~15 seconds

**Full** (`--full`):

- All standard checks
- Inference tests
- Profile-based integration tests
- ~60 seconds

**CI/CD Integration**: Use `./verify.sh --remote --full` in GitHub Actions with secrets for DEPLOY_REMOTE_URL, DEPLOY_USERNAME, and DEPLOY_PASSWORD.

## benchmark.sh

Run performance benchmarks on deployed models.

### Usage

```bash
# Run all benchmarks
./benchmark.sh

# Benchmark specific equivalence group
./benchmark.sh --group embeddings-384

# Custom iteration count
./benchmark.sh --iterations 1000

# Deploy benchmarking profile and run benchmarks
./benchmark.sh --deploy

# Benchmark remote instance
./benchmark.sh --remote --iterations 500
```

### Configuration (.env)

```bash
# Target instance
HARPER_URL=http://localhost:9926                           # Local
DEPLOY_REMOTE_URL=https://your-instance.com:9926          # Remote

# Benchmark settings
BENCHMARK_ITERATIONS=100        # Default iteration count
BENCHMARK_GROUP=embeddings-384  # Specific group to benchmark
BENCHMARK_PROFILE=benchmarking  # Profile to use

# Backend availability
OLLAMA_HOST=http://localhost:11434
```

**Equivalence Groups**: `embeddings-384` (ONNX vs Transformers.js), `embeddings-768` (Ollama vs Transformers.js)

**Output**: Results saved to `benchmark-*.json` with latency metrics (avg, p50, p95, p99), error rates, and winner determination.

**For benchmarking details**, see [BENCHMARKING.md](BENCHMARKING.md).

**Setup**: Deploy benchmarking profile first with `npm run preload:benchmarking`

## demo.sh

Run interactive demonstrations of model inference.

### Usage

```bash
# Run all demos locally
./demo.sh

# Demo remote instance
./demo.sh --remote

# Use specific profile
./demo.sh --profile minimal
```

### Configuration (.env)

```bash
# Local instance (default)
HARPER_URL=http://localhost:9926

# Remote instance
DEPLOY_REMOTE_URL=https://your-instance.com:9926

# Demo settings
DEMO_PROFILE=development  # Profile to use for demo
```

**Demo Sequence**: Health check → Model inventory → Text embedding inference → Backend demos → Metrics display

## Common Workflows

**Local Development**: `npm run dev` → `npm run preload:testing` → `./verify.sh --full` → `./demo.sh`

**Remote Deployment**: `./deploy.sh` → `./verify.sh --remote --full` → `./demo.sh --remote`

**Performance Analysis**: `npm run preload:benchmarking` → `./benchmark.sh --iterations 1000` → View results in `benchmark-*.json`

**CI/CD Pipeline**: `./deploy.sh --no-tests` → `./verify.sh --remote --full` → `./benchmark.sh --remote --iterations 50`

**For complete deployment guide**, see [DEPLOYMENT.md](DEPLOYMENT.md).

## Environment Variables Reference

### Required

- `DEPLOY_PASSWORD` or `CLI_TARGET_PASSWORD`: Harper admin password

### Optional

| Variable               | Default                  | Purpose                   |
| ---------------------- | ------------------------ | ------------------------- |
| `HARPER_URL`           | `http://localhost:9926`  | Local Harper URL          |
| `DEPLOY_REMOTE_URL`    | -                        | Remote Harper URL         |
| `DEPLOY_USERNAME`      | `HDB_ADMIN`              | Harper admin username     |
| `CLI_TARGET_USERNAME`  | `$DEPLOY_USERNAME`       | Override username         |
| `CLI_TARGET_PASSWORD`  | `$DEPLOY_PASSWORD`       | Override password         |
| `MODEL_FETCH_TOKEN`    | -                        | Token for model fetch API |
| `OLLAMA_HOST`          | `http://localhost:11434` | Ollama service URL        |
| `TEST_PROFILE`         | `testing`                | Profile for verification  |
| `BENCHMARK_PROFILE`    | `benchmarking`           | Profile for benchmarks    |
| `BENCHMARK_ITERATIONS` | `100`                    | Benchmark iterations      |
| `DEMO_PROFILE`         | `development`            | Profile for demos         |

## Troubleshooting

**"Cannot connect to Harper"**: Check if running with `curl http://localhost:9926/Status`

**"No models deployed"**: Deploy with `npm run preload:testing` or specific profile

**"Deployment size exceeds 800MB"**: Select fewer backends (automatic prompt) or set `DEPLOY_BACKENDS=transformers` in .env

**"Ollama not available"**: Start Ollama (`ollama serve`) or set `OLLAMA_HOST` in .env

**For deployment troubleshooting**, see [DEPLOYMENT.md](DEPLOYMENT.md#troubleshooting).

## Best Practices

1. **Always use .env** - Never hardcode credentials
2. **Verify after deploy** - Run `./verify.sh --remote --full`
3. **Benchmark before production** - Use `./benchmark.sh` to choose best backend
4. **Use profiles** - Leverage model profiles for consistent deployments
5. **Check script help** - All scripts support `--help`

## Dependencies

**All scripts**: bash 4.0+, curl, jq, Node.js 18+

**verify.sh**: Node.js test runner, integration tests in `tests/integration/`

## Next Steps

- Configure `.env` (see [DEPLOYMENT.md](DEPLOYMENT.md#environment-configuration))
- Run `./verify.sh --quick` to check local setup
- See [DEPLOYMENT.md](DEPLOYMENT.md) for deployment workflow
- See [BENCHMARKING.md](BENCHMARKING.md) for performance testing
- See [PROFILE_TESTING.md](PROFILE_TESTING.md) for profile management
