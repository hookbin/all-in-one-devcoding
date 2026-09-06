# All-in-One DevCoding

用于 Synology NAS 的单容器 Web 开发环境，基于：

- LinuxServer `code-server`
- Nginx
- Node.js 20、npm、pnpm、yarn、Express
- PM2、nodemon
- MongoDB 7.0.5
- mongo-express

当前镜像面向 `linux/amd64`。MongoDB 使用官方 x86_64 二进制文件，ARM64 暂不支持。

## 工作方式

Nginx 是唯一的 HTTP 入口，监听容器内的 `8000` 端口：

| URL | 目标 |
| --- | --- |
| `/` | `/config/www` 静态资源 |
| `/vscode/` | code-server：`127.0.0.1:8080` |
| `/app/` | Node.js 应用：`127.0.0.1:3000` |
| `/express/` | mongo-express：`127.0.0.1:8081` |
| `/health` | Nginx 健康检查，返回 `200 OK` |

MongoDB 只应监听容器内部的 `127.0.0.1:27017`，不要映射 `27017` 到宿主机。

## 持久化目录

将 Synology 目录挂载到容器的 `/config`：

```text
/config
├── app/              Node.js 应用
├── www/              Nginx 静态网站根目录
├── mongo_data/       MongoDB 数据
├── nginx/
│   └── nginx.conf    Nginx 运行配置
├── logs/
│   ├── nginx/        Nginx 日志
│   └── mongodb/      MongoDB 日志
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

## 构建镜像

在项目根目录执行：

```bash
docker build \
  -t all-in-one-devcoding:latest .
```

## 运行容器

将 `/volume1/docker/devcoding` 替换为实际的 Synology 目录：

```bash
docker run -d \
  --name devcoding \
  --restart unless-stopped \
  -e TZ=Asia/Shanghai \
  -p 8000:8000 \
  -v /volume1/docker/devcoding:/config \
  all-in-one-devcoding:latest
```

MongoDB 会由 s6 自动启动，使用 `/config/mongo_data` 保存数据，并只监听容器内部的 `127.0.0.1:27017`。
mongo-express 由 PM2 自动启动和管理，监听容器内部的 `127.0.0.1:8081`，并通过 `/express/` 访问。
PM2 会由 s6 自动启动，并从 `/config/.pm2/dump.pm2` 恢复已保存的应用。
首次启动时会自动生成默认应用：

```text
/config/app/server.js
/config/app/package.json
/config/app/ecosystem.config.js
```

默认应用是 Express 项目，监听 `127.0.0.1:3000`，通过 `http://NAS-IP:8000/app/` 访问。已有文件不会被覆盖。
PM2 会监视 `/config/app`，修改 Express 应用文件后自动重启应用；`node_modules` 和日志文件会被忽略。

查看状态和日志：

```bash
docker ps
docker logs -f devcoding
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
http://NAS-IP:8000/express/
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
│       ├── mongodb/
│       │   └── run
│       └── pm2/
│           └── run
└── .github/
    └── workflows/
```

`Dockerfile` 负责安装运行环境；`docker/` 负责默认应用、Nginx 配置、PM2 配置和 LinuxServer s6 启动初始化。
