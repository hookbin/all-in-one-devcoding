# Synology Web Development Container

基于 `lscr.io/linuxserver/code-server:latest` 的单容器 NAS 开发环境。

## 功能

- code-server
- Node.js 20
- pnpm / yarn
- PM2 / nodemon
- MongoDB 7.0.5
- mongo-express
- Nginx
- 本地纯 TOTP 登录
- s6 service 管理
- GitHub Actions Docker build + smoke test

## 项目结构

```text
.
├── Dockerfile
├── .dockerignore
├── README.md
├── docker
│   ├── nginx
│   │   └── nginx.conf
│   ├── services
│   │   ├── mongodb
│   │   │   └── run
│   │   ├── mongo-express
│   │   │   └── run
│   │   ├── node-app
│   │   │   └── run
│   │   ├── nginx
│   │   │   └── run
│   │   └── totp
│   │       └── run
│   ├── totp
│   │   ├── package.json
│   │   └── server.js
│   └── www
│       └── index.html
└── .github
    └── workflows
        └── docker-test.yml
```

## 路由

容器内 Nginx 监听 `8000`。

| 路径 | 目标 | TOTP |
|---|---|---|
| `/` | `/config/www` | 否 |
| `/app/*` | Node.js `127.0.0.1:3000` | 否 |
| `/vscode/*` | code-server `127.0.0.1:8080` | 是 |
| `/express/*` | mongo-express `127.0.0.1:8081` | 是 |
| `/totp/*` | TOTP `127.0.0.1:4180` | 登录入口 |
| `/health` | Nginx | 否 |

MongoDB 只监听：

```text
127.0.0.1:27017
```

因此不需要，也不应该：

```text
-p 27017:27017
```

## 构建

当前 MongoDB 二进制为 x86_64，因此构建：

```bash
docker build --platform linux/amd64 -t synology-webdev:latest .
```

GitHub Actions 已固定：

```yaml
platforms: linux/amd64
```

ARM64 Synology 需要更换 MongoDB ARM64 方案。

## 运行

```bash
docker run -d \
  --name webdev \
  --restart unless-stopped \
  -p 8000:8000 \
  -v /volume1/docker/webdev/config:/config \
  synology-webdev:latest
```

然后：

```text
http://NAS-IP:8000/
```

如果使用 Synology Reverse Proxy，建议：

```text
HTTPS :443
    ↓
Synology Reverse Proxy
    ↓
container:8000
```

外部访问：

```text
https://NAS/
```

## TOTP

第一次启动，如果不存在：

```text
/config/totp/secret
```

TOTP 服务会自动生成 Secret。

查看：

```bash
docker logs webdev
```

会看到：

```text
Generated TOTP secret at /config/totp/secret
TOTP secret: ...
```

将 Secret 加入 Google Authenticator、Microsoft Authenticator、1Password、Bitwarden 等支持标准 TOTP 的应用。

然后：

```text
https://NAS/vscode/
```

或者：

```text
https://NAS/express/
```

输入 6 位动态验证码。

默认 Session 有效期为 8 小时。

## Node.js App

项目目录：

```text
/config/app
```

需要：

```text
/config/app/package.json
```

并且 package.json 建议存在：

```json
{
  "scripts": {
    "start": "node server.js"
  }
}
```

容器启动：

1. 等待 MongoDB TCP 端口 ready；
2. 如果没有 `node_modules`，执行 `pnpm install`；
3. 使用 PM2 启动 `npm start`。

访问：

```text
https://NAS/app/
```

例如：

```text
/app/api
```

会转发到：

```text
127.0.0.1:3000/api
```

如果没有 `package.json`，Node service 保持 idle，不影响其他服务。

## code-server

code-server 由 LinuxServer 基础镜像自己的 s6 服务管理。

本 Dockerfile 不重复启动 code-server。

外部：

```text
/vscode/
```

内部：

```text
127.0.0.1:8080
```

TOTP 是外层认证。

注意：LinuxServer code-server 自身可能仍有认证配置，因此可能形成：

```text
TOTP
  ↓
code-server 自身认证
  ↓
IDE
```

如果希望完全取消 code-server 自身认证，需要额外配置 LinuxServer code-server 的认证方式。

## mongo-express

