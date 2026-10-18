#!/usr/bin/env bash
#
# 服务器端部署：从 GHCR 拉取 CI（.github/workflows/backend.yml）
# 已经构建好的镜像，用本目录的 compose 定义重启 API 或 Worker。
#
# 为什么是"拉"而不是"构建"：服务器上从源码构建要装 uv、拉 Python 基础镜像、跑
# 完整依赖解析；CI 已经在 ubuntu-24.04 上构建并推送了同一份镜像。本脚本只负责
# 拉取、解析不可变摘要、重启容器。
#
# 镜像范围：
#   api     -> API 镜像 + Sandbox 镜像摘要（Sandbox 只作题包元数据，不在 API 主机拉取）
#   worker  -> Worker 镜像 + Sandbox 镜像（判题主机必须本地有 Sandbox 才能执行）
#
# 与 compose 的契约：compose.api.yaml / compose.worker.yaml 要求 image 是
# `repo@sha256:...` 形式的不可变引用（容器内 deploy/check_release.py 会再次校验，
# 不通过就拒绝启动）。所以脚本先把 tag 解析成摘要，再通过环境变量传进 compose；
# 不要图省事改成 :latest，那会让 check_release.py 直接退出。
#
# 本脚本必须在仓库检出目录内运行（需要 deploy/compose.*.yaml 和上一级的 .env 文件）。
#
# 用法：
#   ./deploy_from_ghcr.sh                         # API，latest
#   ./deploy_from_ghcr.sh api 1a2b3c4             # API，指定提交（也是回滚方式）
#   ./deploy_from_ghcr.sh worker 1a2b3c4          # 判题主机上的 Worker
#   PULL_TOKEN=... PULL_USERNAME=... ./deploy_from_ghcr.sh api
#   SANDBOX_IMAGE=ghcr.io/xauat-iosclub/oj-sandbox@sha256:<64位> ./deploy_from_ghcr.sh api
#
# 私有 GHCR 包需要先在服务器上登录（PAT 至少带 read:packages）：
#   echo "$TOKEN" | docker login ghcr.io --username <你的GitHub用户名> --password-stdin
# 或者用 PULL_USERNAME / PULL_TOKEN 让脚本临时登录、退出时自动登出。
#
# 同目录必须有：
#   compose.api.yaml / compose.worker.yaml
# API 主机还需要：../.env.production
# 判题主机还需要：../.env.worker.production（含 DOCKER_GID / JUDGE_CPUSET）

# 服务器上常见的调用方式是 `sh deploy_from_ghcr.sh`，而 Debian/Ubuntu 的 /bin/sh
# 是 dash：它没有 pipefail / [[ ]] / $SECONDS / ${BASH_SOURCE[0]}，会在 set 那行
# 直接以 "Illegal option -o pipefail" 退出。检测到不是 bash 就用 bash 重新执行自己。
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

ROLE="${1:-api}"
TAG="${2:-${IMAGE_TAG:-latest}}"

# 镜像仓库。CI 把三个镜像推到 ghcr.io/<owner>/oj-{api,worker,sandbox}（仓库名全小写）。
# 换 registry / 命名空间时只需要覆盖 IMAGE_PREFIX。
IMAGE_PREFIX="${IMAGE_PREFIX:-ghcr.io/xauat-iosclub/oj}"
API_REPO="${API_REPO:-${IMAGE_PREFIX}-api}"
WORKER_REPO="${WORKER_REPO:-${IMAGE_PREFIX}-worker}"
SANDBOX_REPO="${SANDBOX_REPO:-${IMAGE_PREFIX}-sandbox}"

READY_TIMEOUT="${READY_TIMEOUT:-90}"
WORKER_SETTLE_SECONDS="${WORKER_SETTLE_SECONDS:-8}"

case "$ROLE" in
  api)
    COMPOSE_FILE="compose.api.yaml"
    ENV_FILE="$BACKEND_ROOT/.env.production"
    COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-letcoding-api}"
    ROLE_REPO="$API_REPO"
    ROLE_VAR="API_IMAGE"
    SERVICE="api"
    ;;
  worker)
    COMPOSE_FILE="compose.worker.yaml"
    ENV_FILE="$BACKEND_ROOT/.env.worker.production"
    COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-letcoding-worker}"
    ROLE_REPO="$WORKER_REPO"
    ROLE_VAR="WORKER_IMAGE"
    SERVICE="worker"
    ;;
  *)
    echo "用法：$0 [api|worker] [tag]" >&2
    exit 2
    ;;
