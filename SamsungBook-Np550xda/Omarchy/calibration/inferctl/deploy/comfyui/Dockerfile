FROM python:3.12-slim-bookworm@sha256:6a0e06f5ba0b373d051aabd3fffb9b873f27f9a2a3a14bcbe37dee6f0e3bbc70
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 HOME=/tmp
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 && rm -rf /var/lib/apt/lists/*
ADD --checksum=sha256:78ef9a9a068fc659ddcc79038b2e06854e6fbfaeb9c328d7dbcacd3d3c9c4361 https://codeload.github.com/Comfy-Org/ComfyUI/tar.gz/19ae172bff6c9e4c738e7f2e00fe087f5b5b46ab /tmp/comfy.tar.gz
RUN mkdir -p /app/ComfyUI && tar -xzf /tmp/comfy.tar.gz --strip-components=1 -C /app/ComfyUI && rm /tmp/comfy.tar.gz
WORKDIR /app/ComfyUI
RUN python -m pip install torch==2.14.1+cpu torchvision==0.29.1+cpu --index-url https://download.pytorch.org/whl/cpu
RUN python -m pip install -r requirements.txt && python -m pip check && python -m pip freeze > /app/requirements-resolved.txt
RUN python -m pip install gguf==0.19.0 && python -m pip check && python -m pip freeze > /app/requirements-resolved.txt
LABEL org.opencontainers.image.source="https://github.com/Comfy-Org/ComfyUI" org.opencontainers.image.revision="19ae172bff6c9e4c738e7f2e00fe087f5b5b46ab"
USER 1000:1000
EXPOSE 8188
ENTRYPOINT ["python", "/app/ComfyUI/main.py"]
CMD ["--cpu", "--listen", "0.0.0.0", "--port", "8188", "--offline"]
