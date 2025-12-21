#!/bin/bash

# LuoWrt 自动安装脚本 for PVE
# 功能: 自动从GitHub下载最新LuoWrt release并在PVE中创建虚拟机

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置变量
GITHUB_REPO="yixijun/LuoWrt"
DOWNLOAD_DIR="/tmp/luowrt"
VM_STORAGE=""
SYSTEM_ARCH=""
ARCH_ALIAS=""
ARCH_VARIANTS=""

# 声明关联数组
declare -A STORAGE_MAP

# 打印函数
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查磁盘空间
check_disk_space() {
    print_info "检查磁盘空间..."
    
    local temp_dirs=("/tmp/luowrt" "/var/tmp/luowrt" "/root/tmp/luowrt" "/opt/tmp/luowrt")
    
    for temp_dir in "${temp_dirs[@]}"; do
        local parent_dir
        parent_dir=$(dirname "$temp_dir")
        
        if [ ! -d "$parent_dir" ] || [ ! -w "$parent_dir" ]; then
            continue
        fi
        
        mkdir -p "$temp_dir" 2>/dev/null || continue
        
        local available_space
        available_space=$(df -m "$temp_dir" 2>/dev/null | awk 'NR==2 {print $4}')
        available_space=${available_space:-0}
        
        if [ "$available_space" -ge 3072 ]; then
            DOWNLOAD_DIR="$temp_dir"
            print_success "使用临时目录: $DOWNLOAD_DIR (可用空间: ${available_space}MB)"
            return 0
        else
            print_warning "$temp_dir 空间不足 (${available_space}MB)"
            rm -rf "$temp_dir" 2>/dev/null
        fi
    done
    
    print_error "无法找到足够的临时目录空间！请至少清理出3GB空间后再试。"
    exit 1
}

# 检查PVE环境
check_pve_environment() {
    if ! command -v qm &> /dev/null; then
        print_error "此脚本需要在PVE环境中运行"
        exit 1
    fi
    print_success "检测到PVE环境"
}

# 检测系统架构
detect_system_architecture() {
    print_info "正在检测系统架构..."
    
    local uname_arch
    uname_arch=$(uname -m)
    
    case "$uname_arch" in
        x86_64|amd64)
            SYSTEM_ARCH="amd64"
            ARCH_ALIAS="x86_64"
            ARCH_VARIANTS="x86-64"
            ;;
        aarch64|arm64)
            SYSTEM_ARCH="arm64"
            ARCH_ALIAS="aarch64"
            ARCH_VARIANTS=""
            ;;
        armv7l|armhf)
            SYSTEM_ARCH="arm"
            ARCH_ALIAS="armv7"
            ARCH_VARIANTS=""
            ;;
        *)
            if grep -q "Intel\|AMD" /proc/cpuinfo 2>/dev/null; then
                SYSTEM_ARCH="amd64"
                ARCH_ALIAS="x86_64"
                ARCH_VARIANTS="x86-64"
            elif grep -q "AArch64\|ARMv8" /proc/cpuinfo 2>/dev/null; then
                SYSTEM_ARCH="arm64"
                ARCH_ALIAS="aarch64"
            elif grep -q "ARMv7" /proc/cpuinfo 2>/dev/null; then
                SYSTEM_ARCH="arm"
                ARCH_ALIAS="armv7"
            else
                print_error "无法确定系统架构"
                return 1
            fi
            ;;
    esac
    
    print_success "检测到系统架构: $SYSTEM_ARCH ($ARCH_ALIAS)"
    return 0
}

