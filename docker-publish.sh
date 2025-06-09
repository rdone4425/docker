#!/bin/bash
set -e

# 自我保存功能：当脚本通过管道执行时，将自己保存到本地
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
if [[ "$0" == *"/dev/fd/"* ]] || [[ "$0" == "bash" ]]; then
  # 如果是通过管道执行，则将自己保存到当前目录
  SCRIPT_NAME="docker-publish.sh"
  if [ ! -f "$SCRIPT_NAME" ]; then
    echo "正在将脚本保存到本地文件: $SCRIPT_NAME"
    cat > "$SCRIPT_NAME" << 'EOF'
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
DOCKERFILE_PATH="./Dockerfile"
DOCKERFILE_DIR="."
DOCKER_PROXY=""

# 调试信息函数
debug_info() {
  echo -e "\n[调试信息] $1"
}

# 从Git仓库获取仓库名
get_repo_name() {
  # 检查是否在Git仓库中
  if ! command -v git &> /dev/null || ! git rev-parse --is-inside-work-tree &> /dev/null 2>/dev/null; then
    # 尝试获取当前目录名作为仓库名
    local dir_name=$(basename "$(pwd)")
    echo "$dir_name"
    return
  fi
  
  # 获取远程仓库URL
  local remote_url=$(git config --get remote.origin.url 2>/dev/null)
  
  if [ -z "$remote_url" ]; then
    # 使用当前目录名作为仓库名
    local dir_name=$(basename "$(pwd)")
    echo "$dir_name"
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
  echo "用法: $0 [选项]"
  echo "选项:"
  echo "  -u, --username USERNAME   指定Docker Hub用户名"
  echo "  -t, --tag TAG             指定镜像标签 (默认: latest)"
  echo "  -n, --name NAME           指定镜像名称 (默认: 从当前目录名或GitHub仓库名获取)"
  echo "  -g, --github-url URL      指定GitHub仓库URL"
  echo "  -f, --force               强制重新输入所有信息"
  echo "  -d, --dockerfile PATH     指定Dockerfile路径"
  echo "  -p, --proxy PROXY         指定Docker镜像代理地址"
  echo "  -h, --help                显示此帮助信息"
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
DOCKER_PROXY=${DOCKER_PROXY:-""}

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
    -d|--dockerfile)
      DOCKERFILE_PATH="$2"
      DOCKERFILE_DIR=$(dirname "$DOCKERFILE_PATH")
      shift
      shift
      ;;
    -p|--proxy)
      DOCKER_PROXY="$2"
      save_env "DOCKER_PROXY" "$DOCKER_PROXY"
      shift
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
  echo "========================================================"
  echo "请输入您的Docker Hub用户名: "
  read -r DOCKER_USERNAME
  
if [ -z "$DOCKER_USERNAME" ]; then
    echo "错误: 用户名不能为空"
  exit 1
fi
  
  # 保存用户名到.env文件
  save_env "DOCKER_USERNAME" "$DOCKER_USERNAME"
  
  # 提示输入Docker Hub密码
  echo "请输入您的Docker Hub密码 (将保存到.env文件): "
  read -rs DOCKER_PASSWORD
  echo # 添加换行
  
  if [ ! -z "$DOCKER_PASSWORD" ]; then
    # 保存密码到.env文件
    save_env "DOCKER_PASSWORD" "$DOCKER_PASSWORD"
    echo "Docker Hub密码已保存"
  else
    echo "警告: 未提供Docker Hub密码，登录时可能需要手动输入"
  fi
  
  # 提示输入Docker镜像代理地址
  echo "请输入Docker镜像代理地址 (留空则不使用代理): "
  read -r input_proxy
  
  if [ ! -z "$input_proxy" ]; then
    DOCKER_PROXY="$input_proxy"
  fi
  
  # 保存代理地址到.env文件
  save_env "DOCKER_PROXY" "$DOCKER_PROXY"
  if [ ! -z "$DOCKER_PROXY" ]; then
    echo "Docker镜像代理地址已设置为: $DOCKER_PROXY"
  else
    echo "未设置Docker镜像代理地址"
  fi
