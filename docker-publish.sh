#!/bin/bash
set -e

# 显示欢迎信息
echo "========================================================"
echo "  Docker镜像构建与发布脚本 v1.0"
echo "  来源: https://github.com/rdone4425/docker"
echo "========================================================"
echo ""

# 配置信息
ENV_FILE=".env"
IMAGE_TAG="latest"

# 从Git仓库获取仓库名
get_repo_name() {
  # 检查是否在Git仓库中
  if ! command -v git &> /dev/null || ! git rev-parse --is-inside-work-tree &> /dev/null; then
    # 尝试获取当前目录名作为仓库名
    local dir_name=$(basename "$(pwd)")
    echo -n "无法从Git仓库获取名称，是否使用当前目录名'$dir_name'作为镜像名? (y/n): "
    read -r use_dir_name
    
    if [[ "$use_dir_name" =~ ^[Yy]$ ]]; then
      echo "$dir_name"
    else
      echo -n "请输入镜像名称: "
      read -r custom_name
      if [ -z "$custom_name" ]; then
        echo "未提供名称，使用当前目录名'$dir_name'"
        echo "$dir_name"
      else
        echo "$custom_name"
      fi
    fi
    return
  fi
  
  # 获取远程仓库URL
  local remote_url=$(git config --get remote.origin.url 2>/dev/null)
  
  if [ -z "$remote_url" ]; then
    # 尝试获取当前目录名作为仓库名
    local dir_name=$(basename "$(pwd)")
    echo -n "无法获取Git远程仓库URL，是否使用当前目录名'$dir_name'作为镜像名? (y/n): "
    read -r use_dir_name
    
    if [[ "$use_dir_name" =~ ^[Yy]$ ]]; then
      echo "$dir_name"
    else
      echo -n "请输入镜像名称: "
      read -r custom_name
      if [ -z "$custom_name" ]; then
        echo "未提供名称，使用当前目录名'$dir_name'"
        echo "$dir_name"
      else
        echo "$custom_name"
      fi
    fi
    return
  fi
  
  # 从URL中提取仓库名
  local repo_name=""
  
  # 处理不同格式的Git URL
  if [[ "$remote_url" =~ .*github\.com[:/]([^/]+)/([^/.]+)(\.git)? ]]; then
    # GitHub格式: https://github.com/user/repo.git 或 git@github.com:user/repo.git
    repo_name="${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ .*[:/]([^/]+)(\.git)? ]]; then
    # 其他格式: 提取最后一个路径组件
    repo_name="${BASH_REMATCH[1]}"
    # 移除.git后缀
    repo_name="${repo_name%.git}"
  else
    # 如果无法解析，使用当前目录名
    repo_name=$(basename "$(pwd)")
  fi
  
  # 确保名称符合Docker镜像命名规则（小写，只允许字母、数字、连字符）
  repo_name=$(echo "$repo_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
  
  echo "$repo_name"
}

# 从GitHub URL中提取仓库名和用户名
extract_from_github_url() {
  local url=$1
  local repo_name=""
  local user_name=""
  
  # 处理不同格式的GitHub URL
  if [[ "$url" =~ https://github\.com/([^/]+)/([^/.]+)(\.git)? ]]; then
    # HTTPS格式: https://github.com/user/repo.git
    user_name="${BASH_REMATCH[1]}"
    repo_name="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ git@github\.com:([^/]+)/([^/.]+)(\.git)? ]]; then
    # SSH格式: git@github.com:user/repo.git
    user_name="${BASH_REMATCH[1]}"
    repo_name="${BASH_REMATCH[2]}"
  fi
  
  echo "$user_name $repo_name"
}

# 显示帮助信息
show_help() {
  echo "使用方法: $0 [选项]"
  echo "选项:"
  echo "  -u, --username USERNAME    指定Docker Hub用户名 (会保存到.env文件中)"
  echo "  -t, --tag TAG              指定镜像标签 (默认: latest)"
  echo "  -n, --name NAME            指定镜像名称 (默认: 从Git仓库名获取)"
  echo "  -g, --github-url URL       指定GitHub仓库URL"
  echo "  -f, --force                强制重新输入所有信息"
  echo "  -h, --help                 显示帮助信息"
  echo "例子:"
  echo "  $0 --username johndoe --tag v1.0"
  echo "  $0 --tag v2.0              # 使用保存的用户名"
  echo "  $0 --name custom-name      # 使用自定义镜像名称"
  echo "  $0 --github-url https://github.com/user/repo.git"
}

# 加载.env文件中的环境变量
load_env() {
  if [ -f "$ENV_FILE" ]; then
    echo "加载环境变量文件: $ENV_FILE"
    while IFS='=' read -r key value || [ -n "$key" ]; do
      # 忽略注释和空行
      [[ $key =~ ^#.*$ ]] || [ -z "$key" ] && continue
      # 去除引号
      value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
      # 导出变量
      export "$key=$value"
    done < "$ENV_FILE"
  fi
}

# 保存环境变量到.env文件
save_env() {
  local key=$1
  local value=$2
  
  # 如果文件不存在，创建它
  if [ ! -f "$ENV_FILE" ]; then
    echo "# Docker发布脚本环境变量" > "$ENV_FILE"
    echo "# 创建于 $(date)" >> "$ENV_FILE"
    echo "" >> "$ENV_FILE"
  fi
  
  # 检查变量是否已存在
  if grep -q "^$key=" "$ENV_FILE"; then
    # 在Unix/Linux上更新变量
    sed -i "s/^$key=.*/$key=\"$value\"/" "$ENV_FILE" 2>/dev/null || \
    # 在macOS上更新变量
    sed -i "" "s/^$key=.*/$key=\"$value\"/" "$ENV_FILE"
  else
    # 添加新变量
    echo "$key=\"$value\"" >> "$ENV_FILE"
  fi
  
  echo "已保存 $key 到 $ENV_FILE 文件"
}

# 加载环境变量
load_env

# 设置默认值
DOCKER_USERNAME=${DOCKER_USERNAME:-""}
DOCKER_PASSWORD=${DOCKER_PASSWORD:-""}
GITHUB_URL=${GITHUB_URL:-""}
FORCE_INPUT=${FORCE_INPUT:-false}
IMAGE_NAME=${IMAGE_NAME:-"$(get_repo_name)"}
GITHUB_USERNAME=${GITHUB_USERNAME:-""}

# 如果设置了DOCKER_TAG环境变量，则使用它
if [ ! -z "$DOCKER_TAG" ]; then
  IMAGE_TAG="$DOCKER_TAG"
fi

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -u|--username)
      DOCKER_USERNAME="$2"
      shift
      shift
      ;;
    -t|--tag)
      IMAGE_TAG="$2"
      shift
      shift
      ;;
    -n|--name)
      IMAGE_NAME="$2"
      shift
      shift
      ;;
    -g|--github-url)
      GITHUB_URL="$2"
      shift
      shift
      ;;
    -f|--force)
      FORCE_INPUT=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "未知选项: $1"
      show_help
      exit 1
      ;;
  esac
