#!/bin/bash

CONFIG_FILE=".docker_config"
VERSION_FILE=".version_config"
REGISTRY_FILE=".registry_config"
HISTORY_FILE=".build_history"

# 默认镜像仓库
PROXY_REGISTRY="docker.442595.xyz"
# 官方仓库
OFFICIAL_REGISTRY="docker.io"
# 默认初始版本号
DEFAULT_VERSION="0.01"
# 可选的加速镜像仓库列表
REGISTRY_OPTIONS=(
  "docker.fxxk.dedyn.io"
  "docker.442595.xyz"
  "registry.cn-hangzhou.aliyuncs.com"
  "registry.cn-beijing.aliyuncs.com"
  "registry.cn-shanghai.aliyuncs.com"
  "registry.cn-shenzhen.aliyuncs.com"
  "registry.cn-qingdao.aliyuncs.com"
  "registry.cn-hongkong.aliyuncs.com"
  "docker.mirrors.ustc.edu.cn"
)

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    if [ -f "$REGISTRY_FILE" ]; then
        source "$REGISTRY_FILE"
    fi
}

save_config() {
    echo "DOCKER_USER=\"$DOCKER_USER\"" > "$CONFIG_FILE"
    echo "DOCKER_PASS=\"$DOCKER_PASS\"" >> "$CONFIG_FILE"
}

save_registry() {
    echo "PROXY_REGISTRY=\"$PROXY_REGISTRY\"" > "$REGISTRY_FILE"
}

get_version() {
    if [ -f "$VERSION_FILE" ]; then
        VERSION=$(cat "$VERSION_FILE")
    else
        VERSION="$DEFAULT_VERSION"
        echo "$VERSION" > "$VERSION_FILE"
    fi
}

set_version() {
    get_version
    echo "当前版本号为：$VERSION"
    read -p "请输入新的版本号（如 0.01），留空则不修改: " input_version
    if [[ "$input_version" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        VERSION="$input_version"
        echo "$VERSION" > "$VERSION_FILE"
        echo "版本号已设置为：$VERSION"
    elif [ -z "$input_version" ]; then
        echo "版本号未修改。"
    else
        echo "输入格式有误，版本号未修改。"
    fi
}

inc_version() {
    VERSION=$(awk "BEGIN {printf \"%.2f\", $VERSION + 0.01}")
    echo "$VERSION" > "$VERSION_FILE"
}

select_registry() {
    echo "请选择代理镜像仓库："
    echo "0. 自定义镜像仓库"
    for i in "${!REGISTRY_OPTIONS[@]}"; do
        idx=$((i+1))
        echo "$idx. ${REGISTRY_OPTIONS[$i]}"
    done
    
    read -p "请输入选项 (1-${#REGISTRY_OPTIONS[@]}, 0 自定义): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if [ "$choice" -eq 0 ]; then
            read -p "请输入自定义代理镜像仓库地址: " custom_registry
            if [ -n "$custom_registry" ]; then
                PROXY_REGISTRY="$custom_registry"
                echo "已设置代理镜像仓库为：$PROXY_REGISTRY"
            else
                echo "输入为空，未修改代理镜像仓库。"
                return
            fi
        elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#REGISTRY_OPTIONS[@]}" ]; then
            PROXY_REGISTRY="${REGISTRY_OPTIONS[$((choice-1))]}"
            echo "已设置代理镜像仓库为：$PROXY_REGISTRY"
        else
            echo "无效选项，未修改代理镜像仓库。"
            return
        fi
        save_registry
    else
        echo "无效输入，未修改代理镜像仓库。"
    fi
}

set_proxy_registry() {
    echo "当前代理镜像仓库地址为：${PROXY_REGISTRY}"
    echo "1. 从列表选择镜像仓库"
    echo "2. 手动输入镜像仓库地址"
    echo "3. 测试镜像仓库速度"
    echo "4. 返回上级菜单"
    read -p "请选择操作 (1-4): " option
    
    case $option in
        1)
            select_registry
            ;;
        2)
            read -p "请输入新的代理镜像仓库地址（如 registry.cn-hangzhou.aliyuncs.com），留空则不修改: " input_registry
            if [ -n "$input_registry" ]; then
                PROXY_REGISTRY="$input_registry"
                echo "已设置代理镜像仓库为：$PROXY_REGISTRY"
                save_registry
            else
                echo "未修改代理镜像仓库。"
            fi
            ;;
        3)
            test_registry_speed
            ;;
        4)
            return
            ;;
        *)
            echo "无效选项，未修改代理镜像仓库。"
            ;;
    esac
}

