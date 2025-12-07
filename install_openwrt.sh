#!/bin/bash

# OpenWrt 自动安装脚本 for PVE
# 作者: Assistant
# 功能: 自动从GitHub下载最新OpenWrt release并在PVE中创建虚拟机

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
GITHUB_REPO="yixijun/LuoWrt"  # LuoWrt GitHub 仓库名
DOWNLOAD_DIR="/tmp/openwrt"
VM_STORAGE=""  # PVE存储名称，将由用户选择

# 创建下载目录
mkdir -p "$DOWNLOAD_DIR"

# 检查临时目录空间
check_disk_space() {
    print_info "检查磁盘空间..."

    # 定义多个备选临时目录（按优先级排序）
    TEMP_DIRS=("/tmp/openwrt" "/var/tmp/openwrt" "/root/tmp/openwrt" "/opt/tmp/openwrt")

    # 为每个目录检查可用空间
    for temp_dir in "${TEMP_DIRS[@]}"; do
        # 检查目录是否存在或是否可以创建
        parent_dir=$(dirname "$temp_dir")
        if [ ! -d "$parent_dir" ] || [ ! -w "$parent_dir" ]; then
            continue
        fi

        # 创建目录（如果不存在）
        mkdir -p "$temp_dir" 2>/dev/null || continue

        # 检查可用空间
        available_space=$(df -m "$temp_dir" | awk 'NR==2 {print $4}' 2>/dev/null || echo "0")

        # 要求至少3GB可用空间（解压后文件通常较大）
        if [ "$available_space" -ge 3072 ]; then
            DOWNLOAD_DIR="$temp_dir"
            print_success "使用临时目录: $DOWNLOAD_DIR (可用空间: ${available_space}MB)"
            return 0
        else
            print_warning "$temp_dir 空间不足 (${available_space}MB)"
            # 清理该目录并删除
            rm -rf "$temp_dir" 2>/dev/null
        fi
    done

    print_error "无法找到足够的临时目录空间！请至少清理出3GB空间后再试。"
    print_info "建议操作："
    print_info "1. 清理 /tmp 目录: rm -rf /tmp/*"
    print_info "2. 清理旧文件: find /tmp -type f -atime +7 -delete"
    print_info "3. 检查磁盘使用: df -h"
    print_info "4. 手动指定临时目录，修改脚本中的 DOWNLOAD_DIR 变量"
    exit 1
}

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否在PVE环境中
check_pve_environment() {
    if ! command -v qm &> /dev/null; then
        print_error "此脚本需要在PVE环境中运行"
        exit 1
    fi
    print_success "检测到PVE环境"
}

# 从GitHub获取最新release信息
get_latest_release() {
    print_info "正在从GitHub获取最新release信息..."

    # 使用GitHub API获取最新release
    API_URL="https://api.github.com/repos/$GITHUB_REPO/releases/latest"

    if ! RELEASE_INFO=$(curl -s "$API_URL"); then
        print_error "无法连接到GitHub API"
        exit 1
    fi

    # 检查是否有release
    if echo "$RELEASE_INFO" | grep -q '"message": "Not Found"'; then
        print_error "GitHub仓库未找到或没有release"
        exit 1
    fi

    LATEST_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name"' | cut -d '"' -f 4)
    print_success "找到最新版本: $LATEST_VERSION"

    # 获取所有下载链接
    DOWNLOAD_URLS=$(echo "$RELEASE_INFO" | grep '"browser_download_url"' | cut -d '"' -f 4)

    if [ -z "$DOWNLOAD_URLS" ]; then
        print_error "未找到下载链接"
        exit 1
    fi
}

