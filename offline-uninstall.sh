#!/usr/bin/env bash
# =============================================================================
#  AgentSystem 离线授权版 · 彻底卸载脚本  v1.1.0
#  -----------------------------------------------------------------------------
#  删除范围（默认全量）：
#    1. 容器     : agentsystem-* / mingyingkeji-*（含一次性初始化容器）
#    2. 数据卷   : 本次部署创建的 Postgres / Redis / Weaviate / Neo4j / 沙箱 / 日志卷
#    3. 网络     : 本次部署创建的 overlay 网络
#    4. 镜像     : 部署包内置的 9 个镜像（--keep-images 可保留）
#    5. 服务单元 : systemd agentsystem.service / crontab @reboot / rc.local 条目
#    6. 安装目录 : 当前安装目录（含配置、备份、日志、授权文件）
#    7. 历史环境 : 旧版 /opt/AgentSystem-离线授权版-v1.0 及其容器/镜像/数据卷
#    8. 部署日志 : /var/log/agentsystem-*.log
#
#  选项:
#    --yes, -y        跳过二次确认（自动化 / 远程执行）
#    --keep-images    保留 Docker 镜像
#    --keep-data      保留数据卷（仅移除容器与目录）
#    --keep-dir       保留安装目录（仅清理容器/镜像/数据）
#    --purge-source   同时删除源码目录 /opt/AgentSystem-src-20261030 与历史安装包 tar.gz
#    --dry-run        只打印将要删除的内容
# =============================================================================
set -Eeuo pipefail
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
CALLER_DIR="$(dirname "$SCRIPT_PATH")"

