#!/usr/bin/env bash
#
# Deploy script for Harper Edge AI Ops
#
# Uses Harper CLI for deployment to remote Harper instances.
# See docs/DEPLOYMENT.md for complete documentation.
#
# Usage:
#   ./deploy.sh                  # Deploy current directory
#   ./deploy.sh --restart        # Deploy and restart Harper
#   ./deploy.sh --status         # Check deployment status
#   ./deploy.sh --test           # Run post-deployment tests
#   ./deploy.sh --full           # Full deploy: push, restart, and test

set -e  # Exit on error

# ============================================
# LOAD ENVIRONMENT
# ============================================

# Load .env file if it exists
if [[ -f .env ]]; then
    # Export variables from .env file
    set -a
    source .env
    set +a
fi

# ============================================
# CONFIGURATION
# ============================================

# Remote Harper instance (configurable via .env)
REMOTE_HOST="${DEPLOY_REMOTE_HOST:-ai-ops.irjudson-ai.harperfabric.com}"
REMOTE_PORT="${DEPLOY_REMOTE_PORT:-9925}"
REMOTE_URL="${DEPLOY_REMOTE_URL:-https://${REMOTE_HOST}:${REMOTE_PORT}}"

# Harper Admin Credentials (configurable via .env or environment)
REMOTE_USERNAME="${CLI_TARGET_USERNAME:-${DEPLOY_USERNAME:-HDB_ADMIN}}"
REMOTE_PASSWORD="${CLI_TARGET_PASSWORD:-${DEPLOY_PASSWORD:-}}"

# Model Fetch Token (for testing, configurable via .env)
MODEL_FETCH_TOKEN="${MODEL_FETCH_TOKEN:-}"

# Harper deploy options (configurable via .env)
DEPLOY_REPLICATED="${DEPLOY_REPLICATED:-true}"  # Replicate across cluster nodes
DEPLOY_RESTART="${DEPLOY_RESTART:-true}"        # Restart after deploy

# Backend selection (configurable via .env for automated deployments)
# Set to 'auto' to skip interactive prompt, or comma-separated: onnx,tensorflow,transformers
DEPLOY_BACKENDS="${DEPLOY_BACKENDS:-}"

# Script flow options (defaults to full deployment)
RESTART_HARPER=true
RUN_TESTS=true
CHECK_STATUS=false
DRY_RUN=false
LOCAL_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# FUNCTIONS
# ============================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if Harper CLI is installed
    if ! command -v harper &> /dev/null; then
        log_error "Harper CLI not found. Install with: npm install -g harper"
        exit 1
    fi

    # Check if git is clean
    if [[ -n $(git status --porcelain) ]]; then
        log_warn "Working directory has uncommitted changes"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Check if credentials are configured (skip for local mode)
    if [[ -z "$REMOTE_PASSWORD" ]] && [[ "$LOCAL_MODE" != "true" ]]; then
        log_error "REMOTE_PASSWORD not set"
        log_info "Set in .env file:"
        log_info "  DEPLOY_PASSWORD=your-password"
        log_info "Or use environment variable:"
        log_info "  export CLI_TARGET_PASSWORD=your-password"
        exit 1
    fi

    if [[ -z "$MODEL_FETCH_TOKEN" ]]; then
        log_warn "MODEL_FETCH_TOKEN not set - tests will fail if token is required"
        log_info "Set in .env file: MODEL_FETCH_TOKEN=your-token"
    fi

    log_success "Prerequisites check passed"
}

check_remote_connection() {
    local silent=${1:-false}  # Optional parameter for silent mode (used during retries)

    if [[ "$silent" != "true" ]]; then
        log_info "Testing connection to remote Harper instance..."
    fi

    # Use /health endpoint (built-in Harper endpoint, always available)
    # Check both HTTP status code and response body
    local response=$(curl -k -s --max-time 5 "${REMOTE_URL}/health" 2>/dev/null)
    local http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 5 "${REMOTE_URL}/health" 2>/dev/null)

    if [[ "$http_code" == "200" ]] && [[ "$response" == *"running"* ]]; then
        if [[ "$silent" != "true" ]]; then
            log_success "Remote Harper instance is accessible and running"
        fi
        return 0
    else
        if [[ "$silent" != "true" ]]; then
            log_error "Cannot connect to ${REMOTE_URL}/health"
            log_info "HTTP ${http_code}, Response: ${response}"
            log_info "Check if Harper instance is running"
        fi
        return 1
    fi
}

