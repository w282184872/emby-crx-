#!/bin/bash

# ====================================================
# Emby 主题工具箱 (宿主机直通版 - 严格校验)
# ====================================================

CONTAINER_NAME="emby"
TARGET_DIR="/system/dashboard-ui"
INDEX_FILE="$TARGET_DIR/index.html"
INDEX_BAK="$TARGET_DIR/index.html.bak"
REPO_ZIP_URL="https://github.com/w282184872/emby-crx-/archive/refs/heads/main.zip"
FILES_TO_EXTRACT=("common-utils.js" "jquery-3.6.0.min.js" "md5.min.js" "style.css" "main.js")

echo "====================================="
echo "    Emby 主题工具箱 (宿主机直通版)    "
echo "====================================="

# 1. 前置检查：容器是否运行，内部是否存在目标目录
if ! command -v docker &> /dev/null; then
    echo "[错误] 宿主机未安装 Docker 命令！"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
    echo "[错误] 找不到正在运行的容器: $CONTAINER_NAME"
    exit 1
fi

if ! docker exec "$CONTAINER_NAME" test -f "$INDEX_FILE"; then
    echo "[错误] 容器 $CONTAINER_NAME 内找不到目标文件: $INDEX_FILE"
    echo "请确认该镜像的安装目录是否确为 $TARGET_DIR"
    exit 1
fi

# --- 安装/更新 功能 ---
do_install() {
    echo ""
    echo "========== 开始安装/更新 =========="
    
    # 1. 容器内备份 index.html
    docker exec "$CONTAINER_NAME" sh -c "if [ ! -f \"$INDEX_BAK\" ]; then cp \"$INDEX_FILE\" \"$INDEX_BAK\"; echo '  [备份] 已在容器内备份原文件至 $INDEX_BAK'; else echo '  [备份] 容器内备份已存在，跳过。'; fi"

    # 2. 在宿主机下载并解压文件
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit

    echo "  正在宿主机下载源码压缩包..."
    if command -v curl &> /dev/null; then
        curl -sL -o emby-crx.zip "$REPO_ZIP_URL"
    else
        wget -qO emby-crx.zip "$REPO_ZIP_URL"
    fi

    echo "  正在解压并提取文件..."
    unzip -q emby-crx.zip

    # 3. 将文件推送进容器
    echo "  正在将资源推送到容器内部..."
    for file in "${FILES_TO_EXTRACT[@]}"; do
        FIND_FILE=$(find . -type f -name "$file" | head -n 1)
        if [ -n "$FIND_FILE" ]; then
            # 如果容器里已经有同名的其他旧文件，顺手备份一下
            docker exec "$CONTAINER_NAME" sh -c "if [ -f \"$TARGET_DIR/$file\" ]; then cp -f \"$TARGET_DIR/$file\" \"$TARGET_DIR/${file}.bak\"; fi"
            # 从宿主机复制到容器内，并强制赋予 755 权限防止 403 报错
            docker cp "$FIND_FILE" "${CONTAINER_NAME}:${TARGET_DIR}/"
            docker exec "$CONTAINER_NAME" chmod 755 "$TARGET_DIR/$file"
        fi
    done

    # 4. 修改 index.html (拉出到宿主机修改再推回，避免容器内缺少 sed/awk)
    echo "  正在修改代码..."
    docker cp "${CONTAINER_NAME}:${INDEX_FILE}" ./index.html
    
    if grep -q "id='theme-css'" ./index.html; then
        echo "  [提示] index.html 中已存在主题代码，跳过写入。"
    else
        awk '/<\/head>/{print "    <link rel='\''stylesheet'\'' id='\''theme-css'\''  href='\''style.css'\'' type='\''text/css'\'' media='\''all'\'' />\n    <script src=\"common-utils.js\"></script>\n    <script src=\"jquery-3.6.0.min.js\"></script>\n    <script src=\"md5.min.js\"></script>\n    <script src=\"main.js\"></script>"}1' ./index.html > ./index.html.tmp
        mv ./index.html.tmp ./index.html
        docker cp ./index.html "${CONTAINER_NAME}:${INDEX_FILE}"
        docker exec "$CONTAINER_NAME" chmod 644 "$INDEX_FILE"
    fi
    
    rm -rf "$TEMP_DIR"

    # ====================================================
    # 5. 双重验证模块
    # ====================================================
    echo ""
    echo "========== 开始执行验证 =========="
    VERIFY_FAIL=0

    echo "【验证 1: 文件存在性检查 (容器内)】"
    for file in "${FILES_TO_EXTRACT[@]}"; do
        if docker exec "$CONTAINER_NAME" test -f "$TARGET_DIR/$file"; then
            echo "  [成功] $file 已存在于容器的 $TARGET_DIR/ 中"
        else
            echo "  [失败] $file 未能在容器内找到！"
            VERIFY_FAIL=1
        fi
    done

    echo "【验证 2: HTML代码注入检查】"
    # 为了避免通过 docker exec 执行复杂 grep 带来的转义问题，将文件拉取到宿主机验证
    VERIFY_TEMP=$(mktemp)
    docker cp "${CONTAINER_NAME}:${INDEX_FILE}" "$VERIFY_TEMP"
    
    if grep -q "<link rel='stylesheet' id='theme-css'  href='style.css' type='text/css' media='all' />" "$VERIFY_TEMP" && \
       grep -q "<script src=\"common-utils.js\"></script>" "$VERIFY_TEMP" && \
       grep -q "<script src=\"jquery-3.6.0.min.js\"></script>" "$VERIFY_TEMP" && \
       grep -q "<script src=\"md5.min.js\"></script>" "$VERIFY_TEMP" && \
       grep -q "<script src=\"main.js\"></script>" "$VERIFY_TEMP"; then
        echo "  [成功] 5 行注入代码已在容器的 index.html 中全部验证通过！"
    else
        echo "  [失败] index.html 代码验证不完整或未找到！"
        VERIFY_FAIL=1
    fi
    rm -f "$VERIFY_TEMP"

    echo ""
    if [ "$VERIFY_FAIL" -eq 0 ]; then
        echo "========== ✅ 安装与验证完美通过！ =========="
        echo "正在自动重启 Emby 容器以应用更改 (解决 404 缓存问题)..."
        docker restart "$CONTAINER_NAME"
        echo "重启完成！请刷新浏览器 (Ctrl+F5) 生效。"
    else
        echo "========== ❌ 验证过程出现异常！ =========="
    fi
}

