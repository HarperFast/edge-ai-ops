# Harper Edge AI

**Production-ready multi-backend ML inference engine for Harper.**

Run ONNX, TensorFlow.js, Transformers.js, and Ollama models with unified API, async model fetching, profile-based management, and performance benchmarking.

---

## What It Does

Harper Edge AI is a complete inference engine that makes it easy to deploy and run ML models in production:

- **Multi-Backend Support** - Use the best runtime for each model (ONNX, TensorFlow.js, Transformers.js, Ollama)
- **Async Model Fetching** - Download models from HuggingFace, HTTP, or filesystem with progress tracking
- **Profile Management** - Deploy model sets with simple configuration files
- **Performance Benchmarking** - Compare equivalent models across backends
- **Deployment Automation** - Scripts for deploy, verify, benchmark, and demo
- **Production Ready** - Full test coverage, pre-commit hooks, comprehensive docs

---

## Quick Start (5 Minutes)

### Prerequisites

```bash
# Node.js 18+
node --version

# Harper 4.0+
# Install: https://docs.harperdb.io/docs/getting-started/installation
harper --version

# Ollama (optional, for LLM inference)
# Download: https://ollama.ai/
ollama --version
```

### Installation

```bash
git clone https://github.com/HarperFast/edge-ai-ops.git
cd harper-edge-ai-example
npm install

# Start Harper server
npm run dev              # Server at http://localhost:9926

# Load test models
npm run preload:testing

# Run tests
npm test
```

### First Inference

```bash
# Run a quick demo
./demo.sh

# Or make a direct API call
curl -X POST http://localhost:9926/Predict \
  -H "Content-Type: application/json" \
  -d '{
    "modelName": "test-transformers-embedding",
    "modelVersion": "v1",
    "inputs": {"text": "This is a test"}
  }'
```

---

## Core Features

### 1. Multi-Backend Inference

Run models on the optimal backend for your use case:

| Backend             | Use Cases                                | Status   | Package                     |
| ------------------- | ---------------------------------------- | -------- | --------------------------- |
| **ONNX Runtime**    | Optimized production models              | ✅ Ready | onnxruntime-node 1.20.1     |
| **TensorFlow.js**   | Universal Sentence Encoder, Keras models | ✅ Ready | @tensorflow/tfjs-node       |
| **Transformers.js** | Hugging Face models (WASM)               | ✅ Ready | @xenova/transformers 2.17.2 |
| **Ollama**          | Local LLMs (chat, embeddings)            | ✅ Ready | External service            |

**Features:**

- Automatic backend routing based on framework
- LRU model caching with configurable size
- Unified prediction API
- File-backed blob storage for large models (86MB+)

### 2. Model Fetch System

Download models from multiple sources with full job tracking:

```bash
# Fetch from HuggingFace
harper-ai fetch huggingface Xenova/all-MiniLM-L6-v2 \
  --name minilm --version v1 --framework transformers

# Check job status
harper-ai jobs --status pending

# View model inventory
harper-ai models
```

**Capabilities:**

- Multi-source downloads (HuggingFace, HTTP URLs, filesystem)
- Async job queue with real-time progress
- Retry logic with exponential backoff
- Optional token authentication
- Complete CLI tool

**Full Guide:** [Model Fetch System Documentation](docs/MODEL_FETCH_SYSTEM.md)

### 3. Profile-Based Model Management

Deploy model sets with configuration files:

```json
// profiles/testing.json
{
	"name": "testing",
	"description": "One model per backend for CI/CD",
	"models": [
		{
			"modelName": "test-transformers-embedding",
			"framework": "transformers",
			"modelBlob": {
				"modelName": "Xenova/all-MiniLM-L6-v2",
				"taskType": "feature-extraction"
			}
		}
	]
}
```

```bash
# Deploy testing profile
npm run preload:testing

# Deploy benchmarking profile
npm run preload:benchmarking

# Deploy custom profile
node scripts/preload-models.js --profile production
```

**Available Profiles:**

- `testing` - One model per backend for CI/CD
- `benchmarking` - Equivalence groups for performance comparison
- `development` - Full test suite
- `production` - Production-ready models only
- `minimal` - Single model for quick tests

