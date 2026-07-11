# Build from the repo root so `workers/common` is in the build context:
#   docker build -f workers/video_gen/Dockerfile -t <registry>/video-gen:<tag> .
FROM runpod/base:0.6.2-cuda12.1.0

WORKDIR /app

COPY workers/video_gen/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY workers/common /app/common
COPY workers/video_gen/handler.py /app/handler.py

ENV PYTHONUNBUFFERED=1
CMD ["python", "-u", "handler.py"]
