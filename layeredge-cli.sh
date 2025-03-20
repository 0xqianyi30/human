#!/bin/bash

# LayerEdge 轻节点安装脚本，适用于 Ubuntu 24.04.2 LTS
# 支持两个独立账户运行

# 颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 变量
HOME_DIR=$HOME
LAYEREDGE_DIR1="$HOME_DIR/light-node-1"
LAYEREDGE_DIR2="$HOME_DIR/light-node-2"
ENV_FILE1="$LAYEREDGE_DIR1/.env"
ENV_FILE2="$LAYEREDGE_DIR2/.env"
LOG_DIR="/var/log/layeredge"

# 输出消息的函数
print_message() {
    echo -e "${BLUE}[LayerEdge 设置]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查是否以 root 运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请以 root 或 sudo 权限运行"
        exit 1
    fi
}

# 创建目录
create_directories() {
    mkdir -p $LOG_DIR
    chmod 755 $LOG_DIR
}

# 更新系统并安装基础依赖
update_system() {
    print_message "正在更新系统并安装基础依赖..."
    apt-get update && apt-get upgrade -y
    apt-get install -y build-essential curl wget git pkg-config libssl-dev jq ufw
    print_success "系统更新和依赖安装完成"
}

# 安装 Go
install_go() {
    print_message "正在安装 Go 1.18+..."
    wget https://go.dev/dl/go1.22.5.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go1.22.5.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >>~/.bashrc
    source ~/.bashrc
    rm go1.22.5.linux-amd64.tar.gz
    print_success "Go 安装成功"
}

# 检查 Go 是否安装
check_go() {
    if ! command -v go &>/dev/null; then
        install_go
    else
        go_version=$(go version | awk '{print $3}' | sed 's/go//')
        if [ "$(echo -e "1.18\n$go_version" | sort -V | head -n1)" != "1.18" ]; then
            print_warning "Go 版本低于 1.18，正在更新..."
            install_go
        else
            print_success "Go 版本 $go_version 已安装"
        fi
    fi
}

# 安装 Rust
install_rust() {
    print_message "正在安装 Rust 1.81.0+..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
    print_success "Rust 安装成功"
}

# 检查 Rust 是否安装
check_rust() {
    if ! command -v rustc &>/dev/null; then
        install_rust
    else
        rust_version=$(rustc --version | awk '{print $2}')
        if [ "$(echo -e "1.81.0\n$rust_version" | sort -V | head -n1)" != "1.81.0" ]; then
            print_warning "Rust 版本低于 1.81.0，正在更新..."
            rustup update
        else
            print_success "Rust 版本 $rust_version 已安装"
        fi
    fi
}

# 安装 Risc0 工具链
install_risc0() {
    print_message "正在安装 Risc0 工具链..."
    curl -L https://risczero.com/install | bash
    source ~/.bashrc
    rzup install
    print_success "Risc0 工具链安装成功"
}

# 克隆仓库
clone_repo() {
    local instance=$1
    local dir=$2
    print_message "正在为实例 $instance 克隆 LayerEdge 轻节点仓库..."
    cd $HOME_DIR
    if [ -d "$dir" ]; then
        print_warning "'light-node-$instance' 目录已存在，正在更新..."
        cd $dir
        git pull
    else
        git clone https://github.com/Layer-Edge/light-node.git "light-node-$instance"
        cd $dir
    fi
    print_success "实例 $instance 仓库克隆成功"
}

# 设置环境变量
setup_env() {
    local instance=$1
    local env_file=$2
    print_message "正在为实例 $instance 设置环境变量..."

    if [ -f "$env_file" ]; then
        print_warning ".env 文件已存在，是否覆盖？(y/n)"
        read -r overwrite
        if [[ ! $overwrite =~ ^[Yy]$ ]]; then
            print_message "保留现有 .env 文件"
            return
        fi
    fi

    if [ "$instance" == "1" ]; then
        cat >$env_file <<EOF
GRPC_URL=34.31.74.109:9090
CONTRACT_ADDR=cosmos1ufs3tlq4umljk0qfe8k5ya0x6hpavn897u2cnf9k0en9jr7qarqqt56709
ZK_PROVER_URL=http://127.0.0.1:3001
API_REQUEST_TIMEOUT=100
POINTS_API=http://127.0.0.1:8080
EOF
    else
        cat >$env_file <<EOF
GRPC_URL=34.31.74.109:9090
CONTRACT_ADDR=cosmos1ufs3tlq4umljk0qfe8k5ya0x6hpavn897u2cnf9k0en9jr7qarqqt56709
ZK_PROVER_URL=http://127.0.0.1:3002
API_REQUEST_TIMEOUT=100
POINTS_API=http://127.0.0.1:8081
EOF
    fi

    read -p "请输入实例 $instance 的 CLI 节点私钥（不带 '0x'，或按 Enter 稍后设置）： " private_key
    if [ ! -z "$private_key" ]; then
        echo "PRIVATE_KEY=$private_key" >>$env_file
        print_success "实例 $instance 私钥已添加"
    else
        print_warning "实例 $instance 未设置私钥，您需要稍后手动在 .env 文件中设置"
    fi

    chmod 600 $env_file  # 提高安全性
    print_success "实例 $instance 环境变量配置完成"
}

