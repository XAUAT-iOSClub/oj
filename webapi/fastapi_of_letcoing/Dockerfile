FROM public.ecr.aws/docker/library/python:3.13-slim-bookworm
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 APP_ENV=production \
    UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
# uv 版本须与生成 uv.lock 的版本一致，否则 --frozen 可能因锁文件格式差异失败。
RUN pip install --no-cache-dir uv==0.10.7 \
    && groupadd --gid 10001 letcoding \
    && useradd --uid 10001 --gid 10001 --no-create-home letcoding \
    && mkdir -p /var/lib/letcoding/uploads \
    && chown 10001:10001 /var/lib/letcoding/uploads
# 依赖层与源码层分离：改代码不触发重新解析依赖。
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY . .
ENV PATH="/app/.venv/bin:$PATH" UPLOAD_DIR=/var/lib/letcoding/uploads
USER 10001:10001
EXPOSE 8080
CMD ["python", "-m", "deploy.start_api"]