else
  # 显示当前Docker账号信息
  echo "========================================================"
  echo "当前Docker账号: $DOCKER_USERNAME"
  echo "是否切换到其他Docker账号? (y/n): "
  read -r switch_account
  
  if [[ "$switch_account" =~ ^[Yy]$ ]]; then
    echo "请输入新的Docker Hub用户名: "
    read -r DOCKER_USERNAME
    
    if [ -z "$DOCKER_USERNAME" ]; then
      echo "错误: 用户名不能为空"
      exit 1
    fi
    
    # 保存新用户名到.env文件
    save_env "DOCKER_USERNAME" "$DOCKER_USERNAME"
    
    # 提示输入新Docker Hub密码
    echo "请输入新的Docker Hub密码 (将保存到.env文件): "
    read -rs DOCKER_PASSWORD
    echo # 添加换行
    
    if [ ! -z "$DOCKER_PASSWORD" ]; then
      # 保存新密码到.env文件
      save_env "DOCKER_PASSWORD" "$DOCKER_PASSWORD"
      echo "新的Docker Hub密码已保存"
    else
      echo "警告: 未提供Docker Hub密码，登录时可能需要手动输入"
    fi
    
    # 确保登出当前账号
    echo "正在登出当前Docker账号..."
    docker logout
    
    # 提示输入Docker镜像代理地址
    echo "是否需要修改Docker镜像代理地址? (y/n): "
    read -r change_proxy
    
    if [[ "$change_proxy" =~ ^[Yy]$ ]]; then
      echo "当前Docker镜像代理地址: $DOCKER_PROXY"
      echo "请输入新的Docker镜像代理地址 (留空则不使用代理): "
      read -r input_proxy
      
      DOCKER_PROXY="$input_proxy"
      
      # 保存代理地址到.env文件
      save_env "DOCKER_PROXY" "$DOCKER_PROXY"
      if [ ! -z "$DOCKER_PROXY" ]; then
        echo "Docker镜像代理地址已设置为: $DOCKER_PROXY"
      else
        echo "未设置Docker镜像代理地址"
      fi
    fi
  fi
fi

# 如果GitHub URL为空或强制输入，则提示输入
if [ -z "$GITHUB_URL" ] || [ "$FORCE_INPUT" = true ]; then
  echo "========================================================"
  echo "请输入GitHub仓库URL (https://github.com/user/repo.git): "
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
      echo "是否使用 '$gh_repo' 作为镜像名? (y/n): "
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

