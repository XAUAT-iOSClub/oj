# LetCoding 后端

Flask + Flask-RESTX API，PostgreSQL 保存业务事实，Redis 负责限流、缓存及任务运输。目录名保留历史名称，实际框架不是 FastAPI。

普通代码运行/题库判题通过可配置 Judge0 服务；比赛提交和参考答案校验由独立 Worker 的 Docker 沙箱执行。API 进程不运行编译器、不启动 Worker；数据库迁移由部署启动包装器或独立迁移任务在接流量前执行。

## 开发与验证

```sh
uv sync                       # 按 uv.lock 建 .venv，含 dev 依赖
# 配置数据库、Redis、独立密钥等环境变量；开发时 APP_ENV=development 才加载 .env。
uv run python manage.py migrate
uv run python manage.py seed
uv run python main.py
# Worker 单独启动；默认需要 Docker 沙箱镜像。
uv run python manage.py worker
uv run python -m pytest -q
```

开发 API 默认监听 `127.0.0.1:6173`。测试使用隔离的临时 Redis/PostgreSQL，需要本机安装 redis-server、PostgreSQL 工具、g++ 和 JDK；可用 `PG_BINDIR` 指定 PostgreSQL 的 bin 目录。开发测试中的本地执行不提供生产安全保证。

## 部署与接口

详细部署顺序、配置、14 项改造对应关系、迁移兼容和验收限制见 [HARDENING.md](HARDENING.md)。沙箱结构见 [JUDGE_ARCHITECTURE.md](JUDGE_ARCHITECTURE.md)。配置模板为 [.env.example](.env.example)，依赖以 [pyproject.toml](pyproject.toml) 声明、[uv.lock](uv.lock) 锁定，安装与启动统一走 uv。

- 生产入口：`python -m deploy.start_api`；启动包装器预检并显式迁移后运行 Gunicorn。独立迁移任务模式设置 `DB_MIGRATION_MODE=check`。
- Swagger：`/swagger/`；路由及语言支持以控制器和 `JUDGE0_LANGUAGES` 为准。
- `/healthz` 进程存活；`/readyz` 检查迁移、表/列兼容性与 Redis；`/healthz/judge?pool=contest` 检查该队列的有效接单心跳。
- `/metrics` 需要独立 `METRICS_TOKEN` Bearer 凭证，应仅由内部监控访问。
- OAuth 浏览器回调只携带一次性 code；`POST /auth/exchange` 结合浏览器会话兑换令牌。
- 提交记录仅本人及 manager 可查询；响应不返回隐藏测试输入或答案。

### CI/CD 与服务器部署

- **验收**：`.github/workflows/backend.yml` 在每次 push/PR 上跑后端测试、依赖审计、Sandbox 集成和前端契约；`release-gate` 是唯一发布门禁。
- **镜像**：`.github/workflows/publish-images.yml` 在验收工作流于 `main` 上成功后触发（也可手动 `workflow_dispatch`），构建并推送：
  - `ghcr.io/xauat-iosclub/oj-api`
  - `ghcr.io/xauat-iosclub/oj-worker`
  - `ghcr.io/xauat-iosclub/oj-sandbox`

  每个镜像带两个 tag：完整提交 SHA（不可变，用于回滚）和 `latest`。
- **服务器部署**：在服务器上的仓库检出中执行 `deploy/deploy_from_ghcr.sh`。它把 tag 解析成 `repo@sha256:...` 摘要后传给 compose（`check_release.py` 要求不可变引用），再重启对应服务：

  ```sh
  # API 主机（需要 .env.production）
  ./deploy/deploy_from_ghcr.sh api            # latest
  ./deploy/deploy_from_ghcr.sh api <commit>   # 指定提交 / 回滚

  # 判题主机（需要 .env.worker.production，且宿主机可访问 Docker socket）
  ./deploy/deploy_from_ghcr.sh worker <commit>
  ```

  私有包先 `docker login ghcr.io`（PAT 需 `read:packages`），或用 `PULL_USERNAME` / `PULL_TOKEN` 让脚本临时登录。API 主机只解析 Sandbox 摘要、不拉取 Sandbox 镜像；判题主机会拉取并实际执行它。

生产保障、迁移与验收要求：[PRODUCTION_READINESS.md](PRODUCTION_READINESS.md)。

本轮启动修复、性能优化与平台接入步骤：[DEPLOYMENT_UPGRADE.md](DEPLOYMENT_UPGRADE.md)。