PROJECT_NAMES=("agentsystem" "mingyingkeji")
IMAGE_LIST=(
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
LEGACY_DIRS=(
  "/opt/AgentSystem-离线授权版-v1.0"
)
SOURCE_DIR="/opt/AgentSystem-src-20261030"

ASSUME_YES=0
KEEP_IMAGES=0
KEEP_DATA=0
KEEP_DIR=0
PURGE_SOURCE=0
DRY_RUN=0

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
act()  { printf "  %s▹%s %s\n" "$C_BLU" "$C_RST" "$*"; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then printf "      %s[dry-run]%s %s\n" "$C_DIM" "$C_RST" "$*"; return 0; fi
  "$@" >/dev/null 2>&1 || true
}

usage() {
  sed -n '2,30p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
  exit 0
}

# 判断目录是否为 AgentSystem 安装目录（避免误删）
is_install_dir() {
  local d="$1"
  [ -n "$d" ] && [ -d "$d" ] || return 1
  [ -f "$d/docker/docker-compose.offline.yaml" ] || [ -f "$d/api/.env.docker" ] || [ -f "$d/offline-deploy.sh" ]
}

# 收集并删除容器
purge_containers() {
  act "扫描并删除容器（项目标签 / 名称前缀）"
  local ids=() id name pf
  for pf in "${PROJECT_NAMES[@]}"; do
    while IFS= read -r id; do [ -n "$id" ] && ids+=("$id"); done < <(
      docker ps -aq -f "label=com.docker.compose.project=${pf}" 2>/dev/null || true
    )
    while IFS= read -r id; do [ -n "$id" ] && ids+=("$id"); done < <(
      docker ps -aq -f "name=^${pf}-" 2>/dev/null || true
    )
  done
  if [ "${#ids[@]}" -eq 0 ]; then ok "未发现相关容器"; return 0; fi
  local uniq; uniq="$(printf '%s\n' "${ids[@]}" | sort -u)"
  for id in $uniq; do
    name="$(docker inspect -f '{{.Name}}' "$id" 2>/dev/null | sed 's#^/##')"
    if [ "$DRY_RUN" -eq 0 ]; then docker rm -f "$id" >/dev/null 2>&1 || true; fi
    printf "      %s✘ 容器 %s%s\n" "$C_RED" "${name:-$id}" "$C_RST"
  done
  ok "容器已清理"
}

# 删除数据卷
purge_volumes() {
  if [ "$KEEP_DATA" -eq 1 ]; then warn "已指定 --keep-data，跳过数据卷删除"; return 0; fi
  act "扫描并删除数据卷（保留标记卷除外）"
  local vols=() v pf
  for pf in "${PROJECT_NAMES[@]}"; do
    while IFS= read -r v; do [ -n "$v" ] && vols+=("$v"); done < <(
      docker volume ls -q -f "label=com.docker.compose.project=${pf}" 2>/dev/null || true
    )
    while IFS= read -r v; do [ -n "$v" ] && vols+=("$v"); done < <(
      docker volume ls -q --format '{{.Name}}' 2>/dev/null | grep -E "^${pf}_" || true
    )
  done
  if [ "${#vols[@]}" -eq 0 ]; then ok "未发现相关数据卷"; return 0; fi
  for v in $(printf '%s\n' "${vols[@]}" | sort -u); do
    if [ "$DRY_RUN" -eq 0 ]; then docker volume rm -f "$v" >/dev/null 2>&1 || true; fi
    printf "      %s✘ 数据卷 %s%s\n" "$C_RED" "$v" "$C_RST"
  done
  ok "数据卷已清理"
}

# 删除网络
purge_networks() {
  act "扫描并删除容器网络"
  local nets=() n pf
  for pf in "${PROJECT_NAMES[@]}"; do
    while IFS= read -r n; do [ -n "$n" ] && nets+=("$n"); done < <(
      docker network ls --format '{{.Name}}' 2>/dev/null | grep -E "^${pf}_" || true
    )
  done
  if [ "${#nets[@]}" -eq 0 ]; then ok "未发现相关网络"; return 0; fi
  for n in $(printf '%s\n' "${nets[@]}" | sort -u); do
    if [ "$DRY_RUN" -eq 0 ]; then docker network rm "$n" >/dev/null 2>&1 || true; fi
    printf "      %s✘ 网络 %s%s\n" "$C_RED" "$n" "$C_RST"
  done
  ok "网络已清理"
}

# 删除镜像
purge_images() {
  if [ "$KEEP_IMAGES" -eq 1 ]; then warn "已指定 --keep-images，跳过镜像删除"; return 0; fi
  act "删除部署内置镜像（仅本产品使用的 9 个）"
  local img
  for img in "${IMAGE_LIST[@]}"; do
    if docker image inspect "$img" >/dev/null 2>&1; then
      if [ "$DRY_RUN" -eq 0 ]; then docker rmi -f "$img" >/dev/null 2>&1 || true; fi
      printf "      %s✘ 镜像 %s%s\n" "$C_RED" "$img" "$C_RST"
    fi
  done
  # 历史调试标签
  for img in "mingyingkeji-api:pre-lan-fix"; do
    if docker image inspect "$img" >/dev/null 2>&1; then
      [ "$DRY_RUN" -eq 0 ] && docker rmi -f "$img" >/dev/null 2>&1 || true
      printf "      %s✘ 镜像 %s%s\n" "$C_RED" "$img" "$C_RST"
    fi
  done
  ok "镜像已清理"
}

# systemd / cron / rc.local
purge_autostart() {
  act "清理开机自启配置"
  if command -v systemctl >/dev/null 2>&1; then
    for unit in agentsystem.service mingyingkeji.service AgentSystem.service; do
      if [ -f "/etc/systemd/system/$unit" ]; then
        run systemctl stop "$unit"
        run systemctl disable "$unit"
        run rm -f "/etc/systemd/system/$unit"
        printf "      %s✘ systemd 单元 %s%s\n" "$C_RED" "$unit" "$C_RST"
      fi
    done
    run systemctl daemon-reload
  fi
  if command -v crontab >/dev/null 2>&1; then
    local before after
    before="$(crontab -l 2>/dev/null || true)"
    after="$(printf '%s\n' "$before" | grep -vE 'agentsystem|mingyingkeji' || true)"
    if [ "$before" != "$after" ]; then
      if [ "$DRY_RUN" -eq 0 ]; then printf '%s\n' "$after" | crontab - || true; fi
      printf "      %s✘ crontab 开机条目%s\n" "$C_RED" "$C_RST"
    fi
  fi
  if [ -f /etc/rc.local ]; then
    if grep -qE 'agentsystem|mingyingkeji' /etc/rc.local 2>/dev/null; then
      if [ "$DRY_RUN" -eq 0 ]; then
        sed -i.bak -E '/agentsystem|mingyingkeji/d' /etc/rc.local && rm -f /etc/rc.local.bak
      fi
      printf "      %s✘ /etc/rc.local 条目%s\n" "$C_RED" "$C_RST"
    fi
  fi
  ok "开机自启配置已清理"
}

# 删除目录
purge_dirs() {
  act "清理安装目录"
  local -a dirs=()
  local d

  if [ "$KEEP_DIR" -eq 0 ]; then
    # 仅当脚本所在目录确实是「已部署实例」（含 .deploy-meta）时才删除自身目录，
    # 避免在解压出来的部署包目录里执行清理时把安装包本身删掉。
    if [ -f "$CALLER_DIR/.deploy-meta" ] && is_install_dir "$CALLER_DIR"; then
      dirs+=("$CALLER_DIR")
    fi
    for d in "${LEGACY_DIRS[@]}"; do
      [ -d "$d" ] && dirs+=("$d")
    done
    # 常见安装位置兜底
    for d in /opt/AgentSystem /opt/agentsystem /root/agentsystem; do
      [ -d "$d" ] && is_install_dir "$d" && dirs+=("$d")
    done
  fi

  if [ "$PURGE_SOURCE" -eq 1 ]; then
    [ -d "$SOURCE_DIR" ] && dirs+=("$SOURCE_DIR")
    for f in /opt/AgentSystem-离线授权版-v1.0*.tar.gz /opt/AgentSystem-离线授权版-v1.1.0*.tar.gz; do
      [ -f "$f" ] && { run rm -f "$f"; printf "      %s✘ 安装包 %s%s\n" "$C_RED" "$f" "$C_RST"; }
    done
  fi

  if [ "${#dirs[@]}" -eq 0 ]; then ok "未发现需要删除的安装目录"; return 0; fi
  for d in $(printf '%s\n' "${dirs[@]}" | sort -u); do
    # 安全护栏：禁止删除根目录 / 家目录 / 过短路径
    case "$d" in
      ""|"/"|"/root"|"/home"|"/opt"|"/usr"|"/etc"|"/var") err "跳过危险路径：$d"; continue ;;
    esac
    [ "${#d}" -ge 6 ] || { err "跳过过短路径：$d"; continue; }
    if [ "$DRY_RUN" -eq 0 ]; then rm -rf -- "$d"; fi
    printf "      %s✘ 目录 %s%s\n" "$C_RED" "$d" "$C_RST"
  done
  ok "安装目录已清理"
}

