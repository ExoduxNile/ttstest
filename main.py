from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import os
import io
import numpy as np
from ebooklib import epub, ITEM_DOCUMENT
from bs4 import BeautifulSoup
import soundfile as sf
from kokoro_onnx import Kokoro
import fitz
import warnings
import re
import pymupdf4llm

import asyncio

# Suppress warnings
warnings.filterwarnings("ignore", category=UserWarning, module='ebooklib')
warnings.filterwarnings("ignore", category=FutureWarning, module='ebooklib')

app = FastAPI()

# Add CORS middleware for external form access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://tropley.com"],  # Adjust for specific origins in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Kokoro model globally with error handling for missing files
model_path = "kokoro-v1.0.onnx"
voices_path = "voices-v1.0.bin"
if not os.path.exists(model_path) or not os.path.exists(voices_path):
    raise HTTPException(status_code=500, detail=f"Missing model or voice files: {model_path}, {voices_path}")
kokoro = Kokoro(model_path, voices_path)

def chunk_text(text, initial_chunk_size=1000):
    """Split text into chunks at sentence boundaries with dynamic sizing."""
    sentences = text.replace('\n', ' ').split('.')
    chunks = []
    current_chunk = []
    current_size = 0
    chunk_size = initial_chunk_size
    
    for sentence in sentences:
        if not sentence.strip():
            continue
        sentence = sentence.strip() + '.'
        sentence_size = len(sentence)
        
        if sentence_size > chunk_size:
            words = sentence.split()
            current_piece = []
            current_piece_size = 0
            for word in words:
                word_size = len(word) + 1
                if current_piece_size + word_size > chunk_size:
                    if current_piece:
                        chunks.append(' '.join(current_piece).strip() + '.')
                    current_piece = [word]
                    current_piece_size = word_size
                else:
                    current_piece.append(word)
                    current_piece_size += word_size
            if current_piece:
                chunks.append(' '.join(current_piece).strip() + '.')
            continue
        
        if current_size + sentence_size > chunk_size and current_chunk:
            chunks.append(' '.join(current_chunk))
            current_chunk = []
            current_size = 0
        
        current_chunk.append(sentence)
        current_size += sentence_size
    
    if current_chunk:
        chunks.append(' '.join(current_chunk))
    
    return chunks

def validate_language(lang):
    """Validate if the language is supported."""
    supported_languages = set(kokoro.get_languages())
    if lang not in supported_languages:
        raise HTTPException(status_code=400, detail=f"Unsupported language: {lang}. Supported: {', '.join(sorted(supported_languages))}")
    return lang

def validate_voice(voice):
    """Validate single or blended voices."""
    supported_voices = set(kokoro.get_voices())
    if ',' in voice:
        voices = []
        weights = []
        for pair in voice.split(','):
            if ':' in pair:
                v, w = pair.strip().split(':')
                voices.append(v.strip())
                weights.append(float(w.strip()))
            else:
                voices.append(pair.strip())
                weights.append(50.0)
        if len(voices) != 2:
            raise HTTPException(status_code=400, detail="Voice blending requires exactly two voices")
        for v in voices:
            if v not in supported_voices:
                raise HTTPException(status_code=400, detail=f"Unsupported voice: {v}. Supported: {', '.join(sorted(supported_voices))}")
        total = sum(weights)
        if total != 100:
            weights = [w * (100/total) for w in weights]
        style1 = kokoro.get_voice_style(voices[0])
        style2 = kokoro.get_voice_style(voices[1])
        blend = np.add(style1 * (weights[0]/100), style2 * (weights[1]/100))
        return blend
    if voice not in supported_voices:
        raise HTTPException(status_code=400, detail=f"Unsupported voice: {voice}. Supported: {', '.join(sorted(supported_voices))}")
    return voice

def extract_text_from_epub(epub_content):
    """Extract text from EPUB file content."""
    with open("temp.epub", "wb") as f:
        f.write(epub_content)
    book = epub.read_epub("temp.epub")
    full_text = ""
    for item in book.get_items():
        if item.get_type() == ITEM_DOCUMENT:
            soup = BeautifulSoup(item.get_body_content(), "html.parser")
            full_text += soup.get_text()
    os.remove("temp.epub")
    return full_text

def extract_text_from_pdf(pdf_content):
    """Extract text from PDF file content."""
    with open("temp.pdf", "wb") as f:
        f.write(pdf_content)
    doc = fitz.open("temp.pdf")
    full_text = ""
    for page in doc:
        full_text += page.get_text()
    doc.close()
    os.remove("temp.pdf")
    return full_text

