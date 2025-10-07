# 使用 vLLM 官方提供的、包含所有依赖的基础镜像
FROM vllm/vllm-openai:v0.4.2

# 设置环境变量，直接指向 Qwen 官方的 AWQ 量化模型
# 这个模型文件更小，显存占用也大幅降低
ENV MODEL_NAME="Qwen/Qwen1.5-1.8B-Chat-AWQ"

# vLLM 服务的启动命令
CMD ["python", "-m", "vllm.entrypoints.openai.api_server", \
     "--host", "0.0.0.0", \
     "--model", env.MODEL_NAME, \
     # 关键参数：告诉 vLLM 这是一个 AWQ 量化模型
     "--quantization", "awq", \
     # 允许 vLLM 使用 90% 的 GPU 显存，为您 6GB 的显卡留出安全边际
     "--gpu-memory-utilization", "0.9", \
     # 支持的最大对话长度
     "--max-model-len", "4096"]
