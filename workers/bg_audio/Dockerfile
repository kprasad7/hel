# Build from the repo root so `workers/common` is in the build context:
#   docker build -f workers/bg_audio/Dockerfile -t <registry>/bg-audio:<tag> .
FROM runpod/base:0.6.2-cuda12.1.0

WORKDIR /app

COPY workers/bg_audio/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY workers/common /app/common
COPY workers/bg_audio/handler.py /app/handler.py

ENV PYTHONUNBUFFERED=1
CMD ["python", "-u", "handler.py"]
