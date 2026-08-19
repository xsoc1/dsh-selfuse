# services

本地服务代码与编排。

- `image-gen/`：SDXL-Turbo 生图服务（FastAPI，端口 17821）。`server.py` 已入库；
  `venv/` 与 `hf/` 模型缓存不入库。
- `ollama/`：便携 Ollama 编排。只存 manifest/脚本，模型二进制不入库。

安装器可启动/探测这些服务（见 `dsh-control.ps1` / GUI）。