mongo-express 不使用 Basic Auth：

```text
ME_CONFIG_BASICAUTH_USERNAME
ME_CONFIG_BASICAUTH_PASSWORD
```

外部认证由 Nginx + TOTP 提供：

```text
Browser
  ↓
HTTPS
  ↓
Nginx
  ↓
TOTP
  ↓
mongo-express
```

## 启动关系

s6 同时管理多个 service，但依赖关系使用 readiness check：

```text
MongoDB
   │
   ├── ready ──→ mongo-express
   │
   └── ready ──→ Node.js

code-server ──→ LinuxServer s6 管理

TOTP ────────→ 独立启动

Nginx ───────→ 独立启动
```

Nginx 不等待所有后端。

因此：

```text
/              可以立即访问
/app/          后端未 ready 时可能 502
/vscode/       后端未 ready 时可能 502
/express/      MongoDB/ME 未 ready 时可能 502
```

## GitHub Actions

工作流：

```text
.github/workflows/docker-test.yml
```

每次 push / pull request 自动：

1. Build Docker image
2. 使用 `linux/amd64`
3. 启动 container
4. 检查 `/health`
5. 检查 `/`
6. 检查 TOTP login
7. 检查 `/vscode/`
8. 检查 `/express/`
9. 检查 MongoDB
10. 检查 TOTP service
11. 执行 `nginx -t`
12. 失败时输出 container logs
13. 自动清理测试容器

## 持久化目录

只需要持久化：

```text
/config
```

主要数据：

```text
/config/app
/config/www
/config/totp/secret
/config/mongo_data
/config/logs
```

不要把：

```text
/config/totp/secret
```

提交到 Git。

## 安全建议

### HTTPS

生产环境建议：

```text
https://NAS/
```

不要直接把 TOTP 服务暴露给公网。

### MongoDB

不要：

```bash
-p 27017:27017
```

### TOTP Secret

Secret 相当于认证主密钥。

如果泄露，应删除：

```text
/config/totp/secret
```

重启后生成新的 Secret。

## Dockerfile 的设计原则

Dockerfile 现在只负责：

- 安装系统依赖
- 安装 Node.js
- 安装全局 CLI
- 安装 MongoDB
- COPY 配置
- COPY s6 services
- 设置权限
- Nginx build-time validation
- EXPOSE
- HEALTHCHECK

业务逻辑全部放在 `docker/`：

```text
docker/
├── nginx/
├── services/
├── totp/
└── www/
```

因此以后修改：

```text
Nginx → docker/nginx/nginx.conf
TOTP  → docker/totp/server.js
Mongo → docker/services/mongodb/run
Node  → docker/services/node-app/run
ME    → docker/services/mongo-express/run
首页  → docker/www/index.html
```

不需要再修改 Dockerfile。


## 持久化映射

推荐不要只挂载一个 `/config`，而是把需要持久化的目录分别映射到 NAS。

推荐：

```bash
docker run -d \
  --name webdev \
  --restart unless-stopped \
  -p 8000:8000 \
  -v /volume1/docker/webdev/app:/config/app \
  -v /volume1/docker/webdev/www:/config/www \
  -v /volume1/docker/webdev/totp:/config/totp \
  -v /volume1/docker/webdev/logs:/config/logs \
  -v /volume1/docker/webdev/mongo_data:/config/mongo_data \
  -v /volume1/docker/webdev/nginx:/config/nginx \
  synology-webdev:latest
```

### Nginx 配置

NAS：

```text
/volume1/docker/webdev/nginx/nginx.conf
```

容器：

```text
/config/nginx/nginx.conf
```

第一次启动时，如果外部目录没有 `nginx.conf`，容器会自动从镜像中的默认配置复制一份。

以后直接编辑 NAS 上的：

```text
/volume1/docker/webdev/nginx/nginx.conf
```

然后重启容器：

```bash
docker restart webdev
```

即可。

这样重新创建/升级 Docker image 时，Nginx 配置不会丢失。

### MongoDB 数据

NAS：

```text
/volume1/docker/webdev/mongo_data
```

容器：

```text
/config/mongo_data
```

MongoDB 数据库文件全部持久化到 NAS。

删除容器不会删除 MongoDB 数据：

```text
docker rm -f webdev
```

