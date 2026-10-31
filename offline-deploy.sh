#!/usr/bin/env bash
# =============================================================================
#  MINGYINGKEJI · AgentSystem 离线授权版 · 一键部署系统  v3.0
# -----------------------------------------------------------------------------
#  · 完全离线：内置 9 个 Docker 镜像 tar，无需联网、无需本地构建
#  · 跨发行版：CentOS / RHEL / Rocky / AlmaLinux / Fedora / Ubuntu / Debian /
#              openSUSE / SLES / Arch / Alpine（需 bash）等
#  · 自动化链路：环境自检 → 资源/端口检查 → 配置生成 → 镜像导入 →
#                编排启动 → 健康探针 → 开机自启 → 访问自检 → 运维面板
#  · 幂等：可重复执行；已存在的配置、密钥、数据卷会被保留
# =============================================================================
set -Eeuo pipefail

# --- 以 bash 重新执行（避免被 sh/dash 调用时语法不兼容） ---------------------
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then exec bash "$0" "$@"; fi
  echo "需要 bash 才能运行本脚本（Alpine: apk add bash）" >&2
  exit 1
fi

# ------------------------------- 常量 ---------------------------------------
APP_NAME="AgentSystem"
APP_BRAND="MINGYINGKEJI"
APP_VERSION="1.1.0"
APP_BUILD="20261031"
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$INSTALL_DIR/docker"
IMAGES_DIR="$DOCKER_DIR/images"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.offline.yaml"
ENV_FILE="$DOCKER_DIR/.env"
ENV_TEMPLATE="$DOCKER_DIR/.env.template"
API_ENV_FILE="$INSTALL_DIR/api/.env.docker"
PROJECT_NAME="agentsystem"
SERVICE_NAME="agentsystem"
MANIFEST="$IMAGES_DIR/MANIFEST.txt"

PUBLIC_PORT="${PUBLIC_PORT:-2679}"
PUBLIC_URL_OVERRIDE=""
SKIP_IMAGES=0
NO_AUTOSTART=0
ASSUME_YES=0
START_TS=$(date +%s)
LOG_FILE="/var/log/${SERVICE_NAME}-deploy-$(date +%Y%m%d-%H%M%S).log"

