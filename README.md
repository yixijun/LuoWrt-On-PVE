# LuoWrt 自动安装脚本

这是一个用于在 Proxmox VE (PVE) 环境中自动安装 LuoWrt 的 Linux 脚本。

## 功能特性

- 🔄 自动从 GitHub 下载最新的 LuoWrt release
- 💾 支持 512MB 和 3072MB ROM 版本选择
- 💿 支持多种固件格式：img.gz、qcow2、vmdk
- 🔄 支持 BIOS 和 EFI (UEFI) 启动模式选择
- 🔧 自动检测和安装 EFI 固件
- 🖥️ 自动获取下一个可用的 VM ID
- 💽 自动检测并选择 PVE 存储池
- ⚙️ 可配置 CPU 核心数和内存大小
- 🚀 可选择是否在创建后启动虚拟机
- 🧹 自动清理临时文件
- 💾 **智能空间管理**：多级临时目录选择，自动清理机制
- 📊 **精确空间预估**：预估下载和解压所需空间
- 🔍 **智能文件解压**：自动识别多种压缩格式（gzip、xz、bzip2）
- 🛠️ **格式兼容性**：支持非标准压缩文件和已解压镜像
- 🔍 **实时空间监控**：下载过程中动态检查磁盘空间
- ✅ **文件完整性检查**：自动验证下载和解压后的文件

## 系统要求

- Proxmox VE 环境
- 具有创建虚拟机权限的用户
- 网络连接（用于从 GitHub 下载文件）
- 基本的 Linux 工具：curl, wget, qm, pvesm 命令

## 使用方法

1. 将脚本下载到您的 PVE 主机：
```bash
wget https://raw.githubusercontent.com/yixijun/LuoWrt-On-PVE/main/install_luowrt.sh
```

2. 添加执行权限：
```bash
chmod +x install_luowrt.sh
```

3. 运行脚本：
```bash
sudo ./install_luowrt.sh
```

## 配置说明

### 脚本配置

在运行前，您可以修改脚本中的以下变量：

```bash
GITHUB_REPO="yixijun/LuoWrt"  # LuoWrt GitHub 仓库名
```

**注意**：PVE 存储池现在由用户在运行时交互选择，无需预先配置。

### 文件名匹配

脚本支持以下固件格式和版本：

**支持的版本：**
- LuoWrt-512：512MB RAM版本
- LuoWrt-3072：3072MB RAM版本

**支持的格式：**
- img.gz：推荐格式，兼容性最好（需要解压）
- qcow2：QCOW2格式（直接使用）
- vmdk：VMware格式（直接使用）

**启动模式：**
- BIOS：传统启动模式，兼容性最好，适用于大多数情况
- EFI：现代UEFI启动模式，支持新硬件特性

**文件名示例：**
- `LuoWrt-512-x86-64-generic-squashfs-combined.img.gz` (BIOS版本)
- `LuoWrt-3072-x86-64-generic-squashfs-combined.qcow2` (BIOS版本)
- `LuoWrt-3072-x86-64-generic-squashfs-combined-efi.vmdk` (EFI版本)
- `LuoWrt-512-x86-64-uefi-gpt-squashfs-combined.img.gz` (EFI版本)

**注意：EFI模式会自动搜索带有 "-efi"、"uefi" 等标识的文件。**

## 脚本执行流程

1. **环境检查**：确认当前运行在 PVE 环境中
2. **获取最新版本**：从 GitHub API 获取最新的 release 信息
3. **版本选择**：用户选择 512MB 或 3072MB ROM 版本
4. **格式选择**：用户选择固件格式（img.gz、qcow2、vmdk）
5. **启动方式选择**：用户选择 BIOS 或 EFI (UEFI) 启动模式
6. **固件检测**：检查并自动安装所需的固件（EFI模式）
7. **下载 ROM**：下载并处理选中的 ROM 文件（根据启动模式智能匹配）
8. **存储池检测**：自动检测并显示可用的 PVE 存储池
9. **存储池选择**：用户选择要使用的存储池（显示详细信息如类型、大小、可用空间）
10. **VM ID 分配**：自动获取下一个可用的虚拟机 ID
11. **配置虚拟机**：设置 CPU 核心数、内存大小和启动选项
12. **创建虚拟机**：在 PVE 中创建并配置虚拟机（包含适当的固件配置）
13. **清理**：删除临时下载的文件

## 示例输出

```
=== LuoWrt 自动安装脚本 ===
适用于 Proxmox VE 环境

[SUCCESS] 检测到PVE环境
[INFO] 正在从GitHub获取最新release信息...
[SUCCESS] 找到最新版本: v23.05.2

可用的ROM版本:
1) 512MB版本
2) 3072MB版本
请选择ROM版本 (1-2): 1
[SUCCESS] 已选择512MB版本

选择文件格式:
1) img.gz (推荐，兼容性最好)
2) qcow2 (QCOW2格式)
3) vmdk (VMware格式)
请选择文件格式 (1-3): 1
[SUCCESS] 已选择 img.gz 格式

选择启动方式:
1) BIOS (传统启动模式，兼容性好)
2) EFI (UEFI启动模式，现代系统推荐)
请选择启动方式 (1-2): 1
[SUCCESS] 已选择 BIOS 启动模式

[INFO] 正在搜索512 MB img.gz 格式的下载链接...
[SUCCESS] 下一个可用的VM ID: 105

[INFO] 正在获取可用的存储池列表...
[SUCCESS] 找到 2 个可用存储池

可用的存储池:
1) local-lvm (类型: lvm-thin, 大小: 100G, 已用: 20G, 可用: 80G)
2) local (类型: dir, 大小: 500G, 已用: 150G, 可用: 350G)
请选择存储池 (1-2): 1
[SUCCESS] 已选择存储池: local-lvm
[INFO] 存储池信息: 类型=lvm-thin, 总大小=100G, 可用空间=80G

虚拟机配置:
请输入CPU核心数 (默认: 2): 2
[SUCCESS] CPU核心数: 2
请输入内存大小 (MB) (默认: 1024): 1024
[SUCCESS] 内存大小: 1024MB
是否在创建后启动虚拟机? (y/n, 默认: n): y
[SUCCESS] 虚拟机将在创建后启动

配置确认:
VM ID: 105
ROM版本: 512MB
文件格式: img.gz
启动方式: bios
存储池: local-lvm
CPU: 2 cores
Memory: 1024MB
启动虚拟机: 是
确认创建虚拟机? (y/n): y

[INFO] 正在创建虚拟机...
[INFO] 正在导入磁盘镜像...
[SUCCESS] 虚拟机创建完成！

=== 安装完成 ===
您可以通过以下命令管理虚拟机:
  启动: qm start 105
  停止: qm stop 105
  控制台: qm terminal 105
  删除: qm destroy 105
```

