# syntax=docker/dockerfile:1
ARG ALPINE_VERSION=3.20
ARG UBUNTU_VERSION=24.04
ARG NODE_IMAGE=node:20-slim
ARG NODE_SETUP_MAJOR=20
ARG TEXT_TO_CAD_VERSION=0.3.9
ARG OPENCODE_AI_VERSION=1.17.18
ARG OPENCHAMBER_VERSION=1.14.1
ARG LEANCTX_VERSION=3.9.6
ARG LEANCTX_SHA256=a7a450c1bc7c98594a8fda1e66625bfa8d4391749e8b0d444bcbce986d769f2f

FROM alpine:${ALPINE_VERSION} AS upstream-fetcher
ARG TEXT_TO_CAD_VERSION
RUN apk add --no-cache curl tar
WORKDIR /upstream
RUN curl -fsSL \
    "https://github.com/earthtojake/text-to-cad/archive/refs/tags/${TEXT_TO_CAD_VERSION}.tar.gz" \
    -o upstream.tar.gz && \
    tar xzf upstream.tar.gz && \
    mv text-to-cad-* text-to-cad && \
    rm -f upstream.tar.gz

FROM ubuntu:${UBUNTU_VERSION} AS builder
ARG TEXT_TO_CAD_VERSION
ARG NODE_SETUP_MAJOR
ARG OPENCODE_AI_VERSION
ARG OPENCHAMBER_VERSION
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg build-essential \
    python3.12 python3.12-dev python3.12-venv \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_SETUP_MAJOR}.x" | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*
ENV VIRTUAL_ENV=/opt/venv
RUN python3.12 -m venv "$VIRTUAL_ENV"
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
COPY --from=upstream-fetcher /upstream/text-to-cad /upstream/text-to-cad
WORKDIR /upstream/text-to-cad
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir build123d numpy ocp-vscode playwright && \
    pip install --no-cache-dir skills/cad/scripts/packages/cadpy && \
    python -m playwright install chromium --with-deps && \
    npm install -g "opencode-ai@${OPENCODE_AI_VERSION}" && \
    npm install -g "@openchamber/web@${OPENCHAMBER_VERSION}" && \
    NPM_PREFIX="$(npm config get prefix)" && \
    mkdir -p /tmp/opencode-stage && \
    cp -L "${NPM_PREFIX}/bin/opencode" /tmp/opencode-stage/ && \
    cp -r "${NPM_PREFIX}/lib/node_modules/opencode-ai" /tmp/opencode-stage/ && \
    mkdir -p /tmp/opencode-stage/@openchamber && \
    cp -r "${NPM_PREFIX}/lib/node_modules/@openchamber/web" /tmp/opencode-stage/@openchamber/

FROM ${NODE_IMAGE} AS node-runtime

FROM ubuntu:${UBUNTU_VERSION} AS runtime
ARG TEXT_TO_CAD_VERSION
ARG OPENCHAMBER_VERSION
ARG LEANCTX_VERSION
ARG LEANCTX_SHA256
LABEL org.opencontainers.image.title="text-to-cad Workbench" \
      org.opencontainers.image.description="Docker workbench for earthtojake/text-to-cad" \
      org.opencontainers.image.version="${TEXT_TO_CAD_VERSION}" \
      org.opencontainers.image.source="https://github.com/earthtojake/text-to-cad"
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 TZ=Etc/UTC
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl python3.12 python3.12-venv \
    libgl1 libglib2.0-0 libnss3 libnspr4 libatk1.0-0 \
    libatk-bridge2.0-0 libcups2 libdrm2 libdbus-1-3 libxkbcommon0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 \
    libpango-1.0-0 libcairo2 libasound2t64 passwd xz-utils netcat-openbsd tmux \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL \
    "https://github.com/yvgude/lean-ctx/releases/download/v${LEANCTX_VERSION}/lean-ctx-x86_64-unknown-linux-musl.tar.gz" \
    -o /tmp/lean-ctx.tar.gz && \
    printf '%s %s\n' "${LEANCTX_SHA256}" "/tmp/lean-ctx.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/lean-ctx.tar.gz -C /usr/local/bin lean-ctx && \
    chmod +x /usr/local/bin/lean-ctx && \
    rm -f /tmp/lean-ctx.tar.gz
COPY --from=builder /upstream/text-to-cad /opt/upstream-src
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/playwright-browsers /opt/playwright-browsers
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
ENV PATH="/opt/venv/bin:$PATH"
RUN python -m playwright install-deps chromium
COPY --from=node-runtime /usr/local/bin/ /usr/local/bin/
COPY --from=node-runtime /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /tmp/opencode-stage/opencode /usr/local/bin/opencode
COPY --from=builder /tmp/opencode-stage/opencode-ai /usr/local/lib/node_modules/opencode-ai
COPY --from=builder /tmp/opencode-stage/@openchamber /usr/local/lib/node_modules/@openchamber
RUN ln -sf /usr/local/lib/node_modules/@openchamber/web/bin/cli.js /usr/local/bin/openchamber && \
    chmod +x /usr/local/lib/node_modules/@openchamber/web/bin/cli.js
ENV NODE_PATH="/usr/local/lib/node_modules"
ENV BASH_ENV="/home/opencode/.config/lean-ctx/env.sh"
ENV CLAUDE_ENV_FILE="/home/opencode/.config/lean-ctx/env.sh"
RUN mkdir -p /opt/workspace-seed
COPY --from=upstream-fetcher /upstream/text-to-cad/README.md /opt/workspace-seed/
COPY --from=upstream-fetcher /upstream/text-to-cad/benchmarks /opt/workspace-seed/benchmarks
COPY --from=upstream-fetcher /upstream/text-to-cad/assets /opt/workspace-seed/assets
RUN mkdir -p /opt/workspace-seed/models /opt/workspace-seed/output
RUN if id ubuntu &>/dev/null 2>&1; then \
        usermod --login opencode --move-home --home /home/opencode ubuntu && \
        groupmod --new-name opencode ubuntu; \
    else \
        groupadd --gid 1000 opencode && \
        useradd --uid 1000 --gid 1000 -m opencode; \
    fi 2>/dev/null; \
    chown -R 1000:1000 /home/opencode
RUN mkdir -p \
    /home/opencode/.config/lean-ctx \
    /home/opencode/.local/share/lean-ctx \
    /home/opencode/.local/state/lean-ctx \
    /home/opencode/.cache/lean-ctx && \
    cat > /home/opencode/.config/lean-ctx/config.toml <<'EOF'
permission_inheritance = "on"
compression_level = "standard"
shell_allowlist_extra = [
  "docker",
  "docker compose",
  "git",
  "node",
  "npm",
  "python",
  "python3",
]
savings_footer = "auto"
EOF
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 3000 3002
WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
