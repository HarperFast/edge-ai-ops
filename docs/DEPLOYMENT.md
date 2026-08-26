# Deploying Harper Edge AI

This guide covers deploying to local and remote Harper instances with environment configuration, testing, and production best practices.

**For script usage details**, see [SCRIPTS.md](SCRIPTS.md).

## Quick Start

```bash
# Local development
npm run dev                      # Start Harper
npm run preload:testing          # Deploy test models
./verify.sh --full               # Verify

# Remote deployment
./deploy.sh                      # Deploy code (uses .env config)
./verify.sh --remote --full      # Verify deployment
```

**Script Details**: See [deploy.sh](SCRIPTS.md#deploysh) and [verify.sh](SCRIPTS.md#verifysh) in SCRIPTS.md.

## Prerequisites

1. **Harper CLI installed locally**

   ```bash
   npm install -g harper
   ```

2. **Remote Harper instance running**
   - Instance URL (e.g., `https://ai-ops.irjudson-ai.harperfabric.com:9925`)
   - Admin credentials (username and password)

3. **Environment configured**
   - Local `.env` file with your desired configuration
   - `MODEL_FETCH_TOKEN` set for API authentication

## Environment Configuration

Create a `.env` file in your project root with deployment configuration:

```bash
# Remote Harper Instance
DEPLOY_REMOTE_URL=https://your-instance.com:9925
DEPLOY_USERNAME=HDB_ADMIN
DEPLOY_PASSWORD=your-admin-password

# Deployment Options
DEPLOY_REPLICATED=true           # Replicate across cluster (default: true)
DEPLOY_RESTART=true              # Restart after deploy (true/false/rolling)
DEPLOY_BACKENDS=onnx,transformers  # Optional: auto-select backends

# Authentication
MODEL_FETCH_TOKEN=your-secret-token
```

**Generate a secure token:**

```bash
# macOS/Linux
openssl rand -base64 32

# Or Node.js
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
```

**For detailed configuration options**, see [Environment Variables Reference](SCRIPTS.md#environment-variables-reference) in SCRIPTS.md.

### Configure Remote .env File

Before deploying, ensure your remote instance has the proper environment configuration. Create/edit `.env` on your remote Harper instance with:

```bash
# Model Fetch System Configuration
MODEL_FETCH_TOKEN=your-secret-token-here
MODEL_FETCH_WORKER_ENABLED=true
MODEL_FETCH_MAX_CONCURRENT=3
MODEL_FETCH_POLL_INTERVAL=5000
MODEL_FETCH_MAX_FILE_SIZE=5368709120
MODEL_FETCH_MAX_RETRIES=3
MODEL_FETCH_INITIAL_RETRY_DELAY=5000

# Ollama Configuration (if using Ollama backend)
OLLAMA_HOST=http://localhost:11434
OLLAMA_DEFAULT_MODEL=llama2

# Inference Engine
MODEL_CACHE_SIZE=10

# Debug (optional)
DEBUG=false
```

**Generate a secure token:**

```bash
# On macOS/Linux:
openssl rand -base64 32

# Or use Node.js:
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
```

## Deploying

Use `deploy.sh` to deploy code to remote instances:

```bash
# Full deployment (code + replicate + restart + verify)
./deploy.sh

# Preview before deploying
./deploy.sh --dry-run
```

**For all deployment options**, see [deploy.sh](SCRIPTS.md#deploysh) in SCRIPTS.md.

## Testing Deployed System

After deployment, verify the system works end-to-end:

### Automated Verification

```bash
# Quick smoke test
./verify.sh --remote --quick

# Full verification with inference tests
./verify.sh --remote --full
```

**For verification details**, see [verify.sh](SCRIPTS.md#verifysh) in SCRIPTS.md.

### Manual Testing with harper-ai CLI

Set up your environment to point to the remote instance:

```bash
export HARPER_URL=https://your-instance.com:9926
export MODEL_FETCH_TOKEN=your-secret-token
```

**1. Fetch a model:**

```bash
harper-ai model fetch huggingface Xenova/all-MiniLM-L6-v2 \
  --modelName minilm --modelVersion v1
```

**2. Watch job progress:**

```bash
harper-ai job watch <jobId>
```

**3. Run inference:**

```bash
harper-ai model test minilm:v1 --input "Hello world"
```

**For complete harper-ai usage**, see [Model Fetch System Documentation](MODEL_FETCH_SYSTEM.md).

## Troubleshooting

### Deployment Issues

**Authentication errors:**

- Verify `DEPLOY_USERNAME` and `DEPLOY_PASSWORD` in `.env`
- Check remote instance is running: `curl https://your-instance.com:9926/Status`

**Deployment fails:**

- Check network connectivity to remote instance
- Verify admin permissions on remote Harper
- Review remote Harper logs: `harper logs target=$DEPLOY_REMOTE_URL`

**For script-specific issues**, see [Troubleshooting](SCRIPTS.md#troubleshooting) in SCRIPTS.md.

### Model Fetch Issues

**Worker not starting:**

- Verify `MODEL_FETCH_WORKER_ENABLED=true` in remote `.env`
- Check worker logs: `harper logs target=$DEPLOY_REMOTE_URL | grep ModelFetchWorker`
- Ensure schema.graphql was deployed

**Jobs failing:**

- Check remote server has internet access (for HuggingFace)
- Verify disk space in models directory
- Review job errors: `harper-ai job get <jobId>`

**Authentication errors:**

- Verify `MODEL_FETCH_TOKEN` matches on client and remote
- Check for extra whitespace in token

## Production Considerations

### Clustered Deployments

Deploy to multi-node Harper clusters:

```bash
# Deploy with cluster replication (default)
DEPLOY_REPLICATED=true ./deploy.sh

# Rolling restart for zero downtime
DEPLOY_RESTART=rolling ./deploy.sh
```

### Rollback Strategy

If deployment causes issues:

```bash
git checkout <previous-commit>
./deploy.sh
git checkout main
```

### Monitoring

Monitor remote instances:

```bash
# View logs
harper logs target=$DEPLOY_REMOTE_URL

# Check system resources
harper system_information target=$DEPLOY_REMOTE_URL

# Monitor model fetch jobs
export HARPER_URL=$DEPLOY_REMOTE_URL
harper-ai job list --status downloading
```

### Security Best Practices

1. **Never commit credentials** - Use `.env` file (already in `.gitignore`)
2. **Use strong tokens** - Generate with `openssl rand -base64 32`
3. **Secure network** - Use HTTPS for remote instances
4. **Rotate tokens** - Use different tokens for dev/staging/production
5. **Monitor access** - Review Harper logs regularly

## Next Steps

- Review [SCRIPTS.md](SCRIPTS.md) for script usage details
- See [MODEL_FETCH_SYSTEM.md](MODEL_FETCH_SYSTEM.md) for harper-ai CLI guide
- Check [BENCHMARKING.md](BENCHMARKING.md) for performance testing
- Read [PROFILE_TESTING.md](PROFILE_TESTING.md) for profile-based deployment