**Full Guide:** [Profile Testing Documentation](docs/PROFILE_TESTING.md)

### 4. Performance Benchmarking

Compare equivalent models across backends to optimize deployment:

```bash
# Deploy benchmarking models
npm run preload:benchmarking

# Run benchmarks
./benchmark.sh --iterations 100

# View results
cat benchmark-*.json | jq '.winner'
```

**Capabilities:**

- Cross-backend comparison (ONNX vs TensorFlow vs Transformers.js vs Ollama)
- Equivalence group validation (compatible output dimensions)
- Statistical metrics (avg, p50, p95, p99 latency, error rates)
- Historical benchmark tracking
- Automated test data generation

**Full Guide:** [Benchmarking Documentation](docs/BENCHMARKING.md)

### 5. Deployment Automation

Four focused scripts for complete deployment lifecycle:

| Script         | Purpose                        | Example                           |
| -------------- | ------------------------------ | --------------------------------- |
| `deploy.sh`    | Deploy code to Harper instance | `./deploy.sh --remote`            |
| `verify.sh`    | Verify deployed system         | `./verify.sh --full`              |
| `benchmark.sh` | Run performance benchmarks     | `./benchmark.sh --iterations 500` |
| `demo.sh`      | Interactive demonstrations     | `./demo.sh --remote`              |

All scripts use `.env` configuration (no hardcoded values).

**Full Guide:** [Scripts Reference](docs/SCRIPTS.md)

---

## Project Structure

```
├── src/
│   ├── resources.js              # Harper resource definitions
│   ├── core/
│   │   ├── backends/
│   │   │   ├── Onnx.js          # ONNX Runtime backend
│   │   │   ├── TensorFlow.js    # TensorFlow.js backend
│   │   │   ├── Transformers.js  # Transformers.js backend
│   │   │   └── Ollama.js        # Ollama backend
│   │   ├── InferenceEngine.js   # Unified inference router
│   │   └── MonitoringBackend.js # Telemetry tracking
│   └── workers/
│       └── ModelFetchWorker.js  # Async model download worker
│
├── scripts/
│   ├── preload-models.js        # Profile-based model deployment
│   ├── cli/harper-ai.js         # CLI tool for model management
│   └── lib/
│       ├── model-fetch-client.js # Model Fetch API client
│       └── shell-utils.sh        # Shared shell utilities
│
├── tests/
│   ├── unit/                    # 11 unit test files (63 tests)
│   └── integration/             # 10 integration test files
│
├── profiles/                    # Model profile definitions
│   ├── minimal.json             # Minimal profile (1 model)
│   ├── testing.json             # Testing profile (4 models)
│   ├── benchmarking.json        # Benchmarking profile (equivalence groups)
│   ├── development.json         # Development profile (8 models)
│   └── production.json          # Production profile
│
├── deploy.sh                    # Deployment script
├── verify.sh                    # Verification script
├── benchmark.sh                 # Benchmarking script
└── demo.sh                      # Demo script
```

---

## API Examples

### Inference API

```javascript
// Text embedding
const response = await fetch('http://localhost:9926/Predict', {
	method: 'POST',
	headers: { 'Content-Type': 'application/json' },
	body: JSON.stringify({
		modelName: 'test-transformers-embedding',
		modelVersion: 'v1',
		inputs: { text: 'product search query' },
	}),
});

const { embedding } = await response.json();
console.log('Embedding:', embedding); // [0.123, -0.456, ...]
```

### Model Management

```javascript
// List all deployed models
const models = await fetch('http://localhost:9926/Model/').then((r) => r.json());

// Get specific model
const model = await fetch('http://localhost:9926/Model/minilm:v1').then((r) => r.json());

// Delete model
await fetch('http://localhost:9926/Model/minilm:v1', { method: 'DELETE' });
```

### Model Fetch API