esac

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$SCRIPT_DIR/$COMPOSE_FILE" -p "$COMPOSE_PROJECT_NAME")

# 登录/登出都针对实际使用的镜像仓库；覆盖 API_REPO/WORKER_REPO 时也不会登错 registry。
REGISTRY_HOST="${ROLE_REPO%%/*}"

# ------------------------------------------------------------------ 前置检查

command -v docker >/dev/null 2>&1 || { echo "错误：未找到 docker。" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "错误：需要 docker compose v2 插件（docker compose，而非旧版 docker-compose）。" >&2; exit 1; }

if [[ ! -f "$SCRIPT_DIR/$COMPOSE_FILE" ]]; then
  echo "错误：$SCRIPT_DIR/$COMPOSE_FILE 不存在；请在仓库的 webapi/fastapi_of_letcoing 检出中运行。" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "错误：未找到 $ENV_FILE。" >&2
  echo "      复制 .env.example 为 $(basename "$ENV_FILE")，填入生产配置后再运行。" >&2
  echo "      注意该文件含密钥，不要提交进 git。" >&2
  exit 1
fi

# 摘要必须是 sha256:<64 hex>。compose 与 check_release.py 都依赖这个格式。
is_digest_ref() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._:/-]*@sha256:[0-9a-f]{64}$ ]]
}

# ------------------------------------------------------------------ 镜像仓库登录

if [[ -n "${PULL_TOKEN:-}" ]]; then
  : "${PULL_USERNAME:?设置了 PULL_TOKEN 就必须同时设置 PULL_USERNAME}"
  trap 'docker logout "$REGISTRY_HOST" >/dev/null 2>&1 || true' EXIT
  printf '%s' "$PULL_TOKEN" | docker login "$REGISTRY_HOST" --username "$PULL_USERNAME" --password-stdin
fi

# ------------------------------------------------------------------ 解析不可变引用

# 优先远程读取顶层 manifest 摘要（buildx imagetools 不会真的拉取镜像层），
# 这样 API 主机不必为了拿 Sandbox 的摘要而下载 g++/JDK/Go 那几百 MB。
# 服务器没有 buildx 时退化为拉取后从 RepoDigests 读取；能否接受取决于镜像大小。
resolve_ref() {
  local repo="$1" tag="$2" digest=""

  if docker buildx version >/dev/null 2>&1; then
    digest="$(docker buildx imagetools inspect "${repo}:${tag}" 2>/dev/null | awk '/^Digest:/ {print $2; exit}')"
  fi

  if [[ "$digest" != sha256:* ]]; then
    echo "==> 无法远程读取 ${repo}:${tag} 的摘要（缺少 buildx 或仓库不可达），改为拉取后解析" >&2
    docker pull "${repo}:${tag}" >/dev/null
    digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "${repo}:${tag}" 2>/dev/null | sed 's/.*@//')"
  fi

  if [[ "$digest" != sha256:* ]]; then
    echo "错误：无法解析 ${repo}:${tag} 的不可变摘要。" >&2
    echo "      可以手动指定 SANDBOX_IMAGE=<repo>@sha256:<64位> 或安装 docker buildx 后重试。" >&2
    return 1
  fi

  printf '%s@%s\n' "$repo" "$digest"
}

role_ref="$(resolve_ref "$ROLE_REPO" "$TAG")"
is_digest_ref "$role_ref" || { echo "错误：解析结果不是不可变引用：$role_ref" >&2; exit 1; }

# Sandbox：允许调用方直接给摘要，跳过远程解析（离线/受限网络时用）。
if [[ -n "${SANDBOX_IMAGE:-}" ]]; then
  if ! is_digest_ref "$SANDBOX_IMAGE"; then
    echo "错误：SANDBOX_IMAGE 必须是 repo@sha256:<64位>，收到：$SANDBOX_IMAGE" >&2
    exit 1
  fi
  sandbox_ref="$SANDBOX_IMAGE"
else
  sandbox_ref="$(resolve_ref "$SANDBOX_REPO" "$TAG")"
  is_digest_ref "$sandbox_ref" || { echo "错误：解析结果不是不可变引用：$sandbox_ref" >&2; exit 1; }
fi

# ------------------------------------------------------------------ 拉取与启动

previous_image="$(docker container inspect -f '{{.Config.Image}}' "$("${COMPOSE[@]}" ps -q "$SERVICE" 2>/dev/null || true)" 2>/dev/null || true)"