# 构建 Merkle 服务
build_merkle() {
    local instance=$1
    local dir=$2
    print_message "正在为实例 $instance 构建 Risc0 Merkle 服务..."
    cd $dir/risc0-merkle-service
    source $HOME/.cargo/env
    cargo build
    print_success "实例 $instance Merkle 服务构建成功"
}

# 构建轻节点
build_node() {
    local instance=$1
    local dir=$2
    print_message "正在为实例 $instance 构建 LayerEdge 轻节点..."
    cd $dir
    source /etc/profile
    go build
    print_success "实例 $instance 轻节点构建成功"
}

# 创建 systemd 服务
create_services() {
    local instance=$1
    local dir=$2
    local env_file=$3
    print_message "正在为实例 $instance 创建 Merkle 服务的 systemd 服务..."
    cat >/etc/systemd/system/layeredge-merkle-$instance.service <<EOF
[Unit]
Description=LayerEdge Merkle 服务 (实例 $instance)
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$dir/risc0-merkle-service
ExecStart=$HOME/.cargo/bin/cargo run
Restart=on-failure
RestartSec=10
StandardOutput=append:$LOG_DIR/merkle-$instance.log
StandardError=append:$LOG_DIR/merkle-$instance-error.log

[Install]
WantedBy=multi-user.target
EOF

    print_message "正在为实例 $instance 创建轻节点的 systemd 服务..."
    cat >/etc/systemd/system/layeredge-node-$instance.service <<EOF
[Unit]
Description=LayerEdge 轻节点 (实例 $instance)
After=layeredge-merkle-$instance.service
Requires=layeredge-merkle-$instance.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$dir
EnvironmentFile=$env_file
ExecStart=$dir/light-node-$instance
Restart=on-failure
RestartSec=10
StandardOutput=append:$LOG_DIR/node-$instance.log
StandardError=append:$LOG_DIR/node-$instance-error.log

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 /etc/systemd/system/layeredge-merkle-$instance.service
    chmod 644 /etc/systemd/system/layeredge-node-$instance.service
    print_success "实例 $instance Systemd 服务创建完成"
}

# 配置防火墙
setup_firewall() {
    print_message "正在配置防火墙..."
    ufw allow 22/tcp
    ufw allow 3001/tcp
    ufw allow 3002/tcp
    ufw allow 8080/tcp
    ufw allow 8081/tcp
    ufw --force enable
    print_success "防火墙配置完成"
}

# 启用并启动服务
start_services() {
    local instance=$1
    print_message "正在为实例 $instance 启用并启动服务..."
    systemctl daemon-reload
    systemctl enable layeredge-merkle-$instance.service
    systemctl enable layeredge-node-$instance.service
    systemctl start layeredge-merkle-$instance.service
    print_message "等待实例 $instance Merkle 服务初始化（30 秒）..."
    sleep 30
    systemctl start layeredge-node-$instance.service

    if systemctl is-active --quiet layeredge-merkle-$instance.service; then
        print_success "实例 $instance Merkle 服务运行正常"
    else
        print_error "实例 $instance Merkle 服务启动失败，请查看日志：journalctl -u layeredge-merkle-$instance.service"
    fi

    if systemctl is-active --quiet layeredge-node-$instance.service; then
        print_success "实例 $instance 轻节点运行正常"
    else
        print_error "实例 $instance 轻节点启动失败，请查看日志：journalctl -u layeredge-node-$instance.service"
    fi
}

# 停止服务
stop_services() {
    local instance=$1
    print_message "正在停止实例 $instance 的 LayerEdge 服务..."
    systemctl stop layeredge-node-$instance.service
    systemctl stop layeredge-merkle-$instance.service
    print_success "实例 $instance 服务已停止"
}

