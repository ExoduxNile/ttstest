#!/bin/bash

# Exit on any error
set -e

# Log function for better debugging
log() {
    echo "[INFO] $1"
}

# Step 1: Install uv if not already installed
log "Installing uv..."
if ! command -v uv &> /dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
fi
uv --version

# Step 2: Set up Python 3.12 environment
log "Setting up Python 3.12 with uv..."
uv python pin 3.12
uv venv
source .venv/bin/activate

# Step 3: Initialize project and configure dependencies
log "Configuring project with uv..."
uv init --name kokoro-tts
cat <<EOT > pyproject.toml
[project]
name = "kokoro-tts"
version = "0.1.0"
dependencies = [
    "kokoro>=0.9.4",
    "soundfile",
    "misaki[en]",
    "fastapi",
    "uvicorn",
]

[tool.uv]
python = "3.12"
EOT

# Step 4: Download Kokoro TTS model files directly
log "Downloading Kokoro TTS model files..."
if [ ! -f "voices-v1.0.bin" ]; then
    uv run wget https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/voices-v1.0.bin
fi
if [ ! -f "kokoro-v1.0.onnx" ]; then
    uv run wget https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/kokoro-v1.0.onnx
fi

# Step 5: Install dependencies
log "Installing dependencies with uv..."
uv sync

# Step 6: Create FastAPI application
log "Creating FastAPI application..."
cat <<EOT > main.py
from fastapi import FastAPI
from kokoro import KPipeline
import soundfile as sf
from fastapi.responses import StreamingResponse
import io

app = FastAPI()

# Initialize Kokoro pipeline
pipeline = KPipeline(lang_code='a')  # American English

@app.get("/tts")
async def generate_speech(text: str, voice: str = "af_sarah"):
    generator = pipeline(text, voice=voice)
    audio_data = next(generator)[2]  # Get audio from generator
    sf.write("output.wav", audio_data, 24000)
    
    # Stream the audio file
    with open("output.wav", "rb") as audio_file:
        return StreamingResponse(io.BytesIO(audio_file.read()), media_type="audio/wav")

@app.get("/")
async def root():
    return {"message": "Kokoro TTS API"}
EOT

# Step 7: Create Procfile for Render
log "Creating Procfile..."
echo "web: uvicorn main:app --host 0.0.0.0 --port \$PORT" > Procfile

# Step 8: Create runtime.txt for Python version
log "Creating runtime.txt..."
echo "python-3.12.0" > runtime.txt

# Step 9: Verify setup
log "Verifying setup..."
ls -l voices-v1.0.bin kokoro-v1.0.onnx main.py Procfile runtime.txt
uv run python -m pip list

log "Setup complete! Ready for deployment on Render."
