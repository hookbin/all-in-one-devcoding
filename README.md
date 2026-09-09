# All-in-One DevCoding

用于 Synology NAS 的单容器 Web 开发环境，基于：

- LinuxServer `code-server`
- Nginx
- Node.js 20、npm、pnpm、yarn、Express
- PM2、nodemon
- MongoDB 7.0.5

当前镜像面向 `linux/amd64`。MongoDB 使用官方 x86_64 二进制文件，ARM64 暂不支持。

## 工作方式

Nginx 是唯一的 HTTP 入口，监听容器内的 `8000` 端口：

| URL | 目标 |
| --- | --- |
| `/` | `/config/www` 静态资源 |
| `/vscode/` | code-server：`127.0.0.1:8443`，Nginx 会移除外部 `/vscode` 前缀 |
| `/app/` | Node.js 应用：`127.0.0.1:3000` |
| `/health` | Nginx 健康检查，返回 `200 OK` |

MongoDB 只应监听容器内部的 `127.0.0.1:27017`，不要映射 `27017` 到宿主机。

## 持久化目录

将 Synology 目录挂载到容器的 `/config`：

```text
/config
├── app/              Node.js 应用
├── www/              Nginx 静态网站根目录
├── mongo_data/       MongoDB 数据
├── data/             code-server 用户数据
├── extensions/       VS Code 扩展
├── workspace/        code-server 工作区
├── nginx/
│   └── nginx.conf    Nginx 运行配置
├── logs/
│   ├── nginx/        Nginx 日志
│   ├── code-server/  code-server 日志
│   ├── mongodb/      MongoDB 日志
│   └── logrotate.status
└── .pm2/             PM2 数据
```

容器首次启动时会自动创建这些目录，并将默认 Nginx 配置复制到：

```text
/config/nginx/nginx.conf
```

默认配置不会覆盖已经存在的文件。以后直接编辑 Synology 映射目录中的 `nginx/nginx.conf`，然后重启容器即可生效。

Nginx 配置模板位于镜像内：

```text
/opt/default-nginx.conf
```

容器内的 logrotate 服务每天执行一次日志轮转；Nginx、MongoDB、code-server 和 PM2 日志单文件超过 `50 MB` 时也会轮转。每类日志保留最近 `14` 个轮转文件，旧文件会压缩保存。轮转状态保存在 `/config/logs/logrotate.status`，不依赖群晖宿主机的定时任务。

## 权限和环境变量

容器内 `/config` 目录固定由 `abc:abc` 用户和用户组拥有：

```text
abc:abc
```

Synology 上的 `/config` 映射目录必须允许容器内的 `abc` 用户读写。
容器内 `abc` 的实际 UID/GID 以以下命令输出为准：

```bash
sudo docker exec devcoding id abc
```

如果 Synology 使用 SSH 设置目录权限，应使用上述输出中的数字 UID/GID：

```bash
sudo chown -R UID:GID /volume1/docker/devcoding
```

`TZ` 默认设置为 `Asia/Shanghai`，权限不通过 `PUID`、`PGID` 配置。

镜像还设置了：

```text
PM2_HOME=/config/.pm2
NPM_CONFIG_PREFIX=/opt/npm-global
```

可通过 `NGINX_ADMIN_TOKEN` 启用 Nginx 配置管理 API。该令牌不会写入镜像：

```bash
-e NGINX_ADMIN_TOKEN=请替换为随机长令牌
```

查询状态：

```bash
curl http://NAS-IP:8000/app/api/nginx/status
```

校验并重新加载 `/config/nginx/nginx.conf`：

```bash
curl -X POST \
  -H "X-Nginx-Admin-Token: 请替换为随机长令牌" \
  http://NAS-IP:8000/app/api/nginx/reload
```

配置校验失败时不会执行 reload。未设置令牌时，reload API 会返回 `401`。

## 构建镜像

在项目根目录执行：

```bash
docker build \
  -t all-in-one-devcoding:latest .
```

## 自动化容器测试

运行容器级 smoke test：

```bash
IMAGE=all-in-one-devcoding:latest bash tests/container-smoke.sh
```

测试只通过 `curl` 验证页面路径 `/`、`/health`、`/app/`、`/vscode/` 返回 HTTP `200`。每次请求连接和通信超时均为 3 秒，GitHub Actions 会在推送镜像前自动执行该脚本。

## 在群晖 NAS 部署

### 前置条件

- 群晖为 x86_64/AMD64。当前镜像中的 MongoDB 官方二进制不支持 ARM64。
- 已安装 Container Manager，并准备一个持久化目录，例如 `/volume1/docker/devcoding`。
- NAS 的 `8000` 端口没有被其他服务占用。

### 使用 Container Manager 或 SSH 创建容器