# 检查Dockerfile是否存在
if [ ! -f "$DOCKERFILE_PATH" ]; then
  # 从GitHub URL中提取仓库名
  REPO_NAME=""
  if [ ! -z "$GITHUB_URL" ]; then
    read -r gh_user gh_repo <<< "$(extract_from_github_url "$GITHUB_URL")"
    if [ ! -z "$gh_repo" ]; then
      REPO_NAME="$gh_repo"
    fi
  fi
  
  # 如果有仓库名，尝试在该目录中查找Dockerfile
  if [ ! -z "$REPO_NAME" ] && [ -f "$REPO_NAME/Dockerfile" ]; then
    DOCKERFILE_PATH="$REPO_NAME/Dockerfile"
    DOCKERFILE_DIR="$REPO_NAME"
    echo "在 $REPO_NAME 目录中找到Dockerfile"
  # 尝试在当前目录的子目录中查找
  elif [ -f "$IMAGE_NAME/Dockerfile" ]; then
    DOCKERFILE_PATH="$IMAGE_NAME/Dockerfile"
    DOCKERFILE_DIR="$IMAGE_NAME"
    echo "在 $IMAGE_NAME 目录中找到Dockerfile"
  else
    echo "错误: 找不到Dockerfile，请确保Dockerfile存在或使用 --dockerfile 选项指定路径"
    echo "尝试查找的位置:"
    echo "  - $DOCKERFILE_PATH"
    echo "  - $REPO_NAME/Dockerfile (如果有GitHub URL)"
    echo "  - $IMAGE_NAME/Dockerfile"
    
    # 如果有GitHub URL但找不到Dockerfile，尝试从GitHub下载
    if [ ! -z "$GITHUB_URL" ] && [ ! -z "$REPO_NAME" ]; then
      echo "本地未找到Dockerfile，尝试克隆整个项目..."
      
      # 创建仓库目录（如果不存在）
      if [ -d "$REPO_NAME" ]; then
        echo "目录 $REPO_NAME 已存在，将先删除..."
        rm -rf "$REPO_NAME"
      fi
      
      echo "克隆仓库 $GITHUB_URL 到 $REPO_NAME 目录..."
      if command -v git &> /dev/null; then
        git clone "$GITHUB_URL" "$REPO_NAME"
        if [ $? -ne 0 ]; then
          echo "错误: 克隆仓库失败"
          exit 1
        fi
        echo "仓库克隆成功!"
      else
        echo "错误: 需要git命令来克隆仓库"
        echo "尝试使用curl下载必要文件..."
        
        # 如果git不可用，尝试使用curl下载
        mkdir -p "$REPO_NAME"
        
        # 构建raw GitHub URL
        RAW_URL="${GITHUB_URL/github.com/raw.githubusercontent.com}"
        RAW_URL="${RAW_URL%.git}/main"
        
        echo "从 $RAW_URL 下载文件..."
        
        # 下载Dockerfile
        if command -v curl &> /dev/null; then
          curl -s -o "$REPO_NAME/Dockerfile" "$RAW_URL/Dockerfile"
        elif command -v wget &> /dev/null; then
          wget -q -O "$REPO_NAME/Dockerfile" "$RAW_URL/Dockerfile"
        else
          echo "错误: 需要curl或wget来下载文件"
          exit 1
        fi
        
        # 检查下载是否成功
        if [ ! -f "$REPO_NAME/Dockerfile" ] || [ ! -s "$REPO_NAME/Dockerfile" ]; then
          echo "错误: Dockerfile下载失败或为空"
          rm -rf "$REPO_NAME"
          exit 1
        fi
        
        # 下载其他常用文件
        for file in package.json package-lock.json docker-compose.yml docker-entrypoint.sh .dockerignore .env.example; do
          if command -v curl &> /dev/null; then
            curl -s -o "$REPO_NAME/$file" "$RAW_URL/$file" || echo "注意: $file 不存在或无法下载"
          elif command -v wget &> /dev/null; then
            wget -q -O "$REPO_NAME/$file" "$RAW_URL/$file" || echo "注意: $file 不存在或无法下载"
          fi
        done
        
        # 创建基本目录结构
        mkdir -p "$REPO_NAME/src" "$REPO_NAME/public" "$REPO_NAME/views" "$REPO_NAME/routes" "$REPO_NAME/models"
        
        # 尝试下载基本目录中的文件
        for dir in src public views routes models; do
          # 尝试下载index文件
          if command -v curl &> /dev/null; then
            curl -s -o "$REPO_NAME/$dir/index.js" "$RAW_URL/$dir/index.js" || echo "注意: $dir/index.js 不存在或无法下载"
          elif command -v wget &> /dev/null; then
            wget -q -O "$REPO_NAME/$dir/index.js" "$RAW_URL/$dir/index.js" || echo "注意: $dir/index.js 不存在或无法下载"
          fi
        done
        
        echo "基本文件下载完成（注意：这不是完整的项目，只包含基本文件）"
      fi
      
      # 检查Dockerfile是否存在
      if [ -f "$REPO_NAME/Dockerfile" ]; then
        DOCKERFILE_PATH="$REPO_NAME/Dockerfile"
        DOCKERFILE_DIR="$REPO_NAME"
        echo "在克隆的仓库中找到Dockerfile: $DOCKERFILE_PATH"
        
        # 确保entrypoint脚本可执行
        if [ -f "$REPO_NAME/docker-entrypoint.sh" ]; then
          chmod +x "$REPO_NAME/docker-entrypoint.sh"
        fi
      else
        echo "错误: 在克隆的仓库中找不到Dockerfile"
        exit 1
      fi
    fi
  fi
fi

