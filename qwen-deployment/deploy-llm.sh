#!/bin/bash

# ==============================================================================
#           大模型应用自动化部署脚本 (v1)
#
# 功能:
# 1. 清理旧的 Kubernetes 资源
# 2. 使用 Dockerfile 构建本地镜像
# 3. 将镜像加载到 Kind 集群
# 4. 应用 deployment.yaml 文件进行部署
# 5. 提供后续的验证和访问指令
#
# 使用方法:
# 1. 将此脚本放置在包含 Dockerfile 和 deployment.yaml 的目录中
# 2. 给予执行权限: chmod +x deploy-llm.sh
# 3. 运行脚本: ./deploy-llm.sh
# ==============================================================================

# --- 配置区 (如果需要，可在此处修改) ---
# Docker 镜像相关
IMAGE_NAME="qwen1.8b-awq"
IMAGE_TAG="v1"

# Kubernetes 相关
DEPLOYMENT_FILE="deployment.yaml"
CLUSTER_NAME="llm-research-cluster" # 必须与您的 Kind 集群名称一致
APP_LABEL="qwen-awq"                # 必须与 deployment.yaml 中的 app label 一致

# 组合最终名称
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
DEPLOYMENT_NAME="${APP_LABEL}-deployment"
SERVICE_NAME="${APP_LABEL}-service"

# --- 辅助函数 (用于彩色输出) ---
info() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

error() {
    echo -e "\033[31m[ERROR] $1\033[0m"
    exit 1
}

warn() {
    echo -e "\033[33m[WARN] $1\033[0m"
}

# --- 脚本主逻辑 ---

# 步骤 0: 环境检查
info "正在检查所需文件..."
if [ ! -f "Dockerfile" ] || [ ! -f "${DEPLOYMENT_FILE}" ]; then
    error "错误: Dockerfile 或 ${DEPLOYMENT_FILE} 不存在于当前目录！请将脚本放置在正确的位置。"
fi
info "文件检查通过。"
echo ""

# 步骤 1: 清理旧的 Kubernetes 资源
info "第 1 步: 正在清理旧的 Deployment 和 Service (如果存在)..."
kubectl delete deployment ${DEPLOYMENT_NAME} --ignore-not-found=true
kubectl delete service ${SERVICE_NAME} --ignore-not-found=true
# 等待资源彻底删除，避免立即重建时发生冲突
sleep 3
info "清理完成。"
echo ""

# 步骤 2: 构建 Docker 镜像
info "第 2 步: 正在使用 Dockerfile 构建镜像: ${FULL_IMAGE_NAME}..."
docker build -t ${FULL_IMAGE_NAME} . || error "Docker 镜像构建失败！"
info "镜像构建成功。"
echo ""

# 步骤 3: 加载镜像到 Kind 集群
info "第 3 步: 正在将镜像加载到 Kind 集群 '${CLUSTER_NAME}'..."
warn "这个过程可能会很慢，因为它需要复制整个镜像文件，请耐心等待..."
kind load docker-image ${FULL_IMAGE_NAME} --name ${CLUSTER_NAME} || error "加载镜像到 Kind 失败！"
info "镜像加载成功。"
echo ""

# 步骤 4: 应用 Kubernetes manifest 文件
info "第 4 步: 正在应用 Kubernetes 部署文件 '${DEPLOYMENT_FILE}'..."
kubectl apply -f ${DEPLOYMENT_FILE} || error "应用 Kubernetes manifest 失败！"
info "部署指令已成功发送到集群。"
echo ""

# --- 部署完成后的指引 ---
info "✅ 自动化部署脚本执行完毕！"
info "您的模型 Pod 正在后台启动，这需要几分钟时间来下载模型文件。"
echo ""
info "--- 接下来请按以下步骤操作 ---"
echo "1. 打开一个新的终端，使用以下命令监控 Pod 状态："
echo -e "\033[33mkubectl get pods -l app=${APP_LABEL} --watch\033[0m"
echo "   (等待 Pod 状态变为 Running)"
echo ""
echo "2. Pod 变为 Running 后，再打开一个新终端，查看实时日志以确认服务已就绪："
echo "   (首先获取 Pod 名称: POD_NAME=\$(kubectl get pods -l app=${APP_LABEL} -o jsonpath='{.items[0].metadata.name}'))"
echo -e "\033[33mkubectl logs -f \$POD_NAME\033[0m"
echo "   (等待日志中出现 'Uvicorn running on http://0.0.0.0:8000')"
echo ""
echo "3. 服务就绪后，再打开一个新终端，建立端口转发以访问服务："
echo -e "\033[33mkubectl port-forward service/${SERVICE_NAME} 8080:80\033[0m"
echo "   (让此命令保持运行)"
echo ""
echo "4. 最后，打开第四个终端，使用 curl 测试 API："
echo -e "\033[33mcurl http://localhost:8080/v1/chat/completions -H \"Content-Type: application/json\" -d '{\"model\": \"Qwen/Qwen1.5-1.8B-Chat-AWQ\", \"messages\": [{\"role\": \"user\", \"content\": \"你好！\"}]}'\033[0m"