async def process_chunk_sequential(chunk, voice, speed, lang):
    """Process a single chunk of text sequentially."""
    try:
        samples, sample_rate = kokoro.create(chunk, voice=voice, speed=speed, lang=lang)
        return samples, sample_rate
    except Exception as e:
        if "index 510 is out of bounds" in str(e):
            words = chunk.split()
            new_size = int(len(chunk) * 0.6)
            pieces = []
            current_piece = []
            current_size = 0
            for word in words:
                word_size = len(word) + 1
                if current_size + word_size > new_size:
                    if current_piece:
                        pieces.append(' '.join(current_piece).strip())
                    current_piece = [word]
                    current_size = word_size
                else:
                    current_piece.append(word)
                    current_size += word_size
            if current_piece:
                pieces.append(' '.join(current_piece).strip())
            all_samples = []
            last_sample_rate = None
            for piece in pieces:
                samples, sr = await process_chunk_sequential(piece, voice, speed, lang)
                if samples is not None:
                    all_samples.extend(samples)
                    last_sample_rate = sr
            return all_samples, last_sample_rate
        raise HTTPException(status_code=500, detail=f"Error processing chunk: {str(e)}")

@app.get("/")
async def root():
    return {"message": "Kokoro TTS API"}

@app.get("/voices")
async def list_voices():
    """List available voices."""
    voices = list(kokoro.get_voices())
    return {"voices": voices}

@app.get("/languages")
async def list_languages():
    """List supported languages."""
    languages = list(kokoro.get_languages())
    return {"languages": languages}

@app.post("/tts")
async def text_to_speech(
    text: str = Form(...),
    voice: str = Form("af_sarah"),
    speed: float = Form(1.0),
    lang: str = Form("en-us"),
    format: str = Form("wav")
):
    """Convert text to speech."""
    if format not in ["wav", "mp3"]:
        raise HTTPException(status_code=400, detail="Format must be 'wav' or 'mp3'")
    lang = validate_language(lang)
    voice = validate_voice(voice)
    chunks = chunk_text(text, initial_chunk_size=1000)
    all_samples = []
    sample_rate = None
    for chunk in chunks:
        samples, sr = await process_chunk_sequential(chunk, voice, speed, lang)
        if samples is not None:
            if sample_rate is None:
                sample_rate = sr
            all_samples.extend(samples)
    if not all_samples:
        raise HTTPException(status_code=500, detail="No audio generated")
    buffer = io.BytesIO()
    sf.write(buffer, all_samples, sample_rate, format=format)
    buffer.seek(0)
    return StreamingResponse(buffer, media_type=f"audio/{format}", headers={"Content-Disposition": f"attachment; filename=output.{format}"})

@app.post("/upload-epub")
async def upload_epub(
    file: UploadFile = File(...),
    voice: str = Form("af_sarah"),
    speed: float = Form(1.0),
    lang: str = Form("en-us"),
    format: str = Form("wav")
):
    """Convert EPUB to speech."""
    if not file.filename.endswith(".epub"):
        raise HTTPException(status_code=400, detail="File must be an EPUB")
    if format not in ["wav", "mp3"]:
        raise HTTPException(status_code=400, detail="Format must be 'wav' or 'mp3'")
    lang = validate_language(lang)
    voice = validate_voice(voice)
    content = await file.read()
    text = extract_text_from_epub(content)
    chunks = chunk_text(text, initial_chunk_size=1000)
    all_samples = []
    sample_rate = None
    for chunk in chunks:
        samples, sr = await process_chunk_sequential(chunk, voice, speed, lang)
        if samples is not None:
            if sample_rate is None:
                sample_rate = sr
            all_samples.extend(samples)
    if not all_samples:
        raise HTTPException(status_code=500, detail="No audio generated")
    buffer = io.BytesIO()
    sf.write(buffer, all_samples, sample_rate, format=format)
    buffer.seek(0)
    return StreamingResponse(buffer, media_type=f"audio/{format}", headers={"Content-Disposition": f"attachment; filename=output.{format}"})

@app.post("/upload-pdf")
async def upload_pdf(
    file: UploadFile = File(...),
    voice: str = Form("af_sarah"),
    speed: float = Form(1.0),
    lang: str = Form("en-us"),
    format: str = Form("wav")
):
    """Convert PDF to speech."""
    if not file.filename.endswith(".pdf"):
        raise HTTPException(status_code=400, detail="File must be a PDF")
    if format not in ["wav", "mp3"]:
        raise HTTPException(status_code=400, detail="Format must be 'wav' or 'mp3'")
    lang = validate_language(lang)
    voice = validate_voice(voice)
    content = await file.read()
    text = extract_text_from_pdf(content)
    chunks = chunk_text(text, initial_chunk_size=1000)
    all_samples = []
    sample_rate = None
    for chunk in chunks:
        samples, sr = await process_chunk_sequential(chunk, voice, speed, lang)
        if samples is not None:
            if sample_rate is None:
                sample_rate = sr
            all_samples.extend(samples)
    if not all_samples:
        raise HTTPException(status_code=500, detail="No audio generated")
    buffer = io.BytesIO()
    sf.write(buffer, all_samples, sample_rate, format=format)
    buffer.seek(0)
    return StreamingResponse(buffer, media_type=f"audio/{format}", headers={"Content-Disposition": f"attachment; filename=output.{format}"})
