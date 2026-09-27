#!/bin/bash

# Server Services Bootstrap Script
# Checks and starts services if they're not running

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check and start systemd service
check_systemd_service() {
  local service=$1
  if systemctl is-active --quiet "$service"; then
    log_info "$service is already running"
  else
    log_warn "$service is not running. Starting..."
    sudo systemctl start "$service"
    if systemctl is-active --quiet "$service"; then
      log_info "$service started successfully"
    else
      log_error "Failed to start $service"
    fi
  fi
}

# Function to check and start docker compose project
check_docker_compose() {
  local project_name=$1
  local project_path=$2

  if [ ! -d "$project_path" ]; then
    log_error "Directory '$project_path' does not exist"
    return
  fi

  cd "$project_path"

  # Check if any containers from this compose project are running
  local running=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)
  local total=$(docker compose ps --services 2>/dev/null | wc -l)

  if [ "$running" -gt 0 ] && [ "$running" -eq "$total" ]; then
    log_info "$project_name compose stack is already running"
  else
    log_warn "$project_name compose stack is not fully running. Starting..."
    docker compose up -d
    if [ $? -eq 0 ]; then
      log_info "$project_name started successfully"
    else
      log_error "Failed to start $project_name"
    fi
  fi

  cd - >/dev/null
}

# Function to check and start VirtualBox VM
check_virtualbox_vm() {
  local vm_name=$1

  # VirtualBox needs to be run as the regular user, not root
  if [ "$EUID" -eq 0 ]; then
    local vm_status=$(sudo -u xdx VBoxManage showvminfo "$vm_name" --machinereadable 2>/dev/null | grep "VMState=" | cut -d'"' -f2)

    if [ "$vm_status" == "running" ]; then
      log_info "VirtualBox VM '$vm_name' is already running"
    else
      log_warn "VirtualBox VM '$vm_name' is not running. Starting in headless mode..."
      sudo -u xdx VBoxManage startvm "$vm_name" --type headless 2>/dev/null || log_error "Failed to start VM '$vm_name'"
    fi
  else
    local vm_status=$(VBoxManage showvminfo "$vm_name" --machinereadable 2>/dev/null | grep "VMState=" | cut -d'"' -f2)

    if [ "$vm_status" == "running" ]; then
      log_info "VirtualBox VM '$vm_name' is already running"
    else
      log_warn "VirtualBox VM '$vm_name' is not running. Starting in headless mode..."
      VBoxManage startvm "$vm_name" --type headless 2>/dev/null || log_error "Failed to start VM '$vm_name'"
    fi
  fi
}

echo "========================================"
echo "Starting Server Services Bootstrap"
echo "========================================"
echo

# Check if running with appropriate privileges
if [ "$EUID" -ne 0 ] && ! groups | grep -q docker; then
  log_warn "This script requires sudo for systemd services and docker group membership for containers"
fi

# Systemd Services
log_info "Checking systemd services..."
check_systemd_service "nginx"
check_systemd_service "authelia"
check_systemd_service "postfix"
check_systemd_service "plexmediaserver"

echo

# VirtualBox VM (Home Assistant)
log_info "Checking VirtualBox VM..."
check_virtualbox_vm "HomeAssistant"

echo

# Docker Compose Projects
log_info "Checking docker compose projects..."
check_docker_compose "Uptime Kuma" "/opt/stacks/uptime-kuma"
check_docker_compose "Nextcloud" "/opt/stacks/nextcloud-docker"
check_docker_compose "Vaultwarden" "/opt/stacks/vaultwarden"
check_docker_compose "HomePage" "/opt/stacks/homepage"
check_docker_compose "Dockge" "/opt/dockge"
echo
echo "========================================"
echo "Bootstrap Complete"
echo "========================================"
