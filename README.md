# Network Status Monitor

监控内网和公网 IP 变动，并通过飞书机器人推送通知。

## 功能

- 自动检测内网接口 IP 变更（新增 / 修改 / 丢失）
- 自动检测公网 IP 变更
- 飞书卡片消息推送，严重事件红色告警
- 支持 Linux systemd 服务 / Windows NSSM 服务 或任务计划
- 提供预编译二进制包，开箱即用

## 下载

从 [Releases](https://github.com/Moxin1044/Network_status_monitoring/releases/latest) 下载对应平台的压缩包：

| 平台 | 架构 | 文件 |
|------|------|------|
| Linux | x86_64 (64位) | `network-status-monitoring-linux-amd64.tar.gz` |
| Linux | i686 (32位) | `network-status-monitoring-linux-386.tar.gz` |
| Linux | armv7 (arm) | `network-status-monitoring-linux-arm.tar.gz` |
| Linux | aarch64 (arm64) | `network-status-monitoring-linux-arm64.tar.gz` |
| Windows | x86_64 (64位) | `network-status-monitoring-windows-amd64.zip` |
| Windows | i686 (32位) | `network-status-monitoring-windows-386.zip` |
| Windows | aarch64 (arm64) | `network-status-monitoring-windows-arm64.zip` |

每个压缩包内包含：

- 可执行文件
- `config.yml` 配置文件模板
- 对应平台的安装脚本（`install.sh` / `install.bat`）

## 配置

编辑 `config.yml`：

```yaml
feishu_webhook: "https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx"
check_interval: 30
```

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `feishu_webhook` | 飞书自定义机器人 Webhook 地址 | `*`（需替换） |
| `check_interval` | 检测间隔，单位：秒 | `30` |

### 获取飞书 Webhook

1. 打开飞书群聊 → **设置** → **群机器人** → **添加机器人** → **自定义机器人**
2. 设置机器人名称（如"网络监控"），点击添加
3. 复制生成的 Webhook 地址，格式为 `https://open.feishu.cn/open-apis/bot/v2/hook/...`
4. 将地址填入 `config.yml` 的 `feishu_webhook` 字段

### 配置文件查找顺序

程序启动时按以下顺序查找 `config.yml`：

1. 当前工作目录下的 `config.yml`
2. `/etc/network_status_monitoring/config.yml`（Linux）
3. `C:\Program Files\NetworkStatusMonitoring\config.yml`（Windows）

若均未找到则使用默认配置（webhook 为 `*`，间隔 30 秒）。

## 部署

### Linux

```bash
# 1. 下载并解压（以 amd64 为例）
wget https://github.com/Moxin1044/Network_status_monitoring/releases/latest/download/network-status-monitoring-linux-amd64.tar.gz
tar xzf network-status-monitoring-linux-amd64.tar.gz

# 2. 编辑配置
vim config.yml

# 3. 运行安装脚本
chmod +x install.sh
sudo ./install.sh
```

安装脚本会自动完成：

- 将二进制文件安装到 `/opt/network-status-monitoring/`
- 创建符号链接 `/usr/local/bin/network-status-monitoring`
- 部署 `config.yml` 到安装目录
- 创建 systemd 服务并提示是否启用开机自启动和立即启动

#### 服务管理

```bash
sudo systemctl start network-status-monitoring    # 启动
sudo systemctl stop network-status-monitoring     # 停止
sudo systemctl restart network-status-monitoring  # 重启
sudo systemctl status network-status-monitoring   # 查看状态
sudo journalctl -u network-status-monitoring -f   # 查看实时日志
sudo systemctl enable network-status-monitoring   # 启用开机自启
sudo systemctl disable network-status-monitoring  # 禁用开机自启
```

#### 卸载

```bash
./install.sh --uninstall
```

### Windows

```
1. 下载并解压 zip 包（以 amd64 为例）
2. 编辑 config.yml，填入飞书 Webhook 地址
3. 右键以管理员身份运行 install.bat
```

安装脚本会自动完成：

- 将程序安装到 `C:\Program Files\NetworkStatusMonitoring\`
- 部署 `config.yml` 到安装目录
- 检测或下载 NSSM，注册 Windows 服务（可用任务计划替代）
- 提示是否启用开机自启动和立即启动

#### 服务管理（NSSM 模式）

```
nssm start NetworkStatusMonitor       # 启动
nssm stop NetworkStatusMonitor        # 停止
nssm restart NetworkStatusMonitor     # 重启
nssm status NetworkStatusMonitor      # 查看状态
```

#### 服务管理（任务计划模式）

```
schtasks /run /tn "NetworkStatusMonitor"        # 启动
schtasks /end /tn "NetworkStatusMonitor"         # 停止
schtasks /change /tn "NetworkStatusMonitor" /enable   # 启用自启
schtasks /change /tn "NetworkStatusMonitor" /disable  # 禁用自启
schtasks /delete /tn "NetworkStatusMonitor" /f        # 删除任务
```

#### 卸载

```
install.bat --uninstall
```

### 从源码编译

需要安装 [Rust](https://rustup.rs/)，然后：

```bash
git clone https://github.com/Moxin1044/Network_status_monitoring.git
cd Network_status_monitoring

# 编辑配置
vim config.yml

# 编译并使用源码目录自带的安装脚本
cargo build --release
sudo ./install.sh        # Linux
install.bat              # Windows（管理员）
```

源码目录的 `install.sh` / `install.bat` 会自动编译后再安装。

## 通知示例

程序启动时发送蓝色卡片，包含当前所有监控接口和公网 IP：

> 🟢 网络监控启动
> 📡 监控已启动，当前网络状态如下
> 🌐 **ens192**　IP: `192.168.1.100`
> 🌐 **公网 IP**: `1.2.3.4`

检测到变更时发送橙色/红色卡片：

> ⚠️ 网络状态变更通知
> 📡 **检测到变更**: `ens192` IP变更、公网IP变更
> 🌐 **ens192** IP变更
> 　　↩️ 旧: `192.168.1.100`
> 　　➡️ 新: `192.168.1.200`
> 🌐 **公网IP变更**
> 　　↩️ 旧: `1.2.3.4`
> 　　➡️ 新: `5.6.7.8`

接口下线或公网 IP 丢失时使用红色告警卡片。

## 监控的接口

默认监控以下前缀的网络接口：

- `ens*` — 以太网接口
- `enp*` — 以太网接口（可预测命名）
- `wlp*` — 无线网卡接口

## 许可证

MIT
