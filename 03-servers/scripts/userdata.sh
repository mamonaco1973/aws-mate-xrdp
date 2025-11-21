#!/bin/bash

# =================================================================================
# Active Directory Integration & EFS File Server Bootstrap Script
# =================================================================================
# Purpose:
#   - Install and configure required components for domain-joined Linux instances
#   - Register with AWS SSM Agent for remote management
#   - Mount Amazon EFS volumes for home and shared directories
#   - Join the host to Active Directory using Samba/SSSD/Winbind
#   - Configure Samba for file services integrated with AD
#   - Apply security, sudo, and directory permission policies
#
# Notes:
#   - Intended for Ubuntu-based systems (tested on 22.04/24.04 LTS)
#   - Requires IAM role/instance profile with Secrets Manager + SSM permissions
#   - Expects variables like ${efs_mnt_server}, ${domain_fqdn}, ${realm},
#     ${netbios}, ${force_group}, and ${admin_secret} to be passed in at runtime
#
# =================================================================================

# ---------------------------------------------------------------------------------
# Section 0: Ensure AWS SSM Agent is Installed and Running
# ---------------------------------------------------------------------------------
# The Amazon SSM Agent allows remote management, patching, and automation.
# Installing via snap ensures the latest version is available.
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

# ---------------------------------------------------------------------------------
# Section 1: Update OS and Install Required Packages
# ---------------------------------------------------------------------------------
# Refresh package metadata
apt-get update -y

# Prevent interactive prompts during package installs
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------------
# Section 2: Mount Amazon EFS File System
# ---------------------------------------------------------------------------------
# Prepare mount points for shared storage (/efs, /home, /data)
mkdir -p /efs
echo "${efs_mnt_server}:/ /efs   efs   _netdev,tls  0 0" | sudo tee -a /etc/fstab
systemctl daemon-reload
mount /efs

mkdir -p /efs/home
mkdir -p /efs/data
echo "${efs_mnt_server}:/home /home  efs   _netdev,tls  0 0" | sudo tee -a /etc/fstab
systemctl daemon-reload
mount /home

# ---------------------------------------------------------------------------------
# Section 3: Join Active Directory Domain
# ---------------------------------------------------------------------------------
# Retrieve AD admin credentials securely from AWS Secrets Manager
secretValue=$(aws secretsmanager get-secret-value --secret-id ${admin_secret} \
    --query SecretString --output text)
admin_password=$(echo $secretValue | jq -r '.password')
admin_username=$(echo $secretValue | jq -r '.username' | sed 's/.*\\//')

# Perform AD join with Samba as membership software (logs to /tmp/join.log)
echo -e "$admin_password" | sudo /usr/sbin/realm join --membership-software=samba \
    -U "$admin_username" ${domain_fqdn} --verbose >> /tmp/join.log 2>&1

# ---------------------------------------------------------------------------------
# Section 4: Enable Password Authentication for AD Users
# ---------------------------------------------------------------------------------
# Update SSHD configuration to allow password-based logins (required for AD users)
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' \
    /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

# ---------------------------------------------------------------------------------
# Section 5: Configure SSSD for AD Integration
# ---------------------------------------------------------------------------------
# Adjust SSSD settings for simplified user experience:
#   - Use short usernames instead of user@domain
#   - Disable ID mapping to respect AD-assigned UIDs/GIDs
#   - Adjust fallback homedir format
sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' \
    /etc/sssd/sssd.conf
sudo sed -i 's/ldap_id_mapping = True/ldap_id_mapping = False/g' \
    /etc/sssd/sssd.conf
sudo sed -i 's|fallback_homedir = /home/%u@%d|fallback_homedir = /home/%u|' \
    /etc/sssd/sssd.conf
sudo sed -i \
  -e 's/^access_provider *= *.*/access_provider = simple/' \
  /etc/sssd/sssd.conf
  
# Prevent XAuthority warnings for new AD users
touch /etc/skel/.Xauthority
chmod 600 /etc/skel/.Xauthority

# Enable automatic home directory creation and restart services
sudo pam-auth-update --enable mkhomedir
sudo systemctl restart ssh

