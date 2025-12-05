#!/bin/bash
# ==============================================================================
# Script: niri-undochange.sh
# Purpose: Emergency rollback to 'Before Niri Setup' checkpoint
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

echo ""
echo -e "${H_RED}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${H_RED}║           NIRI INSTALLATION FAILURE DETECTED         ║${NC}"
echo -e "${H_RED}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
warn "Critical error encountered during Niri setup."
log "Initiating system rollback to checkpoint: 'Before Niri Setup'..."

# ------------------------------------------------------------------------------
# Function: Perform Rollback
# ------------------------------------------------------------------------------
perform_rollback() {
    local config="$1"
    local marker="Before Niri Setup"
    
    # 1. 查找标记快照的 ID
    local snap_id
    snap_id=$(snapper -c "$config" list --columns number,description | grep "$marker" | awk '{print $1}' | tail -n 1)
    
    if [ -n "$snap_id" ]; then
        log "Reverting changes in '$config' (Target Snapshot ID: $snap_id)..."
        
        # 2. 执行撤销 (undochange ID..0)
        # 这会将文件系统当前状态(0) 恢复到 ID 的状态
        if snapper -c "$config" undochange "$snap_id"..0; then
            success "Successfully reverted $config."
        else
            error "Failed to revert $config. Manual intervention required."
            # 如果回滚失败，不要重启，让用户看日志
            exit 1 
        fi
    else
        warn "Checkpoint '$marker' not found in $config. Skipping."
    fi
}

# ------------------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------------------

# 1. 回滚 Root 和 Home
perform_rollback "root"
perform_rollback "home"

# 2. 状态文件保护
# 我们保留 .install_progress 文件，这样重启后前面 00-03 的步骤会被自动跳过
# 但为了安全，我们确保 04-niri-setup.sh 不在里面
if [ -f "$PARENT_DIR/.install_progress" ]; then
    sed -i "/04-niri-setup.sh/d" "$PARENT_DIR/.install_progress"
fi

# 3. 强制重启
echo ""
echo -e "${H_YELLOW}>>> Rollback complete. System restored to pre-Niri state.${NC}"
echo -e "${H_YELLOW}>>> The system must reboot to clear memory/process states.${NC}"
echo ""

for i in {10..1}; do
    echo -ne "\r   ${H_RED}Rebooting in ${i}s...${NC}"
    sleep 1
done

echo ""
systemctl reboot