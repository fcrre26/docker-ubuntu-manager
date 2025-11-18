# 手动创建 Dockerfile
cat > /root/ubuntu-ssh.dockerfile << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list

RUN apt update && \
    apt install -y openssh-server sudo curl wget vim && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd

RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

RUN echo 'root:123456789' | chpasswd

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
EOF

# 手动构建镜像
docker build -t ubuntu-ssh-local:latest -f /root/ubuntu-ssh.dockerfile .
