# claude CLI を --dangerously-skip-permissions 付きで安全に実行するためのコンテナイメージ
# 参考: .claude/knowledge/ciso/decisions.md / .claude/knowledge/cto/decisions.md / Issue #266
FROM node:20-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV CLAUDE_PROJECT_DIR=/workspace

# 必要パッケージのインストール
# - tini: PID 1 の zombie reaping
# - iptables, iproute2: entrypoint.sh での egress allowlist 設定
# - util-linux: setpriv（non-root 降格と capability bounding set drop）
# - dnsutils: getent 代替の dig 等（デバッグ用途）
# - ca-certificates, curl, git: claude CLI 動作に必要
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        tini \
        iptables \
        iproute2 \
        util-linux \
        dnsutils \
        ca-certificates \
        curl \
        git \
    && rm -rf /var/lib/apt/lists/*

# claude CLI の global install
RUN npm install -g @anthropic-ai/claude-code@latest \
    && npm cache clean --force

# non-root ユーザーの作成
# node:20-slim には既に UID/GID 1000 の node ユーザーが存在するため削除してから claude を作成する
RUN userdel -r node \
    && useradd -m -u 1000 -s /bin/bash claude \
    && mkdir -p /workspace /state /home/claude/.claude \
    && chown -R claude:claude /workspace /state /home/claude

# entrypoint のコピー
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace

# tini を PID 1 にして entrypoint を実行
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["claude", "--version"]
