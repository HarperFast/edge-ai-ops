#!/usr/bin/env bash
#
# Verify deployed Harper Edge AI system
#
# Tests a deployed running system to ensure all components work.
# NOT a pre-commit test - this is for integration/smoke testing.
#
# Usage:
#   ./verify.sh                          # Verify local instance
#   ./verify.sh --remote                 # Verify remote instance from .env
#   ./verify.sh --profile testing        # Use specific model profile
#   ./verify.sh --quick                  # Quick smoke test only
#   ./verify.sh --full                   # Full verification suite

set -e  # Exit on error

# ============================================
# LOAD ENVIRONMENT
# ============================================

# Load .env file if it exists
if [[ -f .env ]]; then
    set -a
    source .env
    set +a
fi

# Load shared utilities
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/scripts/lib/shell-utils.sh"

# ============================================
# CONFIGURATION
# ============================================

# Default to local instance
HARPER_URL="${HARPER_URL:-http://localhost:9926}"
DEPLOY_REMOTE_URL="${DEPLOY_REMOTE_URL:-}"
REMOTE_USERNAME="${CLI_TARGET_USERNAME:-${DEPLOY_USERNAME:-HDB_ADMIN}}"
REMOTE_PASSWORD="${CLI_TARGET_PASSWORD:-${DEPLOY_PASSWORD:-}}"
MODEL_FETCH_TOKEN="${MODEL_FETCH_TOKEN:-}"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

# Test configuration
TEST_PROFILE="${TEST_PROFILE:-testing}"
QUICK_MODE=false
FULL_MODE=false
REMOTE_MODE=false
DEPLOY_PROFILE=false

# ============================================
# FUNCTIONS
# ============================================

show_help() {
    cat << EOF
Harper Edge AI Verification Script

Verify a running Harper instance (NOT for pre-commit testing).

USAGE:
    ./verify.sh [OPTIONS]

DEPLOYMENT SCENARIOS:
    This script works with three deployment scenarios:

    1. Local dev mode (npm run dev)
       - App runs from project directory with DEV_MODE=true
       - Models can be loaded from local files or fetched from HuggingFace
       - Target: http://localhost:9926 (default)
       - Example: ./verify.sh --deploy --full

    2. Local deployed (harper deploy to localhost)
       - App deployed to ~/hdb/components/edge-ai-ops/
       - Models must be fetched from HuggingFace (no local files available)
       - Target: http://localhost:9926 (default)
       - Example: ./verify.sh --deploy --full

    3. Remote deployed (harper deploy to remote host)
       - App deployed to remote HarperDB instance
       - Models must be fetched from HuggingFace
       - Target: DEPLOY_REMOTE_URL from .env
       - Example: ./verify.sh --remote --deploy --full

OPTIONS:
    --help              Show this help message
    --remote            Target remote instance (uses DEPLOY_REMOTE_URL from .env)
                        Default: http://localhost:9926
    --profile <name>    Use specific model profile (default: testing)
    --deploy            Fetch and deploy profile models before verification
                        Models are fetched from HuggingFace (or local files in dev mode)
    --quick             Quick smoke test only (health + basic API)
    --full              Full verification suite (includes inference and integration tests)

CONFIGURATION (.env):
    # Local instance (default)
    HARPER_URL=http://localhost:9926

    # Remote instance (for --remote flag)
    DEPLOY_REMOTE_URL=https://your-instance.com:9926
    DEPLOY_USERNAME=HDB_ADMIN
    DEPLOY_PASSWORD=your-password
    MODEL_FETCH_TOKEN=your-token

    # Backend availability
    OLLAMA_HOST=http://localhost:11434

EXAMPLES:
    # Verify local instance (dev or deployed)
    ./verify.sh

    # Quick smoke test
    ./verify.sh --quick

    # Deploy models and run full verification (local dev or deployed)
    ./verify.sh --deploy --full

    # Verify specific profile
    ./verify.sh --profile benchmarking

    # Deploy and verify remote instance
    ./verify.sh --remote --deploy --full

    # Quick check of remote instance
    ./verify.sh --remote --quick

EOF
}

