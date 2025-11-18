#!/bin/sh
DEFAULT_PASSWORD="123456789"
BASE_PORT=32200
CONTAINER_PREFIX="ubuntu-ssh"
CUSTOM_IMAGE="ubuntu-ssh-local:latest"

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
        error_msg "Docker 未安装"
        echo "请先在 iStoreOS 中安装 Docker:"
        echo "1. 进入 iStoreOS 管理界面"
        echo "2. 在应用商店中安装 Docker"
        echo "3. 或者使用命令: opkg update && opkg install docker"
        exit 1
    fi
    
    info_msg "检查 Docker 服务状态..."
    if ! docker version >/dev/null 2>&1; then
        error_msg "Docker 服务未运行，正在尝试启动..."
        
        if /etc/init.d/docker start 2>/dev/null; then
            success_msg "Docker 服务启动成功"
            sleep 3
        elif service docker start 2>/dev/null; then
            success_msg "Docker 服务启动成功"
            sleep 3
        elif dockerd >/dev/null 2>&1 & then
            success_msg "Docker 守护进程启动成功"
            sleep 5
        else
            error_msg "无法启动 Docker 服务"
            echo "请手动启动 Docker:"
            echo "1. /etc/init.d/docker start"
            echo "2. 或: service docker start"
            echo "3. 或: dockerd &"
            exit 1
        fi
    else
        success_msg "Docker 服务正在运行"
    fi
}

create_dockerfile() {
    info_msg "创建 Dockerfile..."
    cat > /root/ubuntu-ssh.dockerfile << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 更换为国内源加速下载
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list

# 安装必要的软件包
RUN apt update && \
    apt install -y openssh-server sudo curl wget vim && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd

# 配置SSH
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

# 设置root密码
RUN echo 'root:123456789' | chpasswd

# 暴露SSH端口
EXPOSE 22

# 直接启动SSH服务
CMD ["/usr/sbin/sshd", "-D"]
EOF
    
    # 验证 Dockerfile 是否创建成功
    if [ -f "/root/ubuntu-ssh.dockerfile" ]; then
        success_msg "Dockerfile 创建成功"
        info_msg "Dockerfile 内容:"
        cat /root/ubuntu-ssh.dockerfile
    else
        error_msg "Dockerfile 创建失败"
        return 1
    fi
}

check_and_build_image() {
    info_msg "检查自定义镜像..."
    if ! docker images | grep -q "ubuntu-ssh-local"; then
        info_msg "未找到自定义镜像，开始构建..."
        
        # 确保 Dockerfile 存在
        if [ ! -f "/root/ubuntu-ssh.dockerfile" ]; then
            warning_msg "Dockerfile 不存在，正在创建..."
            create_dockerfile
        fi
        
        # 验证 Dockerfile 内容
        if grep -q "FROM ubuntu" /root/ubuntu-ssh.dockerfile; then
            info_msg "Dockerfile 内容验证通过"
        else
            error_msg "Dockerfile 内容不正确，重新创建..."
            create_dockerfile
        fi
        
        info_msg "开始构建镜像..."
        if docker build -t ${CUSTOM_IMAGE} -f /root/ubuntu-ssh.dockerfile .; then
            success_msg "自定义镜像构建完成"
        else
            error_msg "镜像构建失败"
            echo "尝试手动构建..."
            echo "docker build -t ${CUSTOM_IMAGE} -f /root/ubuntu-ssh.dockerfile ."
            exit 1
        fi
    else
        info_msg "自定义镜像已存在"
    fi
}