1. 在 NAS 上创建目录 `/volume1/docker/devcoding`，并确保 Container Manager 对该目录有读写权限。
2. 在 Container Manager 中创建容器，或通过 SSH 执行下面的 Docker 命令。
3. 只配置端口映射 `8000:8000` 和目录映射 `/volume1/docker/devcoding:/config`，不要映射 MongoDB 的 `27017`。

如需启用 Nginx 配置管理 API，在容器环境变量中设置一个随机长令牌：

```text
NGINX_ADMIN_TOKEN=替换为随机长令牌
```

将 `/volume1/docker/devcoding` 替换为实际的 Synology 目录：

如果需要启用 Nginx 管理 API，将下面命令中的 `NGINX_ADMIN_TOKEN` 行取消注释并替换为随机长令牌。

```bash
docker run -d \
  --name devcoding \
  --restart unless-stopped \
  -e TZ=Asia/Shanghai \
  -p 8000:8000 \
  -v /volume1/docker/devcoding:/config \
  all-in-one-devcoding:latest
```

容器启动时，LinuxServer 的 s6 会自动启动 Nginx 服务，使用 `/config/nginx/nginx.conf`，监听容器内的 `8000` 端口。容器重启或 Nginx 进程退出后，s6 会负责重新拉起服务。

首次启动后，容器会在 `/config` 下创建应用、网站、MongoDB 数据、日志和 PM2 数据目录。用以下命令确认容器内用户 UID/GID，再按实际数字修正 NAS 目录权限：

```bash
docker exec devcoding id abc
chown -R UID:GID /volume1/docker/devcoding
```

验证部署：

```bash
curl -f http://NAS-IP:8000/health
curl -f http://NAS-IP:8000/app/
```

浏览器访问：

```text
http://NAS-IP:8000/
http://NAS-IP:8000/vscode/
http://NAS-IP:8000/app/
```

### 安全注意事项

- code-server 不启用内置密码认证。只能在可信内网中直接访问；公网访问必须经过 DSM 反向代理、HTTPS 和身份认证。
- 不要添加 `27017:27017` 端口映射。MongoDB 已限制监听容器内的 `127.0.0.1`。
- `NGINX_ADMIN_TOKEN` 仅用于 `/app/api/nginx/reload`，不要提交到 Git 或写入镜像。

MongoDB 会由 s6 自动启动，使用 `/config/mongo_data` 保存数据，并只监听容器内部的 `127.0.0.1:27017`。
PM2 会由 s6 自动启动，并从 `/config/.pm2/dump.pm2` 恢复已保存的应用。
首次启动时会自动生成默认应用：

```text
/config/app/server.js
/config/app/package.json
/config/app/ecosystem.config.js
```

默认应用是 Express 项目，监听 `127.0.0.1:3000`，通过 `http://NAS-IP:8000/app/` 访问。已有文件不会被覆盖。
PM2 会监视 `/config/app`，修改 Express 应用文件后自动重启应用；`node_modules` 和日志文件会被忽略。

code-server 通过 Nginx 的 `/vscode/` 子路径访问。该配置按照官方 subpath 方式转发，并保留末尾 `/`：

```text
http://NAS-IP:8000/vscode/
```

查看状态和日志：

```bash
docker ps
docker logs -f devcoding
```

查看容器内日志轮转状态或立即执行一次轮转：

```bash
docker exec devcoding cat /config/logs/logrotate.status
docker exec devcoding logrotate -s /config/logs/logrotate.status -f /etc/logrotate.d/devcoding
```

进入容器：

```bash
sudo docker exec -it devcoding bash
```

如需替换默认应用，编辑 `/config/app/server.js` 或
`/config/app/ecosystem.config.js`，然后执行：

```bash
pm2 startOrRestart /config/app/ecosystem.config.js
pm2 save
```

以后容器重启时，PM2 会自动恢复已保存的应用。检查 PM2 状态：

```bash
pm2 list
pm2 ping
```

## 访问地址

将 `NAS-IP` 替换为 NAS 的实际地址：

```text
http://NAS-IP:8000/
http://NAS-IP:8000/vscode/
http://NAS-IP:8000/app/
http://NAS-IP:8000/health
```

健康检查只确认 Nginx HTTP 入口可用，不代表所有后端服务都已完成初始化。

## 项目结构

```text
.
├── Dockerfile
├── README.md
├── docker/
│   ├── nginx/
│   │   └── nginx.conf
│   ├── app/
│   │   └── server.js
│   ├── pm2/
│   │   └── ecosystem.config.js
│   ├── cont-init.d/
│   │   └── 10-runtime-directories
│   └── services.d/
│       ├── nginx/
│       │   └── run
│       ├── logrotate/
│       │   └── run
│       ├── mongodb/
│       │   └── run
│       └── pm2/
│           └── run
└── .github/
    └── workflows/
```

`Dockerfile` 负责安装运行环境；`docker/` 负责默认应用、Nginx 配置、PM2 配置和 LinuxServer s6 启动初始化。