purge_logs() {
  act "清理部署日志"
  local f found=0
  for f in /var/log/agentsystem-*.log /tmp/agentsystem-*.log; do
    [ -f "$f" ] || continue
    found=1
    run rm -f "$f"
    printf "      %s✘ 日志 %s%s\n" "$C_RED" "$f" "$C_RST"
  done
  [ "$found" -eq 1 ] || ok "未发现部署日志"
}

# 汇总展示
show_plan() {
  hr
  printf "  %sAgentSystem 彻底卸载%s\n" "$C_RED$C_BLD" "$C_RST"
  hr
  printf "  %-16s %s\n" "安装目录" "$CALLER_DIR"
  printf "  %-16s %s\n" "目标项目" "${PROJECT_NAMES[*]}"
  printf "  %-16s %s\n" "数据卷" "$([ "$KEEP_DATA" -eq 1 ] && echo '保留' || echo '删除')"
  printf "  %-16s %s\n" "镜像" "$([ "$KEEP_IMAGES" -eq 1 ] && echo '保留' || echo '删除')"
  printf "  %-16s %s\n" "安装目录" "$([ "$KEEP_DIR" -eq 1 ] && echo '保留' || echo '删除')"
  printf "  %-16s %s\n" "源码/安装包" "$([ "$PURGE_SOURCE" -eq 1 ] && echo '一并删除' || echo '保留')"
  hr_thin
  printf "  %s此操作不可恢复：数据库、授权文件、上传的文件都将被永久删除。%s\n" "$C_YEL" "$C_RST"
  hr
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes|-y) ASSUME_YES=1; shift ;;
      --keep-images) KEEP_IMAGES=1; shift ;;
      --keep-data) KEEP_DATA=1; shift ;;
      --keep-dir) KEEP_DIR=1; shift ;;
      --purge-source) PURGE_SOURCE=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage ;;
      *) err "未知参数：$1"; exit 2 ;;
    esac
  done

  [ "$(id -u)" -eq 0 ] || { err "请使用 root 运行"; exit 1; }
  command -v docker >/dev/null 2>&1 || { err "未检测到 docker"; exit 1; }

  show_plan

  if [ "$ASSUME_YES" -ne 1 ]; then
    printf "  确认彻底删除以上全部内容？输入 %sYES%s 继续: " "$C_RED$C_BLD" "$C_RST"
    local ans=""; read -r ans || true
    [ "$ans" = "YES" ] || { printf "\n  已取消\n\n"; exit 0; }
  fi

  printf "\n"
  purge_containers
  purge_volumes
  purge_networks
  purge_images
  purge_autostart
  purge_logs
  purge_dirs

  printf "\n"
  hr
  printf "  %s✔ 卸载完成%s   ·   所有本次安装的容器 / 数据卷 / 镜像 / 服务单元 / 目录均已清除\n" "$C_GRN$C_BLD" "$C_RST"
  hr_thin
  printf "  校验残留：\n"
  printf "    docker ps -a | grep -E 'agentsystem|mingyingkeji'   %s\n" "$(docker ps -a 2>/dev/null | grep -cE 'agentsystem|mingyingkeji' || true) 条"
  printf "    docker volume ls | grep -E 'agentsystem|mingyingkeji' %s\n" "$(docker volume ls 2>/dev/null | grep -cE 'agentsystem|mingyingkeji' || true) 条"
  printf "    docker images | grep mingyingkeji                     %s\n" "$(docker images 2>/dev/null | grep -c mingyingkeji || true) 条"
  hr
  printf "  重新部署：\n"
  printf "    tar -xzf AgentSystem-*.tar.gz -C /opt && cd /opt/AgentSystem-* && bash offline-deploy.sh\n\n"
}

main "$@"
