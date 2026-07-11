# Build from the repo root:
#   docker build -f workers/assembly/Dockerfile -t <registry>/assembly:<tag> .
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN pip install --no-cache-dir boto3

COPY services/common/dynamo.py /app/common/dynamo.py
COPY services/common/models.py /app/common/models.py
RUN touch /app/common/__init__.py
COPY workers/assembly/main.py /app/main.py

ENV PYTHONUNBUFFERED=1
CMD ["python", "-u", "main.py"]
