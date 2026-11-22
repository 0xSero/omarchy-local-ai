# Local Adreno image. Build it on the Snapdragon (linux/arm64), not on an x86 machine:
# the CPU flags are those of the machine that runs the compiler.
#
#   docker build -f docker/adreno/Dockerfile -t omarchy-local-ai/adreno-vulkan:local docker/adreno
#
# Local AI uses this tag instead of the pinned ghcr.io/ggml-org/llama.cpp:server-vulkan
# image when the tag exists. Build it when the pinned image's Mesa does not list the
# Adreno (engine log: "ggml_vulkan: No devices found") but `vulkaninfo` on the host does.
# Ubuntu 26.04 is the same base as that pinned image; swap MESA packages here if a newer
# Turnip is required. GGML_NATIVE=ON targets this Oryon CPU (NEON, dotprod, fp16, i8mm;
# do not force SVE — first-generation Oryon does not have it).

FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates cmake git ninja-build pkg-config \
    libvulkan-dev vulkan-tools mesa-vulkan-drivers glslc spirv-headers libssl-dev \
 && rm -rf /var/lib/apt/lists/*

# Same llama.cpp revision as ghcr.io/ggml-org/llama.cpp:server-vulkan b12211.
ARG LLAMA_REV=7d7f0287530bc8981690f361d8c1627dbae1c99a
RUN git clone https://github.com/ggml-org/llama.cpp /src \
 && git -C /src checkout "$LLAMA_REV" \
 && cmake -S /src -B /src/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DGGML_NATIVE=ON -DGGML_VULKAN=ON -DLLAMA_BUILD_TESTS=OFF -DGGML_BACKEND_DL=OFF \
 && cmake --build /src/build --target llama-server -j"$(nproc)" \
 && mkdir -p /app \
 && cp /src/build/bin/llama-server /app/llama-server \
 && rm -rf /src

ENV LLAMA_ARG_HOST=0.0.0.0 \
    LLAMA_ARG_PORT=8080 \
    VK_DRIVER_FILES=/usr/share/vulkan/icd.d/freedreno_icd.json
WORKDIR /app
ENTRYPOINT ["/app/llama-server"]