show_containers() {
    info_msg "当前运行的Ubuntu容器:"
    local container_count=$(docker ps --filter "name=${CONTAINER_PREFIX}" --format "{{.Names}}" | wc -l)
    if [ "$container_count" -eq 0 ]; then
        echo "暂无运行的容器"
    else
        docker ps --filter "name=${CONTAINER_PREFIX}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    fi
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
    
    # 检查端口是否被占用
    if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        error_msg "端口 ${port} 已被占用，跳过创建"
        return 1
    fi
    
    # 创建容器
    info_msg "执行: docker run -d --name ${container_name} -p ${port}:22 ${CUSTOM_IMAGE}"
    if docker run -d --restart=unless-stopped --name ${container_name} -p ${port}:22 ${CUSTOM_IMAGE}; then
        success_msg "容器创建命令执行成功"
    else
        error_msg "容器创建失败!"
        return 1
    fi
    
    # 等待容器启动
    info_msg "等待容器启动..."
    sleep 15
    
    # 验证容器是否运行
    if docker ps | grep -q ${container_name}; then
        success_msg "容器运行状态正常"
    else
        error_msg "容器创建后未运行，查看日志:"
        docker logs ${container_name}
        info_msg "尝试启动容器..."
        if docker start ${container_name}; then
            sleep 5
            if docker ps | grep -q ${container_name}; then
                success_msg "容器启动成功"
            else
                error_msg "容器仍然无法启动"
                return 1
            fi
        else
            error_msg "容器启动失败"
            return 1
        fi
    fi
    
    # 设置自定义密码
    if [ "${DEFAULT_PASSWORD}" != "123456789" ]; then
        info_msg "设置自定义密码..."
        if docker exec ${container_name} bash -c "echo 'root:${DEFAULT_PASSWORD}' | chpasswd"; then
            success_msg "密码设置成功"
        else
            warning_msg "密码设置失败，使用默认密码"
        fi
    fi
    
    success_msg "容器 ${container_name} 创建完成!"
    echo "SSH连接信息:"
    echo "  容器名: ${container_name}"
    echo "  SSH端口: ${port}"
    echo "  用户名: root"
    echo "  密码: ${DEFAULT_PASSWORD}"
    echo "  连接命令: ssh root@127.0.0.1 -p ${port}"
    echo ""
    
    # 显示容器状态
    info_msg "容器状态:"
    docker ps --filter "name=${container_name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
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
    
    local success_count=0
    local fail_count=0
    
    for i in $(seq 1 $count); do
        local container_num=$((start_num + i - 1))
        local container_port=$((current_port + i - 1))
        
        echo ""
        info_msg "正在创建第 ${i}/${count} 个容器..."
        if create_container $container_num $container_port; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
            error_msg "容器 ${CONTAINER_PREFIX}${container_num} 创建失败"
        fi
    done
    
    echo ""
    if [ $success_count -gt 0 ]; then
        success_msg "成功创建 ${success_count} 个容器"
    fi
    if [ $fail_count -gt 0 ]; then
        error_msg "失败 ${fail_count} 个容器"
    fi
    
    show_containers
}

delete_container() {
    show_containers
    read -p "请输入要删除的容器名称: " container_name
    if [ -z "$container_name" ]; then
        error_msg "容器名称不能为空"
        return 1
    fi
    
    if docker rm -f ${container_name} 2>/dev/null; then
        success_msg "容器 ${container_name} 已删除"
    else
        error_msg "删除失败，容器可能不存在"
    fi
}

delete_all_containers() {
    local containers=$(docker ps -a --filter "name=${CONTAINER_PREFIX}" --format "{{.Names}}")
    if [ -z "$containers" ]; then
        info_msg "没有找到要删除的容器"
        return 0
    fi
    
    echo "以下容器将被删除:"
    echo "$containers"
    echo ""
    read -p "确认删除所有容器？(y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        if docker rm -f $(echo $containers) 2>/dev/null; then
            success_msg "所有容器已删除"
        else
            error_msg "删除过程中出现错误"
        fi
    else
        info_msg "取消删除操作"
    fi
}

restart_container() {
    show_containers
    read -p "请输入要重启的容器名称: " container_name
    if [ -z "$container_name" ]; then
        error_msg "容器名称不能为空"
        return 1
    fi
    
    if docker restart ${container_name} 2>/dev/null; then
        success_msg "容器 ${container_name} 已重启"
        sleep 3
        info_msg "容器状态:"
        docker ps --filter "name=${container_name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        error_msg "重启失败，容器可能不存在"
    fi
}

show_menu() {
    echo ""
    echo "=========================================="
    echo "    Docker Ubuntu 容器管理脚本"
    echo "    iStoreOS 专用版"
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
    clear
    info_msg "初始化 Docker 环境..."
    check_docker
    
    # 先创建 Dockerfile，再构建镜像
    create_dockerfile
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
            4) delete_container ;;
            5) delete_all_containers ;;
            6) restart_container ;;
            7) 
                success_msg "再见!"
                exit 0 
                ;;
            *) error_msg "无效选择" ;;
        esac
        echo "" && read -p "按回车键继续..."
        clear
    done
}

# 脚本入口
main
