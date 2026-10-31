# Changelog

All notable MINGYINGKEJI changes are documented in this file.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html) for public
release tags.

## [1.1.0] - 2026-10-31

### Fixed

- 控制台「连接中心」菜单被锁定、无法点击：`system-features.enable_external_integrations`
  恒为 `false`（部署包默认 `EXTERNAL_INTEGRATIONS_ENABLED=false`），前端将其判定为
  「管理员未启用」并渲染锁图标。离线部署配置默认开启外部集成，并自动下发
  OAuth 回调 / 结果地址（`INTEGRATION_OAUTH_CALLBACK_URL`、
  `INTEGRATION_OAUTH_RESULT_URL`）。

### Added

- `INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP`（默认 `false`）：显式允许内网 HTTP 部署使用
  非 HTTPS 的 OAuth 回调地址。此前 `config` 校验要求 HTTPS 或 loopback，纯内网
  HTTP 部署会在启动时 panic（`INTEGRATION_OAUTH_CALLBACK_URL must be an HTTPS URL
  or a loopback HTTP URL`）。放行时启动日志输出安全警告。
- 回归测试：`TestExternalIntegrationsConfigIntranetHTTPOptIn`、
  `TestExternalIntegrationOAuthDeploymentAllowsIntranetHTTPOptIn`。
- `offline-manage.sh` 运维控制台（状态 / 健康 / 日志 / 备份 / 恢复 / 诊断 / 重启）。
- `offline-uninstall.sh` 彻底卸载（容器 / 卷 / 网络 / 镜像 / 服务单元 / 目录 / 日志，
  兼容清理旧版 `AgentSystem-离线授权版-v1.0`）。

### Changed

- `offline-deploy.sh` 重写为 12 阶段、幂等、跨发行版的一键部署：镜像按 MANIFEST 校验
  幂等导入、端口预检、配置一致性同步（`docker/.env` ↔ `api/.env.docker` →
  `runner/.env` / `sandbox/.env`）、systemd（rc.local / cron 兜底）开机自启、
  访问与连接中心自检。
- 离线编排（`docker-compose.offline.yaml` / 模板）支持
  `INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP`，OAuth URL 默认派生自 `PUBLIC_URL`。

## [Unreleased]

### Added

- Docker release workflow for API, web, sandbox, and runner images.
- Public migration check command for validating migration IDs, filenames,
  dangerous statements, and fresh PostgreSQL execution.

### Changed

- v1.0.7-fixed: 图片生成文件 URL 修复。api/.env.docker 与 docker/.env 的
  FILES_URL / PUBLIC_URL 默认改为 0.0.0.0 占位符，deploy.sh 新增
  update_dynamic_urls() 在部署时自动替换为实际服务器 IP，
  避免浏览器把 localhost 解析到本机导致图片/文件加载失败。
- v1.0.7-fixed: 视频生成适配确认。OpenAI 兼容适配器已支持
  POST /v1/videos/generations 端点（openai.go / mingyingkeji_cloud.go）。
  若上游网关返回 task_plugin_system_disabled，需在网关侧启用任务插件系统。
- Docker Compose starts the full local experience by default. A core-only mode
  is available for lighter development.
- Public database migrations now use a Go migration baseline plus append-only
  timestamped migration files.

### Security

- Open source hygiene checks block local agent state, secrets, generated
  runtime data, and unexpected binary files from release candidates.

## Release Notes

Release notes are written from `.github/RELEASE_TEMPLATE.md` and summarized in
this changelog after each release.
