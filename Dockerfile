# syntax=docker/dockerfile:1.7

ARG NODE_VERSION=22
ARG RUST_VERSION=1.90

FROM rust:${RUST_VERSION}-bookworm AS rust-toolchain

FROM node:${NODE_VERSION}-bookworm AS builder

ARG TARGETARCH

ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    PATH="/usr/local/cargo/bin:${PATH}"

COPY --from=rust-toolchain /usr/local/cargo /usr/local/cargo
COPY --from=rust-toolchain /usr/local/rustup /usr/local/rustup

RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global pnpm@10

WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN --mount=type=cache,id=codex-webui-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=codex-webui-cargo-git,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,id=codex-webui-cargo-target-${TARGETARCH},target=/app/backend/target,sharing=locked \
    pnpm build \
    && mkdir -p /app/runtime-artifacts \
    && cp /app/dist/backend/*/backend /app/runtime-artifacts/backend


FROM node:${NODE_VERSION}-bookworm-slim AS runtime

ARG CODEX_VERSION=0.153.0

ENV NPM_CONFIG_PREFIX=/home/node/.local \
    PATH="/home/node/.local/bin:${PATH}"

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        openssh-client \
        procps \
        ripgrep \
        tini \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app/build /app/scripts /data /workspace /home/node/.codex /home/node/.local /home/node/.npm \
    && chown -R node:node /app /data /workspace /home/node/.codex /home/node/.local /home/node/.npm

USER node

# Keep the CLI under node's writable npm prefix. The in-app update action runs as
# this same unprivileged user, so npm can replace the package without root access.
RUN npm install --global "@openai/codex@${CODEX_VERSION}"

WORKDIR /app

COPY --from=builder --chown=node:node /app/build/static ./build/static
COPY --from=builder --chown=node:node /app/runtime-artifacts/backend ./backend
COPY --from=builder --chown=node:node /app/scripts/hash-password.mjs ./scripts/hash-password.mjs

ENV HOST=0.0.0.0 \
    PORT=4173 \
    CODEX_HOME=/home/node/.codex \
    CODEX_WEBUI_CODEX_BIN=/home/node/.local/bin/codex \
    CODEX_WEBUI_DATA_DIR=/data \
    CODEX_WEBUI_ALLOWED_ROOTS=/workspace \
    CODEX_WEBUI_BASE_PATH=""

EXPOSE 4173

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl --fail --silent --show-error http://127.0.0.1:4173/healthz >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/backend"]
