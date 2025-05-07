#!/bin/bash

# Exit on any error
set -e

# Log function for better debugging
log() {
    echo "[INFO] $1"
}

# Step 1: Ensure Python 3.12 is active
log "Setting up Python environment..."
python3 --version

# Step 2: Create virtual environment
log "Creating virtual environment..."
python3 -m venv .venv
source .venv/bin/activate

# Step 3: Configure dependencies with requirements.txt
log "Configuring dependencies..."
cat <<EOT > requirements.txt
kokoro>=0.9.4
kokoro-onnx==0.4.8
fastapi
uvicorn
soundfile
beautifulsoup4
# Removed unnecessary dependencies
# sounddevice  # Not used in main.py
# PyMuPDF      # Redundant with pymupdf4llm
EOT

# Step 4: Skip downloading Kokoro TTS model files to save memory
log "Skipping download of Kokoro TTS model files to reduce memory usage"
# Optionally, add logic to download specific files manually later
# Download either voices.json or voices.bin (bin is preferred)
wget https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/voices-v1.0.bin

# Download the model
wget https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/kokoro-v1.0.onnx

# Step 5: Install dependencies with pip
log "Installing dependencies with pip..."
pip install -r requirements.txt

# Step 6: Assume main.py is provided in the repository (use uploaded main.py)
log "Using provided main.py for FastAPI application"
# Ensure main.py exists in the repository; no need to create a new one
if [ ! -f "main.py" ]; then
    log "Error: main.py not found in repository"
    exit 1
fi

# Step 7: Create Procfile for Render
log "Creating Procfile..."
echo "web: uvicorn main:app --host 0.0.0.0 --port \$PORT" > Procfile

# Step 8: Create runtime.txt for Python version
log "Creating runtime.txt..."
echo "python-3.12.0" > runtime.txt

# Step 9: Verify setup
log "Verifying setup..."
ls -l main.py Procfile runtime.txt
pip list

log "Setup complete! Ready for deployment on Render."