# 创建状态检查脚本
create_status_script() {
    local instance=$1
    print_message "正在为实例 $instance 创建状态检查脚本..."
    cat >$HOME_DIR/check-layeredge-status-$instance.sh <<EOF
#!/bin/bash

echo "===== LayerEdge 服务状态 (实例 $instance) ====="
systemctl status layeredge-merkle-$instance.service | grep "Active:"
systemctl status layeredge-node-$instance.service | grep "Active:"

echo -e "\n===== Merkle 日志最后 10 行 (实例 $instance) ====="
tail -n 10 $LOG_DIR/merkle-$instance.log

echo -e "\n===== 节点日志最后 10 行 (实例 $instance) ====="
tail -n 10 $LOG_DIR/node-$instance.log

echo -e "\n===== 错误日志最后 10 行 (实例 $instance) ====="
tail -n 10 $LOG_DIR/merkle-$instance-error.log
tail -n 10 $LOG_DIR/node-$instance-error.log
EOF

    chmod +x $HOME_DIR/check-layeredge-status-$instance.sh
    print_success "实例 $instance 状态检查脚本已创建：$HOME_DIR/check-layeredge-status-$instance.sh"
}

# 查看日志
view_logs() {
    echo -e "\n${CYAN}可用日志：${NC}"
    echo "1) 实例 1 Merkle 服务日志"
    echo "2) 实例 1 轻节点日志"
    echo "3) 实例 1 Merkle 错误日志"
    echo "4) 实例 1 轻节点错误日志"
    echo "5) 实例 2 Merkle 服务日志"
    echo "6) 实例 2 轻节点日志"
    echo "7) 实例 2 Merkle 错误日志"
    echo "8) 实例 2 轻节点错误日志"
    echo "9) 返回主菜单"

    read -p "选择要查看的日志： " log_choice

    case $log_choice in
    1) less $LOG_DIR/merkle-1.log ;;
    2) less $LOG_DIR/node-1.log ;;
    3) less $LOG_DIR/merkle-1-error.log ;;
    4) less $LOG_DIR/node-1-error.log ;;
    5) less $LOG_DIR/merkle-2.log ;;
    6) less $LOG_DIR/node-2.log ;;
    7) less $LOG_DIR/merkle-2-error.log ;;
    8) less $LOG_DIR/node-2-error.log ;;
    9) return ;;
    *) print_error "无效选择" ;;
    esac
}

# 检查节点状态
check_status() {
    local instance=$1
    $HOME_DIR/check-layeredge-status-$instance.sh
}

# 查看服务状态
view_service_status() {
    echo -e "\n${CYAN}服务状态：${NC}"
    echo "1) 实例 1 Merkle 服务状态"
    echo "2) 实例 1 轻节点服务状态"
    echo "3) 实例 2 Merkle 服务状态"
    echo "4) 实例 2 轻节点服务状态"
    echo "5) 返回主菜单"

    read -p "选择服务： " service_choice

    case $service_choice in
    1) systemctl status layeredge-merkle-1.service ;;
    2) systemctl status layeredge-node-1.service ;;
    3) systemctl status layeredge-merkle-2.service ;;
    4) systemctl status layeredge-node-2.service ;;
    5) return ;;
    *) print_error "无效选择" ;;
    esac
}

# 更新私钥
update_private_key() {
    echo "请选择要更新的实例："
    echo "1) 实例 1"
    echo "2) 实例 2"
    read -p "输入实例编号： " instance

    local env_file
    if [ "$instance" == "1" ]; then
        env_file=$ENV_FILE1
    elif [ "$instance" == "2" ]; then
        env_file=$ENV_FILE2
    else
        print_error "无效实例编号"
        return
    fi

    read -p "请输入实例 $instance 的新 CLI 节点私钥（不带 '0x'）： " new_private_key

    if [ -f "$env_file" ]; then
        if grep -q "PRIVATE_KEY" "$env_file"; then
            sed -i "s/PRIVATE_KEY=.*/PRIVATE_KEY=$new_private_key/" $env_file
        else
            echo "PRIVATE_KEY=$new_private_key" >>$env_file
        fi
        print_success "实例 $instance 私钥已更新"

        print_message "正在重启实例 $instance 轻节点服务以应用更改..."
        systemctl restart layeredge-node-$instance.service
    else
        print_error "实例 $instance 的 .env 文件未找到，请先运行安装程序。"
    fi
}