done

# 检查Docker是否安装
if ! command -v docker &> /dev/null; then
  echo "错误: Docker未安装或不在PATH中"
  exit 1
fi

# 如果用户名为空或强制输入，则提示输入
if [ -z "$DOCKER_USERNAME" ] || [ "$FORCE_INPUT" = true ]; then
  echo -n "请输入您的Docker Hub用户名: "
  read -r DOCKER_USERNAME
  
if [ -z "$DOCKER_USERNAME" ]; then
    echo "错误: 用户名不能为空"
  exit 1
fi
  
  # 保存用户名到.env文件
  save_env "DOCKER_USERNAME" "$DOCKER_USERNAME"
  
  # 提示输入Docker Hub密码
  echo -n "请输入您的Docker Hub密码 (将保存到.env文件): "
  read -rs DOCKER_PASSWORD
  echo # 添加换行
  
  if [ ! -z "$DOCKER_PASSWORD" ]; then
    # 保存密码到.env文件
    save_env "DOCKER_PASSWORD" "$DOCKER_PASSWORD"
    echo "Docker Hub密码已保存"
  else
    echo "警告: 未提供Docker Hub密码，登录时可能需要手动输入"
  fi
fi

# 如果GitHub URL为空或强制输入，则提示输入
if [ -z "$GITHUB_URL" ] || [ "$FORCE_INPUT" = true ]; then
  echo -n "请输入GitHub仓库URL (https://github.com/user/repo.git): "
  read -r GITHUB_URL
  
  if [ -z "$GITHUB_URL" ]; then
    echo "警告: 未提供GitHub仓库URL，将使用默认设置"
  else
    # 从URL中提取用户名和仓库名
    read -r gh_user gh_repo <<< "$(extract_from_github_url "$GITHUB_URL")"
    
    if [ ! -z "$gh_user" ] && [ ! -z "$gh_repo" ]; then
      echo "检测到GitHub用户名: $gh_user"
      echo "检测到GitHub仓库名: $gh_repo"
      
      # 如果用户确认，使用提取的仓库名作为镜像名
      echo -n "是否使用 '$gh_repo' 作为镜像名? (y/n): "
      read -r use_repo_name
      
      if [[ "$use_repo_name" =~ ^[Yy]$ ]]; then
        IMAGE_NAME="$gh_repo"
        echo "已设置镜像名称为: $IMAGE_NAME"
      fi
      
      # 保存GitHub用户名
      GITHUB_USERNAME="$gh_user"
      save_env "GITHUB_USERNAME" "$GITHUB_USERNAME"
    else
      echo "警告: 无法从URL中提取用户名和仓库名"
    fi
    
    # 保存GitHub URL
    save_env "GITHUB_URL" "$GITHUB_URL"
  fi