# 构建Docker镜像
echo -e "\n===== 步骤1: 构建Docker镜像 ====="
echo "使用Dockerfile: $DOCKERFILE_PATH"
docker build -t $IMAGE_NAME -f "$DOCKERFILE_PATH" "$DOCKERFILE_DIR"
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
  echo "检测到Docker已登录，是否重新登录? (y/n): "
  read -r relogin
  
  if [[ "$relogin" =~ ^[Yy]$ ]]; then
    echo "正在登出当前Docker账号..."
    docker logout
    
    echo "请输入Docker Hub用户名 (默认: $DOCKER_USERNAME): "
    read -r new_username
    if [ ! -z "$new_username" ]; then
      DOCKER_USERNAME="$new_username"
      save_env "DOCKER_USERNAME" "$DOCKER_USERNAME"
    fi
    
    echo "请输入Docker Hub密码: "
    read -rs DOCKER_PASSWORD
    echo # 添加换行
    
    if [ ! -z "$DOCKER_PASSWORD" ]; then
      # 保存密码到.env文件
      save_env "DOCKER_PASSWORD" "$DOCKER_PASSWORD"
      # 使用新密码登录
      echo "使用新凭据登录Docker Hub..."
      echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
    else
      echo "请手动输入Docker Hub密码:"
      docker login -u $DOCKER_USERNAME
    fi
    
    if [ $? -ne 0 ]; then
      echo "错误: 登录Docker Hub失败"
      exit 1
    fi
    echo "登录成功!"
  else
    echo "继续使用当前登录状态..."
  fi
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
push_status=$?

if [ $push_status -ne 0 ]; then
  echo -e "\n错误: 推送镜像失败 (错误码: $push_status)"
  echo "可能的原因:"
  echo "1. Docker Hub登录凭据无效或已过期"
  echo "2. 您没有权限推送到仓库 $DOCKER_USERNAME/$IMAGE_NAME"
  echo "3. 仓库可能不存在，需要先在Docker Hub创建"
  
  echo -e "\n是否尝试重新登录并推送? (y/n): "
  read -r retry_push
  
  if [[ "$retry_push" =~ ^[Yy]$ ]]; then
    echo "正在登出当前Docker账号..."
    docker logout
    
    echo "请输入Docker Hub用户名: "
    read -r DOCKER_USERNAME
    save_env "DOCKER_USERNAME" "$DOCKER_USERNAME"
    
    echo "请输入Docker Hub密码: "
    read -rs DOCKER_PASSWORD
    echo # 添加换行
    
    if [ ! -z "$DOCKER_PASSWORD" ]; then
      save_env "DOCKER_PASSWORD" "$DOCKER_PASSWORD"
    fi
    
    # 重新标记镜像
    echo "重新标记镜像为 $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
    docker tag $IMAGE_NAME $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG
    
    # 重新登录
    echo "重新登录Docker Hub..."
    if [ ! -z "$DOCKER_PASSWORD" ]; then
      echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
    else
      docker login -u $DOCKER_USERNAME
    fi
    
    if [ $? -ne 0 ]; then
      echo "错误: 登录Docker Hub失败"
      exit 1
    fi
    
    # 重新推送
    echo "重新推送镜像..."
    docker push $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG
    
    if [ $? -ne 0 ]; then
      echo "错误: 推送镜像再次失败"
      echo "请检查您是否已在Docker Hub创建了仓库 $DOCKER_USERNAME/$IMAGE_NAME"
      echo "或者尝试手动执行: docker push $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
      exit 1
    fi
  else
    echo "推送失败，退出脚本"
    exit 1
  fi
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

# 删除下载的仓库目录
echo -e "\n===== 步骤6: 清理下载的仓库 ====="
# 检查是否是从GitHub下载的仓库
if [ ! -z "$GITHUB_URL" ] && [ ! -z "$REPO_NAME" ] && [ -d "$REPO_NAME" ] && [ "$DOCKERFILE_DIR" = "$REPO_NAME" ]; then
  echo "正在删除下载的仓库目录: $REPO_NAME"
  rm -rf "$REPO_NAME"
  if [ $? -ne 0 ]; then
    echo "警告: 删除仓库目录失败"
  else
    echo "仓库目录删除成功!"
  fi
fi

echo -e "\n===== 完成! ====="
echo "镜像已成功发布到Docker Hub: $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
echo "您可以使用以下命令拉取此镜像:"
echo "docker pull $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
echo -e "\n如果下载速度较慢，可以使用镜像代理加速:"
echo "docker pull $DOCKER_PROXY/$DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"

# 获取脚本的真实路径
REAL_SCRIPT_PATH="./docker-publish.sh"
if [ -f "$SCRIPT_NAME" ]; then
  REAL_SCRIPT_PATH="./$SCRIPT_NAME"
fi

