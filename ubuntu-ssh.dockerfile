# 创建镜像构建文件
cat > /root/ubuntu-ssh.dockerfile << 'EOF'
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && \
    apt install -y openssh-server sudo curl wget vim && \
    apt clean
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
RUN echo 'root:123456789' | chpasswd
RUN mkdir -p /run/sshd
RUN echo '#!/bin/bash\nmkdir -p /run/sshd\n/usr/sbin/sshd -D &\nsleep infinity' > /start.sh && \
    chmod +x /start.sh
EXPOSE 22
CMD ["/bin/bash", "/start.sh"]
EOF
