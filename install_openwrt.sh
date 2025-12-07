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

    # 下载文件
    if [ -f "$DOWNLOAD_DIR/$FILENAME" ]; then
        print_warning "文件已存在，跳过下载"
    else
        print_info "开始下载..."
        if ! wget -O "$DOWNLOAD_DIR/$FILENAME" "$SELECTED_URL"; then
            print_error "下载失败"
            exit 1
        fi
        print_success "下载完成"
    fi

    # 根据文件格式处理
    case "$FILE_FORMAT" in
        "img.gz")
            UNCOMPRESSED_FILE="${FILENAME%.gz}"
            if [ -f "$DOWNLOAD_DIR/$UNCOMPRESSED_FILE" ]; then
                print_warning "解压文件已存在，跳过解压"
            else
                print_info "正在解压文件..."
                gunzip -c "$DOWNLOAD_DIR/$FILENAME" > "$DOWNLOAD_DIR/$UNCOMPRESSED_FILE"
                print_success "解压完成"
            fi
            IMAGE_FILE="$DOWNLOAD_DIR/$UNCOMPRESSED_FILE"
            ;;
        "qcow2"|"vmdk")
            # qcow2和vmdk格式无需解压
            IMAGE_FILE="$DOWNLOAD_DIR/$FILENAME"
            ;;
    esac

    print_success "文件准备完成: $IMAGE_FILE"
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

    print_info "使用GitHub仓库: $GITHUB_REPO"

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