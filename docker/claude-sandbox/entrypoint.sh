#!/bin/bash
# claude-sandbox entrypoint
#
# 処理順序:
#   1. root 権限で iptables OUTPUT allowlist を設定
#   2. /run/secrets/ からシークレットを読み取り env に展開
#   3. setpriv で UID/GID 1000 に降格し、capability bounding set を全て drop
#      （降格後は全 capability の再取得が物理的に不可能）
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
    # ip6tables が利用可能な環境では IPv6 側も同様に DROP にする（IPv6 経由の漏洩防止）
    if command -v ip6tables >/dev/null; then
        ip6tables -P OUTPUT DROP
    fi

    # loopback は常時許可
    iptables -A OUTPUT -o lo -j ACCEPT
    if command -v ip6tables >/dev/null; then
        ip6tables -A OUTPUT -o lo -j ACCEPT
    fi

    # DNS 解決用（53/udp, 53/tcp）
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
    if command -v ip6tables >/dev/null; then
        ip6tables -A OUTPUT -p udp --dport 53 -j ACCEPT
        ip6tables -A OUTPUT -p tcp --dport 53 -j ACCEPT
    fi

    # allowlist ホストを DNS 解決して ACCEPT ルール追加
    # 注: CDN IP ローテーション対策として ESTABLISHED,RELATED も許可する
    # IPv4 と IPv6 を分けて解決する（ahosts は両方を返すため iptables に食わせると失敗する）
    local host ip
    for host in "${ALLOWED_HOSTS[@]}"; do
        while read -r ip; do
            if [[ -n "$ip" ]]; then
                iptables -A OUTPUT -p tcp -d "$ip" --dport 443 -j ACCEPT
            fi
        done < <(getent ahostsv4 "$host" | awk '{ print $1 }' | sort -u)

        if command -v ip6tables >/dev/null; then
            while read -r ip; do
                if [[ -n "$ip" ]]; then
                    ip6tables -A OUTPUT -p tcp -d "$ip" --dport 443 -j ACCEPT
                fi
            done < <(getent ahostsv6 "$host" | awk '{ print $1 }' | sort -u)
        fi
    done

    # 既存接続と関連接続は許可（CDN IP ローテーションへの部分的フォールバック）
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    if command -v ip6tables >/dev/null; then
        ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    fi
}

load_secrets() {
    # Docker secrets のファイル経由注入
    # host 側からの -e ANTHROPIC_API_KEY= 等の env 渡しは禁止
    # secret file が無いのに env が設定済みの場合は、host 側の -e 渡しと判定して明示的に拒否する
    if [[ ! -f /run/secrets/anthropic_api_key && -n "${ANTHROPIC_API_KEY:-}" ]]; then
        echo "エラー: ANTHROPIC_API_KEY が env で注入されています。" >&2
        echo "        host 側からの -e 渡しは禁止です。" >&2
        echo "        /run/secrets/anthropic_api_key を bind mount で注入してください。" >&2
        echo "        詳細: docs/SECURITY.md の「コンテナ隔離の最低条件」項目 3 を参照。" >&2
        exit 1
    fi
    if [[ ! -f /run/secrets/github_token && -n "${GH_TOKEN:-}" ]]; then
        echo "エラー: GH_TOKEN が env で注入されています。" >&2
        echo "        host 側からの -e 渡しは禁止です。" >&2
        echo "        /run/secrets/github_token を bind mount で注入してください。" >&2
        echo "        詳細: docs/SECURITY.md の「コンテナ隔離の最低条件」項目 3 を参照。" >&2
        exit 1
    fi

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
    # exec が失敗した場合のみ到達（set -e により即終了するが、明示的にも終了する）
    echo "FATAL: setpriv による降格に失敗しました" >&2
    exit 1
}

main "$@"
