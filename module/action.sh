#!/system/bin/sh
set -e

MODDIR="${0%/*}"
CONFIG_FILE="$MODDIR/confige.txt"
APPLIST_CONF="$MODDIR/applist.conf"

RAW_BASE="https://raw.githubusercontent.com/AkiHaza/Comet-Thread-Opt/main"
API_URL="https://api.github.com/repos/AkiHaza/Comet-Thread-Opt/commits"
PER_PAGE=22

TMP_GAME="$MODDIR/.tmp_game.$$"
TMP_RULES="$MODDIR/.tmp_rules.$$"
API_RESPONSE="$MODDIR/.api_response.$$"

cleanup() {
    rm -f "$TMP_GAME" "$TMP_RULES" "$API_RESPONSE"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

download_file() {
    local url="$1"
    local output="$2"

    rm -f "$output"
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL --connect-timeout 10 -o "$output" "$url"; then
            rm -f "$output"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q -T 10 -O "$output" "$url"; then
            rm -f "$output"
            return 1
        fi
    else
        return 1
    fi

    if [ ! -s "$output" ]; then
        rm -f "$output"
        return 1
    fi
}

get_config_value() {
    [ -f "$CONFIG_FILE" ] || return 0
    grep -E "^$1=" "$CONFIG_FILE" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\r\n'
}

set_config_value() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$CONFIG_FILE"
    fi
}

MODE_VAL="$(get_config_value mode)"
SOC_8G3="$(get_config_value 8G3)"
TIME_AREA="$(get_config_value time_area)"
LAST_TIME="$(get_config_value time)"

[ "$MODE_VAL" = "mix" ] || MODE_VAL="app"
[ "$SOC_8G3" = "on" ] || SOC_8G3="off"
[ -n "$TIME_AREA" ] || TIME_AREA="UTC"

if [ "$SOC_8G3" = "on" ]; then
    PROFILE_NAME="8G3"
    APP_URL="$RAW_BASE/app/App_8G3.txt"
    GAME_URL="$RAW_BASE/game/Game_8G3.txt"
else
    PROFILE_NAME="Common"
    APP_URL="$RAW_BASE/app/App_common.txt"
    GAME_URL="$RAW_BASE/game/Game_common.txt"
fi

echo "-------------------------------------"
echo "📱 当前配置: $PROFILE_NAME / $MODE_VAL"
echo "⬇️  正在下载 $PROFILE_NAME App 配置..."
if ! download_file "$APP_URL" "$TMP_RULES"; then
    echo "❌ App 配置下载失败，请检查网络"
    echo "⚠️  已保留当前配置"
    exit 1
fi

GAME_UPDATED=0
if [ "$MODE_VAL" = "mix" ]; then
    echo "⬇️  正在下载 $PROFILE_NAME Game 配置..."
    if ! download_file "$GAME_URL" "$TMP_GAME"; then
        echo "❌ Game 配置下载失败，请检查网络"
        echo "⚠️  已保留当前配置，避免 Mix 规则不完整"
        exit 1
    fi
    printf '\n' >> "$TMP_RULES"
    cat "$TMP_GAME" >> "$TMP_RULES"
    GAME_UPDATED=1
fi

mv -f "$TMP_RULES" "$APPLIST_CONF"

if ! UPDATE_TIME=$(TZ="$TIME_AREA" date +"%m%d %H:%M" 2>/dev/null); then
    TIME_AREA=UTC
    UPDATE_TIME=$(TZ=UTC date +"%m%d %H:%M")
    set_config_value time_area "$TIME_AREA"
fi
MODE_NAME="App"
[ "$MODE_VAL" = "mix" ] && MODE_NAME="Mix"
sed -i "/^description=/ s|^description=.*|description=彗星线程分配 $PROFILE_NAME $MODE_NAME 配置时间:${UPDATE_TIME}|" "$MODDIR/module.prop"

UTC_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
set_config_value time "$UTC_TIME"

echo "-------------------------------------"
echo "✅ $PROFILE_NAME App 配置已更新"
[ "$GAME_UPDATED" = "1" ] && echo "✅ $PROFILE_NAME Game 配置已更新"
echo "-------------------------------------"
echo "📝 更新内容:"

if [ -n "$LAST_TIME" ]; then
    FETCH_URL="${API_URL}?sha=main&since=${LAST_TIME}&per_page=${PER_PAGE}"
else
    FETCH_URL="${API_URL}?sha=main&per_page=${PER_PAGE}"
fi

HTTP_CODE=""
if command -v curl >/dev/null 2>&1; then
    set +e
    HTTP_CODE=$(curl -sSL --connect-timeout 10 -A "Comet-Thread-Opt" \
        -H "Accept: application/vnd.github+json" \
        -o "$API_RESPONSE" -w "%{http_code}" "$FETCH_URL" 2>/dev/null)
    set -e
fi

if [ "$HTTP_CODE" = "200" ]; then
    set +e
    NEW_COMMITS=$(grep -Eo '"message"[[:space:]]*:[[:space:]]*"[^"]*"' "$API_RESPONSE" | \
        sed 's/^"message"[[:space:]]*:[[:space:]]*"//;s/"$//' | \
        sed 's/\\n.*//' | grep -E "^(App|Game):")
    set -e
    if [ -n "$NEW_COMMITS" ]; then
        echo "$NEW_COMMITS"
    else
        echo "暂无新更新"
    fi
elif [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "429" ]; then
    echo "⚠️  GitHub API 请求过于频繁，请稍后再试"
elif [ -z "$HTTP_CODE" ]; then
    echo "⚠️  当前环境缺少 curl，已跳过更新日志查询"
else
    echo "⚠️  GitHub API 返回错误 ($HTTP_CODE)"
fi

echo "-------------------------------------"
echo "🎉 配置更新完成，无需重启"