check_harper_health() {
    log_info "Checking Harper health..."

    local response
    response=$(curl -s --max-time 5 "${HARPER_URL}/Status" 2>/dev/null || echo "")

    if [[ -z "$response" ]]; then
        log_error "Cannot connect to Harper at ${HARPER_URL}"
        return 1
    fi

    if echo "$response" | grep -q "healthy"; then
        log_success "Harper Edge AI is running at ${HARPER_URL}"
        return 0
    else
        log_error "Unexpected response from ${HARPER_URL}/Status"
        log_error "Response: ${response}"
        return 1
    fi
}

check_api_endpoints() {
    log_info "Checking API endpoints..."

    # Check Model API
    if curl -s --max-time 5 "${HARPER_URL}/Model/" >/dev/null 2>&1; then
        log_success "✓ Model API accessible"
    else
        log_error "✗ Model API not accessible"
        return 1
    fi

    # Check ModelFetchJobs API (if token provided)
    if [[ -n "$MODEL_FETCH_TOKEN" ]]; then
        if curl -s --max-time 5 "${HARPER_URL}/ModelFetchJobs?token=${MODEL_FETCH_TOKEN}" >/dev/null 2>&1; then
            log_success "✓ ModelFetchJobs API accessible"
        else
            log_warn "⚠ ModelFetchJobs API not accessible (may need authentication)"
        fi
    fi

    # Check InspectModel API
    if [[ -n "$MODEL_FETCH_TOKEN" ]]; then
        if curl -s --max-time 5 "${HARPER_URL}/InspectModel?source=huggingface&sourceReference=Xenova/all-MiniLM-L6-v2&token=${MODEL_FETCH_TOKEN}" >/dev/null 2>&1; then
            log_success "✓ InspectModel API accessible"
        else
            log_warn "⚠ InspectModel API not accessible"
        fi
    fi

    log_success "API endpoint check complete"
}

check_deployed_models() {
    log_info "Checking deployed models..."

    local response
    response=$(curl -s "${HARPER_URL}/Model/" 2>/dev/null || echo "[]")

    local count
    count=$(echo "$response" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$count" -eq 0 ]]; then
        log_warn "No models deployed (run: npm run preload:${TEST_PROFILE})"
        return 1
    fi

    log_success "Found ${count} deployed model(s)"

    # Show model summary
    echo "$response" | jq -r '.[] | "  - \(.modelName):\(.modelVersion) (\(.framework))"' 2>/dev/null || true

    return 0
}

check_backends() {
    log_info "Checking backend availability..."

    # Check Ollama
    if curl -s --max-time 2 "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
        log_success "✓ Ollama available at ${OLLAMA_HOST}"
    else
        log_warn "⚠ Ollama not available at ${OLLAMA_HOST}"
    fi

    # Transformers.js and ONNX are always available (no external deps)
    log_success "✓ Transformers.js backend available"
    log_success "✓ ONNX backend available"

    # TensorFlow.js is available if package is installed
    log_success "✓ TensorFlow.js backend available"
}

run_profile_tests() {
    log_info "Running profile-based integration tests..."

    export TEST_PROFILE="${TEST_PROFILE}"
    export HARPER_URL="${HARPER_URL}"
    export OLLAMA_HOST="${OLLAMA_HOST}"

    # Run tests and capture output + exit code
    local output
    output=$(node --test tests/integration/profile-deployment.test.js 2>&1)
    local exit_code=$?

    # Show last 20 lines
    echo "$output" | tail -20

    if [[ $exit_code -eq 0 ]]; then
        log_success "Profile tests passed"
        return 0
    else
        log_error "Profile tests failed"
        return 1
    fi
}

run_inference_tests() {
    log_info "Running inference tests..."

    # Find a deployed model to test
    local models
    models=$(curl -s "${HARPER_URL}/Model/" 2>/dev/null || echo "[]")

    local test_model
    test_model=$(echo "$models" | jq -r '.[0] | "\(.modelName):\(.modelVersion)"' 2>/dev/null)

    if [[ -z "$test_model" ]] || [[ "$test_model" == "null:null" ]]; then
        log_warn "No models available for inference testing"
        return 1
    fi

    local model_name model_version
    model_name=$(echo "$test_model" | cut -d: -f1)
    model_version=$(echo "$test_model" | cut -d: -f2)

    log_info "Testing inference on ${model_name}:${model_version}..."

    local response
    response=$(curl -s -X POST "${HARPER_URL}/Predict" \
        -H "Content-Type: application/json" \
        -d "{
            \"modelName\": \"${model_name}\",
            \"modelVersion\": \"${model_version}\",
            \"features\": {\"text\": \"This is a verification test\"}
        }" 2>/dev/null)

    if echo "$response" | grep -q "error"; then
        log_error "Inference failed: $(echo "$response" | jq -r '.error' 2>/dev/null || echo "Unknown error")"
        return 1
    fi

    if echo "$response" | grep -qE "embedding|embeddings|output"; then
        log_success "✓ Inference successful on ${model_name}:${model_version}"
        return 0
    else
        log_warn "⚠ Unexpected inference response format"
        return 1
    fi
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
        --remote)
            REMOTE_MODE=true
            shift
            ;;
        --profile)
            TEST_PROFILE="$2"
            shift 2
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --full)
            FULL_MODE=true
            shift
            ;;
        --deploy)
            DEPLOY_PROFILE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Use remote URL if remote mode