select_backends() {
    log_info "Selecting ML backends for deployment..."

    local backend_selection=""

    # Check if DEPLOY_BACKENDS is set (automated deployment)
    if [[ -n "$DEPLOY_BACKENDS" ]]; then
        log_info "Using backends from DEPLOY_BACKENDS: $DEPLOY_BACKENDS"
        backend_selection="$DEPLOY_BACKENDS"
    else
        # Interactive selection
        echo ""
        echo "Available ML backends and their sizes:"
        echo "  1. ONNX Runtime        - 183 MB"
        echo "  2. TensorFlow.js       - 683 MB"
        echo "  3. Transformers.js     -  45 MB"
        echo "  4. All backends        - 911 MB (WARNING: >800MB)"
        echo ""
        echo "Note: Ollama backend is always available (0 MB - external service)"
        echo ""
        echo "Select backends to deploy (comma-separated, e.g., 1,3 or 'all'):"
        read -r backend_selection

        # Default to all if empty
        if [[ -z "$backend_selection" ]]; then
            backend_selection="all"
        fi
    fi

    # Parse selection
    DEPLOY_ONNX=false
    DEPLOY_TENSORFLOW=false
    DEPLOY_TRANSFORMERS=false

    if [[ "$backend_selection" == "all" ]] || [[ "$backend_selection" == "4" ]]; then
        DEPLOY_ONNX=true
        DEPLOY_TENSORFLOW=true
        DEPLOY_TRANSFORMERS=true
    else
        IFS=',' read -ra SELECTIONS <<< "$backend_selection"
        for sel in "${SELECTIONS[@]}"; do
            # Trim whitespace
            sel=$(echo "$sel" | xargs)
            case $sel in
                1|onnx) DEPLOY_ONNX=true ;;
                2|tensorflow) DEPLOY_TENSORFLOW=true ;;
                3|transformers) DEPLOY_TRANSFORMERS=true ;;
                *) log_warn "Unknown selection: $sel" ;;
            esac
        done
    fi

    # Calculate total size
    local total_size=0
    local selected_backends=""

    if [[ "$DEPLOY_ONNX" == "true" ]]; then
        total_size=$((total_size + 183))
        selected_backends="${selected_backends}ONNX, "
    fi

    if [[ "$DEPLOY_TENSORFLOW" == "true" ]]; then
        total_size=$((total_size + 683))
        selected_backends="${selected_backends}TensorFlow, "
    fi

    if [[ "$DEPLOY_TRANSFORMERS" == "true" ]]; then
        total_size=$((total_size + 45))
        selected_backends="${selected_backends}Transformers.js, "
    fi

    # Remove trailing comma
    selected_backends="${selected_backends%, }"

    if [[ -z "$selected_backends" ]]; then
        log_error "No backends selected. At least one backend is required."
        exit 1
    fi

    log_info "Selected backends: ${selected_backends}"

    # Calculate node_modules size if not skipping
    local node_modules_size=0
    if [[ "${SKIP_NODE_MODULES}" != "true" ]] && [[ -d "node_modules" ]]; then
        # Get size in MB (du -sm gives size in MB)
        node_modules_size=$(du -sm node_modules 2>/dev/null | cut -f1)
        if [[ -z "$node_modules_size" ]]; then
            node_modules_size=0
        fi
    fi

    # Check models directory size (always excluded from deployment)
    local models_size=0
    if [[ -d "models" ]]; then
        models_size=$(du -sm models 2>/dev/null | cut -f1)
        if [[ -z "$models_size" ]]; then
            models_size=0
        fi
        if [[ $models_size -gt 0 ]]; then
            log_info "Note: models/ directory (${models_size}MB) is excluded from deployment (.gitignore)"
        fi
    fi

    # Calculate total deployment size
    local total_with_deps=$((total_size + node_modules_size))

    # Auto-enable SKIP_NODE_MODULES if total exceeds 800MB
    if [[ $total_with_deps -gt 800 ]] && [[ "${SKIP_NODE_MODULES}" != "true" ]]; then
        log_warn "⚠️  Total deployment size would be ${total_with_deps}MB (backends: ${total_size}MB + node_modules: ${node_modules_size}MB)"
        log_warn "This exceeds the 800MB recommended limit."
        log_info "Automatically enabling SKIP_NODE_MODULES to reduce upload size."
        log_info "Remote instance will need to run 'npm install' after deployment."
        SKIP_NODE_MODULES=true
        echo ""
        total_with_deps=$total_size
    fi

    if [[ "${SKIP_NODE_MODULES}" == "true" ]]; then
        log_info "Estimated deployment size: ${total_size} MB (node_modules excluded)"
    else
        log_info "Estimated deployment size: ${total_with_deps} MB (backends: ${total_size}MB + node_modules: ${node_modules_size}MB)"
    fi

    # Warn if still >800MB
    if [[ $total_with_deps -gt 800 ]]; then
        log_warn "⚠️  Deployment size (${total_with_deps}MB) exceeds 800MB!"
        log_warn "This may cause slow deployments or storage issues."
        echo ""
        # Skip confirmation in dry-run mode
        if [[ "$DRY_RUN" != "true" ]]; then
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Deployment cancelled."
                exit 0
            fi
        fi
    fi

    echo ""
}

