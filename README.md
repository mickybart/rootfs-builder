# Archlinux ARM root builder

## Dependencies

### build from x86_64

```
Install binfmt-qemu-static and qemu-user-static from AUR

systemctl enable --now systemd-binfmt
```

### build from ARM with distcc cross-compilation on x86_64

read: https://archlinuxarm.org/wiki/Distcc_Cross-Compiling

## Build

Simply run the following to generate the rootfs

```
make
```

If you want to specify a stack

```
make STACK="halium"
```

If you want to set a specific MAKEFLAGS

```
make MAKEFLAGS="-j6"
```

If you don't want to install AUR helper and packages

```
make AUR=0
```

If you want to set a bigger image file than 2GiB

```
make IMGSIZE=<size in MiB>
```

If you want a specific target

```
make TARGET="x86_64|armv7"
```

### Build (debug mode)

This mode will force -ex and output of all commands into the chroot

```
make DEBUG=1
```

### Distcc

```
make DISTCC="ip1 ip2 ip..."
```

### Chroot into the build

```
make mount

sudo chroot build  /bin/sh
<ctrl+D>

make umount
```

