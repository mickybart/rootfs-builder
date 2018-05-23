#rootfs for Archlinux

DEBUG ?= 0
DISTCC ?= 0
JMAKEFLAGS ?= 0
STACK ?= halium
IMGSIZE ?= 2048
AUR ?= 1
TARGET ?= "armv7"

ARMHOST=$(shell [ $(shell uname -m) == "armv7l" ] && echo 1 || echo 0 )

SRCDIR=src
BUILDDIR=build
CUSTOMIZATION=customization/$(STACK)
BUILDER=builder

SUDO=/usr/bin/sudo

QEMU=
QEMU64=

ifeq (,$(filter $(TARGET),x86_64))
ifeq ($(ARMHOST),0)
QEMU=/usr/bin/qemu-arm-static
QEMU64=/usr/bin/qemu-aarch64-static
endif
endif

ifneq ($(DEBUG),0)
  HIDE=
else
  HIDE=@
endif

# Arch Linux image
#
ifeq ($(TARGET),armv7)
ARCHLINUX_SYSTEM_IMAGE_FILE=ArchLinuxARM-$(TARGET)-latest.tar.gz
ARCHLINUX_SYSTEM_IMAGE_URL=https://archlinuxarm.org/os/$(ARCHLINUX_SYSTEM_IMAGE_FILE)
else ifeq ($(TARGET),x86_64)
ARCHLINUX_SYSTEM_IMAGE_FILE=ArchLinux-$(TARGET)-latest.tar.gz
else
ARCHLINUX_SYSTEM_IMAGE_FILE=
endif

SRC_ARCHLINUX_SYSTEM_IMAGE_FILE=$(SRCDIR)/$(ARCHLINUX_SYSTEM_IMAGE_FILE)

ARCHLINUX_ROOTFS=$(STACK).rootfs.tar.gz

.PHONY : all mount umount mount-build umount-build extract image tgz

all: image

tgz: | .image .mount-build $(ARCHLINUX_ROOTFS) umount-build

image: $(SUDO) $(BUILDDIR) | build.img .mount-build .extract .mount .rootfs .umount
	$(HIDE)touch .image

$(ARCHLINUX_ROOTFS):
	$(info Building $(ARCHLINUX_ROOTFS))
	$(HIDE)$(SUDO) bsdtar czf $@ -C $(BUILDDIR) .
	$(HIDE)$(SUDO) chown $(USER):$(shell id -g -n $(USER)) $@
	@echo "Completed: $(ARCHLINUX_ROOTFS)"

$(SRC_ARCHLINUX_SYSTEM_IMAGE_FILE): $(SRCDIR)
	$(info Downloading GNU/Linux Image: $(ARCHLINUX_SYSTEM_IMAGE_FILE))
	$(HIDE)curl -L $(ARCHLINUX_SYSTEM_IMAGE_URL) -o $@

build.img:
	$(info Creating build.img)
	$(HIDE)dd if=/dev/zero of=build.img bs=1M count=$(IMGSIZE) > /dev/null 2>/dev/null
	$(HIDE)mkfs.ext4 build.img > /dev/null 2>/dev/null

extract: $(SUDO) $(BUILDDIR) | build.img .mount-build .extract umount-build

.extract: $(SRC_ARCHLINUX_SYSTEM_IMAGE_FILE)
	$(info Extracting $(ARCHLINUX_SYSTEM_IMAGE_FILE))
	$(HIDE)$(SUDO) bsdtar --numeric-owner -xzf $(SRC_ARCHLINUX_SYSTEM_IMAGE_FILE) -C $(BUILDDIR)
	$(HIDE)touch .extract

.mount: mount
	$(HIDE)touch .mount

.umount: umount
	$(HIDE)touch .umount

.mount-build:
	$(HIDE)$(SUDO) mount -o loop build.img $(BUILDDIR)
	$(HIDE)touch .mount-build

.rootfs:
	$(info Patching rootfs)
	$(HIDE)$(SUDO) chroot $(BUILDDIR) /bin/sh /home/.customization/builder/chroot-builder.sh $(DEBUG) "$(DISTCC)" $(JMAKEFLAGS) "$(QEMU)" $(AUR)
	$(HIDE)touch .rootfs

