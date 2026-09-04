FROM lscr.io/linuxserver/code-server:latest

USER root

# 1. 声明环境变量
ENV ME_CONFIG_BASICAUTH_USERNAME="admin" \
    ME_CONFIG_BASICAUTH_PASSWORD="admin" \
    ME_CONFIG_MONGODB_URL="mongodb://localhost:27017/" \
    ME_CONFIG_SITE_BASEURL="/express/"

# 2. 安装基础工具、数据库依赖 以及 Nginx
RUN apt-get update && apt-get install -y curl git vim nano wget libcurl4 nginx

# 3. 安装 Node.js 与全局工具 (含 mongo-express)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g pnpm yarn pm2 nodemon mongo-express

# 4. 安装 MongoDB
RUN wget -qO /tmp/mongo.tgz https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-7.0.5.tgz && \
    tar -zxvf /tmp/mongo.tgz -C /tmp && \
    mv /tmp/mongodb-linux-x86_64-ubuntu2204-7.0.5/bin/* /usr/local/bin/ && \
    rm -rf /tmp/mongo*

# 5. 修复 npm 全局工具权限
RUN chown -R 1000:1000 /usr/lib/node_modules \
    && chown -R 1000:1000 /usr/bin/npm \
    && chown -R 1000:1000 /usr/bin/node \
    && chown -R 1000:1000 /usr/bin/pm2 \
    && chown -R 1000:1000 /usr/bin/mongo-express

# 6. 使用 heredoc 注入启动和路由控制脚本
RUN cat << 'EOF' > /etc/cont-init.d/99-start-services
#!/bin/bash

# ==========================================
# 初始化目录和权限
# ==========================================
mkdir -p /config/mongo_data /config/nginx /config/logs
chown -R abc:abc /config/mongo_data /config/nginx /config/logs

# ==========================================
# 启动后台服务 (DB & GUI)
# ==========================================
s6-setuidgid abc mongod --dbpath /config/mongo_data --logpath /config/logs/mongo.log --fork
s6-setuidgid abc bash -c "nohup mongo-express > /config/logs/mongo-express.log 2>&1 &"

# ==========================================
# 控制台高亮输出 (每次启动容器时打印)
# ==========================================
echo ""
echo "=================================================================="
echo "          🚀 Web Dev Environment is Ready!                        "
echo "=================================================================="
echo " 🌐 [Nginx Proxy]   Port: 80    | Routing all traffic below:"
echo " 💻 [Web IDE]       Port: 8080  | Access via: http://<IP>/vscode/"
echo " 🍃 [Mongo GUI]     Port: 8081  | Access via: http://<IP>/express/"
echo " 🚀 [Node.js App]   Port: 3000  | Access via: http://<IP>/"
echo " 🗄️  [MongoDB]       Port: 27017 | (Internal Network Only)"
echo "=================================================================="
echo ""

# 启动 Nginx
nginx -c /config/nginx/nginx.conf
EOF

# 7. 赋予脚本执行权限并清理环境
RUN chmod +x /etc/cont-init.d/99-start-services \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 8. 声明映射和端口
VOLUME ["/config", ""]
EXPOSE 80 8080 8081 3000