# 手动选择架构
select_architecture() {
    echo -e "\n${BLUE}请选择系统架构:${NC}"
    echo "1) amd64 (x86_64) - Intel/AMD 64位处理器"
    echo "2) arm64 (aarch64) - ARM 64位处理器"
    echo "3) arm (armv7) - ARM 32位处理器"
    
    while true; do
        read -rp "请选择架构 (1-3): " arch_choice
        case $arch_choice in
            1)
                SYSTEM_ARCH="amd64"
                ARCH_ALIAS="x86_64"
                ARCH_VARIANTS="x86-64"
                break
                ;;
            2)
                SYSTEM_ARCH="arm64"
                ARCH_ALIAS="aarch64"
                ARCH_VARIANTS=""
                break
                ;;
            3)
                SYSTEM_ARCH="arm"
                ARCH_ALIAS="armv7"
                ARCH_VARIANTS=""
                break
                ;;
            *)
                print_error "无效选择，请输入1-3"
                ;;
        esac
    done
    print_success "已选择 $SYSTEM_ARCH 架构"
}

# 从GitHub获取最新release
get_latest_release() {
    print_info "正在从GitHub获取最新release信息..."
    
    local api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
    
    if ! RELEASE_INFO=$(curl -s "$api_url"); then
        print_error "无法连接到GitHub API"
        exit 1
    fi
    
    if echo "$RELEASE_INFO" | grep -q '"message": "Not Found"'; then
        print_error "GitHub仓库未找到或没有release"
        exit 1
    fi
    
    LATEST_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name"' | cut -d '"' -f 4)
    print_success "找到最新版本: $LATEST_VERSION"
    
    DOWNLOAD_URLS=$(echo "$RELEASE_INFO" | grep '"browser_download_url"' | cut -d '"' -f 4)
    
    if [ -z "$DOWNLOAD_URLS" ]; then
        print_error "未找到下载链接"
        exit 1
    fi
}

# 构建架构匹配模式
build_arch_pattern() {
    local purpose="$1"
    local arch_pattern="($SYSTEM_ARCH|$ARCH_ALIAS"
    
    if [ -n "$ARCH_VARIANTS" ]; then
        arch_pattern="$arch_pattern|$ARCH_VARIANTS"
    fi
    arch_pattern="$arch_pattern)"
    
    case "$purpose" in
        "display")
            local display="$SYSTEM_ARCH ($ARCH_ALIAS"
            [ -n "$ARCH_VARIANTS" ] && display="$display, $ARCH_VARIANTS"
            echo "$display)"
            ;;
        "pattern")
            echo "$arch_pattern"
            ;;
    esac
}

# 构建文件匹配模式
build_file_pattern() {
    local rom_size="$1"
    local boot_mode="$2"
    local file_format="$3"
    local arch_pattern="$4"
    
    local efi_part=""
    [ "$boot_mode" = "efi" ] && efi_part=".*-efi"
    
    case "$file_format" in
        "img.gz")
            echo ".*LuoWrt-${rom_size}.*${arch_pattern}${efi_part}.*\\.img\\.gz"
            ;;
        "qcow2")
            echo ".*LuoWrt-${rom_size}.*${arch_pattern}${efi_part}.*\\.qcow2$"
            ;;
    esac
}


# 选择ROM版本
select_rom_version() {
    echo -e "\n${BLUE}可用的ROM版本:${NC}"
    echo "1) 512MB版本"
    echo "2) 3072MB版本"
    
    while true; do
        read -rp "请选择ROM版本 (1-2): " rom_choice
        case $rom_choice in
            1) ROM_SIZE="512"; break ;;
            2) ROM_SIZE="3072"; break ;;
            *) print_error "无效选择，请输入1或2" ;;
        esac
    done
    print_success "已选择${ROM_SIZE}MB版本"
    
    echo -e "\n${BLUE}选择文件格式:${NC}"
    echo "1) img.gz (推荐，兼容性最好)"
    echo "2) qcow2 (QCOW2格式)"
    
    while true; do
        read -rp "请选择文件格式 (1-2): " format_choice
        case $format_choice in
            1) FILE_FORMAT="img.gz"; break ;;
            2) FILE_FORMAT="qcow2"; break ;;
            *) print_error "无效选择，请输入1或2" ;;
        esac
    done
    print_success "已选择 $FILE_FORMAT 格式"
    
    echo -e "\n${BLUE}选择启动方式:${NC}"
    echo "1) BIOS (传统启动模式，兼容性好)"
    echo "2) EFI (UEFI启动模式，现代系统推荐)"
    
    while true; do
        read -rp "请选择启动方式 (1-2): " boot_choice
        case $boot_choice in
            1)
                BOOT_MODE="bios"
                BOOT_FIRMWARE=""
                BOOT_MACHINE="pc"
                break
                ;;
            2)
                BOOT_MODE="efi"
                BOOT_FIRMWARE="ovmf"
                BOOT_MACHINE="q35"
                break
                ;;
            *) print_error "无效选择，请输入1或2" ;;
        esac
    done
    print_success "已选择 $BOOT_MODE 启动模式"
}

