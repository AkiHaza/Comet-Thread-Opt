#!/system/bin/sh
set -e
MODDIR="${0%/*}"

APP_URL="https://raw.githubusercontent.com/AkiHaza/Comet-Thread-Opt/main/app/App_8G3.txt"
GAME_URL="https://raw.githubusercontent.com/AkiHaza/Comet-Thread-Opt/main/game/Game_8G3.txt"
API_URL="https://api.github.com/repos/AkiHaza/Comet-Thread-Opt/commits"

APPLIST_CONF="${MODDIR}/applist.conf"
CONFIG_FILE="${MODDIR}/config.txt"

TMP_APP="${MODDIR}/.tmp_app"
TMP_GAME="${MODDIR}/.tmp_game"
GAME_C=0

PER_PAGE=22

cleanup() { rm -f "$TMP_APP" "$TMP_GAME" "${MODDIR}/.api_response"; }
trap cleanup EXIT

download_file() {
    local url="$1" output="${2:-}"
    if command -v curl >/dev/null 2>&1; then
        if [ -z "$output" ]; then
            curl -fsSL --connect-timeout 10 "$url"
        else
            curl -fsSL --connect-timeout 10 -o "$output" "$url"
        fi
    elif command -v wget >/dev/null 2>&1; then
        if [ -z "$output" ]; then
            wget -q -T 10 -O - "$url"
        else
            wget -q -T 10 -O "$output" "$url"
        fi
    else
        return 1
    fi
}

MODE_VAL="app"
TIME_AREA="UTC"
LAST_TIME=""
if [ -f "$CONFIG_FILE" ]; then
    MODE_VAL=$(grep -E '^mode=' "$CONFIG_FILE" | cut -d= -f2 | tr -d '\r\n')
    TIME_AREA=$(grep -E '^time_area=' "$CONFIG_FILE" | cut -d= -f2 | tr -d '\r\n')
    LAST_TIME=$(grep -E '^time=' "$CONFIG_FILE" | head -n1 | cut -d= -f2- | tr -d '\r\n')
fi
[ -z "$MODE_VAL" ] && MODE_VAL="app"
[ -z "$TIME_AREA" ] && TIME_AREA="UTC"

echo "⬇️  正在下载 App 配置..."
if ! download_file "$APP_URL" "$TMP_APP"; then
    echo "❌ 下载 App 配置失败，请检查网络"
    exit 1
fi
cat "$TMP_APP" > "$APPLIST_CONF"

if [ "$MODE_VAL" = "mix" ]; then
    echo "⬇️  正在下载 Game 配置..."
    if download_file "$GAME_URL" "$TMP_GAME"; then
        echo "" >> "$APPLIST_CONF"
        cat "$TMP_GAME" >> "$APPLIST_CONF"
        GAME_C=1
    else
        echo "⚠️  Game 配置下载失败，仅使用 App 配置"
    fi
fi

UPDATE_TIME=$(TZ="$TIME_AREA" date +"%m%d %H:%M")
MODE_NAME="App"
[ "$MODE_VAL" = "mix" ] && MODE_NAME="Mix"
sed -i "/^description=/ s/^description=.*/description=彗星线程分配 $MODE_NAME 配置时间:${UPDATE_TIME}/" "${MODDIR}/module.prop"

UTC_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
sed -i "s/^time=.*/time=$UTC_TIME/" "$CONFIG_FILE"

echo "-------------------------------------"
echo "✅ App 配置已更新"
[ "$GAME_C" = "1" ] && echo "✅ Game 配置已更新"
echo "-------------------------------------"
echo "📝 更新内容:"

if [ -n "$LAST_TIME" ]; then
    FETCH_URL="${API_URL}?sha=main&since=${LAST_TIME}&per_page=${PER_PAGE}"
else
    FETCH_URL="${API_URL}?sha=main&per_page=${PER_PAGE}"
fi

set +e
HTTP_CODE=$(curl -sSL --connect-timeout 10 -A "Comet-Thread-Opt" \
    -H "Accept: application/vnd.github+json" \
    -o "${MODDIR}/.api_response" -w "%{http_code}" "$FETCH_URL" 2>/dev/null)
set -e

if [ "$HTTP_CODE" = "200" ]; then
    set +e
    NEW_COMMITS=$(grep -Eo '"message":"[^"]*"' "${MODDIR}/.api_response" | \
        sed 's/"message":"//;s/"$//' | sed 's/\\n.*//' | grep -E "^(App|Game):")
    set -e
    if [ -n "$NEW_COMMITS" ]; then
        echo "$NEW_COMMITS"
    else
        echo "暂无新更新"
    fi
elif [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "429" ]; then
    echo "⚠️  GitHub API 请求过于频繁,请稍后再试"
else
    echo "⚠️  GitHub API 返回错误 ($HTTP_CODE)"
fi

echo "-------------------------------------"
echo "🎉 配置更新完成"