test_registry_speed() {
    echo "开始测试各镜像仓库速度..."
    echo "将下载一个小镜像(hello-world)来测试速度，请稍候..."
    
    # 确保先清理本地的hello-world镜像
    docker rmi hello-world:latest &>/dev/null
    
    # 测试结果存储
    declare -A results
    
    # 测试官方仓库
    echo "测试官方仓库 (docker.io)..."
    start=$(date +%s.%N)
    docker pull hello-world &>/dev/null
    end=$(date +%s.%N)
    duration=$(echo "$end - $start" | bc)
    results["docker.io"]=$duration
    docker rmi hello-world:latest &>/dev/null
    echo "docker.io: $duration 秒"
    
    # 测试每个镜像仓库
    for registry in "${REGISTRY_OPTIONS[@]}"; do
        echo "测试 $registry..."
        start=$(date +%s.%N)
        # 尝试从镜像仓库拉取
        if docker pull $registry/library/hello-world:latest &>/dev/null; then
            end=$(date +%s.%N)
            duration=$(echo "$end - $start" | bc)
            results["$registry"]=$duration
            echo "$registry: $duration 秒"
        else
            echo "$registry: 拉取失败，可能不支持此镜像"
            results["$registry"]="失败"
        fi
        docker rmi $registry/library/hello-world:latest &>/dev/null
    done
    
    # 显示结果
    echo -e "\n速度测试结果 (按速度排序):"
    echo "========================================"
    echo "镜像仓库                         | 时间(秒)"
    echo "----------------------------------------"
    
    # 过滤出成功的结果并排序
    successful_results=()
    successful_registries=()
    for registry in "${!results[@]}"; do
        if [[ "${results[$registry]}" != "失败" ]]; then
            successful_results+=("$registry ${results[$registry]}")
            successful_registries+=("$registry")
        fi
    done
    
    # 排序并显示
    index=1
    sorted_registries=()
    if [ ${#successful_results[@]} -gt 0 ]; then
        printf '%s\n' "${successful_results[@]}" | sort -k2 -n | while read -r line; do
            registry=$(echo $line | cut -d' ' -f1)
            time=$(echo $line | cut -d' ' -f2)
            printf "%-3s %-35s | %s\n" "$index." "$registry" "$time"
            sorted_registries[$index]=$registry
            ((index++))
        done > /tmp/registry_speeds
        cat /tmp/registry_speeds
    fi
    echo "========================================"
    
    # 从文件加载排序后的镜像仓库列表
    sorted_registries=()
    while read -r line; do
        idx=$(echo $line | cut -d' ' -f1 | tr -d '.')
        registry=$(echo $line | cut -d' ' -f2)
        sorted_registries[$idx]=$registry
    done < /tmp/registry_speeds
    
    # 让用户从列表中选择
    echo -e "\n请选择您想使用的镜像仓库:"
    echo "0. 取消，不修改当前设置"
    
    # 获取最快的仓库
    fastest_registry=${sorted_registries[1]}
    
    # 输出提示信息
    if [ -n "$fastest_registry" ]; then
        echo -e "* 最快的镜像仓库是: \033[1;32m$fastest_registry\033[0m"
    fi
    
    read -p "请输入选项 (0-${#sorted_registries[@]}): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if [ "$choice" -eq 0 ]; then
            echo "保持当前设置不变"
        elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#sorted_registries[@]}" ]; then
            selected_registry=${sorted_registries[$choice]}
            if [ -n "$selected_registry" ]; then
                PROXY_REGISTRY="$selected_registry"
                save_registry
                echo "已将代理镜像仓库设置为：$PROXY_REGISTRY"
            fi
        else
            echo "无效选项，未修改代理镜像仓库。"
        fi
    else
        echo "无效输入，未修改代理镜像仓库。"
    fi
    
    # 清理临时文件
    rm -f /tmp/registry_speeds
}

login() {
    load_config
    if [ -n "$DOCKER_USER" ] && [ -n "$DOCKER_PASS" ]; then
        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
        if [ $? -ne 0 ]; then
            echo "Docker 登录失败，请检查账号或密码。"
            LOGIN_STATUS=0
        else
            echo "Docker 登录成功。"
            LOGIN_STATUS=1
        fi
    else
        read -p "请输入Docker仓库账号: " DOCKER_USER
        read -s -p "请输入Docker仓库密码: " DOCKER_PASS
        echo
        save_config
        login
    fi
}

build_and_push() {
    load_config
    get_version
    login
    if [ "$LOGIN_STATUS" != "1" ]; then
        echo "登录失败，无法继续。"
        return
    fi
    read -p "请输入GitHub仓库地址（例如 https://github.com/yourname/yourrepo.git）: " GIT_URL
    REPO_NAME=$(basename -s .git "$GIT_URL")
    
    # 检查当前版本是否可用，如果不可用则自动增加版本号
    check_version_available() {
        local current_version=$1
        local repo_name=$2
        local full_image_name="$DOCKER_USER/$repo_name:$current_version"
        
        echo "检查版本 $current_version 是否可用..."
        # 尝试拉取镜像，如果能拉取到说明版本已存在
        if docker pull "$full_image_name" &>/dev/null; then
            echo "发现版本 $current_version 已存在，自动增加版本号..."
            VERSION=$(awk "BEGIN {printf \"%.2f\", $current_version + 0.01}")
            echo "$VERSION" > "$VERSION_FILE"
            echo "版本号已更新为：$VERSION"
            # 递归检查新版本是否可用
            check_version_available "$VERSION" "$repo_name"
        else
            echo "版本 $current_version 可用，将使用此版本进行构建。"
        fi
    }
    
    # 调用检查函数
    check_version_available "$VERSION" "$REPO_NAME"
    
    if [ -d "$REPO_NAME" ]; then
        echo "本地已存在 $REPO_NAME 目录，先删除旧目录。"
        rm -rf "$REPO_NAME"
    fi
    git clone "$GIT_URL"
    if [ $? -ne 0 ]; then
        echo "GitHub 仓库下载失败！"
        return
    fi
    cd "$REPO_NAME"
    IMAGE_NAME="$REPO_NAME:$VERSION"
    docker buildx build --platform linux/amd64,linux/arm64 -t "$IMAGE_NAME" --push .
    if [ $? -ne 0 ]; then
        echo "镜像构建失败！"
        cd ..
        rm -rf "$REPO_NAME"
        return
    fi
    # 官方镜像名称
    OFFICIAL_IMAGE_NAME="$DOCKER_USER/$REPO_NAME:$VERSION"
    # 代理镜像名称
    PROXY_IMAGE_NAME="$PROXY_REGISTRY/$DOCKER_USER/$REPO_NAME:$VERSION"
    
    # 标记和推送到官方仓库
    docker tag "$IMAGE_NAME" "$OFFICIAL_IMAGE_NAME"
    echo "正在推送镜像到官方Docker Hub..."
    docker push "$OFFICIAL_IMAGE_NAME"
    
    if [ $? -eq 0 ]; then
        echo "镜像上传成功：$OFFICIAL_IMAGE_NAME"
        echo "同时标记为代理仓库镜像：$PROXY_IMAGE_NAME"
        docker tag "$IMAGE_NAME" "$PROXY_IMAGE_NAME"
        
        # 记录构建历史
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        echo "$timestamp|$GIT_URL|$OFFICIAL_IMAGE_NAME|$PROXY_IMAGE_NAME" >> "$HISTORY_FILE"
        
        echo ""
        echo "====================== 拉取命令 ======================"
        echo -e "\033[1;32m通过代理仓库拉取: \033[1;36mdocker pull $PROXY_IMAGE_NAME\033[0m"
        echo -e "\033[1;33m通过官方仓库拉取: \033[1;36mdocker pull $OFFICIAL_IMAGE_NAME\033[0m"
        echo "======================================================"
        echo ""
        echo "====================== 运行命令 ======================"
        echo -e "\033[1;32m运行容器: \033[1;36mdocker run -d --name $REPO_NAME $PROXY_IMAGE_NAME\033[0m"
        echo "======================================================"
        echo ""
        
        inc_version
    else
        echo "镜像上传失败！"
    fi
    cd ..
    echo "正在删除本地仓库目录 $REPO_NAME ..."
    rm -rf "$REPO_NAME"
    echo "正在删除本地镜像..."
    docker rmi "$IMAGE_NAME"
    docker rmi "$OFFICIAL_IMAGE_NAME"
    if docker image inspect "$PROXY_IMAGE_NAME" &>/dev/null; then
        docker rmi "$PROXY_IMAGE_NAME"
    fi
}

show_build_history() {
    if [ ! -f "$HISTORY_FILE" ] || [ ! -s "$HISTORY_FILE" ]; then
        echo "尚无构建历史记录。"
        return
    fi
    
    echo "===================== 构建历史记录 ====================="
    echo "序号 | 构建时间           | 仓库名称 | 版本  | GitHub 仓库"
    echo "----------------------------------------------------------"
    
    # 展示最近的20条记录
    count=1
    tac "$HISTORY_FILE" | head -20 | while IFS='|' read -r timestamp git_url official_image proxy_image; do
        # 提取仓库名和版本号
        repo_name=$(echo "$official_image" | cut -d'/' -f2 | cut -d':' -f1)
        version=$(echo "$official_image" | cut -d':' -f2)
        
        printf "%-4s | %-19s | %-8s | %-5s | %s\n" "$count" "$timestamp" "$repo_name" "$version" "$git_url"
        count=$((count+1))
    done
    
    echo "----------------------------------------------------------"
    echo "选择操作:"
    echo "1. 查看特定记录的详细信息和拉取命令"
    echo "2. 返回主菜单"
    read -p "请输入选项 (1-2): " choice
    
    if [ "$choice" = "1" ]; then
        read -p "请输入要查看详细信息的记录序号: " record_num
        if [[ "$record_num" =~ ^[0-9]+$ ]] && [ "$record_num" -ge 1 ]; then
            # 获取对应记录的信息
            record=$(tac "$HISTORY_FILE" | head -20 | sed -n "${record_num}p")
            if [ -n "$record" ]; then
                IFS='|' read -r timestamp git_url official_image proxy_image <<< "$record"
                echo ""
                echo "构建时间: $timestamp"
                echo "GitHub 仓库: $git_url"
                echo ""
                echo "====================== 拉取命令 ======================"
                echo -e "\033[1;32m通过代理仓库拉取: \033[1;36mdocker pull $proxy_image\033[0m"
                echo -e "\033[1;33m通过官方仓库拉取: \033[1;36mdocker pull $official_image\033[0m"
                echo "======================================================"
                echo ""
                
                # 提取仓库名用于运行命令
                repo_name=$(echo "$official_image" | cut -d'/' -f2 | cut -d':' -f1)
                
                echo "====================== 运行命令 ======================"
                echo -e "\033[1;32m运行容器: \033[1;36mdocker run -d --name $repo_name $proxy_image\033[0m"
                echo "======================================================"
                echo ""
            else
                echo "未找到该记录。"
            fi
        else
            echo "无效的序号。"
        fi
    fi
}

check_docker_user() {
    load_config
    if [ -z "$DOCKER_USER" ]; then
        echo "请先登录Docker仓库（选项1）"
        return 1
    fi
    return 0
}

LOGIN_STATUS=0
REPO_NAME=""

while true; do
    get_version
    load_config
    echo "请选择操作："
    echo "1. 登录镜像仓库"
    echo "2. 从GitHub下载、构建并上传镜像（自动清理，自动递增版本号）"
    echo "3. 设置版本号（当前：$VERSION）"
    echo "4. 镜像仓库设置（当前：$PROXY_REGISTRY）"
    echo "5. 构建历史与拉取命令"
    echo "6. 退出"
    read -p "请输入选项(1/2/3/4/5/6): " choice

    case $choice in
        1)
            login
            ;;
        2)
            build_and_push
            ;;
        3)
            set_version
            ;;
        4)
            set_proxy_registry
            ;;
        5)
            show_build_history
            ;;
        6)
            echo "退出程序。"
            docker logout
            break
            ;;
        *)
            echo "无效选项，请重新输入。"
            ;;
    esac
done