echo -e "\n下次运行只需执行: $REAL_SCRIPT_PATH"
EOF
    chmod +x "$SCRIPT_NAME"
    echo "脚本已保存为 $SCRIPT_NAME 并设置为可执行"
    echo "下次可以直接运行 ./$SCRIPT_NAME"
    echo "现在继续执行..."
    echo "========================================================"
  fi
fi

# 显示欢迎信息
echo "========================================================"
echo "  Docker镜像构建与发布脚本 v1.0"
echo "  来源: https://github.com/rdone4425/docker"
echo "========================================================"
echo ""

# 配置信息
ENV_FILE=".env"
IMAGE_TAG="latest"
DOCKERFILE_PATH="./Dockerfile"
DOCKERFILE_DIR="."
DOCKER_PROXY=""

# 调试信息函数
debug_info() {
  echo -e "\n[调试信息] $1"
}

# 从Git仓库获取仓库名
get_repo_name() {
  # 检查是否在Git仓库中
  if ! command -v git &> /dev/null || ! git rev-parse --is-inside-work-tree &> /dev/null 2>/dev/null; then
    # 尝试获取当前目录名作为仓库名
    local dir_name=$(basename "$(pwd)")
    echo "$dir_name"
    return
  fi
  
  # 获取远程仓库URL
  local remote_url=$(git config --get remote.origin.url 2>/dev/null)
  
  if [ -z "$remote_url" ]; then
    # 使用当前目录名作为仓库名
    local dir_name=$(basename "$(pwd)")
    echo "$dir_name"
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
  echo "用法: $0 [选项]"
  echo "选项:"
  echo "  -u, --username USERNAME   指定Docker Hub用户名"
  echo "  -t, --tag TAG             指定镜像标签 (默认: latest)"
  echo "  -n, --name NAME           指定镜像名称 (默认: 从当前目录名或GitHub仓库名获取)"
  echo "  -g, --github-url URL      指定GitHub仓库URL"
  echo "  -f, --force               强制重新输入所有信息"
  echo "  -d, --dockerfile PATH     指定Dockerfile路径"
  echo "  -p, --proxy PROXY         指定Docker镜像代理地址"
  echo "  -h, --help                显示此帮助信息"
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
DOCKER_PROXY=${DOCKER_PROXY:-""}

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
    -d|--dockerfile)
      DOCKERFILE_PATH="$2"
      DOCKERFILE_DIR=$(dirname "$DOCKERFILE_PATH")
      shift
      shift
      ;;
    -p|--proxy)
      DOCKER_PROXY="$2"
      save_env "DOCKER_PROXY" "$DOCKER_PROXY"
      shift
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
  echo "========================================================"
  echo "请输入您的Docker Hub用户名: "
  read -r DOCKER_USERNAME
  
if [ -z "$DOCKER_USERNAME" ]; then
    echo "错误: 用户名不能为空"
  exit 1
fi
  
  # 保存用户名到.env文件
  save_env "DOCKER_USERNAME" "$DOCKER_USERNAME"
  
  # 提示输入Docker Hub密码
  echo "请输入您的Docker Hub密码 (将保存到.env文件): "
  read -rs DOCKER_PASSWORD
  echo # 添加换行
  
  if [ ! -z "$DOCKER_PASSWORD" ]; then
    # 保存密码到.env文件
    save_env "DOCKER_PASSWORD" "$DOCKER_PASSWORD"
    echo "Docker Hub密码已保存"
  else
    echo "警告: 未提供Docker Hub密码，登录时可能需要手动输入"
  fi
  
  # 提示输入Docker镜像代理地址
  echo "请输入Docker镜像代理地址 (留空则不使用代理): "
  read -r input_proxy
  
  if [ ! -z "$input_proxy" ]; then
    DOCKER_PROXY="$input_proxy"
  fi
  
  # 保存代理地址到.env文件
  save_env "DOCKER_PROXY" "$DOCKER_PROXY"
  if [ ! -z "$DOCKER_PROXY" ]; then
    echo "Docker镜像代理地址已设置为: $DOCKER_PROXY"
  else
    echo "未设置Docker镜像代理地址"
  fi
