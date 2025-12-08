#!/bin/bash
# checkpoint_box_builder.sh
# Build Check Point R81.20 Vagrant boxes with custom IP configuration

set -e

BOX_NAME="checkpoint-r8120"
WORK_DIR="_tmp_cp_box"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/checkpoint_box_builder.log"
CONSOLE_LOG_FILE="${SCRIPT_DIR}/checkpoint_box_builder.console.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize log file
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_command() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] COMMAND: $*" >> "$LOG_FILE"
}

# Start new log
echo "========================================" > "$LOG_FILE"
echo "Check Point Box Builder Log" >> "$LOG_FILE"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "Command: $0 $*" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Function to display usage
show_usage() {
    cat << EOF
Usage: $(basename "$0") COMMAND [OPTIONS]

Commands:
  prepare     Prepare VM disk and ISO with custom IP configuration
  build       Build Vagrant box from configured disk
  auto        Prepare VM, boot it, wait for completion, then build box (all-in-one)
  help        Show this help message

Prepare options:
  --disk PATH    Path to original Check Point disk image
                 (default: ../cp_r81_20_disk.qcow2)

Build options:
  --disk PATH    Path to configured Check Point disk image
                 (auto-detected from ${WORK_DIR}/ if not specified)

Examples:
  $(basename "$0") prepare --disk ../original_checkpoint_r81_20_disk.qcow2
  $(basename "$0") build
  $(basename "$0") build --disk ${WORK_DIR}/cp_disk_10.194.58.200.qcow2
  $(basename "$0") auto --disk ../original_checkpoint_r81_20_disk.qcow2

EOF
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if ((i > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Function to extract IP from address for filename
ip_to_filename() {
    echo "$1" | tr '.' '_'
}

# Function: prepare
cmd_prepare() {
    local original_disk="../cp_r81_20_disk.qcow2"
    local auto_build=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --disk)
                original_disk="$2"
                shift 2
                ;;
            --auto-build)
                auto_build=true
                shift
                ;;
            *)
                echo -e "${RED}Error: Unknown option $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check if original disk exists
    if [[ ! -f "$original_disk" ]]; then
        echo -e "${RED}Error: Original disk not found: $original_disk${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Check Point R81.20 - VM Preparation                      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Prompt for box naming
    echo -e "${GREEN}Box Configuration${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Enter box name [checkpoint-r8120]: " box_base_name
    box_base_name=${box_base_name:-checkpoint-r8120}
    
    read -p "Enter box version (e.g., 81.20, 1.0.0) [81.20]: " box_version
    box_version=${box_version:-81.20}

    read -p "Enter box hostname (e.g., checkpoint-gw) [checkpoint-gw]: " box_hostname
    box_hostname=${box_hostname:-checkpoint-gw}

    echo ""
    
    # Prompt for network configuration
    echo -e "${GREEN}Network Configuration${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Enter IP address [10.194.58.200]: " ip_address
    ip_address=${ip_address:-10.194.58.200}
    
    while ! validate_ip "$ip_address"; do
        echo -e "${RED}Invalid IP address. Please try again.${NC}"
        read -p "Enter IP address: " ip_address
    done
    
    # Extract network portion for gateway default
    IFS='.' read -ra IP_PARTS <<< "$ip_address"
    default_gateway="${IP_PARTS[0]}.${IP_PARTS[1]}.${IP_PARTS[2]}.1"
    
    read -p "Enter netmask [255.255.255.0]: " netmask
    netmask=${netmask:-255.255.255.0}
    
    read -p "Enter gateway [$default_gateway]: " gateway
    gateway=${gateway:-$default_gateway}
    
    echo ""
    echo -e "${GREEN}Configuration Summary:${NC}"
    echo "  Box Name:   $box_base_name"
    echo "  Version:    $box_version"
    echo "  Hostname:   $box_hostname"
    echo "  IP Address: $ip_address"
    echo "  Netmask:    $netmask"
    echo "  Gateway:    $gateway"
    
    log_message "=== PREPARE: Box Configuration ==="
    log_message "Box Name: $box_base_name"
    log_message "Version: $box_version"
    log_message "Hostname: $box_hostname"
    log_message "=== PREPARE: Network Configuration ==="
    log_message "IP Address: $ip_address"
    log_message "Netmask: $netmask"
    log_message "Gateway: $gateway"
    
    echo ""
    read -p "Continue? [Y/n]: " confirm
    confirm=${confirm:-Y}
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    # Create work directory structure
    echo ""
    echo -e "${BLUE}Creating directory structure...${NC}"
    rm -rf "${WORK_DIR}"
    mkdir -p "${WORK_DIR}/file_structure/openstack/2015-10-15"
    
    # Generate user_data file
    echo -e "${BLUE}Generating user_data configuration...${NC}"
    cat > "${WORK_DIR}/file_structure/openstack/2015-10-15/user_data" << EOF
#cloud-config
#
# user-data file for Check Point R81.20
#
# For more information, see:
# - https://support.checkpoint.com/results/sk/sk179752
# - https://community.checkpoint.com/t5/General-Topics/Management-Interface-eth0-assigned-via-DHCP-cannot-remove-the/m-p/259712

# Set the hostname & admin password
hostname: ${box_hostname}
password: admin123

# Login banner (shown at login prompt)
banner: |
  Check Point CloudGuard Network Security
  This system is for authorized use only.

# Message of the day (shown after successful login)
motd: |
  ==================================================================
          Welcome to Check Point CloudGuard Network Security
  ==================================================================
  This is a LAB/TEST environment created for educational and
  testing purposes.
  
  Security Gateway and Security Management components are
  installed on this system, you can access both portals:
    - GAiA Portal GUI    : https://${ip_address}/
    - SmartConsole WebGUI: https://${ip_address}/smartconsole
  
  By using this product you agree to the terms and conditions
  as specified in https://www.checkpoint.com/download_agreement.html

  user_data version: 2025-10-29_auto-generated
  IP Configuration: ${ip_address}/${netmask} via ${gateway}
  ==================================================================


### Configure the network
network:
  version: 1
  config:
    - type: physical
      name: eth0
      subnets:
        - type: static
          address: ${ip_address}
          netmask: ${netmask}
          gateway: ${gateway}
          #dns_nameservers: [1.1.1.1, 8.8.8.8] ## Optional DNS servers - currently not used, default will be the same as gateway

# Run First Time Wizard in standalone mode (Security Gateway + Security Management)
# This will be executed on the first boot
runcmd:

  ### Run First Time Wizard configuration
  # maintenance_hash was generated with the password admin123
  # You can generate a new hash by using the command 'grub-mkpasswd-pbkdf2', before recreating the VM.
  - echo "RUNCMD> Running First Time Wizard configuration..."
  - |
    config_system -s "install_security_gw=true\
    &install_security_managment=true\
    &install_mgmt_primary=true\
    &mgmt_admin_radio=gaia_admin\
    &mgmt_gui_clients_radio=any\
    &maintenance_hash='grub.pbkdf2.sha512.10000.721029F548E36425A9E20E1454D0946E4A0C2ECE23250E6817C31556251C3F47BE7CE164114279E18C9D9783DCD2E3418C68AE0CD9007E437716195FC16CF005.EA75DE1D489B04E5EAEDB8010D60F4CE929F455E61B4EF9CB2E5E133BD974A2EEFC4F89EDD1A17CCDC448FDCDC711804FC04DB14E68CDCD70FA3881C0AB346E3'\
    &ftw_sic_key=aaaa\
    &primary=1.1.1.1\
    &timezone='Etc/GMT'\
    &upload_info=false\
    &upload_crash_data=false\
    &download_from_checkpoint_non_security=false\
    &download_info=false\
    &reboot_if_required=true" 2>&1 | tee /tmp/ftw_output.txt
    
    if grep -q "First time configuration was completed!" /tmp/ftw_output.txt; then
      echo "RUNCMD> First Time Wizard completed successfully, waiting for reboot..."
      sleep 60
    else
      echo "RUNCMD> First Time Wizard skipped (already installed or failed), continuing..."
    fi
    rm -f /tmp/ftw_output.txt

  ### Set expert password (non-interactive)
  - echo "RUNCMD> Setting expert password..."
  - |
    cat > /tmp/expert_pwd.txt << 'EOFPWD'
    admin123
    admin123
    EOFPWD
    clish -c "set expert-password" < /tmp/expert_pwd.txt
    rm /tmp/expert_pwd.txt

  ### Create user vagrant
  - echo "RUNCMD> Create user 'vagrant'..."
  - clish -c "set password-controls complexity 1"
  - clish -c "add user vagrant uid 2000 homedir /home/vagrant"
  - clish -c "add rba user vagrant roles adminRole"
  - clish -c "set user vagrant shell /bin/bash"
  - clish -c "set user vagrant newpass vagrant"
  - echo "RUNCMD> Configuring sudoers for user 'vagrant'..."
  - |
    cat >> /etc/sudoers << 'EOFSUDO'

    ## For vagrant box
    vagrant ALL=(ALL) NOPASSWD: ALL

    EOFSUDO

  ### Set up vagrant user for SSH access
  - echo "RUNCMD> Setting up SSH access for user 'vagrant'..."
  - |
    mkdir -p /home/vagrant/.ssh
    cat > /home/vagrant/.ssh/authorized_keys << 'EOFSSH'
    ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key
    EOFSSH
    chmod 700 /home/vagrant/.ssh
    chmod 600 /home/vagrant/.ssh/authorized_keys
    chown -R vagrant:users /home/vagrant/.ssh

  ### Enable DHCP client on eth0 to allow dynamic IP assignment (although it should be the IP configured statically above)
  - echo "RUNCMD> Enabling DHCP client on eth0..."
  - |
    clish -c "add dhcp client interface eth0"
    clish -c "save config"

  ### Device enters a time loop to avoid having to rebuild the VM every 14 days
  - echo "RUNCMD> Configuring time loop..."
  - |
    # Capture the creation date and day of week (this will be baked into the box)
    CREATION_DATE="\$(date '+%d %b %Y %H:%M:%S')"
    CREATION_DOW="\$(date '+%u')"
    
    # Set date at boot time via rc.local (always reset to creation date)
    cat >> /etc/rc.d/rc.local << EOFBOOT
    # Set Check Point date to box creation date at every boot
    /usr/bin/date -s "\${CREATION_DATE}" && /sbin/hwclock -w
    EOFBOOT
    chmod +x /etc/rc.d/rc.local
    
    # Create weekly cron job to reset date (every week on the same day as creation)
    cat > /etc/cron.d/reset-date << EOFTIME
    # Reset Check Point date to box creation date every week on the same day at 1:00 AM to avoid license expiration
    0 1 * * \${CREATION_DOW} root /usr/bin/date -s "\${CREATION_DATE}" && /sbin/hwclock -w
    EOFTIME
    chmod 644 /etc/cron.d/reset-date
    chown root:root /etc/cron.d/reset-date


  ### Configure API settings to accept calls from all IP addresses that can be used for GUI clients (with retry logic)
  - echo ""
  - echo "RUNCMD> Configure via mgmt_cli to accept API calls from all IP addresses that can be used for GUI clients... (>3min wait)"
  - |
    # Retry logic: attempt several times with 20-second waits (it takes at least 3 minutes to be able to login)
    MAX_RETRIES=10
    SLEEP_INTERVAL=20
    RETRY_COUNT=0
    SUCCESS=0
    
    while [ \$RETRY_COUNT -lt \$MAX_RETRIES ]; do
      echo "Attempt \$((RETRY_COUNT + 1)) of \$MAX_RETRIES..."
      
      # Try to login directly (API runs on port 443)
      SESSION_FILE=\$(mktemp)
      
      if mgmt_cli --port 443 -d "System Data" -r true login > "\${SESSION_FILE}" 2>&1; then
        echo "API login successful, configuring settings..."
        mgmt_cli --port 443 -s "\${SESSION_FILE}" set api-settings accepted-api-calls-from "All IP addresses that can be used for GUI clients"
        mgmt_cli --port 443 -s "\${SESSION_FILE}" publish
        mgmt_cli --port 443 -s "\${SESSION_FILE}" logout
        rm "\${SESSION_FILE}"
        echo "API configuration completed successfully"
        SUCCESS=1
        break
      else
        echo "API login failed. Error details:"
        cat "\${SESSION_FILE}"
        echo "---"
        rm -f "\${SESSION_FILE}"
      fi
      
      RETRY_COUNT=\$((RETRY_COUNT + 1))
      if [ \$RETRY_COUNT -lt \$MAX_RETRIES ]; then
        echo "Waiting \$SLEEP_INTERVAL seconds before retry..."
        sleep \$SLEEP_INTERVAL
      fi
    done
    
    if [ \$SUCCESS -eq 0 ]; then
      echo "WARNING: Failed to configure API settings after \$MAX_RETRIES attempts"
      echo "You may need to configure API settings manually via SmartConsole"
    fi
  

  # Final step: reboot due to First Time Wizard
  #- echo "RUNCMD> Rebooting system..."
  #- reboot
  # Final step: turn off the system, as it will be rebooted upon VM creation
#   - echo "RUNCMD> Shutting down system..."
#   - shutdown -h now
EOF
    
    # Generate ISO
    ip_filename=$(ip_to_filename "$ip_address")
    iso_name="cp_r81_20_config_${ip_filename}.iso"
    iso_path="${SCRIPT_DIR}/${iso_name}"
    
    echo -e "${BLUE}Generating ISO: ${iso_name}${NC}"
    genisoimage -r -V config-2 -o "${iso_path}" "${WORK_DIR}/file_structure/" > /dev/null 2>&1
    
    if [[ ! -f "${iso_path}" ]]; then
        echo -e "${RED}Error: Failed to create ISO${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ ISO created successfully${NC}"
    
    # Copy and resize disk
    disk_name="cp_disk_${ip_filename}.qcow2"
    disk_path="${WORK_DIR}/${disk_name}"
    
    # Save box name and version to a file for the build step
    echo "$box_base_name" > "${WORK_DIR}/.box_name"
    echo "$box_version" > "${WORK_DIR}/.box_version"
    
    echo -e "${BLUE}Copying original disk...${NC}"
    cp "$original_disk" "$disk_path"
    
    echo -e "${BLUE}Resizing disk to 100G...${NC}"
    qemu-img resize "$disk_path" 100G > /dev/null 2>&1
    
    echo -e "${GREEN}✓ Disk prepared successfully${NC}"
    echo ""
    
    # Display virt-install command
    vm_name="checkpoint-r8120-${ip_filename}"
    
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║   NEXT STEP: Boot the VM                                   ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Run the following command to start the VM:${NC}"
    echo ""
    cat << EOF
virt-install \\
  --name=${vm_name} \\
  --ram=8192 \\
  --vcpus=2 \\
  --disk path=${SCRIPT_DIR}/${disk_path},bus=ide,format=qcow2 \\
  --disk path=${iso_path},device=cdrom,readonly=on \\
  --network=network:default,model=virtio \\
  --graphics none \\
  --import
EOF
    echo ""
    
    if [[ "$auto_build" == false ]]; then
        echo -e "${YELLOW}Important:${NC}"
        echo "  1. The VM will boot and run the First Time Wizard (takes ~5-10 minutes)"
        echo "  2. Wait for the configuration to complete"
        echo "  3. Shut down the VM: virsh shutdown ${vm_name}"
        echo "  4. Once shut down, run: $(basename "$0") build"
        echo ""
        
        read -p "Do you want to run the virt-install command now? [y/N]: " run_now
        run_now=${run_now:-N}
    else
        # Auto mode: always run virt-install
        run_now="y"
    fi
    
    if [[ "$run_now" =~ ^[Yy]$ ]] || [[ "$auto_build" == true ]]; then
        echo ""
        echo -e "${BLUE}Starting VM...${NC}"
        log_message "=== Starting VM: ${vm_name} ==="
        log_message "Disk: ${SCRIPT_DIR}/${disk_path}"
        log_message "ISO: ${iso_path}"
        
        if [[ "$auto_build" == true ]]; then
            # In auto mode, use expect to automatically exit console when login prompt appears
            echo -e "${YELLOW}Auto mode: Will automatically exit console when login prompt appears${NC}"
            log_message "Auto mode: Using expect to detect login prompt"
            echo ""
            
            # Check if expect is available
            if ! command -v expect &> /dev/null; then
                echo -e "${RED}Error: 'expect' is not installed. Please install it:${NC}"
                echo "  sudo apt-get install expect"
                echo ""
                echo "Or run manually without auto mode."
                log_message "ERROR: expect is not installed"
                exit 1
            fi
            
            # Create expect script to watch for login prompt and log output
            expect_script=$(mktemp)
            console_log="${CONSOLE_LOG_FILE}"
            
            cat > "$expect_script" << EXPECTEOF
#!/usr/bin/expect -f
set timeout -1

# Open log file
log_file -a "${console_log}"

# Spawn virt-install
eval spawn [lrange \$argv 0 end]

# Watch for the login prompt
expect {
    "login:" {
        send_user "\n\n*** Login prompt detected! VM is ready. ***\n"
        send_user "*** Shutting down VM... ***\n\n"
        sleep 2
        # Send Ctrl+] to exit console
        send "\x1d"
        expect eof
    }
    timeout {
        send_user "\n\n*** Timeout waiting for login prompt ***\n"
        exit 1
    }
    eof {
        send_user "\n\n*** Console closed ***\n"
    }
}
EXPECTEOF
            
            chmod +x "$expect_script"
            
            log_command "expect virt-install --name=${vm_name} --ram=8192 --vcpus=2 --disk path=${SCRIPT_DIR}/${disk_path},bus=ide,format=qcow2 --disk path=${iso_path},device=cdrom,readonly=on --network=network:default,model=virtio --graphics none --import"
            log_message "Console output will be logged to: ${console_log}"
            
            # Run virt-install with expect
            "$expect_script" virt-install \
              --name="${vm_name}" \
              --ram=8192 \
              --vcpus=2 \
              --disk path="${SCRIPT_DIR}/${disk_path}",bus=ide,format=qcow2 \
              --disk path="${iso_path}",device=cdrom,readonly=on \
              --network=network:default,model=virtio \
              --graphics none \
              --import 2>&1 | tee -a "$LOG_FILE"
            
            rm -f "$expect_script"
            log_message "VM console session completed"
        else
            # Manual mode - just run virt-install normally with logging
            log_command "virt-install --name=${vm_name} --ram=8192 --vcpus=2 --disk path=${SCRIPT_DIR}/${disk_path},bus=ide,format=qcow2 --disk path=${iso_path},device=cdrom,readonly=on --network=network:default,model=virtio --graphics none --import"
            
            virt-install \
              --name="${vm_name}" \
              --ram=8192 \
              --vcpus=2 \
              --disk path="${SCRIPT_DIR}/${disk_path}",bus=ide,format=qcow2 \
              --disk path="${iso_path}",device=cdrom,readonly=on \
              --network=network:default,model=virtio \
              --graphics none \
              --import 2>&1 | tee -a "$LOG_FILE"
        fi
        
        # After VM exits (user pressed Ctrl+] or VM shutdown)
        echo ""
        echo -e "${GREEN}VM console closed.${NC}"
        log_message "VM console closed"
        
        if [[ "$auto_build" == true ]]; then
            echo ""
            echo -e "${YELLOW}Shutting down VM gracefully...${NC}"
            log_message "Shutting down VM: ${vm_name}"
            virsh shutdown "${vm_name}" 2>&1 | tee -a "$LOG_FILE" || true
            
            echo -e "${YELLOW}Waiting for VM to fully shut down...${NC}"
            log_message "Waiting for VM shutdown..."
            # Wait for VM to be in shut off state
            for i in {1..60}; do
                vm_state=$(virsh domstate "${vm_name}" 2>/dev/null || echo "unknown")
                if [[ "$vm_state" == "shut off" ]]; then
                    echo -e "${GREEN}✓ VM has shut down${NC}"
                    log_message "VM successfully shut down"
                    break
                fi
                if [[ $i -eq 60 ]]; then
                    echo -e "${RED}Warning: VM did not shut down automatically${NC}"
                    echo "Please manually shut it down: virsh shutdown ${vm_name}"
                    echo "Then run: $(basename "$0") build"
                    exit 1
                fi
                sleep 2
                echo -n "."
            done
            
            echo ""
            echo -e "${BLUE}Proceeding to build box...${NC}"
            sleep 2
            
            # Cleanup VM from virsh
            echo -e "${BLUE}Cleaning up VM definition...${NC}"
            log_message "Cleaning up VM definition: ${vm_name}"
            
            # Destroy if still running
            if virsh domstate "${vm_name}" 2>/dev/null | grep -q "running"; then
                log_message "VM still running, destroying..."
                virsh destroy "${vm_name}" 2>&1 | tee -a "$LOG_FILE" || true
            fi
            
            # Undefine the VM
            log_message "Undefining VM: ${vm_name}"
            virsh undefine "${vm_name}" 2>&1 | tee -a "$LOG_FILE" || true
            echo -e "${GREEN}✓ VM cleanup complete${NC}"
            
            # Call build function with the configured disk and auto-mode flag
            cmd_build --disk "${SCRIPT_DIR}/${disk_path}" --auto-mode
        else
            echo ""
            echo -e "${YELLOW}Next steps:${NC}"
            echo "  1. Wait for the VM to complete its configuration"
            echo "  2. Shut down the VM: virsh shutdown ${vm_name}"
            echo "  3. Run: $(basename "$0") build"
        fi
    else
        echo ""
        echo -e "${GREEN}Preparation complete!${NC}"
        echo "Run the virt-install command above when ready."
    fi
}