# ------------------------------- 颜色 ---------------------------------------
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_RST=$'\033[0m'; C_BLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[1;31m'; C_GRN=$'\033[1;32m'; C_YEL=$'\033[1;33m'
  C_BLU=$'\033[1;34m'; C_MAG=$'\033[1;35m'; C_CYN=$'\033[1;36m'; C_WHT=$'\033[1;37m'
else
  C_RST=""; C_BLD=""; C_DIM=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_MAG=""; C_CYN=""; C_WHT=""
fi

# ------------------------------- 输出 ---------------------------------------
hr()      { printf "%s%s%s\n" "$C_MAG" "──────────────────────────────────────────────────────────────────────────────" "$C_RST"; }
hr_thin() { printf "%s%s%s\n" "$C_DIM" "╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌" "$C_RST"; }
info()    { printf "  %s▸%s %s\n" "$C_CYN" "$C_RST" "$*"; }
ok()      { printf "  %s✔%s %s\n" "$C_GRN" "$C_RST" "$*"; }
warn()    { printf "  %s▲%s %s\n" "$C_YEL" "$C_RST" "$*"; }
err()     { printf "  %s✘%s %s\n" "$C_RED" "$C_RST" "$*"; }
kv()      { printf "  %s%-14s%s %s\n" "$C_DIM" "$1" "$C_RST" "$2"; }
step() {
  local no="$1" total="$2" title="$3"
  printf "\n%s╔══════════════════════════════════════════════════════════════════════════════╗%s\n" "$C_BLU$C_BLD" "$C_RST"
  printf "%s║%s  %s%02d/%02d%s  %-66s%s║%s\n" "$C_BLU$C_BLD" "$C_RST" "$C_CYN$C_BLD" "$no" "$total" "$C_RST" "$title" "$C_BLU$C_BLD" "$C_RST"
  printf "%s╚══════════════════════════════════════════════════════════════════════════════╝%s\n" "$C_BLU$C_BLD" "$C_RST"
}
die() { err "$*"; printf "\n%s部署中断%s  ← 详见日志: %s\n\n" "$C_RED$C_BLD" "$C_RST" "$LOG_FILE"; exit 1; }

banner() {
  clear 2>/dev/null || true
  printf "%s" "$C_CYN"
  cat <<'BANNER'

    ███╗   ███╗██╗███╗   ██╗ ██████╗██╗   ██╗██╗███╗   ██╗ ██████╗
    ████╗ ████║██║████╗  ██║██╔════╝╚██╗ ██╔╝██║████╗  ██║██╔════╝
    ██╔████╔██║██║██╔██╗ ██║██║  ███╗ ╚████╔╝ ██║██╔██╗ ██║██║  ███╗
    ██║╚██╔╝██║██║██║╚██╗██║██║   ██║  ╚██╔╝  ██║██║╚██╗██║██║   ██║
    ██║ ╚═╝ ██║██║██║ ╚████║╚██████╔╝   ██║   ██║██║ ╚████║╚██████╔╝
    ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝
BANNER
  printf "%s" "$C_RST"
  printf "  %sAgentSystem · 离线授权版 · 一键部署系统%s\n" "$C_GRN$C_BLD" "$C_RST"
  hr
  kv "版本" "v${APP_VERSION} (build ${APP_BUILD})"
  kv "部署模式" "OFFLINE · 内置镜像 · 零网络依赖 · 零本地构建"
  kv "目标主机" "$(hostname -f 2>/dev/null || hostname)  [$(uname -m)]"
  kv "系统发行版" "$( . /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-unknown}" || echo unknown )"
  kv "内核版本" "$(uname -r)"
  kv "开始时间" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  hr
  printf "\n"
}

# ---------------------------- 小工具 ----------------------------------------
gen_hex() { od -An -tx1 -N"${1:-16}" /dev/urandom | tr -d ' \n'; }

detect_ip() {
  local ip=""
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')" || true
  if [ -z "$ip" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')" || true
  fi
  if [ -z "$ip" ]; then
    ip="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')" || true
  fi
  printf '%s' "${ip:-127.0.0.1}"
}

port_busy() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntH "sport = :$p" 2>/dev/null | grep -q . && return 0
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p$" && return 0
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 && return 0
  fi
  return 1
}

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time "${2:-3}" "$1" 2>/dev/null || true; }

usage() {
  cat <<EOF
${APP_NAME} 离线一键部署 v${APP_VERSION}

用法: sudo ./offline-deploy.sh [选项]

选项:
  --port <端口>        统一访问端口（默认 ${PUBLIC_PORT}）
  --public-url <URL>   指定对外访问地址（默认自动探测本机 IP，如 http://1.2.3.4:2679）
  --skip-images        跳过镜像导入（镜像已在本地仓库时使用）
  --no-autostart       不配置开机自启
  --yes, -y            非交互模式，所有确认自动通过
  -h, --help           显示本帮助

示例:
  sudo ./offline-deploy.sh
  sudo ./offline-deploy.sh --port 8080 --public-url http://10.0.0.8:8080
EOF
}

# 读取键值（.env 安全解析）
env_get() {
  local file="$1" key="$2" def="${3:-}" val
  [ -f "$file" ] || { printf '%s' "$def"; return; }
  val="$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d '\r' || true)"
  [ -n "$val" ] || val="$def"
  printf '%s' "$val"
}

env_set() {
  local file="$1" key="$2" val="$3"
  [ -f "$file" ] || : >"$file"
  if grep -qE "^[[:space:]]*${key}=" "$file"; then
    local esc="${val//\\/\\\\}"; esc="${esc//|/\\|}"
    sed -i.bak "s|^[[:space:]]*${key}=.*|${key}=${esc}|" "$file" && rm -f "${file}.bak"
  else
    printf '%s=%s\n' "$key" "$val" >>"$file"
  fi
}

# ------------------------- 01 环境与权限 ------------------------------------
check_environment() {
  step 1 12 "环境与权限自检 · Environment / Privileges"

  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 运行（sudo ./offline-deploy.sh）"
  fi
  ok "运行身份：root"

  local arch; arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) ok "CPU 架构：${arch}（镜像为 linux/amd64）" ;;
    *) warn "CPU 架构：${arch} —— 内置镜像为 amd64，非 amd64 主机需启用 qemu 模拟" ;;
  esac

  [ -f "$COMPOSE_FILE" ] || die "未找到编排文件：$COMPOSE_FILE（部署包不完整）"
  { [ -f "$ENV_TEMPLATE" ] || [ -f "$ENV_FILE" ]; } || die "缺少 docker/.env.template（部署包不完整）"
  [ -f "$API_ENV_FILE" ] || die "缺少 api/.env.docker（部署包不完整）"
  ok "部署包结构完整（编排文件 / 配置模板 / API 配置）"

  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  ok "部署日志：${LOG_FILE}"

  local cpus mem_mb
  cpus="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
  mem_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  if [ "$mem_mb" -ge 7800 ]; then ok "CPU ${cpus} 核 · 内存 ${mem_mb} MB（满足 ≥ 8GB）"
  else warn "CPU ${cpus} 核 · 内存 ${mem_mb} MB（低于建议 8GB，知识库/沙箱可能启动较慢）"; fi

  local free_mb
  free_mb="$(df -Pm "$INSTALL_DIR" | awk 'NR==2 {print $4}')"
  if [ "$free_mb" -ge 20000 ]; then ok "可用磁盘 ${free_mb} MB（满足 ≥ 20GB）"
  else warn "可用磁盘 ${free_mb} MB（建议 ≥ 20GB，镜像导入约需 12GB）"; fi
}

# ------------------------- 02 Docker ----------------------------------------
COMPOSE_BIN=""
check_docker() {
  step 2 12 "容器引擎探测 · Docker Engine"

  if command -v docker >/dev/null 2>&1; then
    ok "Docker CLI：$(docker --version 2>/dev/null | head -1)"
  else
    err "未检测到 Docker Engine"
    info "离线安装：将 docker-ce / containerd.io / docker-compose-plugin 的 rpm 或 deb 包拷入主机后安装"
    info "在线安装：curl -fsSL https://get.docker.com | sh"
    die "缺少 Docker，无法继续"
  fi

  if docker info >/dev/null 2>&1; then
    ok "Docker 守护进程运行中 · 存储驱动 $(docker info --format '{{.Driver}}' 2>/dev/null) · 版本 $(docker info --format '{{.ServerVersion}}' 2>/dev/null)"
  else
    info "尝试启动 Docker 守护进程..."
    ( systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true ) || true
    sleep 3
    docker info >/dev/null 2>&1 || die "Docker 守护进程未运行：systemctl start docker"
    ok "Docker 守护进程已启动"
  fi

  if systemctl list-unit-files 2>/dev/null | grep -q '^docker.service'; then
    systemctl enable docker >/dev/null 2>&1 && ok "docker.service 已设置为开机自启"
  fi
}

