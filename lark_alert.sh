#!/bin/bash

# Lark（飞书）报警脚本 - 发送消息到飞书群
# 用法: ./lark_alert.sh [消息内容]
# 示例: ./lark_alert.sh "hello bot"
# 示例: ./lark_alert.sh "扫描完成: 发现 3 个开放端口"
# 逻辑与 tg_alert.sh 一致，仅发送目标为 Lark

# ========== 请填写 Webhook 地址 ==========
# 飞书群 → 设置 → 群机器人 → 添加机器人 → 自定义机器人 → 复制 Webhook 地址
# 格式: https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
WEBHOOK_URL="https://open.larksuite.com/open-apis/bot/v2/hook/6b08434f-1687-47fc-9ab5-4d85031681cf"
# =====================================

# 要发送的文本：有参数用参数，没有则默认 "hello bot"
TEXT="${1:-hello bot}"

if [ -z "$WEBHOOK_URL" ]; then
    echo "错误: 请先填写 WEBHOOK_URL"
    echo "  1. 飞书群 → 设置 → 群机器人 → 添加机器人 → 自定义机器人"
    echo "  2. 复制 Webhook 地址，填到本脚本的 WEBHOOK_URL="
    exit 1
fi

# 构建 JSON（支持多行和特殊字符）：优先用 jq，否则用 python3
if command -v jq &>/dev/null; then
    BODY=$(jq -n --arg t "$TEXT" '{msg_type:"text",content:{text:$t}}')
else
    BODY=$(printf '%s' "$TEXT" | python3 -c 'import json,sys; print(json.dumps({"msg_type":"text","content":{"text":sys.stdin.read()}}, ensure_ascii=False))' 2>/dev/null) || {
        echo "错误: 需要安装 jq 或 python3 以构建 JSON。可执行: yum install -y jq 或 dnf install -y jq"
        exit 1
    }
fi

# 调用 Lark Webhook 发消息
RESPONSE=$(curl -4 -sS -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$BODY")

# 简单检查是否成功（飞书成功返回 code 为 0 或 StatusCode 为 0）
if echo "$RESPONSE" | grep -qE '"code":\s*0|"StatusCode":\s*0'; then
    echo "已发送到 Lark: $TEXT"
else
    echo "发送失败。接口返回: $RESPONSE"
    exit 1
fi