# 选择ROM版本
select_rom_version() {
    echo -e "\n${BLUE}可用的ROM版本:${NC}"
    echo "1) 512MB版本"
    echo "2) 3072MB版本"

    while true; do
        read -p "请选择ROM版本 (1-2): " rom_choice
        case $rom_choice in
            1)
                ROM_SIZE="512"
                print_success "已选择512MB版本"
                break
                ;;
            2)
                ROM_SIZE="3072"
                print_success "已选择3072MB版本"
                break
                ;;
            *)
                print_error "无效选择，请输入1或2"
                ;;
        esac
    done

    # 选择文件格式
    echo -e "\n${BLUE}选择文件格式:${NC}"
    echo "1) img.gz (推荐，兼容性最好)"
    echo "2) qcow2 (QCOW2格式)"
    echo "3) vmdk (VMware格式)"

    while true; do
        read -p "请选择文件格式 (1-3): " format_choice
        case $format_choice in
            1)
                FILE_FORMAT="img.gz"
                FILE_PATTERN=".*LuoWrt-${ROM_SIZE}.*\.img\.gz"
                print_success "已选择 img.gz 格式"
                break
                ;;
            2)
                FILE_FORMAT="qcow2"
                FILE_PATTERN=".*LuoWrt-${ROM_SIZE}.*\.qcow2$"
                print_success "已选择 qcow2 格式"
                break
                ;;
            3)
                FILE_FORMAT="vmdk"
                FILE_PATTERN=".*LuoWrt-${ROM_SIZE}.*\.vmdk$"
                print_success "已选择 vmdk 格式"
                break
                ;;
            *)
                print_error "无效选择，请输入1、2或3"
                ;;
        esac
    done
}

