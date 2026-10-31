#!/usr/bin/env bash
# =============================================================================
#  AgentSystem 离线授权版 · 运维控制台  v1.1.0
#  用法: bash offline-manage.sh <command> [args]
# =============================================================================
set -Eeuo pipefail
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$INSTALL_DIR/docker"
ENV_FILE="$DOCKER_DIR/.env"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.offline.yaml"
API_ENV_FILE="$INSTALL_DIR/api/.env.docker"
META_FILE="$INSTALL_DIR/.deploy-meta"
PROJECT_NAME="agentsystem"
SERVICE_NAME="agentsystem"
BACKUP_DIR="$INSTALL_DIR/backups"

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_RST=$'\033[0m'; C_BLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[1;31m'; C_GRN=$'\033[1;32m'; C_YEL=$'\033[1;33m'
  C_BLU=$'\033[1;34m'; C_MAG=$'\033[1;35m'; C_CYN=$'\033[1;36m'; C_WHT=$'\033[1;37m'
else
  C_RST=""; C_BLD=""; C_DIM=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_MAG=""; C_CYN=""; C_WHT=""
fi

hr()      { printf "%s%s%s\n" "$C_MAG" "──────────────────────────────────────────────────────────────────────────────" "$C_RST"; }
hr_thin() { printf "%s%s%s\n" "$C_DIM" "╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌" "$C_RST"; }
ok()   { printf "  %s✔%s %s\n" "$C_GRN" "$C_RST" "$*"; }
warn() { printf "  %s▲%s %s\n" "$C_YEL" "$C_RST" "$*"; }
err()  { printf "  %s✘%s %s\n" "$C_RED" "$C_RST" "$*"; }
info() { printf "  %s▸%s %s\n" "$C_CYN" "$C_RST" "$*"; }

env_get() {
  local file="$1" key="$2" def="${3:-}" val=""
  [ -f "$file" ] && val="$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '\r' || true)"
  [ -n "$val" ] || val="$def"
  printf '%s' "$val"
}

COMPOSE_BIN=""
detect_compose() {
  if docker compose version >/dev/null 2>&1; then COMPOSE_BIN="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then COMPOSE_BIN="docker-compose"
  else err "未检测到 Docker Compose"; exit 1; fi
}

compose() {
  if [ "$COMPOSE_BIN" = "docker compose" ]; then
    docker compose -p "$PROJECT_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  else
    docker-compose -p "$PROJECT_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  fi
}

require_stack() {
  detect_compose
  [ -f "$COMPOSE_FILE" ] || { err "缺少编排文件：$COMPOSE_FILE"; exit 1; }
}

public_url() {
  local u; u="$(env_get "$ENV_FILE" PUBLIC_URL "")"
  if [ -z "$u" ]; then
    local p; p="$(env_get "$ENV_FILE" PUBLIC_PORT 2679)"
    u="http://127.0.0.1:${p}"
  fi
  printf '%s' "$u"
}

# ------------------------------- 命令 ---------------------------------------
cmd_status() {
  require_stack
  local url port
  url="$(public_url)"; port="$(env_get "$ENV_FILE" PUBLIC_PORT 2679)"
  hr
  printf "  %sAgentSystem · 运行状态%s   %s\n" "$C_CYN$C_BLD" "$C_RST" "$(date '+%Y-%m-%d %H:%M:%S')"
  hr
  printf "  %-12s %-10s %-22s %-10s %s\n" "SERVICE" "STATE" "HEALTH" "UPTIME" "IMAGE"
  hr_thin
  local svc cid st health up img
  for svc in nginx api web postgres redis weaviate neo4j sandbox runner; do
    cid="$(docker ps -aq -f "label=com.docker.compose.project=${PROJECT_NAME}" -f "label=com.docker.compose.service=${svc}" | head -1)"
    if [ -z "$cid" ]; then
      printf "  %-12s %s%-10s%s %-22s %-10s %s\n" "$svc" "$C_RED" "absent" "$C_RST" "-" "-" "-"
      continue
    fi
    st="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$cid" 2>/dev/null || echo n/a)"
    local started_s now_s up_s
    started_s="$(docker inspect -f '{{.State.StartedAt}}' "$cid" 2>/dev/null || true)"
    now_s="$(date -u +%Y-%m-%dT%H:%M:%S)"
    up="-"
    if [ -n "$started_s" ]; then
      local a b
      a="$(date -u -d "${started_s}" +%s 2>/dev/null || echo 0)"
      b="$(date -u -d "${now_s}" +%s 2>/dev/null || echo 0)"
      if [ "$a" -gt 0 ] && [ "$b" -ge "$a" ]; then
        local d=$(( b - a ))
        if [ "$d" -ge 86400 ]; then up="$((d/86400))d$(((d%86400)/3600))h"
        elif [ "$d" -ge 3600 ]; then up="$((d/3600))h$(((d%3600)/60))m"
        else up="$((d/60))m"; fi
      fi
    fi
    img="$(docker inspect -f '{{.Config.Image}}' "$cid" 2>/dev/null || echo -)"
    local color="$C_GRN"
    [ "$st" = "running" ] || color="$C_RED"
    [ "$health" = "unhealthy" ] && color="$C_RED"
    [ "$health" = "starting" ] && color="$C_YEL"
    printf "  %-12s %s%-10s%s %-22s %-10s %s\n" "$svc" "$color" "$st" "$C_RST" "$health" "$up" "$img"
  done
  hr_thin
  printf "  入口: %s%s%s   本机: %shttp://127.0.0.1:%s%s\n" "$C_CYN" "$url" "$C_RST" "$C_CYN" "$port" "$C_RST"
  printf "  自启: %s\n" "$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || echo '未配置')"
  hr
}

cmd_health() {
  require_stack
  local port base code
  port="$(env_get "$ENV_FILE" PUBLIC_PORT 2679)"
  base="http://127.0.0.1:${port}"
  hr
  printf "  %s健康探针 · Health Probes%s\n" "$C_CYN$C_BLD" "$C_RST"
  hr

  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$base/healthz" 2>/dev/null || true)"
  [ "$code" = "200" ] && ok "nginx /healthz → 200" || err "nginx /healthz → ${code:-000}"

  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$base/console/api/setup" 2>/dev/null || true)"
  [ "$code" = "200" ] && ok "api /console/api/setup → 200" || err "api /console/api/setup → ${code:-000}"

  local body
  body="$(curl -s --max-time 5 "$base/console/api/system-features" 2>/dev/null || true)"
  if printf '%s' "$body" | grep -q '"enable_external_integrations":true'; then
    ok "连接中心（外部集成）→ 已启用"
  else
    warn "连接中心（外部集成）→ 未启用"
  fi

  body="$(curl -s --max-time 5 "$base/console/api/setup" 2>/dev/null || true)"
  local st; st="$(printf '%s' "$body" | sed -n 's/.*"step":"\([^"]*\)".*/\1/p')"
  info "初始化状态：${st:-unknown}"

  body="$(curl -s --max-time 5 "$base/console/api/license/status" 2>/dev/null || true)"
  info "授权状态：$(printf '%s' "$body" | head -c 160)"
  hr
}

cmd_urls() {
  local url; url="$(public_url)"
  local ip; ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')" || true
  local port; port="$(env_get "$ENV_FILE" PUBLIC_PORT 2679)"
  hr
  printf "  %s访问入口 · Access%s\n" "$C_CYN$C_BLD" "$C_RST"
  hr
  printf "  %-10s %s\n" "控制台"   "${C_CYN}${url}/console${C_RST}"
  printf "  %-10s %s\n" "初始化"   "${C_CYN}${url}/init${C_RST}"
  printf "  %-10s %s\n" "授权"     "${C_CYN}${url}/license${C_RST}"
  printf "  %-10s %s\n" "连接中心" "${C_CYN}${url}/console/integrations${C_RST}"
  printf "  %-10s %s\n" "本机"     "http://127.0.0.1:${port}"
  [ -n "${ip:-}" ] && printf "  %-10s %s\n" "本机IP" "$ip"
  hr
}

cmd_logs() {
  require_stack
  local svc="${1:-}"; shift || true
  local follow=0
  for a in "$@"; do [ "$a" = "-f" ] || [ "$a" = "--follow" ] && follow=1; done
  if [ -z "$svc" ]; then
    err "用法: offline-manage.sh logs <服务名> [-f]"
    info "可用服务: nginx api web postgres redis weaviate neo4j sandbox runner"
    exit 2
  fi
  info "日志来源：${PROJECT_NAME}-${svc}-1    （Ctrl+C 退出）"
  if [ "$follow" -eq 1 ]; then compose logs -f --tail=200 "$svc"; else compose logs --tail=200 "$svc"; fi
}

cmd_logs_all() {
  require_stack
  info "全部服务日志（tail=120，Ctrl+C 退出）"
  compose logs --tail=120 -f
}

cmd_start()   { require_stack; info "启动服务栈..."; compose up -d --remove-orphans; ok "已启动"; cmd_status; }
cmd_stop()    { require_stack; info "停止服务栈（数据卷保留）..."; compose stop; ok "已停止"; }
cmd_restart() { require_stack; info "重启服务栈..."; compose restart; sleep 5; cmd_status; }
cmd_down()    { require_stack; info "移除容器与网络（数据卷保留）..."; compose down --remove-orphans; ok "已移除"; }

cmd_config() {
  hr
  printf "  %s运行配置 · Configuration%s\n" "$C_CYN$C_BLD" "$C_RST"
  hr
  printf "  安装目录  %s\n" "$INSTALL_DIR"
  printf "  编排文件  %s\n" "$COMPOSE_FILE"
  printf "  环境文件  %s\n" "$ENV_FILE"
  printf "  API 配置  %s\n" "$API_ENV_FILE"
  printf "  项目名    %s\n" "$PROJECT_NAME"
  hr_thin
  local k
  for k in PUBLIC_URL PUBLIC_PORT API_PORT WEB_PORT POSTGRES_PORT REDIS_HOST_PORT WEAVIATE_PORT NEO4J_HTTP_PORT NEO4J_BOLT_PORT EXTERNAL_INTEGRATIONS_ENABLED INTEGRATION_OAUTH_CALLBACK_URL INTEGRATION_OAUTH_ALLOW_INSECURE_HTTP; do
    printf "  %-38s %s\n" "$k" "$(env_get "$ENV_FILE" "$k" "-")"
  done
  hr_thin
  printf "  %s敏感项（密码 / 密钥）已省略，查看请直接编辑 %s%s\n" "$C_DIM" "$ENV_FILE" "$C_RST"
  hr
}

cmd_shell() {
  require_stack
  local svc="${1:-api}"
  info "进入容器 ${PROJECT_NAME}-${svc}-1 ..."
  docker exec -it "${PROJECT_NAME}-${svc}-1" sh -lc 'command -v bash >/dev/null && exec bash || exec sh'
}

cmd_db() {
  require_stack
  local db; db="$(env_get "$ENV_FILE" POSTGRES_DB mingyingkeji)"
  info "PostgreSQL 交互终端（数据库 ${db}，输入 \\q 退出）"
  docker exec -it "${PROJECT_NAME}-postgres-1" psql -U postgres -d "$db"
}

cmd_backup() {
  require_stack
  mkdir -p "$BACKUP_DIR"
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  local db; db="$(env_get "$ENV_FILE" POSTGRES_DB mingyingkeji)"
  local out="$BACKUP_DIR/agentsystem-backup-${ts}.tar.gz"
  local tmp="$BACKUP_DIR/.tmp-${ts}"
  mkdir -p "$tmp"
  info "导出数据库 ${db} ..."
  docker exec "${PROJECT_NAME}-postgres-1" pg_dump -U postgres -d "$db" >"$tmp/db.sql" || { err "pg_dump 失败"; rm -rf "$tmp"; exit 1; }
  ok "数据库已导出：$(du -h "$tmp/db.sql" | cut -f1)"
  cp "$ENV_FILE" "$tmp/docker.env" 2>/dev/null || true
  cp "$API_ENV_FILE" "$tmp/api.env.docker" 2>/dev/null || true
  cp "$META_FILE" "$tmp/deploy-meta" 2>/dev/null || true
  tar -czf "$out" -C "$tmp" . && rm -rf "$tmp"
  ok "备份完成：$out ($(du -h "$out" | cut -f1))"
  info "恢复：bash $INSTALL_DIR/offline-manage.sh restore $out"
}

cmd_restore() {
  require_stack
  local file="${1:-}"
  [ -n "$file" ] || { err "用法: offline-manage.sh restore <备份文件.tar.gz>"; exit 2; }
  [ -f "$file" ] || { err "文件不存在：$file"; exit 2; }
  local tmp; tmp="$(mktemp -d)"
  tar -xzf "$file" -C "$tmp"
  [ -f "$tmp/db.sql" ] || { err "备份包中没有 db.sql"; rm -rf "$tmp"; exit 1; }
  local db; db="$(env_get "$ENV_FILE" POSTGRES_DB mingyingkeji)"
  warn "即将覆盖数据库 ${db} 的现有数据，5 秒后开始（Ctrl+C 取消）"
  sleep 5
  docker exec -i "${PROJECT_NAME}-postgres-1" psql -U postgres -d "$db" <"$tmp/db.sql" >/dev/null
  rm -rf "$tmp"
  ok "数据库已恢复，建议重启 api：bash $INSTALL_DIR/offline-manage.sh restart"
}

cmd_doctor() {
  hr
  printf "  %s环境诊断 · Doctor%s\n" "$C_CYN$C_BLD" "$C_RST"
  hr
  printf "  %-24s %s\n" "OS" "$( . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo unknown)"
  printf "  %-24s %s\n" "Kernel" "$(uname -r)"
  printf "  %-24s %s\n" "Docker" "$(docker --version 2>/dev/null || echo '未安装')"
  printf "  %-24s %s\n" "Compose" "$(docker compose version --short 2>/dev/null || docker-compose version --short 2>/dev/null || echo '未安装')"
  printf "  %-24s %s\n" "磁盘可用" "$(df -h "$INSTALL_DIR" | awk 'NR==2 {print $4}')"
  printf "  %-24s %s\n" "内存" "$(free -h 2>/dev/null | awk '/Mem:/ {print $2" total / "$7" available"}' || echo unknown)"
  hr_thin
  local url; url="$(public_url)"
  printf "  %s入口连通性%s\n" "$C_CYN" "$C_RST"
  printf "  %-24s %s\n" "/healthz" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$url/healthz" 2>/dev/null || echo 000)"
  printf "  %-24s %s\n" "/console" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$url/console" 2>/dev/null || echo 000)"
  printf "  %-24s %s\n" "/console/api/system-features" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$url/console/api/system-features" 2>/dev/null || echo 000)"
  hr
}

cmd_version() {
  local v b
  v="$(env_get "$META_FILE" APP_VERSION "1.1.0")"
  b="$(env_get "$META_FILE" APP_BUILD "20261031")"
  printf "AgentSystem 离线授权版 v%s (build %s)\n" "$v" "$b"
}

usage() {
  cat <<EOF
${C_CYN}AgentSystem 运维控制台${C_RST}

用法: bash offline-manage.sh <command> [args]

  ${C_WHT}status${C_RST}                服务状态总览（状态 / 健康 / 启动时间 / 镜像）
  ${C_WHT}health${C_RST}                健康探针（入口 / API / 连接中心 / 授权 / 初始化）
  ${C_WHT}urls${C_RST}                  打印全部访问入口
  ${C_WHT}start${C_RST}                 启动服务栈
  ${C_WHT}stop${C_RST}                  停止服务栈（保留数据）
  ${C_WHT}restart${C_RST}               重启服务栈
  ${C_WHT}down${C_RST}                  移除容器与网络（保留数据卷）
  ${C_WHT}logs <svc> [-f]${C_RST}       查看指定服务日志（nginx api web postgres redis
                              weaviate neo4j sandbox runner）
  ${C_WHT}logs-all${C_RST}              跟踪全部服务日志
  ${C_WHT}config${C_RST}                查看运行配置
  ${C_WHT}shell <svc>${C_RST}           进入容器（默认 api）
  ${C_WHT}db${C_RST}                    PostgreSQL 交互终端
  ${C_WHT}backup${C_RST}                备份数据库 + 配置到 backups/
  ${C_WHT}restore <file>${C_RST}        从备份包恢复数据库
  ${C_WHT}doctor${C_RST}                环境与连通性诊断
  ${C_WHT}version${C_RST}               版本信息
  ${C_RED}uninstall${C_RST}             彻底卸载（等同 offline-uninstall.sh）

示例:
  bash offline-manage.sh logs api -f
  bash offline-manage.sh backup
EOF
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    status|ps)      cmd_status "$@" ;;
    health)         cmd_health "$@" ;;
    urls)           cmd_urls "$@" ;;
    start|up)       cmd_start "$@" ;;
    stop)           cmd_stop "$@" ;;
    restart)        cmd_restart "$@" ;;
    down)           cmd_down "$@" ;;
    logs|log)       cmd_logs "$@" ;;
    logs-all)       cmd_logs_all "$@" ;;
    config)         cmd_config "$@" ;;
    shell)          cmd_shell "$@" ;;
    db)             cmd_db "$@" ;;
    backup)         cmd_backup "$@" ;;
    restore)        cmd_restore "$@" ;;
    doctor)         cmd_doctor "$@" ;;
    version|--version|-v) cmd_version ;;
    uninstall)      exec bash "$INSTALL_DIR/offline-uninstall.sh" "$@" ;;
    ""|-h|--help|help) usage ;;
    *) err "未知命令：$cmd"; echo; usage; exit 2 ;;
  esac
}

main "$@"
