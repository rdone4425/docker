# Docker 镜像管理工具使用手册

## 快速安装

使用以下命令一键安装并运行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/rdone4425/docker/main/docker-publish.sh)
```

此命令会自动下载并执行最新版本的脚本，无需手动下载和设置权限。

## 简介

本工具是一个用于简化 Docker 镜像构建、上传和管理的命令行脚本。它提供了以下主要功能：

- 从 GitHub 仓库自动构建 Docker 镜像
- 自动管理镜像版本号
- 同时推送到官方 Docker Hub 和加速镜像仓库
- 测试和选择最快的镜像仓库
- 记录和查看构建历史
- 生成镜像拉取和运行命令

## 安装和设置

1. 下载脚本：
   ```bash
   wget https://raw.githubusercontent.com/rdone4425/docker/main/docker-publish.sh
   chmod +x docker-publish.sh
   ```

2. 初次运行时，脚本会引导您设置 Docker Hub 账号和密码。

## 主要功能

### 1. 登录镜像仓库

登录到 Docker Hub，以便能够推送镜像。账号信息会保存在本地配置文件中，后续无需重复输入。

### 2. 从 GitHub 构建并上传镜像

- 自动从 GitHub 仓库克隆代码
- 构建 Docker 镜像
- 自动检查版本号并递增
- 推送到官方 Docker Hub
- 同时推送到代理镜像仓库
- 清理构建过程中的临时文件
- 提供拉取和运行命令

### 3. 设置版本号

管理镜像版本号，可以手动设置或使用自动递增功能。

### 4. 镜像仓库设置

- 从预定义列表中选择镜像仓库
- 手动设置自定义镜像仓库
- 测试不同镜像仓库的速度，选择最快的仓库

### 5. 构建历史与拉取命令

- 查看最近的构建历史记录
- 获取特定镜像的拉取和运行命令

## 使用示例

### 构建并上传镜像

```bash
# 使用一键安装命令
bash <(curl -Ls https://raw.githubusercontent.com/rdone4425/docker/main/docker-publish.sh)

# 或者如果已下载脚本
./docker-publish.sh

# 选择选项 2，然后输入 GitHub 仓库地址
```

### 查看构建历史

```bash
# 使用一键安装命令
bash <(curl -Ls https://raw.githubusercontent.com/rdone4425/docker/main/docker-publish.sh)

# 选择选项 5，然后根据提示操作
```

### 测试镜像仓库速度

```bash
# 使用一键安装命令
bash <(curl -Ls https://raw.githubusercontent.com/rdone4425/docker/main/docker-publish.sh)

# 选择选项 4，然后选择"测试镜像仓库速度"
```

## 配置文件

脚本使用以下配置文件保存状态：

- `.docker_config`: 保存 Docker Hub 账号信息
- `.version_config`: 保存当前版本号
- `.registry_config`: 保存当前使用的镜像仓库
- `.build_history`: 保存构建历史记录

## 镜像拉取命令

脚本提供了两种拉取命令：

1. 通过代理仓库拉取（推荐，速度更快）：
   ```bash
   docker pull <代理仓库地址>/<用户名>/<仓库名>:<版本号>
   ```

2. 通过官方仓库拉取：
   ```bash
   docker pull <用户名>/<仓库名>:<版本号>
   ```

## 运行容器命令

脚本同时提供了容器运行命令：

```bash
docker run -d --name <应用名称> <镜像地址>
```

如果需要映射端口或挂载卷，可以使用：

```bash
docker run -d --name <应用名称> -p <主机端口>:<容器端口> <镜像地址>
```

## 注意事项

- 脚本需要有 Docker 和 Git 环境
- 需要有 Docker Hub 账号
- 确保有足够的权限构建和推送镜像