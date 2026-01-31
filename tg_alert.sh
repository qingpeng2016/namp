#!/bin/bash

# Telegram 报警脚本 - 发送消息到 TG 群
# 用法: ./tg_alert.sh [消息内容]
# 示例: ./tg_alert.sh "hello bot"
# 示例: ./tg_alert.sh "扫描完成: 发现 3 个开放端口"

# ========== 请填写以下两项 ==========
# 1. Bot Token（从 @BotFather 获取，已填）
BOT_TOKEN="8520699314:AAEYwn1MPGZvQ-ezc6-ff0CzwooenQu2UKY"

# 2. 群的 Chat ID（把机器人加进群后，在群里发一条消息，然后浏览器打开下面链接查看）
#    https://api.telegram.org/bot${BOT_TOKEN}/getUpdates
#    在返回的 JSON 里找 "chat":{"id":-100xxxxxxxxxx} ，把那个数字填到下面（含负号）
CHAT_ID="-5054662630"
# =====================================

# 要发送的文本：有参数用参数，没有则默认 "hello bot"
TEXT="${1:-hello bot}"

if [ -z "$CHAT_ID" ]; then
    echo "错误: 请先填写 CHAT_ID"
    echo "  1. 把机器人 @LaLaScanAlertBot 加进你的报警群"
    echo "  2. 在群里随便发一条消息"
    echo "  3. 浏览器打开: https://api.telegram.org/bot${BOT_TOKEN}/getUpdates"
    echo "  4. 在页面里找到 \"chat\":{\"id\":-100xxxxx} ，把 id 的值填到本脚本的 CHAT_ID="
    exit 1
fi

# 调用 Telegram API 发消息（--data-urlencode 支持多行和特殊字符）
URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
RESPONSE=$(curl -sS -X POST "$URL" \
    -d "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${TEXT}" \
    -d "disable_web_page_preview=true")

# 简单检查是否成功
if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo "已发送到 TG: $TEXT"
else
    echo "发送失败。接口返回: $RESPONSE"
    exit 1
fi
