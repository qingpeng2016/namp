#!/bin/bash

# 端口测试脚本
# 用法: ./test_port.sh <IP地址> <端口1> [端口2] [端口3] ...
# 示例: ./test_port.sh 183.2.133.238 10161
# 示例: ./test_port.sh 183.2.133.238 10161 10162 25100

set +e  # 允许命令失败，继续执行

# 检查参数
if [ $# -lt 2 ]; then
    echo "错误: 请提供IP地址和至少一个端口作为参数"
    echo "用法: $0 <IP地址> <端口1> [端口2] [端口3] ..."
    echo "示例: $0 183.2.133.238 10161"
    echo "示例: $0 183.2.133.238 10161 10162 25100"
    exit 1
fi

TARGET_IP="$1"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 删除当前文件夹下所有匹配 out_IP_*.txt 的文件
find "$SCRIPT_DIR" -maxdepth 1 -type f -name "out_${TARGET_IP}_*.txt" -delete 2>/dev/null || true

# 创建带时间戳的输出文件名（格式：out_IP_时间戳.txt）
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
OUTPUT_FILE="$SCRIPT_DIR/out_${TARGET_IP}_${TIMESTAMP}.txt"

# 将所有输出重定向到文件（同时保留终端输出）
exec > >(tee "$OUTPUT_FILE") 2>&1
shift  # 移除第一个参数（IP地址）
PORTS=("$@")  # 剩余的所有参数都是端口

echo "=========================================="
echo "端口测试脚本"
echo "目标IP: $TARGET_IP"
echo "端口: ${PORTS[*]}"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""

# 全局结果数组（用于最后生成表格）
# 协议顺序：TLS, WS, SSL, HTTPS, HTTP
declare -a TEST_PORTS
declare -a TEST_RESULTS
declare -a TEST_COMMANDS
declare -a TEST_TLS_PROBS
declare -a TEST_WS_PROBS
declare -a TEST_SSL_PROBS
declare -a TEST_HTTPS_PROBS
declare -a TEST_HTTP_PROBS
TEST_COUNT=0

# 每个端口的最终概率（用于最后汇总）
declare -A PORT_FINAL_TLS_PROB
declare -A PORT_FINAL_WS_PROB
declare -A PORT_FINAL_SSL_PROB
declare -A PORT_FINAL_HTTPS_PROB
declare -A PORT_FINAL_HTTP_PROB

# 测试单个端口的函数
test_single_port() {
    local PORT="$1"
    
    echo "=========================================="
    echo "测试端口: $PORT"
    echo "=========================================="
    echo ""
    
    # 初始化判断变量（每个端口独立）
    local IS_HTTPS=false
    local IS_HTTP=false
    local IS_TLS=false
    local IS_SSL=false
    local IS_WS=false
    local IS_CONNECTED=false
    
    # 当前端口的最终概率（用于最后汇总）
    local FINAL_TLS_PROB=0
    local FINAL_WS_PROB=0
    local FINAL_SSL_PROB=0
    local FINAL_HTTPS_PROB=0
    local FINAL_HTTP_PROB=0

    # 1. HTTP 扫描（明文 Web）
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. HTTP 扫描（明文 Web）"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "执行命令: curl -sS -m 5 -v http://${TARGET_IP}:${PORT}/"
    echo ""
    local HTTP_OUTPUT=$(curl -sS -m 5 -v "http://${TARGET_IP}:${PORT}/" 2>&1 || true)
    echo "$HTTP_OUTPUT"
    echo ""

    # 分析HTTP结果
    # 协议概率：TLS, WS, SSL, HTTPS, HTTP
    local HTTP_RESULT="失败"
    local HTTP_TLS_PROB=0
    local HTTP_WS_PROB=0
    local HTTP_SSL_PROB=0
    local HTTP_HTTPS_PROB=0
    local HTTP_HTTP_PROB=0

    # 判定为 HTTP 的标准：HTTP/1.1 200/301/302/400/401/403/404，或返回 Server:/Content-Type:
    if echo "$HTTP_OUTPUT" | grep -qiE "(HTTP/1\.1 (200|301|302|400|401|403|404)|Server:|Content-Type:)" && ! echo "$HTTP_OUTPUT" | grep -qiE "(Empty reply from server|Connection reset by peer)"; then
        # HTTP响应是明确的HTTP协议特征 - 100%
        IS_HTTP=true
        IS_CONNECTED=true
        HTTP_RESULT="检测到HTTP服务（明确的HTTP协议）"
        HTTP_TLS_PROB=0
        HTTP_WS_PROB=0
        HTTP_SSL_PROB=0
        HTTP_HTTPS_PROB=0
        HTTP_HTTP_PROB=100
    elif echo "$HTTP_OUTPUT" | grep -qiE "(Empty reply from server|Connection reset by peer)"; then
        # 非 HTTP：Empty reply from server, Connection reset by peer
        HTTP_RESULT="非HTTP服务"
        HTTP_TLS_PROB=0
        HTTP_WS_PROB=0
        HTTP_SSL_PROB=0
        HTTP_HTTPS_PROB=0
        HTTP_HTTP_PROB=0
    else
        HTTP_RESULT="连接失败或无HTTP响应"
        HTTP_TLS_PROB=0
        HTTP_WS_PROB=0
        HTTP_SSL_PROB=0
        HTTP_HTTPS_PROB=0
        HTTP_HTTP_PROB=0
    fi
    TEST_PORTS[$TEST_COUNT]="$PORT"
    TEST_COMMANDS[$TEST_COUNT]="curl -sS -m 5 -v http://${TARGET_IP}:${PORT}/"
    TEST_RESULTS[$TEST_COUNT]="$HTTP_RESULT"
    TEST_TLS_PROBS[$TEST_COUNT]=$HTTP_TLS_PROB
    TEST_WS_PROBS[$TEST_COUNT]=$HTTP_WS_PROB
    TEST_SSL_PROBS[$TEST_COUNT]=$HTTP_SSL_PROB
    TEST_HTTPS_PROBS[$TEST_COUNT]=$HTTP_HTTPS_PROB
    TEST_HTTP_PROBS[$TEST_COUNT]=$HTTP_HTTP_PROB
    TEST_COUNT=$((TEST_COUNT + 1))
    
    # 更新最终概率（取最大值）
    if [ $HTTP_TLS_PROB -gt $FINAL_TLS_PROB ]; then FINAL_TLS_PROB=$HTTP_TLS_PROB; fi
    if [ $HTTP_WS_PROB -gt $FINAL_WS_PROB ]; then FINAL_WS_PROB=$HTTP_WS_PROB; fi
    if [ $HTTP_SSL_PROB -gt $FINAL_SSL_PROB ]; then FINAL_SSL_PROB=$HTTP_SSL_PROB; fi
    if [ $HTTP_HTTPS_PROB -gt $FINAL_HTTPS_PROB ]; then FINAL_HTTPS_PROB=$HTTP_HTTPS_PROB; fi
    if [ $HTTP_HTTP_PROB -gt $FINAL_HTTP_PROB ]; then FINAL_HTTP_PROB=$HTTP_HTTP_PROB; fi
    echo ""

    # 2. HTTPS 扫描（HTTP over TLS）
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "2. HTTPS 扫描（HTTP over TLS）"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "执行命令: curl -k -sS -m 5 -v https://${TARGET_IP}:${PORT}/"
    echo ""
    local HTTPS_OUTPUT=$(curl -k -sS -m 5 -v "https://${TARGET_IP}:${PORT}/" 2>&1 || true)
    echo "$HTTPS_OUTPUT"
    echo ""

    # 分析HTTPS结果
    # 协议概率：TLS, WS, SSL, HTTPS, HTTP
    local HTTPS_RESULT="失败"
    local HTTPS_TLS_PROB=0
    local HTTPS_WS_PROB=0
    local HTTPS_SSL_PROB=0
    local HTTPS_HTTPS_PROB=0
    local HTTPS_HTTP_PROB=0

    # 判定为 HTTPS：TLS 握手成功 + HTTP/1.1 xxx
    if echo "$HTTPS_OUTPUT" | grep -qiE "(SSL connection using TLSv|HTTP/1\.1 [0-9]+)" && ! echo "$HTTPS_OUTPUT" | grep -qiE "(SSL_ERROR_SYSCALL|wrong version number|handshake failure)"; then
        # HTTPS响应是明确的HTTPS协议特征 - 100%
        IS_HTTPS=true
        IS_CONNECTED=true
        HTTPS_RESULT="检测到HTTPS服务（明确的HTTPS协议）"
        HTTPS_TLS_PROB=0
        HTTPS_WS_PROB=0
        HTTPS_SSL_PROB=0
        HTTPS_HTTPS_PROB=100
        HTTPS_HTTP_PROB=0
    elif echo "$HTTPS_OUTPUT" | grep -qiE "(SSL_ERROR_SYSCALL|wrong version number|handshake failure)"; then
        # 非 HTTPS：SSL_ERROR_SYSCALL, wrong version number, handshake failure
        HTTPS_RESULT="非HTTPS服务"
        HTTPS_TLS_PROB=0
        HTTPS_WS_PROB=0
        HTTPS_SSL_PROB=0
        HTTPS_HTTPS_PROB=0
        HTTPS_HTTP_PROB=0
    else
        HTTPS_RESULT="连接失败"
        HTTPS_TLS_PROB=0
        HTTPS_WS_PROB=0
        HTTPS_SSL_PROB=0
        HTTPS_HTTPS_PROB=0
        HTTPS_HTTP_PROB=0
    fi
    TEST_PORTS[$TEST_COUNT]="$PORT"
    TEST_COMMANDS[$TEST_COUNT]="curl -k -sS -m 5 -v https://${TARGET_IP}:${PORT}/"
    TEST_RESULTS[$TEST_COUNT]="$HTTPS_RESULT"
    TEST_TLS_PROBS[$TEST_COUNT]=$HTTPS_TLS_PROB
    TEST_WS_PROBS[$TEST_COUNT]=$HTTPS_WS_PROB
    TEST_SSL_PROBS[$TEST_COUNT]=$HTTPS_SSL_PROB
    TEST_HTTPS_PROBS[$TEST_COUNT]=$HTTPS_HTTPS_PROB
    TEST_HTTP_PROBS[$TEST_COUNT]=$HTTPS_HTTP_PROB
    TEST_COUNT=$((TEST_COUNT + 1))
    
    # 更新最终概率（取最大值）
    if [ $HTTPS_TLS_PROB -gt $FINAL_TLS_PROB ]; then FINAL_TLS_PROB=$HTTPS_TLS_PROB; fi
    if [ $HTTPS_WS_PROB -gt $FINAL_WS_PROB ]; then FINAL_WS_PROB=$HTTPS_WS_PROB; fi
    if [ $HTTPS_SSL_PROB -gt $FINAL_SSL_PROB ]; then FINAL_SSL_PROB=$HTTPS_SSL_PROB; fi
    if [ $HTTPS_HTTPS_PROB -gt $FINAL_HTTPS_PROB ]; then FINAL_HTTPS_PROB=$HTTPS_HTTPS_PROB; fi
    if [ $HTTPS_HTTP_PROB -gt $FINAL_HTTP_PROB ]; then FINAL_HTTP_PROB=$HTTPS_HTTP_PROB; fi
    echo ""

    # 3. SSL/TLS 扫描（纯 TLS，不一定是 HTTP）
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "3. SSL/TLS 扫描（纯 TLS，不一定是 HTTP）"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "执行命令: openssl s_client -connect ${TARGET_IP}:${PORT} -servername ${TARGET_IP} -brief"
    echo ""
    local SSL_OUTPUT=$(timeout 5 openssl s_client -connect "${TARGET_IP}:${PORT}" -servername "${TARGET_IP}" -brief </dev/null 2>&1 || true)
    echo "$SSL_OUTPUT"
    echo ""

    # 分析SSL/TLS结果
    # 协议概率：TLS, WS, SSL, HTTPS, HTTP
    local SSL_RESULT="失败"
    local SSL_TLS_PROB=0
    local SSL_WS_PROB=0
    local SSL_SSL_PROB=0
    local SSL_HTTPS_PROB=0
    local SSL_HTTP_PROB=0

    # 判定为 TLS/SSL：Protocol: TLSv1.x, Cipher:, Server certificate
    if echo "$SSL_OUTPUT" | grep -qiE "(Protocol.*TLSv|Cipher.*:|Server certificate)"; then
        # SSL/TLS连接成功 - 明确的SSL/TLS协议特征 - 100%
        IS_TLS=true
        IS_SSL=true
        IS_CONNECTED=true
        SSL_RESULT="检测到SSL/TLS服务（明确的SSL/TLS协议）"
        SSL_TLS_PROB=100
        SSL_WS_PROB=0
        SSL_SSL_PROB=100
        SSL_HTTPS_PROB=0
        SSL_HTTP_PROB=0
    else
        SSL_RESULT="未检测到SSL/TLS服务"
        SSL_TLS_PROB=0
        SSL_WS_PROB=0
        SSL_SSL_PROB=0
        SSL_HTTPS_PROB=0
        SSL_HTTP_PROB=0
    fi
    TEST_PORTS[$TEST_COUNT]="$PORT"
    TEST_COMMANDS[$TEST_COUNT]="openssl s_client -connect ${TARGET_IP}:${PORT} -servername ${TARGET_IP} -brief"
    TEST_RESULTS[$TEST_COUNT]="$SSL_RESULT"
    TEST_TLS_PROBS[$TEST_COUNT]=$SSL_TLS_PROB
    TEST_WS_PROBS[$TEST_COUNT]=$SSL_WS_PROB
    TEST_SSL_PROBS[$TEST_COUNT]=$SSL_SSL_PROB
    TEST_HTTPS_PROBS[$TEST_COUNT]=$SSL_HTTPS_PROB
    TEST_HTTP_PROBS[$TEST_COUNT]=$SSL_HTTP_PROB
    TEST_COUNT=$((TEST_COUNT + 1))
    
    # 更新最终概率（取最大值）
    if [ $SSL_TLS_PROB -gt $FINAL_TLS_PROB ]; then FINAL_TLS_PROB=$SSL_TLS_PROB; fi
    if [ $SSL_WS_PROB -gt $FINAL_WS_PROB ]; then FINAL_WS_PROB=$SSL_WS_PROB; fi
    if [ $SSL_SSL_PROB -gt $FINAL_SSL_PROB ]; then FINAL_SSL_PROB=$SSL_SSL_PROB; fi
    if [ $SSL_HTTPS_PROB -gt $FINAL_HTTPS_PROB ]; then FINAL_HTTPS_PROB=$SSL_HTTPS_PROB; fi
    if [ $SSL_HTTP_PROB -gt $FINAL_HTTP_PROB ]; then FINAL_HTTP_PROB=$SSL_HTTP_PROB; fi
    echo ""

    # 4. WebSocket (WS) 扫描（明文）
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "4. WebSocket (WS) 扫描（明文）"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "执行命令: curl -i -N -H \"Connection: Upgrade\" -H \"Upgrade: websocket\" -H \"Sec-WebSocket-Version: 13\" -H \"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\" http://${TARGET_IP}:${PORT}/"
    echo ""
    local WS_OUTPUT=$(curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -m 5 "http://${TARGET_IP}:${PORT}/" 2>&1 || true)
    echo "$WS_OUTPUT"
    echo ""

    # 分析WebSocket结果
    # 协议概率：TLS, WS, SSL, HTTPS, HTTP
    local WS_RESULT="失败"
    local WS_TLS_PROB=0
    local WS_WS_PROB=0
    local WS_SSL_PROB=0
    local WS_HTTPS_PROB=0
    local WS_HTTP_PROB=0

    # 判定为 WS：HTTP/1.1 101 Switching Protocols + Upgrade: websocket
    if echo "$WS_OUTPUT" | grep -qiE "(HTTP/1\.1 101 Switching Protocols|Upgrade: websocket)" && ! echo "$WS_OUTPUT" | grep -qiE "(HTTP/1\.1 (400|404)|Empty reply)"; then
        # WebSocket响应是明确的WS协议特征 - 100%
        IS_WS=true
        IS_CONNECTED=true
        WS_RESULT="检测到WebSocket服务（明确的WS协议）"
        WS_TLS_PROB=0
        WS_WS_PROB=100
        WS_SSL_PROB=0
        WS_HTTPS_PROB=0
        WS_HTTP_PROB=0
    elif echo "$WS_OUTPUT" | grep -qiE "(HTTP/1\.1 (400|404)|Empty reply)"; then
        # 非 WS：400/404, Empty reply
        WS_RESULT="非WebSocket服务"
        WS_TLS_PROB=0
        WS_WS_PROB=0
        WS_SSL_PROB=0
        WS_HTTPS_PROB=0
        WS_HTTP_PROB=0
    else
        WS_RESULT="连接失败或无WebSocket响应"
        WS_TLS_PROB=0
        WS_WS_PROB=0
        WS_SSL_PROB=0
        WS_HTTPS_PROB=0
        WS_HTTP_PROB=0
    fi
    TEST_PORTS[$TEST_COUNT]="$PORT"
    TEST_COMMANDS[$TEST_COUNT]="curl -i -N -H \"Connection: Upgrade\" -H \"Upgrade: websocket\" -H \"Sec-WebSocket-Version: 13\" -H \"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\" http://${TARGET_IP}:${PORT}/"
    TEST_RESULTS[$TEST_COUNT]="$WS_RESULT"
    TEST_TLS_PROBS[$TEST_COUNT]=$WS_TLS_PROB
    TEST_WS_PROBS[$TEST_COUNT]=$WS_WS_PROB
    TEST_SSL_PROBS[$TEST_COUNT]=$WS_SSL_PROB
    TEST_HTTPS_PROBS[$TEST_COUNT]=$WS_HTTPS_PROB
    TEST_HTTP_PROBS[$TEST_COUNT]=$WS_HTTP_PROB
    TEST_COUNT=$((TEST_COUNT + 1))
    
    # 更新最终概率（取最大值）
    if [ $WS_TLS_PROB -gt $FINAL_TLS_PROB ]; then FINAL_TLS_PROB=$WS_TLS_PROB; fi
    if [ $WS_WS_PROB -gt $FINAL_WS_PROB ]; then FINAL_WS_PROB=$WS_WS_PROB; fi
    if [ $WS_SSL_PROB -gt $FINAL_SSL_PROB ]; then FINAL_SSL_PROB=$WS_SSL_PROB; fi
    if [ $WS_HTTPS_PROB -gt $FINAL_HTTPS_PROB ]; then FINAL_HTTPS_PROB=$WS_HTTPS_PROB; fi
    if [ $WS_HTTP_PROB -gt $FINAL_HTTP_PROB ]; then FINAL_HTTP_PROB=$WS_HTTP_PROB; fi
    echo ""

    # 5. WSS 扫描（WebSocket over TLS）
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "5. WSS 扫描（WebSocket over TLS）"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "执行命令: curl -k -i -N -H \"Connection: Upgrade\" -H \"Upgrade: websocket\" -H \"Sec-WebSocket-Version: 13\" -H \"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\" https://${TARGET_IP}:${PORT}/"
    echo ""
    local WSS_OUTPUT=$(curl -k -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -m 5 "https://${TARGET_IP}:${PORT}/" 2>&1 || true)
    echo "$WSS_OUTPUT"
    echo ""

    # 分析WSS结果
    # 协议概率：TLS, WS, SSL, HTTPS, HTTP
    local WSS_RESULT="失败"
    local WSS_TLS_PROB=0
    local WSS_WS_PROB=0
    local WSS_SSL_PROB=0
    local WSS_HTTPS_PROB=0
    local WSS_HTTP_PROB=0

    # 判定为 WSS：TLS 握手成功 + 101 Switching Protocols
    if echo "$WSS_OUTPUT" | grep -qiE "(SSL connection using TLSv|HTTP/1\.1 101 Switching Protocols)" && ! echo "$WSS_OUTPUT" | grep -qiE "(SSL_ERROR_SYSCALL|wrong version number|handshake failure)"; then
        # WSS响应是明确的WSS协议特征 - 100%
        IS_WS=true
        IS_CONNECTED=true
        WSS_RESULT="检测到WSS服务（明确的WSS协议）"
        WSS_TLS_PROB=0
        WSS_WS_PROB=100
        WSS_SSL_PROB=0
        WSS_HTTPS_PROB=0
        WSS_HTTP_PROB=0
    elif echo "$WSS_OUTPUT" | grep -qiE "(SSL_ERROR_SYSCALL|wrong version number|handshake failure)"; then
        # 非 WSS
        WSS_RESULT="非WSS服务"
        WSS_TLS_PROB=0
        WSS_WS_PROB=0
        WSS_SSL_PROB=0
        WSS_HTTPS_PROB=0
        WSS_HTTP_PROB=0
    else
        WSS_RESULT="连接失败或无WSS响应"
        WSS_TLS_PROB=0
        WSS_WS_PROB=0
        WSS_SSL_PROB=0
        WSS_HTTPS_PROB=0
        WSS_HTTP_PROB=0
    fi
    TEST_PORTS[$TEST_COUNT]="$PORT"
    TEST_COMMANDS[$TEST_COUNT]="curl -k -i -N -H \"Connection: Upgrade\" -H \"Upgrade: websocket\" -H \"Sec-WebSocket-Version: 13\" -H \"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\" https://${TARGET_IP}:${PORT}/"
    TEST_RESULTS[$TEST_COUNT]="$WSS_RESULT"
    TEST_TLS_PROBS[$TEST_COUNT]=$WSS_TLS_PROB
    TEST_WS_PROBS[$TEST_COUNT]=$WSS_WS_PROB
    TEST_SSL_PROBS[$TEST_COUNT]=$WSS_SSL_PROB
    TEST_HTTPS_PROBS[$TEST_COUNT]=$WSS_HTTPS_PROB
    TEST_HTTP_PROBS[$TEST_COUNT]=$WSS_HTTP_PROB
    TEST_COUNT=$((TEST_COUNT + 1))
    
    # 更新最终概率（取最大值）
    if [ $WSS_TLS_PROB -gt $FINAL_TLS_PROB ]; then FINAL_TLS_PROB=$WSS_TLS_PROB; fi
    if [ $WSS_WS_PROB -gt $FINAL_WS_PROB ]; then FINAL_WS_PROB=$WSS_WS_PROB; fi
    if [ $WSS_SSL_PROB -gt $FINAL_SSL_PROB ]; then FINAL_SSL_PROB=$WSS_SSL_PROB; fi
    if [ $WSS_HTTPS_PROB -gt $FINAL_HTTPS_PROB ]; then FINAL_HTTPS_PROB=$WSS_HTTPS_PROB; fi
    if [ $WSS_HTTP_PROB -gt $FINAL_HTTP_PROB ]; then FINAL_HTTP_PROB=$WSS_HTTP_PROB; fi
    echo ""
    
    # 保存当前端口的最终概率
    PORT_FINAL_TLS_PROB[$PORT]=$FINAL_TLS_PROB
    PORT_FINAL_WS_PROB[$PORT]=$FINAL_WS_PROB
    PORT_FINAL_SSL_PROB[$PORT]=$FINAL_SSL_PROB
    PORT_FINAL_HTTPS_PROB[$PORT]=$FINAL_HTTPS_PROB
    PORT_FINAL_HTTP_PROB[$PORT]=$FINAL_HTTP_PROB
}

# 主程序：循环测试所有端口
for PORT in "${PORTS[@]}"; do
    test_single_port "$PORT"
done

# 总结和判断
echo "=========================================="
echo "测试完成！"
echo "=========================================="
# 输出测试结果表格
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 测试结果汇总表格"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 打印表格头部（端口 | 命令 | TLS | WS | SSL | HTTPS | HTTP）
# 使用column命令来确保列对齐
printf "%s\n" "----------------------------------------------------------------------------------------------------------------------------------------------------------------------"

# 先准备数据，然后统一用column处理
TEMP_TABLE=$(mktemp)
{
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "端口" "命令" "TLS" "WS" "SSL" "HTTPS" "HTTP"
    
    # 打印表格内容
    PREV_PORT=""
    for ((i=0; i<TEST_COUNT; i++)); do
        PORT="${TEST_PORTS[$i]}"
        CMD="${TEST_COMMANDS[$i]}"
        TLS_PROB="${TEST_TLS_PROBS[$i]:-0}"
        WS_PROB="${TEST_WS_PROBS[$i]:-0}"
        SSL_PROB="${TEST_SSL_PROBS[$i]:-0}"
        HTTPS_PROB="${TEST_HTTPS_PROBS[$i]:-0}"
        HTTP_PROB="${TEST_HTTP_PROBS[$i]:-0}"
        
        printf "%s\t%s\t%s%%\t%s%%\t%s%%\t%s%%\t%s%%\n" "$PORT" "$CMD" "$TLS_PROB" "$WS_PROB" "$SSL_PROB" "$HTTPS_PROB" "$HTTP_PROB"
        PREV_PORT="$PORT"
    done
} | column -t -s $'\t' > "$TEMP_TABLE"

# 输出表头
head -1 "$TEMP_TABLE"
printf "%s\n" "----------------------------------------------------------------------------------------------------------------------------------------------------------------------"

# 输出数据，在端口变化时添加分割线
PREV_PORT=""
LINE_NUM=0
while IFS= read -r line; do
    LINE_NUM=$((LINE_NUM + 1))
    # 跳过表头行
    if [ $LINE_NUM -eq 1 ]; then
        continue
    fi
    
    # 提取端口号（第一列）
    CURRENT_PORT=$(echo "$line" | awk '{print $1}')
    
    # 如果端口号变化，添加分割线
    if [ -n "$PREV_PORT" ] && [ "$CURRENT_PORT" != "$PREV_PORT" ]; then
        printf "%s\n" "----------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    fi
    
    echo "$line"
    PREV_PORT="$CURRENT_PORT"
done < "$TEMP_TABLE"

printf "%s\n" "----------------------------------------------------------------------------------------------------------------------------------------------------------------------"
rm -f "$TEMP_TABLE"

# 累计概率（只统计有效的测试）
TOTAL_TLS_PROB=0
TOTAL_WS_PROB=0
TOTAL_SSL_PROB=0
TOTAL_HTTPS_PROB=0
TOTAL_HTTP_PROB=0
VALID_TESTS=0

for ((i=0; i<TEST_COUNT; i++)); do
    TLS_PROB="${TEST_TLS_PROBS[$i]:-0}"
    WS_PROB="${TEST_WS_PROBS[$i]:-0}"
    SSL_PROB="${TEST_SSL_PROBS[$i]:-0}"
    HTTPS_PROB="${TEST_HTTPS_PROBS[$i]:-0}"
    HTTP_PROB="${TEST_HTTP_PROBS[$i]:-0}"
    
    # 累计概率（只统计有效的测试）
    if [ "$TLS_PROB" -gt 0 ] || [ "$WS_PROB" -gt 0 ] || [ "$SSL_PROB" -gt 0 ] || [ "$HTTPS_PROB" -gt 0 ] || [ "$HTTP_PROB" -gt 0 ]; then
        TOTAL_TLS_PROB=$((TOTAL_TLS_PROB + TLS_PROB))
        TOTAL_WS_PROB=$((TOTAL_WS_PROB + WS_PROB))
        TOTAL_SSL_PROB=$((TOTAL_SSL_PROB + SSL_PROB))
        TOTAL_HTTPS_PROB=$((TOTAL_HTTPS_PROB + HTTPS_PROB))
        TOTAL_HTTP_PROB=$((TOTAL_HTTP_PROB + HTTP_PROB))
        VALID_TESTS=$((VALID_TESTS + 1))
    fi
done

if ! command -v column >/dev/null 2>&1; then
    printf "%s\n" "----------------------------------------------------------------------------------------------------------------------------------------------------------------------"
fi
echo ""

# 按端口分组显示最终判断概率
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 最终判断概率"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for PORT in "${PORTS[@]}"; do
    echo "----------------------------------------------------"
    printf "%-20s %-20s %-50s\n" "端口" "协议" "概率"
    echo "----------------------------------------------------"
    
    FINAL_TLS_PROB="${PORT_FINAL_TLS_PROB[$PORT]:-0}"
    FINAL_WS_PROB="${PORT_FINAL_WS_PROB[$PORT]:-0}"
    FINAL_SSL_PROB="${PORT_FINAL_SSL_PROB[$PORT]:-0}"
    FINAL_HTTPS_PROB="${PORT_FINAL_HTTPS_PROB[$PORT]:-0}"
    FINAL_HTTP_PROB="${PORT_FINAL_HTTP_PROB[$PORT]:-0}"
    
    printf "%-20s %-20s %-50s\n" "$PORT" "TLS" "协议概率: ${FINAL_TLS_PROB}%"
    printf "%-20s %-20s %-50s\n" "$PORT" "WS" "协议概率: ${FINAL_WS_PROB}%"
    printf "%-20s %-20s %-50s\n" "$PORT" "SSL" "协议概率: ${FINAL_SSL_PROB}%"
    printf "%-20s %-20s %-50s\n" "$PORT" "HTTPS" "协议概率: ${FINAL_HTTPS_PROB}%"
    printf "%-20s %-20s %-50s\n" "$PORT" "HTTP" "协议概率: ${FINAL_HTTP_PROB}%"
    echo "----------------------------------------------------"
done
echo ""

# 找出概率最高的协议
MAX_PROB=$FINAL_TLS_PROB
MAX_PROTOCOL="TLS"
if [ $FINAL_WS_PROB -gt $MAX_PROB ]; then
    MAX_PROB=$FINAL_WS_PROB
    MAX_PROTOCOL="WS"
fi
if [ $FINAL_SSL_PROB -gt $MAX_PROB ]; then
    MAX_PROB=$FINAL_SSL_PROB
    MAX_PROTOCOL="SSL"
fi
if [ $FINAL_HTTPS_PROB -gt $MAX_PROB ]; then
    MAX_PROB=$FINAL_HTTPS_PROB
    MAX_PROTOCOL="HTTPS"
fi
if [ $FINAL_HTTP_PROB -gt $MAX_PROB ]; then
    MAX_PROB=$FINAL_HTTP_PROB
    MAX_PROTOCOL="HTTP"
fi

# 明确的协议判断逻辑
DETERMINED_PROTOCOL=""
DETERMINED_CONFIDENCE=""

# 检查是否有明确的协议特征
HAS_TLS_VERSION_ERROR=false
HAS_HTTP_09=false
for ((i=0; i<TEST_COUNT; i++)); do
    RESULT="${TEST_RESULTS[$i]}"
    if echo "$RESULT" | grep -qiE "TLS版本不匹配"; then
        HAS_TLS_VERSION_ERROR=true
    fi
    if echo "$RESULT" | grep -qiE "HTTP/0.9|收到HTTP/0.9"; then
        HAS_HTTP_09=true
    fi
done

# 1. 优先检查HTTP/0.9响应（这是最明确的HTTP信号）
if [ "$HAS_HTTP_09" = true ] && [ $FINAL_HTTP_PROB -ge 80 ]; then
    DETERMINED_PROTOCOL="HTTP"
    DETERMINED_CONFIDENCE="高"
elif [ "$HAS_TLS_VERSION_ERROR" = true ] && [ $FINAL_TLS_PROB -ge 70 ]; then
    DETERMINED_PROTOCOL="TLS"
    DETERMINED_CONFIDENCE="高"
elif [ $FINAL_HTTPS_PROB -ge 80 ]; then
    DETERMINED_PROTOCOL="HTTPS"
    DETERMINED_CONFIDENCE="高"
elif [ $FINAL_HTTP_PROB -ge 80 ]; then
    DETERMINED_PROTOCOL="HTTP"
    DETERMINED_CONFIDENCE="高"
elif [ $FINAL_TLS_PROB -ge 70 ]; then
    DETERMINED_PROTOCOL="TLS"
    DETERMINED_CONFIDENCE="中"
elif [ $FINAL_WS_PROB -ge 80 ]; then
    DETERMINED_PROTOCOL="WS"
    DETERMINED_CONFIDENCE="高"
elif [ $FINAL_SSL_PROB -ge 80 ]; then
    DETERMINED_PROTOCOL="SSL"
    DETERMINED_CONFIDENCE="高"
elif [ $MAX_PROB -gt 0 ]; then
    DETERMINED_PROTOCOL="$MAX_PROTOCOL"
    DETERMINED_CONFIDENCE="低"
else
    DETERMINED_PROTOCOL="未知"
    DETERMINED_CONFIDENCE="无"
fi

# 按端口输出最终判断
for PORT in "${PORTS[@]}"; do
    FINAL_TLS_PROB="${PORT_FINAL_TLS_PROB[$PORT]:-0}"
    FINAL_WS_PROB="${PORT_FINAL_WS_PROB[$PORT]:-0}"
    FINAL_SSL_PROB="${PORT_FINAL_SSL_PROB[$PORT]:-0}"
    FINAL_HTTPS_PROB="${PORT_FINAL_HTTPS_PROB[$PORT]:-0}"
    FINAL_HTTP_PROB="${PORT_FINAL_HTTP_PROB[$PORT]:-0}"
    
    # 找出当前端口的最高概率协议
    PORT_MAX_PROB=$FINAL_TLS_PROB
    PORT_MAX_PROTOCOL="TLS"
    if [ $FINAL_WS_PROB -gt $PORT_MAX_PROB ]; then
        PORT_MAX_PROB=$FINAL_WS_PROB
        PORT_MAX_PROTOCOL="WS"
    fi
    if [ $FINAL_SSL_PROB -gt $PORT_MAX_PROB ]; then
        PORT_MAX_PROB=$FINAL_SSL_PROB
        PORT_MAX_PROTOCOL="SSL"
    fi
    if [ $FINAL_HTTPS_PROB -gt $PORT_MAX_PROB ]; then
        PORT_MAX_PROB=$FINAL_HTTPS_PROB
        PORT_MAX_PROTOCOL="HTTPS"
    fi
    if [ $FINAL_HTTP_PROB -gt $PORT_MAX_PROB ]; then
        PORT_MAX_PROB=$FINAL_HTTP_PROB
        PORT_MAX_PROTOCOL="HTTP"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 端口 $PORT 协议判断结果"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ $FINAL_HTTP_PROB -eq 100 ]; then
        echo "✅ **协议类型: HTTP**"
        echo "判断依据:"
        echo "- ✅ 检测到明确的HTTP响应（HTTP/1.1 xxx 或 HTTP/0.9）"
        echo "- ✅ HTTP协议概率: 100%"
    elif [ $FINAL_HTTPS_PROB -eq 100 ]; then
        echo "✅ **协议类型: HTTPS**"
        echo "判断依据:"
        echo "- ✅ TLS握手成功 + HTTP/1.1响应"
        echo "- ✅ HTTPS协议概率: 100%"
    elif [ $FINAL_TLS_PROB -eq 100 ]; then
        echo "✅ **协议类型: TLS**"
        echo "判断依据:"
        echo "- ✅ 检测到TLS版本错误（error:1404B42E:SSL routines:ST_CONNECT:tlsv1 alert protocol version）"
        echo "- ✅ 服务器支持TLS但版本不兼容"
        echo "- ✅ TLS协议概率: 100%"
        echo "- ✅ 这是纯TLS协议服务（不是HTTPS）"
    elif [ $FINAL_SSL_PROB -eq 100 ]; then
        echo "✅ **协议类型: SSL**"
        echo "判断依据:"
        echo "- ✅ SSL连接成功，但证书无HTTP信息"
        echo "- ✅ SSL协议概率: 100%"
    elif [ $FINAL_WS_PROB -eq 100 ]; then
        echo "✅ **协议类型: WS**"
        echo "判断依据:"
        echo "- ✅ 检测到HTTP/1.1 101 Switching Protocols + Upgrade: websocket"
        echo "- ✅ WS协议概率: 100%"
    elif [ $PORT_MAX_PROB -gt 0 ]; then
        echo "⚠️ **协议类型: $PORT_MAX_PROTOCOL (概率: ${PORT_MAX_PROB}%)**"
        echo "判断依据:"
        echo "- ⚠️ TLS协议概率: ${FINAL_TLS_PROB}%"
        echo "- ⚠️ WS协议概率: ${FINAL_WS_PROB}%"
        echo "- ⚠️ SSL协议概率: ${FINAL_SSL_PROB}%"
        echo "- ⚠️ HTTPS协议概率: ${FINAL_HTTPS_PROB}%"
        echo "- ⚠️ HTTP协议概率: ${FINAL_HTTP_PROB}%"
    else
        echo "❌ **协议类型: 未知**"
        echo "判断依据:"
        echo "- ❌ 所有协议概率均为0%"
        echo "- ❌ 端口可能关闭或服务类型未知"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
done

# ========== 汇总检测到的协议，发送到 TG ==========
TG_MSG=""
TG_HEADER="🔔 端口协议检测报警 $(date '+%Y-%m-%d %H:%M:%S')"
TG_SEP="===================================="
TOTAL_PORTS=${#PORTS[@]}
ABNORMAL_COUNT=0
for PORT in "${PORTS[@]}"; do
    FINAL_TLS_PROB="${PORT_FINAL_TLS_PROB[$PORT]:-0}"
    FINAL_WS_PROB="${PORT_FINAL_WS_PROB[$PORT]:-0}"
    FINAL_SSL_PROB="${PORT_FINAL_SSL_PROB[$PORT]:-0}"
    FINAL_HTTPS_PROB="${PORT_FINAL_HTTPS_PROB[$PORT]:-0}"
    FINAL_HTTP_PROB="${PORT_FINAL_HTTP_PROB[$PORT]:-0}"
    HAS_ANY=false
    PORT_BLOCK=""
    # 内网IP：环境变量 INTERNAL_IP（phase2_scan 第3参），未设则用 TARGET_IP
    INTERNAL_IP_DISPLAY="${INTERNAL_IP:-$TARGET_IP}"
    # 用户内网IP：取 TARGET_IP 前 3 段，第 4 段 = 取整((端口-10000)/100)
    FIRST3="${TARGET_IP%.*}"
    FOURTH=$(( (PORT - 10000) / 100 ))
    USER_INTERNAL_IP="${FIRST3}.${FOURTH}"
    if [ "$FINAL_HTTP_PROB" -gt 0 ]; then
        PORT_BLOCK="${PORT_BLOCK}IP: ${TARGET_IP}
内网IP: ${INTERNAL_IP_DISPLAY}
端口: ${PORT}
用户内网IP: ${USER_INTERNAL_IP}
协议: HTTP
命令: curl -sS -m 5 -v http://${TARGET_IP}:${PORT}/
------------------------------------------------
"
        HAS_ANY=true
    fi
    if [ "$FINAL_HTTPS_PROB" -gt 0 ]; then
        PORT_BLOCK="${PORT_BLOCK}IP: ${TARGET_IP}
内网IP: ${INTERNAL_IP_DISPLAY}
端口: ${PORT}
用户内网IP: ${USER_INTERNAL_IP}
协议: HTTPS
命令: curl -k -sS -m 5 -v https://${TARGET_IP}:${PORT}/
------------------------------------------------
"
        HAS_ANY=true
    fi
    if [ "$FINAL_TLS_PROB" -gt 0 ]; then
        PORT_BLOCK="${PORT_BLOCK}IP: ${TARGET_IP}
内网IP: ${INTERNAL_IP_DISPLAY}
端口: ${PORT}
用户内网IP: ${USER_INTERNAL_IP}
协议: TLS
命令: openssl s_client -connect ${TARGET_IP}:${PORT} -servername ${TARGET_IP} -brief
------------------------------------------------
"
        HAS_ANY=true
    fi
    if [ "$FINAL_SSL_PROB" -gt 0 ]; then
        PORT_BLOCK="${PORT_BLOCK}IP: ${TARGET_IP}
内网IP: ${INTERNAL_IP_DISPLAY}
端口: ${PORT}
用户内网IP: ${USER_INTERNAL_IP}
协议: SSL
命令: openssl s_client -connect ${TARGET_IP}:${PORT} -servername ${TARGET_IP} -brief
------------------------------------------------
"
        HAS_ANY=true
    fi
    if [ "$FINAL_WS_PROB" -gt 0 ]; then
        PORT_BLOCK="${PORT_BLOCK}IP: ${TARGET_IP}
内网IP: ${INTERNAL_IP_DISPLAY}
端口: ${PORT}
用户内网IP: ${USER_INTERNAL_IP}
协议: WS
命令: curl -i -N -H \"Connection: Upgrade\" -H \"Upgrade: websocket\" -H \"Sec-WebSocket-Version: 13\" -H \"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\" -m 5 http://${TARGET_IP}:${PORT}/
------------------------------------------------
"
        HAS_ANY=true
    fi
    if [ "$HAS_ANY" = true ]; then
        TG_MSG="${TG_MSG}${PORT_BLOCK}"
        ABNORMAL_COUNT=$((ABNORMAL_COUNT + 1))
    fi
done

# 汇总：IP、内网IP（若有）、检测端口数、异常端口数（始终发到 TG）
TG_SUMMARY="IP: ${TARGET_IP}
"
[ -n "${INTERNAL_IP:-}" ] && TG_SUMMARY="${TG_SUMMARY}内网IP: ${INTERNAL_IP}
"
TG_SUMMARY="${TG_SUMMARY}检测端口数: ${TOTAL_PORTS}
异常端口数: ${ABNORMAL_COUNT}
------------------------------------------------
"
FULL_MSG="${TG_SEP}
${TG_HEADER}
${TG_SUMMARY}${TG_MSG}"

echo "=========================================="
echo "发送协议检测结果到 TG"
echo "=========================================="
if [ -f "$SCRIPT_DIR/tg_alert.sh" ]; then
    "$SCRIPT_DIR/tg_alert.sh" "$FULL_MSG" || echo "⚠️ TG 发送失败或未配置"
else
    echo "⚠️ 未找到 tg_alert.sh，跳过 TG 发送"
fi
echo ""

echo "=========================================="
echo "测试完成！"
echo "=========================================="