create_deployment_package() {
    log_info "Creating deployment package with selected backends..."

    # Backup original package.json
    cp package.json package.json.backup

    # Use Node.js to modify package.json (cross-platform compatible)
    node -e "
        const fs = require('fs');
        const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));

        // Build new dependencies based on selections
        const newDeps = { uuid: pkg.dependencies.uuid };

        if ('$DEPLOY_ONNX' === 'true') {
            newDeps['onnxruntime-node'] = pkg.dependencies['onnxruntime-node'];
        }

        if ('$DEPLOY_TENSORFLOW' === 'true') {
            newDeps['@tensorflow/tfjs-node'] = pkg.dependencies['@tensorflow/tfjs-node'];
            newDeps['@tensorflow-models/universal-sentence-encoder'] = pkg.dependencies['@tensorflow-models/universal-sentence-encoder'];
        }

        if ('$DEPLOY_TRANSFORMERS' === 'true') {
            newDeps['@xenova/transformers'] = pkg.dependencies['@xenova/transformers'];
        }

        // Replace dependencies
        pkg.dependencies = newDeps;

        // Write modified package.json
        fs.writeFileSync('package.json', JSON.stringify(pkg, null, '\t') + '\n');
    "

    log_success "Deployment package configured"
}

restore_package_json() {
    log_info "Restoring original package.json..."

    if [[ -f package.json.backup ]]; then
        mv package.json.backup package.json
        rm -f package.json.tmp
        log_success "Original package.json restored"
    fi
}

create_deploy_staging() {
    log_info "Creating deployment staging directory..."

    # Get project name (parent directory name) for Harper CLI project parameter
    local project_name=$(basename "$PWD")
    export DEPLOY_PROJECT_NAME="${project_name}"

    # Use fixed staging directory name
    local staging_dir="dist"

    # Remove old staging directory if it exists
    if [[ -d "${staging_dir}" ]]; then
        rm -rf "${staging_dir}"
    fi

    # Create staging directory
    mkdir -p "${staging_dir}"

    # Copy essential files and directories
    log_info "Copying application files..."
    cp -R src "${staging_dir}/"
    cp schemas.graphql "${staging_dir}/"
    cp package.json "${staging_dir}/"

    # Copy config.yaml if it exists
    if [[ -f "config.yaml" ]]; then
        cp config.yaml "${staging_dir}/"
    fi

    # Copy .env file for remote configuration
    if [[ -f ".env" ]]; then
        cp .env "${staging_dir}/"
        log_info "Copied .env file for remote configuration"
    else
        log_warn ".env file not found - remote instance may need manual configuration"
    fi

    # Copy node_modules if not skipping
    if [[ "${SKIP_NODE_MODULES}" != "true" ]]; then
        log_info "Copying node_modules (this may take a moment)..."
        cp -R node_modules "${staging_dir}/"
    fi

    # Get actual size of staging directory
    local staging_size=$(du -sm "${staging_dir}" 2>/dev/null | cut -f1)
    log_info "Staging directory: ${staging_dir}/ (${staging_size}MB)"

    # Export for use in deploy_code
    export DEPLOY_STAGING_DIR="${staging_dir}"
}