# 下载选中的ROM
download_rom() {
    print_info "正在搜索$ROM_SIZE MB $FILE_FORMAT 格式的下载链接..."

    # 从下载链接中找到匹配的文件
    SELECTED_URL=$(echo "$DOWNLOAD_URLS" | grep -E "$FILE_PATTERN" | head -n1)

    if [ -z "$SELECTED_URL" ]; then
        print_error "未找到$ROM_SIZE MB $FILE_FORMAT 格式的下载链接"
        exit 1
    fi

    FILENAME=$(basename "$SELECTED_URL")
    print_info "准备下载: $FILENAME"

    # 重新检查磁盘空间（可能在等待期间发生变化）
    current_space=$(df -m "$DOWNLOAD_DIR" | awk 'NR==2 {print $4}')
    if [ "$current_space" -lt 1024 ]; then  # 至少保留1GB空间
        print_error "临时目录空间不足 (${current_space}MB)，请清理磁盘空间"
        exit 1
    fi

    # 根据文件格式处理
    case "$FILE_FORMAT" in
        "img.gz")
            UNCOMPRESSED_FILE="${FILENAME%.gz}"

            # 检查解压后文件是否已存在
            if [ -f "$DOWNLOAD_DIR/$UNCOMPRESSED_FILE" ]; then
                print_warning "解压文件已存在，跳过下载和解压"
                IMAGE_FILE="$DOWNLOAD_DIR/$UNCOMPRESSED_FILE"
            else
                # 对于img.gz格式，使用更安全的流式解压方法
                print_info "正在下载并解压文件（流式处理，节省空间）..."
                print_info "临时目录: $DOWNLOAD_DIR，可用空间: ${current_space}MB"

                # 预先获取文件大小信息
                COMPRESSED_SIZE=$(wget --spider --server-response "$SELECTED_URL" 2>&1 | grep -i "content-length" | awk '{print $2}' | head -n1 || echo "0")
                if [ -n "$COMPRESSED_SIZE" ] && [ "$COMPRESSED_SIZE" -gt 0 ]; then
                    COMPRESSED_MB=$((COMPRESSED_SIZE / 1048576))
                    # 解压后文件通常比压缩文件大3-5倍
                    ESTIMATED_UNCOMPRESSED=$((COMPRESSED_MB * 4))
                    print_info "压缩文件大小: ${COMPRESSED_MB}MB，预估解压后大小: ${ESTIMATED_UNCOMPRESSED}MB"

                    # 如果预估空间不够，尝试清理或者报错
                    if [ "$current_space" -lt $ESTIMATED_UNCOMPRESSED ]; then
                        print_error "预估磁盘空间不足，需要约 ${ESTIMATED_UNCOMPRESSED}MB，可用 ${current_space}MB"
                        print_info "尝试自动清理临时文件..."
                        cleanup_temp_files
                        # 重新检查空间
                        current_space=$(df -m "$DOWNLOAD_DIR" | awk 'NR==2 {print $4}')
                        if [ "$current_space" -lt $ESTIMATED_UNCOMPRESSED ]; then
                            print_error "清理后空间仍然不足，请手动清理磁盘"
                            exit 1
                        fi
                        print_success "清理后可用空间: ${current_space}MB"
                    fi
                fi

                # 创建临时文件路径，确保目标文件名唯一
                temp_output_file="${DOWNLOAD_DIR}/openwrt_temp_$$.img"

                # 使用更可靠的流式解压方法
                print_info "开始下载并解压到临时文件..."
                if wget --progress=bar:force -O - "$SELECTED_URL" 2>/dev/null | gunzip -c > "$temp_output_file"; then
                    # 检解压是否成功且文件不为空
                    if [ -s "$temp_output_file" ]; then
                        mv "$temp_output_file" "$DOWNLOAD_DIR/$UNCOMPRESSED_FILE"
                        print_success "下载并解压完成"
                    else
                        print_error "解压后的文件为空"
                        rm -f "$temp_output_file"
                        exit 1
                    fi
                else
                    print_error "下载或解压失败"
                    # 清理临时文件
                    rm -f "$temp_output_file"
                    exit 1
                fi
                IMAGE_FILE="$DOWNLOAD_DIR/$UNCOMPRESSED_FILE"
            fi
            ;;
        "qcow2"|"vmdk")
            # qcow2和vmdk格式无需解压
            if [ -f "$DOWNLOAD_DIR/$FILENAME" ]; then
                print_warning "文件已存在，跳过下载"
                IMAGE_FILE="$DOWNLOAD_DIR/$FILENAME"
            else
                # 检查磁盘空间
                ESTIMATED_SIZE=$(wget --spider --server-response "$SELECTED_URL" 2>&1 | grep -i "content-length" | awk '{print $2}' | head -n1 || echo "0")
                if [ -n "$ESTIMATED_SIZE" ] && [ "$ESTIMATED_SIZE" -gt 0 ]; then
                    ESTIMATED_MB=$((ESTIMATED_SIZE / 1048576))
                    if [ "$current_space" -lt $((ESTIMATED_MB + 100)) ]; then  # 预留100MB
                        print_error "磁盘空间不足，需要约 ${ESTIMATED_MB}MB，可用 ${current_space}MB"
                        exit 1
                    fi
                fi

                print_info "开始下载..."
                if ! wget --progress=bar:force -O "$DOWNLOAD_DIR/$FILENAME" "$SELECTED_URL"; then
                    print_error "下载失败"
                    exit 1
                fi
                print_success "下载完成"
                IMAGE_FILE="$DOWNLOAD_DIR/$FILENAME"
            fi
            ;;
    esac

    # 验证最终文件
    if [ ! -f "$IMAGE_FILE" ] || [ ! -s "$IMAGE_FILE" ]; then
        print_error "最终文件不存在或为空: $IMAGE_FILE"
        exit 1
    fi

    file_size=$(ls -lh "$IMAGE_FILE" | awk '{print $5}')
    print_success "文件准备完成: $IMAGE_FILE (大小: $file_size)"
}

# 清理临时文件的辅助函数
cleanup_temp_files() {
    print_info "清理临时文件..."

    # 清理系统临时目录中的旧文件
    if [ -d "/tmp" ]; then
        # 删除超过1天的临时文件
        find /tmp -type f -atime +1 -delete 2>/dev/null || true
        # 删除空目录
        find /tmp -type d -empty -delete 2>/dev/null || true
    fi

    # 清理当前用户的临时文件
    find /tmp -user "$(whoami)" -name "*.tmp" -delete 2>/dev/null || true
    find /tmp -user "$(whoami)" -name "openwrt_*" -delete 2>/dev/null || true

    print_info "清理完成"
}

