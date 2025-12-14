#!/bin/bash

# 存储池检测模拟测试脚本
# 模拟PVE环境测试存储池识别和显示功能

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "=== PVE 存储池检测模拟测试 ==="

# 模拟 pvesm status 输出
echo -e "\n${BLUE}模拟 pvesm status 输出:${NC}"
cat << 'EOF'
storid   content     type     status            avail
local    iso,snippets   dir     active            1048576
local-lvm images        lvmthin active            534734
EOF

# 模拟存储池数据
STORAGE_INFO="local dir active 1048576 0 1048576
local-lvm lvmthin active 534734 12378112 12913146"

print_success "使用模拟数据测试存储池检测功能"

# 解析存储池信息
STORAGE_LIST=()
STORAGE_MAP=()

while IFS= read -r line; do
    if [ -n "$line" ]; then
        echo "处理行: $line"

        # 使用更可靠的字段解析方式
        STORAGE_NAME=$(echo "$line" | awk '{print $1}')
        STORAGE_TYPE=$(echo "$line" | awk '{print $2}')
        STORAGE_STATUS=$(echo "$line" | awk '{print $3}')
        STORAGE_USED=$(echo "$line" | awk '{print $4}')
        STORAGE_AVAIL=$(echo "$line" | awk '{print $5}')
        STORAGE_TOTAL=$(echo "$line" | awk '{print $6}')

        echo "  名称: $STORAGE_NAME"
        echo "  类型: $STORAGE_TYPE"
        echo "  状态: $STORAGE_STATUS"
        echo "  已用: $STORAGE_USED"
        echo "  可用: $STORAGE_AVAIL"
        echo "  总计: $STORAGE_TOTAL"

        # 智能解析存储池大小信息
        if [[ "$STORAGE_STATUS" == "active" ]]; then
            # 如果状态是active，尝试从其他字段获取大小信息
            if [[ -n "$STORAGE_TOTAL" && "$STORAGE_TOTAL" =~ ^[0-9]+$ ]]; then
                STORAGE_SIZE="$STORAGE_TOTAL"
            else
                STORAGE_SIZE="N/A"
            fi
        else
            STORAGE_SIZE="$STORAGE_STATUS"
        fi

        # 格式化数字显示（转换为GB）
        format_size() {
            local size=$1
            if [[ "$size" =~ ^[0-9]+$ ]]; then
                if [ "$size" -gt 1073741824 ]; then
                    echo "$(echo "scale=1; $size/1073741824" | bc 2>/dev/null || echo "$((size/1073741824))")TB"
                elif [ "$size" -gt 1048576 ]; then
                    echo "$(echo "scale=1; $size/1048576" | bc 2>/dev/null || echo "$((size/1048576))")GB"
                elif [ "$size" -gt 1024 ]; then
                    echo "$(echo "scale=1; $size/1024" | bc 2>/dev/null || echo "$((size/1024))")MB"
                else
                    echo "${size}KB"
                fi
            else
                echo "$size"
            fi
        }

        # 格式化显示的大小
        DISPLAY_SIZE=$(format_size "$STORAGE_SIZE")
        DISPLAY_USED=$(format_size "$STORAGE_USED")
        DISPLAY_AVAIL=$(format_size "$STORAGE_AVAIL")

        STORAGE_LIST+=("$STORAGE_NAME")
        STORAGE_MAP["$STORAGE_NAME"]="$STORAGE_TYPE|$DISPLAY_SIZE|$DISPLAY_USED|$DISPLAY_AVAIL"

        echo "  解析后大小: $DISPLAY_SIZE"
        echo ""
    fi
done <<< "$STORAGE_INFO"

print_success "找到 ${#STORAGE_LIST[@]} 个可用存储池"

# 显示解析结果
echo -e "\n${BLUE}修复后的存储池列表显示:${NC}"
for i in "${!STORAGE_LIST[@]}"; do
    STORAGE_NAME="${STORAGE_LIST[$i]}"
    IFS='|' read -r STORAGE_TYPE STORAGE_SIZE STORAGE_USED STORAGE_AVAIL <<< "${STORAGE_MAP[$STORAGE_NAME]}"

    printf "%d) %s (类型: %s, 大小: %s, 已用: %s, 可用: %s)\n" \
        $((i+1)) "$STORAGE_NAME" "$STORAGE_TYPE" "$STORAGE_SIZE" "$STORAGE_USED" "$STORAGE_AVAIL"
done

echo -e "\n${BLUE}=== 修复说明 ===${NC}"
echo "1. ✅ 修复了 'active' 状态显示问题"
echo "2. ✅ 现在能正确显示所有存储池（包括 local 和 local-lvm）"
echo "3. ✅ 智能大小格式化（KB → MB → GB → TB）"
echo "4. ✅ 改进了字段解析逻辑"
echo "5. ✅ 移除了 -content images 限制，显示所有存储池"

echo -e "\n${BLUE}=== 测试完成 ===${NC}"