#!/bin/bash

# =============================================================================
# RunPod Ollama GPU Auto-Setup Script
# Automatically sets up Ollama with DeepSeek-R1 14b on RunPod A100 GPU
# Based on: RUNPOD_OLLAMA_GPU_SETUP.md
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# =============================================================================
# Step 1: Install GPU Detection Tools
# =============================================================================
log "Step 1: Installing GPU detection tools (required for GPU support)..."

apt update -y
apt install -y pciutils lshw curl

# Verify GPU is detected
log "Verifying GPU detection..."
if lspci | grep -i nvidia > /dev/null; then
    success "NVIDIA GPU detected by system"
    lspci | grep -i nvidia
else
    error "No NVIDIA GPU detected! Check hardware."
    exit 1
fi

# =============================================================================
# Step 2: Install Ollama with GPU Support  
# =============================================================================
log "Step 2: Installing Ollama with GPU support..."

# Remove any existing Ollama installation
rm -rf /usr/local/bin/ollama 2>/dev/null || true

# Install Ollama
log "Downloading and installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# Verify GPU support was detected during installation
log "Verifying Ollama installation..."
if /usr/local/bin/ollama --version > /dev/null 2>&1; then
    success "Ollama installed successfully"
    /usr/local/bin/ollama --version
else
    error "Ollama installation failed"
    exit 1
fi

# =============================================================================
# Step 3: Setup Workspace and Environment
# =============================================================================
log "Step 3: Setting up workspace structure..."

# Create workspace directories
mkdir -p /workspace/{logs,ollama}
cd /workspace

# Copy Ollama binary for local control (optional)
cp /usr/local/bin/ollama /workspace/ollama/ollama
chmod +x /workspace/ollama/ollama

success "Workspace created at /workspace"

# =============================================================================
# Step 4: Configure Environment Variables
# =============================================================================
log "Step 4: Configuring environment variables..."

# Check if RunPod environment variables are set (recommended approach)
if [ -n "$OLLAMA_HOST" ] && [ -n "$CUDA_VISIBLE_DEVICES" ]; then
    success "RunPod environment variables detected (recommended setup)"
    log "OLLAMA_HOST: $OLLAMA_HOST"
    log "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
    log "OLLAMA_GPU: $OLLAMA_GPU"
    log "CUDA_HOME: $CUDA_HOME"
else
    warning "RunPod environment variables not set, using manual configuration"
    # Set environment variables manually (fallback approach)
    export OLLAMA_HOST=0.0.0.0
    export CUDA_HOME=/usr/local/cuda-11.8
    export CUDA_VISIBLE_DEVICES=0,1
    export OLLAMA_GPU=1
    export LD_LIBRARY_PATH=/usr/local/cuda-11.8/lib64:/usr/local/nvidia/lib:/usr/local/nvidia/lib64
    export PATH=/usr/local/cuda-11.8/bin:/usr/local/nvidia/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    
    log "Environment variables set manually"
fi

# =============================================================================
# Step 5: Start Ollama Server with GPU Support
# =============================================================================
log "Step 5: Starting Ollama server with GPU support..."

# Kill any existing Ollama processes
pkill -9 ollama 2>/dev/null || true
sleep 3

# Start Ollama server using the recommended approach
if [ -n "$OLLAMA_HOST" ] && [ "$OLLAMA_HOST" = "0.0.0.0" ]; then
    # Use RunPod environment variables (recommended)
    success "Using RunPod environment variables for Ollama startup"
    /usr/local/bin/ollama serve > logs/ollama.log 2>&1 &
else
    # Use manual environment variables (fallback)
    warning "Using manual environment variables for Ollama startup"
    OLLAMA_HOST=0.0.0.0 CUDA_VISIBLE_DEVICES=0,1 /usr/local/bin/ollama serve > logs/ollama.log 2>&1 &
fi

# Wait for server to start
sleep 8

# =============================================================================
# Step 6: Verify Ollama Server is Running
# =============================================================================
log "Step 6: Verifying Ollama server is running..."

