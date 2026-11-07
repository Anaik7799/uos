#!/usr/bin/env bash
set -euo pipefail

# Canonical UOS Razr15-1 Modular MAX 26.8.0 + Mojo 1.3.0 + CUDA Qwen2.5-Coder-7B Supervisor
# - Launches Windows CUDA sm_75 llama-server.exe worker on :8081 (29/29 layers offloaded, 8192 ctx, FlashAttn)
# - Launches Pixi-managed Modular MAX 26.8.0 / Mojo 1.3.0 OpenAI-compatible gateway on :8000
# - Launches Windows-host Erlang TCP proxy on 0.0.0.0:8000 (rule 'UOS-C3I-Erlang-Runtime' Public Allow)

export PATH="/home/an/.pixi/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LD_PRELOAD="/home/an/uos-max/libcuda_shim.so"
export MODULAR_NVPTX_COMPILER_PATH="/home/an/uos-max/ptxas_sm75_shim.sh"
export LD_LIBRARY_PATH="/usr/lib/wsl/lib:/home/an/uos-max/.pixi/envs/default/lib:${LD_LIBRARY_PATH:-}"

export RAZR1_WIN_HOST="100.114.9.28"
export MAX_BACKEND_URL="http://100.114.9.28:8081"
export MAX_QWEN_BACKEND_URL="http://100.114.9.28:8081"

# 1. Reclaim VRAM if LM Studio GUI is running
/mnt/c/Windows/System32/taskkill.exe /F /IM "LM Studio.exe" >/dev/null 2>&1 || true

# 2. Ensure CUDA sm_75 worker on :8081 is running
if ! curl -s --max-time 2 "${MAX_QWEN_BACKEND_URL}/health" | grep -q 'ok'; then
  nohup /home/an/uos-max/run_llama_cuda_8081.sh > /home/an/uos-max/llama_cuda_8081.log 2>&1 < /dev/null &
  disown
fi

# 3. Ensure Pixi MAX 26.8.0 Gateway on :8000 is running
if ! pgrep -f 'max_qwen_server.py' >/dev/null 2>&1; then
  nohup /home/an/uos-max/.pixi/envs/default/bin/python /home/an/uos-max/max_qwen_server.py > /home/an/uos-max/max_qwen_8000.log 2>&1 < /dev/null &
  disown
fi

# 4. Ensure Windows Erlang TCP proxy on 0.0.0.0:8000 -> WSL2:8000 is running
WSL_IP=$(hostname -I | awk '{print $1}')
WSL_TUPLE=$(echo "${WSL_IP}" | tr '.' ',')
sed -i "s/{172,[0-9]*,[0-9]*,[0-9]*}/{${WSL_TUPLE}}/g" /home/an/uos-max/tcp_proxy_8000.escript
cp -f /home/an/uos-max/tcp_proxy_8000.escript /mnt/c/Users/abhij/tcp_proxy_8000.escript
if ! /mnt/c/Windows/System32/netstat.exe -ano | grep -q ':8000.*LISTENING'; then
  nohup /mnt/c/Windows/System32/cmd.exe /c "C:\\Users\\abhij\\bin\\erl\\bin\\escript.exe C:\\Users\\abhij\\tcp_proxy_8000.escript" > /home/an/uos-max/tcp_proxy_8000.log 2>&1 < /dev/null &
  disown
fi

for i in $(seq 1 30); do
  if curl -s --max-time 2 "http://127.0.0.1:8000/v1/models" | grep -q 'Qwen2.5-Coder-7B'; then
    echo "READY: MAX 26.8.0 Gateway (:8000) + CUDA sm_75 Worker (:8081) + Tailnet Proxy (100.114.9.28:8000) online"
    exit 0
  fi
  sleep 1
done

echo "ERROR: Pipeline did not become ready in time"
exit 1