# --- 卸载/还原 功能 ---
do_uninstall() {
    echo ""
    echo "========== 开始卸载与还原 =========="
    
    # 1. 还原 index.html
    if docker exec "$CONTAINER_NAME" test -f "$INDEX_BAK"; then
        echo "  发现容器内有备份文件，正在还原 $INDEX_FILE ..."
        docker exec "$CONTAINER_NAME" sh -c "cp -f \"$INDEX_BAK\" \"$INDEX_FILE\" && rm -f \"$INDEX_BAK\""
    else
        echo "  未找到备份，正在通过宿主机拉取并清理代码恢复 $INDEX_FILE ..."
        TEMP_INDEX=$(mktemp)
        docker cp "${CONTAINER_NAME}:${INDEX_FILE}" "$TEMP_INDEX"
        cat "$TEMP_INDEX" | grep -v "theme-css" | grep -v "common-utils.js" | grep -v "jquery-3.6.0.min.js" | grep -v "md5.min.js" | grep -v "main.js" > "${TEMP_INDEX}.tmp"
        docker cp "${TEMP_INDEX}.tmp" "${CONTAINER_NAME}:${INDEX_FILE}"
        rm -f "$TEMP_INDEX" "${TEMP_INDEX}.tmp"
    fi

    # 2. 清理容器内的主题文件
    echo "  正在清理容器内的主题资源文件..."
    for file in "${FILES_TO_EXTRACT[@]}"; do
        docker exec "$CONTAINER_NAME" rm -f "$TARGET_DIR/$file"
        # 还原可能存在的文件备份
        docker exec "$CONTAINER_NAME" sh -c "if [ -f \"$TARGET_DIR/${file}.bak\" ]; then mv -f \"$TARGET_DIR/${file}.bak\" \"$TARGET_DIR/$file\"; fi"
    done

    echo "正在重启 Emby 容器以应用还原..."
    docker restart "$CONTAINER_NAME"
    echo "========== ✅ 卸载与还原完成！ =========="
    echo "系统已恢复原样，请刷新浏览器 (Ctrl+F5) 生效。"
}

# --- 主菜单 ---
echo "请选择操作："
echo "  1) 安装/更新主题 (覆盖并备份)"
echo "  2) 一键卸载并还原"
read -p "请输入序号 (1 或 2): " OP_CHOICE

case $OP_CHOICE in
    1)
        do_install
        ;;
    2)
        do_uninstall
        ;;
    *)
        echo "[错误] 输入无效，脚本退出。"
        exit 1
        ;;
esac
