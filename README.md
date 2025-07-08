# RunPod Ollama Toolkit 🚀

Automated setup scripts for RunPod GPU instances with Ollama and large language models.

## Usage

To download and run a script from this repository on your RunPod instance:

```bash
# 1. Navigate to workspace
cd /workspace

# 2. Download the script (note the correct raw URL with %20 for spaces)
curl -O "https://raw.githubusercontent.com/CompliBioAI/runpod_toolkit/main/A100%20SXM%20-%20Deepseek-14b/runpod_restart_script.sh"

# 3. Make it executable
chmod +x runpod_restart_script.sh

# 4. Run the script
./runpod_restart_script.sh
```

**Note:** The folder name can be different depending on the specific script you want to use. Replace `A100%20SXM%20-%20Deepseek-14b` in the URL with the appropriate folder name from this repository, ensuring spaces are encoded as `%20`.
