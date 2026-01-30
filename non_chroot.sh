source ./utility.sh

# Internet connectivity check
if ! ping -c1 ping.archlinux.org >/dev/null 2>&1; then
    echo "ERROR: No internet connection or failed to resolve domain."
    exit 1
fi

# Are we booted correctly?
if [ $(cat /sys/firmware/efi/fw_platform_size 2>/dev/null) != "64" ]; then
    echo "ERROR: System isn't booted in UEFI mode or isn't 64-bit."
    exit 1
fi

# Sync system clock
#timedatectl set-ntp true

# Sync pacman and packages
#pacman -Syu --noconfirm

# Drive selection
while true; do
    lsblk -o NAME,SIZE,MODEL
    read -rp "Select a drive (default: nvme0n1): " TARGET_DRIVE
    TARGET_DRIVE="/dev/${TARGET_DRIVE:-nvme0n1}"
    
    # Check if the drive exists
    if [ -b "$TARGET_DRIVE" ]; then
        echo "Selected drive: $TARGET_DRIVE."
        break
    else
        echo "ERROR: $TARGET_DRIVE does not exist."
    fi
done

# Partitioning
FORMAT_EFI=1

read -rp "Partition interactively? (Y/n): " confirm
confirm="${confirm:-Y}"
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "Partitioning interactively"
    fdisk $TARGET_DRIVE

    read -rp "Select EFI: " EFI_PART
    read -rp "Select root: " ROOT_PART
    
    read -rp "Format EFI? (Y/n): " confirm
    confirm="${confirm:-Y}"
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        FORMAT_EFI=0
    fi
else
    read -rp "WARNING: $TARGET_DRIVE will be fully erased. Continue? (y/N): " confirm
    confirm="${confirm:-N}"
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 1
    fi

    sgdisk --zap-all "$TARGET_DRIVE"
    sgdisk -n 1:0:+1G -t 1:EF00 "$TARGET_DRIVE"
    sgdisk -n 2:0:0 -t 2:8300 "$TARGET_DRIVE"

    EFI_PART="${TARGET_DRIVE}1"
    ROOT_PART="${TARGET_DRIVE}2"
fi

# Get some DATA
set_pass USER_PASS "Set user password"
set_pass ROOT_PASS "Set root password"
set_pass LUKS_PASS "Set LUKS password"

# Formatting
if [ "$FORMAT_EFI" -eq 1 ]; then
    mkfs.fat -F32 "$EFI_PART"
fi

cryptsetup luksFormat "$ROOT_PART" <<<"$LUKS_PASS"
cryptsetup open "$ROOT_PART" cryptroot <<<"$LUKS_PASS"

CRYPT_PART="/dev/mapper/cryptroot"

mkfs.btrfs "${CRYPT_PART}" -f

# BTRFS setup
BASE_OPTS=(
    "rw,relatime,ssd,space_cache=v2,compress=zstd:3"
)

# Name Mount Compress Cow
SUBVOLS=(
    "@ /" 
    "@home /home"
    "@varlog /var/log"
    "@snapshots /.snapshots"
    "@paccache /var/cache/pacman"
    "@libvirt /var/lib/libvirt"
    "@docker /var/lib/docker"
)

mkdir -p /mnt
mount "$CRYPT_PART" /mnt

# Subvolume creation
for entry in "${SUBVOLS[@]}"; do
    read -r SUBVOL MOUNTPOINT <<< "$entry"
    SUBVOL_PATH="/mnt/$SUBVOL"
    btrfs subvolume create "$SUBVOL_PATH"
    btrfs property set "$SUBVOL_PATH" compression zstd:3
done

# Mount root partition
umount /mnt
mount -o "$BASE_OPTS,subvol=@" "$CRYPT_PART" /mnt

# Mount everything else
for entry in "${SUBVOLS[@]}"; do
    read -r SUBVOL MOUNTPOINT <<< "$entry"
    [[ "$SUBVOL" == "@" ]] && continue
    TARGET_DIR="/mnt$MOUNTPOINT"
    mkdir -p "$TARGET_DIR"
    mount -o "$BASE_OPTS,subvol=$SUBVOL" "$CRYPT_PART" "$TARGET_DIR"
done

# Fstab generation
FSTAB_TEMP="/tmp/fstab"
CRYPT_UUID=$(blkid -s UUID -o value "$CRYPT_PART")
BOOT_UUID=$(blkid -s UUID -o value "$EFI_PART")

for entry in "${SUBVOLS[@]}"; do
    read -r SUBVOL MOUNTPOINT <<< "$entry"

    OPTS="$BASE_OPTS,subvol=$SUBVOL"
    echo "UUID=$CRYPT_UUID $MOUNTPOINT btrfs $OPTS 0 0" >> "$FSTAB_TEMP"
done

# Boot partition
BOOT_OPTS="rw,relatime,fmask=0137,dmask=0027,utf8,shortname=mixed"
mkdir -p /mnt/boot
mount -o "$BOOT_OPTS" "$EFI_PART" /mnt/boot
echo "UUID=$BOOT_UUID /boot vfat $BOOT_OPTS 0 2" >> "$FSTAB_TEMP"

# System installation
if grep -i 'Intel' /proc/cpuinfo >/dev/null 2>&1; then
    ucode_pkg=intel-ucode
elif grep -i 'AMD' /proc/cpuinfo >/dev/null 2>&1; then
    ucode_pkg=amd-ucode
else
    ucode_pkg=""
fi

pacstrap -K /mnt base base-devel linux linux-firmware networkmanager "${ucode_pkg}" --noconfirm
