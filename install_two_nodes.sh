#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

echo -e "${GREEN}欢迎安装 LayerEdge CLI Light Node（双实例版）！${NC}"

# 检查权限
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}请以 root 用户或使用 sudo 运行此脚本！${NC}"
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
rzup install

# 创建工作目录
cd ~
git clone https://github.com/Layer-Edge/light-node.git
cp -r light-node light-node-1
cp -r light-node light-node-2

# 安装第一个节点（钱包 1）
echo -e "${GREEN}开始安装第一个节点（钱包 1）...${NC}"
echo "请输入第一个钱包的私钥（PRIVATE_KEY_1）："
read -p "PRIVATE_KEY_1: " PRIVATE_KEY_1

cd ~/light-node-1
cat <<EOF > .env
GRPC_URL=34.31.74.109:9090
CONTRACT_ADDR=cosmos1ufs3tlq4umljk0qfe8k5ya0x6hpavn897u2cnf9k0en9jr7qarqqt56709
ZK_PROVER_URL=http://127.0.0.1:3001
API_REQUEST_TIMEOUT=100
POINTS_API=http://127.0.0.1:8080
PRIVATE_KEY='$PRIVATE_KEY_1'
EOF
source .env

echo "构建并启动 Merkle 服务（钱包 1）..."
cd risc0-merkle-service
cargo build || { echo -e "${RED}Merkle 服务构建失败！${NC}"; exit 1; }
cargo run > merkle1.log 2>&1 &
sleep 10

echo "构建并启动 CLI 节点（钱包 1）..."
cd ../
go build || { echo -e "${RED}CLI 节点构建失败！${NC}"; exit 1; }
./light-node > node1.log 2>&1 &
sleep 5

echo -e "${GREEN}第一个节点安装完成！${NC}"

# 安装第二个节点（钱包 2）
echo -e "${GREEN}开始安装第二个节点（钱包 2）...${NC}"
echo "请输入第二个钱包的私钥（PRIVATE_KEY_2）："
read -p "PRIVATE_KEY_2: " PRIVATE_KEY_2

cd ~/light-node-2
cat <<EOF > .env
GRPC_URL=34.31.74.109:9090
CONTRACT_ADDR=cosmos1ufs3tlq4umljk0qfe8k5ya0x6hpavn897u2cnf9k0en9jr7qarqqt56709
ZK_PROVER_URL=http://127.0.0.1:3002
API_REQUEST_TIMEOUT=100
POINTS_API=http://127.0.0.1:8080
PRIVATE_KEY='$PRIVATE_KEY_2'
EOF
source .env

echo "构建并启动 Merkle 服务（钱包 2）..."
cd risc0-merkle-service
PORT=3002 cargo build || { echo -e "${RED}Merkle 服务构建失败！${NC}"; exit 1; }
PORT=3002 cargo run > merkle2.log 2>&1 &
sleep 10

echo "构建并启动 CLI 节点（钱包 2）..."
cd ../
go build || { echo -e "${RED}CLI 节点构建失败！${NC}"; exit 1; }
./light-node > node2.log 2>&1 &
sleep 5

echo -e "${GREEN}第二个节点安装完成！${NC}"

# 检查运行状态并显示日志
echo -e "${GREEN}检查两个节点的运行状态...${NC}"
ps aux | grep -E "light-node|risc0-merkle-service"

echo -e "${GREEN}显示第一个节点的日志（最近 10 行）：${NC}"
tail -n 10 ~/light-node-1/node1.log
echo -e "${GREEN}显示第一个 Merkle 服务的日志（最近 10 行）：${NC}"
tail -n 10 ~/light-node-1/risc0-merkle-service/merkle1.log

echo -e "${GREEN}显示第二个节点的日志（最近 10 行）：${NC}"
tail -n 10 ~/light-node-2/node2.log
echo -e "${GREEN}显示第二个 Merkle 服务的日志（最近 10 行）：${NC}"
tail -n 10 ~/light-node-2/risc0-merkle-service/merkle2.log

echo -e "${GREEN}安装完成！${NC}"
echo "日志文件位置："
echo "  - 钱包 1 CLI: ~/light-node-1/node1.log"
echo "  - 钱包 1 Merkle: ~/light-node-1/risc0-merkle-service/merkle1.log"
echo "  - 钱包 2 CLI: ~/light-node-2/node2.log"
echo "  - 钱包 2 Merkle: ~/light-node-2/risc0-merkle-service/merkle2.log"
echo "下一步：访问 https://dashboard.layeredge.io 连接钱包和公钥。"
echo "实时查看日志：tail -f <日志文件路径>"