# ------------------------- 03 Compose ---------------------------------------
check_compose() {
  step 3 12 "编排工具探测 · Docker Compose"

  if docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN="docker compose"
    ok "Compose V2 插件：$(docker compose version --short 2>/dev/null || docker compose version 2>/dev/null | head -1)"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN="docker-compose"
    ok "Compose V1 独立二进制：$(docker-compose version --short 2>/dev/null || docker-compose version 2>/dev/null | head -1)"
  else
    err "未检测到 docker compose / docker-compose"
    info "离线安装：docker-compose-plugin（rpm/deb）或 docker-compose 单文件二进制复制到 /usr/local/bin/"
    die "缺少 Compose，无法继续"
  fi
}

compose() {
  if [ "$COMPOSE_BIN" = "docker compose" ]; then
    docker compose -p "$PROJECT_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  else
    docker-compose -p "$PROJECT_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  fi
}

# ------------------------- 04 端口 ------------------------------------------
check_ports() {
  step 4 12 "端口占用检查 · Port Availability"

  local -a ports=(
    "${PUBLIC_PORT}:统一入口(nginx)"
    "$(env_get "$ENV_FILE" API_PORT 2670):API"
    "$(env_get "$ENV_FILE" WEB_PORT 2680):Web"
    "$(env_get "$ENV_FILE" SANDBOX_PORT 2660):沙箱运行时"
    "$(env_get "$ENV_FILE" RUNNER_PORT 2665):插件运行时"
    "$(env_get "$ENV_FILE" POSTGRES_PORT 5434):PostgreSQL"
    "$(env_get "$ENV_FILE" REDIS_HOST_PORT 6381):Redis"
    "$(env_get "$ENV_FILE" WEAVIATE_PORT 18080):Weaviate"
    "$(env_get "$ENV_FILE" NEO4J_HTTP_PORT 7474):Neo4j HTTP"
    "$(env_get "$ENV_FILE" NEO4J_BOLT_PORT 7687):Neo4j Bolt"
  )

  local conflict=0 item port name
  for item in "${ports[@]}"; do
    port="${item%%:*}"; name="${item#*:}"
    if port_busy "$port"; then
      err "端口 ${port} 已被占用（${name}）"
      conflict=$((conflict+1))
    else
      ok "端口 ${port} 空闲（${name}）"
    fi
  done

  if [ "$conflict" -gt 0 ]; then
    info "如为旧版 AgentSystem 占用，请先执行彻底卸载："
    info "  ${C_WHT}bash $INSTALL_DIR/offline-uninstall.sh --yes${C_RST}"
    info "或改用其它端口：${C_WHT}bash $INSTALL_DIR/offline-deploy.sh --port 8080${C_RST}"
    die "存在 ${conflict} 个端口冲突"
  fi
}

