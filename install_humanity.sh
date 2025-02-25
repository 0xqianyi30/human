#!/bin/bash

# 检查是否以 root 用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以 root 用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到 root 用户，然后再次运行此脚本。"
    exit 1
fi

# 安装 Python 3.11 和必要依赖
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt install -y python3.11 python3.11-venv python3.11-dev python3-pip

# 克隆 Humanity 仓库
if [ -d "Humanity" ]; then
    echo "检测到 Humanity 目录已存在，正在删除..."
    rm -rf Humanity
    echo "Humanity 目录已删除。"
fi

echo "正在从 GitHub 克隆 Humanity 仓库..."
git clone https://github.com/sdohuajia/Humanity.git
if [ ! -d "Humanity" ]; then
    echo "克隆失败，请检查网络连接或仓库地址。"
    exit 1
fi

cd Humanity || { echo "无法进入 Humanity 目录"; exit 1; }

# 创建和激活虚拟环境
python3.11 -m venv venv
source venv/bin/activate

# 安装 Python 包
python3.11 -m pip install --upgrade pip
if [ -f requirements.txt ]; then
    python3.11 -m pip install -r requirements.txt
else
    echo "未找到 requirements.txt 文件，无法安装依赖。"
    exit 1
fi

# 手动安装 httpx
python3.11 -m pip install httpx

# 配置私钥信息
read -p "请输入您的私钥: " private_key
private_keys_file="private_keys.txt"
echo "$private_key" >> "$private_keys_file"
echo "私钥信息已添加到 $private_keys_file."

# 运行脚本
echo "正在使用 screen 启动 main.py..."
screen -dmS Humanity
screen -S Humanity -X stuff $"cd $(pwd)\n"
screen -S Humanity -X stuff $"source venv/bin/activate\n"
screen -S Humanity -X stuff $"python3 main.py\n"
echo "使用 'screen -r Humanity' 命令来查看日志。"
echo "要退出 screen 会话，请按 Ctrl+A 然后按 D。"
