#! /bin/bash

echo "--------Kickstart 服务自动部署脚本----------"
echo '!注意，脚本中所有IP地址，请根据实际情况更改.---'
echo 'auther:qiankun-----------------------------'
echo '-------------------------------------------'
echo '-------------------------------------------'
echo '-------------------------------------------'
echo '-------------------------------------------'
echo '-------------------------------------------'
echo '-------------------------------------------'

echo '正在判断准备工作....'
# 判断网络状态
curl www.baidu.com  &> /dev/null
if [ $? -eq 0 ]
then
	echo ">>>>网络状态正常"
else
	echo "无法连接到intetnet!"
	exit
fi

# 判断selinux状态
Selinux=`getenforce`
if [ $Selinux == 'Disabled' ]
then
	echo ">>>>Selinux已关闭"
else
	echo "Selinux状态：$Selinux,正在关闭Selinux,完成后系统即将重启！"
	setforce 0
	init 6
fi

# 判断firewalld状态
Firewall=`systemctl status firewalld | grep active | awk '{print $2}'`
if [ $Firewall == 'active' ]
then
	echo "Firewalld状态：$Firewalld, 正在关闭Firewalld！"
else
	echo ">>>>Firewalld已关闭"
	systemctl stop firewalld
fi

#判断是否存在镜像光盘
lsblk | grep 'sr0' &> /dev/null
if [ $? -eq 0 ]
then
	echo ">>>>已识别镜像文件"
elif [ $? -eq 1 ]
then
	echo "请插入镜像光盘！"
fi

# 安装服务
echo "正在安装dhcp、tftp、http、syslinux服务，过程漫长.请稍后...."
yum install dhcp tftp-server syslinux httpd -y &> /dev/null
if [ $? -eq 0 ]
then
	echo '>>>>已安装dhcp、tftp-server、syslinux、httpd服务'
else
	echo '服务安装失败，请检查网络是否正常！'
fi

# 配置DHCP服务
if [ $? -eq 0 ]
then
	cat >/etc/dhcp/dhcpd.conf<<EOF
	subnet 192.168.70.0 netmask 255.255.255.0 {
	range 192.168.70.100 192.168.70.200;
	option subnet-mask 255.255.255.0;
	default-lease-time 21600;
	max-lease-time 43200;
	next-server 192.168.70.64;
	filename "/pxelinux.0";
	}
EOF
fi

if [ $? -eq 0 ]
then
	echo ">>>>已完成DHCP服务配置"
fi

# 修改tftp配置文件
sed -i 's/yes/no/g' /etc/xinetd.d/tftp
if [ $? -eq 0 ]
then
	echo ">>>>已修改TFTP配置文件"
fi

# 获取pxelinux.0系统文件
cd /var/lib/tftpboot/ && cp /usr/share/syslinux/pxelinux.0 .
if [ $? -eq 0 ]
then
	echo ">>>>已复制pxelinux.0系统文件到tftp目录"
fi

# 创建镜像挂在目录，并添加pxelinux.o配置文件，
DIR1="/var/www/html/CentOS7"
DIR2="/var/lib/tftpboot/pxelinux.cfg"
if [ ! -e $DIR1 ] && [ ! -e $DIR2 ]
then
	mkdir -p $DIR1
	mkdir -p $DIR2
else
	echo "目录已存在！"
fi

#挂载镜像并复制内核文件
mount /dev/sr0 $DIR1 &> /dev/null
cp -a /var/www/html/CentOS7/isolinux/* /var/lib/tftpboot/

# 修改启动配置文件default
file_default="/var/lib/tftpboot/pxelinux.cfg/default"
if [ ! -e $file_default ]
then
cp /var/www/html/CentOS7/isolinux/isolinux.cfg /var/lib/tftpboot/pxelinux.cfg/default
echo '>>>>已复制镜像默认启动文件default'
sed -i '1c default kickstarts' $file_default
sed -i '2c timeout 30' $file_default
cat >>$file_default<<EOF
label kickstarts
  menu label ^Install CentOS 7
  kernel vmlinuz
  append initrd=initrd.img ks=http://192.168.70.64/ks_config/ks.cfg  net.ifnames=0 biosdevname=0 ksdevice=eth0
EOF
	echo ">>>>已修改default启动文件"
fi

DIR3='/var/www/html/ks_config'
if [ ! -e $DIR3 ]
then
	mkdir - p /var/www/html/ks_config
cat >>$DIR3/ks.cfg<<EOF
install
text
url --url="http://192.168.70.64/CentOS7/"
lang zh_CN.UTF-8
keyboard --vckeymap=cn --xlayouts='cn'
bootloader --location=mbr --driveorder=sda --append="crashkernel=auto rhgb quiet" 

network  --bootproto=dhcp --device=eth0 --onboot=yes --ipv6=auto --no-activate
network  --hostname=localhost.localdomain
authconfig --enableshadow --passalgo=sha512
rootpw --iscrypted $6$ef98PzAjG1eZ1jgh$2g5j7q/kRNRskWViQ2WnAfjeOkVUas3jIu1NonjquUioywrBieLmzTODtM.MALToljp9Kj0nJeuNdbhbwrgnQ1
timezone Asia/Shanghai --isUtc
ignoredisk --only-use=sda
clearpart --all --initlabel --drives=sda
part /boot --fstype xfs --size=200
part swap --size=1024
part / --fstype xfs --size=1 --grow
firstboot --disable
selinux --disabled
firewall --disabled
logging --level=info
reboot

%packages
@^minimal
@core
chrony
kexec-tools
%end
EOF
echo ">>>>已定制ks.cfg文件"
fi
# 配置ks.cfg权限
chmod 777 $DIR3/ks.cfg

# 启动服务
systemctl start dhcpd
systemctl start tftp.socket
systemctl start httpd
echo '>>>>所有服务已重启，脚本执行完成！'