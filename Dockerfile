FROM lscr.io/linuxserver/code-server:latest

# LinuxServer 镜像默认就是 root 执行构建，无需写 USER root

# 安装 Node.js 和全局工具
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g pnpm yarn pm2 nodemon

# 清理缓存以减小镜像体积
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 注意：这里不需要写 USER 1000。
# LinuxServer 的启动脚本 (s6-overlay) 会在容器启动时，
# 根据 docker-compose.yml 中的 PUID 和 PGID 自动为你配置安全的用户权限。
