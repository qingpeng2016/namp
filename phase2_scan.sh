#!/bin/bash

# 两阶段扫描脚本：端口发现 + 服务识别（针对 HTTP/HTTPS/WSS/TLS/WS）
# 用法: ./phase2_scan.sh <IP地址> [端口范围] [内网IP]
# 端口范围格式: 10000-35534 或 80,443,8080 或 1-65535
# 内网IP：可选，仅用于最后报警时在消息中附带「内网IP: xxx」

# set -e  # 已删除：避免正常失败（如 curl/openssl 连接失败）导致脚本中断

# 参数处理：使用默认值，不提示错误
TARGET="${1:-127.0.0.1}"  # 如果没有提供IP地址，默认使用localhost
PORT_RANGE="${2:-10000-35534}"  # 如果没有提供端口范围，默认使用 10000-35534
INTERNAL_IP="${3:-}"  # 内网IP，可选，仅用于报警消息
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 临时文件命名（仅用于端口列表）
PORTS_FILE="open_ports_${TARGET}_${TIMESTAMP}.txt"

echo "=========================================="
echo "两阶段扫描脚本"
echo "目标IP: $TARGET"
echo "端口范围: $PORT_RANGE"
[ -n "$INTERNAL_IP" ] && echo "内网IP: $INTERNAL_IP"
echo "时间戳: $TIMESTAMP"
echo "=========================================="
echo ""

# ==========================================
# 第一阶段：端口发现
# ==========================================
echo "=========================================="
echo "第一阶段：端口发现 ($PORT_RANGE)"
echo "=========================================="
echo ""

echo "开始扫描端口范围 $PORT_RANGE..."
echo ""

# 第一阶段扫描，输出到屏幕，同时保存到临时文件用于提取端口
TEMP_PHASE1=$(mktemp)
nmap -sT -T4 -v --open --stats-every 5s -p "$PORT_RANGE" "$TARGET" | tee "$TEMP_PHASE1"

echo ""
echo "第一阶段扫描完成！"
echo ""

# ==========================================
# 提取开放端口（先从原始输出中提取，避免清理时丢失端口信息）
# ==========================================
echo "=========================================="
echo "提取开放端口列表"
echo "=========================================="
echo ""

echo "正在从扫描结果中提取端口..."

# 显示扫描结果中的端口状态
echo "扫描结果中的端口状态："
grep -E "^[0-9]+/tcp.*open" "$TEMP_PHASE1" || echo "未找到开放端口"

echo ""

# 提取开放端口（从原始输出中提取，不依赖清理后的文件）
# 使用更宽松的匹配，确保能提取到所有开放端口
EXTRACTED_PORTS=$(grep -E "^[0-9]+/tcp.*open" "$TEMP_PHASE1" | awk '{print $1}' | cut -d'/' -f1 | sort -n | tr '\n' ',' | sed 's/,$//')

# 如果第一种方法失败，尝试备用方法
if [ -z "$EXTRACTED_PORTS" ]; then
    echo "⚠️  警告: 使用主方法未能提取到端口，尝试备用提取方法..."
    # 备用方法：直接匹配端口号（只要状态是 open）
    EXTRACTED_PORTS=$(grep -E "^[0-9]+/tcp" "$TEMP_PHASE1" | grep -i "open" | awk '{print $1}' | cut -d'/' -f1 | sort -n | tr '\n' ',' | sed 's/,$//')
fi

# 将提取到的端口保存到文件
if [ -n "$EXTRACTED_PORTS" ]; then
    echo "$EXTRACTED_PORTS" > "$PORTS_FILE"
    echo "提取到的端口: $EXTRACTED_PORTS"
else
    echo "❌ 错误: 未能提取到任何端口"
    # 创建空文件，后续检查会失败
    touch "$PORTS_FILE"
fi
echo ""

# ==========================================
# 清理：删除包含unknown的行（仅用于显示，不影响端口提取）
# ==========================================
echo "=========================================="
echo "清理输出：删除包含 'unknown' 的行"
echo "=========================================="
echo ""

echo "正在删除包含 'unknown' 的行..."
TEMP_CLEANED=$(mktemp)
grep -v -i "unknown" "$TEMP_PHASE1" > "$TEMP_CLEANED" || true

BEFORE_LINES=$(wc -l < "$TEMP_PHASE1" | tr -d ' ')
AFTER_LINES=$(wc -l < "$TEMP_CLEANED" | tr -d ' ')
DELETED_LINES=$((BEFORE_LINES - AFTER_LINES))

echo "清理完成："
echo "  原始行数: $BEFORE_LINES"
echo "  清理后行数: $AFTER_LINES"
echo "  删除行数: $DELETED_LINES"
echo ""

# 清理临时文件
rm -f "$TEMP_PHASE1" "$TEMP_CLEANED"

