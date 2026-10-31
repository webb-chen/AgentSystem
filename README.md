# MINGYINGKEJI · AgentSystem 离线授权版

AgentSystem 是一套自托管的多租户 AI 应用平台（Go API + Next.js 控制台 + 沙箱 / 插件运行时 +
PostgreSQL / Redis / Neo4j / Weaviate）。本仓库包含完整源码，以及**完全离线**的一键部署工具链：
内置全部 Docker 镜像，部署过程**无需联网拉取镜像、无需本地构建**，适用于无外网 / 内网隔离 /
各类 Linux 发行版环境。

---

## 一、目录结构

```
AgentSystem/
├── offline-deploy.sh                  # 离线一键部署（12 阶段自检 + 镜像导入 + 编排 + 自启）
├── offline-manage.sh                  # 运维控制台（状态/健康/日志/备份/恢复/诊断）
├── offline-uninstall.sh               # 彻底卸载（容器/卷/镜像/服务/目录/日志）
├── make-offline-package.sh            # 构建离线部署包（源码 + 运行配置 + 镜像 tar）
├── README-OFFLINE.md                  # 离线部署包使用手册
├── deploy.sh                          # 在线/开发环境部署脚本
├── api/                               # Go 后端（含数据库迁移）
├── web/                               # Next.js 前端
├── runner/                            # 插件运行时（Go）
├── sandbox/                           # 代码执行沙箱（Python）
├── docker/
│   ├── docker-compose.offline.yaml    # 离线编排（纯镜像，无 build）
│   ├── .env.example                   # 运行环境模板
│   ├── nginx/nginx.conf               # 统一入口反代
│   └── postgres/init/*.sh             # 多库初始化
├── docs/ dev/ scripts/                # 文档、开发脚本、工具脚本
└── lien/                              # 离线授权公钥与示例（不含私钥）
```

---

## 二、环境要求

| 项目 | 最低要求 | 推荐 |
|------|---------|------|
| 操作系统 | 主流 Linux（CentOS / RHEL / Rocky / Alma / Ubuntu / Debian / Fedora / openSUSE / Arch） | CentOS Stream 9 / Ubuntu 22.04 |
| 架构 | x86_64 (amd64) | x86_64 |
| Docker Engine | 20.10+ | 24.x+ |
| Docker Compose | v2 插件（或 v1 独立二进制） | v2 |
| 内存 | 8 GB | 16 GB+ |
| 磁盘可用空间 | 20 GB | 40 GB+ |

> 离线主机需预先安装 Docker（`docker-ce` + `docker-compose-plugin` 的 rpm/deb）。

---

## 三、离线一键部署

```bash
tar -xzf AgentSystem-离线授权版-v1.1.0.tar.gz -C /opt
cd /opt/AgentSystem-离线授权版-v1.1.0
sudo bash offline-deploy.sh
```

部署脚本共 12 个阶段：

```
01 环境与权限自检     05 运行配置生成      09 服务健康探针
02 Docker 引擎探测    06 离线镜像导入      10 访问/初始化/授权自检
03 Compose 探测       07 镜像完整性校验    11 开机自启（systemd→rc.local→cron）
04 端口占用检查       08 服务编排启动      12 部署总览（入口/命令/端口矩阵）
```

常用参数：`--port 8080`、`--public-url http://host:2679`、`--skip-images`、`--no-autostart`。
脚本幂等，重复执行不会破坏数据卷与既有密钥。

---

## 四、访问、登录与授权

| 用途 | 地址 |
|------|------|
| 控制台 | `http://<IP>:2679/console` |
| 初始化管理员 | `http://<IP>:2679/init` |
| 离线授权 | `http://<IP>:2679/license` |
| 连接中心 | `http://<IP>:2679/console/integrations` |

系统默认开启授权校验（`LICENSE_ENABLED=true`）。首次访问跳转 `/license`：

1. 授权页查看机器码（或 `GET /console/api/license/machine-code`）；
2. 由统一授权平台（ULP）签发 `license.lic`：
   通用授权 machine_code 留空或写 `"*"`；机器绑定授权填入机器码；
3. 上传 `license.lic` 立即生效。产品标识固定 `agent-system`。

授权文件持久化在命名卷 `api-conf`（容器内 `/app/conf/license.lic`），重建容器不丢失。

---

## 五、连接中心（外部集成）

连接中心由 `EXTERNAL_INTEGRATIONS_ENABLED` 控制，**本项目部署包默认开启**：

