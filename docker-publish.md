# Docker镜像构建与发布脚本使用指南

## 功能概述

`docker-publish.sh`是一个功能完善的Bash脚本，用于自动化Docker镜像的构建、标记、发布和清理过程。该脚本具有以下主要功能：

- 自动从Git仓库获取项目名称作为Docker镜像名
- 支持用户交互式设置镜像名称
- 自动登录Docker Hub并推送镜像
- 自动清理本地构建环境中的镜像
- 配置信息持久化保存到`.env`文件

## 使用方法

### 基本用法

```bash
./docker-publish.sh
```

首次运行时，脚本会引导您设置必要的配置信息。

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

# 指定GitHub仓库URL
./docker-publish.sh --github-url https://github.com/user/repo.git
```

## 工作流程

脚本执行以下步骤：

1. **配置准备**：
   - 加载`.env`文件中的环境变量
   - 解析命令行参数
   - 获取或提示输入必要信息

2. **构建镜像**：
   - 使用`docker build`命令构建本地镜像

3. **标记镜像**：
   - 使用`docker tag`命令标记镜像，格式为`用户名/镜像名:标签`

4. **登录Docker Hub**：
   - 使用保存的凭据或提示输入密码登录Docker Hub

5. **推送镜像**：
   - 使用`docker push`命令将镜像推送到Docker Hub

6. **清理本地镜像**：
   - 删除标记的镜像（`用户名/镜像名:标签`）
   - 删除基础镜像（`镜像名`）

## 镜像命名逻辑

脚本会尝试通过以下方式获取镜像名称：

1. 首先检查命令行参数中是否指定了名称
2. 如果未指定，尝试从Git仓库获取名称：
   - 如果是GitHub仓库，提取仓库名
   - 如果是其他Git仓库，提取最后一个路径组件
3. 如果无法从Git获取名称：
   - 提示用户是否使用当前目录名
   - 或者让用户输入自定义名称

## 配置持久化

脚本会将以下配置信息保存到`.env`文件中：

- Docker Hub用户名（`DOCKER_USERNAME`）
- Docker Hub密码（`DOCKER_PASSWORD`）
- GitHub仓库URL（`GITHUB_URL`）
- GitHub用户名（`GITHUB_USERNAME`）
- 镜像名称（`IMAGE_NAME`）
- 镜像标签（`DOCKER_TAG`）

## 注意事项

- 脚本需要Docker已安装并可用
- 首次使用时需要提供Docker Hub凭据
- 推荐在Git仓库目录中运行，以便自动获取仓库名称
- 本地镜像会在推送成功后自动删除，如需保留请修改脚本 