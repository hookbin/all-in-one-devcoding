FROM lscr.io/linuxserver/code-server:latest

# 1. 切换到 root 安装系统级依赖
# (LinuxServer 默认使用 root 执行构建命令，这里明确声明)
USER root
RUN apt-get update && apt-get install -y curl git vim nano

# 2. 安装 Node.js 官方源并安装核心程序
# 这里以 20.x 版本为例，满足当前主流 Node.js 生态的需求
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# 3. 全局安装前端常用构建与守护工具 (如 PM2)
RUN npm install -g pnpm yarn pm2 nodemon

# 4. 修复 npm 全局安装的权限问题 (核心防坑步骤)
# LinuxServer 的容器在运行时会将权限降级为默认的 abc 用户 (UID 1000)。
# 必须转移这些全局模块和可执行文件的所有权，否则你在 Web 终端中执行 `npm install -g xxx` 会报 Permission Denied。
RUN chown -R 1000:1000 /usr/lib/node_modules \
    && chown -R 1000:1000 /usr/bin/npm \
    && chown -R 1000:1000 /usr/bin/node \
    && chown -R 1000:1000 /usr/bin/pnpm \
    && chown -R 1000:1000 /usr/bin/yarn \
    && chown -R 1000:1000 /usr/bin/pm2 \
    && chown -R 1000:1000 /usr/bin/nodemon

# 5. 清理缓存以极大地减小镜像构建体积
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*
