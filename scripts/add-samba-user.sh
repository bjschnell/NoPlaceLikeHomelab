#!/bin/bash

# Samba User Addition Script
# Usage: ./add-samba-user.sh <username>

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
  print_error "This script must be run as root (use sudo)"
  exit 1
fi

# Check if username parameter is provided
if [ $# -eq 0 ]; then
  print_error "Usage: $0 <username>"
  print_error "Example: $0 johnsmith"
  exit 1
fi

USERNAME="$1"

# Validate username (basic check)
if [[ ! "$USERNAME" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]; then
  print_error "Invalid username. Use lowercase letters, numbers, underscore, and dash only."
  print_error "Username should start with a letter or underscore and be max 32 characters."
  exit 1
fi

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
  print_warning "System user '$USERNAME' already exists."
  read -p "Continue with Samba setup for existing user? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Aborted."
    exit 1
  fi
else
  print_status "Creating system user: $USERNAME"
  if useradd -m "$USERNAME"; then
    print_status "System user created successfully"
  else
    print_error "Failed to create system user"
    exit 1
  fi
fi

# Add user to sambausers group
print_status "Adding user to sambausers group"
if usermod -a -G sambausers "$USERNAME"; then
  print_status "User added to sambausers group"
else
  print_error "Failed to add user to sambausers group"
  exit 1
fi

# Check if sambausers group exists, create if it doesn't
if ! getent group sambausers >/dev/null 2>&1; then
  print_warning "sambausers group doesn't exist, creating it..."
  groupadd sambausers
  print_status "sambausers group created"
fi

# Add Samba password
print_status "Setting up Samba password for user: $USERNAME"
print_warning "You will need to enter a password for the Samba user"

if smbpasswd -a "$USERNAME"; then
  print_status "Samba password set successfully"
else
  print_error "Failed to set Samba password"
  exit 1
fi

# Enable the Samba user
print_status "Enabling Samba user"
if smbpasswd -e "$USERNAME"; then
  print_status "Samba user enabled successfully"
else
  print_error "Failed to enable Samba user"
  exit 1
fi

# Create private directory if it doesn't exist
PRIVATE_DIR="/Dos/private/$USERNAME"
if [ ! -d "$PRIVATE_DIR" ]; then
  print_status "Creating private directory: $PRIVATE_DIR"
  if mkdir -p "$PRIVATE_DIR" && chown "$USERNAME:$USERNAME" "$PRIVATE_DIR" && chmod 700 "$PRIVATE_DIR"; then
    print_status "Private directory created and configured"
  else
    print_error "Failed to create/configure private directory"
    exit 1
  fi
else
  print_warning "Private directory already exists: $PRIVATE_DIR"
fi

# Test Samba configuration
print_status "Testing Samba configuration"
if testparm -s >/dev/null 2>&1; then
  print_status "Samba configuration is valid"
else
  print_warning "Samba configuration may have issues, please run 'testparm' manually"
fi

# Reload Samba
print_status "Reloading Samba services"
if systemctl reload smb; then
  print_status "Samba services reloaded"
  /
else
  print_warning "Failed to reload Samba services, you may need to restart manually"
fi

# Success message
echo
print_status "=== USER SETUP COMPLETE ==="
print_status "Username: $USERNAME"
print_status "Private share: \\\\$(hostname -I | awk '{print $1}')\\$USERNAME"
print_status "Shared folder: \\\\$(hostname -I | awk '{print $1}')\\shared"
print_status "Local private directory: $PRIVATE_DIR"
echo
print_warning "Note: User can now connect using their Samba password"
print_warning "The private directory will be automatically mounted when they connect"
