FROM lscr.io/linuxserver/code-server:latest

# 1. 切换到 root 安装系统级依赖
# (LinuxServer 默认使用 root 执行构建命令，这里明确一下)
USER root
RUN apt-get update && apt-get install -y curl git vim nano

# 2. 安装 Node.js 官方源并安装核心程序
# 这里以 20.x 版本为例，如果需要别的版本，修改数字即可
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# 3. 全局安装前端常用构建与守护工具 (如 PM2)
RUN npm install -g pnpm yarn pm2 nodemon

# 4. 修复 npm 全局安装的权限问题 (关键步骤)
# LinuxServer 的网页端使用 abc (UID 1000) 用户操作。
# 如果不改权限，以后在终端执行 `npm install -g xxx` 会报 Permission Denied。
RUN chown -R 1000:1000 /usr/lib/node_modules \
    && chown -R 1000:1000 /usr/bin/npm \
    && chown -R 1000:1000 /usr/bin/node \
    && chown -R 1000:1000 /usr/bin/pnpm \
    && chown -R 1000:1000 /usr/bin/yarn \
    && chown -R 1000:1000 /usr/bin/pm2 \
    && chown -R 1000:1000 /usr/bin/nodemon

# 5. 清理缓存以减小镜像体积
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 创建一个存放离线插件的临时目录
RUN mkdir -p /tmp/extensions

# 使用 curl 下载 Codeium 的 .vsix 安装包
RUN curl -L -o /tmp/extensions/codeium.vsix "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/Codeium/vsextensions/codeium/latest/vspackage"

# 使用 code-server 命令行工具进行全局安装
RUN /app/code-server/bin/code-server --install-extension /tmp/extensions/codeium.vsix

# 清理临时文件
RUN rm -rf /tmp/extensions
