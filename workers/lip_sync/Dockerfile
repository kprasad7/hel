# Build from the repo root so `workers/common` is in the build context:
#   docker build -f workers/lip_sync/Dockerfile -t <registry>/lip-sync:<tag> .
#
# Verified against github.com/TMElyralab/MuseTalk (README "Installation" section
# and inference.sh) on 2026-07-11 — MuseTalk isn't a pip-installable library, so
# this vendors their repo and shells out to their CLI script per request (see
# handler.py for why that means no warm-start benefit for this stage, unlike
# the other workers). Re-check the upstream repo if this stops building; `main`
# is not pinned to a commit here and could change under us.
FROM runpod/base:0.6.2-cuda12.1.0

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone --depth 1 https://github.com/TMElyralab/MuseTalk.git /app/MuseTalk
WORKDIR /app/MuseTalk

# MuseTalk's documented env: torch 2.0.1/cu118 wheels (run fine on newer driver
# hosts like RunPod's A100s, which is the standard cross-CUDA-minor pattern),
# then their requirements.txt, then the MMLab stack.
RUN pip install --no-cache-dir torch==2.0.1 torchvision==0.15.2 torchaudio==2.0.2 \
    --index-url https://download.pytorch.org/whl/cu118
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir -U openmim \
    && mim install mmengine \
    && mim install "mmcv==2.0.1" \
    && mim install "mmdet==3.1.0" \
    && mim install "mmpose==1.1.0"

# Bakes model weights into the image (multi-GB) so cold starts don't also pay
# a weight-download cost. download_weights.sh additionally does `pip install`
# for huggingface_hub[cli]/gdown, already covered above by requirements.txt.
RUN bash download_weights.sh

RUN pip install --no-cache-dir runpod pynvml requests pyyaml

COPY workers/common /app/MuseTalk/common
COPY workers/lip_sync/handler.py /app/MuseTalk/handler.py

ENV PYTHONUNBUFFERED=1
CMD ["python3.11", "-u", "handler.py"]