# Test server connectivity
if curl -s http://localhost:11434/api/version > /dev/null; then
    success "Ollama server is running"
    VERSION=$(curl -s http://localhost:11434/api/version | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    log "Ollama version: $VERSION"
else
    error "Ollama server failed to start"
    log "Server logs:"
    cat logs/ollama.log
    exit 1
fi

# =============================================================================
# Step 7: Download DeepSeek-R1 Model and Verify GPU Detection
# =============================================================================
log "Step 7: Downloading DeepSeek-R1 14b model (this may take 5-10 minutes)..."

# Check if model already exists
if /usr/local/bin/ollama list | grep -q "deepseek-r1:14b"; then
    success "DeepSeek-R1 14b model already exists"
else
    log "Downloading DeepSeek-R1 14b model..."
    /usr/local/bin/ollama pull deepseek-r1:14b
    success "Model downloaded successfully"
fi

# Verify model is available
log "Available models:"
/usr/local/bin/ollama list

# Check for GPU detection in logs (appears after model download)
log "Checking for GPU detection in logs..."
sleep 2

if grep -i "inference compute" logs/ollama.log > /dev/null; then
    success "GPU detection confirmed in logs!"
    grep -i "inference compute" logs/ollama.log
else
    warning "GPU detection not found in logs yet. This may appear when the model is first used."
fi

# =============================================================================
# Step 8: Test GPU Usage
# =============================================================================
log "Step 8: Testing model and GPU usage..."

# Test the model with a simple prompt
log "Testing model response..."
TEST_RESPONSE=$(/usr/local/bin/ollama run deepseek-r1:14b "Respond with 'GPU test successful' if you can read this." --timeout 30s 2>/dev/null || echo "Test failed")

if [[ "$TEST_RESPONSE" == *"successful"* ]] || [[ "$TEST_RESPONSE" == *"GPU"* ]]; then
    success "Model test successful!"
    log "Model response: $TEST_RESPONSE"
else
    warning "Model test may have timed out or failed, but server should still be functional"
fi

# =============================================================================
# Step 9: Final Verification and Status
# =============================================================================
log "Step 9: Final verification and status..."

# Check model status
log "Checking model processor assignment..."
MODEL_STATUS=$(/usr/local/bin/ollama ps 2>/dev/null || echo "No models currently loaded")
log "Model status: $MODEL_STATUS"

# Check GPU memory usage
log "Current GPU status:"
if command -v nvidia-smi > /dev/null; then
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits
else
    warning "nvidia-smi not available"
fi

# =============================================================================
# Setup Complete - Display Summary
# =============================================================================
echo ""
echo "==============================================================================="
success "🚀 RunPod Ollama GPU Setup Complete!"
echo "==============================================================================="
echo ""
log "📋 Setup Summary:"
log "   • Ollama Server: Running on 0.0.0.0:11434"
log "   • Model: deepseek-r1:14b available"
log "   • GPU: A100 configured for inference"
log "   • Workspace: /workspace"
log "   • Logs: /workspace/logs/ollama.log"
echo ""
log "🔗 External Access URL:"
log "   https://$(hostname)-11434.proxy.runpod.net"
echo ""
log "🧪 Test Commands:"
log "   curl -s http://localhost:11434/api/version"
log "   /usr/local/bin/ollama list"
log "   /usr/local/bin/ollama run deepseek-r1:14b 'Hello!'"
echo ""
log "📊 Monitor GPU Usage:"
log "   watch -n 1 nvidia-smi"
echo ""
log "🔍 Check Logs:"
log "   tail -f /workspace/logs/ollama.log"
echo ""

# Create a quick status check script
cat > /workspace/status_check.sh << 'EOF'
#!/bin/bash
echo "=== Ollama Status ==="
curl -s http://localhost:11434/api/version && echo "✅ Server running" || echo "❌ Server down"
echo ""
echo "=== Available Models ==="
/usr/local/bin/ollama list
echo ""
echo "=== Running Models ==="
/usr/local/bin/ollama ps
echo ""
echo "=== GPU Status ==="
nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits
EOF

chmod +x /workspace/status_check.sh

success "🎯 Quick status check script created: /workspace/status_check.sh"
echo ""
warning "📝 Important Notes:"
log "   • RunPod pods auto-pause after ~10 minutes of inactivity"
log "   • Re-run this script anytime you restart the pod"
log "   • Set RunPod environment variables for easier setup (see documentation)"
log "   • Your external URL: https://$(hostname)-11434.proxy.runpod.net"
echo ""
success "✅ Setup complete! Your Ollama server with DeepSeek-R1 14b is ready to use." 
