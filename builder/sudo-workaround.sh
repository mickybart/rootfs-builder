#!/bin/bash

# in case of qemu-arm-static used, it is not possible to get euid 0 from a user as
# sudo sticky bit will not work as qem-arm-static is set without.
# of course we can't set the sticky bit to qemu-arm-static so we can use a specific workaround for sudo ...

# $1 : Debug mode ?
# $2 : install/uninstall

# $1 is used to pass DEBUG flag (0: no debug, else: debug)
if [ ${1-0} -eq 0 ]; then
	set -e
else
	set -ex
fi

function install() {
	mv /usr/bin/sudo /usr/bin/sudo.workaround
	cat << EOF > /usr/bin/sudo
#!/bin/bash
/usr/bin/qemu-arm-staticS /usr/bin/sudo.workaround \$@
EOF
	chmod +x /usr/bin/sudo
	cp /usr/bin/qemu-arm-static /usr/bin/qemu-arm-staticS
	chmod +s /usr/bin/qemu-arm-staticS
}

function uninstall() {
	if [ -f /usr/bin/sudo.workaround ]; then 
		rm /usr/bin/sudo
		mv /usr/bin/sudo.workaround /usr/bin/sudo
		rm /usr/bin/qemu-arm-staticS
	fi
}

# Needs sudo installed
if [ ! -f /usr/bin/sudo ]; then
	exit 0
fi

case $2 in
	install)
		install
		;;
	uninstall)
		uninstall
		;;
esac