else
  # 显示当前Docker账号信息
  echo "========================================================"
  echo "当前Docker账号: $DOCKER_USERNAME"
  echo "是否切换到其他Docker账号? (y/n): "
  read -r switch_account
  
  if [[ "$switch_account" =~ ^[Yy]$ ]]; then
    echo "请输入新的Docker Hub用户名: "
    read -r DOCKER_USERNAME
    
    if [ -z "$DOCKER_USERNAME" ]; then
      echo "错误: 用户名不能为空"
      exit 1
    fi
    
    # 保存新用户名到.env文件
    save_env "DOCKER_USERNAME" "$DOCKER_USERNAME"
    
    # 提示输入新Docker Hub密码
    echo "请输入新的Docker Hub密码 (将保存到.env文件): "
    read -rs DOCKER_PASSWORD
    echo # 添加换行
    
    if [ ! -z "$DOCKER_PASSWORD" ]; then
      # 保存新密码到.env文件
      save_env "DOCKER_PASSWORD" "$DOCKER_PASSWORD"
      echo "新的Docker Hub密码已保存"
    else
      echo "警告: 未提供Docker Hub密码，登录时可能需要手动输入"
    fi
    
    # 确保登出当前账号
    echo "正在登出当前Docker账号..."
    docker logout
    
    # 提示输入Docker镜像代理地址
    echo "是否需要修改Docker镜像代理地址? (y/n): "
    read -r change_proxy
    
    if [[ "$change_proxy" =~ ^[Yy]$ ]]; then
      echo "当前Docker镜像代理地址: $DOCKER_PROXY"
      echo "请输入新的Docker镜像代理地址 (留空则不使用代理): "
      read -r input_proxy
      
      DOCKER_PROXY="$input_proxy"
      
      # 保存代理地址到.env文件
      save_env "DOCKER_PROXY" "$DOCKER_PROXY"
      if [ ! -z "$DOCKER_PROXY" ]; then
        echo "Docker镜像代理地址已设置为: $DOCKER_PROXY"
      else
        echo "未设置Docker镜像代理地址"
      fi
    fi
  fi
fi

# 如果GitHub URL为空或强制输入，则提示输入
if [ -z "$GITHUB_URL" ] || [ "$FORCE_INPUT" = true ]; then
  echo "========================================================"
  echo "请输入GitHub仓库URL (https://github.com/user/repo.git): "
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
      echo "是否使用 '$gh_repo' 作为镜像名? (y/n): "
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

