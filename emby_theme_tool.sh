#!/bin/bash

# ====================================================
# Emby CRX Theme 工具箱 (终极修复版)
# ====================================================

# 终端输出颜色
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

# 核心文件名列表
FILES=("common-utils.js" "jquery-3.6.0.min.js" "md5.min.js" "style.css" "main.js")

echo -e "${GREEN}=====================================${RESET}"
echo -e "${GREEN}    Emby CRX Theme 工具箱脚本        ${RESET}"
echo -e "${GREEN}=====================================${RESET}"

# --- 通用函数：获取环境信息 ---
get_env_info() {
    echo "请选择您的 Emby 安装环境："
    echo "  1) Docker 容器版 (推荐)"
    echo "  2) 群晖套件版 / 物理机原生版"
    read -p "请输入序号 (1-2, 默认 1): " ENV_CHOICE
    ENV_CHOICE=${ENV_CHOICE:-1}

    if [ "$ENV_CHOICE" == "1" ]; then
        read -p "请输入 Emby 容器名称 (默认: emby): " CONTAINER_NAME
        CONTAINER_NAME=${CONTAINER_NAME:-emby}
        
        # 检查容器状态
        if ! docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
            echo -e "${RED}[错误] 找不到正在运行的容器: ${CONTAINER_NAME}${RESET}"
            exit 1
        fi

        echo -e "${YELLOW}正在定位 dashboard-ui 目录...${RESET}"
        UI_PATH=""
        # 优先检测常见的几个标准路径
        for p in "/system/dashboard-ui" "/app/emby/system/dashboard-ui" "/usr/emby/system/dashboard-ui"; do
            if docker exec "$CONTAINER_NAME" test -f "$p/index.html"; then 
                UI_PATH="$p"
                break
            fi
        done
        
        # 如果找不到，再用全盘搜索
        if [ -z "$UI_PATH" ]; then
            UI_PATH=$(docker exec "$CONTAINER_NAME" find / -maxdepth 5 -type d -name "dashboard-ui" 2>/dev/null | head -n 1)
        fi

        if [ -z "$UI_PATH" ]; then
            echo -e "${RED}[错误] 无法定位容器内 dashboard-ui 目录${RESET}"
            exit 1
        fi
        echo -e "${GREEN}[成功] 找到目录: $UI_PATH${RESET}"
    else
        read -p "请输入 dashboard-ui 目录绝对路径: " PHYSICAL_DIR
        PHYSICAL_DIR="${PHYSICAL_DIR%/}"
        if [ ! -f "$PHYSICAL_DIR/index.html" ]; then
            echo -e "${RED}[错误] 路径无效或 index.html 不存在${RESET}"
            exit 1
        fi
    fi
}

