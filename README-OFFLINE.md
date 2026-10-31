# AgentSystem · 离线授权版 v1.1.0

> 一键离线部署包（Docker）· 内置 9 个镜像 · 零网络依赖 · 零本地构建 · 开机自启 · 完整运维与卸载

---

## 1. 这是什么

本目录是一个**完全离线**的 AgentSystem 部署包：

| 组成 | 说明 |
|------|------|
| `offline-deploy.sh` | 一键部署（自检 → 导入镜像 → 生成配置 → 编排启动 → 健康探针 → 开机自启） |
| `offline-manage.sh` | 运维控制台（状态 / 健康 / 日志 / 备份 / 恢复 / 诊断 / 重启 / 停止） |
| `offline-uninstall.sh` | 彻底卸载（容器 / 数据卷 / 镜像 / 服务单元 / 目录 / 日志，一次清空） |
| `docker/images/*.tar` | 9 个内置 Docker 镜像（api / web / sandbox / runner / nginx / postgres / redis / neo4j / weaviate） |
| `docker/` | 编排文件、nginx 反代配置、PostgreSQL 初始化脚本、`.env.template` |
| `api/ runner/ sandbox/ web/` | 各服务运行配置（`.env`） |

**部署过程不需要联网、不需要 `docker pull`、不需要本地构建镜像。**

---

## 2. 环境要求

| 项目 | 最低 | 建议 |
|------|------|------|
| 操作系统 | CentOS 7+/RHEL 8+/Rocky/Alma/Ubuntu 18.04+/Debian 11+/Fedora/openSUSE/Arch（Alpine 需 `apk add bash`） | CentOS Stream 9 / Ubuntu 22.04 |
| CPU 架构 | x86_64 (amd64) | 4 核+ |
| 内存 | 8 GB | 16 GB |
| 磁盘 | 20 GB 可用 | 40 GB |
| Docker | 20.10+（含 `docker compose` 或 `docker-compose`） | 24.x + Compose V2 |

> Docker 本身需自行准备（离线环境请预先安装 `docker-ce` + `docker-compose-plugin` 的 rpm/deb）。
> 一键脚本会检测并给出提示，不会联网安装。

---

## 3. 一键部署

```bash
# 1) 解包
tar -xzf AgentSystem-离线授权版-v1.1.0.tar.gz -C /opt
cd /opt/AgentSystem-离线授权版-v1.1.0

# 2) 一键部署（默认端口 2679，自动探测本机 IP）
sudo bash offline-deploy.sh

# 可选参数
sudo bash offline-deploy.sh --port 8080                       # 换端口
sudo bash offline-deploy.sh --public-url http://10.0.0.8:2679 # 指定对外地址（反代/域名场景）
sudo bash offline-deploy.sh --skip-images                     # 镜像已在本地，跳过导入
sudo bash offline-deploy.sh --no-autostart                    # 不配置开机自启
```

脚本会依次完成 **12 个阶段** 并输出彩色进度面板：

```
 01 环境与权限自检        07 镜像完整性校验
 02 Docker 引擎探测       08 服务编排启动
 03 Docker Compose 探测   09 服务健康探针（9 个容器）
 04 端口占用检查          10 访问 / 初始化 / 授权自检
 05 运行配置生成          11 开机自启（systemd → rc.local → cron 兜底）
 06 离线镜像导入          12 部署总览（访问地址 / 运维命令 / 端口矩阵）
```

**幂等**：重复执行不会破坏已有数据卷、密钥与配置。

---

## 4. 访问与登录

部署完成后终端会打印完整入口，形如：

| 用途 | 地址 |
|------|------|
| 控制台 | `http://<服务器IP>:2679/console` |
| 初始化管理员 | `http://<服务器IP>:2679/init` |
| 离线授权 | `http://<服务器IP>:2679/license` |
| 连接中心 | `http://<服务器IP>:2679/console/integrations` |

**首次使用**：打开 `/init` 创建管理员邮箱与密码 → 用该账号登录 `/console`。
若系统已初始化，直接使用原账号登录。

**离线授权**：`GET /console/api/license/machine-code` 获取机器码 → 交给授权管理员签发
`license.lic`（通用授权 machine_code 留空或写 `*`）→ 在 `/license` 页面上传。
授权文件持久化在 `docker/conf`（容器卷 `api-conf`），重建容器不丢失。

---

## 5. 连接中心（外部集成）

本版本**默认开启**连接中心，控制台侧边栏「连接中心」不再显示锁定图标：

* `EXTERNAL_INTEGRATIONS_ENABLED=true`
* `INTEGRATION_OAUTH_CALLBACK_URL=<PUBLIC_URL>/console/api/integrations/oauth/callback`
* `INTEGRATION_OAUTH_RESULT_URL=<PUBLIC_URL>/console/integrations/oauth/result`
* 内网 HTTP 部署时自动设置 `INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP=true`
  （API 默认要求 HTTPS 或 loopback，本开关是显式的内网放行项；若使用 HTTPS 反代，
  脚本会自动关闭它）

