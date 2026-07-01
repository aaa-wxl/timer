#!/bin/bash
# XTimer 压测脚本 - 测量 cost_time 分布
# 用法: ./bench.sh [timer_count]
# 示例: ./bench.sh 500

set -e

TIMER_COUNT=${1:-200}
BASE_URL="http://127.0.0.1:8082"
APP="loadtest"
CRON="0+*+*+*+*+?"
CALLBACK_URL="http://127.0.0.1:8082/xtimer/callback"

echo "=========================================="
echo "XTimer 压测 - cost_time 测量"
echo "=========================================="
echo "Timer 数量: $TIMER_COUNT"
echo "Cron: 每分钟第0秒触发 (0 * * * * ?)"
echo "=========================================="

# Step 1: 清理
echo ""
echo "[1/5] 清理旧数据..."
docker exec mysql mysql -uroot -pPaiSmart2025 -e 'DELETE FROM `bitstorm-svr`.timer_task; DELETE FROM `bitstorm-svr`.xtimer;' 2>/dev/null
docker exec redis redis-cli -a PaiSmart2025 FLUSHDB 2>/dev/null
echo "✓ 清理完成"

# Step 2: 创建 Timer
echo ""
echo "[2/5] 创建 $TIMER_COUNT 个 Timer..."
RESPONSE=$(curl -s -X POST "$BASE_URL/xtimer/batchCreateTimers?count=$TIMER_COUNT&cron=$CRON&callbackUrl=$CALLBACK_URL")
SUCCESS=$(echo "$RESPONSE" | grep -o '"success":[0-9]*' | grep -o '[0-9]*')
FAILED=$(echo "$RESPONSE" | grep -o '"failed":[0-9]*' | grep -o '[0-9]*')
echo "✓ 创建完成: 成功=$SUCCESS, 失败=$FAILED"

# Step 3: 等待 migrator 迁移
echo ""
echo "[3/5] 等待 migrator 迁移 (15秒)..."
sleep 15
TASK_COUNT=$(docker exec mysql mysql -uroot -pPaiSmart2025 -N -e 'SELECT COUNT(*) FROM `bitstorm-svr`.timer_task;' 2>/dev/null)
echo "✓ 迁移完成: $TASK_COUNT 个 task 已写入"

# Step 4: 等待下一分钟边界 + 执行时间
echo ""
echo "[4/5] 等待下一分钟边界..."
CURRENT_SECOND=$(date +%S)
WAIT_SECONDS=$((60 - CURRENT_SECOND))
echo "当前秒: $CURRENT_SECOND, 等待 $WAIT_SECONDS 秒..."
sleep $WAIT_SECONDS
echo "✓ 到达分钟边界: $(date '+%H:%M:%S')"

# 等待 executor 执行完
echo "等待 executor 执行 (30秒)..."
sleep 30

# Step 5: 查询结果
echo ""
echo "[5/5] 查询 cost_time 统计..."
echo ""

# 计算上一分钟的 runTimer 时间戳 (毫秒)
# 当前时间减去当前秒数再减去60秒，就是上一分钟的 00 秒
NOW_MS=$(date +%s%3N)
CURRENT_SEC=$(date +%S)
# 上一分钟的 00 秒
RUN_TIMER=$(( NOW_MS - CURRENT_SEC * 1000 - 60000 ))
# 四舍五入到整分钟
RUN_TIMER=$(( RUN_TIMER / 60000 * 60000 ))

echo "查询 runTimer=$RUN_TIMER ($(date -d @$((RUN_TIMER/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $((RUN_TIMER/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'N/A'))"
echo ""

RESULT=$(curl -s "$BASE_URL/xtimer/bench/result?app=$APP&runTimer=$RUN_TIMER")
echo "$RESULT" | python3 -m json.tool 2>/dev/null || echo "$RESULT"

echo ""
echo "=========================================="
echo "压测完成!"
echo "=========================================="