```javascript
// Start async fetch job
const job = await fetch('http://localhost:9926/FetchModel', {
	method: 'POST',
	headers: { 'Content-Type': 'application/json' },
	body: JSON.stringify({
		source: 'huggingface',
		sourceReference: 'Xenova/all-MiniLM-L6-v2',
		modelName: 'minilm',
		modelVersion: 'v1',
		framework: 'transformers',
	}),
}).then((r) => r.json());

// Check job status
const status = await fetch(`http://localhost:9926/ModelFetchJobs?id=${job.jobId}`).then((r) => r.json());
```

---

## Scripts

```bash
# Development
npm run dev                      # Start Harper server
npm run preload                  # Load development models
npm run preload:testing          # Load testing profile
npm run preload:benchmarking     # Load benchmarking profile

# Testing
npm test                         # Run unit tests
npm run test:integration         # Run integration tests
npm run test:all                 # Run all tests

# Deployment
./deploy.sh                      # Deploy to remote Harper
./verify.sh --full               # Verify deployment
./benchmark.sh                   # Run benchmarks
./demo.sh                        # Interactive demo

# Linting & Formatting
npm run lint                     # Check code style
npm run lint:fix                 # Auto-fix issues
npm run format                   # Format all files
npm run format:check             # Check formatting
```

---

## Requirements

### System Requirements

- **Node.js** 18.0.0 or higher
- **npm** 9.0.0 or higher
- **Harper** 4.0.0 or higher
- **Operating System**: macOS or Linux

### Optional Dependencies

- **Ollama** - For LLM inference (chat and embeddings)
- **GPU** - For accelerated ONNX inference (optional)

### Installed Packages

- `onnxruntime-node@1.20.1` - ONNX Runtime
- `@xenova/transformers@2.17.2` - Transformers.js
- `@tensorflow/tfjs-node` - TensorFlow.js (optional)
- `uuid@11.0.3` - ID generation
- `sharp@0.32.6` - Image processing (optional)

---

## Documentation

### Getting Started

- [Quick Start](#quick-start-5-minutes) - Get running in 5 minutes
- [Deployment Guide](docs/DEPLOYMENT.md) - Local and remote deployment
- [Scripts Reference](docs/SCRIPTS.md) - deploy.sh, verify.sh, benchmark.sh, demo.sh

### Features

- [Model Fetch System](docs/MODEL_FETCH_SYSTEM.md) - Async model downloads (HuggingFace, HTTP, filesystem)
- [Benchmarking](docs/BENCHMARKING.md) - Performance comparison across backends
- [Profile Testing](docs/PROFILE_TESTING.md) - Profile-based model management
- [Model Metadata](docs/MODEL_METADATA.md) - Metadata conventions for benchmarking

### Technical

- [ONNX Runtime Guide](docs/ONNX_RUNTIME_GUIDE.md) - ONNX backend details
- [Roadmap](ROADMAP.md) - Future plans and milestones
- [Contributing](CONTRIBUTING.md) - How to contribute

---

## Test Coverage

- **Unit Tests**: 11 files, 63 tests (all passing)
- **Integration Tests**: 10 files covering end-to-end workflows
- **Coverage**: ~70% (unit + integration), 20% integration-only
- **Pre-commit Hooks**: Lint, format, and test before every commit

```bash
npm test                 # Run unit tests (63 tests, ~2s)
npm run test:integration # Run integration tests (~30s)
npm run test:all         # Run all tests
```

---

## Contributing

We welcome contributions! Here's how to get started:

1. **Read the docs** - Understand current capabilities
2. **Check the roadmap** - See [ROADMAP.md](ROADMAP.md) for planned features
3. **Follow conventions** - ESLint + Prettier configured
4. **Write tests** - All code must have tests
5. **Update docs** - Keep documentation current

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.

---

## Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/HarperFast/edge-ai-ops/issues)
- **Harper Docs**: https://docs.harperdb.io/

---

## Acknowledgments

Built with:

- [Harper](https://harperdb.io) - Application and database platform
- [ONNX Runtime](https://onnxruntime.ai/) - Optimized inference
- [Transformers.js](https://huggingface.co/docs/transformers.js) - Hugging Face models in JS
- [Ollama](https://ollama.ai/) - Local LLMs
- [TensorFlow.js](https://www.tensorflow.org/js) - Universal Sentence Encoder
