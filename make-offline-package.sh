#!/usr/bin/env bash
# =============================================================================
#  AgentSystem 离线授权版 · 离线部署包构建脚本
#  -----------------------------------------------------------------------------
#  用途：在已导入 9 个镜像的主机上，把「源码 + 运行配置 + 镜像 tar + 部署/运维/
#        卸载脚本」打成一个可离线分发的一键部署包。
#
#  用法:
#     bash make-offline-package.sh [输出目录]        # 默认 /opt
#     bash make-offline-package.sh /data/dist
#
#  产物:
#     <输出目录>/AgentSystem-离线授权版-v<版本>/        部署目录
#     <输出目录>/AgentSystem-离线授权版-v<版本>.tar.gz  分发压缩包
# =============================================================================
set -Eeuo pipefail
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-/opt}"
APP_VERSION="1.1.0"
APP_BUILD="20261031"
PKG_NAME="AgentSystem-离线授权版-v${APP_VERSION}"
STAGE="$OUT_DIR/$PKG_NAME"
TARBALL="$OUT_DIR/${PKG_NAME}.tar.gz"

C_RST=$'\033[0m'; C_GRN=$'\033[1;32m'; C_CYN=$'\033[1;36m'; C_YEL=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'
ok()   { printf "  ${C_GRN}✔${C_RST} %s\n" "$*"; }
info() { printf "  ${C_CYN}▸${C_RST} %s\n" "$*"; }
warn() { printf "  ${C_YEL}▲${C_RST} %s\n" "$*"; }
die()  { printf "  ${C_RED}✘${C_RST} %s\n" "$*"; exit 1; }
hr()   { printf "${C_DIM}%s${C_RST}\n" "──────────────────────────────────────────────────────────────────────────────"; }

gen_hex() { od -An -tx1 -N"${1:-16}" /dev/urandom | tr -d ' \n'; }

# 安全地写入/覆盖 KEY=VALUE
put() {
  local file="$1" key="$2" val="$3"
  if grep -qE "^[[:space:]]*${key}=" "$file" 2>/dev/null; then
    local esc="${val//\\/\\\\}"; esc="${esc//|/\\|}"
    sed -i.bak "s|^[[:space:]]*${key}=.*|${key}=${esc}|" "$file" && rm -f "${file}.bak"
  else
    printf '%s=%s\n' "$key" "$val" >>"$file"
  fi
}

hr
printf "  ${C_BLD}AgentSystem 离线部署包构建${C_RST}  v${APP_VERSION} (build ${APP_BUILD})\n"
hr
info "源码目录 : $ROOT"
info "输出目录 : $OUT_DIR"
info "包名     : $PKG_NAME"

# --------------------------- 0. 前置检查 ------------------------------------
command -v docker >/dev/null 2>&1 || die "需要 docker"
docker info >/dev/null 2>&1 || die "docker 守护进程未运行"
for f in "$ROOT/offline-deploy.sh" "$ROOT/offline-manage.sh" "$ROOT/offline-uninstall.sh"; do
  [ -f "$f" ] || die "缺少脚本：$f"
done
[ -f "$ROOT/docker/docker-compose.offline.yaml" ] || die "缺少编排文件"
[ -f "$ROOT/docker/.env.example" ] || die "缺少 docker/.env.example"
[ -f "$ROOT/api/.env.docker.example" ] || die "缺少 api/.env.docker.example"
[ -f "$ROOT/runner/.env.example" ] || die "缺少 runner/.env.example"
[ -f "$ROOT/sandbox/.env.example" ] || die "缺少 sandbox/.env.example"
[ -f "$ROOT/web/.env.example" ] || die "缺少 web/.env.example"
ok "源文件检查通过"

# --------------------------- 1. 生成密钥 ------------------------------------
PGPW="$(gen_hex 16)"
REDISPW="$(gen_hex 16)"
NEOPW="$(gen_hex 12)"
SECRET="$(gen_hex 16)"
RUNNERKEY="$(gen_hex 16)"
ENCKEY="$(gen_hex 16)"
info "已生成一次性随机密钥（PostgreSQL / Redis / Neo4j / JWT / Runner / 加密密钥）"

# --------------------------- 2. 建目录 --------------------------------------
rm -rf -- "$STAGE"
mkdir -p "$STAGE"/{docker/images,docker/nginx,docker/postgres/init,api,web,runner,sandbox}
ok "构建目录：$STAGE"

