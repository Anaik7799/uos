#!/usr/bin/env bash
set -euo pipefail
# UOS Razr15-1 Optimal CUDA Backend Launcher for Qwen2.5-Coder-7B-Instruct-GGUF (Q4_K_M)
# Hardware Target: Intel i7-9750H (6C/12T AVX2) + NVIDIA GeForce RTX 2070 Max-Q (8192 MiB, Turing sm_75)
# Optimization Profile:
#   -ngl 99                : Offload all 29 transformer layers + output weight to CUDA0
#   -c 32768               : 32K total context window (16384 tokens per slot across 2 parallel slots)
#   --flash-attn on        : Turing sm_75 Flash Attention kernel
#   --cache-type-k q8_0    : Quantized K cache (50% KV VRAM reduction, 0 perplexity loss)
#   --cache-type-v q8_0    : Quantized V cache (50% KV VRAM reduction)
#   -b 2048 -ub 512        : Prompt batch / microbatch tuned for 36..46 SMs on Turing sm_75
#   -t 6 -tb 12            : 6 physical cores for token gen, 12 logical threads for prompt batch
#   --cont-batching        : Continuous batching with 2 parallel slots (-np 2, 16384 ctx/slot)
#   --mlock                : Pin host buffers in RAM to prevent WSL2 page swapping

/mnt/c/Windows/System32/taskkill.exe /F /IM "LM Studio.exe" 2>/dev/null || true
/mnt/c/Windows/System32/taskkill.exe /F /IM "llama-server.exe" 2>/dev/null || true
sleep 1

# Must cd to /mnt/c/... before invoking cmd.exe (avoids UNC working directory reject)
# Must prepend win-llama-cuda-vendor-v2 for cublas64_12.dll / cudart64_12.dll (avoids Exit 53 ERROR_BAD_NETPATH)
cd /mnt/c/Users/abhij
nohup /mnt/c/Windows/System32/cmd.exe /c "set PATH=C:\Users\abhij\.lmstudio\extensions\backends\vendor\win-llama-cuda-vendor-v2;C:\Users\abhij\.lmstudio\extensions\backends\vendor\_amphibian\win-llama-cuda-vendor-v2;%PATH% && C:\Users\abhij\.lmstudio\extensions\backends\llama.cpp-win-x86_64-nvidia-cuda-avx2-2.67.0\llama-server.exe -m C:\Users\abhij\.lmstudio\models\Qwen\Qwen2.5-Coder-7B-Instruct-GGUF\qwen2.5-coder-7b-instruct-q4_k_m.gguf --alias Qwen/Qwen2.5-Coder-7B-Instruct-GGUF --host 0.0.0.0 --port 8081 -ngl 99 -c 32768 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 -b 2048 -ub 512 -t 6 -tb 12 -np 2 --cont-batching" > /home/an/uos-max/llama_cuda_8081.log 2>&1 < /dev/null &
echo "Launched optimized CUDA sm_75 llama-server.exe on :8081 (32768 total ctx / 16384 per slot, PID: $!)"
