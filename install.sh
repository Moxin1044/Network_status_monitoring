#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "  ${BLUE}ℹ${NC}  $1"; }
success() { echo -e "  ${GREEN}✔${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
error()   { echo -e "  ${RED}✖${NC}  $1"; }

ask_yes() {
    local prompt="$1"
    local default="${2:-Y}"
    if [[ "$default" == "Y" ]]; then
        prompt="$prompt ${CYAN}[Y/n]${NC} "
    else
        prompt="$prompt ${CYAN}[y/N]${NC} "
    fi
    while true; do
        read -p "$(echo -e "$prompt")" answer
        case "$answer" in
            [yY][eE][sS]|[yY]) return 0 ;;
            [nN][oO]|[nN]) return 1 ;;
            "") [[ "$default" == "Y" ]] && return 0 || return 1 ;;
            *) echo -e "  ${YELLOW}请输入 y 或 n${NC}" ;;
        esac
    done
}

SERVICE_NAME="network-status-monitoring"
INSTALL_DIR="/opt/network-status-monitoring"
BIN_LINK="/usr/local/bin/network-status-monitoring"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

do_uninstall() {
    echo ""
    echo -e "${BOLD}${RED}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${RED}│${NC}   ${BOLD}Network Status Monitor - 卸载程序${NC}               ${BOLD}${RED}│${NC}"
    echo -e "${BOLD}${RED}└─────────────────────────────────────────────────┘${NC}"
    echo ""

    local found=0

    if sudo systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        found=1
        echo -e "${BOLD}  步骤 1/5: 停止服务${NC}"
        echo ""
        sudo systemctl stop "$SERVICE_NAME"
        success "服务已停止"
        echo ""
    else
        info "服务未运行，跳过停止步骤"
        echo ""
        [[ -f "$SERVICE_FILE" ]] && found=1
        [[ -d "$INSTALL_DIR" ]] && found=1
        [[ -L "$BIN_LINK" ]] && found=1
    fi

    if [[ "$found" -eq 0 ]]; then
        error "未检测到 Network Status Monitor 的安装"
        echo ""
        exit 1
    fi

    echo -e "${BOLD}  步骤 2/5: 禁用开机自启动并移除服务${NC}"
    echo ""

    if [[ -f "$SERVICE_FILE" ]]; then
        sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        sudo rm -f "$SERVICE_FILE"
        sudo systemctl daemon-reload
        success "systemd 服务已移除"
    else
        info "未找到服务文件，跳过"
    fi

    echo ""
    echo -e "${BOLD}  步骤 3/5: 移除可执行文件链接${NC}"
    echo ""

    if [[ -L "$BIN_LINK" ]]; then
        sudo rm -f "$BIN_LINK"
        success "已移除: ${BIN_LINK}"
    else
        info "未找到链接文件，跳过"
    fi

    echo ""
    echo -e "${BOLD}  步骤 4/5: 移除安装目录${NC}"
    echo ""

    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/config.yml" ]]; then
            if ask_yes "是否保留配置文件 config.yml?" "N"; then
                sudo cp "$INSTALL_DIR/config.yml" "/tmp/network-status-monitoring-config.yml.bak"
                success "配置文件已备份到: /tmp/network-status-monitoring-config.yml.bak"
            fi
        fi
        sudo rm -rf "$INSTALL_DIR"
        success "安装目录已移除: ${INSTALL_DIR}"
    else
        info "安装目录不存在，跳过"
    fi

    echo ""
    echo -e "${BOLD}  步骤 5/5: 清理残留${NC}"
    echo ""

    local has_residual=0

    if sudo systemctl list-unit-files "$SERVICE_NAME.service" &>/dev/null; then
        sudo systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
        info "已清理 systemd 残留状态"
        has_residual=1
    fi

    if [[ "$has_residual" -eq 0 ]]; then
        info "无残留需要清理"
    fi

    echo ""
    echo -e "${BOLD}${GREEN}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${GREEN}│${NC}   ${BOLD}卸载完成!${NC}                                     ${BOLD}${GREEN}│${NC}"
    echo -e "${BOLD}${GREEN}└─────────────────────────────────────────────────┘${NC}"
    echo ""
    if [[ -f "/tmp/network-status-monitoring-config.yml.bak" ]]; then
        echo -e "  ${CYAN}配置备份:${NC}  /tmp/network-status-monitoring-config.yml.bak"
    fi
    echo ""
}