# 检查端口文件是否存在且有内容
if [ ! -f "$PORTS_FILE" ] || [ ! -s "$PORTS_FILE" ]; then
    echo "⚠️  警告: 端口文件不存在或为空！"
    echo "尝试重新提取端口..."
    # 如果文件不存在，尝试从 nmap 输出中重新提取
    # 这里我们需要重新扫描，或者使用之前保存的信息
    # 但由于临时文件已删除，我们无法重新提取
    rm -f "$PORTS_FILE"
    exit 1
fi

PORT_COUNT=$(cat "$PORTS_FILE" | tr ',' '\n' | grep -v '^$' | wc -l | tr -d ' ')

if [ "$PORT_COUNT" -eq 0 ] || [ -z "$PORT_COUNT" ]; then
    echo "⚠️  警告: 在端口范围 $PORT_RANGE 中未找到任何开放端口！"
    echo ""
    echo "可能的原因："
    echo "  1. 这些端口确实都是关闭的"
    echo "  2. 端口被防火墙阻止"
    echo "  3. 服务未运行"
    echo ""
    echo "建议："
    echo "  - 尝试扫描其他端口范围"
    echo "  - 检查目标主机是否在线"
    echo "  - 使用其他扫描方式（如 -sS SYN扫描）"
    echo ""
    rm -f "$PORTS_FILE"
    exit 1
fi

echo "已提取 $PORT_COUNT 个开放端口"
echo "端口列表保存到: $PORTS_FILE"
echo ""

# 显示前10个端口作为预览
echo "端口预览（前10个）："
head -1 "$PORTS_FILE" | tr ',' '\n' | head -10
echo ""

# ==========================================
# 第二阶段：服务识别
# ==========================================
echo "=========================================="
echo "第二阶段：服务识别（HTTP/HTTPS/WSS/TLS/WS）"
echo "目标IP: $TARGET"
echo "端口数量: $PORT_COUNT"
echo "=========================================="
echo ""

PORTS=$(cat "$PORTS_FILE")
echo "开始服务识别扫描..."
echo ""

# 第二阶段扫描，输出到屏幕，同时保存到临时文件用于提取服务信息
# -sT: TCP connect scan (与第一阶段一致)
# -sV: 版本检测和服务识别
# --script ssl*,http*,tls*: 运行SSL和HTTP相关脚本
# -p: 指定端口列表
# -T4: 时间模板4（快速扫描）
# -v: 详细输出
# --stats-every 5s: 每5秒显示统计信息
# --open: 只显示开放端口
# --script-timeout 30s: 脚本超时时间

TEMP_PHASE2=$(mktemp)
nmap -sT -T4 -v \
     --open \
     --stats-every 5s \
     -sV \
     --script "ssl*,http*,tls*" \
     --script-timeout 30s \
     -p "$PORTS" \
     "$TARGET" | tee "$TEMP_PHASE2"

echo ""
echo "=========================================="
echo "扫描完成！"
echo "=========================================="
echo ""

# ==========================================
# 结果摘要
# ==========================================
echo "=========================================="
echo "扫描结果摘要"
echo "=========================================="
echo ""
echo "端口列表: $PORTS_FILE"
echo ""

# 自动显示HTTP/HTTPS相关服务（只匹配真实的脚本输出，避免误报）
echo "检测到的HTTP/HTTPS/WSS/TLS/WS服务："
# 查找包含真实脚本输出的行，然后向上查找对应的端口行
HTTP_SERVICES=$(grep -B 5 -E 'ssl-cert:|http-title:' "$TEMP_PHASE2" | grep -E '^[0-9]+/tcp.*open' | sort -u || echo "")
if [ -z "$HTTP_SERVICES" ]; then
    echo "未发现HTTP/HTTPS相关服务"
else
    echo "$HTTP_SERVICES"
fi
echo ""

# 提取端口号并调用 test_port.sh（使用所有开放端口）
echo "=========================================="
echo "开始详细端口协议检测"
echo "=========================================="
echo ""

# 从端口文件中读取所有端口，转换为空格分隔的格式
ALL_PORTS=$(cat "$PORTS_FILE" | tr ',' '\n' | tr -d ' ' | grep -v '^$' | tr '\n' ' ')

if [ -n "$ALL_PORTS" ]; then
    echo "提取到的端口: $ALL_PORTS"
    echo ""
    echo "执行命令: ./test_port.sh $TARGET $ALL_PORTS"
    echo ""
    
    # 调用 test_port.sh，使用所有开放端口（若有内网IP则通过环境变量传入，供报警使用）
    export INTERNAL_IP
    ./test_port.sh "$TARGET" $ALL_PORTS
else
    echo "⚠️  警告: 未能提取到端口号"
fi
echo ""

# 清理临时文件
rm -f "$TEMP_PHASE2"

echo "=========================================="
echo "扫描完成！"
echo "=========================================="