# 显示仪表板连接信息
show_dashboard_info() {
    echo -e "\n${CYAN}======= LayerEdge 仪表板连接信息 =======${NC}"
    echo "1. 访问 dashboard.layeredge.io"
    echo "2. 连接您的钱包"
    echo "3. 绑定您的 CLI 节点公钥"
    echo "4. 在以下地址查看您的积分："
    echo "   实例 1: https://light-node.layeredge.io/api/cli-node/points/{您的钱包地址}"
    echo "   实例 2: https://light-node.layeredge.io/api/cli-node/points/{您的钱包地址}"
    echo -e "${CYAN}=========================================${NC}"

    read -p "按 Enter 继续..."
}

# 完整安装
install_full() {
    local instance=$1
    local dir=$2
    local env_file=$3
    check_root
    create_directories
    update_system
    check_go
    check_rust
    install_risc0
    clone_repo $instance $dir
    setup_env $instance $env_file
    build_merkle $instance $dir
    build_node $instance $dir
    create_services $instance $dir $env_file
    setup_firewall
    create_status_script $instance
    start_services $instance

    print_message "============================================"
    print_success "实例 $instance LayerEdge 轻节点完整安装完成！"
    print_message "============================================"
    read -p "按 Enter 继续..."
}

# 显示横幅
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║               LayerEdge 轻节点管理器                    ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 主菜单
main_menu() {
    while true; do
        show_banner
        echo добы: echo -e "${CYAN}安装选项：${NC}"
        echo "1) 完整安装实例 1"
        echo "2) 完整安装实例 2"
        echo "3) 更新仓库 (实例 1)"
        echo "4) 更新仓库 (实例 2)"
        echo "5) 构建/重建服务 (实例 1)"
        echo "6) 构建/重建服务 (实例 2)"
        echo ""
        echo -e "${CYAN}服务管理：${NC}"
        echo "7) 启动服务 (实例 1)"
        echo "8) 启动服务 (实例 2)"
        echo "9) 停止服务 (实例 1)"
        echo "10) 停止服务 (实例 2)"
        echo "11) 重启服务 (实例 1)"
        echo "12) 重启服务 (实例 2)"
        echo "13) 查看服务状态"
        echo ""
        echo -e "${CYAN}监控与配置：${NC}"
        echo "14) 检查节点状态 (实例 1)"
        echo "15) 检查节点状态 (实例 2)"
        echo "16) 查看日志"
        echo "17) 更新私钥"
        echo "18) 仪表板连接信息"
        echo ""
        echo "19) 退出"
        echo ""
        read -p "请输入您的选择： " choice

        case $choice in
        1) install_full 1 $LAYEREDGE_DIR1 $ENV_FILE1 ;;
        2) install_full 2 $LAYEREDGE_DIR2 $ENV_FILE2 ;;
        3)
            check_root
            clone_repo 1 $LAYEREDGE_DIR1
            read -p "按 Enter 继续..."
            ;;
        4)
            check_root
            clone_repo 2 $LAYEREDGE_DIR2
            read -p "按 Enter 继续..."
            ;;
        5)
            check_root
            build_merkle 1 $LAYEREDGE_DIR1
            build_node 1 $LAYEREDGE_DIR1
            read -p "按 Enter 继续..."
            ;;
        6)
            check_root
            build_merkle 2 $LAYEREDGE_DIR2
            build_node 2 $LAYEREDGE_DIR2
            read -p "按 Enter 继续..."
            ;;
        7)
            check_root
            start_services 1
            read -p "按 Enter 继续..."
            ;;
        8)
            check_root
            start_services 2
            read -p "按 Enter 继续..."
            ;;
        9)
            check_root
            stop_services 1
            read -p "按 Enter 继续..."
            ;;
        10)
            check_root
            stop_services 2
            read -p "按 Enter 继续..."
            ;;
        11)
            check_root
            stop_services 1
            start_services 1
            read -p "按 Enter 继续..."
            ;;
        12)
            check_root
            stop_services 2
            start_services 2
            read -p "按 Enter 继续..."
            ;;
        13)
            check_root
            view_service_status
            ;;
        14)
            check_status 1
            read -p "按 Enter 继续..."
            ;;
        15)
            check_status 2
            read -p "按 Enter 继续..."
            ;;
        16)
            view_logs
            ;;
        17)
            check_root
            update_private_key
            read -p "按 Enter 继续..."
            ;;
        18)
            show_dashboard_info
            ;;
        19)
            echo "正在退出 LayerEdge 轻节点管理器，再见！"
            exit 0
            ;;
        *)
            print_error "无效选项，请重试。"
            read -p "按 Enter 继续..."
            ;;
        esac
    done
}

# 执行主菜单
main_menu