fi

# 保存镜像名到环境变量
save_env "IMAGE_NAME" "$IMAGE_NAME"

echo "===== 开始构建和发布Docker镜像 ====="
echo "镜像名称: $IMAGE_NAME"
echo "Docker用户名: $DOCKER_USERNAME"
echo "镜像标签: $IMAGE_TAG"
if [ ! -z "$GITHUB_URL" ]; then
  echo "GitHub仓库: $GITHUB_URL"
fi

# 构建Docker镜像
echo -e "\n===== 步骤1: 构建Docker镜像 ====="
docker build -t $IMAGE_NAME .
if [ $? -ne 0 ]; then
  echo "错误: 构建Docker镜像失败"
  exit 1
fi
echo "镜像构建成功!"

# 标记Docker镜像
echo -e "\n===== 步骤2: 标记Docker镜像 ====="
docker tag $IMAGE_NAME $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG
if [ $? -ne 0 ]; then
  echo "错误: 标记Docker镜像失败"
  exit 1
fi
echo "镜像标记成功!"

# 登录Docker Hub
echo -e "\n===== 步骤3: 登录Docker Hub ====="
# 检查是否已经登录
if [ -f "$HOME/.docker/config.json" ] && grep -q "auth" "$HOME/.docker/config.json"; then
  echo "检测到Docker已登录，跳过登录步骤..."
else
  if [ ! -z "$DOCKER_PASSWORD" ]; then
    # 使用保存的密码自动登录
    echo "使用保存的密码登录Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
  else
    # 手动输入密码
echo "请输入您的Docker Hub密码:"
docker login -u $DOCKER_USERNAME
  fi
  
if [ $? -ne 0 ]; then
  echo "错误: 登录Docker Hub失败"
  exit 1
fi
echo "登录成功!"
fi

# 推送镜像到Docker Hub
echo -e "\n===== 步骤4: 推送镜像到Docker Hub ====="
docker push $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG
if [ $? -ne 0 ]; then
  echo "错误: 推送镜像失败"
  exit 1
fi
echo "镜像推送成功!"

# 保存标签到环境变量
save_env "DOCKER_TAG" "$IMAGE_TAG"

# 删除本地构建环境中的镜像
echo -e "\n===== 步骤5: 删除本地镜像 ====="
echo "正在删除本地镜像: $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
docker rmi $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG
if [ $? -ne 0 ]; then
  echo "警告: 删除标记的镜像失败"
else
  echo "标记的镜像删除成功!"
fi

echo "正在删除本地镜像: $IMAGE_NAME"
docker rmi $IMAGE_NAME
if [ $? -ne 0 ]; then
  echo "警告: 删除基础镜像失败"
else
  echo "基础镜像删除成功!"
fi

echo -e "\n===== 完成! ====="
echo "镜像已成功发布到Docker Hub: $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
echo "您可以使用以下命令拉取此镜像:"
echo "docker pull $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG" 
echo -e "\n下次运行只需执行: $0" 