.mount-manual: $(SUDO) $(QEMU) $(QEMU64) $(BUILDDIR) $(CUSTOMIZATION) $(BUILDER)
	$(info Preparing the build)
	$(HIDE)$(SUDO) mount --bind /dev $(BUILDDIR)/dev
	$(HIDE)$(SUDO) mount --bind /proc $(BUILDDIR)/proc
	$(HIDE)$(SUDO) mount --bind /sys $(BUILDDIR)/sys
	$(HIDE)$(SUDO) mount --bind /tmp $(BUILDDIR)/tmp
	$(HIDE)$(SUDO) mv $(BUILDDIR)/etc/resolv.conf $(BUILDDIR)/etc/resolv.conf.bak
	$(HIDE)$(SUDO) cp /etc/resolv.conf $(BUILDDIR)/etc/resolv.conf
	$(HIDE)$(SUDO) cp -r $(CUSTOMIZATION) $(BUILDDIR)/home/.customization
	$(HIDE)$(SUDO) cp -r $(BUILDER) $(BUILDDIR)/home/.customization/
	$(HIDE)if [ -n "$(QEMU)" ]; then \
		$(SUDO) cp $(QEMU) $(BUILDDIR)/usr/bin/ ;\
		$(SUDO) cp $(QEMU64) $(BUILDDIR)/usr/bin/ ;\
		$(SUDO) chroot $(BUILDDIR) /bin/sh /home/.customization/builder/sudo-workaround.sh $(DEBUG) install ;\
	fi
	$(HIDE)touch .mount-manual

mount: | .mount-build .mount-manual

umount: $(SUDO) $(BUILDDIR)
	$(info Cleaning up the build)
	$(HIDE)if [ -n "$(QEMU)" ]; then \
		$(SUDO) chroot $(BUILDDIR) /bin/sh /home/.customization/builder/sudo-workaround.sh $(DEBUG) uninstall ;\
	fi
	$(HIDE)$(SUDO) fuser -m -k $(BUILDDIR) || true
	$(HIDE)$(SUDO) umount $(BUILDDIR)/dev
	$(HIDE)$(SUDO) umount $(BUILDDIR)/proc
	$(HIDE)$(SUDO) umount $(BUILDDIR)/sys
	$(HIDE)$(SUDO) umount $(BUILDDIR)/tmp
	$(HIDE)$(SUDO) mv $(BUILDDIR)/etc/resolv.conf.bak $(BUILDDIR)/etc/resolv.conf
	$(HIDE)$(SUDO) rm -rf $(BUILDDIR)/home/.customization
	$(HIDE)if [ -n "$(QEMU)" ]; then \
		$(SUDO) rm $(BUILDDIR)$(QEMU) ;\
		$(SUDO) rm $(BUILDDIR)$(QEMU64) ;\
	fi
	$(HIDE)$(SUDO) umount $(BUILDDIR)
	$(HIDE)rm -f .mount-manual
	$(HIDE)rm -f .mount-build

mount-build: .mount-build

umount-build:
	$(HIDE)$(SUDO) umount $(BUILDDIR)
	$(HIDE)rm -f .mount-build

$(SRCDIR):
	$(HIDE)mkdir -p $(SRCDIR)

$(BUILDDIR):
	$(HIDE)mkdir -p $(BUILDDIR)

.PHONY: clean clean-image clean-tgz clean-$(SCRDIR) mrproper

clean: $(SUDO)
	$(shell [ -f .mount-manual ] && make umount )
	$(HIDE)rm -f .extract
	$(HIDE)rm -f .mount
	$(HIDE)rm -f .mount-build
	$(HIDE)rm -f .umount
	$(HIDE)rm -f .rootfs
	$(HIDE)rm -f .image

clean-image:
	$(HIDE)rm -f build.img

clean-tgz:
	$(HIDE)rm -f $(ARCHLINUX_ROOTFS)

clean-$(SRCDIR):
	$(HIDE)rm -rf $(SRCDIR)

mrproper: clean clean-$(SRCDIR) clean-image clean-tgz

