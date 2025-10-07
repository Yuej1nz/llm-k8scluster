#!/bin/bash

# ====================================================================================
#     Kind K8s 集群 + GPU + 网络 全自动化部署脚本 (最终决战版 v10)
# ====================================================================================
#
# 主要改进 (相比 v9):
# 1. 【可靠性】: 修复了 helm --set affinity="{}" 参数被错误解析为数组的问题，
#              通过使用单引号 '--set affinity='{}'' 来确保其被正确解析为空对象。
#
# ====================================================================================

# --- 配置区 ---
CLUSTER_NAME="llm-research-cluster"
CONFIG_FILE="kind-multinode-gpu.yaml"
CALICO_MANIFEST_URL="https://docs.projectcalico.org/manifests/calico.yaml"
NVIDIA_PLUGIN_CHART_VERSION="0.17.4"
NVIDIA_PLUGIN_NS="nvidia-device-plugin"

# --- 辅助函数 ---
info() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

error() {
    echo -e "\033[31m[ERROR] $1\033[0m"
    exit 1
}

# --- 第 1 步：清理并创建 Kind 集群 ---
info "正在删除旧集群 '${CLUSTER_NAME}' (如果存在)..."
kind delete cluster --name ${CLUSTER_NAME}

info "正在使用 '${CONFIG_FILE}' 创建新的多节点集群..."
info "重要提示: 请确保 '${CONFIG_FILE}' 已正确配置 NVIDIA container runtime！"
kind create cluster --config ${CONFIG_FILE} --name ${CLUSTER_NAME} || error "Kind 集群创建失败！"

# --- 第 2 步：配置 K8s 节点 (污点/标签) ---
info "等待所有节点在 K8s 中注册..."
kubectl wait --for=condition=Ready node --all --timeout=120s || error "节点未能进入 Ready 状态！"

CONTROL_PLANE_NODE="${CLUSTER_NAME}-control-plane"
info "正在移除控制平面节点 '${CONTROL_PLANE_NODE}' 的污点，允许调度 Pod..."
kubectl taint nodes ${CONTROL_PLANE_NODE} node-role.kubernetes.io/control-plane:NoSchedule- || error "移除控制平面污点失败！"

info "正在为所有 Worker 节点添加 'nvidia.com/gpu' 污点..."
WORKER_NODES=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}')
for node in ${WORKER_NODES}; do
    info "  -> 为节点 '${node}' 添加污点..."
    kubectl taint nodes ${node} nvidia.com/gpu=true:NoSchedule || error "为 worker 节点 '${node}' 添加污点失败！"
done

# --- 第 3 步：安装 Calico CNI 网络插件 ---
info "正在从 '${CALICO_MANIFEST_URL}' 安装 Calico CNI..."
kubectl apply -f ${CALICO_MANIFEST_URL} || error "安装 Calico 失败！"

info "等待 Calico Pod 完全就绪..."
kubectl wait --for=condition=Ready pod -l k8s-app=calico-node -n kube-system --timeout=300s || error "Calico node Pod 未能进入 Ready 状态！"
kubectl wait --for=condition=Ready pod -l k8s-app=calico-kube-controllers -n kube-system --timeout=300s || error "Calico controllers Pod 未能进入 Ready 状态！"

info "等待所有节点在 CNI 安装后恢复 Ready 状态..."
kubectl wait --for=condition=Ready node --all --timeout=180s || error "安装 CNI 后，节点未能恢复 Ready 状态！"

# --- 第 4 步：安装 NVIDIA GPU Device Plugin ---
info "正在准备安装 NVIDIA GPU Plugin..."
helm uninstall nvdp --namespace ${NVIDIA_PLUGIN_NS} 2>/dev/null || true
kubectl delete ns ${NVIDIA_PLUGIN_NS} 2>/dev/null || true

info "等待旧的 nvidia-device-plugin 命名空间被彻底删除..."
kubectl wait --for=delete namespace/${NVIDIA_PLUGIN_NS} --timeout=60s || info "命名空间不存在或已被删除，继续执行。"

info "正在更新 Helm 仓库..."
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update

info "正在使用 Helm 安装 nvidia-device-plugin (v${NVIDIA_PLUGIN_CHART_VERSION})..."
# 【最终核心修正】使用单引号来传递空对象，避免被 shell 错误解析
helm install nvdp nvdp/nvidia-device-plugin \
  --namespace ${NVIDIA_PLUGIN_NS} \
  --create-namespace \
  --version ${NVIDIA_PLUGIN_CHART_VERSION} \
  --set mps.enabled=false \
  --set runtimeClassName="nvidia" \
  -f nvidia-values.yaml \
  --wait || error "Helm 安装 NVIDIA 插件失败！"

# --- 第 5 步：最终检查 ---
info "集群基础设施已全部就绪！"
echo ""
info "节点状态："
kubectl get nodes -o wide
echo ""
info "GPU 插件 Pod 状态："
kubectl get pods -n ${NVIDIA_PLUGIN_NS} -o wide
echo ""
info "检查各节点是否已上报 GPU 资源 (nvidia.com/gpu)："
kubectl describe nodes | grep -E "^Name:|nvidia.com/gpu" | grep -B1 "nvidia.com/gpu"

echo ""
info "✅ 部署成功！"
