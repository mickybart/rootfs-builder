#!/bin/bash

set -e

# 3 Args needed:
# $1 : Debug mode ?
# $2 : Distcc master ?
# $3 : Makeflags ?
# $4 : ARM Host ?
# $5 : AUR ?

# $1 is used to pass DEBUG flag (0: no debug, else: debug)
DEBUG=${1-0}
if [ $DEBUG -eq 0 ]; then
	OUTPUT_FILTER="&> /dev/null"
	SH_SET="-e"
else
	OUTPUT_FILTER=""
	SH_SET="-ex"
	set -ex
fi

# $2 is used for distcc (0: no, else: list of IPs)
DISTCC=$2

# $3 is used to set MAKEFLAGS options (0: auto generation, else: string)
MAKEFLAGS=$3

if [ "$MAKEFLAGS" == "0" ]; then
	if [ "$DISTCC" != "0" ]; then
		MAKEFLAGS="-j$(expr 2 \* $(echo "$DISTCC" | wc -w) + 1)"
	else
		MAKEFLAGS="-j2"
	fi
fi

# $4 is used to know if we are building the image from an ARM host or not
ARMHOST=$4

AUR=$5
AURHELPER=pacaur

ADDITIONAL_BASE_PACKAGES="base-devel git rsync vim bash-completion"
SUDO_USER=alarm

# Go to the parent directory of the directory script
cd $(dirname $(dirname $(readlink -f $0)))

# chroot_early scripts
echo "(chroot) Executing hooks/*.chroot_early"
for file in $(find hooks/ -name "*.chroot_early" | sort); do
	echo " => running $file"
	eval sh $SH_SET $file $OUTPUT_FILTER
done

# Update the system
echo "(chroot) Updating all packages..."
eval pacman -Syu --noconfirm $OUTPUT_FILTER

# Install early minimal requirements
echo "(chroot) Installing additional base packages"
eval pacman -S --noconfirm $ADDITIONAL_BASE_PACKAGES $OUTPUT_FILTER

# Set MAKEFLAGS
echo "(chroot) MAKEFLAGS configuration with $MAKEFLAGS"
sed -i "s/^#MAKEFLAGS/MAKEFLAGS/;s/^MAKEFLAGS=.*/MAKEFLAGS=\"$MAKEFLAGS\"/" /etc/makepkg.conf

# Distcc ?
if [ "$DISTCC" != "0" ]; then
	echo "(chroot) Distcc configuration (master device) with hosts: $DISTCC"
	eval pacman -S --noconfirm distcc $OUTPUT_FILTER
	sed -i 's/^BUILDENV=\(.*\)!distcc\(.*\)/BUILDENV=\1distcc\2/' /etc/makepkg.conf
	sed -i "s/^#DISTCC_HOSTS=/DISTCC_HOSTS=/;s/^DISTCC_HOSTS=.*/DISTCC_HOSTS=\"$DISTCC\"/" /etc/makepkg.conf
fi

# Sudo - (wheel group will be able to request high privileges without password. alarm is on this group and will permit to support AUR packages installation)
if [ $AUR -ne 0 ]; then
	echo "(chroot) sudo configuration"
	sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
	if [ $ARMHOST -eq 0 ]; then
		echo "(chroot) sudo workaround in qemu context"
		eval "sh $PWD/builder/sudo-workaround.sh $DEBUG install" $OUTPUT_FILTER
	fi
fi

# Install AUR helper (pacaur)
if [ $AUR -eq 0 ]; then
	echo "(chroot) We will not setup anything relative to AUR. Fallback to pacman !"
	echo "(chroot) aur-helper.sh script will be copied to the home of $SUDO_USER"
	eval cp $PWD/builder/aur-helper.sh /home/$SUDO_USER/ $OUTPUT_FILTER
	echo "sh ~/aur-helper.sh install $AURHELPER && rm -f ~/aur-{helper,install}.sh" > /home/$SUDO_USER/aur-install.sh
	eval chown $SUDO_USER /home/$SUDO_USER/aur-install.sh $OUTPUT_FILTER
	eval chmod +x /home/$SUDO_USER/aur-install.sh $OUTPUT_FILTER
else
	echo "(chroot) Installing AUR helper ($AURHELPER)"
	eval sudo -u $SUDO_USER -i -- sh $SH_SET $PWD/builder/aur-helper.sh install $AURHELPER $OUTPUT_FILTER
fi

# Install package-lists/*.chroot
echo "(chroot) Installing package-lists/*.chroot"
echo ' => /!\ Can be long if some packages need to be compiled from AUR. Please be patient ...'
AURHELPER_FLAGS=$(sh builder/aur-helper.sh getflags $AURHELPER)
for file in $(find package-lists/ -name "*.chroot" | sort); do
	echo " => from $file"
	if [ $AUR -eq 0 ]; then
		eval pacman -S --noconfirm $(cat $file | egrep -v '^#' | tr '\n' ' ') $OUTPUT_FILTER
	else
		eval sudo -u $SUDO_USER -i -- $AURHELPER -S $AURHELPER_FLAGS $(cat $file | egrep -v '^#' | tr '\n' ' ') $OUTPUT_FILTER
	fi
done

# chroot scripts
echo "(chroot) Executing hooks/*.chroot"
for file in $(find hooks/ -name "*.chroot" | sort); do
	echo " => running $file"
	eval sh $SH_SET $file $OUTPUT_FILTER
done

# Clean up
echo "(chroot) Cleaning up"

echo " => downloaded packages"
rm -f /var/cache/pacman/pkg/*.tar.xz
if [ $AUR -ne 0 ]; then
	eval sudo -u $SUDO_USER -i -- sh $SH_SET $PWD/builder/aur-helper.sh cleanup $AURHELPER $OUTPUT_FILTER
fi

echo " => MAKEFLAGS unconfiguration"
sed -i "s/^MAKEFLAGS=.*/#MAKEFLAGS=\"-j2\"/" /etc/makepkg.conf

if [ "$DISTCC" != "0" ]; then
	echo " => Distcc unconfiguration"
	sed -i 's/^BUILDENV=\(.*\)distcc\(.*\)/BUILDENV=\1!distcc\2/' /etc/makepkg.conf
	sed -i "s/^DISTCC_HOSTS=.*/#DISTCC_HOSTS=\"\"/" /etc/makepkg.conf
fi