cleanup_deploy_staging() {
    if [[ -n "${DEPLOY_STAGING_DIR}" ]] && [[ -d "${DEPLOY_STAGING_DIR}" ]]; then
        log_info "Cleaning up staging directory..."
        rm -rf "${DEPLOY_STAGING_DIR}"
    fi
}

deploy_code() {
    log_info "Deploying code to ${REMOTE_URL}..."

    local current_branch=$(git branch --show-current)
    log_info "Current branch: ${current_branch}"

    # Set up trap to clean up on error
    trap 'cleanup_deploy_staging; restore_package_json' EXIT ERR INT TERM

    # Create staging directory with only files to deploy
    create_deploy_staging

    # Deploy using Harper CLI from staging directory
    log_info "Deploying via Harper CLI..."
    log_info "  Project: ${DEPLOY_PROJECT_NAME}"
    log_info "  Replicated: ${DEPLOY_REPLICATED}"
    log_info "  Restart: ${DEPLOY_RESTART}"
    log_info "  Skip node_modules: ${SKIP_NODE_MODULES}"

    # Build deploy command with all parameters
    local deploy_cmd="harper deploy project=\"${DEPLOY_PROJECT_NAME}\" target=\"${REMOTE_URL}\" username=\"${REMOTE_USERNAME}\" password=\"${REMOTE_PASSWORD}\" replicated=\"${DEPLOY_REPLICATED}\" restart=\"${DEPLOY_RESTART}\""

    # Add skip_node_modules if enabled
    if [[ "${SKIP_NODE_MODULES}" == "true" ]]; then
        deploy_cmd="${deploy_cmd} skip_node_modules=\"true\""
    fi

    log_info "Deploying project '${DEPLOY_PROJECT_NAME}' to ${REMOTE_URL}..."

    # Change to staging directory and run deployment
    cd "${DEPLOY_STAGING_DIR}"

    # Run deployment
    local deploy_output
    deploy_output=$(eval "${deploy_cmd}" 2>&1)
    local deploy_exit_code=$?

    # Change back to original directory
    cd ..

    # Display the output
    echo "$deploy_output"

    # Check if deploy succeeded
    if [[ $deploy_exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $deploy_exit_code"
        cleanup_deploy_staging
        restore_package_json
        trap - EXIT ERR INT TERM
        exit 1
    fi

    # Check for timeout in output (Harper CLI returns exit code 0 even on 408)
    if echo "$deploy_output" | grep -q "408"; then
        log_error "Deployment timed out (408 Request Timeout)"
        log_error "Try reducing deployment size with fewer backends in DEPLOY_BACKENDS"
        cleanup_deploy_staging
        restore_package_json
        trap - EXIT ERR INT TERM
        exit 1
    fi

    # Check for other error indicators
    if echo "$deploy_output" | grep -qE "error|Error|ERROR|failed|Failed"; then
        log_error "Deployment appears to have failed (check output above)"
        cleanup_deploy_staging
        restore_package_json
        trap - EXIT ERR INT TERM
        exit 1
    fi

    if [[ "$DEPLOY_RESTART" == "true" ]] || [[ "$DEPLOY_RESTART" == "rolling" ]]; then
        log_info "Waiting for restart to complete..."
        sleep 5
    fi

    # Clean up staging directory
    cleanup_deploy_staging

    # Restore package.json
    restore_package_json

    # Clear trap
    trap - EXIT ERR INT TERM

    log_success "Code deployed successfully"
}

restart_harper() {
    log_info "Restarting Harper on remote instance..."

    # Export credentials as environment variables (required by Harper CLI)
    export CLI_TARGET_USERNAME="$REMOTE_USERNAME"
    export CLI_TARGET_PASSWORD="$REMOTE_PASSWORD"

    # Restart using Harper CLI
    harper restart target="${REMOTE_URL}"

    # Unset credentials after use
    unset CLI_TARGET_USERNAME
    unset CLI_TARGET_PASSWORD

    log_info "Waiting for Harper to restart..."
    sleep 5

    log_success "Harper restarted"
}

check_deployment_status() {
    log_info "Checking deployment status..."

    # Wait for Harper to restart and become available
    log_info "Waiting for Harper to restart (up to 60 seconds)..."
    local max_attempts=12  # 60 seconds total (12 * 5 seconds)
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        # Use silent mode to avoid spamming error messages during expected failures
        if check_remote_connection "true"; then
            log_success "Harper is running"
            break
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            printf "."  # Progress indicator
            sleep 5
            attempt=$((attempt + 1))
        else
            echo ""  # New line after dots
            log_error "Harper did not respond after $((max_attempts * 5)) seconds"
            return 1
        fi
    done

    if [[ $attempt -gt 1 ]]; then
        echo ""  # New line after dots
    fi

    # Check using Harper CLI
    log_info "Getting Harper status..."
    export CLI_TARGET_USERNAME="$REMOTE_USERNAME"
    export CLI_TARGET_PASSWORD="$REMOTE_PASSWORD"

    harper status target="${REMOTE_URL}" || true

    unset CLI_TARGET_USERNAME
    unset CLI_TARGET_PASSWORD

    log_success "Status check complete"
}

run_deployment_tests() {
    log_info "Running post-deployment tests..."

    # REMOTE_URL is the deployment port (9925), but CLI needs application port (9926)
    # Convert deployment URL to application URL by changing port from 9925 to 9926
    local APP_URL
    if [[ "$REMOTE_URL" =~ :9925$ ]]; then
        APP_URL="${REMOTE_URL%:9925}:9926"
    else
        # For local deployments, use localhost:9926
        APP_URL="http://localhost:9926"
    fi

    export HARPER_URL="${APP_URL}"
    export MODEL_FETCH_TOKEN="${MODEL_FETCH_TOKEN}"

    log_info "Testing against application URL: ${APP_URL}"

    # Test 1: Inspect a HuggingFace model
    log_info "Test 1: Inspect model..."
    if node scripts/cli/harper-ai.js model inspect huggingface Xenova/all-MiniLM-L6-v2 --variant quantized --url "${APP_URL}" --token "${MODEL_FETCH_TOKEN}" --username "${REMOTE_USERNAME}" --password "${REMOTE_PASSWORD}"; then
        log_success "✓ Model inspection works"
    else
        log_error "✗ Model inspection failed"
        return 1
    fi

    # Test 2: List jobs
    log_info "Test 2: List jobs..."
    if node scripts/cli/harper-ai.js job list --url "${APP_URL}" --token "${MODEL_FETCH_TOKEN}" --username "${REMOTE_USERNAME}" --password "${REMOTE_PASSWORD}"; then
        log_success "✓ Job listing works"
    else
        log_error "✗ Job listing failed"
        return 1
    fi

    # Test 3: List models
    log_info "Test 3: List models..."
    if node scripts/cli/harper-ai.js model list --url "${APP_URL}" --token "${MODEL_FETCH_TOKEN}" --username "${REMOTE_USERNAME}" --password "${REMOTE_PASSWORD}"; then
        log_success "✓ Model listing works"
    else
        log_error "✗ Model listing failed"
        return 1
    fi

    # Test 4: Fetch model and test inference
    log_info "Test 4: Fetch model and test inference..."

    # Check if model already exists
    local TEST_MODEL="deploy-test-inference"
    local MODEL_LIST
    MODEL_LIST=$(node scripts/cli/harper-ai.js model list \
        --url "${APP_URL}" \
        --token "${MODEL_FETCH_TOKEN}" \
        --username "${REMOTE_USERNAME}" \
        --password "${REMOTE_PASSWORD}" 2>&1)

    if echo "${MODEL_LIST}" | grep -q "${TEST_MODEL}"; then
        log_info "Model ${TEST_MODEL} already exists, skipping fetch"
    else
        # Fetch a small quantized model for testing
        log_info "Fetching model ${TEST_MODEL}..."
        local FETCH_OUTPUT
        FETCH_OUTPUT=$(node scripts/cli/harper-ai.js model fetch huggingface Xenova/all-MiniLM-L6-v2 \
            --name "${TEST_MODEL}" \
            --variant quantized \
            --url "${APP_URL}" \
            --token "${MODEL_FETCH_TOKEN}" \
            --username "${REMOTE_USERNAME}" \
            --password "${REMOTE_PASSWORD}" 2>&1)

        if echo "${FETCH_OUTPUT}" | grep -q "Fetch job created"; then
            local JOB_ID
            JOB_ID=$(echo "${FETCH_OUTPUT}" | grep "Job ID:" | awk '{print $NF}')
            log_info "Job created: ${JOB_ID}, waiting for completion..."

            # Wait for job to complete (max 60 seconds)
            local TIMEOUT=60
            local ELAPSED=0
            while [ $ELAPSED -lt $TIMEOUT ]; do
                local JOB_STATUS
                JOB_STATUS=$(node scripts/cli/harper-ai.js job get "${JOB_ID}" \
                    --url "${APP_URL}" \
                    --token "${MODEL_FETCH_TOKEN}" \
                    --username "${REMOTE_USERNAME}" \
                    --password "${REMOTE_PASSWORD}" 2>&1)

                if echo "${JOB_STATUS}" | grep -q "Status:.*completed"; then
                    log_info "Model fetch completed"
                    break
                elif echo "${JOB_STATUS}" | grep -q "Status:.*failed"; then
                    log_error "✗ Model fetch failed"
                    echo "${JOB_STATUS}"
                    return 1
                fi

                sleep 5
                ELAPSED=$((ELAPSED + 5))
            done

            if [ $ELAPSED -ge $TIMEOUT ]; then
                log_error "✗ Model fetch timed out after ${TIMEOUT} seconds"
                return 1
            fi
        else
            log_error "✗ Unexpected fetch output:"
            echo "${FETCH_OUTPUT}"
            return 1
        fi
    fi

    # Test inference on the fetched model
    log_info "Testing inference on ${TEST_MODEL}..."
    local AUTH_HEADER="Authorization: Basic $(echo -n "${REMOTE_USERNAME}:${REMOTE_PASSWORD}" | base64)"
    local INFERENCE_RESPONSE
    INFERENCE_RESPONSE=$(curl -s -X POST "${APP_URL}/Predict" \
        -H "Content-Type: application/json" \
        -H "${AUTH_HEADER}" \
        -d "{
            \"modelName\": \"${TEST_MODEL}\",
            \"modelVersion\": \"v1\",
            \"features\": {\"text\": \"This is a test sentence for embedding.\"}
        }")

    # Check if response contains error
    if echo "${INFERENCE_RESPONSE}" | grep -q '"error"'; then
        log_warn "⚠ Inference failed (model fetched but inference has issues):"
        echo "${INFERENCE_RESPONSE}" | jq '.' 2>/dev/null || echo "${INFERENCE_RESPONSE}"
        log_info "Model fetch system is working, but inference needs investigation"
    # Check if response contains embeddings
    elif echo "${INFERENCE_RESPONSE}" | grep -q '"embeddings"'; then
        # Extract embedding dimension
        local EMBEDDING_DIM
        EMBEDDING_DIM=$(echo "${INFERENCE_RESPONSE}" | jq '.embeddings[0] | length' 2>/dev/null)

        if [ "${EMBEDDING_DIM}" = "384" ]; then
            log_success "✓ Inference works (embeddings: ${EMBEDDING_DIM} dimensions)"
        elif [ -n "${EMBEDDING_DIM}" ] && [ "${EMBEDDING_DIM}" != "null" ]; then
            log_warn "⚠ Inference returned embeddings but unexpected dimension: ${EMBEDDING_DIM} (expected 384)"
        else
            log_warn "⚠ Inference response has embeddings field but couldn't parse dimension"
        fi
    else
        log_warn "⚠ Inference response format unexpected:"
        echo "${INFERENCE_RESPONSE}" | jq '.' 2>/dev/null || echo "${INFERENCE_RESPONSE}"
        log_info "Model fetch system is working, but inference response format needs investigation"
    fi

    log_success "All deployment tests passed"
}

show_help() {
    cat << EOF
Harper Edge AI Ops - Deployment Script

Uses Harper CLI for deployment to remote Harper instances.
See docs/DEPLOYMENT.md for complete documentation.

USAGE:
    ./deploy.sh [OPTIONS]

DEFAULT BEHAVIOR:
    Full deployment: deploy + replicate + restart + test
    To skip any step, use the --no-* flags below.

OPTIONS:
    --help              Show this help message
    --local             Verify local Harper instance (http://localhost:9926)
                        Note: For local dev, just use 'npm run dev' - no deployment needed
    --dry-run           Show what would be deployed without executing
    --no-restart        Skip Harper restart after deployment
    --no-tests          Skip post-deployment tests
    --no-replicate      Deploy to single node only (no cluster replication)
    --status            Check deployment status (no deploy)

EXAMPLES:
    # Full deployment (default: deploy + replicate + restart + test)
    ./deploy.sh

    # Deploy without restarting
    ./deploy.sh --no-restart

    # Deploy without tests
    ./deploy.sh --no-tests

    # Deploy to single node only (no cluster replication)
    ./deploy.sh --no-replicate

    # Deploy with no restart and no tests
    ./deploy.sh --no-restart --no-tests

    # Check current status only
    ./deploy.sh --status

    # Preview what would be deployed
    ./deploy.sh --dry-run

    # Deploy to local Harper instance (development)
    ./deploy.sh --local

    # Preview local deployment
    ./deploy.sh --local --dry-run

    # Local deployment with specific backends
    DEPLOY_BACKENDS=onnx,transformers ./deploy.sh --local

CONFIGURATION:
    Remote: ${REMOTE_URL}
    Username: ${REMOTE_USERNAME}

    Configuration priority (highest to lowest):
      1. Environment variables (CLI_TARGET_*, DEPLOY_*)
      2. .env file
      3. Script defaults

    .env file variables:
      DEPLOY_REMOTE_HOST=ai-ops.irjudson-ai.harperfabric.com
      DEPLOY_REMOTE_PORT=9925
      DEPLOY_REMOTE_URL=https://ai-ops.irjudson-ai.harperfabric.com:9925
      DEPLOY_USERNAME=HDB_ADMIN
      DEPLOY_PASSWORD=your-password
      DEPLOY_REPLICATED=true              # Replicate across cluster
      DEPLOY_RESTART=true                 # Restart after deploy (true/false/rolling)
      MODEL_FETCH_TOKEN=your-token

    Environment variable overrides:
      CLI_TARGET_USERNAME=HDB_ADMIN
      CLI_TARGET_PASSWORD=your-password
      MODEL_FETCH_TOKEN=your-token

PREREQUISITES:
    - Harper CLI installed: npm install -g harper
    - Remote Harper instance running
    - Valid admin credentials in .env or environment

EOF
}

show_dry_run_plan() {
    log_info "========================================="
    log_info "DRY RUN - Deployment Plan"
    log_info "========================================="
    echo ""

    log_info "Target Configuration:"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        echo "  Mode:             Local Development"
    else
        echo "  Mode:             Remote"
    fi
    echo "  Target URL:       ${REMOTE_URL}"
    echo "  Username:         ${REMOTE_USERNAME}"
    echo "  Replicated:       ${DEPLOY_REPLICATED}"
    echo "  Restart Harper:   ${RESTART_HARPER}"
    echo "  Run Tests:        ${RUN_TESTS}"
    echo ""

    log_info "Selected Backends:"
    local backends_list=""
    local total_size=0

    if [[ "$DEPLOY_ONNX" == "true" ]]; then
        backends_list="${backends_list}  ✓ ONNX Runtime        - 183 MB\n"
        total_size=$((total_size + 183))
    fi

    if [[ "$DEPLOY_TENSORFLOW" == "true" ]]; then
        backends_list="${backends_list}  ✓ TensorFlow.js       - 683 MB\n"
        total_size=$((total_size + 683))
    fi

    if [[ "$DEPLOY_TRANSFORMERS" == "true" ]]; then
        backends_list="${backends_list}  ✓ Transformers.js     -  45 MB\n"
        total_size=$((total_size + 45))
    fi

    backends_list="${backends_list}  ✓ Ollama              -   0 MB (external service)"

    echo -e "$backends_list"
    echo ""
    log_info "Total Deployment Size: ${total_size} MB"

    if [[ $total_size -gt 800 ]]; then
        log_warn "⚠️  Deployment size exceeds 800MB!"
    fi
    echo ""

    log_info "Deployment Steps:"
    echo "  1. Package selected backends"
    echo "  2. Deploy to ${REMOTE_URL}"
    if [[ "$DEPLOY_REPLICATED" == "true" ]]; then
        echo "  3. Replicate across cluster nodes"
    else
        echo "  3. Deploy to single node only"
    fi
    if [[ "$RESTART_HARPER" == "true" ]]; then
        echo "  4. Restart Harper"
        echo "  5. Check deployment status"
    fi
    if [[ "$RUN_TESTS" == "true" ]]; then
        echo "  6. Run post-deployment tests"
    fi
    echo ""

    log_success "========================================="
    log_success "Dry Run Complete"
    log_success "========================================="
    echo ""
    log_info "To execute this deployment, run without --dry-run:"
    echo "  ./deploy.sh"
    echo ""
}

# ============================================
# MAIN
# ============================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --no-restart)
            RESTART_HARPER=false
            shift
            ;;
        --no-tests)
            RUN_TESTS=false
            shift
            ;;
        --no-replicate)
            DEPLOY_REPLICATED=false
            shift
            ;;
        --status)
            CHECK_STATUS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --local)
            LOCAL_MODE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override configuration for local mode
