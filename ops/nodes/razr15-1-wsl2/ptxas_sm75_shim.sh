#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == *.ptx ]]; then
    sed -i -E "s/\.version [0-9]+\.[0-9]+/.version 8.3/g" "$arg" 2>/dev/null || true
  fi
done
exec /home/an/cuda123/.pixi/envs/default/bin/ptxas "$@"
