# All-in-One DevCoding

> Synology NAS 上的 All-in-One Web Development Container

一个面向 Synology NAS 的单容器开发环境，将常用的 Web 开发运行时集中在一个 Docker 容器中。

当前阶段专注于提供稳定、简单的 **Runtime Environment**：

* Nginx
* code-server
* Node.js 20
* pnpm
* yarn
* PM2
* MongoDB 7
* mongo-express

后续再基于当前 Runtime Environment 规划 **App Manager / Control Plane**。

---

## 1. 项目定位

本项目不是生产环境 Web Server，也不是完整的 PaaS。

它的目标是：

> 在 Synology NAS 上提供一个开箱即用的个人/小团队 Web 开发工作站。

容器启动后，可以通过浏览器访问：

* Web 开发环境
* code-server
* Node.js 应用
* MongoDB
* mongo-express

整个开发环境集中在一个容器中，由 NAS 提供持久化存储。

---

## 2. 当前阶段目标

当前版本只解决：

> **Runtime Plane**

也就是：

```text
Node.js
PM2
MongoDB
mongo-express
Nginx
code-server
```

暂时不解决：

```text
App Manager
TOTP
用户管理
动态应用管理
动态路由管理
权限管理
应用注册中心
```

这些功能属于后续的 **Control Plane**。

---

## 3. Architecture

当前整体结构：

```text
                         Synology NAS
                              │
                              │ HTTP :8000
                              ▼
                        ┌─────────────┐
                        │    Nginx    │
                        │ Entry Point │
                        └──────┬──────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
        ┌──────────┐    ┌──────────────┐   ┌───────────┐
        │code-server│    │ Node.js App  │   │mongo-expr.│
        │   :8080  │    │    :3000     │   │   :8081   │
        └──────────┘    └───────┬──────┘   └─────┬─────┘
                                │                │
                                └───────┬────────┘
                                        ▼
                                  ┌───────────┐
                                  │  MongoDB  │
                                  │   :27017  │
                                  └───────────┘
```

### 服务关系

| Service       | Internal Address  | External      |
| ------------- | ----------------- | ------------- |
| Nginx         | `0.0.0.0:8000`    | Yes           |
| code-server   | `127.0.0.1:8080`  | Through Nginx |
| Node.js       | `127.0.0.1:3000`  | Through Nginx |
| mongo-express | `127.0.0.1:8081`  | Through Nginx |
| MongoDB       | `127.0.0.1:27017` | No            |

### 核心原则

**只有 Nginx 对外提供 HTTP 服务。**

MongoDB、Node.js、mongo-express、code-server 都属于容器内部服务。

---

## 4. Nginx

Nginx 是当前 Runtime Environment 的唯一 HTTP Entry Point。

默认监听：

```text
0.0.0.0:8000
```

当前提供以下路由：

| URL         | Backend          | Description   |
| ----------- | ---------------- | ------------- |
| `/`         | `/config/www`    | 默认 Web 页面     |
| `/app/`     | `127.0.0.1:3000` | Node.js 应用    |
| `/vscode/`  | `127.0.0.1:8080` | code-server   |
| `/express/` | `127.0.0.1:8081` | mongo-express |
| `/health`   | Nginx            | Health Check  |

当前 Nginx 配置是 **Static Configuration**。

不会在当前阶段实现动态路由管理。

---

## 5. code-server

code-server 提供浏览器版 VS Code 开发环境。

访问：

```text
/vscode/
```

内部服务：

```text
127.0.0.1:8080
```

code-server 使用基础镜像：

```text
lscr.io/linuxserver/code-server
```

因此服务生命周期继续由 LinuxServer 镜像的 **s6** 体系负责。

本项目不重复实现 code-server 的启动管理。

---

## 6. Node.js

当前 Node.js 版本：

```text
Node.js 20
```

同时提供：

```text
npm
pnpm
yarn
```

用于开发 Node.js / JavaScript / TypeScript 项目。

默认 Node.js 应用端口：

```text
127.0.0.1:3000
```

Nginx：

```text
/app/
```

反向代理到：

```text
127.0.0.1:3000
```

当前阶段只支持一个默认 Node.js Runtime。

多应用管理将在后续 App Manager 阶段实现。

---

## 7. PM2

PM2 用于管理 Node.js 应用进程。

当前安装：

```text
pm2
```

以及：

```text
nodemon
```

PM2 的作用是提供：

* Node.js 进程管理
* 自动重启
* 开发环境进程管理
* 日志管理
* 应用生命周期基础能力

当前阶段：

> PM2 只是 Runtime Tool，不负责应用注册和应用管理 UI。

后续 App Manager 可以在 PM2 之上构建 Control Plane。

---

