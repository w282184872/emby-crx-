#!/bin/bash

# ====================================================
# Emby 主题纯净安装与卸载脚本 (含备份与严格校验)
# ====================================================

TARGET_DIR="/system/dashboard-ui"
INDEX_FILE="$TARGET_DIR/index.html"
INDEX_BAK="$TARGET_DIR/index.html.bak"
REPO_ZIP_URL="https://github.com/w282184872/emby-crx-/archive/refs/heads/main.zip"
FILES_TO_EXTRACT=("common-utils.js" "jquery-3.6.0.min.js" "md5.min.js" "style.css" "main.js")

echo "====================================="
echo "    Emby 主题工具箱 (绝对路径版)    "
echo "====================================="

# 确保在正确的环境下运行
if [ ! -d "$TARGET_DIR" ] || [ ! -f "$INDEX_FILE" ]; then
    echo "[错误] 找不到目标目录或文件: $INDEX_FILE"
    echo "请确认当前是否在包含 /system/dashboard-ui/ 的环境中。"
    exit 1
fi

# --- 安装/更新 功能 ---
do_install() {
    echo ""
    echo "========== 开始安装/更新 =========="
    
    # 1. 备份 index.html (如果已存在备份则跳过，保证备份是最纯净的原版)
    if [ ! -f "$INDEX_BAK" ]; then
        cp "$INDEX_FILE" "$INDEX_BAK"
        echo "  [备份] 已备份原文件至 $INDEX_BAK"
    else
        echo "  [备份] 原文件备份已存在，无需重复备份。"
    fi

    # 2. 准备临时目录并下载文件
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit

    echo "  正在下载源码压缩包..."
    if command -v curl &> /dev/null; then
        curl -sL -o emby-crx.zip "$REPO_ZIP_URL"
    else
        wget -qO emby-crx.zip "$REPO_ZIP_URL"
    fi

    if [ ! -f "emby-crx.zip" ]; then
        echo "  [错误] 下载失败，请检查网络。"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    echo "  正在解压并覆盖提取文件..."
    unzip -q emby-crx.zip

    # 3. 提取文件、备份可能存在的原同名文件并覆盖
    for file in "${FILES_TO_EXTRACT[@]}"; do
        # 如果目标目录已有同名文件，备份它（除了 index.html 的其他文件）
        if [ -f "$TARGET_DIR/$file" ]; then
            cp -f "$TARGET_DIR/$file" "$TARGET_DIR/${file}.bak"
        fi
        # 强制覆盖拷贝
        find . -type f -name "$file" -exec cp -f {} "$TARGET_DIR/" \;
    done

    # 4. 修改 index.html
    echo "  正在写入代码到 $INDEX_FILE ..."
    if grep -q "id='theme-css'" "$INDEX_FILE"; then
        echo "  [提示] $INDEX_FILE 中已存在主题代码，跳过写入。"
    else
        awk '/<\/head>/{print "    <link rel='\''stylesheet'\'' id='\''theme-css'\''  href='\''style.css'\'' type='\''text/css'\'' media='\''all'\'' />\n    <script src=\"common-utils.js\"></script>\n    <script src=\"jquery-3.6.0.min.js\"></script>\n    <script src=\"md5.min.js\"></script>\n    <script src=\"main.js\"></script>"}1' "$INDEX_FILE" > "${INDEX_FILE}.tmp"
        mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
    fi

    rm -rf "$TEMP_DIR"

    # 5. 双重验证模块
    echo ""
    echo "========== 开始执行验证 =========="
    VERIFY_FAIL=0

    # 验证 1
    echo "【验证 1: 文件存在性检查】"
    for file in "${FILES_TO_EXTRACT[@]}"; do
        if [ -f "$TARGET_DIR/$file" ]; then
            echo "  [成功] $file 已存在于 $TARGET_DIR/"
        else
            echo "  [失败] $file 未能在 $TARGET_DIR/ 中找到！"
            VERIFY_FAIL=1
        fi
    done

    # 验证 2
    echo "【验证 2: HTML代码注入检查】"
    if grep -q "<link rel='stylesheet' id='theme-css'  href='style.css' type='text/css' media='all' />" "$INDEX_FILE" && \
       grep -q "<script src=\"common-utils.js\"></script>" "$INDEX_FILE" && \
       grep -q "<script src=\"jquery-3.6.0.min.js\"></script>" "$INDEX_FILE" && \
       grep -q "<script src=\"md5.min.js\"></script>" "$INDEX_FILE" && \
       grep -q "<script src=\"main.js\"></script>" "$INDEX_FILE"; then
        echo "  [成功] 5 行代码已在 index.html 中全部验证通过！"
    else
        echo "  [失败] index.html 代码验证不完整或未找到！"
        VERIFY_FAIL=1
    fi

    echo ""
    if [ "$VERIFY_FAIL" -eq 0 ]; then
        echo "========== ✅ 安装与验证完美通过！ =========="
        echo "请刷新浏览器 (Ctrl+F5) 生效。"
    else
        echo "========== ❌ 验证过程出现异常！ =========="
    fi
}

# --- 卸载/还原 功能 ---
do_uninstall() {
    echo ""
    echo "========== 开始卸载与还原 =========="
    
    # 1. 还原 index.html
    if [ -f "$INDEX_BAK" ]; then
        echo "  发现备份文件，正在还原 $INDEX_FILE ..."
        cp -f "$INDEX_BAK" "$INDEX_FILE"
        rm -f "$INDEX_BAK"
    else
        echo "  未找到备份文件，正在通过代码清理恢复 $INDEX_FILE ..."
        # 使用 grep -v 安全剔除包含特定字符的行
        cat "$INDEX_FILE" | grep -v "theme-css" | grep -v "common-utils.js" | grep -v "jquery-3.6.0.min.js" | grep -v "md5.min.js" | grep -v "main.js" > "${INDEX_FILE}.tmp"
        mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
    fi

    # 2. 清理提取的文件，并还原可能存在的独立备份
    echo "  正在清理主题文件..."
    for file in "${FILES_TO_EXTRACT[@]}"; do
        rm -f "$TARGET_DIR/$file"
        # 如果存在该文件的备份（说明覆盖前系统里有这文件），则还原它
        if [ -f "$TARGET_DIR/${file}.bak" ]; then
            mv "$TARGET_DIR/${file}.bak" "$TARGET_DIR/$file"
        fi
    done

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
