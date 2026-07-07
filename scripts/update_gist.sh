#!/bin/bash
# せどりナレッジベース → GitHub Gist 自動更新スクリプト

CONFIG_FILE="$(dirname "$0")/../.gist_config"
SEDORI_FILE="$(dirname "$0")/../knowledge/sedori.md"

# 設定読み込み
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: .gist_config が見つかりません"
  exit 1
fi
source "$CONFIG_FILE"

# コンテンツをJSON文字列に変換
CONTENT=$(python3 -c "import sys,json; print(json.dumps(open(sys.argv[1]).read()))" "$SEDORI_FILE")

# Gist更新
RESULT=$(curl -s -X PATCH \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/gists/$GIST_ID" \
  -d "{
    \"files\": {
      \"sedori.md\": {
        \"content\": $CONTENT
      }
    }
  }")

# 結果確認
if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('id') else 1)" 2>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M')] Gist更新成功"
else
  echo "[$(date '+%Y-%m-%d %H:%M')] Gist更新失敗: $RESULT"
fi