echo "==> 拉取 $role_ref"
docker pull "$role_ref"

# 判题主机要真正执行 Sandbox；API 主机只需要它的摘要。
if [[ "$ROLE" == "worker" ]]; then
  echo "==> 拉取 $sandbox_ref"
  docker pull "$sandbox_ref"
fi

# 显式导出：compose 插值优先级是 shell 环境 > --env-file，
# 所以即使 env 文件里还留着旧值，也会被这里覆盖。
export JUDGE_SANDBOX_IMAGE="$sandbox_ref"
export "$ROLE_VAR=$role_ref"

echo "==> 启动（project=${COMPOSE_PROJECT_NAME}，service=${SERVICE}）"
"${COMPOSE[@]}" up -d --no-build --remove-orphans

# ------------------------------------------------------------------ 就绪等待

container_id="$("${COMPOSE[@]}" ps -q "$SERVICE")"
if [[ -z "$container_id" ]]; then
  echo "错误：compose 没有启动出 $SERVICE 容器。最近日志：" >&2
  "${COMPOSE[@]}" logs --tail 60 >&2 || true
  exit 1
fi

if [[ "$ROLE" == "api" ]]; then
  # 启动即失败的两大原因：迁移失败（migrate 服务非 0 退出）和运行时配置不合法
  # （deploy/start_api.py 预检直接抛）。所以不只看容器在不在跑：/healthz 只证明
  # 进程活着，/readyz 才会检查迁移、表/列兼容性和 Redis，部署门禁用后者。
  if command -v curl >/dev/null 2>&1; then
    echo "==> 等待 /readyz 就绪（最多 ${READY_TIMEOUT}s）"
    deadline=$(( SECONDS + READY_TIMEOUT ))
    ready=0
    while (( SECONDS < deadline )); do
      if curl -fsS --max-time 2 "http://127.0.0.1:8080/readyz" >/dev/null 2>&1; then
        ready=1
        break
      fi
      if [[ "$(docker container inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null || echo false)" != "true" ]]; then
        echo "错误：$SERVICE 容器已退出。日志：" >&2
        docker logs --tail 80 "$container_id" >&2 || true
        exit 1
      fi
      sleep 1
    done
    if (( ! ready )); then
      echo "错误：${READY_TIMEOUT}s 内 /readyz 未就绪。最近日志：" >&2
      docker logs --tail 80 "$container_id" >&2 || true
      exit 1
    fi
  else
    echo "==> 宿主机没有 curl，跳过 /readyz 探测；只校验容器仍在运行"
    sleep "$WORKER_SETTLE_SECONDS"
    if [[ "$(docker container inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null || echo false)" != "true" ]]; then
      echo "错误：$SERVICE 容器已退出。日志：" >&2
      docker logs --tail 80 "$container_id" >&2 || true
      exit 1
    fi
  fi
else
  # Worker 没有 HTTP 端点：观察一小段时间，确认不是配置错误导致的崩溃循环。
  echo "==> 观察 Worker ${WORKER_SETTLE_SECONDS}s，确认没有立即退出"
  sleep "$WORKER_SETTLE_SECONDS"
  if [[ "$(docker container inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null || echo false)" != "true" ]]; then
    echo "错误：Worker 容器已退出。日志：" >&2
    docker logs --tail 80 "$container_id" >&2 || true
    exit 1
  fi
fi

# ------------------------------------------------------------------ 收尾

# 只清 dangling 镜像（不带 -a，不会动还有 tag 的镜像）。
docker image prune --force >/dev/null

echo
echo "==> 部署完成"
echo "    角色 : $ROLE"
echo "    容器 : $container_id"
echo "    镜像 : $role_ref"
echo "    沙箱 : $sandbox_ref"
echo "    配置 : $ENV_FILE"
if [[ -n "$previous_image" && "$previous_image" != "$role_ref" ]]; then
  echo "    回滚 : $0 $ROLE <上一个提交的 SHA>"
  echo "           上次运行的镜像引用：$previous_image"
fi
if [[ "$ROLE" == "api" ]]; then
  echo "    自检 : curl -fsS http://127.0.0.1:8080/healthz && curl -fsS http://127.0.0.1:8080/readyz"
  echo "    排障 : docker logs -f $container_id"
else
  echo "    排障 : docker logs -f $container_id"
  echo "           心跳由 API 侧的 /healthz/judge?pool=<pool> 反映。"
fi
