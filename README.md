# Docker镜像构建与发布脚本使用指南

## 功能概述

`docker-publish.sh`是一个功能完善的Bash脚本，用于自动化Docker镜像的构建、标记、发布和清理过程。该脚本具有以下主要功能：

- 自动从Git仓库获取项目名称作为Docker镜像名
- 支持用户交互式设置镜像名称
- 自动登录Docker Hub并推送镜像
- 自动清理本地构建环境中的镜像和仓库目录
- 配置信息持久化保存到`.env`文件
- 智能查找Dockerfile位置，支持多种项目结构
- 支持切换Docker账号
- **自动克隆GitHub仓库**，无需手动下载项目文件
- **提供镜像代理加速下载**，解决国内网络问题
- **自动清理下载的仓库**，节省磁盘空间

## 使用方法

### 基本用法

```bash
./docker-publish.sh
```

首次运行时，脚本会引导您设置必要的配置信息。

### 通过curl直接执行

无需下载脚本，可以直接通过以下命令执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/rdone4425/docker/main/docker-publish.sh)
```

这种方式会自动从GitHub获取最新版本的脚本并执行。

### 命令行选项

```bash
./docker-publish.sh [选项]
```

| 选项 | 说明 |
|------|------|
| `-u, --username USERNAME` | 指定Docker Hub用户名 |
| `-t, --tag TAG` | 指定镜像标签（默认：latest） |
| `-n, --name NAME` | 指定镜像名称（默认：从Git仓库名获取） |
| `-g, --github-url URL` | 指定GitHub仓库URL |
| `-d, --dockerfile PATH` | 指定Dockerfile路径 |
| `-f, --force` | 强制重新输入所有信息 |
| `-h, --help` | 显示帮助信息 |

### 示例

```bash
# 使用指定用户名和标签
./docker-publish.sh --username johndoe --tag v1.0

# 使用保存的用户名，指定新标签
./docker-publish.sh --tag v2.0

# 使用自定义镜像名称
./docker-publish.sh --name custom-name

# 指定GitHub仓库URL，自动克隆仓库并构建
./docker-publish.sh --github-url https://github.com/user/repo.git

# 指定Dockerfile路径
./docker-publish.sh --dockerfile ./path/to/Dockerfile

# 通过curl执行并指定标签
bash <(curl -Ls https://raw.githubusercontent.com/rdone4425/docker/main/docker-publish.sh) --tag v1.0
```

## 工作流程

脚本执行以下步骤：

1. **配置准备**：
   - 加载`.env`文件中的环境变量
   - 解析命令行参数
   - 获取或提示输入必要信息

2. **获取项目文件**：
   - 检查本地是否存在Dockerfile
   - 如果不存在且提供了GitHub URL，自动克隆整个仓库

3. **构建镜像**：
   - 自动查找Dockerfile位置
   - 使用`docker build`命令构建本地镜像

4. **标记镜像**：
   - 使用`docker tag`命令标记镜像，格式为`用户名/镜像名:标签`

5. **登录Docker Hub**：
   - 使用保存的凭据或提示输入密码登录Docker Hub

6. **推送镜像**：
   - 使用`docker push`命令将镜像推送到Docker Hub

7. **清理本地镜像**：
   - 删除标记的镜像（`用户名/镜像名:标签`）
   - 删除基础镜像（`镜像名`）

8. **清理仓库目录**：
   - 删除从GitHub克隆或下载的仓库目录
   - 释放磁盘空间

## 自动克隆GitHub仓库

当脚本无法在本地找到Dockerfile但提供了GitHub URL时，会自动执行以下操作：

1. 从GitHub URL中提取仓库名称
2. 创建对应的本地目录（如果已存在则先删除）
3. 使用`git clone`命令克隆整个仓库
4. 如果git命令不可用，则使用curl或wget下载必要文件：
   - Dockerfile
   - package.json和package-lock.json
   - docker-compose.yml
   - docker-entrypoint.sh（并设置为可执行）
   - .dockerignore
   - .env.example
   - 创建基本目录结构并下载基本文件

这样，用户只需提供GitHub仓库URL，脚本就能自动获取所有必要的项目文件，无需手动下载或克隆仓库。

## Dockerfile查找逻辑

脚本会按照以下顺序查找Dockerfile：

1. 首先检查是否通过`--dockerfile`选项指定了Dockerfile路径
2. 如果未指定，尝试在当前目录中查找`Dockerfile`
3. 如果未找到，尝试在从GitHub URL提取的仓库名目录中查找
4. 如果仍未找到，尝试在镜像名目录中查找
5. 如果所有位置都未找到Dockerfile，尝试从GitHub克隆仓库
6. 如果仍然找不到，脚本会显示错误信息并退出

## 镜像命名逻辑

脚本会尝试通过以下方式获取镜像名称：

1. 首先检查命令行参数中是否指定了名称
2. 如果未指定，尝试从Git仓库获取名称：
   - 如果是GitHub仓库，提取仓库名
   - 如果是其他Git仓库，提取最后一个路径组件
3. 如果无法从Git获取名称：
   - 使用当前目录名作为默认名称

## Docker账号管理

脚本支持以下Docker账号管理功能：

1. 首次运行时，提示输入Docker Hub用户名和密码
2. 后续运行时，使用保存的凭据自动登录
3. 可以随时切换到其他Docker账号，无需重新运行脚本或修改配置文件
4. 切换账号时会自动登出当前账号，确保凭据安全

## 配置持久化

脚本会将以下配置信息保存到`.env`文件中：

- Docker Hub用户名（`DOCKER_USERNAME`）
- Docker Hub密码（`DOCKER_PASSWORD`）
- GitHub仓库URL（`GITHUB_URL`）
- GitHub用户名（`GITHUB_USERNAME`）
- 镜像名称（`IMAGE_NAME`）
- 镜像标签（`DOCKER_TAG`）

## 使用镜像代理加速

对于国内用户，从Docker Hub拉取镜像可能会比较慢。脚本提供了使用镜像代理的方式来加速下载：

```bash
# 直接从Docker Hub拉取
docker pull username/imagename:tag

# 使用镜像代理加速
docker pull docker.442595.xyz/username/imagename:tag
```

镜像代理服务由 [docker.442595.xyz](https://docker.442595.xyz/) 提供，可以显著提高国内网络环境下的镜像下载速度。

## 注意事项

- 脚本需要Docker已安装并可用
- 首次使用时需要提供Docker Hub凭据
- 推荐在Git仓库目录中运行，以便自动获取仓库名称
- 本地镜像会在推送成功后自动删除，如需保留请修改脚本
- 如果项目结构复杂，建议使用`--dockerfile`选项直接指定Dockerfile路径
- 自动克隆功能需要git命令可用，如果不可用会尝试使用curl/wget下载基本文件
- 如果遇到网络问题，可以使用镜像代理加速下载 