# ------------------------- 05 配置生成 --------------------------------------
configure() {
  step 5 12 "运行配置生成 · Secrets / URLs / Feature Flags"

  if [ ! -f "$ENV_FILE" ]; then
    cp "$ENV_TEMPLATE" "$ENV_FILE"
    ok "已从模板创建 docker/.env"
  else
    ok "检测到既有 docker/.env，保留现有密钥与数据配置（幂等）"
  fi

  # 模板中未预置的密钥在此生成（部署包已内置一次性随机密钥，通常不再生成）
  local -A gen_map=(
    [POSTGRES_PASSWORD]=16 [REDIS_PASSWORD]=16 [NEO4J_PASSWORD]=12 [SECRET_KEY]=16 [PLUGIN_RUNNER_API_KEY]=16
  )
  local k generated=0
  for k in "${!gen_map[@]}"; do
    if [ -z "$(env_get "$ENV_FILE" "$k")" ]; then
      env_set "$ENV_FILE" "$k" "$(gen_hex "${gen_map[$k]}")"
      generated=$((generated+1))
    fi
  done
  if [ "$generated" -gt 0 ]; then ok "已生成缺失密钥 ${generated} 项（PostgreSQL / Redis / Neo4j / JWT / Runner）"
  else ok "密钥齐备（沿用部署包内置随机密钥）"; fi

  local ip public_url
  ip="$(detect_ip)"
  if [ -n "$PUBLIC_URL_OVERRIDE" ]; then
    public_url="${PUBLIC_URL_OVERRIDE%/}"
    ok "使用指定访问地址：${public_url}"
  else
    public_url="http://${ip}:${PUBLIC_PORT}"
    ok "自动探测访问地址：${public_url}"
  fi

  env_set "$ENV_FILE" PUBLIC_PORT "$PUBLIC_PORT"
  env_set "$ENV_FILE" PUBLIC_URL "$public_url"
  env_set "$ENV_FILE" WEB_API_CORS_ALLOW_ORIGINS "$public_url"

  # 连接中心（外部集成）默认开启；内网 HTTP 部署需要显式放行
  env_set "$ENV_FILE" EXTERNAL_INTEGRATIONS_ENABLED "true"
  env_set "$ENV_FILE" INTEGRATION_OAUTH_CALLBACK_URL "${public_url}/console/api/integrations/oauth/callback"
  env_set "$ENV_FILE" INTEGRATION_OAUTH_RESULT_URL "${public_url}/console/integrations/oauth/result"
  case "$public_url" in
    https://*) env_set "$ENV_FILE" INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP "false" ;;
    *)         env_set "$ENV_FILE" INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP "true"  ;;
  esac
  ok "连接中心：已启用（EXTERNAL_INTEGRATIONS_ENABLED=true）"
  ok "OAuth 回调：${public_url}/console/api/integrations/oauth/callback"

  # --- API 侧配置同步（密码 / URL / 迁移开关 / 集成开关） ---
  local pgpw redis_pw neo_pw secret
  pgpw="$(env_get "$ENV_FILE" POSTGRES_PASSWORD)"
  redis_pw="$(env_get "$ENV_FILE" REDIS_PASSWORD)"
  neo_pw="$(env_get "$ENV_FILE" NEO4J_PASSWORD)"
  secret="$(env_get "$ENV_FILE" SECRET_KEY)"

  local key
  for key in WAIT_FOR_DB MIGRATION_ENABLED SEED_ENABLED; do
    env_set "$API_ENV_FILE" "$key" "true"
  done
  ok "数据库迁移开关：WAIT_FOR_DB / MIGRATION_ENABLED / SEED_ENABLED = true"

  env_set "$API_ENV_FILE" DB_HOST "postgres"
  env_set "$API_ENV_FILE" DB_PORT "5432"
  env_set "$API_ENV_FILE" DB_USERNAME "postgres"
  env_set "$API_ENV_FILE" DB_NAME "$(env_get "$ENV_FILE" POSTGRES_DB mingyingkeji)"
  env_set "$API_ENV_FILE" DB_SSLMODE "disable"
  env_set "$API_ENV_FILE" DB_PASSWORD "$pgpw"
  env_set "$API_ENV_FILE" REDIS_HOST "redis"
  env_set "$API_ENV_FILE" REDIS_PORT "6379"
  env_set "$API_ENV_FILE" REDIS_PASSWORD "$redis_pw"
  env_set "$API_ENV_FILE" NEO4J_URI "bolt://neo4j:7687"
  env_set "$API_ENV_FILE" NEO4J_USERNAME "neo4j"
  env_set "$API_ENV_FILE" NEO4J_PASSWORD "$neo_pw"
  env_set "$API_ENV_FILE" SECRET_KEY "$secret"
  env_set "$API_ENV_FILE" PLUGIN_RUNNER_API_KEY "$(env_get "$ENV_FILE" PLUGIN_RUNNER_API_KEY)"
  env_set "$API_ENV_FILE" CONSOLE_API_URL "$public_url"
  env_set "$API_ENV_FILE" FILES_URL "$public_url"
  env_set "$API_ENV_FILE" WEB_API_CORS_ALLOW_ORIGINS "$public_url"

  env_set "$API_ENV_FILE" EXTERNAL_INTEGRATIONS_ENABLED "true"
  env_set "$API_ENV_FILE" INTEGRATION_OAUTH_CALLBACK_URL "${public_url}/console/api/integrations/oauth/callback"
  env_set "$API_ENV_FILE" INTEGRATION_OAUTH_RESULT_URL "${public_url}/console/integrations/oauth/result"
  case "$public_url" in
    https://*) env_set "$API_ENV_FILE" INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP "false" ;;
    *)         env_set "$API_ENV_FILE" INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP "true"  ;;
  esac
  ok "API 配置已同步（DB / Redis / Neo4j / 对外 URL / 集成开关）"

  # --- 插件运行时 / 沙箱 / Web 的凭据同步（与 docker/.env 保持一致） ---
  local runner_env="$INSTALL_DIR/runner/.env"
  if [ -f "$runner_env" ]; then
    env_set "$runner_env" EXECUTOR_API_KEY "$(env_get "$ENV_FILE" PLUGIN_RUNNER_API_KEY)"
    env_set "$runner_env" EXECUTOR_DB_PASSWORD "$pgpw"
    env_set "$runner_env" EXECUTOR_REDIS_PASSWORD "$redis_pw"
    env_set "$runner_env" EXECUTOR_DB_HOST "mingyingkeji-postgres"
    ok "插件运行时配置已同步：runner/.env"
  fi
  local sandbox_env="$INSTALL_DIR/sandbox/.env"
  if [ -f "$sandbox_env" ]; then
    env_set "$sandbox_env" POSTGRES_PASSWORD "$pgpw"
    ok "沙箱运行时配置已同步：sandbox/.env"
  fi

  # --- Web 侧配置 ---
  local web_env="$INSTALL_DIR/web/.env.local"
  if [ -f "$web_env" ]; then
    env_set "$web_env" NEXT_PUBLIC_API_URL "$public_url"
    env_set "$web_env" CONSOLE_API_URL "$public_url"
    env_set "$web_env" NEXT_PUBLIC_APP_NAME "$APP_BRAND"
    ok "Web 配置已同步：NEXT_PUBLIC_API_URL=${public_url}"
  else
    warn "未找到 web/.env.local（跳过 Web 侧 URL 同步）"
  fi

  cat >"$INSTALL_DIR/.deploy-meta" <<META