# 下载ROM
download_rom() {
    print_info "正在搜索 ${ROM_SIZE}MB $FILE_FORMAT 格式的下载链接..."
    
    local arch_pattern
    arch_pattern=$(build_arch_pattern "pattern")
    local file_pattern
    file_pattern=$(build_file_pattern "$ROM_SIZE" "$BOOT_MODE" "$FILE_FORMAT" "$arch_pattern")
    
    print_info "文件匹配模式: $file_pattern"
    
    # 查找匹配的文件
    if [ "$BOOT_MODE" = "bios" ]; then
        SELECTED_URL=$(echo "$DOWNLOAD_URLS" | grep -E "$file_pattern" | grep -v -i "efi\|uefi" | head -n1)
    else
        SELECTED_URL=$(echo "$DOWNLOAD_URLS" | grep -E "$file_pattern" | head -n1)
        if [ -z "$SELECTED_URL" ]; then
            local uefi_pattern=".*LuoWrt-${ROM_SIZE}.*${arch_pattern}.*uefi.*\\.img\\.gz"
            SELECTED_URL=$(echo "$DOWNLOAD_URLS" | grep -E "$uefi_pattern" | head -n1)
        fi
    fi
    
    if [ -z "$SELECTED_URL" ]; then
        print_error "未找到匹配的下载链接"
        print_info "可用文件列表："
        echo "$DOWNLOAD_URLS" | while read -r url; do
            [ -n "$url" ] && echo "  - $(basename "$url")"
        done
        exit 1
    fi
    
    FILENAME=$(basename "$SELECTED_URL")
    print_info "准备下载: $FILENAME"
    
    # 检查磁盘空间
    local current_space
    current_space=$(df -m "$DOWNLOAD_DIR" | awk 'NR==2 {print $4}')
    if [ "$current_space" -lt 1024 ]; then
        print_error "临时目录空间不足 (${current_space}MB)"
        exit 1
    fi
    
    case "$FILE_FORMAT" in
        "img.gz")
            download_and_extract_gz
            ;;
        "qcow2")
            download_qcow2
            ;;
    esac
    
    if [ ! -f "$IMAGE_FILE" ] || [ ! -s "$IMAGE_FILE" ]; then
        print_error "最终文件不存在或为空: $IMAGE_FILE"
        exit 1
    fi
    
    local file_size
    file_size=$(ls -lh "$IMAGE_FILE" | awk '{print $5}')
    print_success "文件准备完成: $IMAGE_FILE (大小: $file_size)"
}

# 下载并解压gz文件
download_and_extract_gz() {
    local uncompressed_file="${FILENAME%.gz}"
    
    if [ -f "$DOWNLOAD_DIR/$uncompressed_file" ]; then
        print_warning "解压文件已存在，跳过下载"
        IMAGE_FILE="$DOWNLOAD_DIR/$uncompressed_file"
        return
    fi
    
    local temp_gz="$DOWNLOAD_DIR/temp_compressed_$$.gz"
    local temp_img="$DOWNLOAD_DIR/temp_image_$$.img"
    
    print_info "第一步：下载压缩文件..."
    if ! wget --progress=bar:force -O "$temp_gz" "$SELECTED_URL"; then
        print_error "下载失败"
        rm -f "$temp_gz"
        exit 1
    fi
    
    if [ ! -s "$temp_gz" ]; then
        print_error "下载的文件为空"
        rm -f "$temp_gz"
        exit 1
    fi
    
    print_info "第二步：解压文件..."
    if ! smart_decompress "$temp_gz" "$temp_img"; then
        print_error "解压失败"
        rm -f "$temp_gz" "$temp_img"
        exit 1
    fi
    
    rm -f "$temp_gz"
    
    if [ -s "$temp_img" ]; then
        mv "$temp_img" "$DOWNLOAD_DIR/$uncompressed_file"
        IMAGE_FILE="$DOWNLOAD_DIR/$uncompressed_file"
        print_success "文件处理完成"
    else
        print_error "解压后文件为空"
        rm -f "$temp_img"
        exit 1
    fi
}