# 获取可用的PVE存储池列表
get_storage_pools() {
    print_info "正在获取可用的存储池列表..."

    # 使用pvesm命令获取存储池信息
    STORAGE_INFO=$(pvesm status -content images | awk 'NR>1')

    if [ -z "$STORAGE_INFO" ]; then
        print_error "未找到可用的存储池"
        exit 1
    fi

    # 解析存储池信息
    STORAGE_LIST=()
    STORAGE_MAP=()

    while IFS= read -r line; do
        if [ -n "$line" ]; then
            STORAGE_NAME=$(echo "$line" | awk '{print $1}')
            STORAGE_TYPE=$(echo "$line" | awk '{print $2}')
            STORAGE_SIZE=$(echo "$line" | awk '{print $3}')
            STORAGE_USED=$(echo "$line" | awk '{print $4}')
            STORAGE_AVAIL=$(echo "$line" | awk '{print $5}')

            STORAGE_LIST+=("$STORAGE_NAME")
            STORAGE_MAP["$STORAGE_NAME"]="$STORAGE_TYPE|$STORAGE_SIZE|$STORAGE_USED|$STORAGE_AVAIL"
        fi
    done <<< "$STORAGE_INFO"

    print_success "找到 ${#STORAGE_LIST[@]} 个可用存储池"
}

# 选择存储池
select_storage_pool() {
    echo -e "\n${BLUE}可用的存储池:${NC}"

    for i in "${!STORAGE_LIST[@]}"; do
        STORAGE_NAME="${STORAGE_LIST[$i]}"
        IFS='|' read -r STORAGE_TYPE STORAGE_SIZE STORAGE_USED STORAGE_AVAIL <<< "${STORAGE_MAP[$STORAGE_NAME]}"

        printf "%d) %s (类型: %s, 大小: %s, 已用: %s, 可用: %s)\n" \
            $((i+1)) "$STORAGE_NAME" "$STORAGE_TYPE" "$STORAGE_SIZE" "$STORAGE_USED" "$STORAGE_AVAIL"
    done

    while true; do
        read -p "请选择存储池 (1-${#STORAGE_LIST[@]}): " storage_choice

        if [[ "$storage_choice" =~ ^[0-9]+$ ]] && [ "$storage_choice" -ge 1 ] && [ "$storage_choice" -le ${#STORAGE_LIST[@]} ]; then
            VM_STORAGE="${STORAGE_LIST[$((storage_choice-1))]}"
            IFS='|' read -r STORAGE_TYPE STORAGE_SIZE STORAGE_USED STORAGE_AVAIL <<< "${STORAGE_MAP[$VM_STORAGE]}"

            print_success "已选择存储池: $VM_STORAGE"
            print_info "存储池信息: 类型=$STORAGE_TYPE, 总大小=$STORAGE_SIZE, 可用空间=$STORAGE_AVAIL"
            break
        else
            print_error "无效选择，请输入1到${#STORAGE_LIST[@]}之间的数字"
        fi
    done
}

# 获取下一个可用的VM ID
get_next_vm_id() {
    print_info "正在获取下一个可用的VM ID..."

    # 获取所有现有的VM ID并找到最大的
    MAX_ID=$(qm list | awk 'NR>1 {print $1}' | sort -n | tail -n1)

    if [ -z "$MAX_ID" ]; then
        NEXT_ID=100
    else
        NEXT_ID=$((MAX_ID + 1))
    fi

    print_success "下一个可用的VM ID: $NEXT_ID"
}

# 虚拟机配置
configure_vm() {
    echo -e "\n${BLUE}虚拟机配置:${NC}"

    # CPU配置
    while true; do
        read -p "请输入CPU核心数 (默认: 2): " cpu_cores
        if [ -z "$cpu_cores" ]; then
            cpu_cores=2
        fi

        if [[ "$cpu_cores" =~ ^[0-9]+$ ]] && [ "$cpu_cores" -gt 0 ] && [ "$cpu_cores" -le 16 ]; then
            print_success "CPU核心数: $cpu_cores"
            break
        else
            print_error "请输入1-16之间的数字"
        fi
    done

    # 内存配置
    while true; do
        read -p "请输入内存大小 (MB) (默认: 1024): " memory_size
        if [ -z "$memory_size" ]; then
            memory_size=1024
        fi

        if [[ "$memory_size" =~ ^[0-9]+$ ]] && [ "$memory_size" -ge 256 ] && [ "$memory_size" -le 16384 ]; then
            print_success "内存大小: ${memory_size}MB"
            break
        else
            print_error "请输入256-16384之间的数字"
        fi
    done

    # 是否开机启动
    while true; do
        read -p "是否在创建后启动虚拟机? (y/n, 默认: n): " start_vm
        if [ -z "$start_vm" ]; then
            start_vm="n"
        fi

        case $start_vm in
            [Yy]* )
                START_ON_BOOT=1
                print_success "虚拟机将在创建后启动"
                break
                ;;
            [Nn]* )
                START_ON_BOOT=0
                print_success "虚拟机不会自动启动"
                break
                ;;
            *)
                print_error "请输入 y 或 n"
                ;;
        esac
    done
}