# 检查Dockerfile是否存在
if [ ! -f "$DOCKERFILE_PATH" ]; then
  # 从GitHub URL中提取仓库名
  REPO_NAME=""
  if [ ! -z "$GITHUB_URL" ]; then
    read -r gh_user gh_repo <<< "$(extract_from_github_url "$GITHUB_URL")"
    if [ ! -z "$gh_repo" ]; then
      REPO_NAME="$gh_repo"
    fi
  fi
  
  # 如果有仓库名，尝试在该目录中查找Dockerfile
  if [ ! -z "$REPO_NAME" ] && [ -f "$REPO_NAME/Dockerfile" ]; then
    DOCKERFILE_PATH="$REPO_NAME/Dockerfile"
    DOCKERFILE_DIR="$REPO_NAME"
    echo "在 $REPO_NAME 目录中找到Dockerfile"
  # 尝试在当前目录的子目录中查找
  elif [ -f "$IMAGE_NAME/Dockerfile" ]; then
    DOCKERFILE_PATH="$IMAGE_NAME/Dockerfile"
    DOCKERFILE_DIR="$IMAGE_NAME"
    echo "在 $IMAGE_NAME 目录中找到Dockerfile"
  else
    echo "错误: 找不到Dockerfile，请确保Dockerfile存在或使用 --dockerfile 选项指定路径"
    echo "尝试查找的位置:"
    echo "  - $DOCKERFILE_PATH"
    echo "  - $REPO_NAME/Dockerfile (如果有GitHub URL)"
    echo "  - $IMAGE_NAME/Dockerfile"
    
    # 如果有GitHub URL但找不到Dockerfile，尝试从GitHub下载
    if [ ! -z "$GITHUB_URL" ] && [ ! -z "$REPO_NAME" ]; then
      echo "本地未找到Dockerfile，尝试克隆整个项目..."
      
      # 创建仓库目录（如果不存在）
      if [ -d "$REPO_NAME" ]; then
        echo "目录 $REPO_NAME 已存在，将先删除..."
        rm -rf "$REPO_NAME"
      fi
      
      echo "克隆仓库 $GITHUB_URL 到 $REPO_NAME 目录..."
      if command -v git &> /dev/null; then
        git clone "$GITHUB_URL" "$REPO_NAME"
        if [ $? -ne 0 ]; then
          echo "错误: 克隆仓库失败"
          exit 1
        fi
        echo "仓库克隆成功!"
      else
        echo "错误: 需要git命令来克隆仓库"
        echo "尝试使用curl下载必要文件..."
        
        # 如果git不可用，尝试使用curl下载
        mkdir -p "$REPO_NAME"
        
        # 构建raw GitHub URL
        RAW_URL="${GITHUB_URL/github.com/raw.githubusercontent.com}"
        RAW_URL="${RAW_URL%.git}/main"
        
        echo "从 $RAW_URL 下载文件..."
        
        # 下载Dockerfile
        if command -v curl &> /dev/null; then
          curl -s -o "$REPO_NAME/Dockerfile" "$RAW_URL/Dockerfile"
        elif command -v wget &> /dev/null; then
          wget -q -O "$REPO_NAME/Dockerfile" "$RAW_URL/Dockerfile"
        else
          echo "错误: 需要curl或wget来下载文件"
          exit 1
        fi
        
        # 检查下载是否成功
        if [ ! -f "$REPO_NAME/Dockerfile" ] || [ ! -s "$REPO_NAME/Dockerfile" ]; then
          echo "错误: Dockerfile下载失败或为空"
          rm -rf "$REPO_NAME"
          exit 1
        fi
        
        # 下载其他常用文件
        for file in package.json package-lock.json docker-compose.yml docker-entrypoint.sh .dockerignore .env.example; do
          if command -v curl &> /dev/null; then
            curl -s -o "$REPO_NAME/$file" "$RAW_URL/$file" || echo "注意: $file 不存在或无法下载"
          elif command -v wget &> /dev/null; then
            wget -q -O "$REPO_NAME/$file" "$RAW_URL/$file" || echo "注意: $file 不存在或无法下载"
          fi
        done
        
        # 创建基本目录结构
        mkdir -p "$REPO_NAME/src" "$REPO_NAME/public" "$REPO_NAME/views" "$REPO_NAME/routes" "$REPO_NAME/models"
        
        # 尝试下载基本目录中的文件
        for dir in src public views routes models; do
          # 尝试下载index文件
          if command -v curl &> /dev/null; then
            curl -s -o "$REPO_NAME/$dir/index.js" "$RAW_URL/$dir/index.js" || echo "注意: $dir/index.js 不存在或无法下载"
          elif command -v wget &> /dev/null; then
            wget -q -O "$REPO_NAME/$dir/index.js" "$RAW_URL/$dir/index.js" || echo "注意: $dir/index.js 不存在或无法下载"
          fi
        done
        
        echo "基本文件下载完成（注意：这不是完整的项目，只包含基本文件）"
      fi
      
      # 检查Dockerfile是否存在
      if [ -f "$REPO_NAME/Dockerfile" ]; then
        DOCKERFILE_PATH="$REPO_NAME/Dockerfile"
        DOCKERFILE_DIR="$REPO_NAME"
        echo "在克隆的仓库中找到Dockerfile: $DOCKERFILE_PATH"
        
        # 确保entrypoint脚本可执行
        if [ -f "$REPO_NAME/docker-entrypoint.sh" ]; then
          chmod +x "$REPO_NAME/docker-entrypoint.sh"
        fi
      else
        echo "错误: 在克隆的仓库中找不到Dockerfile"
        exit 1
      fi
    fi
  fi
fi