APP_NAME=${APP_NAME}
APP_VERSION=${APP_VERSION}
APP_BUILD=${APP_BUILD}
PUBLIC_URL=${public_url}
PUBLIC_PORT=${PUBLIC_PORT}
PROJECT_NAME=${PROJECT_NAME}
SERVICE_NAME=${SERVICE_NAME}
COMPOSE_BIN=${COMPOSE_BIN}
INSTALL_DIR=${INSTALL_DIR}
DEPLOYED_AT=$(date '+%Y-%m-%d %H:%M:%S')
META
  ok "部署元信息已写入 .deploy-meta"
}

# ------------------------- 06 镜像导入 --------------------------------------
import_images() {
  step 6 12 "离线镜像导入 · Bundled Images"

  if [ "$SKIP_IMAGES" -eq 1 ]; then
    warn "已按 --skip-images 跳过镜像导入"
    return 0
  fi
  [ -d "$IMAGES_DIR" ] || die "镜像目录不存在：$IMAGES_DIR"

  local -a tars=()
  local f
  for f in "$IMAGES_DIR"/*.tar; do [ -e "$f" ] && tars+=("$f"); done
  [ "${#tars[@]}" -gt 0 ] || die "镜像目录为空：$IMAGES_DIR"

  local total="${#tars[@]}" idx=0 loaded=0 skipped=0 t0 t1
  info "共 ${total} 个内置镜像包，逐个校验并导入..."

  for f in "${tars[@]}"; do
    idx=$((idx+1))
    local base size_s
    base="$(basename "$f")"
    size_s="$(du -h "$f" 2>/dev/null | cut -f1)"

    local want_img="" want_id="" have_id=""
    local manifest_line
    manifest_line="$(awk -F'|' -v n="$base" '$1==n {print $2"|"$3}' "$MANIFEST" 2>/dev/null | head -1 || true)"
    if [ -n "$manifest_line" ]; then
      want_img="${manifest_line%%|*}"
      want_id="${manifest_line##*|}"
      have_id="$(docker image inspect -f '{{.Id}}' "$want_img" 2>/dev/null | cut -c8-19 || true)"
    fi

    printf "  %s[%2d/%2d]%s %-56s %s%8s%s\n" "$C_CYN" "$idx" "$total" "$C_RST" "$base" "$C_DIM" "$size_s" "$C_RST"
    if [ -n "$want_id" ] && [ "$want_id" = "$have_id" ]; then
      printf "        %s↳ 已存在且校验一致，跳过导入%s\n" "$C_DIM" "$C_RST"
      skipped=$((skipped+1)); continue
    fi

    t0=$(date +%s)
    local out; out="$(docker load -i "$f" 2>&1)" || { printf '%s\n' "$out"; die "镜像导入失败：$base"; }
    t1=$(date +%s)
    loaded=$((loaded+1))
    local names; names="$(printf '%s\n' "$out" | sed -n 's/^Loaded image: //p' | paste -sd ', ' -)"
    printf "        %s↳ 导入完成 %2ds · %s%s\n" "$C_GRN" "$((t1-t0))" "${names:-ok}" "$C_RST"
  done

  ok "镜像导入完成：新导入 ${loaded} 个 / 已存在跳过 ${skipped} 个 / 共 ${total} 个"
}

# ------------------------- 07 镜像校验 --------------------------------------
verify_images() {
  step 7 12 "镜像完整性校验 · Integrity Check"

  local -a expect=(
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
  local miss=0 img sz
  printf "  %s%-42s %-12s %s%s\n" "$C_DIM" "IMAGE" "SIZE" "STATUS" "$C_RST"
  hr_thin
  for img in "${expect[@]}"; do
    if docker image inspect "$img" >/dev/null 2>&1; then
      sz="$(docker image inspect "$img" --format '{{.Size}}' 2>/dev/null | awk '{printf "%.0f MB", $1/1048576}')"
      printf "  %-42s %-12s %s✔ ready%s\n" "$img" "$sz" "$C_GRN" "$C_RST"
    else
      printf "  %-42s %-12s %s✘ missing%s\n" "$img" "-" "$C_RED" "$C_RST"
      miss=$((miss+1))
    fi
  done
  hr_thin
  [ "$miss" -eq 0 ] || die "缺失 ${miss} 个镜像，请确认部署包 docker/images/ 完整"
  ok "9 个核心镜像全部就绪"
}

# ------------------------- 08 启动 ------------------------------------------
start_stack() {
  step 8 12 "服务编排启动 · Orchestration"

  info "编排文件：docker/docker-compose.offline.yaml"
  info "编排项目：${PROJECT_NAME}"
  compose down --remove-orphans >/dev/null 2>&1 || true
  ok "已清理同名残留容器（数据卷保留）"

  if compose up -d --remove-orphans; then
    ok "容器编排指令已下发成功"
  else
    die "容器启动失败，请检查：${C_WHT}${COMPOSE_BIN} -p ${PROJECT_NAME} -f ${COMPOSE_FILE} logs${C_RST}"
  fi
}

# ------------------------- 09 健康检查 --------------------------------------
SERVICE_LIST="nginx api web postgres redis weaviate neo4j sandbox runner"
wait_healthy() {
  step 9 12 "服务健康探针 · Health Probes"

  local max_wait=360 elapsed=0
  local -A state=()
  while [ "$elapsed" -lt "$max_wait" ]; do
    local up=0 healthy=0 svc cid st health_now state_now
    for svc in $SERVICE_LIST; do
      cid="$(docker ps -aq -f "label=com.docker.compose.project=${PROJECT_NAME}" -f "label=com.docker.compose.service=${svc}" | head -1)"
      if [ -z "$cid" ]; then state[$svc]="missing"; continue; fi
      health_now="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo none)"
      state_now="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
      if [ "$health_now" = "none" ]; then
        # 无 healthcheck 的服务（weaviate 等）：running 即视为就绪
        if [ "$state_now" = "running" ]; then st="healthy"; else st="$state_now"; fi
      else
        st="$health_now"
      fi
      state[$svc]="$st"
      if [ "$st" = "healthy" ] || [ "$st" = "running" ]; then up=$((up+1)); fi
      if [ "$st" = "healthy" ]; then healthy=$((healthy+1)); fi
    done

    printf "\r  %s⏱%s 健康探针 %3ds/%3ds  ·  就绪 %d/9  ·  健康 %d/9   " \
      "$C_MAG" "$C_RST" "$elapsed" "$max_wait" "$up" "$healthy"
    if [ "$healthy" -ge 9 ]; then
      printf "\n"
      break
    fi
    sleep 4; elapsed=$((elapsed+4))
  done
  printf "\n"

  printf "  %s%-12s %-16s%s\n" "$C_DIM" "SERVICE" "STATE" "$C_RST"
  hr_thin
  local svc bad=0
  for svc in $SERVICE_LIST; do
    local st="${state[$svc]:-unknown}"
    case "$st" in
      healthy) printf "  %-12s %s● healthy%s\n" "$svc" "$C_GRN" "$C_RST" ;;
      running|starting) printf "  %-12s %s◐ %s%s\n" "$svc" "$C_YEL" "$st" "$C_RST"; bad=$((bad+1)) ;;
      *) printf "  %-12s %s✘ %s%s\n" "$svc" "$C_RED" "$st" "$C_RST"; bad=$((bad+1)) ;;
    esac
  done
  hr_thin

  if [ "$bad" -gt 0 ]; then
    warn "${bad} 个服务尚未完全就绪（部分重型服务首次启动需 2~5 分钟）"
    info "实时查看：${C_WHT}bash $INSTALL_DIR/offline-manage.sh logs api${C_RST}"
  else
    ok "9 个服务全部 healthy"
  fi
}

# ------------------------- 10 访问自检 --------------------------------------
verify_access() {
  step 10 12 "访问与初始化自检 · Access / Setup / License"

  local base="http://127.0.0.1:${PUBLIC_PORT}" i code=""
  for i in $(seq 1 40); do
    code="$(http_code "$base/healthz" 2)"
    [ "$code" = "200" ] && break
    sleep 2
  done
  if [ "$code" = "200" ]; then ok "统一入口 /healthz → 200"
  else warn "统一入口暂未响应（HTTP ${code:-000}），可能仍在启动"; fi

  local body step_val
  body="$(curl -s --max-time 6 "$base/console/api/setup" 2>/dev/null || true)"
  step_val="$(printf '%s' "$body" | sed -n 's/.*"step":"\([^"]*\)".*/\1/p')"
  case "$step_val" in
    not_started) ok "初始化状态：未初始化（首次访问 /init 创建管理员）" ;;
    finished)    ok "初始化状态：已完成（可直接登录控制台）" ;;
    "")          warn "初始化状态未知：$(printf '%s' "$body" | head -c 120)" ;;
    *)           ok "初始化状态：${step_val}" ;;
  esac

  body="$(curl -s --max-time 6 "$base/console/api/system-features" 2>/dev/null || true)"
  if printf '%s' "$body" | grep -q '"enable_external_integrations":true'; then
    ok "连接中心（外部集成）：已启用 —— 控制台「连接中心」不再锁定"
  else
    warn "连接中心开关未生效，请检查 api 日志"
    info "  docker logs ${PROJECT_NAME}-api-1 --tail 80"
  fi

  body="$(curl -s --max-time 6 "$base/console/api/license/status" 2>/dev/null || true)"
  case "$body" in
    *'"code":"ok"'*)
      case "$body" in
        *'"valid":true'*|*'"activated":true'*) ok "离线授权：已激活" ;;
        *) ok "授权接口可达（尚未激活，请在 /license 上传 license.lic）" ;;
      esac ;;
    *license_missing*) ok "授权接口可达：未上传 license.lic（在 /license 页面激活）" ;;
    "") warn "授权接口无响应" ;;
    *) ok "授权接口可达" ;;
  esac

  local tables db
  db="$(env_get "$ENV_FILE" POSTGRES_DB mingyingkeji)"
  tables="$(docker exec "${PROJECT_NAME}-postgres-1" psql -U postgres -d "$db" \
    -tAc "select count(*) from information_schema.tables where table_schema='public';" 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$tables" ] && [ "$tables" -gt 0 ] 2>/dev/null; then
    ok "数据库迁移：已建表 ${tables} 张"
  else
    warn "数据库表数量异常（${tables:-未知}），请检查 api 日志"
  fi
}