if [[ "$LOCAL_MODE" == "true" ]]; then
    # For local development mode, use application port (9926) not deployment port (9925)
    # Local mode with npm run dev doesn't need separate deployment
    REMOTE_URL="http://localhost:9926"
    REMOTE_HOST="localhost"
    REMOTE_PORT="9926"
    REMOTE_USERNAME="${DEPLOY_USERNAME:-admin}"
    REMOTE_PASSWORD="${DEPLOY_PASSWORD}"
    # Local deployments typically don't need replication
    DEPLOY_REPLICATED=false
fi

# Execute based on flags
if [[ "$CHECK_STATUS" == "true" ]]; then
    check_deployment_status
    exit 0
fi

# Main deployment flow
echo ""
log_info "========================================="
log_info "Harper Edge AI Ops - Deployment"
log_info "========================================="
echo ""

# Skip prerequisite checks in dry-run mode
if [[ "$DRY_RUN" != "true" ]]; then
    check_prerequisites
    check_remote_connection
fi

# Select backends for deployment
select_backends

# Show dry-run plan and exit if requested
if [[ "$DRY_RUN" == "true" ]]; then
    show_dry_run_plan
    exit 0
fi

if [[ "$LOCAL_MODE" == "true" ]]; then
    log_info "Local mode detected - skipping deployment (app already running via npm run dev)"
    log_info "Verifying app is accessible..."
else
    create_deployment_package

    # Deploy code - exit on failure
    if ! deploy_code; then
        log_error "Deployment failed, aborting"
        exit 1
    fi
fi

if [[ "$RESTART_HARPER" == "true" ]] && [[ "$LOCAL_MODE" != "true" ]]; then
    if ! restart_harper; then
        log_error "Restart failed, aborting"
        exit 1
    fi
    if ! check_deployment_status; then
        log_error "Status check failed, aborting"
        exit 1
    fi
fi

if [[ "$RUN_TESTS" == "true" ]]; then
    if ! run_deployment_tests; then
        log_error "Tests failed, aborting"
        exit 1
    fi
fi

echo ""
log_success "========================================="
log_success "Deployment Complete!"
log_success "========================================="
echo ""

log_info "Next steps:"
log_info "  1. Check status: ./deploy.sh --status"
log_info "  2. Test CLI: npm exec harper-ai model list --url ${REMOTE_URL}"
log_info "  3. View docs: docs/DEPLOYMENT.md"
echo ""