```dotenv
EXTERNAL_INTEGRATIONS_ENABLED=true
INTEGRATION_OAUTH_CALLBACK_URL=http://<PUBLIC_URL>/console/api/integrations/oauth/callback
INTEGRATION_OAUTH_RESULT_URL=http://<PUBLIC_URL>/console/integrations/oauth/result
INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP=true   # 内网 HTTP 部署时必需
```

`INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP` 为显式放行项：API 校验 OAuth 回调时必须为 HTTPS
或 loopback HTTP；纯内网 HTTP 部署（如 `http://192.168.1.10:2679`）打开该开关后即可正常启动，
启动日志会打印一条警告。若前置 HTTPS 反代，请保持为 `false`。

---

## 六、运维命令

```bash
bash offline-manage.sh                 # 命令总览
bash offline-manage.sh status          # 服务状态 / 健康 / 启动时间 / 镜像
bash offline-manage.sh health          # 入口、API、连接中心、授权、初始化探针
bash offline-manage.sh logs api -f     # 实时日志（nginx web postgres redis weaviate neo4j sandbox runner）
bash offline-manage.sh restart         # 重启整栈
bash offline-manage.sh backup          # 备份数据库 + 配置
bash offline-manage.sh doctor          # 环境诊断
systemctl status agentsystem           # 开机自启单元
```

---

## 七、彻底卸载

```bash
sudo bash offline-uninstall.sh          # 交互确认
sudo bash offline-uninstall.sh --yes    # 无人值守
```

删除：容器、数据卷、网络、9 个镜像、systemd 单元、crontab / rc.local 条目、安装目录、
部署日志，并清理旧版 `/opt/AgentSystem-离线授权版-v1.0` 的残留。
可选：`--keep-data`、`--keep-images`、`--keep-dir`、`--purge-source`、`--dry-run`。

---

## 八、端口说明

| 端口 | 服务 | 说明 |
|------|------|------|
| 2679 | nginx | 统一访问入口 |
| 2670 | api | 后端 API |
| 2680 | web | 前端 Next.js |
| 2660 | sandbox | 代码执行沙箱 |
| 2665 | runner | 插件运行时 |
| 5434 | postgres | 数据库 |
| 6381 | redis | 缓存 |
| 7474 / 7687 | neo4j | 图数据库 |
| 18080 | weaviate | 向量库 |

---

## 九、开发

```bash
make setup        # 安装依赖
make dev-api      # 后端热重载
make dev-web      # 前端 dev server
make dev-docker   # 本地全栈（含知识库/沙箱/插件运行时）
```

后端使用 Go 1.26 + Gin + Fx；前端使用 Next.js 15 + TypeScript + Tailwind。
数据库迁移在 API 启动时自动执行（`MIGRATION_ENABLED=true`）。

---

## 十、变更记录

### v1.1.0 (2026-10-31)

1. **修复「连接中心」菜单锁定、无法进入**：控制台侧边栏的锁由
   `system-features.enable_external_integrations` 驱动，原部署包
   `EXTERNAL_INTEGRATIONS_ENABLED=false` 导致功能被判定为「管理员未启用」。
   - 部署配置默认开启连接中心，并自动注入 OAuth 回调 / 结果地址；
   - 新增 `INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP`（默认 `false`）：允许纯内网 HTTP 部署
     通过 OAuth 回调地址校验，避免 API 因
     `INTEGRATION_OAUTH_CALLBACK_URL must be an HTTPS URL or a loopback HTTP URL` 启动失败；
   - 启动日志在放行时打印显式警告，便于安全审计；
   - 新增回归测试 `TestExternalIntegrationsConfigIntranetHTTPOptIn`、
     `TestExternalIntegrationOAuthDeploymentAllowsIntranetHTTPOptIn`。
2. **离线部署工具链重写**：`offline-deploy.sh`（12 阶段、幂等、开机自启、
   跨发行版）、`offline-manage.sh`（运维控制台）、`offline-uninstall.sh`（彻底卸载）。
3. **配置一致性**：部署时自动同步 `docker/.env` 与 `api/.env.docker`、
   `runner/.env`、`sandbox/.env` 的数据库 / Redis / Runner 密钥，避免手动改密码后
   API 反复重启。
4. **Neo4j 凭据下发**：`api/.env.docker` 的 `NEO4J_PASSWORD` 与 `docker/.env` 保持一致。

### v1.0.7-fixed

1. 图片/文件 URL 使用 `PUBLIC_URL` 动态下发，修复生成图片在客户端 404。
2. 视频生成适配 OpenAI 兼容 `/v1/videos/generations` 上游。

---

## 十一、许可

Apache-2.0 / 商业授权双许可，详见 `LICENSE` 与 `LICENSE-APACHE`。