重新创建并继续挂载：

```text
/volume1/docker/webdev/mongo_data
```

即可恢复。

### 推荐完整目录

```text
/volume1/docker/webdev/
├── app/
├── www/
├── totp/
│   └── secret
├── logs/
├── mongo_data/
└── nginx/
    └── nginx.conf
```

其中：

```text
app/         Node.js 项目
www/         Nginx 静态网站
totp/        TOTP Secret
logs/        Nginx/MongoDB 等日志
mongo_data/  MongoDB 数据库
nginx/       Nginx 配置
```

### 为什么 Nginx 配置不能直接只 COPY 到 `/config`

Dockerfile 中：

```dockerfile
COPY docker/nginx/nginx.conf /config/nginx/nginx.conf
```

如果运行时：

```bash
-v /volume1/docker/webdev/nginx:/config/nginx
```

bind mount 会覆盖镜像里的 `/config/nginx`。

因此本项目采用：

```text
镜像默认配置
    ↓
/opt/default-nginx.conf
    ↓
第一次启动
    ↓
/config/nginx/nginx.conf
    ↓
NAS 持久化
```

这是为了同时满足：

- Docker image 自带默认配置；
- NAS 可以修改 Nginx 配置；
- 重建 image 不覆盖用户配置；
- 容器删除后配置仍然存在。

### Docker Volume 声明

Dockerfile 中声明：

```dockerfile
VOLUME [
  "/config/app",
  "/config/www",
  "/config/totp",
  "/config/logs",
  "/config/mongo_data",
  "/config/nginx"
]
```

如果使用 Synology Container Manager，分别把上述容器目录绑定到 NAS 对应目录即可。

## 日志持久化

所有自定义服务日志统一放到：

```text
/config/logs
```

并通过 NAS 映射持久化：

```text
/volume1/docker/webdev/logs
        ↓
/config/logs
```

目录结构：

```text
logs/
├── nginx/
│   ├── access.log
│   └── error.log
├── mongodb/
│   └── mongod.log
├── mongo-express/
│   └── mongo-express.log
├── node-app/
│   ├── out.log
│   └── error.log
├── pm2/
│   └── PM2 runtime files
├── totp/
│   └── totp.log
└── code-server/
```

### Nginx

```text
/config/logs/nginx/access.log
/config/logs/nginx/error.log
```

Nginx 配置直接写入上述持久化目录。

### MongoDB

```text
/config/logs/mongodb/mongod.log
```

MongoDB 数据本身仍然独立保存于：

```text
/config/mongo_data
```

不要把 MongoDB 数据和日志混在同一个目录。

### mongo-express

```text
/config/logs/mongo-express/mongo-express.log
```

mongo-express 的 stdout/stderr 会写入这个文件。

### Node.js / PM2

Node.js 应用：

```text
/config/logs/node-app/out.log
/config/logs/node-app/error.log
```

PM2 自身运行目录：

```text
/config/logs/pm2
```

因此不会把 PM2 日志散落到 `abc` 用户的 home 目录。

### TOTP

```text
/config/logs/totp/totp.log
```

TOTP Secret 仍然单独保存：

```text
/config/totp/secret
```

### code-server

`code-server` 由 LinuxServer 基础镜像自己的 s6 service 管理。该 service 的具体日志行为由基础镜像控制，因此本项目不会强行覆盖其原生 service。

`/config/logs/code-server` 作为预留目录；如果后续需要将 code-server 日志完全文件化，可以针对 LinuxServer 当前版本的 service 定制。

### 日志和 Docker logs

本项目的服务日志优先写入：

```text
/config/logs
```

所以 NAS 上可以长期保留日志。

但 s6/service 的启动信息仍可能出现在：

```bash
docker logs webdev
```

这是正常的，两者用途不同：

```text
/config/logs
    → 应用运行日志、Nginx access/error、MongoDB log

docker logs
    → 容器/s6 生命周期和启动诊断信息
```

### 日志轮转

生产环境建议后续加入 logrotate 或基于应用自身的日志轮转策略。

尤其需要关注：

```text
nginx/access.log
mongo-express/mongo-express.log
node-app/out.log
node-app/error.log
totp/totp.log
```

不要让开发容器长期无限增长日志文件。