## 8. MongoDB

当前 MongoDB：

```text
7.0.5
```

MongoDB 是容器内部数据库服务。

监听：

```text
127.0.0.1:27017
```

### 安全边界

MongoDB 不应该直接暴露到 Docker Host：

```text
❌ -p 27017:27017
```

也不应该监听：

```text
0.0.0.0:27017
```

当前架构：

```text
Node.js
   │
   ▼
127.0.0.1:27017
   │
   ▼
MongoDB
```

数据目录：

```text
/config/mongo_data
```

---

## 9. mongo-express

mongo-express 提供 MongoDB Web 管理界面。

内部监听：

```text
127.0.0.1:8081
```

通过 Nginx：

```text
/express/
```

访问。

当前阶段不加入 TOTP、App Manager 等额外认证逻辑。

认证方案将在后续 Control Plane / Authentication 阶段统一设计。

---

## 10. 持久化

整个容器使用：

```text
/config
```

作为持久化根目录。

当前目录结构：

```text
/config
├── app/
├── www/
├── mongo_data/
├── nginx/
└── logs/
```

说明：

### `/config/app`

默认 Node.js 应用目录。

### `/config/www`

默认 Nginx Web 根目录。

### `/config/mongo_data`

MongoDB 数据目录。

### `/config/nginx`

Nginx 持久化配置目录。

### `/config/logs`

服务日志目录。

---

## 11. Docker Volume

容器使用：

```text
/config
```

作为主要持久化 Volume。

例如：

```bash
docker run -d \
  --name devcoding \
  -p 8000:8000 \
  -v /volume1/docker/devcoding:/config \
  hookbin/all-in-one-devcoding
```

其中：

```text
/volume1/docker/devcoding
```

是 Synology NAS 上的实际持久化目录。

---

## 12. Nginx Configuration

镜像内提供默认 Nginx 配置模板：

```text
/opt/default-nginx.conf
```

持久化配置目录：

```text
/config/nginx
```

这样可以避免 Docker bind mount：

```text
/config/nginx
```

容器首次启动时，模板会复制为：

```text
/config/nginx/nginx.conf
```

以后可以直接编辑 Synology 映射目录中的 `nginx/nginx.conf`。如果该文件已经存在，容器启动时不会覆盖它。

Nginx 运行时明确使用 `/config/nginx/nginx.conf`，修改该文件后重启容器即可生效。

当前阶段 Nginx 配置保持静态。

未来 App Manager 可以扩展：

```text
/config/nginx/
├── nginx.conf
└── routes/
    ├── app-foo.conf
    ├── app-bar.conf
    └── ...
```

但这属于下一阶段设计。

---

## 13. Logs

日志统一放在：

```text
/config/logs
```

建议结构：

```text
/config/logs
├── nginx/
├── mongodb/
├── mongo-express/
├── node-app/
├── pm2/
└── code-server/
```

当前阶段主要保证日志可以持久化。

日志轮转策略可以后续独立完善。

---

## 14. s6 Service Management

容器使用 LinuxServer 基础镜像提供的 s6 服务体系。

服务管理原则：

```text
Docker
  │
  ▼
LinuxServer Base Image
  │
  ▼
s6
  │
  ├── code-server
  ├── nginx
  ├── mongodb
  ├── mongo-express
  └── node-app / PM2
```

Dockerfile 本身不负责直接启动这些服务。

不要在 Dockerfile 中使用：

```dockerfile
CMD nginx ...
```

或者：

```dockerfile
CMD mongod ...
```

来代替 s6。

---

## 15. Service Dependencies

当前服务依赖关系：

```text
MongoDB
   │
   ├── mongo-express
   │
   └── Node.js App
```

Nginx：

```text
Nginx
  │
  ├── code-server
  ├── Node.js
  └── mongo-express
```

Nginx 本身不需要等待所有后端服务完全启动。

因此容器刚启动时，某些服务仍在初始化可能出现：

```text
502 Bad Gateway
```

这是允许的启动状态。

待后端服务完成启动后，Nginx 即可正常代理。

---

## 16. Health Check

当前健康检查以 Nginx 为入口：

```text
GET /health
```

成功返回：

```text
200 OK
```

例如：

```bash
curl http://127.0.0.1:8000/health
```

预期：

```text
OK
```

Health Check 的目标是确认：

> 容器的 HTTP Entry Point 正常工作。

它不等价于所有后端服务都已经完全 Ready。

---

## 17. Dockerfile

当前 Dockerfile 的职责非常明确：

### 负责

```text
安装系统依赖
安装 Nginx
安装 Node.js
安装 pnpm
安装 yarn
安装 PM2
安装 nodemon
安装 mongo-express
安装 MongoDB
准备 /config
复制默认 Nginx 配置
提供 Health Check
```

