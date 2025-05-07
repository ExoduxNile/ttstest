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
soundfile
beautifulsoup4
pymupdf4llm
sounddevice
PyMuPDF
soundfile
ebooklib
kokoro-onnx==0.4.8
fastapi
uvicorn
EOT
onnxruntime
numpy

# Step 4: Download Kokoro TTS model files directly
log "Downloading Kokoro TTS model files..."
if [ ! -f "voices-v1.0.bin" ]; then
    wget https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/voices-v1.0.bin
fi
if [ ! -f "kokoro-v1.0.onnx" ]; then
    wget https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/kokoro-v1.0.onnx
fi

# Step 5: Install dependencies with pip
log "Installing dependencies with pip..."
pip install -r requirements.txt

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
pip list

log "Setup complete! Ready for deployment on Render."
