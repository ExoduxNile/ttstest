# Stage 1: Build dependencies
FROM python:3.12-slim AS builder

WORKDIR /app

# Copy setup script and requirements
COPY setup.sh .
COPY requirements.txt .

# Make setup.sh executable
RUN chmod +x setup.sh

# Run setup.sh to install dependencies
RUN ./setup.sh

# Stage 2: Final image
FROM python:3.12-slim

WORKDIR /app

# Copy virtual environment from builder
COPY --from=builder /app/.venv .venv

# Copy application files
COPY main.py .
COPY kokoro-v1.0.onnx .
COPY voices-v1.0.bin .
COPY Procfile .
COPY runtime.txt .

# Activate virtual environment and set entrypoint
ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]