# Function: build
cmd_build() {
    local configured_disk=""
    local auto_mode=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --disk)
                configured_disk="$2"
                shift 2
                ;;
            --auto-mode)
                auto_mode=true
                shift
                ;;
            *)
                echo -e "${RED}Error: Unknown option $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Auto-detect disk if not provided
    if [[ -z "$configured_disk" ]]; then
        echo -e "${BLUE}Auto-detecting configured disk...${NC}"
        
        disk_files=("${WORK_DIR}"/cp_disk_*.qcow2)
        
        if [[ ${#disk_files[@]} -eq 0 ]] || [[ ! -f "${disk_files[0]}" ]]; then
            echo -e "${RED}Error: No configured disk found in ${WORK_DIR}/${NC}"
            echo "Please run 'prepare' first or specify --disk PATH"
            exit 1
        fi
        
        if [[ ${#disk_files[@]} -gt 1 ]]; then
            echo -e "${YELLOW}Multiple disks found:${NC}"
            for i in "${!disk_files[@]}"; do
                echo "  [$i] ${disk_files[$i]}"
            done
            read -p "Select disk number [0]: " disk_num
            disk_num=${disk_num:-0}
            configured_disk="${disk_files[$disk_num]}"
        else
            configured_disk="${disk_files[0]}"
        fi
    fi
    
    # Check if disk exists
    if [[ ! -f "$configured_disk" ]]; then
        echo -e "${RED}Error: Disk not found: $configured_disk${NC}"
        exit 1
    fi
    
    # Read box name and version from saved files (if they exist)
    if [[ -f "${WORK_DIR}/.box_name" ]]; then
        box_base_name=$(cat "${WORK_DIR}/.box_name")
    else
        box_base_name="${BOX_NAME}"
    fi
    
    if [[ -f "${WORK_DIR}/.box_version" ]]; then
        box_version=$(cat "${WORK_DIR}/.box_version")
    else
        # Fallback: use IP as version if not specified
        box_version=""
    fi
    
    # Extract IP from disk filename
    disk_basename=$(basename "$configured_disk")
    ip_filename=$(echo "$disk_basename" | sed 's/cp_disk_\(.*\)\.qcow2/\1/')
    ## NOT SURE THE ISO PART IS NEEDED ANYMORE - testing without it
    # iso_name="cp_r81_20_config_${ip_filename}.iso"
    # iso_path="${SCRIPT_DIR}/${iso_name}"
    # if [[ ! -f "$iso_path" ]]; then
    #     echo -e "${RED}Error: Matching ISO not found: $iso_path${NC}"
    #     exit 1
    # fi
    
    # Sanitize box name for filename (replace / with -)
    box_name_safe=$(echo "$box_base_name" | tr '/' '-')
    
    # Set box name with IP address
    box_name="${box_name_safe}_${ip_filename}.box"
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Check Point R81.20 - Box Builder                         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Configuration:${NC}"
    echo "  Box Name:   $box_base_name"
    echo "  Version:    $box_version"
    echo "  Disk:       $configured_disk"
    # echo "  ISO:        $iso_path"
    echo "  Output:     ${box_name}"
    echo ""
    
    log_message "=== BUILD: Starting box creation ==="
    log_message "Box Name: $box_base_name"
    log_message "Version: $box_version"
    log_message "Disk: $configured_disk"
    # log_message "ISO: $iso_path"
    log_message "Box: ${box_name}"
    
    if [[ "$auto_mode" == false ]]; then
        read -p "Continue? [Y/n]: " confirm
        confirm=${confirm:-Y}
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi
    
    # Create box directory
    box_dir="${WORK_DIR}/box_build"
    echo ""
    echo -e "${BLUE}Creating box structure...${NC}"
    rm -rf "$box_dir"
    mkdir -p "$box_dir"
    
    # Copy disk as box.img
    echo -e "${BLUE}Copying configured disk...${NC}"
    cp "$configured_disk" "$box_dir/box.img"
    
    # Copy ISO -- NOT SURE IT'S NEEDED, let's try to remove it
    # echo -e "${BLUE}Copying ISO...${NC}"
    # cp "$iso_path" "$box_dir/"
    
    # Create metadata.json
    echo -e "${BLUE}Creating metadata.json...${NC}"
    cat > "$box_dir/metadata.json" << 'EOF'
{
  "provider": "libvirt",
  "format": "qcow2",
  "virtual_size": 100
}
EOF
    
    # Create Vagrantfile
    echo -e "${BLUE}Creating Vagrantfile...${NC}"
    cat > "$box_dir/Vagrantfile" << 'EOF'
Vagrant.configure("2") do |config|
    config.vm.provider :libvirt do |libvirt|
        libvirt.driver = "kvm"
    end

    config.vm.boot_timeout = 300
    config.vm.communicator = 'ssh'
    config.vm.synced_folder ".", "/vagrant", disabled: true
    config.vm.allow_fstab_modification = false
    config.vm.allow_hosts_modification = false
    config.vm.guest = "redhat" # to avoid auto-detection

    config.ssh.shell = "bash"
    config.ssh.sudo_command = ""
    config.ssh.username = "vagrant"
    config.ssh.password = "vagrant"
    config.ssh.insert_key = false

    config.vm.provider :libvirt do |lv|
        lv.memory = 8192
        lv.cpus = 2
    end
end

EOF
    
    # Package the box
    echo -e "${BLUE}Packaging box...${NC}"
    log_message "Packaging box: ${box_name}"
    log_command "cd ${box_dir} && tar czf ${SCRIPT_DIR}/${box_name} ./*"
    (cd "$box_dir" && tar czf "${SCRIPT_DIR}/${box_name}" ./*)
    
    if [[ ! -f "${SCRIPT_DIR}/${box_name}" ]]; then
        echo -e "${RED}Error: Failed to create box${NC}"
        log_message "ERROR: Failed to create box"
        exit 1
    fi
    
    log_message "Box created successfully: ${SCRIPT_DIR}/${box_name}"
    
    # Create metadata.json for proper versioning
    # Convert IP filename back to dotted notation for version
    ip_version=$(echo "$ip_filename" | tr '_' '.')
    metadata_file="${SCRIPT_DIR}/${box_name_safe}_${ip_filename}_metadata.json"
    
    echo -e "${BLUE}Creating metadata file for versioning...${NC}"
    log_message "Creating metadata file: ${metadata_file}"
    
    cat > "$metadata_file" << EOF
{
  "name": "${box_base_name}",
  "description": "Check Point R81.20 Security Gateway with IP ${ip_version}",
  "versions": [
    {
      "version": "${box_version}",
      "providers": [
        {
          "name": "libvirt",
          "url": "file://${SCRIPT_DIR}/${box_name}"
        }
      ]
    }
  ]
}
EOF
    
    log_message "Metadata file created: ${metadata_file}"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✓ Box created successfully!                              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Box location:${NC} ${SCRIPT_DIR}/${box_name}"
    echo -e "${GREEN}Metadata:${NC}     ${metadata_file}"
    echo ""
    echo -e "${YELLOW}To add this box to Vagrant:${NC}"
    echo ""
    echo "  vagrant box add ${metadata_file}"
    echo ""
    echo -e "${GREEN}This will add the box as '${box_base_name}' with version '${box_version}'${NC}"
    echo ""
    echo -e "${GREEN}Alternative (without metadata):${NC}"
    echo ""
    echo "  vagrant box add ${box_base_name} ${SCRIPT_DIR}/${box_name}"
    echo ""
    
    # Ask about cleanup
    if [[ "$auto_mode" == false ]]; then
        read -p "Do you want to clean up temporary files in ${WORK_DIR}? [y/N]: " cleanup
        cleanup=${cleanup:-N}
    else
        # Auto mode: always clean up
        cleanup="y"
        echo -e "${YELLOW}Auto mode: Cleaning up temporary files...${NC}"
    fi
    
    if [[ "$cleanup" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Cleaning up...${NC}"
        log_message "Cleaning up temporary files: ${WORK_DIR}"
        rm -rf "${WORK_DIR}" || true
        echo -e "${GREEN}✓ Cleanup complete${NC}"
        log_message "Cleanup complete"
    else
        echo -e "${YELLOW}Temporary files kept in ${WORK_DIR}/${NC}"
        log_message "Temporary files kept in: ${WORK_DIR}"
    fi
    
    log_message "=== BUILD: Completed successfully ==="
    log_message "Log file: ${LOG_FILE}"
    echo ""
    echo -e "${YELLOW}Full log available at: ${LOG_FILE}${NC}"
    
    # Explicit exit to prevent any fall-through
    exit 0
}

# Function: auto (prepare + build)
cmd_auto() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Check Point R81.20 - Automated Box Creation              ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}This will:${NC}"
    echo "  1. Prepare the VM disk and ISO with your IP configuration"
    echo "  2. Start the VM for first-time configuration"
    echo "  3. VM will be shutdown automatically after configuration"
    echo "  4. Build the Vagrant box"
    echo ""
    read -p "Continue? [Y/n]: " confirm
    confirm=${confirm:-Y}
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    # Call prepare with auto-build flag
    cmd_prepare --auto-build "$@"
}

# Main script logic
case "${1:-}" in
    prepare)
        shift
        cmd_prepare "$@"
        ;;
    build)
        shift
        cmd_build "$@"
        ;;
    auto)
        shift
        cmd_auto "$@"
        ;;
    help|--help|-h)
        show_usage
        ;;
    "")
        echo -e "${RED}Error: No command specified${NC}"
        echo ""
        show_usage
        exit 1
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$1'${NC}"
        echo ""
        show_usage
        exit 1
        ;;
esac

