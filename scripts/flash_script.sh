#MAGISK
##########################################################################################
#
# Magisk Flash Script
# by topjohnwu
#
# This script will detect, construct the environment for Magisk
# It will then call boot_patch.sh to patch the boot image
#
##########################################################################################

##########################################################################################
# Preparation
##########################################################################################

COMMONDIR=$INSTALLER/common
APK=$COMMONDIR/magisk.apk
CHROMEDIR=$INSTALLER/chromeos

# Default permissions
umask 022

OUTFD=$2
ZIP=$3

if [ ! -f $COMMONDIR/util_functions.sh ]; then
  echo "! Unable to extract zip file!"
  exit 1
fi

# Load utility fuctions
. $COMMONDIR/util_functions.sh

setup_flashable

##########################################################################################
# Detection
##########################################################################################

ui_print "************************"
ui_print "* Magisk v$MAGISK_VER Installer"
ui_print "************************"

is_mounted /data || mount /data || is_mounted /cache || mount /cache || abort "! Unable to mount partitions"
mount_partitions

find_boot_image
find_dtbo_image

check_data
get_flags

[ -z $BOOTIMAGE ] && abort "! Unable to detect target image"
ui_print "- Target image: $BOOTIMAGE"
[ -z $DTBOIMAGE ] || ui_print "- DTBO image: $DTBOIMAGE"

# Detect version and architecture
api_level_arch_detect

[ $API -lt 16 ] && abort "! Magisk is only for Jellybean and above (4.1+)"

ui_print "- Device platform: $ARCH"

BINDIR=$INSTALLER/$ARCH32
chmod -R 755 $CHROMEDIR $BINDIR

# Check if system root is installed and remove
remove_system_su

##########################################################################################
# Environment
##########################################################################################

ui_print "- Constructing environment"

if $DATA; then
  MAGISKBIN=/data/magisk
  $DATA_DE && MAGISKBIN=/data/adb/magisk
  run_migrations
else
  MAGISKBIN=/cache/data_bin
fi

# Copy required files
rm -rf $MAGISKBIN/* 2>/dev/null
mkdir -p $MAGISKBIN 2>/dev/null
cp -af $BINDIR/. $COMMONDIR/. $CHROMEDIR $TMPDIR/bin/busybox $MAGISKBIN
chmod -R 755 $MAGISKBIN

# addon.d
if [ -d /system/addon.d ]; then
  ui_print "- Adding addon.d survival script"
  mount -o rw,remount /system
  ADDOND=/system/addon.d/99-magisk.sh
  echo '#!/sbin/sh' > $ADDOND
  echo '# ADDOND_VERSION=2' >> $ADDOND
  echo 'exec sh /data/adb/magisk/addon.d.sh "$@"' >> $ADDOND
  chmod 755 $ADDOND
fi

$BOOTMODE || recovery_actions

##########################################################################################
# Boot patching
##########################################################################################

eval $BOOTSIGNER -verify < $BOOTIMAGE && BOOTSIGNED=true
$BOOTSIGNED && ui_print "- Boot image is signed with AVB 1.0"

SOURCEDMODE=true
cd $MAGISKBIN

# Source the boot patcher
. ./boot_patch.sh "$BOOTIMAGE"

ui_print "- Flashing new boot image"
flash_image new-boot.img "$BOOTIMAGE" || abort "! Insufficient partition size"
rm -f new-boot.img

if [ -f stock_boot* ]; then
  rm -f /data/stock_boot* 2>/dev/null
  $DATA && mv stock_boot* /data
fi

$KEEPVERITY || patch_dtbo_image

if [ -f stock_dtbo* ]; then
  rm -f /data/stock_dtbo* 2>/dev/null
  $DATA && mv stock_dtbo* /data
fi

cd /
# Cleanups
$BOOTMODE || recovery_cleanup
rm -rf $TMPDIR

ui_print "- Done"
exit 0
