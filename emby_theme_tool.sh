#!/bin/bash

# ====================================================
# Emby CRX Theme 工具箱 (支持安装与一键卸载)
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
    echo "  1) Docker 容器版"
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

        # 定位目录
        UI_PATH=""
        for p in "/system/dashboard-ui" "/app/emby/system/dashboard-ui"; do
            # 这里修复了 ffi 的拼写错误为 fi
            if docker exec "$CONTAINER_NAME" test -d "$p"; then UI_PATH="$p"; break; fi
        done
        
        if [ -z "$UI_PATH" ]; then
            UI_PATH=$(docker exec "$CONTAINER_NAME" find / -maxdepth 5 -type d -name "dashboard-ui" 2>/dev/null | head -n 1)
        fi

        if [ -z "$UI_PATH" ]; then
            echo -e "${RED}[错误] 无法定位容器内 dashboard-ui 目录${RESET}"
            exit 1
        fi
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
    curl -sL -o emby-crx.zip https://github.com/Nolovenodie/emby-crx/archive/refs/heads/master.zip
    unzip -q -j emby-crx.zip "emby-crx-master/common-utils.js" "emby-crx-master/jquery-3.6.0.min.js" "emby-crx-master/md5.min.js" "emby-crx-master/style.css" "emby-crx-master/main.js"

    if [ "$ENV_CHOICE" == "1" ]; then
        # Docker 安装逻辑
        for file in "${FILES[@]}"; do
            docker cp "$file" "${CONTAINER_NAME}:${UI_PATH}/"
            docker exec "$CONTAINER_NAME" chmod 644 "${UI_PATH}/$file"
        done
        docker cp "${CONTAINER_NAME}:${UI_PATH}/index.html" ./index.html
        if ! grep -q "theme-css" ./index.html; then
            sed -i '/<\/head>/i \    <link rel="stylesheet" id="theme-css" href="style.css" type="text/css" media="all" />\n    <script src="common-utils.js"></script>\n    <script src="jquery-3.6.0.min.js"></script>\n    <script src="md5.min.js"></script>\n    <script src="main.js"></script>' ./index.html
            docker cp ./index.html "${CONTAINER_NAME}:${UI_PATH}/index.html"
            docker exec "$CONTAINER_NAME" chmod 644 "${UI_PATH}/index.html"
        fi
    else
        # 物理机安装逻辑
        for file in "${FILES[@]}"; do
            cp -f "$file" "$PHYSICAL_DIR/"
            chmod 644 "$PHYSICAL_DIR/$file"
        done
        if ! grep -q "theme-css" "$PHYSICAL_DIR/index.html"; then
            sed -i '/<\/head>/i \    <link rel="stylesheet" id="theme-css" href="style.css" type="text/css" media="all" />\n    <script src="common-utils.js"></script>\n    <script src="jquery-3.6.0.min.js"></script>\n    <script src="md5.min.js"></script>\n    <script src="main.js"></script>' "$PHYSICAL_DIR/index.html"
            chmod 644 "$PHYSICAL_DIR/index.html"
        fi
    fi
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}[成功] 主题操作完成！请刷新浏览器 (Ctrl+F5) 查看效果。${RESET}"
}

# --- 功能：执行卸载还原 ---
do_uninstall() {
    echo -e "${YELLOW}正在清理修改并恢复原始状态...${RESET}"
    
    if [ "$ENV_CHOICE" == "1" ]; then
        # Docker 卸载逻辑
        docker cp "${CONTAINER_NAME}:${UI_PATH}/index.html" ./index_to_clean.html
        sed -i '/theme-css/d' ./index_to_clean.html
        sed -i '/common-utils.js/d' ./index_to_clean.html
        sed -i '/jquery-3.6.0.min.js/d' ./index_to_clean.html
        sed -i '/md5.min.js/d' ./index_to_clean.html
        sed -i '/main.js/d' ./index_to_clean.html
        docker cp ./index_to_clean.html "${CONTAINER_NAME}:${UI_PATH}/index.html"
        rm ./index_to_clean.html
        
        for file in "${FILES[@]}"; do
            docker exec "$CONTAINER_NAME" rm -f "${UI_PATH}/$file"
        done
    else
        # 物理机卸载逻辑
        sed -i '/theme-css/d' "$PHYSICAL_DIR/index.html"
        sed -i '/common-utils.js/d' "$PHYSICAL_DIR/index.html"
        sed -i '/jquery-3.6.0.min.js/d' "$PHYSICAL_DIR/index.html"
        sed -i '/md5.min.js/d' "$PHYSICAL_DIR/index.html"
        sed -i '/main.js/d' "$PHYSICAL_DIR/index.html"
        
        for file in "${FILES[@]}"; do
            rm -f "$PHYSICAL_DIR/$file"
        done
    fi
    echo -e "${GREEN}[成功] 卸载完成，已恢复原始 index.html 并清理相关资源文件。${RESET}"
}

# --- 主逻辑入口 ---
echo "请选择操作："
echo "  1) 安装/更新主题"
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
