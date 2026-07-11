# Build from the repo root so `workers/common` is in the build context:
#   docker build -f workers/tts/Dockerfile -t <registry>/tts:<tag> .
FROM runpod/base:0.6.2-cuda12.1.0

# espeak-ng: fallback phonemizer for out-of-vocabulary words in Kokoro's G2P.
RUN apt-get update && apt-get install -y --no-install-recommends espeak-ng \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY workers/tts/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY workers/common /app/common
COPY workers/tts/handler.py /app/handler.py

ENV PYTHONUNBUFFERED=1
CMD ["python3.11", "-u", "handler.py"]
