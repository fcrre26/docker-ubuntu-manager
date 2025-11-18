# 创建主管理脚本
cat > /root/docker-ubuntu-manager.sh << 'EOF'
#!/bin/sh
DEFAULT_PASSWORD="123456789"
BASE_PORT=32200
CONTAINER_PREFIX="ubuntu-ssh"
CUSTOM_IMAGE="ubuntu-ssh:latest"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error_msg() { echo -e "${RED}[错误] $1${NC}"; }
success_msg() { echo -e "${GREEN}[成功] $1${NC}"; }
warning_msg() { echo -e "${YELLOW}[警告] $1${NC}"; }
info_msg() { echo -e "${BLUE}[信息] $1${NC}"; }

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        error_msg "Docker 未安装或未启动"
        exit 1
    fi
}

check_and_build_image() {
    if ! docker images | grep -q "ubuntu-ssh"; then
        info_msg "未找到自定义镜像，开始构建..."
        if [ -f "/root/ubuntu-ssh.dockerfile" ]; then
            docker build -t ${CUSTOM_IMAGE} -f /root/ubuntu-ssh.dockerfile .
            success_msg "自定义镜像构建完成"
        else
            error_msg "Dockerfile 不存在，请先创建 /root/ubuntu-ssh.dockerfile"
            exit 1
        fi
    fi
}

show_containers() {
    info_msg "当前运行的Ubuntu容器:"
    docker ps --filter "name=${CONTAINER_PREFIX}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
}

get_next_port() {
    local last_port=$(docker ps --filter "name=${CONTAINER_PREFIX}" --format "{{.Ports}}" | grep -o ":[0-9]*->22" | cut -d: -f2 | cut -d- -f1 | sort -n | tail -1)
    if [ -z "$last_port" ]; then
        echo $BASE_PORT
    else
        echo $((last_port + 1))
    fi
}

get_next_number() {
    local last_num=$(docker ps -a --filter "name=${CONTAINER_PREFIX}" --format "{{.Names}}" | grep -o "[0-9]*$" | sort -n | tail -1)
    if [ -z "$last_num" ]; then
        echo 1
    else
        echo $((last_num + 1))
    fi
}

create_container() {
    local num=$1
    local port=$2
    local container_name="${CONTAINER_PREFIX}${num}"
    
    info_msg "正在创建容器 ${container_name} (端口: ${port})..."
    docker run -d --restart=unless-stopped --name ${container_name} -p ${port}:22 ${CUSTOM_IMAGE}
    sleep 3
    
    if [ "${DEFAULT_PASSWORD}" != "123456789" ]; then
        docker exec ${container_name} bash -c "echo 'root:${DEFAULT_PASSWORD}' | chpasswd"
    fi
    
    success_msg "容器 ${container_name} 创建完成!"
    echo "SSH连接信息:"
    echo "  容器名: ${container_name}"
    echo "  SSH端口: ${port}"
    echo "  用户名: root"
    echo "  密码: ${DEFAULT_PASSWORD}"
    echo "  连接命令: ssh root@127.0.0.1 -p ${port}"
    echo ""
}

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
    echo "6. 重启容器"
    echo "7. 退出脚本"
    echo "=========================================="
}

main() {
    check_docker
    check_and_build_image
    while true; do
        show_menu
        show_containers
        echo ""
        read -p "请选择操作 [1-7]: " choice
        case $choice in
            1) show_containers ;;
            2) 
                local next_num=$(get_next_number)
                local next_port=$(get_next_port)
                create_container $next_num $next_port 
                ;;
            3) create_containers ;;
            4)
                show_containers
                read -p "请输入要删除的容器名称: " container_name
                docker rm -f ${container_name} && success_msg "容器已删除" || error_msg "删除失败"
                ;;
            5)
                docker rm -f $(docker ps -a --filter "name=${CONTAINER_PREFIX}" --format "{{.Names}}") && success_msg "所有容器已删除"
                ;;
            6)
                show_containers
                read -p "请输入要重启的容器名称: " container_name
                docker restart ${container_name} && success_msg "容器已重启"
                ;;
            7) 
                success_msg "再见!"
                exit 0 
                ;;
            *) error_msg "无效选择" ;;
        esac
        echo "" && read -p "按回车键继续..."
    done
}
main
EOF

chmod +x /root/docker-ubuntu-manager.sh
