Stage 1: Build dependencies and download model/voice files

FROM python:3.12-slim AS builder

WORKDIR /app

Install curl for downloading files

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

Download model and voice files

RUN curl -L -o kokoro-v1.0.onnx https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/kokoro-v1.0.onnx &&
curl -L -o voices-v1.0.bin https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/voices-v1.0.bin

Copy setup script and requirements

COPY setup.sh . COPY requirements.txt .

Make setup.sh executable

RUN chmod +x setup.sh

Run setup.sh to install dependencies

RUN ./setup.sh

Stage 2: Final image

FROM python:3.12-slim

WORKDIR /app

Copy virtual environment from builder

COPY --from=builder /app/.venv .venv

Copy application files and model/voice files

COPY main.py . COPY --from=builder /app/kokoro-v1.0.onnx . COPY --from=builder /app/voices-v1.0.bin . COPY Procfile . COPY runtime.txt .

Activate virtual environment and set entrypoint

ENV PATH="/app/.venv/bin:$PATH" EXPOSE=8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