### 不负责

```text
❌ App Manager
❌ TOTP
❌ 用户认证
❌ 动态路由
❌ 应用注册
❌ 应用创建
❌ 应用删除
❌ 应用启停 UI
❌ Secret 管理
```

这样 Dockerfile 可以保持稳定。

---

## 18. Build

构建：

```bash
docker build -t all-in-one-devcoding .
```

或者：

```bash
docker build \
  -t all-in-one-devcoding:latest \
  .
```

---

## 19. Run

基本运行方式：

```bash
docker run -d \
  --name devcoding \
  -p 8000:8000 \
  -v /volume1/docker/devcoding:/config \
  all-in-one-devcoding:latest
```

查看容器：

```bash
docker ps
```

查看日志：

```bash
docker logs devcoding
```

进入容器：

```bash
docker exec -it devcoding bash
```

---

## 20. Access

容器启动以后：

### Main Web

```text
http://NAS-IP:8000/
```

### code-server

```text
http://NAS-IP:8000/vscode/
```

### mongo-express

```text
http://NAS-IP:8000/express/
```

### Node.js

```text
http://NAS-IP:8000/app/
```

### Health

```text
http://NAS-IP:8000/health
```

---

## 21. Synology Reverse Proxy

推荐通过 Synology Reverse Proxy 对外提供 HTTPS。

整体结构：

```text
Internet / LAN
      │
      │ HTTPS
      ▼
Synology Reverse Proxy
      │
      │ HTTP
      ▼
127.0.0.1:8000
      │
      ▼
     Nginx
```

例如：

```text
https://dev.example.com
```

反向代理到：

```text
http://127.0.0.1:8000
```

TLS 终止由 Synology 负责。

---

## 22. Security Boundary

当前版本的安全边界：

### Nginx

唯一外部 HTTP Entry Point。

### MongoDB

只监听：

```text
127.0.0.1:27017
```

不对外暴露。

### code-server

只通过 Nginx 访问。

### mongo-express

只通过 Nginx 访问。

### Node.js

只通过 Nginx 访问。

---

## 23. Platform

当前 MongoDB 安装方式依赖 MongoDB 官方 x86_64 Linux binary。

因此当前主要目标平台：

```text
linux/amd64
```

即：

```text
Synology x86_64
```

ARM64 Synology 暂不作为当前版本目标。

未来如果支持 ARM64，需要重新设计 MongoDB 安装方案。

---

# 24. Project Structure

当前项目建议保持：

```text
all-in-one-devcoding/
│
├── Dockerfile
├── README.md
│
├── docker/
│   ├── nginx/
│   │   └── nginx.conf
│   │
│   ├── services/
│   │   ├── nginx/
│   │   ├── mongodb/
│   │   ├── mongo-express/
│   │   └── node-app/
│   │
│   └── www/
│       └── index.html
│
└── .github/
    └── workflows/
        └── docker.yml
```

具体目录可以随着实现继续调整，但原则是：

> Dockerfile 负责构建环境，`docker/` 负责运行时配置和服务定义。

---

# 25. Development Workflow

典型开发流程：

```text
1. 启动 Container
       │
       ▼
2. 打开 code-server
       │
       ▼
3. 创建 /config/app
       │
       ▼
4. 开发 Node.js 项目
       │
       ▼
5. 使用 pnpm / yarn 安装依赖
       │
       ▼
6. PM2 / nodemon 启动应用
       │
       ▼
7. Nginx /app/ 提供访问
       │
       ▼
8. Node.js 连接 localhost MongoDB
```

---

# 26. Current Scope

当前版本明确包含：

* [x] Docker development environment
* [x] Nginx
* [x] code-server
* [x] Node.js 20
* [x] npm
* [x] pnpm
* [x] yarn
* [x] PM2
* [x] nodemon
* [x] MongoDB 7
* [x] mongo-express
* [x] Persistent `/config`
* [x] Nginx reverse proxy
* [x] Health Check
* [x] s6 service management

---

# 27. Not in Current Scope

以下功能暂时不实现：

* [ ] App Manager
* [ ] Control Plane
* [ ] TOTP
* [ ] Password Authentication
* [ ] User Management
* [ ] Application Registry
* [ ] Dynamic Application Ports
* [ ] Dynamic Nginx Routes
* [ ] Application Create/Delete
* [ ] Application Start/Stop UI
* [ ] Application Resource Monitoring
* [ ] Secret Management
* [ ] Multi-user Permission System

---

# 28. Future: App Manager

下一阶段将在当前 Runtime Environment 之上增加：

