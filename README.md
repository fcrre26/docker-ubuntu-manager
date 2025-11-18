# Docker Ubuntu 容器管理脚本

一个简洁的交互式脚本，用于快速创建和管理多个Ubuntu Docker容器。

## 快速安装

### 一键下载并运行

```bash
wget -q -O- https://raw.githubusercontent.com/fcrre26/docker-ubuntu-manager/refs/heads/main/docker-ubuntu-manager.sh | sh
```

### 手动安装

```bash
wget https://raw.githubusercontent.com/fcrre26/docker-ubuntu-manager/refs/heads/main/docker-ubuntu-manager.sh
wget https://raw.githubusercontent.com/fcrre26/docker-ubuntu-manager/refs/heads/main/ubuntu-ssh.dockerfile
chmod +x docker-ubuntu-manager.sh
./docker-ubuntu-manager.sh
```

## 功能特性

- 🚀 一键创建Ubuntu容器
- 🔢 批量创建多个容器
- 🎯 自动递增端口号
- 🛠️ 完整的容器管理
- 📋 交互式彩色菜单

## 默认配置

- **容器前缀**: `ubuntu-ssh`
- **基础端口**: `32200`
- **默认密码**: `123456789`

## 使用方法

运行脚本后选择相应选项：

1. 查看容器状态
2. 创建单个容器
3. 批量创建容器
4. 删除单个容器
5. 删除所有容器
6. 重启SSH服务
7. 退出

## 连接示例

```bash
ssh root@你的IP -p 32200
# 密码: 123456789
```

## 注意事项

- 确保Docker服务正常运行
- 每个容器约占用200MB空间
- 默认配置仅用于测试环境

---

享受便捷的容器管理！ 🎉
