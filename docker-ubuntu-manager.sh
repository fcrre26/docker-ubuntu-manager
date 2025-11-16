cat > /root/docker-ubuntu-manager.sh << 'EOF'
#!/bin/sh

DEFAULT_PASSWORD="123456789"
BASE_PORT=32200
CONTAINER_PREFIX="ubuntu-ssh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示带颜色的消息
error_msg() { echo -e "${RED}[错误] $1${NC}"; }
success_msg() { echo -e "${GREEN}[成功] $1${NC}"; }
warning_msg() { echo -e "${YELLOW}[警告] $1${NC}"; }
info_msg() { echo -e "${BLUE}[信息] $1${NC}"; }

# 检查Docker是否可用
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        error_msg "Docker 未安装或未启动"
        exit 1
    fi
}

# 显示当前运行的容器
show_containers() {
    info_msg "当前运行的Ubuntu容器:"
    docker ps --filter "name=${CONTAINER_PREFIX}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
}

# 获取下一个可用端口
get_next_port() {
    local last_port=$(docker ps --filter "name=${CONTAINER_PREFIX}" --format "{{.Ports}}" | grep -o ":[0-9]*->22" | cut -d: -f2 | cut -d- -f1 | sort -n | tail -1)
    if [ -z "$last_port" ]; then
        echo $BASE_PORT
    else
        echo $((last_port + 1))
    fi
}

# 获取下一个容器编号
get_next_number() {
    local last_num=$(docker ps -a --filter "name=${CONTAINER_PREFIX}" --format "{{.Names}}" | grep -o "[0-9]*$" | sort -n | tail -1)
    if [ -z "$last_num" ]; then
        echo 1
    else
        echo $((last_num + 1))
    fi
}

# 创建单个容器
create_container() {
    local num=$1
    local port=$2
    local container_name="${CONTAINER_PREFIX}${num}"
    
    info_msg "正在创建容器 ${container_name} (端口: ${port})..."
    
    # 拉取镜像（如果不存在）
    if ! docker images | grep -q "ubuntu.*22.04"; then
        info_msg "拉取 Ubuntu 22.04 镜像..."
        docker pull ubuntu:22.04
    fi
    
    # 创建并启动容器
    docker run -d --name ${container_name} -p ${port}:22 ubuntu:22.04 sleep infinity
    
    # 等待容器启动
    sleep 3
    
    # 配置容器
    info_msg "正在配置容器..."
    docker exec ${container_name} bash -c "
        # 更新和安装必要的软件
        apt update -y
        apt install -y openssh-server sudo curl wget vim
        
        # 配置SSH
        sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
        echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
        
        # 设置root密码
        echo 'root:${DEFAULT_PASSWORD}' | chpasswd
        
        # 创建SSH目录
        mkdir -p /run/sshd
        
        # 启动SSH服务
        /usr/sbin/sshd -D &
        
        echo '容器配置完成'
    "
    
    # 等待SSH服务启动
    sleep 5
    
    success_msg "容器 ${container_name} 创建完成!"
    echo "SSH连接信息:"
    echo "  容器名: ${container_name}"
    echo "  SSH端口: ${port}"
    echo "  用户名: root"
    echo "  密码: ${DEFAULT_PASSWORD}"
    echo "  连接命令: ssh root://127.0.0.1 -p ${port}"
    echo ""
}

# 批量创建容器
create_containers() {
    echo ""
    read -p "请输入要创建的容器数量: " count
    
    if ! echo "$count" | grep -qE '^[1-9][0-9]*$'; then
        error_msg "请输入有效的数字"
        return 1
    fi
    
    info_msg "准备创建 ${count} 个Ubuntu容器..."
    
    local start_num=$(get_next_number)
    local current_port=$(get_next_port)
    
    for i in $(seq 1 $count); do
        create_container $((start_num + i - 1)) $((current_port + i - 1))
    done
    
    success_msg "所有容器创建完成!"
    show_containers
}

# 删除所有容器
delete_all_containers() {
    local containers=$(docker ps -a --filter "name=${CONTAINER_PREFIX}" --format "{{.Names}}")
    
    if [ -z "$containers" ]; then
        warning_msg "没有找到 ${CONTAINER_PREFIX} 开头的容器"
        return
    fi
    
    echo "找到以下容器:"
    echo "$containers"
    echo ""
    read -p "确定要删除所有这些容器吗? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        docker rm -f $(echo "$containers")
        success_msg "所有容器已删除"
    else
        info_msg "操作已取消"
    fi
}

# 删除单个容器
delete_single_container() {
    show_containers
    echo ""
    read -p "请输入要删除的容器名称: " container_name
    
    if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker rm -f ${container_name}
        success_msg "容器 ${container_name} 已删除"
    else
        error_msg "容器 ${container_name} 不存在"
    fi
}

# 重启容器SSH服务
restart_ssh() {
    show_containers
    echo ""
    read -p "请输入要重启SSH服务的容器名称: " container_name
    
    if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        info_msg "正在重启 ${container_name} 的SSH服务..."
        docker exec ${container_name} pkill -f sshd
        docker exec ${container_name} /usr/sbin/sshd -D &
        success_msg "SSH服务已重启"
    else
        error_msg "容器 ${container_name} 不存在或未运行"
    fi
}

# 显示菜单
show_menu() {
    echo ""
    echo "=========================================="
    echo "    Docker Ubuntu 容器管理脚本"
    echo "=========================================="
    echo "1. 显示当前容器状态"
    echo "2. 创建单个Ubuntu容器"
    echo "3. 批量创建Ubuntu容器"
    echo "4. 删除单个容器"
    echo "5. 删除所有Ubuntu容器"
    echo "6. 重启容器SSH服务"
    echo "7. 退出脚本"
    echo "=========================================="
}

# 主循环
main() {
    check_docker
    
    while true; do
        show_menu
        show_containers
        echo ""
        read -p "请选择操作 [1-7]: " choice
        
        case $choice in
            1)
                show_containers
                ;;
            2)
                local next_num=$(get_next_number)
                local next_port=$(get_next_port)
                create_container $next_num $next_port
                ;;
            3)
                create_containers
                ;;
            4)
                delete_single_container
                ;;
            5)
                delete_all_containers
                ;;
            6)
                restart_ssh
                ;;
            7)
                success_msg "再见!"
                exit 0
                ;;
            *)
                error_msg "无效选择，请重新输入"
                ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
    done
}

# 运行主函数
main
EOF

# 给脚本执行权限
chmod +x /root/docker-ubuntu-manager.sh

# 创建快捷命令别名
echo "alias ubuntu-docker='/root/docker-ubuntu-manager.sh'" >> /root/.bashrc
source /root/.bashrc

success_msg "脚本安装完成!"
echo "现在你可以使用以下命令运行管理脚本:"
echo "  /root/docker-ubuntu-manager.sh"
echo "或者使用快捷命令:"
echo "  ubuntu-docker"
echo ""
info_msg "脚本功能包括:"
echo "  - 显示当前容器状态"
echo "  - 创建单个Ubuntu容器（自动递增端口）"
echo "  - 批量创建多个Ubuntu容器"
echo "  - 删除容器"
echo "  - 重启SSH服务"