# 下载qcow2文件
download_qcow2() {
    if [ -f "$DOWNLOAD_DIR/$FILENAME" ]; then
        print_warning "文件已存在，跳过下载"
        IMAGE_FILE="$DOWNLOAD_DIR/$FILENAME"
        return
    fi
    
    print_info "开始下载..."
    if ! wget --progress=bar:force -O "$DOWNLOAD_DIR/$FILENAME" "$SELECTED_URL"; then
        print_error "下载失败"
        exit 1
    fi
    
    IMAGE_FILE="$DOWNLOAD_DIR/$FILENAME"
    print_success "下载完成"
}

# 智能解压
smart_decompress() {
    local input_file="$1"
    local output_file="$2"
    
    local file_type
    file_type=$(file -b "$input_file")
    
    case "$file_type" in
        *"gzip compressed"*)
            if gunzip -c "$input_file" > "$output_file" 2>/dev/null; then
                return 0
            elif gunzip -cf "$input_file" > "$output_file" 2>/dev/null; then
                return 0
            fi
            ;;
        *"xz compressed"*)
            xz -dc "$input_file" > "$output_file" && return 0
            ;;
        *"bzip2 compressed"*)
            bzip2 -dc "$input_file" > "$output_file" && return 0
            ;;
        *)
            # 根据扩展名尝试
            case "$input_file" in
                *.gz) gunzip -c "$input_file" > "$output_file" 2>/dev/null && return 0 ;;
                *.xz) xz -dc "$input_file" > "$output_file" && return 0 ;;
                *.bz2) bzip2 -dc "$input_file" > "$output_file" && return 0 ;;
            esac
            ;;
    esac
    
    return 1
}

# 格式化字节大小为人类可读格式
format_bytes() {
    local bytes=$1
    
    if ! [[ "$bytes" =~ ^[0-9]+$ ]] || [ "$bytes" -eq 0 ]; then
        echo "0B"
        return
    fi
    
    if [ "$bytes" -ge 1099511627776 ]; then
        # TB
        local tb=$((bytes / 1099511627776))
        local remainder=$(( (bytes % 1099511627776) * 10 / 1099511627776 ))
        [ "$remainder" -gt 0 ] && echo "${tb}.${remainder}TB" || echo "${tb}TB"
    elif [ "$bytes" -ge 1073741824 ]; then
        # GB
        local gb=$((bytes / 1073741824))
        local remainder=$(( (bytes % 1073741824) * 10 / 1073741824 ))
        [ "$remainder" -gt 0 ] && echo "${gb}.${remainder}GB" || echo "${gb}GB"
    elif [ "$bytes" -ge 1048576 ]; then
        # MB
        local mb=$((bytes / 1048576))
        local remainder=$(( (bytes % 1048576) * 10 / 1048576 ))
        [ "$remainder" -gt 0 ] && echo "${mb}.${remainder}MB" || echo "${mb}MB"
    elif [ "$bytes" -ge 1024 ]; then
        # KB
        local kb=$((bytes / 1024))
        echo "${kb}KB"
    else
        echo "${bytes}B"
    fi
}

