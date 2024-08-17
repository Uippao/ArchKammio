#!/bin/bash

# Exit on errors
set -e

# Function to prompt for input with a default value
prompt() {
    read -p "$1 [$2]: " input
    echo "${input:-$2}"
}

# Ask for user details
USERNAME=$(prompt "Enter your username" "user")
USER_PASSWORD=$(prompt "Enter your password" "password")
ROOT_PASSWORD=$(prompt "Enter the root password" "rootpassword")
HOSTNAME=$(prompt "Enter your hostname" "archlinux")

# Ask for the desktop environment choice
echo "Choose a desktop environment:"
echo "1) KDE Plasma"
echo "2) Cinnamon"
echo "3) No Desktop Environment"
read -p "Enter choice [1-3]: " DE_CHOICE

# Validate DE choice
case $DE_CHOICE in
    1)
        DESKTOP_ENV="plasma"
        ;;
    2)
        DESKTOP_ENV="cinnamon"
        ;;
    3)
        DESKTOP_ENV=""
        ;;
    *)
        echo "Invalid choice, exiting."
        exit 1
        ;;
esac

# Ask for installation type
echo "Choose installation type:"
echo "1) Minimal (only essential packages)"
echo "2) Full (includes additional packages)"
read -p "Enter choice [1-2]: " INSTALL_TYPE

# Ask for boot manager choice
echo "Choose boot manager:"
echo "1) GRUB"
echo "2) GRUB with rEFInd"
read -p "Enter choice [1-2]: " BOOT_CHOICE

# Ask for browser choice if full install
if [ "$INSTALL_TYPE" -eq 2 ]; then
    echo "Choose your browser:"
    echo "1) Firefox"
    echo "2) Vivaldi"
    echo "3) Microsoft Edge"
    read -p "Enter choice [1-3]: " BROWSER_CHOICE

    case $BROWSER_CHOICE in
        1)
            BROWSER="firefox"
            ;;
        2)
            BROWSER="vivaldi"
            ;;
        3)
            BROWSER="microsoft-edge-stable-bin"
            ;;
        *)
            echo "Invalid choice, defaulting to Firefox."
            BROWSER="firefox"
            ;;
    esac
fi

# Set up mirrors
echo "Setting up mirrors for optimal download..."
reflector --latest 5 --sort rate --save /etc/pacman.d/mirrorlist

# Install base system
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the system
arch-chroot /mnt /bin/bash <<EOF

# Set timezone and clock
ln -sf /usr/share/zoneinfo/Europe/Helsinki /etc/localtime
hwclock --systohc

# Set up locale
sed -i 's/^#fi_FI.UTF-8 UTF-8/fi_FI.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=fi_FI.UTF-8" > /etc/locale.conf

# Set up keyboard layout
echo "KEYMAP=fi-latin1" > /etc/vconsole.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Set up hosts file
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Enable sudo for wheel group
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Install necessary packages
pacman -Syu --noconfirm grub efibootmgr networkmanager base-devel

# Install Yay (AUR helper)
sudo -u $USERNAME bash <<AUR
cd /opt
sudo git clone https://aur.archlinux.org/yay.git
sudo chown -R $USERNAME:users yay
cd yay
makepkg -si --noconfirm
AUR

# Install desktop environment if chosen
if [ "$DESKTOP_ENV" == "plasma" ]; then
    pacman -S --noconfirm plasma kde-applications dolphin konsole sddm
    systemctl enable sddm.service
elif [ "$DESKTOP_ENV" == "cinnamon" ]; then
    pacman -S --noconfirm cinnamon dolphin konsole lightdm lightdm-gtk-greeter
    systemctl enable lightdm.service
fi

# Install additional packages if full install is chosen
if [ "$INSTALL_TYPE" -eq 2 ]; then
    pacman -S --noconfirm - < /mnt/root/additional_packages.txt
    pacman -S --noconfirm $BROWSER
fi

# Enable NetworkManager
systemctl enable NetworkManager

# Install boot manager
if [ "$BOOT_CHOICE" -eq 1 ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
elif [ "$BOOT_CHOICE" -eq 2 ]; then
    pacman -S --noconfirm refind
    refind-install
    refind-mkconfig -o /boot/refind_linux.conf

    # Configure rEFInd autoboot timer
    sed -i 's/^#timeout 20/timeout 25/' /boot/EFI/refind/refind.conf

    # Install GRUB as well
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
fi

EOF

# Unmount partitions
umount -R /mnt

# Reboot
echo "Installation complete. Rebooting..."
reboot