if [[ "$REMOTE_MODE" == "true" ]]; then
    if ! setup_remote_url "$DEPLOY_REMOTE_URL"; then
        exit 1
    fi
fi

# Header
echo ""
log_info "========================================="
log_info "Harper Edge AI - System Verification"
log_info "========================================="
echo ""
log_info "Target: ${HARPER_URL}"
log_info "Profile: ${TEST_PROFILE}"
if [[ "$QUICK_MODE" == "true" ]]; then
    log_info "Mode: Quick smoke test"
elif [[ "$FULL_MODE" == "true" ]]; then
    log_info "Mode: Full verification"
else
    log_info "Mode: Standard verification"
fi
echo ""

# Deploy profile models if requested
if [[ "$DEPLOY_PROFILE" == "true" ]]; then
    log_info "Deploying profile models: ${TEST_PROFILE}..."

    # Build preload command - always use --remote to support large ONNX files
    # The FetchModel worker bypasses HTTP body size limits
    preload_cmd="node scripts/preload-models.js --profile ${TEST_PROFILE} --remote"

    # Execute deployment
    if eval "$preload_cmd"; then
        log_success "Profile models deployed successfully"
    else
        log_error "Failed to deploy profile models"
        exit 1
    fi

    echo ""
    log_info "Waiting 5 seconds for models to initialize..."
    sleep 5
    echo ""
fi

# Run verification steps
FAILED=0

# Health check (always run)
if ! check_harper_health; then
    FAILED=1
fi

# API endpoints check (always run)
if ! check_api_endpoints; then
    FAILED=1
fi

# Exit early for quick mode
if [[ "$QUICK_MODE" == "true" ]]; then
    echo ""
    if [[ $FAILED -eq 0 ]]; then
        log_success "========================================="
        log_success "Quick Verification Passed"
        log_success "========================================="
    else
        log_error "========================================="
        log_error "Quick Verification Failed"
        log_error "========================================="
    fi
    echo ""
    exit $FAILED
fi

# Standard checks
if ! check_deployed_models; then
    FAILED=1
fi

if ! check_backends; then
    FAILED=1
fi

# Full mode includes inference tests
if [[ "$FULL_MODE" == "true" ]]; then
    if ! run_inference_tests; then
        FAILED=1
    fi

    if ! run_profile_tests; then
        FAILED=1
    fi
fi

# Summary
echo ""
if [[ $FAILED -eq 0 ]]; then
    log_success "========================================="
    log_success "Verification Complete - All Tests Passed"
    log_success "========================================="
    echo ""
    log_info "System is ready for use"
else
    log_error "========================================="
    log_error "Verification Failed - Issues Found"
    log_error "========================================="
    echo ""
    log_info "Review errors above and fix issues"
fi
echo ""

exit $FAILED