## 故障排除

### 常见问题

1. **无法连接到 GitHub API**
   - 检查网络连接
   - 确认 GitHub 仓库名称正确

2. **找不到匹配的 ROM 文件**
   - 检查文件名匹配模式是否正确
   - 确认 release 中包含所需版本的文件

3. **权限不足**
   - 确保以具有 PVE 管理权限的用户运行脚本
   - 使用 `sudo` 运行脚本

4. **找不到可用的存储池**
   - 检查 PVE 存储配置
   - 确保有权限访问存储池
   - 运行 `pvesm status` 检查存储状态

5. **存储空间不足**
   - 在选择存储池时注意查看可用空间
   - 选择有足够空间的存储池
   - 清理不必要的虚拟机或磁盘

6. **解压时出现 "gzip: no space on device" 错误**
   - 脚本已全面优化空间管理，采用多级临时目录选择机制
   - **智能临时目录选择**：自动尝试多个目录（/tmp、/var/tmp、/root/tmp、/opt/tmp）
   - **流式解压技术**：避免同时存储压缩文件和解压文件，节省磁盘空间
   - **自动空间清理**：在空间不足时自动清理临时文件
   - **精确空间预估**：根据压缩文件大小预估解压后所需空间
   - **最低空间要求**：建议至少有 3GB 可用空间用于临时文件

   **如果仍然遇到空间问题：**
   ```bash
   # 手动清理系统临时文件
   sudo rm -rf /tmp/*
   sudo rm -rf /var/tmp/*

   # 清理旧的包文件（Debian/Ubuntu）
   sudo apt-get clean
   sudo apt-get autoremove

   # 清理日志文件
   sudo journalctl --vacuum-time=7d

   # 检查磁盘使用情况
   df -h
   du -sh /tmp/*
   ```

  7. **解压时出现 "trailing garbage ignored" 警告或解压失败**
   - 脚本已升级智能解压系统，自动处理各种压缩格式
   - **多格式支持**：gzip、xz、bzip2 以及非标准压缩文件
   - **格式自动检测**：使用 `file` 命令智能识别文件类型
   - **容错处理**：自动处理文件头损坏、尾部垃圾数据等问题
   - **镜像文件检测**：自动识别已解压的磁盘镜像文件

   **如果仍然遇到解压问题：**
   ```bash
   # 手动检查文件类型
   file downloaded_file.gz
   hexdump -C downloaded_file.gz | head -n1

   # 尝试手动解压
   gunzip -c downloaded_file.gz > output.img
   # 或者强制解压
   gunzip -cf downloaded_file.gz > output.img

   # 检查解压结果
   file output.img
   ls -lh output.img
   ```

   **自定义临时目录：**
   在脚本开头修改 `DOWNLOAD_DIR` 变量：
   ```bash
   DOWNLOAD_DIR="/path/to/your/large/disk/luowrt"
   ```

8. **EFI启动相关问题**
   - 脚本会自动检测并尝试安装EFI固件
   - 如果EFI固件安装失败，会自动回退到BIOS模式
   - 支持多种包管理器：apt-get (Debian/Ubuntu)、yum/dnf (RedHat/CentOS)

   **手动安装EFI固件：**
   ```bash
   # Debian/Ubuntu PVE
   sudo apt-get update
   sudo apt-get install pve-edk2-firmware ovmf

   # CentOS/RHEL
   sudo yum install edk2-ovmf
   # 或者使用 dnf
   sudo dnf install edk2-ovmf
   ```

   **EFI模式启动失败：**
   - 检查虚拟机是否设置为EFI启动模式
   - 确认下载的是EFI版本的固件文件
   - 可以重新创建虚拟机选择BIOS模式

### 日志和调试

脚本会在执行过程中显示详细的操作信息。如果遇到问题，请查看输出中的错误信息。

## 自定义和扩展

您可以轻松修改脚本以适应您的特定需求：

- 添加更多 ROM 版本选项
- 修改网络配置
- 添加更多的虚拟机硬件选项
- 集成自动化部署流程

## 安全注意事项

- 仅在受信任的网络上运行此脚本
- 验证下载的 ROM 文件的完整性和来源
- 定期更新脚本以确保安全性

## 许可证

此脚本为开源软件，您可以自由使用、修改和分发。

## 支持

如果您遇到问题或有建议，请通过以下方式联系：
- 提交 Issue 到代码仓库
- 发送邮件至维护者

---

**注意**：使用此脚本前，请确保您了解 PVE 虚拟机管理的基本知识，并备份重要数据。