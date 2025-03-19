#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

echo -e "${GREEN}欢迎安装 LayerEdge CLI Light Node（多账号版）！${NC}"

# 检查权限
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}请以 root 用户或使用 sudo 运行此脚本！${NC}"
  exit 1
fi

# 创建 EDGE 目录
EDGE_DIR="$HOME/EDGE"
echo "创建 EDGE 目录：$EDGE_DIR"
mkdir -p "$EDGE_DIR"
cd "$EDGE_DIR" || { echo -e "${RED}进入 EDGE 目录失败！${NC}"; exit 1; }

# 提示输入私钥
echo -e "${GREEN}请输入私钥（每行一个，输入完成后按 Ctrl+D 保存）：${NC}"
> "$HOME/key.txt" # 清空文件
while IFS= read -r line; do
  echo "$line" >> "$HOME/key.txt"
done < /dev/tty
if [ ! -s "$HOME/key.txt" ]; then
  echo -e "${RED}错误：未输入任何私钥！${NC}"
  exit 1
fi

# 安装依赖（只执行一次）
echo "更新系统并安装基本工具..."
apt update && apt upgrade -y
apt install -y git curl build-essential

echo "安装 Go 1.21..."
wget https://golang.org/dl/go1.21.0.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bashrc
source ~/.bashrc
rm go1.21.0.linux-amd64.tar.gz

echo "安装 Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
rustup update

echo "安装 Risc0 工具链..."
curl -L https://risczero.com/install | bash
source $HOME/.cargo/env # 确保环境变量生效
rzup install
# 验证 Risc0 工具链是否安装成功
if ! cargo --list | grep -q "risc0"; then
  echo -e "${RED}错误：Risc0 工具链安装失败！尝试手动安装：${NC}"
  echo "curl -L https://risczero.com/install | bash && rzup install"
  exit 1
fi

# 克隆仓库到 EDGE 目录
echo "克隆 LayerEdge 仓库..."
git clone https://github.com/Layer-Edge/light-node.git "$EDGE_DIR/base-light-node"

# 读取私钥，循环安装
i=1
while IFS= read -r PRIVATE_KEY; do
  echo -e "${GREEN}安装账户 $i（私钥: ${PRIVATE_KEY:0:6}...，默认直连）...${NC}"

  # 创建独立目录
  NODE_DIR="$EDGE_DIR/light-node-$i"
  cp -r "$EDGE_DIR/base-light-node" "$NODE_DIR"
  cd "$NODE_DIR" || { echo -e "${RED}进入目录失败！${NC}"; exit 1; }

  # 配置环境变量（默认直连）
  PORT=$((3000 + i))
  cat <<EOF > .env
GRPC_URL=34.31.74.109:9090
CONTRACT_ADDR=cosmos1ufs3tlq4umljk0qfe8k5ya0x6hpavn897u2cnf9k0en9jr7qarqqt56709
ZK_PROVER_URL=http://127.0.0.1:$PORT
API_REQUEST_TIMEOUT=100
POINTS_API=http://127.0.0.1:8080
PRIVATE_KEY='$PRIVATE_KEY'
EOF
  source .env

  # 启动 Merkle 服务
  echo "构建并启动 Merkle 服务（账户 $i）..."
  cd risc0-merkle-service
  PORT=$PORT cargo build || { echo -e "${RED}Merkle 服务构建失败！${NC}"; exit 1; }
  PORT=$PORT cargo run > "$NODE_DIR/merkle$i.log" 2>&1 &
  sleep 10

  # 启动 CLI 节点
  echo "构建并启动 CLI 节点（账户 $i）..."
  cd "$NODE_DIR"
  go build || { echo -e "${RED}CLI 节点构建失败！${NC}"; exit 1; }
  ./light-node > "$NODE_DIR/node$i.log" 2>&1 &
  sleep 5

  echo -e "${GREEN}账户 $i 安装完成！${NC}"
  i=$((i + 1))
done < "$HOME/key.txt"

# 检查运行状态
echo -e "${GREEN}检查所有节点运行状态...${NC}"
ps aux | grep -E "light-node|risc0-merkle-service"

# 定义颜色数组，用于日志标题区分
COLORS=("$YELLOW" "$BLUE" "$PURPLE" "$CYAN" "$GREEN")
echo -e "${GREEN}显示每个账户的动态运行日志（最近 10 行）：${NC}"
for ((j=1; j<i; j++)); do
  COLOR_INDEX=$(( (j-1) % ${#COLORS[@]} ))
  COLOR=${COLORS[$COLOR_INDEX]}
  
  echo -e "${COLOR}账户 $j（默认直连） CLI 日志：${NC}"
  tail -n 10 "$EDGE_DIR/light-node-$j/node$j.log" | sed 's/\x1B\[[0-9;]*[mK]//g'
  echo -e "${COLOR}账户 $j（默认直连） Merkle 日志：${NC}"
  tail -n 10 "$EDGE_DIR/light-node-$j/merkle$j.log" | sed 's/\x1B\[[0-9;]*[mK]//g'
  echo -e "${GREEN}------------------------${NC}"
done

echo -e "${GREEN}所有节点安装完成！${NC}"
echo "日志文件位置："
for ((j=1; j<i; j++)); do
  echo "  - 账户 $j CLI: $EDGE_DIR/light-node-$j/node$j.log"
  echo "  - 账户 $j Merkle: $EDGE_DIR/light-node-$j/merkle$j.log"
done
echo "下一步：访问 https://dashboard.layeredge.io 连接钱包和公钥。"
echo "实时查看日志：tail -f $EDGE_DIR/light-node-<编号>/node<编号>.log"