# --------------------------- 3. 复制脚本与资产 ------------------------------
cp "$ROOT/offline-deploy.sh" "$STAGE/offline-deploy.sh"
cp "$ROOT/offline-manage.sh" "$STAGE/offline-manage.sh"
cp "$ROOT/offline-uninstall.sh" "$STAGE/offline-uninstall.sh"
chmod 755 "$STAGE"/*.sh

cp "$ROOT/docker/docker-compose.offline.yaml" "$STAGE/docker/"
cp -r "$ROOT/docker/nginx/." "$STAGE/docker/nginx/"
cp -r "$ROOT/docker/postgres/." "$STAGE/docker/postgres/"
ok "编排文件 / nginx / postgres 初始化脚本已复制"

if [ -f "$ROOT/README-OFFLINE.md" ]; then
  cp "$ROOT/README-OFFLINE.md" "$STAGE/README.md"
else
  printf 'AgentSystem 离线授权版 v%s\n' "$APP_VERSION" >"$STAGE/README.md"
fi
printf 'v%s (build %s)\n' "$APP_VERSION" "$APP_BUILD" >"$STAGE/VERSION"

# --------------------------- 4. 生成运行配置 --------------------------------
# 4.1 docker/.env.template
cp "$ROOT/docker/.env.example" "$STAGE/docker/.env.template"
put "$STAGE/docker/.env.template" COMPOSE_PROJECT_NAME "agentsystem"
put "$STAGE/docker/.env.template" PUBLIC_PORT "2679"
put "$STAGE/docker/.env.template" PUBLIC_URL "http://127.0.0.1:2679"
put "$STAGE/docker/.env.template" WEB_API_CORS_ALLOW_ORIGINS "http://127.0.0.1:2679"
put "$STAGE/docker/.env.template" POSTGRES_PASSWORD "$PGPW"
put "$STAGE/docker/.env.template" REDIS_PASSWORD "$REDISPW"
put "$STAGE/docker/.env.template" NEO4J_PASSWORD "$NEOPW"
put "$STAGE/docker/.env.template" SECRET_KEY "$SECRET"
put "$STAGE/docker/.env.template" EXTERNAL_INTEGRATIONS_ENABLED "true"
put "$STAGE/docker/.env.template" INTEGRATION_OAUTH_CALLBACK_URL "http://127.0.0.1:2679/console/api/integrations/oauth/callback"
put "$STAGE/docker/.env.template" INTEGRATION_OAUTH_RESULT_URL "http://127.0.0.1:2679/console/integrations/oauth/result"
put "$STAGE/docker/.env.template" INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP "true"
put "$STAGE/docker/.env.template" PLUGIN_RUNNER_API_KEY "$RUNNERKEY"
ok "docker/.env.template 已生成（连接中心默认开启）"

# 4.2 api/.env.docker
cp "$ROOT/api/.env.docker.example" "$STAGE/api/.env.docker"
A="$STAGE/api/.env.docker"
put "$A" SECRET_KEY "$SECRET"
put "$A" DB_HOST "postgres"
put "$A" DB_PORT "5432"
put "$A" DB_USERNAME "postgres"
put "$A" DB_NAME "mingyingkeji"
put "$A" DB_SSLMODE "disable"
put "$A" DB_PASSWORD "$PGPW"
put "$A" REDIS_HOST "redis"
put "$A" REDIS_PORT "6379"
put "$A" REDIS_PASSWORD "$REDISPW"
put "$A" NEO4J_URI "bolt://neo4j:7687"
put "$A" NEO4J_USERNAME "neo4j"
put "$A" NEO4J_PASSWORD "$NEOPW"
put "$A" WAIT_FOR_DB "true"
put "$A" MIGRATION_ENABLED "true"
put "$A" SEED_ENABLED "true"
put "$A" PLUGIN_RUNNER_API_KEY "$RUNNERKEY"
put "$A" API_KEY_ENCRYPTION_KEY "$ENCKEY"
put "$A" CONSOLE_API_URL "http://127.0.0.1:2679"
put "$A" FILES_URL "http://127.0.0.1:2679"
put "$A" WEB_API_CORS_ALLOW_ORIGINS "http://127.0.0.1:2679"
put "$A" EXTERNAL_INTEGRATIONS_ENABLED "true"
put "$A" INTEGRATION_OAUTH_CALLBACK_URL "http://127.0.0.1:2679/console/api/integrations/oauth/callback"
put "$A" INTEGRATION_OAUTH_RESULT_URL "http://127.0.0.1:2679/console/integrations/oauth/result"
put "$A" INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP "true"
put "$A" LICENSE_ENABLED "true"
ok "api/.env.docker 已生成（密码与 docker/.env 一致）"

# 4.3 runner/.env
cp "$ROOT/runner/.env.example" "$STAGE/runner/.env"
R="$STAGE/runner/.env"
printf '\n# ---- 离线部署包生成 %s ----\n' "$APP_BUILD" >>"$R"
printf 'EXECUTOR_API_KEY=%s\n' "$RUNNERKEY" >>"$R"
printf 'EXECUTOR_DB_PASSWORD=%s\n' "$PGPW" >>"$R"
printf 'EXECUTOR_REDIS_PASSWORD=%s\n' "$REDISPW" >>"$R"
ok "runner/.env 已生成"

# 4.4 sandbox/.env
cp "$ROOT/sandbox/.env.example" "$STAGE/sandbox/.env"
printf '\n# ---- 离线部署包生成 %s ----\n' "$APP_BUILD" >>"$STAGE/sandbox/.env"
printf 'POSTGRES_PASSWORD=%s\n' "$PGPW" >>"$STAGE/sandbox/.env"
ok "sandbox/.env 已生成"

# 4.5 web/.env.local
cp "$ROOT/web/.env.example" "$STAGE/web/.env.local"
put "$STAGE/web/.env.local" NEXT_PUBLIC_API_URL "http://127.0.0.1:2679"
put "$STAGE/web/.env.local" CONSOLE_API_URL "http://127.0.0.1:2679"
put "$STAGE/web/.env.local" NEXT_PUBLIC_APP_NAME "MINGYINGKEJI"
ok "web/.env.local 已生成"

# --------------------------- 5. 导出镜像 ------------------------------------
info "开始导出 9 个内置镜像（docker save）..."
IMAGES=(
  "mingyingkeji-api:latest"
  "mingyingkeji-web:latest"
  "mingyingkeji-sandbox:latest"
  "mingyingkeji-runner:latest"
  "nginx:1.27-alpine"
  "postgres:16-alpine"
  "redis:7-alpine"
  "neo4j:5.15-community"
  "semitechnologies/weaviate:1.38.2"
)
: >"$STAGE/docker/images/MANIFEST.txt"
for img in "${IMAGES[@]}"; do
  docker image inspect "$img" >/dev/null 2>&1 || die "本地缺少镜像：$img（请先导入或构建）"
  fname="$(printf '%s' "$img" | sed 's#[/:]#_#g').tar"
  short_id="$(docker image inspect -f '{{.Id}}' "$img" | cut -c8-19)"
  printf "  ${C_DIM}…${C_RST} %-42s → %s\n" "$img" "$fname"
  docker save -o "$STAGE/docker/images/$fname" "$img"
  printf '%s|%s|%s\n' "$fname" "$img" "$short_id" >>"$STAGE/docker/images/MANIFEST.txt"
done
ok "镜像导出完成，合计 $(du -sh "$STAGE/docker/images" | cut -f1)"

# --------------------------- 6. 打包 ----------------------------------------
chmod 600 "$STAGE"/api/.env.docker "$STAGE"/docker/.env.template "$STAGE"/runner/.env "$STAGE"/sandbox/.env "$STAGE"/web/.env.local 2>/dev/null || true
info "生成校验清单..."
( cd "$STAGE" && find . -type f ! -path './docker/images/*' -print0 | sort -z | xargs -0 sha256sum >CHECKSUMS.txt 2>/dev/null || true )

info "正在打包（约 3GB，视磁盘性能需 2~6 分钟）..."
rm -f "$TARBALL"
tar -C "$OUT_DIR" -czf "$TARBALL" "$PKG_NAME"

ok "部署目录：$STAGE"
ok "分发包  ：$TARBALL  ($(du -h "$TARBALL" | cut -f1))"
hr
printf "  分发与安装：\n"
printf "    scp %s root@<host>:/opt/\n" "$TARBALL"
printf "    ssh root@<host> 'tar -xzf /opt/%s.tar.gz -C /opt && cd /opt/%s && bash offline-deploy.sh'\n" "$PKG_NAME" "$PKG_NAME"
hr
