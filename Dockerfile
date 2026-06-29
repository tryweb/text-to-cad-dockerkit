# syntax=docker/dockerfile:1
FROM alpine:3.20 AS upstream-fetcher
ARG TEXT_TO_CAD_VERSION
RUN test -n "$TEXT_TO_CAD_VERSION" || \
    (echo "ERROR: TEXT_TO_CAD_VERSION build-arg is required" >&2 && exit 1)
RUN apk add --no-cache curl tar
WORKDIR /upstream
RUN curl -fsSL \
    "https://github.com/earthtojake/text-to-cad/archive/refs/tags/${TEXT_TO_CAD_VERSION}.tar.gz" \
    -o upstream.tar.gz && \
    tar xzf upstream.tar.gz && \
    mv text-to-cad-* text-to-cad && \
    rm -f upstream.tar.gz

FROM ubuntu:22.04 AS builder
ARG TEXT_TO_CAD_VERSION
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg build-essential \
    python3.11 python3.11-dev python3.11-venv \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*
ENV VIRTUAL_ENV=/opt/venv
RUN python3.11 -m venv "$VIRTUAL_ENV"
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
COPY --from=upstream-fetcher /upstream/text-to-cad /upstream/text-to-cad
WORKDIR /upstream/text-to-cad
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir build123d numpy ocp-vscode playwright && \
    pip install --no-cache-dir skills/cad/scripts/packages/cadpy && \
    python -m playwright install chromium --with-deps && \
    npm install -g opencode-ai && \
    NPM_PREFIX="$(npm config get prefix)" && \
    mkdir -p /tmp/opencode-stage && \
    cp -L "${NPM_PREFIX}/bin/opencode" /tmp/opencode-stage/ && \
    cp -r "${NPM_PREFIX}/lib/node_modules/opencode-ai" /tmp/opencode-stage/
FROM ubuntu:22.04 AS runtime
ARG TEXT_TO_CAD_VERSION
LABEL org.opencontainers.image.title="text-to-cad Workbench" \
      org.opencontainers.image.description="Docker workbench for earthtojake/text-to-cad" \
      org.opencontainers.image.version="${TEXT_TO_CAD_VERSION}" \
      org.opencontainers.image.source="https://github.com/earthtojake/text-to-cad"
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 TZ=Etc/UTC
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl python3.11 python3.11-venv \
    libgl1-mesa-glx libglib2.0-0 libnss3 libnspr4 libatk1.0-0 \
    libatk-bridge2.0-0 libcups2 libdrm2 libdbus-1-3 libxkbcommon0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 \
    libpango-1.0-0 libcairo2 libasound2 passwd xz-utils netcat tmux \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL \
    "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64" \
    -o /usr/local/bin/ttyd && chmod +x /usr/local/bin/ttyd
COPY --from=builder /upstream/text-to-cad /opt/upstream-src
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY --from=node:20-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:20-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /tmp/opencode-stage/opencode /usr/local/bin/opencode
COPY --from=builder /tmp/opencode-stage/opencode-ai /usr/local/lib/node_modules/opencode-ai
ENV NODE_PATH="/usr/local/lib/node_modules"
RUN mkdir -p /opt/workspace-seed
COPY --from=upstream-fetcher /upstream/text-to-cad/README.md /opt/workspace-seed/
COPY --from=upstream-fetcher /upstream/text-to-cad/benchmarks /opt/workspace-seed/benchmarks
COPY --from=upstream-fetcher /upstream/text-to-cad/assets /opt/workspace-seed/assets
RUN mkdir -p /opt/workspace-seed/models /opt/workspace-seed/output
RUN groupadd --system --gid 1000 opencode 2>/dev/null || true && \
    useradd --system --uid 1000 --gid 1000 -m opencode 2>/dev/null || true
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 3001 3002
WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
