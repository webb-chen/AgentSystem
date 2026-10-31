#!/usr/bin/env bash
#
# ============================================================================
#  MINGYINGKEJI · AgentSystem 离线一键部署脚本
#  无需联网拉取镜像、无需本地构建，直接从 images/*.tar 导入并启动。
#  支持主流 Linux 发行版（CentOS / Ubuntu / Debian / Fedora / openSUSE 等）。
# ============================================================================
set -euo pipefail

# ------------------------- 脚本定位 -------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$SCRIPT_DIR/docker"
IMAGES_DIR="$DOCKER_DIR/images"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.offline.yaml"
ENV_FILE="$DOCKER_DIR/.env"

# ------------------------- 颜色定义 -------------------------
C_RESET=$'\033[0m'
C_CYAN=$'\033[1;36m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_RED=$'\033[1;31m'
C_BLUE=$'\033[1;34m'
C_MAGENTA=$'\033[1;35m'
C_DIM=$'\033[2m'
C_BOLD=$'\033[1m'

# ------------------------- 全局状态 -------------------------
START_TS=$(date +%s)
DOCKER_OK=false
COMPOSE_OK=false

# ------------------------- 工具函数 -------------------------
log_info()  { printf "${C_CYAN}[ · ]${C_RESET} %s\n" "$1"; }
log_ok()    { printf "${C_GREEN}[ ✓ ]${C_RESET} %s\n" "$1"; }
log_warn()  { printf "${C_YELLOW}[ ! ]${C_RESET} %s\n" "$1"; }
log_err()   { printf "${C_RED}[ ✗ ]${C_RESET} %s\n" "$1"; }
log_step()  { printf "\n${C_BLUE}${C_BOLD}▸ %s${C_RESET}\n" "$1"; }

# 科技感分隔线
divider() {
  printf "${C_MAGENTA}────────────────────────────────────────────────────────────────────${C_RESET}\n"
}

# 打印横幅
banner() {
  clear 2>/dev/null || true
  printf "${C_CYAN}${C_BOLD}"
  cat <<'EOF'

   ███╗   ███╗██╗███╗   ██╗ ██████╗██╗   ██╗██╗███╗   ██╗ ██████╗
   ████╗ ████║██║████╗  ██║██╔════╝╝██╗ ██╔╝██║████╗  ██║██╔════╝
   ██╔████╔██║██║██╔██╗ ██║██║  ███╗╚████╔╝ ██║██╔██╗ ██║██║  ███╗
   ██║╚██╔╝██║██║██║╚██╗██║██║   ██║ ╚██╔╝  ██║██║╚██╗██║██║   ██║
   ██║ ╚═╝ ██║██║██║ ╚████║╚██████╔╝  ██║   ██║██║ ╚████║╚██████╔╝
   ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝   ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝

EOF
  printf "${C_RESET}"
  printf "${C_GREEN}${C_BOLD}        AgentSystem · 离线授权版 · 一键部署系统${C_RESET}\n"
  divider
  printf "${C_DIM}  部署脚本版本 : v1.0.0\n"
  printf "  部署模式     : 离线（本地镜像导入，无网络依赖）\n"
  printf "  启动时间     : $(date '+%Y-%m-%d %H:%M:%S')\n${C_RESET}"
  divider
  printf "\n"
}

# 检测 docker
check_docker() {
  log_step "01 · 环境自检 · Docker 引擎"
  if command -v docker >/dev/null 2>&1; then
    local dv
    dv="$(docker --version 2>/dev/null | head -1)"
    log_ok "Docker 已安装 → ${dv}"
    if docker info >/dev/null 2>&1; then
      DOCKER_OK=true
      log_ok "Docker 守护进程运行正常"
    else
      log_err "Docker 守护进程未运行，请先执行 systemctl start docker"
      exit 1
    fi
  else
    log_err "未检测到 Docker，请先安装 Docker Engine"
    log_info "安装参考：https://docs.docker.com/engine/install/"
    exit 1
  fi
}

# 检测 docker compose
check_compose() {
  log_step "02 · 环境自检 · Docker Compose"
  if docker compose version >/dev/null 2>&1; then
    local cv
    cv="$(docker compose version 2>/dev/null | head -1)"
    COMPOSE_OK=true
    log_ok "Docker Compose 插件可用 → ${cv}"
  elif command -v docker-compose >/dev/null 2>&1; then
    local cv
    cv="$(docker-compose version 2>/dev/null | head -1)"
    COMPOSE_OK=true
    log_ok "docker-compose（旧版独立二进制）可用 → ${cv}"
  else
    log_err "未检测到 docker compose，请安装 Compose 插件"
    exit 1
  fi
}

# 磁盘空间检测
check_disk() {
  log_step "03 · 资源检查 · 磁盘空间"
  local need_mb free_mb
  need_mb=25000   # 约 25G（导入镜像 + 运行数据）
  free_mb="$(df -m "$SCRIPT_DIR" | awk 'NR==2 {print $4}')"
  if [ "$free_mb" -lt "$need_mb" ]; then
    log_warn "当前可用磁盘 ${free_mb}MB，建议至少 ${need_mb}MB（25GB）"
    log_warn "空间不足可能导致导入失败，请清理磁盘后重试"
  else
    log_ok "可用磁盘空间 ${free_mb}MB，满足部署要求"
  fi
  local cpu_mem
  cpu_mem="$(free -m | awk '/Mem:/ {print $2}')"
  log_ok "系统内存总量 ${cpu_mem}MB"
  if [ "$cpu_mem" -lt 8192 ]; then
    log_warn "内存小于 8GB，知识库/沙箱等重型服务可能启动缓慢或失败"
  fi
}

# 导入镜像（带进度显示）
import_images() {
  log_step "04 · 离线镜像导入"
  local total=0 done=0
  local -a tars=()
  for f in "$IMAGES_DIR"/*.tar; do
    [ -e "$f" ] || continue
    tars+=("$f")
    total=$((total+1))
  done
  if [ "$total" -eq 0 ]; then
    log_err "未在 ${IMAGES_DIR} 找到任何 .tar 镜像文件"
    exit 1
  fi
  log_info "共发现 ${total} 个离线镜像包，开始导入..."
  for f in "${tars[@]}"; do
    done=$((done+1))
    local name size
    name="$(basename "$f" .tar)"
    size="$(du -h "$f" | cut -f1)"
    printf "  ${C_CYAN}[%2d/%2d]${C_RESET} 正在导入 ${C_BOLD}%-40s${C_RESET} (${size})\n" "$done" "$total" "$name"
    if docker load -i "$f" >/tmp/mingyingkeji_load.log 2>&1; then
      log_ok "导入成功 → ${name}"
    else
      log_err "导入失败 → ${name}"
      cat /tmp/mingyingkeji_load.log
      exit 1
    fi
  done
  rm -f /tmp/mingyingkeji_load.log
  log_ok "全部镜像导入完成"
}

# 校验镜像完整性
verify_images() {
  log_step "05 · 镜像完整性校验"
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
  local missing=0
  for img in "${expect[@]}"; do
    if docker image inspect "$img" >/dev/null 2>&1; then
      printf "  ${C_GREEN}✓${C_RESET} %s\n" "$img"
    else
      printf "  ${C_RED}✗${C_RESET} %s ${C_RED}(缺失)${C_RESET}\n" "$img"
      missing=$((missing+1))
    fi
  done
  if [ "$missing" -gt 0 ]; then
    log_err "有 ${missing} 个镜像缺失，部署中止"
    exit 1
  fi
  log_ok "9 个核心镜像全部就绪"
}

# 自动检测服务器 IP，动态更新 FILES_URL / PUBLIC_URL / INTEGRATION_OAUTH_CALLBACK_URL
# 修复：默认 localhost 会导致浏览器把图片/文件 URL 解析到本机而加载失败
update_dynamic_urls() {
  log_step "05.5 · 网络适配 · 动态 URL 配置"
  local api_env="$SCRIPT_DIR/api/.env.docker"
  local server_ip=""
  server_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  if [ -n "$server_ip" ]; then
    local public_port url_prefix
    public_port="$(grep -E '^PUBLIC_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d '\r' || true)"
    public_port="${public_port:-2679}"
    url_prefix="http://${server_ip}:${public_port}"

    if [ -f "$api_env" ]; then
      if grep -q '^FILES_URL=' "$api_env"; then
        local current_files_url
        current_files_url="$(grep '^FILES_URL=' "$api_env" | tail -n 1 | cut -d= -f2- | tr -d '\r')"
        case "$current_files_url" in
          *localhost*|*0.0.0.0*|"")
            sed -i.bak "s|^FILES_URL=.*|FILES_URL=${url_prefix}|" "$api_env"
            rm -f "${api_env}.bak"
            log_ok "FILES_URL → ${url_prefix}"
            ;;
          *)
            log_info "FILES_URL 已配置（${current_files_url}），保留现有值"
            ;;
        esac
      else
        printf '\nFILES_URL=%s\n' "$url_prefix" >> "$api_env"
        log_ok "FILES_URL → ${url_prefix}（已追加）"
      fi

      if grep -q '^INTEGRATION_OAUTH_CALLBACK_URL=' "$api_env"; then
        local current_oauth
        current_oauth="$(grep '^INTEGRATION_OAUTH_CALLBACK_URL=' "$api_env" | tail -n 1 | cut -d= -f2- | tr -d '\r')"
        case "$current_oauth" in
          *localhost*|*0.0.0.0*|"")
            sed -i.bak "s|^INTEGRATION_OAUTH_CALLBACK_URL=.*|INTEGRATION_OAUTH_CALLBACK_URL=${url_prefix}/console/api/integrations/oauth/callback|" "$api_env"
            rm -f "${api_env}.bak"
            log_ok "INTEGRATION_OAUTH_CALLBACK_URL → ${url_prefix}/console/api/..."
            ;;
        esac
      fi
    fi

    if [ -f "$ENV_FILE" ]; then
      if grep -q '^PUBLIC_URL=' "$ENV_FILE"; then
        local current_public_url
        current_public_url="$(grep '^PUBLIC_URL=' "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d '\r')"
        case "$current_public_url" in
          *localhost*|*0.0.0.0*|"")
            sed -i.bak "s|^PUBLIC_URL=.*|PUBLIC_URL=${url_prefix}|" "$ENV_FILE"
            rm -f "${ENV_FILE}.bak"
            log_ok "PUBLIC_URL → ${url_prefix}"
            ;;
        esac
      fi
      if grep -q '^WEB_API_CORS_ALLOW_ORIGINS=' "$ENV_FILE"; then
        local current_cors
        current_cors="$(grep '^WEB_API_CORS_ALLOW_ORIGINS=' "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d '\r')"
        case "$current_cors" in
          *localhost*|*0.0.0.0*|"")
            sed -i.bak "s|^WEB_API_CORS_ALLOW_ORIGINS=.*|WEB_API_CORS_ALLOW_ORIGINS=${url_prefix}|" "$ENV_FILE"
            rm -f "${ENV_FILE}.bak"
            log_ok "WEB_API_CORS_ALLOW_ORIGINS → ${url_prefix}"
            ;;
        esac
      fi
    fi
  else
    log_warn "未检测到服务器 IP，请手动检查 FILES_URL 配置"
  fi
}

# 启动服务
start_services() {
  log_step "06 · 启动服务栈"
  cd "$DOCKER_DIR"
  log_info "使用 Compose 文件：$(basename "$COMPOSE_FILE")"
  log_info "使用环境配置：.env"
  log_info "正在后台启动所有服务（含知识库 / 沙箱运行时）..."
  if docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d; then
    log_ok "服务栈已提交启动指令"
  else
    log_err "服务启动失败，请检查上方错误输出"
    exit 1
  fi
}

# 等待并展示服务状态
wait_and_status() {
  log_step "07 · 服务健康检查（实时）"
  cd "$DOCKER_DIR"
  local elapsed=0 max_wait=300
  printf "\n"
  while [ "$elapsed" -lt "$max_wait" ]; do
    local line
    printf "${C_CYAN}  ⏱ 已等待 %3ds / %3ds${C_RESET}\n" "$elapsed" "$max_wait"
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | \
      awk -v cyan="$C_CYAN" -v green="$C_GREEN" -v yellow="$C_YELLOW" -v red="$C_RED" -v reset="$C_RESET" '
      NR==1 { print "  " cyan $0 reset }
      NR>1 {
        if ($0 ~ /healthy|Up \(healthy\)/) { print "  " green $0 reset }
        else if ($0 ~ /starting|Starting|created|Created/) { print "  " yellow $0 reset }
        else if ($0 ~ /unhealthy|Exited|Restarting/) { print "  " red $0 reset }
        else { print "  " $0 }
      }'
    # 检查是否全部 healthy
    local unhealthy
    unhealthy="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -a 2>/dev/null | awk 'NR>1 && ($0 ~ /unhealthy|Exited|Restarting/) {c++} END {print c+0}')"
    local total_svc
    total_svc="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -a 2>/dev/null | awk 'NR>1 {c++} END {print c+0}')"
    local healthy
    healthy="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps 2>/dev/null | awk 'NR>1 && $0 ~ /healthy/ {c++} END {print c+0}')"
    if [ "$unhealthy" -gt 0 ]; then
      log_err "检测到 ${unhealthy} 个服务异常，等待重试中..."
    elif [ "$healthy" -ge "$total_svc" ] && [ "$total_svc" -gt 0 ]; then
      printf "\n"
      log_ok "全部 ${total_svc} 个服务均已进入 healthy 状态"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed+5))
    printf "\033[%dA\033[2K" 3  # 上移清屏重绘
  done
  log_warn "等待超时（${max_wait}s），部分服务可能仍在启动，可稍后手动检查"
}

# 打印最终信息
final_summary() {
  local end_ts elapsed
  end_ts=$(date +%s)
  elapsed=$((end_ts - START_TS))
  local public_port
  public_port="$(grep -E '^PUBLIC_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d '\r')"
  public_port="${public_port:-2679}"
  printf "\n"
  divider
  printf "${C_GREEN}${C_BOLD}  ◆ 部署完成 ◆${C_RESET}\n"
  divider
  printf "${C_BOLD}  访问入口:${C_RESET} ${C_CYAN}http://<服务器IP>:${public_port}${C_RESET}\n"
  printf "${C_BOLD}  本机访问:${C_RESET} ${C_CYAN}http://localhost:${public_port}${C_RESET}\n"
  printf "\n"
  printf "${C_YELLOW}  ⚠  离线授权提示:${C_RESET}\n"
  printf "     系统默认已开启统一授权（LICENSE_ENABLED=true）。\n"
  printf "     首次访问会跳转到授权页 ${C_CYAN}/license${C_RESET}，\n"
  printf "     机器绑定授权请复制机器码交给统一授权平台管理员；通用授权可直接上传 license.lic。\n"
  printf "\n"
  printf "${C_DIM}  常用命令:${C_RESET}\n"
  printf "     查看状态 : cd docker && docker compose -f docker-compose.offline.yaml ps\n"
  printf "     查看日志 : cd docker && docker compose -f docker-compose.offline.yaml logs -f <服务名>\n"
  printf "     停止服务 : cd docker && docker compose -f docker-compose.offline.yaml down\n"
  printf "     重启服务 : cd docker && docker compose -f docker-compose.offline.yaml restart\n"
  printf "\n"
  divider
  printf "${C_GREEN}  总耗时 ${elapsed}s · 祝您使用愉快${C_RESET}\n"
  divider
}

# ------------------------- 主流程 -------------------------
main() {
  banner
  check_docker
  check_compose
  check_disk
  import_images
  verify_images
  update_dynamic_urls
  start_services
  wait_and_status
  final_summary
}

main "$@"