# 获取存储池列表
get_storage_pools() {
    print_info "正在获取可用的存储池列表..."
    
    # pvesm status 输出格式: Name Type Status Total Used Available
    # 数值单位是字节
    local storage_info
    storage_info=$(pvesm status 2>/dev/null | awk 'NR>1')
    
    if [ -z "$storage_info" ]; then
        print_error "未找到可用的存储池"
        exit 1
    fi
    
    STORAGE_LIST=()
    STORAGE_MAP=()
    
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ ! "$line" =~ ^[a-zA-Z0-9_-] ]] && continue
        
        local fields
        read -ra fields <<< "$line"
        
        local name="${fields[0]}"
        local type="${fields[1]}"
        local status="${fields[2]}"
        local total="${fields[3]:-0}"
        local used="${fields[4]:-0}"
        local avail="${fields[5]:-0}"
        
        # 跳过非活动存储
        if [ "$status" != "active" ]; then
            continue
        fi
        
        # 检查是否支持VM镜像 - 使用 pvesm 配置检查
        local supports_images="false"
        local storage_content
        storage_content=$(pvesm list "$name" --content images 2>&1)
        if [ $? -eq 0 ]; then
            supports_images="true"
        fi
        
        # 备用方法：检查存储配置
        if [ "$supports_images" = "false" ]; then
            local cfg_content
            cfg_content=$(grep -A10 "^${name}:" /etc/pve/storage.cfg 2>/dev/null | grep "content" | head -1)
            if [[ "$cfg_content" == *"images"* ]]; then
                supports_images="true"
            fi
        fi
        
        # 格式化显示（数值是字节）
        local display_total display_used display_avail
        display_total=$(format_bytes "$total")
        display_used=$(format_bytes "$used")
        display_avail=$(format_bytes "$avail")
        
        STORAGE_LIST+=("$name")
        STORAGE_MAP["$name"]="$type|$display_total|$display_used|$display_avail|$supports_images"
        
    done <<< "$storage_info"
    
    print_success "找到 ${#STORAGE_LIST[@]} 个可用存储池"
}

# 选择存储池
select_storage_pool() {
    echo -e "\n${BLUE}可用的存储池:${NC}"
    echo -e "${YELLOW}提示：标记为 ✓ 的存储池支持VM镜像${NC}"
    
    for i in "${!STORAGE_LIST[@]}"; do
        local name="${STORAGE_LIST[$i]}"
        local info="${STORAGE_MAP[$name]}"
        
        IFS='|' read -r type total used avail supports <<< "$info"
        
        local mark label
        if [[ "$supports" == "true" ]]; then
            mark="${GREEN}✓${NC}"
            label="支持VM"
        else
            mark="${YELLOW}?${NC}"
            label="可能支持"
        fi
        
        printf "%d) %s %b (类型: %s, 总量: %s, 已用: %s, 可用: %s) [%s]\n" \
            $((i+1)) "$name" "$mark" "$type" "$total" "$used" "$avail" "$label"
    done
    
    while true; do
        read -rp "请选择存储池 (1-${#STORAGE_LIST[@]}): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#STORAGE_LIST[@]}" ]; then
            VM_STORAGE="${STORAGE_LIST[$((choice-1))]}"
            local info="${STORAGE_MAP[$VM_STORAGE]}"
            
            IFS='|' read -r type total used avail supports <<< "$info"
            
            # 不再强制检查，允许用户选择任何存储池
            if [[ "$supports" != "true" ]]; then
                print_warning "存储池 '$VM_STORAGE' 可能不支持VM镜像，是否继续？"
                read -rp "继续使用此存储池? (y/n): " confirm
                if [[ ! "$confirm" =~ ^[Yy] ]]; then
                    continue
                fi
            fi
            
            print_success "已选择存储池: $VM_STORAGE"
            print_info "存储池信息: 类型=$type, 总量=$total, 可用=$avail"
            break
        else
            print_error "无效选择"
        fi
    done
}

# 获取下一个VM ID
get_next_vm_id() {
    print_info "正在获取下一个可用的VM ID..."
    
    local max_id
    max_id=$(qm list 2>/dev/null | awk 'NR>1 {print $1}' | sort -n | tail -n1)
    
    if [ -z "$max_id" ]; then
        NEXT_ID=100
    else
        NEXT_ID=$((max_id + 1))
    fi
    
    print_success "下一个可用的VM ID: $NEXT_ID"
}

