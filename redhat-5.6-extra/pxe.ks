# Kickstart file automatically generated by anaconda.

install
url --url http://192.168.1.2:8091/ubuntu_dvd
key --skip
lang en_US.UTF-8
keyboard us
text
# network --bootproto=dhcp
# crowbar
rootpw --iscrypted $1$H6F/NLec$Fps2Ut0zY4MjJtsa1O2yk0
firewall --disabled
authconfig --enableshadow --enablemd5
selinux --disabled
timezone --utc Europe/London
bootloader --location=mbr --driveorder=sda
zerombr yes
ignoredisk --drives=sdb,sdc,sdd,sde,sdf,sdg,sdh,sdi,sdj,sdk,sdl,sdm,sdn,sdo,sdp,sdq,sdr,sds,sdt,sdu,sdv,sdw,sdx,sdy,sdz,hdb,hdc,hdd,hde,hdf,hdg,hdh,hdi,hdj,hdk,hdl,hdm,hdn,hdo,hdp,hdq,hdr,hds,hdt,hdu,hdv,hdw,hdx,hdy,hdz
clearpart --all --drives=sda
part /boot --fstype ext3 --size=100 --ondisk=sda
part swap --recommended
part pv.6 --size=0 --grow --ondisk=sda
volgroup lv_admin --pesize=32768 pv.6
logvol / --fstype ext3 --name=lv_root --vgname=lv_admin --size=1 --grow
reboot

%packages

@base
@core
@editors
@text-internet
keyutils
trousers
fipscheck
device-mapper-multipath
OpenIPMI
OpenIPMI-tools
emacs-nox
openssh
createrepo

%post

export PS4='${BASH_SOURCE}@${LINENO}(${FUNCNAME[0]}): '
exec > /root/post-install.log 2>&1

BASEDIR="/tftpboot/redhat_dvd"
# copy the install image.
mkdir -p "$BASEDIR"
(   cd "$BASEDIR"
    while ! wget -q http://192.168.1.2:8091/files.list; do sleep 1; done
    while read f; do
	wget -a /root/post-install-wget.log -x -nH --cut-dirs=1 \
	    "http://192.168.1.2:8091/${f#./}"
    done < files.list
    rm files.list
)
cat <<EOF >/etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
BOOTPROTO=none
ONBOOT=yes
NETMASK=255.255.255.0
IPADDR=192.168.124.10
GATEWAY=192.168.124.1
TYPE=Ethernet
EOF
(cd /etc/yum.repos.d && rm *)
    
cat >/etc/yum.repos.d/RHEL5.6-Base.repo <<EOF
[RHEL56-Base]
name=RHEL 5.6 Server
baseurl=file://$BASEDIR/Server
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF
    
cat >/etc/yum.repos.d/crowbar-xtras.repo <<EOF
[crowbar-xtras]
name=Crowbar Extra Packages
baseurl=file://$BASEDIR/extra/pkgs
gpgcheck=0
EOF

# Create the repo metadata we will need
(cd /tftpboot/redhat_dvd/extra/pkgs; createrepo -d -q .)

# We prefer rsyslog.
yum -y install rsyslog
chkconfig syslog off
chkconfig rsyslog on

# Make sure rsyslog picks up our stuff
echo '$IncludeConfig /etc/rsyslog.d/*.conf' >>/etc/rsyslog.conf

# Make runlevel 3 the default
sed -i -e '/^id/ s/5/3/' /etc/inittab

mdcp() {
    local dest="$1"
    shift
    mkdir -p "$dest"
    cp "$@" "$dest"
}

finishing_scripts="update_hostname.sh barclamp_install.rb parse_node_data"
(
    cd "$BASEDIR/dell"
    mdcp /opt/dell/bin $finishing_scripts
)
# Install h2n for named management
( 
    cd /opt/dell/; 
    tar -zxf /tftpboot/redhat_dvd/extra/h2n.tar.gz
)
ln -s /opt/dell/h2n-2.56/h2n /opt/dell/bin/h2n    
    
mdcp /opt/dell -r "$BASEDIR/dell/crowbar_framework" 

# Make a destination for switch configs
mdcp /opt/dell/switch "$BASEDIR/dell/"*.stk

# put the chef files in place
mdcp /opt/dell -r "$BASEDIR/dell/chef"
mdcp /etc/rsyslog.d "$BASEDIR/dell/rsyslog.d/"*

# Barclamp preparation (put them in the right places)
mkdir /opt/dell/barclamps
cd barclamps
for i in *; do
  [[ -d $i ]] || continue
  if [ -e $i/crowbar.yml ]; then
    # MODULAR FORMAT copy to right location (installed by rake barclamp:install)
    cp -r $i /opt/dell/barclamps
    echo "copy new format $i"
  else
    echo "WARNING: item $i found in barclamp directory, but it is not a barclamp!"
  fi
done
cd ..
 
# Make sure the bin directory is executable
chmod +x /opt/dell/bin/*
    
#
# Make sure the permissions are right
# Copy from a cd so that means most things are read-only which is fine, 
# except for these.
#
chmod 755 /opt/dell/chef/data_bags/crowbar
chmod 644 /opt/dell/chef/data_bags/crowbar/*
chmod 755 /opt/dell/crowbar_framework/db
chmod 644 /opt/dell/crowbar_framework/db/*
chmod 755 /opt/dell/crowbar_framework/tmp
chmod -R +w /opt/dell/crowbar_framework/tmp/*
chmod 755 /opt/dell/crowbar_framework/public/stylesheets
chmod 755 "$BASEDIR/extra/"*.sh "$BASEDIR/extra/install"
chmod 755 "$BASEDIR/updates/"*
    
    
# Look for any crowbar specific kernel parameters
for s in $(cat /proc/cmdline); do
    VAL=${s#*=} # everything after the first =
    case ${s%%=*} in # everything before the first =
	crowbar.hostname) CHOSTNAME=$VAL;;
	crowbar.url) CURL=$VAL;;
	crowbar.use_serial_console) 
	    sed -i "s/\"use_serial_console\": .*,/\"use_serial_console\": $VAL,/" /opt/dell/chef/data_bags/crowbar/bc-template-provisioner.json;;
	crowbar.debug.logdest) 
	    echo "*.*    $VAL" >> /etc/rsyslog.d/00-crowbar-debug.conf
	    mkdir -p "$BASEDIR/rsyslog.d"
	    echo "*.*    $VAL" >> "$BASEDIR/rsyslog.d/00-crowbar-debug.conf"
	    ;;
	crowbar.authkey)
	    mkdir -p "/root/.ssh"
	    printf "$VAL\n" >>/root/.ssh/authorized_keys
	    cp /root/.ssh/authorized_keys "$BASEDIR/authorized_keys"
	    ;;
	crowbar.debug)
	    sed -i -e '/config.log_level/ s/^#//' \
		-e '/config.logger.level/ s/^#//' \
		/opt/dell/crowbar_framework/config/environments/production.rb
	    ;;
    esac
done
    
if [[ $CHOSTNAME ]]; then
    
    cat > /install_system.sh <<EOF
#!/bin/bash
set -e
cd /tftpboot/redhat_dvd/extra
./install $CHOSTNAME

rm -f /etc/rc2.d/S99install
rm -f /etc/rc3.d/S99install
rm -f /etc/rc5.d/S99install

rm -f /install_system.sh

EOF
	
    chmod +x /install_system.sh
    ln -s /install_system.sh /etc/rc3.d/S99install
    ln -s /install_system.sh /etc/rc5.d/S99install
    ln -s /install_system.sh /etc/rc2.d/S99install
fi