```text
                    Control Plane
                         │
                    App Manager
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
 Application         Nginx            TOTP/Auth
 Management          Routes           Management
        │                │                │
        ▼                ▼                ▼
       PM2            Nginx             Auth
```

App Manager 将成为整个系统的 **Control Plane**。

它负责：

```text
Application
    │
    ├── create
    ├── delete
    ├── enable
    ├── disable
    ├── start
    ├── stop
    ├── restart
    ├── port
    └── route
```

并负责管理：

```text
/config/apps/
```

以及：

```text
/config/nginx/routes/
```

---

# 29. Future Architecture

最终架构计划：

```text
                         Synology NAS
                              │
                              ▼
                         Reverse Proxy
                              │
                              ▼
                         ┌─────────┐
                         │  Nginx  │
                         │ Gateway │
                         └────┬────┘
                              │
             ┌────────────────┼─────────────────┐
             │                │                 │
             ▼                ▼                 ▼
       App Manager       code-server       mongo-express
       Control Plane        :8080              :8081
             │
             │
             ├──────────────► PM2
             │                  │
             │          ┌───────┼───────┐
             │          ▼       ▼       ▼
             │        App A   App B   App C
             │
             ├──────────────► Nginx Routes
             │
             └──────────────► TOTP / Auth
                                    │
                                    ▼
                               Authentication
```

---

# 30. Design Principles

## 30.1 Runtime 与 Control Plane 分离

当前：

```text
Runtime Plane
```

负责运行服务。

未来：

```text
Control Plane
```

负责管理服务。

两者不应该混在 Dockerfile 中。

---

## 30.2 Nginx 是入口

所有外部 HTTP 请求：

```text
Client
  │
  ▼
Nginx
  │
  ├── code-server
  ├── Node.js
  └── mongo-express
```

---

## 30.3 MongoDB 不对外暴露

MongoDB 只提供容器内部服务：

```text
127.0.0.1:27017
```

---

## 30.4 `/config` 是持久化边界

容器可以删除和重新创建。

只要：

```text
/config
```

仍然存在，用户数据就应该继续存在。

```text
Container
   │
   ├── delete
   ├── recreate
   └── update
          │
          ▼
       /config
          │
          ▼
       Persistent
```

---

## 30.5 Dockerfile 保持简单

Dockerfile 的目标：

> Build Runtime Environment.

而不是：

> Build the entire application management platform.

App Manager 应该在后续阶段独立设计。

---

# 31. Roadmap

## Phase 1 — Runtime Environment

当前阶段：

```text
[x] Nginx
[x] code-server
[x] Node.js
[x] PM2
[x] MongoDB
[x] mongo-express
[x] Persistent Storage
[x] Basic Health Check
```

---

## Phase 2 — App Manager

计划：

```text
[ ] App Manager UI
[ ] Application Registry
[ ] Application Create
[ ] Application Delete
[ ] Application Enable / Disable
[ ] PM2 Integration
[ ] Dynamic Port Allocation
[ ] Dynamic Nginx Routes
[ ] Application Status
```

---

## Phase 3 — Authentication

计划：

```text
[ ] TOTP
[ ] TOTP Secret Lifecycle
[ ] Password Fallback
[ ] Authentication Policy
[ ] Login Session
[ ] Credential Management
```

认证系统应该在 App Manager / Control Plane 架构明确以后再实现。

---

# 32. Final Architecture Goal

最终希望形成：

```text
┌──────────────────────────────────────────────┐
│              Synology DevCoding              │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │              Control Plane             │  │
│  │                                        │  │
│  │             App Manager               │  │
│  │                                        │  │
│  │  Apps │ Routes │ Auth │ Configuration │  │
│  └───────────────────┬────────────────────┘  │
│                      │                       │
│                      ▼                       │
│  ┌────────────────────────────────────────┐  │
│  │              Runtime Plane             │  │
│  │                                        │  │
│  │ Nginx │ code-server │ Node │ PM2       │  │
│  │                                        │  │
│  │ MongoDB │ mongo-express                │  │
│  └────────────────────────────────────────┘  │
│                      │                       │
│                      ▼                       │
│                /config                      │
│                  Persistent                 │
└──────────────────────────────────────────────┘
```

核心关系：

| Component     | Responsibility                   |
| ------------- | -------------------------------- |
| Docker        | Runtime Environment              |
| s6            | Service Lifecycle                |
| Nginx         | HTTP Entry Point / Reverse Proxy |
| code-server   | Web IDE                          |
| Node.js       | Application Runtime              |
| PM2           | Node.js Process Manager          |
| MongoDB       | Database                         |
| mongo-express | Database Web UI                  |
| `/config`     | Persistent Data                  |
| App Manager   | Future Control Plane             |

---

## License

待项目正式发布时补充。
