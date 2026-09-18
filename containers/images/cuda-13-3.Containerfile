# -----------------------------------------------------------------------------
# llama.cpp Server Container — CUDA 13.3 (RTX 3050, compute cap 8.6)
#
# Build:
#   just containers.build --cuda 13.3
#   # or: podman build -t llama-server:cuda13.3 -f containers/images/cuda-13-2.Containerfile containers/
#
# Run (standalone):
#   just containers.run --cuda 13.3 --model /path/to/model.gguf
#
# Run (router mode — this instance as backend):
#   just containers.router --model-a cuda12.9 --model-b cuda13.3
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Build Stage
# -----------------------------------------------------------------------------
FROM nvidia/cuda:13.3.1-devel-ubuntu26.04 AS builder

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/llama.cpp

ARG CUDA_ARCH=86

RUN git clone https://github.com/ggml-org/llama.cpp.git . \
    && cmake -B build \
       -DGGML_CUDA=ON \
       -DGGML_CUDA_BLAS=ON \
       -DGGML_CUDA_BLAS_VENDOR=NVIDIA \
       -DGGML_NATIVE=OFF \
       -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
       -DCMAKE_BUILD_TYPE=Release \
       -DBUILD_SHARED_LIBS=OFF \
    && cmake --build build --config Release -j$(nproc) --target llama-server llama-quantize llama-bench

# -----------------------------------------------------------------------------
# Runtime Stage
# -----------------------------------------------------------------------------
FROM nvidia/cuda:13.3.1-runtime-ubuntu26.04

WORKDIR /opt/llama.cpp

COPY --from=builder /opt/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=builder /opt/llama.cpp/build/bin/llama-quantize /usr/local/bin/llama-quantize
COPY --from=builder /opt/llama.cpp/build/bin/llama-bench /usr/local/bin/llama-bench

EXPOSE 9696

ENTRYPOINT ["llama-server"]
CMD ["--help"]