# ---------------------------------------------------------------------------------
# Section 6: Configure Samba File Server
# ---------------------------------------------------------------------------------
# Stop SSSD temporarily to allow Samba configuration updates
sudo systemctl stop sssd

# Write Samba configuration file (smb.conf) with AD + Winbind integration
cat <<EOT > /tmp/smb.conf
[global]
workgroup = ${netbios}
security = ads

# Performance tuning
strict sync = no
sync always = no
aio read size = 1
aio write size = 1
use sendfile = yes

passdb backend = tdbsam

# Printing subsystem (legacy, usually unused in cloud)
printing = cups
printcap name = cups
load printers = yes
cups options = raw

kerberos method = secrets and keytab

# Default user template
template homedir = /home/%U
template shell = /bin/bash
#netbios 

# File creation masks
create mask = 0770
force create mode = 0770
directory mask = 0770
force group = ${force_group}

realm = ${realm}

# ID mapping configuration
idmap config ${realm} : backend = sss
idmap config ${realm} : range = 10000-1999999999
idmap config * : backend = tdb
idmap config * : range = 1-9999

# Winbind options
min domain uid = 0
winbind use default domain = yes
winbind normalize names = yes
winbind refresh tickets = yes
winbind offline logon = yes
winbind enum groups = yes
winbind enum users = yes
winbind cache time = 30
idmap cache time = 60
winbind negative cache time = 0

[homes]
comment = Home Directories
browseable = No
read only = No
inherit acls = Yes

[efs]
comment = Mounted EFS area
path = /efs
read only = no
guest ok = no
EOT

# Deploy Samba configuration
sudo cp /tmp/smb.conf /etc/samba/smb.conf
sudo rm /tmp/smb.conf

# Insert NetBIOS hostname dynamically
head /etc/hostname -c 15 > /tmp/netbios-name
value=$(</tmp/netbios-name)
value=$(echo "$value" | tr -d '-' | tr '[:lower:]' '[:upper:]')
export netbios="$${value^^}"
sudo sed -i "s/#netbios/netbios name=$netbios/g" /etc/samba/smb.conf

# Update NSSwitch configuration for Winbind integration
cat <<EOT > /tmp/nsswitch.conf
passwd:     files sss winbind
group:      files sss winbind
automount:  files sss winbind
shadow:     files sss winbind
hosts:      files dns myhostname
bootparams: nisplus [NOTFOUND=return] files
ethers:     files
netmasks:   files
networks:   files
protocols:  files
rpc:        files
services:   files sss
netgroup:   files sss
publickey:  nisplus
aliases:    files nisplus
EOT

sudo cp /tmp/nsswitch.conf /etc/nsswitch.conf
sudo rm /tmp/nsswitch.conf

# Restart Samba-related services
sudo systemctl restart winbind smb nmb sssd

# ---------------------------------------------------------------------------------
# Section 7: Grant Sudo Privileges to AD Admin Group
# ---------------------------------------------------------------------------------
# Members of "linux-admins" AD group get passwordless sudo access
echo "%linux-admins ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/10-linux-admins

# ---------------------------------------------------------------------------------
# Section 8: Enforce Home Directory Permissions
# ---------------------------------------------------------------------------------
# Force new home directories to have mode 0700 (private)
sudo sed -i 's/^\(\s*HOME_MODE\s*\)[0-9]\+/\10700/' /etc/login.defs

# Trigger home directory creation for specific test accounts

su -c "exit" rpatel
su -c "exit" jsmith
su -c "exit" akumar
su -c "exit" edavis

# Set EFS directory ownership and permissions
chgrp mcloud-users /efs
chgrp mcloud-users /efs/data
chmod 770 /efs
chmod 770 /efs/data
chmod 700 /home/*

cd /efs
git clone https://github.com/mamonaco1973/aws-xubuntu-xrdp.git
chmod -R 775 aws-xubuntu-xrdp
chgrp -R mcloud-users aws-xubuntu-xrdp

# =================================================================================
# End of Script
# =================================================================================