# 配置虚拟机参数
configure_vm() {
    echo -e "\n${BLUE}虚拟机配置:${NC}"
    
    # CPU
    while true; do
        read -rp "请输入CPU核心数 (默认: 2): " cpu_cores
        cpu_cores=${cpu_cores:-2}
        
        if [[ "$cpu_cores" =~ ^[0-9]+$ ]] && [ "$cpu_cores" -ge 1 ] && [ "$cpu_cores" -le 16 ]; then
            print_success "CPU核心数: $cpu_cores"
            break
        fi
        print_error "请输入1-16之间的数字"
    done
    
    # 内存
    while true; do
        read -rp "请输入内存大小 (MB) (默认: 1024): " memory_size
        memory_size=${memory_size:-1024}
        
        if [[ "$memory_size" =~ ^[0-9]+$ ]] && [ "$memory_size" -ge 256 ] && [ "$memory_size" -le 16384 ]; then
            print_success "内存大小: ${memory_size}MB"
            break
        fi
        print_error "请输入256-16384之间的数字"
    done
    
    # 启动选项
    while true; do
        read -rp "是否在创建后启动虚拟机? (y/n, 默认: n): " start_vm
        start_vm=${start_vm:-n}
        
        case $start_vm in
            [Yy]*)
                START_ON_BOOT=1
                print_success "虚拟机将在创建后启动"
                break
                ;;
            [Nn]*)
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


# 检查EFI固件
check_efi_firmware() {
    if [ "$BOOT_MODE" != "efi" ]; then
        BOOT_MACHINE="pc"
        BOOT_FIRMWARE=""
        return 0
    fi
    
    print_info "检查EFI固件可用性..."
    
    BOOT_MACHINE="q35"
    BOOT_FIRMWARE="ovmf"
    
    local firmware_paths=(
        "/usr/share/pve-edk2-firmware/*OVMF*"
        "/usr/share/ovmf/OVMF.fd"
        "/usr/share/ovmf/OVMF_CODE.fd"
        "/usr/share/qemu/ovmf-x86_64.bin"
        "/usr/share/OVMF/OVMF.fd"
    )
    
    for path in "${firmware_paths[@]}"; do
        if ls $path 1>/dev/null 2>&1; then
            print_success "EFI固件可用"
            return 0
        fi
    done
    
    print_warning "未检测到EFI固件，尝试安装..."
    
    if command -v apt-get &>/dev/null; then
        if apt-get update && apt-get install -y pve-edk2-firmware ovmf; then
            print_success "EFI固件安装完成"
            return 0
        fi
    elif command -v yum &>/dev/null; then
        if yum install -y edk2-ovmf; then
            print_success "EFI固件安装完成"
            return 0
        fi
    elif command -v dnf &>/dev/null; then
        if dnf install -y edk2-ovmf; then
            print_success "EFI固件安装完成"
            return 0
        fi
    fi
    
    print_warning "EFI固件安装失败，回退到BIOS模式"
    BOOT_MODE="bios"
    BOOT_MACHINE="pc"
    BOOT_FIRMWARE=""
    return 1
}