do_install() {
    echo ""
    echo -e "${BOLD}${CYAN}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${CYAN}│${NC}   ${BOLD}Network Status Monitor - Linux 安装程序${NC}       ${BOLD}${CYAN}│${NC}"
    echo -e "${BOLD}${CYAN}└─────────────────────────────────────────────────┘${NC}"
    echo ""

    if [[ "$EUID" -eq 0 ]]; then
        warn "检测到以 root 运行，建议使用普通用户执行此脚本"
        if ! ask_yes "是否继续?" "N"; then
            exit 0
        fi
    fi

    if ! command -v sudo &> /dev/null; then
        error "未找到 sudo，请安装后再试"
        exit 1
    fi

    echo -e "${BOLD}  步骤 1/6: 检查编译环境${NC}"
    echo ""

    if ! command -v cargo &> /dev/null; then
        error "未找到 cargo"
        echo ""
        if ask_yes "是否自动安装 Rust? (将通过 rustup.rs 安装)" "Y"; then
            info "正在安装 Rust..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source "$HOME/.cargo/env"
            success "Rust 安装完成"
        else
            error "需要 Rust 编译环境，安装中止"
            exit 1
        fi
    else
        success "cargo 已就绪 ($(cargo --version 2>/dev/null || echo 'unknown'))"
    fi

    echo ""
    echo -e "${BOLD}  步骤 2/6: 编译项目${NC}"
    echo ""

    info "正在编译 release 版本，请稍候..."
    cd "$SCRIPT_DIR"
    cargo build --release 2>&1 | tail -1
    success "编译完成: target/release/${SERVICE_NAME}"

    echo ""
    echo -e "${BOLD}  步骤 3/6: 安装文件${NC}"
    echo ""

    info "安装目录: ${INSTALL_DIR}"

    if [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/config.yml" ]]; then
        warn "检测到已有安装，将保留原有配置文件"
        KEEP_CONFIG=1
    else
        KEEP_CONFIG=0
    fi

    sudo mkdir -p "$INSTALL_DIR"
    sudo cp "target/release/${SERVICE_NAME}" "$INSTALL_DIR/"
    sudo chmod +x "$INSTALL_DIR/${SERVICE_NAME}"

    if [[ "$KEEP_CONFIG" -eq 1 ]]; then
        info "保留现有 config.yml"
    else
        if [[ -f "config.yml" ]]; then
            sudo cp "config.yml" "$INSTALL_DIR/"
        else
            echo -e "feishu_webhook: \"*\"\ncheck_interval: 30" | sudo tee "$INSTALL_DIR/config.yml" > /dev/null
            warn "未找到 config.yml，已生成默认配置"
        fi
    fi

    sudo ln -sf "$INSTALL_DIR/${SERVICE_NAME}" "$BIN_LINK"
    success "可执行文件已安装: ${BIN_LINK} -> ${INSTALL_DIR}/${SERVICE_NAME}"
    success "配置文件: ${INSTALL_DIR}/config.yml"

    echo ""
    echo -e "${BOLD}  步骤 4/6: 创建 systemd 服务${NC}"
    echo ""

    if [[ -f "$SERVICE_FILE" ]]; then
        warn "服务文件已存在，将覆盖"
        sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    fi

    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Network Status Monitor
Documentation=https://github.com/network-status-monitoring
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${SERVICE_NAME}
WorkingDirectory=${INSTALL_DIR}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    success "服务文件已创建: ${SERVICE_FILE}"

    echo ""
    echo -e "${BOLD}  步骤 5/6: 配置开机自启动${NC}"
    echo ""

    if ask_yes "是否启用开机自启动? (systemctl enable)" "Y"; then
        sudo systemctl enable "$SERVICE_NAME"
        success "已启用开机自启动"
    else
        sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        info "未启用开机自启动 (可稍后手动启用)"
    fi

    echo ""
    echo -e "${BOLD}  步骤 6/6: 启动服务${NC}"
    echo ""

    if ask_yes "是否立即启动服务?" "Y"; then
        sudo systemctl start "$SERVICE_NAME"
        sleep 1
        if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
            success "服务已成功启动!"
        else
            error "服务启动失败，请查看日志:"
            echo ""
            sudo journalctl -u "$SERVICE_NAME" -n 10 --no-pager
            echo ""
            warn "常见原因: 网络未就绪 / 配置文件错误"
            info "查看完整日志: sudo journalctl -u $SERVICE_NAME -f"
        fi
    else
        info "服务未启动 (可稍后手动启动)"
    fi

    echo ""
    echo -e "${BOLD}${CYAN}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${CYAN}│${NC}   ${BOLD}安装完成!${NC}                                     ${BOLD}${CYAN}│${NC}"
    echo -e "${BOLD}${CYAN}└─────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BOLD}管理命令:${NC}"
    echo ""
    echo -e "  ${CYAN}启动服务${NC}      sudo systemctl start ${SERVICE_NAME}"
    echo -e "  ${CYAN}停止服务${NC}      sudo systemctl stop ${SERVICE_NAME}"
    echo -e "  ${CYAN}重启服务${NC}      sudo systemctl restart ${SERVICE_NAME}"
    echo -e "  ${CYAN}查看状态${NC}      sudo systemctl status ${SERVICE_NAME}"
    echo -e "  ${CYAN}查看日志${NC}      sudo journalctl -u ${SERVICE_NAME} -f"
    echo -e "  ${CYAN}启用自启${NC}      sudo systemctl enable ${SERVICE_NAME}"
    echo -e "  ${CYAN}禁用自启${NC}      sudo systemctl disable ${SERVICE_NAME}"
    echo -e "  ${CYAN}卸载程序${NC}      ./install.sh --uninstall"
    echo ""
    echo -e "  ${BOLD}配置文件:${NC}  ${INSTALL_DIR}/config.yml"
    echo ""
}

case "${1:-}" in
    --uninstall|-u)
        do_uninstall
        ;;
    --install|-i|"")
        do_install
        ;;
    --help|-h)
        echo ""
        echo "  用法: $0 [选项]"
        echo ""
        echo "  选项:"
        echo "    (无)          安装 Network Status Monitor"
        echo "    --uninstall   卸载 Network Status Monitor"
        echo "    --help        显示帮助信息"
        echo ""
        ;;
    *)
        error "未知选项: $1"
        echo "  使用 --help 查看帮助"
        exit 1
        ;;
esac
