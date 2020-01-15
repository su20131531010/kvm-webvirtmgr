#!/bin/bash
#########################
#部署WebVirtMgr
#########################

install_kvm(){
	#检查CPU是否支持虚拟化
	egrep '(vmx|svm)' /proc/cpuinfo >/dev/null
	if [[ "$?" != "0" ]]; then
		echo -e "\n平台不支持虚拟化,检查后重试"
		exit
	fi

	#关闭Selinux
	sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
	setenforce 0

	#关闭firewalld
	systemctl stop firewalld
	systemctl disable firewalld

	#安装KVM及管理组件
	yum -y install kvm python-virtinst libvirt tunctl bridge-utils virt-manager 
	yum -y install qemu-kvm-tools virt-viewer virt-v2v virt-install libguestfs-tools

	#重启服务并设置开自启
	systemctl restart libvirtd

	#创建软链接
	ln -s /usr/libexec/qemu-kvm /usr/bin/qemu-kvm
}

install_web(){
	#检测相关安装文件是否存在
	if [[ ! -e ./webvirtmgr-master.zip ]]; then
		echo -e "\nMissing file: webvirtmgr-master.zip"
		exit
	elif [[ ! -e ./Django-1.5.5.tar.gz ]]; then
		echo -e "\nMissing file: Django-1.5.5.tar.gz"
		exit
	elif [[ ! -e ./gunicorn-19.5.0-py2.py3-none-any.whl ]]; then
		echo -e "\nMissing file: gunicorn-19.5.0-py2.py3-none-any.whl"
		exit
	elif [[ ! -e ./lockfile-0.12.2-py2.py3-none-any.whl ]]; then
		echo -e "\nMissing file: lockfile-0.12.2-py2.py3-none-any.whl"
		exit
	fi

	#安装WebVirtMgr环境 安装文件提前放好,所以不需要git
	yum -y install python-pip libvirt-python libxml2-python unzip
	yum -y install python-websockify supervisor nginx gcc python-devel

	# 暂时不安装
	# pip install numpy
	
	#解压路径为当前路径,所以文件一定要放在同一个目录
	unzip ./webvirtmgr-master.zip
	mv webvirtmgr-master /usr/local/src/webvirtmgr

	#在线安装Django
	#pip install -r /usr/local/src/webvirtmgr/requirements.txt

	#本地安装Django
	pip install ./Django-1.5.5.tar.gz
	pip install ./gunicorn-19.5.0-py2.py3-none-any.whl
	pip install ./lockfile-0.12.2-py2.py3-none-any.whl

	#设置管理用户
	/usr/local/src/webvirtmgr/manage.py syncdb
	/usr/local/src/webvirtmgr/manage.py collectstatic

	#调用生成配置文件函数
	config

	#在var目录下创建WebVirtMgr目录
	mkdir -pv /var/www/
	mv /usr/local/src/webvirtmgr /var/www/
	chown -R nginx:nginx /var/www/webvirtmgr/

	#权限设置，设置为Local登录(SSH可能无法正常使用)
	groupadd libvirtd
	usermod -a -G libvirtd root
	usermod -a -G libvirtd nginx

	sed -i 's/#unix_sock_group = "libvirt"/unix_sock_group = "libvirt"/' /etc/libvirt/libvirtd.conf

	systemctl enable libvirtd supervisord nginx
	systemctl restart libvirtd supervisord nginx
}

config(){
	cat <<EOF > /etc/nginx/conf.d/webvirtmgr.conf
server {
    listen 8100;

    server_name \$hostname;
    #access_log /var/log/nginx/webvirtmgr_access_log;

    location /static/ {
        root /var/www/webvirtmgr/webvirtmgr; # or /srv instead of /var
        expires max;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-for \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host:\$server_port;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 600;
        proxy_read_timeout 600;
        proxy_send_timeout 600;
        client_max_body_size 1024M; # Set higher depending on your needs
    }
}
EOF

	cat <<EOF > /etc/supervisord.d/webvirtmgr.ini
[program:webvirtmgr]
command=/usr/bin/python /var/www/webvirtmgr/manage.py run_gunicorn -c /var/www/webvirtmgr/conf/gunicorn.conf.py
directory=/var/www/webvirtmgr
autostart=true
autorestart=true
logfile=/var/log/supervisor/webvirtmgr.log
log_stderr=true
user=nginx

[program:webvirtmgr-console]
command=/usr/bin/python /var/www/webvirtmgr/console/webvirtmgr-console
directory=/var/www/webvirtmgr
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/webvirtmgr-console.log
redirect_stderr=true
user=nginx
EOF

	cat <<EOF > /etc/polkit-1/localauthority/50-local.d/50-org.libvirtd-group-access.pkla
[bvirtd group Management Access]
Identity=unix-group:libvirtd
Action=org.libvirt.unix.manage
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
}

echo "###############################"
echo "####KVM/WebVirtMgr部署脚本####"
echo "###############################"
echo "1.安装KVM"
echo "2.安装KVM及WebVirtMgr"
echo "3.创建Bridge网络"
echo -e "\n"
echo "请确保你有足够快的MIRRORS和正确的EPEL"
read -p "输入选择ID: " -t 20 select

case $select in
	"1" )
		install_kvm
		;;
	"2" )
		install_kvm
		install_web
		;;
	"3" )
		echo "建设ing"
		;;
esac