# 构建Docker镜像
echo -e "\n===== 步骤1: 构建Docker镜像 ====="
echo "使用Dockerfile: $DOCKERFILE_PATH"
docker build -t $IMAGE_NAME -f "$DOCKERFILE_PATH" "$DOCKERFILE_DIR"
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
  echo "检测到Docker已登录，是否重新登录? (y/n): "
  read -r relogin
  
  if [[ "$relogin" =~ ^[Yy]$ ]]; then
    echo "正在登出当前Docker账号..."
    docker logout
    
    echo "请输入Docker Hub用户名 (默认: $DOCKER_USERNAME): "
    read -r new_username
    if [ ! -z "$new_username" ]; then
      DOCKER_USERNAME="$new_username"
      save_env "DOCKER_USERNAME" "$DOCKER_USERNAME"
    fi
    
    echo "请输入Docker Hub密码: "
    read -rs DOCKER_PASSWORD
    echo # 添加换行
    
    if [ ! -z "$DOCKER_PASSWORD" ]; then
      # 保存密码到.env文件
      save_env "DOCKER_PASSWORD" "$DOCKER_PASSWORD"
      # 使用新密码登录
      echo "使用新凭据登录Docker Hub..."
      echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
    else
      echo "请手动输入Docker Hub密码:"
      docker login -u $DOCKER_USERNAME
    fi
    
    if [ $? -ne 0 ]; then
      echo "错误: 登录Docker Hub失败"
      exit 1
    fi
    echo "登录成功!"
  else
    echo "继续使用当前登录状态..."
  fi
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
push_status=$?

if [ $push_status -ne 0 ]; then
  echo -e "\n错误: 推送镜像失败 (错误码: $push_status)"
  echo "可能的原因:"
  echo "1. Docker Hub登录凭据无效或已过期"
  echo "2. 您没有权限推送到仓库 $DOCKER_USERNAME/$IMAGE_NAME"
  echo "3. 仓库可能不存在，需要先在Docker Hub创建"
  
  echo -e "\n是否尝试重新登录并推送? (y/n): "
  read -r retry_push
  
  if [[ "$retry_push" =~ ^[Yy]$ ]]; then
    echo "正在登出当前Docker账号..."
    docker logout
    
    echo "请输入Docker Hub用户名: "
    read -r DOCKER_USERNAME
    save_env "DOCKER_USERNAME" "$DOCKER_USERNAME"
    
    echo "请输入Docker Hub密码: "
    read -rs DOCKER_PASSWORD
    echo # 添加换行
    
    if [ ! -z "$DOCKER_PASSWORD" ]; then
      save_env "DOCKER_PASSWORD" "$DOCKER_PASSWORD"
    fi
    
    # 重新标记镜像
    echo "重新标记镜像为 $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
    docker tag $IMAGE_NAME $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG
    
    # 重新登录
    echo "重新登录Docker Hub..."
    if [ ! -z "$DOCKER_PASSWORD" ]; then
      echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
    else
      docker login -u $DOCKER_USERNAME
    fi
    
    if [ $? -ne 0 ]; then
      echo "错误: 登录Docker Hub失败"
      exit 1
    fi
    
    # 重新推送
    echo "重新推送镜像..."
    docker push $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG
    
    if [ $? -ne 0 ]; then
      echo "错误: 推送镜像再次失败"
      echo "请检查您是否已在Docker Hub创建了仓库 $DOCKER_USERNAME/$IMAGE_NAME"
      echo "或者尝试手动执行: docker push $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
      exit 1
    fi
  else
    echo "推送失败，退出脚本"
    exit 1
  fi
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

# 删除下载的仓库目录
echo -e "\n===== 步骤6: 清理下载的仓库 ====="
# 检查是否是从GitHub下载的仓库
if [ ! -z "$GITHUB_URL" ] && [ ! -z "$REPO_NAME" ] && [ -d "$REPO_NAME" ] && [ "$DOCKERFILE_DIR" = "$REPO_NAME" ]; then
  echo "正在删除下载的仓库目录: $REPO_NAME"
  rm -rf "$REPO_NAME"
  if [ $? -ne 0 ]; then
    echo "警告: 删除仓库目录失败"
  else
    echo "仓库目录删除成功!"
  fi
fi

echo -e "\n===== 完成! ====="
echo "镜像已成功发布到Docker Hub: $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
echo "您可以使用以下命令拉取此镜像:"
echo "docker pull $DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
echo -e "\n如果下载速度较慢，可以使用镜像代理加速:"
echo "docker pull $DOCKER_PROXY/$DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"

# 获取脚本的真实路径
REAL_SCRIPT_PATH="./docker-publish.sh"
if [ -f "$SCRIPT_NAME" ]; then
  REAL_SCRIPT_PATH="./$SCRIPT_NAME"
fi

echo -e "\n下次运行只需执行: $REAL_SCRIPT_PATH" 