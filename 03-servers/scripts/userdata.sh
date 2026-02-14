#!/bin/bash

# Active Directory + EFS bootstrap for Ubuntu.
# - Installs and starts SSM agent.
# - Mounts EFS (/efs and /home).
# - Joins Active Directory (realm join using Samba).
# - Updates SSH/SSSD defaults for AD users.
# - Configures Samba + Winbind.
# - Applies sudo and permissions, then clones helper repos.

# Section 0: Ensure AWS SSM Agent is installed and running.
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

# Section 1: Update OS and install required packages.
apt-get update -y
export DEBIAN_FRONTEND=noninteractive

# Section 2: Mount Amazon EFS file system.
mkdir -p /efs
echo "${efs_mnt_server}:/ /efs   efs   _netdev,tls  0 0" | sudo tee -a /etc/fstab
systemctl daemon-reload
mount /efs

mkdir -p /efs/home
mkdir -p /efs/data
echo "${efs_mnt_server}:/home /home  efs   _netdev,tls  0 0" | sudo tee -a /etc/fstab
systemctl daemon-reload
mount /home

# Section 3: Join Active Directory domain.
secretValue=$(aws secretsmanager get-secret-value --secret-id ${admin_secret} \
    --query SecretString --output text)
admin_password=$(echo $secretValue | jq -r '.password')
admin_username=$(echo $secretValue | jq -r '.username' | sed 's/.*\\//')

echo -e "$admin_password" | sudo /usr/sbin/realm join --membership-software=samba \
    -U "$admin_username" ${domain_fqdn} --verbose

# Section 4: Enable password authentication for AD users.
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' \
    /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

# Section 5: Configure SSSD for AD integration.
sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' \
    /etc/sssd/sssd.conf
sudo sed -i 's/ldap_id_mapping = True/ldap_id_mapping = False/g' \
    /etc/sssd/sssd.conf
sudo sed -i 's|fallback_homedir = /home/%u@%d|fallback_homedir = /home/%u|' \
    /etc/sssd/sssd.conf
sudo sed -i \
  -e 's/^access_provider *= *.*/access_provider = simple/' \
  /etc/sssd/sssd.conf
  
touch /etc/skel/.Xauthority
chmod 600 /etc/skel/.Xauthority

sudo pam-auth-update --enable mkhomedir
sudo systemctl restart ssh

# Section 6: Configure Samba file server.
sudo systemctl stop sssd

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

sudo cp /tmp/smb.conf /etc/samba/smb.conf
sudo rm /tmp/smb.conf

head /etc/hostname -c 15 > /tmp/netbios-name
value=$(</tmp/netbios-name)
value=$(echo "$value" | tr -d '-' | tr '[:lower:]' '[:upper:]')
export netbios="$${value^^}"
sudo sed -i "s/#netbios/netbios name=$netbios/g" /etc/samba/smb.conf

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

sudo systemctl restart winbind smb nmb sssd

# Section 7: Grant sudo privileges to AD admin group.
echo "%linux-admins ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/10-linux-admins

# Section 8: Enforce home directory permissions and seed test users.
sudo sed -i 's/^\(\s*HOME_MODE\s*\)[0-9]\+/\10700/' /etc/login.defs

su -c "exit" rpatel
su -c "exit" jsmith
su -c "exit" akumar
su -c "exit" edavis

chgrp mcloud-users /efs
chgrp mcloud-users /efs/data
chmod 770 /efs
chmod 770 /efs/data
chmod 700 /home/*

cd /efs
git clone https://github.com/mamonaco1973/aws-mate-xrdp.git
chmod -R 775 aws-mate-xrdp
chgrp -R mcloud-users aws-mate-xrdp

git clone https://github.com/mamonaco1973/aws-setup.git
chmod -R 775 aws-setup
chgrp -R mcloud-users aws-setup

git clone https://github.com/mamonaco1973/azure-setup.git
chmod -R 775 azure-setup
chgrp -R mcloud-users azure-setup

git clone https://github.com/mamonaco1973/gcp-setup.git
chmod -R 775 gcp-setup
chgrp -R mcloud-users gcp-setup
