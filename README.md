# Emby 主题工具箱（宿主机直通版）

一键为 Docker 部署的 Emby 容器注入自定义主题，支持安装、更新、卸载和严格校验。  
主题文件来自本仓库 [emby-crx-](https://github.com/w282184872/emby-crx-)，脚本直接在宿主机操作，无需进入容器。



✨ 功能特性

自动备份：安装前自动备份原始 index.html，卸载时可完全还原。

严格校验：安装后自动检查所有文件是否存在、HTML 代码是否注入成功。

一键安装/更新：覆盖旧主题前会备份单个文件（.bak），安全无副作用。

一键卸载还原：彻底清除主题并恢复原始界面。

容器重启：操作完成后自动重启 Emby 容器，解决浏览器缓存问题。

📋 前置要求

宿主机已安装 Docker 并具有执行权限。

Emby 容器正在运行，且容器名称为 emby（脚本默认）。

Emby 容器内的网页目录必须为 /system/dashboard-ui（官方镜像默认路径）。

宿主机具备 curl 或 wget、unzip 命令（用于下载和解压主题包）。

⚠️ 注意事项

如果 Emby 容器名称不是 emby，请修改脚本开头的 CONTAINER_NAME 变量。

若 Emby 网页目录不同（例如自定义镜像），请修改 TARGET_DIR 变量。

脚本会直接覆盖 index.html 和主题文件，卸载时可完全恢复（前提是未手动删除备份文件 index.html.bak）。

由于容器内可能缺少 sed/awk，脚本会将 index.html 拉取到宿主机修改后再推送回去。

如果遇到 403 权限错误，脚本已自动执行 chmod 755 处理静态资源文件。

🧹 卸载说明

选择 2 后，脚本会：

从备份文件 index.html.bak 还原原始页面；若无备份则自动清理注入的代码行。

删除主题相关文件（style.css、main.js 等）。

恢复可能存在的单个文件备份（例如 style.css.bak → style.css）。

重启 Emby 容器。


## 🚀 一键安装 / 运行

```bash
bash <(curl -sL https://raw.githubusercontent.com/w282184872/emby-crx-/refs/heads/main/emby_theme_tool.sh?v=$(date +%s))