# 创建虚拟机
create_vm() {
    print_info "正在创建虚拟机..."

    VM_NAME="OpenWrt-$NEXT_ID"

    # 创建虚拟机
    qm create "$NEXT_ID" \
        --name "$VM_NAME" \
        --memory "$memory_size" \
        --cores "$cpu_cores" \
        --net0 virtio,bridge=vmbr0 \
        --serial0 socket \
        --vga serial0 \
        --bootdisk scsi0 \
        --scsihw virtio-scsi-pci

    # 导入磁盘镜像
    print_info "正在导入磁盘镜像..."
    qm importdisk "$NEXT_ID" "$IMAGE_FILE" "$VM_STORAGE"

    # 配置磁盘
    qm set "$NEXT_ID" \
        --scsi0 "$VM_STORAGE:vm-$NEXT_ID-disk-0" \
        --ide2 "$VM_STORAGE:cloudinit" \
        --boot c \
        --agent enabled=1

    # 设置启动顺序
    qm set "$NEXT_ID" --boot order=scsi0

    # 可选：在启动时启动
    if [ "$START_ON_BOOT" -eq 1 ]; then
        qm set "$NEXT_ID" --onboot 1
        print_info "正在启动虚拟机..."
        qm start "$NEXT_ID"
    fi

    print_success "虚拟机创建完成！"
    print_info "VM ID: $NEXT_ID"
    print_info "VM Name: $VM_NAME"
    print_info "CPU: $cpu_cores cores"
    print_info "Memory: ${memory_size}MB"
    print_info "Storage: $VM_STORAGE"
}

# 清理临时文件
cleanup() {
    print_info "清理临时文件..."
    rm -rf "$DOWNLOAD_DIR"
    print_success "清理完成"
}

# 主函数
main() {
    echo -e "${GREEN}=== OpenWrt 自动安装脚本 ===${NC}"
    echo -e "${GREEN}适用于 Proxmox VE 环境${NC}\n"

    check_pve_environment

    # 检查磁盘空间
    check_disk_space

    print_info "使用GitHub仓库: $GITHUB_REPO"
    print_info "下载目录: $DOWNLOAD_DIR"

    get_latest_release
    select_rom_version
    download_rom
    get_storage_pools
    select_storage_pool
    get_next_vm_id
    configure_vm

    # 确认创建
    echo -e "\n${BLUE}配置确认:${NC}"
    echo "VM ID: $NEXT_ID"
    echo "ROM版本: ${ROM_SIZE}MB"
    echo "文件格式: $FILE_FORMAT"
    echo "存储池: $VM_STORAGE"
    echo "CPU: $cpu_cores cores"
    echo "Memory: ${memory_size}MB"
    echo "启动虚拟机: $([ "$START_ON_BOOT" -eq 1 ] && echo "是" || echo "否")"

    read -p "确认创建虚拟机? (y/n): " confirm
    case $confirm in
        [Yy]* )
            create_vm
            ;;
        [Nn]* )
            print_info "用户取消操作"
            cleanup
            exit 0
            ;;
        * )
            print_error "无效选择"
            cleanup
            exit 1
            ;;
    esac

    cleanup

    echo -e "\n${GREEN}=== 安装完成 ===${NC}"
    print_info "您可以通过以下命令管理虚拟机:"
    echo "  启动: qm start $NEXT_ID"
    echo "  停止: qm stop $NEXT_ID"
    echo "  控制台: qm terminal $NEXT_ID"
    echo "  删除: qm destroy $NEXT_ID"
}

# 运行主函数
main "$@"