> 若浏览器仍显示旧状态，请强制刷新（`Ctrl+F5`）或清理站点数据：
> 前端会缓存 `/system-features` 结果，刷新后即恢复。

---

## 6. 运维命令

```bash
bash offline-manage.sh                 # 帮助 / 命令总览
bash offline-manage.sh status          # 服务状态总览（状态/健康/启动时间/镜像）
bash offline-manage.sh health          # 健康探针（入口/API/连接中心/授权/初始化）
bash offline-manage.sh urls            # 打印全部访问入口
bash offline-manage.sh logs api -f     # 实时查看 API 日志（nginx/web/postgres/redis/…）
bash offline-manage.sh logs-all        # 跟踪全部服务日志
bash offline-manage.sh restart         # 重启服务栈
bash offline-manage.sh stop            # 停止（保留数据）
bash offline-manage.sh start           # 启动
bash offline-manage.sh config          # 查看运行配置
bash offline-manage.sh shell api       # 进入容器
bash offline-manage.sh db              # PostgreSQL 终端
bash offline-manage.sh backup          # 备份数据库+配置到 backups/
bash offline-manage.sh restore <file>  # 从备份恢复
bash offline-manage.sh doctor          # 环境与连通性诊断
```

开机自启：

```bash
systemctl status agentsystem     # 查看
systemctl restart agentsystem    # 重启整栈
systemctl disable agentsystem    # 关闭自启
```

---

## 7. 彻底卸载

```bash
sudo bash offline-uninstall.sh          # 交互确认后全量删除
sudo bash offline-uninstall.sh --yes    # 无人值守
```

删除范围：容器、数据卷（数据库/文件/授权）、网络、9 个镜像、systemd 单元、
crontab/rc.local 条目、安装目录、部署日志；并会顺带清理旧版
`/opt/AgentSystem-离线授权版-v1.0` 的残留容器、数据卷与镜像。

可选参数：`--keep-data`（保留数据卷）、`--keep-images`、`--keep-dir`、
`--purge-source`（连源码目录与历史安装包一起删）、`--dry-run`（只预览）。

---

## 8. 端口矩阵

| 端口 | 服务 | 说明 |
|------|------|------|
| 2679 | nginx | **统一入口**（控制台 / API / 文件） |
| 2670 | api | Go 后端 |
| 2680 | web | Next.js 前端 |
| 2660 | sandbox | 沙箱运行时 |
| 2665 | runner | 插件运行时 |
| 5434 | postgres | 数据库 |
| 6381 | redis | 缓存 |
| 7474 / 7687 | neo4j | 图数据库 |
| 18080 | weaviate | 向量库 |

端口可在 `docker/.env` 中调整，或用 `--port` 改变统一入口端口。

---

## 9. 常见问题

**Q：提示端口被占用？**
旧版本仍在运行。先执行 `sudo bash offline-uninstall.sh --yes`，或换端口 `--port 8080`。

**Q：api 容器反复重启？**
`bash offline-manage.sh logs api`。常见原因：`.env` 与 `api/.env.docker` 的数据库密码不一致
（重新执行 `offline-deploy.sh` 会自动同步）。

**Q：连接中心仍然带锁？**
1. `curl http://127.0.0.1:2679/console/api/system-features | grep external` 应为 `true`；
2. 浏览器 `Ctrl+F5` 强刷；
3. 若为旧部署，请确认使用的是本 v1.1.0 部署包（v1.0 默认关闭该能力且 `api` 镜像不含内网 HTTP 放行逻辑）。

**Q：能否迁移数据？**
`offline-manage.sh backup` 生成 `backups/agentsystem-backup-*.tar.gz`（含 `db.sql` 与配置），
在新环境部署后 `offline-manage.sh restore <file>` 即可。

---

## 10. 目录结构

```
AgentSystem-离线授权版-v1.1.0/
├── offline-deploy.sh          # 一键部署
├── offline-manage.sh          # 运维控制台
├── offline-uninstall.sh       # 彻底卸载
├── README.md / VERSION / CHECKSUMS.txt
├── api/.env.docker            # API 运行配置
├── runner/.env                # 插件运行时配置
├── sandbox/.env               # 沙箱运行时配置
├── web/.env.local             # Web 运行配置
└── docker/
    ├── docker-compose.offline.yaml
    ├── .env.template          # 部署时生成 .env（密钥已内置）
    ├── nginx/nginx.conf
    ├── postgres/init/01-init-multiple-dbs.sh
    └── images/*.tar           # 9 个内置镜像 + MANIFEST.txt
```
