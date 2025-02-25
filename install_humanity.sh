#!/bin/bash

# 检查是否以 root 用户运行脚本
if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 用户运行此脚本"
  exit 1
fi

# 安装 Python 3.11 和必要的依赖
apt update
apt install -y python3.11 python3.11-venv python3.11-dev curl

# 克隆 Humanity 仓库
if [ ! -d "Humanity" ]; then
  git clone https://github.com/sdohuajia/Humanity.git
fi

cd Humanity || exit

# 创建和激活 Python 虚拟环境
python3.11 -m venv venv
source venv/bin/activate

# 安装 Python 包
pip install -r requirements.txt

# 手动安装 httpx
pip install httpx

# 配置私钥信息
echo "请输入账户的私钥信息（每行一个），输入完成后按 Ctrl+D 保存："
cat > private_keys.txt

# 配置代理信息
echo "请输入账户的代理信息（每行一个），输入完成后按 Ctrl+D 保存："
cat > proxy.txt

echo "安装成功！请运行 'source venv/bin/activate && python main.py' 启动脚本。"
