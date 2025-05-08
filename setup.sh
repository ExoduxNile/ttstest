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
kokoro-onnx==0.3.9
soundfile
fastapi
uvicorn
numpy
kokoro>=0.9.4
EOT

# Step 4: Install dependencies with pip (optimized for low memory)
log "Installing dependencies with pip..."
pip install --no-cache-dir -r requirements.txt

# Step 5: Verify main.py exists
log "Verifying main.py..."
if [ ! -f "main.py" ]; then
    log "Error: main.py not found in repository"
    exit 1
fi

# Step 6: Create Procfile for Render
log "Creating Procfile..."
echo "web: uvicorn main:app --host 0.0.0.0 --port \$PORT" > Procfile

# Step 7: Create runtime.txt for Python version
log "Creating runtime.txt..."
echo "python-3.12.0" > runtime.txt

# Step 8: Verify setup
log "Verifying setup..."
ls -l main.py Procfile runtime.txt
pip list

log "Setup complete! Ready for deployment on Render."
