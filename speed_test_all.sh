#!/bin/bash

set -u

SERVER_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONFIG_FILE="$SERVER_DIR/conf/config.yaml"
YQ_BINARY="$SERVER_DIR/bin/yq"

TEST_URL="${TEST_URL:-http://www.gstatic.com/generate_204}"
TIMEOUT_MS="${TIMEOUT_MS:-10000}"
CURL_MAX_TIME="${CURL_MAX_TIME:-15}"

read_controller_port() {
  local controller_addr=""

  if [ -x "$YQ_BINARY" ] && [ -f "$CONFIG_FILE" ]; then
    controller_addr=$("$YQ_BINARY" eval '.["external-controller"] // "0.0.0.0:6006"' "$CONFIG_FILE" 2>/dev/null)
  fi

  if [ -z "$controller_addr" ] || [ "$controller_addr" = "null" ]; then
    controller_addr="0.0.0.0:6006"
  fi

  echo "${controller_addr##*:}"
}

API_BASE="${API_BASE:-http://127.0.0.1:$(read_controller_port)}"
PROXIES_JSON=$(mktemp)
trap 'rm -f "$PROXIES_JSON"' EXIT

if ! curl -s --connect-timeout 2 -m 10 "$API_BASE/proxies" > "$PROXIES_JSON"; then
  echo "无法连接 mihomo API: $API_BASE"
  exit 1
fi

mapfile -t PROXY_NAMES < <(python3 - "$PROXIES_JSON" <<'PY'
import json
import sys

skip_types = {
    "Compatible",
    "Direct",
    "Pass",
    "Reject",
    "RejectDrop",
    "Selector",
    "URLTest",
}

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

for name, item in data.get("proxies", {}).items():
    if item.get("type") not in skip_types:
        print(name)
PY
)

if [ -n "${LIMIT:-}" ] && [ "$LIMIT" -gt 0 ] 2>/dev/null; then
  PROXY_NAMES=("${PROXY_NAMES[@]:0:$LIMIT}")
fi

total=${#PROXY_NAMES[@]}
ok=0
failed=0

echo "全量测速: $total 个真实节点"
echo "API: $API_BASE"
echo "URL: $TEST_URL"
echo "Timeout: ${TIMEOUT_MS}ms"
echo ""

for name in "${PROXY_NAMES[@]}"; do
  encoded_name=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$name")
  encoded_url=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TEST_URL")
  response=$(curl -s -m "$CURL_MAX_TIME" "$API_BASE/proxies/$encoded_name/delay?timeout=$TIMEOUT_MS&url=$encoded_url")
  delay=$(python3 -c 'import json, sys; data=json.loads(sys.stdin.read() or "{}"); print(data.get("delay", ""))' <<< "$response" 2>/dev/null)

  if [ -n "$delay" ] && [ "$delay" != "0" ]; then
    ok=$((ok + 1))
    printf '[OK] %-45s %sms\n' "$name" "$delay"
  else
    failed=$((failed + 1))
    message=$(python3 -c 'import json, sys; data=json.loads(sys.stdin.read() or "{}"); print(data.get("message", "测速失败"))' <<< "$response" 2>/dev/null)
    printf '[--] %-45s %s\n' "$name" "$message"
  fi
done

echo ""
echo "测速完成: 可用 $ok / 失败 $failed / 总计 $total"