# --- 功能：执行安装 ---
do_install() {
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit

    echo -e "${YELLOW}正在下载源码...${RESET}"
    if command -v curl &> /dev/null; then
        curl -sL -o emby-crx.zip https://github.com/Nolovenodie/emby-crx/archive/refs/heads/master.zip
    else
        wget -qO emby-crx.zip https://github.com/Nolovenodie/emby-crx/archive/refs/heads/master.zip
    fi
    
    # 解压文件 (-o 表示覆盖不提示)
    unzip -o -q -j emby-crx.zip "emby-crx-master/common-utils.js" "emby-crx-master/jquery-3.6.0.min.js" "emby-crx-master/md5.min.js" "emby-crx-master/style.css" "emby-crx-master/main.js"

    if [ "$ENV_CHOICE" == "1" ]; then
        # Docker 安装逻辑
        echo -e "${YELLOW}正在将文件部署到容器并修复权限...${RESET}"
        for file in "${FILES[@]}"; do
            docker cp "$file" "${CONTAINER_NAME}:${UI_PATH}/"
            # 强制赋予 755 权限，解决 403 拒绝访问问题
            docker exec "$CONTAINER_NAME" chmod 755 "${UI_PATH}/$file"
        done

        docker cp "${CONTAINER_NAME}:${UI_PATH}/index.html" ./index.html
        
        # 使用 AWK 注入代码 (最稳定的跨平台做法)
        if ! grep -q 'id="theme-css"' ./index.html; then
            echo -e "${YELLOW}正在注入代码...${RESET}"
            awk '/<\/head>/{print "    <link rel=\"stylesheet\" id=\"theme-css\" href=\"style.css\" type=\"text/css\" media=\"all\" />\n    <script src=\"common-utils.js\"></script>\n    <script src=\"jquery-3.6.0.min.js\"></script>\n    <script src=\"md5.min.js\"></script>\n    <script src=\"main.js\"></script>"}1' ./index.html > ./index.html.tmp
            mv ./index.html.tmp ./index.html
            docker cp ./index.html "${CONTAINER_NAME}:${UI_PATH}/index.html"
            docker exec "$CONTAINER_NAME" chmod 644 "${UI_PATH}/index.html"
        else
            echo -e "${GREEN}[提示] 页面已经注入过代码，跳过注入。${RESET}"
        fi

        echo -e "${YELLOW}正在重启 Emby 容器以清理缓存 (重要)...${RESET}"
        docker restart "$CONTAINER_NAME"
    else
        # 物理机安装逻辑
        for file in "${FILES[@]}"; do
            cp -f "$file" "$PHYSICAL_DIR/"
            chmod 755 "$PHYSICAL_DIR/$file"
        done
        
        if ! grep -q 'id="theme-css"' "$PHYSICAL_DIR/index.html"; then
            awk '/<\/head>/{print "    <link rel=\"stylesheet\" id=\"theme-css\" href=\"style.css\" type=\"text/css\" media=\"all\" />\n    <script src=\"common-utils.js\"></script>\n    <script src=\"jquery-3.6.0.min.js\"></script>\n    <script src=\"md5.min.js\"></script>\n    <script src=\"main.js\"></script>"}1' "$PHYSICAL_DIR/index.html" > "$PHYSICAL_DIR/index.html.tmp"
            mv "$PHYSICAL_DIR/index.html.tmp" "$PHYSICAL_DIR/index.html"
            chmod 644 "$PHYSICAL_DIR/index.html"
        fi
        echo -e "${YELLOW}请前往群晖/系统面板手动重启 Emby 服务。${RESET}"
    fi

    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}[成功] 安装/更新完毕！请等待 Emby 启动后，在浏览器按 Ctrl+F5 刷新！${RESET}"
}

# --- 功能：执行卸载还原 ---
do_uninstall() {
    echo -e "${YELLOW}正在清理修改并恢复原始状态...${RESET}"
    
    if [ "$ENV_CHOICE" == "1" ]; then
        # Docker 卸载逻辑
        docker cp "${CONTAINER_NAME}:${UI_PATH}/index.html" ./index_to_clean.html
        
        # 使用 grep -v 过滤掉包含关键词的行，比 sed 更安全稳定
        cat ./index_to_clean.html | grep -v "theme-css" | grep -v "common-utils.js" | grep -v "jquery-3.6.0.min.js" | grep -v "md5.min.js" | grep -v "main.js" > ./index_clean.html
        
        docker cp ./index_clean.html "${CONTAINER_NAME}:${UI_PATH}/index.html"
        rm ./index_to_clean.html ./index_clean.html
        
        for file in "${FILES[@]}"; do
            docker exec "$CONTAINER_NAME" rm -f "${UI_PATH}/$file"
        done
        
        echo -e "${YELLOW}正在重启 Emby 容器以恢复默认界面...${RESET}"
        docker restart "$CONTAINER_NAME"
    else
        # 物理机卸载逻辑
        cat "$PHYSICAL_DIR/index.html" | grep -v "theme-css" | grep -v "common-utils.js" | grep -v "jquery-3.6.0.min.js" | grep -v "md5.min.js" | grep -v "main.js" > "$PHYSICAL_DIR/index_clean.html"
        mv "$PHYSICAL_DIR/index_clean.html" "$PHYSICAL_DIR/index.html"
        
        for file in "${FILES[@]}"; do
            rm -f "$PHYSICAL_DIR/$file"
        done
        echo -e "${YELLOW}请前往群晖/系统面板手动重启 Emby 服务。${RESET}"
    fi
    echo -e "${GREEN}[成功] 卸载完成，系统已恢复原始状态！${RESET}"
}

# --- 主逻辑入口 ---
echo "请选择操作："
echo "  1) 安装/更新主题 (修复 404/权限并自动重启)"
echo "  2) 一键卸载还原"
read -p "请输入序号 (1-2): " OP_CHOICE

case $OP_CHOICE in
    1)
        get_env_info
        do_install
        ;;
    2)
        get_env_info
        do_uninstall
        ;;
    *)
        echo -e "${RED}输入错误，退出中...${RESET}"
        exit 1
        ;;
esac