# ------------------------- 11 开机自启 --------------------------------------
setup_autostart() {
  step 11 12 "开机自启配置 · Boot Autostart"

  if [ "$NO_AUTOSTART" -eq 1 ]; then
    warn "已按 --no-autostart 跳过开机自启配置"
    return 0
  fi

  local exec_start exec_stop
  if [ "$COMPOSE_BIN" = "docker compose" ]; then
    exec_start="/usr/bin/docker compose -p ${PROJECT_NAME} --env-file ${ENV_FILE} -f ${COMPOSE_FILE} up -d"
    exec_stop="/usr/bin/docker compose -p ${PROJECT_NAME} --env-file ${ENV_FILE} -f ${COMPOSE_FILE} down"
  else
    exec_start="$(command -v docker-compose) -p ${PROJECT_NAME} --env-file ${ENV_FILE} -f ${COMPOSE_FILE} up -d"
    exec_stop="$(command -v docker-compose) -p ${PROJECT_NAME} --env-file ${ENV_FILE} -f ${COMPOSE_FILE} down"
  fi

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    local unit="/etc/systemd/system/${SERVICE_NAME}.service"
    cat >"$unit" <<UNIT
[Unit]
Description=${APP_BRAND} ${APP_NAME} Offline Stack (v${APP_VERSION})
Documentation=file://${INSTALL_DIR}/README.md
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${DOCKER_DIR}
ExecStartPre=-/usr/bin/docker compose -p ${PROJECT_NAME} --env-file ${ENV_FILE} -f ${COMPOSE_FILE} down --remove-orphans
ExecStart=${exec_start}
ExecStop=${exec_stop}
TimeoutStartSec=0
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload >/dev/null 2>&1 || true
    if systemctl enable "$SERVICE_NAME" >/dev/null 2>&1; then
      ok "systemd 单元已创建：${unit}"
      ok "开机自启：systemctl is-enabled ${SERVICE_NAME} → $(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || echo enabled)"
    else
      warn "systemctl enable 失败，请手动执行：systemctl enable ${SERVICE_NAME}"
    fi
    return 0
  fi

  if command -v rc-update >/dev/null 2>&1 && [ -f /etc/rc.local ]; then
    grep -q "$SERVICE_NAME" /etc/rc.local 2>/dev/null || \
      printf '\n# %s boot autostart\n%s\n' "$SERVICE_NAME" "$exec_start" >>/etc/rc.local
    chmod +x /etc/rc.local 2>/dev/null || true
    ok "已写入 /etc/rc.local 开机自启（OpenRC）"
    return 0
  fi
  if command -v crontab >/dev/null 2>&1; then
    ( crontab -l 2>/dev/null | grep -v "# ${SERVICE_NAME}-autostart" || true
      printf '@reboot sleep 20 && %s  # %s-autostart\n' "$exec_start" "$SERVICE_NAME"
    ) | crontab -
    ok "已写入 crontab @reboot 开机自启"
    return 0
  fi

  warn "未找到 systemd / rc.local / cron，跳过开机自启；请手工挂载启动命令"
}

