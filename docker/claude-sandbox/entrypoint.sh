#!/bin/bash
# claude-sandbox entrypoint
#
# 処理順序:
#   1. root 権限で iptables OUTPUT allowlist を設定
#   2. /run/secrets/ からシークレットを読み取り env に展開
#   3. setpriv で UID/GID 1000 に降格し、capability bounding set から
#      NET_ADMIN / NET_RAW / SYS_ADMIN を drop（降格後の再取得を不可能にする）
#
# 参照: Issue #266 / .claude/knowledge/ciso/decisions.md
set -euo pipefail
set -o pipefail

ALLOWED_HOSTS=(
    api.anthropic.com
    api.github.com
    github.com
)

configure_egress_allowlist() {
    # OUTPUT チェーンのデフォルトポリシーを DROP に変更
    iptables -P OUTPUT DROP

    # loopback は常時許可
    iptables -A OUTPUT -o lo -j ACCEPT

    # DNS 解決用（53/udp, 53/tcp）
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

    # allowlist ホストを DNS 解決して ACCEPT ルール追加
    # 注: CDN IP ローテーション対策として ESTABLISHED,RELATED も許可する
    local host ip
    for host in "${ALLOWED_HOSTS[@]}"; do
        while read -r ip; do
            if [[ -n "$ip" ]]; then
                iptables -A OUTPUT -p tcp -d "$ip" --dport 443 -j ACCEPT
            fi
        done < <(getent ahosts "$host" | awk '{ print $1 }' | sort -u)
    done

    # 既存接続と関連接続は許可（CDN IP ローテーションへの部分的フォールバック）
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
}

load_secrets() {
    # Docker secrets のファイル経由注入
    # host 側からの -e ANTHROPIC_API_KEY= 等の env 渡しは禁止
    if [[ -f /run/secrets/anthropic_api_key ]]; then
        ANTHROPIC_API_KEY="$(cat /run/secrets/anthropic_api_key)"
        export ANTHROPIC_API_KEY
    fi
    if [[ -f /run/secrets/github_token ]]; then
        GH_TOKEN="$(cat /run/secrets/github_token)"
        export GH_TOKEN
    fi
}

main() {
    configure_egress_allowlist
    load_secrets

    # non-root 降格 + capability bounding set 完全 drop
    # 降格後プロセスは NET_ADMIN / SETUID / SETGID 等を再取得できず iptables の後戻りや再度の uid 変更が物理的に不可能
    exec setpriv \
        --reuid=1000 \
        --regid=1000 \
        --clear-groups \
        --inh-caps=-all \
        --bounding-set=-all \
        -- "$@"
}

main "$@"