# 创建虚拟机
create_vm() {
    print_info "正在创建虚拟机..."
    
    local vm_name="LuoWrt"
    
    # 验证存储池
    if ! pvesm status -content images "$VM_STORAGE" >/dev/null 2>&1; then
        print_error "存储池 '$VM_STORAGE' 不支持VM镜像"
        return 1
    fi
    
    # 检查EFI固件
    check_efi_firmware
    
    # 构建创建命令
    local create_cmd="qm create $NEXT_ID"
    create_cmd+=" --name $vm_name"
    create_cmd+=" --memory $memory_size"
    create_cmd+=" --cores $cpu_cores"
    create_cmd+=" --machine $BOOT_MACHINE"
    create_cmd+=" --net0 virtio,bridge=vmbr0"
    create_cmd+=" --serial0 socket"
    create_cmd+=" --vga serial0"
    create_cmd+=" --bootdisk scsi0"
    create_cmd+=" --scsihw virtio-scsi-pci"
    
    if [ "$BOOT_MODE" = "efi" ]; then
        create_cmd+=" --bios ovmf"
        create_cmd+=" --efidisk0 $VM_STORAGE:1,efitype=4m"
    fi
    
    print_info "执行虚拟机创建命令..."
    if ! eval "$create_cmd"; then
        print_error "虚拟机创建失败"
        return 1
    fi
    print_success "虚拟机创建成功"
    
    # 导入磁盘
    print_info "正在导入磁盘镜像..."
    if ! qm importdisk "$NEXT_ID" "$IMAGE_FILE" "$VM_STORAGE"; then
        print_error "磁盘镜像导入失败"
        return 1
    fi
    print_success "磁盘镜像导入成功"
    
    # 配置磁盘
    local disk_path="$VM_STORAGE:vm-$NEXT_ID-disk-0"
    if ! qm set "$NEXT_ID" --scsi0 "$disk_path" --boot c --agent enabled=1; then
        print_error "磁盘配置失败"
        return 1
    fi
    print_success "磁盘配置成功"
    
    # 设置启动顺序
    qm set "$NEXT_ID" --boot order=scsi0
    
    # 启动虚拟机
    if [ "$START_ON_BOOT" -eq 1 ]; then
        qm set "$NEXT_ID" --onboot 1
        print_info "正在启动虚拟机..."
        qm start "$NEXT_ID"
    fi
    
    print_success "虚拟机创建完成！"
    echo ""
    print_info "VM ID: $NEXT_ID"
    print_info "VM Name: $vm_name"
    print_info "CPU: $cpu_cores cores"
    print_info "Memory: ${memory_size}MB"
    print_info "Storage: $VM_STORAGE"
    print_info "Boot Mode: $BOOT_MODE"
}

# 清理临时文件
cleanup() {
    print_info "清理临时文件..."
    rm -rf "$DOWNLOAD_DIR"
    print_success "清理完成"
}

# 主函数
main() {
    echo -e "${GREEN}=== LuoWrt 自动安装脚本 ===${NC}"
    echo -e "${GREEN}适用于 Proxmox VE 环境${NC}\n"
    
    check_pve_environment
    
    if ! detect_system_architecture; then
        print_warning "自动架构检测失败，请手动选择"
        select_architecture
    fi
    
    check_disk_space
    
    print_info "使用GitHub仓库: $GITHUB_REPO"
    print_info "下载目录: $DOWNLOAD_DIR"
    print_info "检测到架构: $(build_arch_pattern "display")"
    
    get_latest_release
    select_rom_version
    get_storage_pools
    select_storage_pool
    get_next_vm_id
    configure_vm
    
    # 确认
    echo -e "\n${BLUE}配置确认:${NC}"
    echo "VM ID: $NEXT_ID"
    echo "系统架构: $(build_arch_pattern "display")"
    echo "ROM版本: ${ROM_SIZE}MB"
    echo "文件格式: $FILE_FORMAT"
    echo "启动方式: $BOOT_MODE"
    echo "存储池: $VM_STORAGE"
    echo "CPU: $cpu_cores cores"
    echo "Memory: ${memory_size}MB"
    echo "启动虚拟机: $([ "$START_ON_BOOT" -eq 1 ] && echo "是" || echo "否")"
    
    read -rp "确认创建虚拟机? (y/n): " confirm
    case $confirm in
        [Yy]*)
            download_rom
            create_vm
            ;;
        *)
            print_info "用户取消操作"
            ;;
    esac
    
    cleanup
    
    echo -e "\n${GREEN}=== 完成 ===${NC}"
    print_info "虚拟机管理命令:"
    echo "  启动: qm start $NEXT_ID"
    echo "  停止: qm stop $NEXT_ID"
    echo "  控制台: qm terminal $NEXT_ID"
    echo "  删除: qm destroy $NEXT_ID"
}

main "$@"