# ------------------------- 12 总览 ------------------------------------------
final_panel() {
  step 12 12 "部署总览 · Deployment Summary"

  local elapsed=$(( $(date +%s) - START_TS ))
  local ip public_url
  ip="$(detect_ip)"
  public_url="$(env_get "$ENV_FILE" PUBLIC_URL "http://${ip}:${PUBLIC_PORT}")"

  printf "\n"
  printf "%s╔══════════════════════════════════════════════════════════════════════════════╗%s\n" "$C_GRN$C_BLD" "$C_RST"
  printf "%s║%s                                                                              %s║%s\n" "$C_GRN$C_BLD" "$C_RST" "$C_GRN$C_BLD" "$C_RST"
  printf "%s║%s        %s◆  DEPLOYMENT SUCCESSFUL · 部署成功%s                               %s║%s\n" "$C_GRN$C_BLD" "$C_RST" "$C_WHT$C_BLD" "$C_RST" "$C_GRN$C_BLD" "$C_RST"
  printf "%s║%s                                                                              %s║%s\n" "$C_GRN$C_BLD" "$C_RST" "$C_GRN$C_BLD" "$C_RST"
  printf "%s╚══════════════════════════════════════════════════════════════════════════════╝%s\n" "$C_GRN$C_BLD" "$C_RST"

  printf "\n%s▎访问入口 · ACCESS%s\n" "$C_CYN$C_BLD" "$C_RST"; hr_thin
  printf "  %s控制台%s        %s%s/console%s\n" "$C_DIM" "$C_RST" "$C_CYN" "$public_url" "$C_RST"
  printf "  %s初始化管理员%s  %s%s/init%s\n" "$C_DIM" "$C_RST" "$C_CYN" "$public_url" "$C_RST"
  printf "  %s离线授权%s      %s%s/license%s\n" "$C_DIM" "$C_RST" "$C_CYN" "$public_url" "$C_RST"
  printf "  %s连接中心%s      %s%s/console/integrations%s\n" "$C_DIM" "$C_RST" "$C_CYN" "$public_url" "$C_RST"
  printf "  %s本机访问%s      %shttp://127.0.0.1:%s%s\n" "$C_DIM" "$C_RST" "$C_CYN" "$PUBLIC_PORT" "$C_RST"

  printf "\n%s▎登录与初始化 · LOGIN%s\n" "$C_CYN$C_BLD" "$C_RST"; hr_thin
  printf "  1. 浏览器打开 %s%s/init%s\n" "$C_CYN" "$public_url" "$C_RST"
  printf "  2. 填写管理员邮箱 + 密码（≥8 位，含字母与数字）创建首个账号\n"
  printf "  3. 使用该邮箱 / 密码登录 %s%s/console%s\n" "$C_CYN" "$public_url" "$C_RST"
  printf "  %s说明：若已初始化过，直接使用原账号登录；密码遗失可在库中重置或重装。%s\n" "$C_DIM" "$C_RST"

  printf "\n%s▎离线授权 · LICENSE%s\n" "$C_CYN$C_BLD" "$C_RST"; hr_thin
  printf "  · 机器码获取：%sGET %s/console/api/license/machine-code%s\n" "$C_DIM" "$public_url" "$C_RST"
  printf "  · 授权文件持久化目录：%s/docker/conf（容器内 /app/conf/license.lic）\n" "$INSTALL_DIR"
  printf "  · 通用授权：machine_code 留空或写 \"*\"；机器绑定：使用上一步机器码\n"

  printf "\n%s▎运维命令 · OPERATIONS%s\n" "$C_CYN$C_BLD" "$C_RST"; hr_thin
  printf "  %-14s %s%s%s\n" "运维控制台" "$C_WHT" "bash ${INSTALL_DIR}/offline-manage.sh" "$C_RST"
  printf "  %-14s %s%s%s\n" "运行状态" "$C_WHT" "bash ${INSTALL_DIR}/offline-manage.sh status" "$C_RST"
  printf "  %-14s %s%s%s\n" "健康检查" "$C_WHT" "bash ${INSTALL_DIR}/offline-manage.sh health" "$C_RST"
  printf "  %-14s %s%s%s\n" "查看日志" "$C_WHT" "bash ${INSTALL_DIR}/offline-manage.sh logs api" "$C_RST"
  printf "  %-14s %s%s%s\n" "全部日志" "$C_WHT" "bash ${INSTALL_DIR}/offline-manage.sh logs-all" "$C_RST"
  printf "  %-14s %s%s%s\n" "重启服务" "$C_WHT" "bash ${INSTALL_DIR}/offline-manage.sh restart" "$C_RST"
  printf "  %-14s %s%s%s\n" "停止服务" "$C_WHT" "bash ${INSTALL_DIR}/offline-manage.sh stop" "$C_RST"
  printf "  %-14s %s%s%s\n" "启动服务" "$C_WHT" "bash ${INSTALL_DIR}/offline-manage.sh start" "$C_RST"
  printf "  %-14s %s%s%s\n" "配置备份" "$C_WHT" "bash ${INSTALL_DIR}/offline-manage.sh backup" "$C_RST"
  printf "  %-14s %s%s%s\n" "开机自启" "$C_WHT" "systemctl status ${SERVICE_NAME}" "$C_RST"
  printf "  %-14s %s%s%s\n" "彻底卸载" "$C_RED" "bash ${INSTALL_DIR}/offline-uninstall.sh" "$C_RST"

  printf "\n%s▎端口矩阵 · PORTS%s\n" "$C_CYN$C_BLD" "$C_RST"; hr_thin
  printf "  %-8s %-22s %-8s %-22s\n" "PORT" "SERVICE" "PORT" "SERVICE"
  printf "  %-8s %-22s %-8s %-22s\n" "${PUBLIC_PORT}" "nginx 统一入口" "$(env_get "$ENV_FILE" API_PORT 2670)" "api 后端"
  printf "  %-8s %-22s %-8s %-22s\n" "$(env_get "$ENV_FILE" WEB_PORT 2680)" "web 前端" "$(env_get "$ENV_FILE" SANDBOX_PORT 2660)" "sandbox 沙箱"
  printf "  %-8s %-22s %-8s %-22s\n" "$(env_get "$ENV_FILE" RUNNER_PORT 2665)" "runner 插件运行时" "$(env_get "$ENV_FILE" POSTGRES_PORT 5434)" "postgres"
  printf "  %-8s %-22s %-8s %-22s\n" "$(env_get "$ENV_FILE" REDIS_HOST_PORT 6381)" "redis" "$(env_get "$ENV_FILE" WEAVIATE_PORT 18080)" "weaviate"
  printf "  %-8s %-22s %-8s %-22s\n" "$(env_get "$ENV_FILE" NEO4J_HTTP_PORT 7474)" "neo4j http" "$(env_get "$ENV_FILE" NEO4J_BOLT_PORT 7687)" "neo4j bolt"

  printf "\n"
  hr
  printf "  %s部署完成%s · 版本 v%s · 模式 离线 · 耗时 %ss · 日志 %s\n" "$C_GRN$C_BLD" "$C_RST" "$APP_VERSION" "$elapsed" "$LOG_FILE"
  printf "  %s连接中心已在本次部署中默认启用，控制台侧边栏不再显示锁定图标。%s\n" "$C_DIM" "$C_RST"
  hr
  printf "\n"
}

# ------------------------------- main ---------------------------------------
main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --port) PUBLIC_PORT="${2:?--port 需要参数}"; shift 2 ;;
      --public-url) PUBLIC_URL_OVERRIDE="${2:?--public-url 需要参数}"; shift 2 ;;
      --skip-images) SKIP_IMAGES=1; shift ;;
      --no-autostart) NO_AUTOSTART=1; shift ;;
      --yes|-y) ASSUME_YES=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) err "未知参数：$1"; usage; exit 2 ;;
    esac
  done

  banner
  check_environment
  check_docker
  check_compose
  check_ports
  configure
  import_images
  verify_images
  start_stack
  wait_healthy
  verify_access
  setup_autostart
  final_panel
}

main "$@"
