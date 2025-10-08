#!/bin/bash
# ImmortalWrt 全自动整盘无人值守安装脚本
# 坏坏 + ChatGPT
set -e

DISK="/dev/sda"
DEFAULT_IP="192.168.3.11"
DEFAULT_NETMASK="255.255.255.0"
DEFAULT_GW="192.168.3.1"

echo "========================================================="
echo " ImmortalWrt 自动整盘安装程序"
echo " ⚠️  所有数据将被清除，请确保已备份！"
echo "========================================================="

# === 10秒输入自定义网络信息 ===
read -t 10 -p "请输入系统 IP 地址 [默认: $DEFAULT_IP]: " IPADDR || IPADDR=$DEFAULT_IP
read -t 10 -p "请输入子网掩码 [默认: $DEFAULT_NETMASK]: " NETMASK || NETMASK=$DEFAULT_NETMASK
read -t 10 -p "请输入网关地址 [默认: $DEFAULT_GW]: " GATEWAY || GATEWAY=$DEFAULT_GW

echo "使用网络配置:"
echo "  IP: $IPADDR"
echo "  掩码: $NETMASK"
echo "  网关: $GATEWAY"
sleep 2

# === 网络配置 ===
IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -m1 -E 'eth0|enp|ens')
ip addr flush dev $IFACE || true
ip addr add ${IPADDR}/24 dev $IFACE
ip route add default via ${GATEWAY}
echo "nameserver 223.5.5.5" > /etc/resolv.conf

# === 清空磁盘 ===
sgdisk --zap-all $DISK || true
wipefs -a $DISK || true
partprobe $DISK

# === 重新分区 ===
sgdisk -n1:0:+32M -t1:ef00 -c1:"EFI" $DISK
sgdisk -n2:0:0 -t2:8300 -c2:"ImmortalWrt" $DISK
partprobe $DISK

# === 格式化 ===
mkfs.vfat -F32 ${DISK}1
mkfs.ext4 -F ${DISK}2

# === 挂载 ===
mount ${DISK}2 /mnt
mkdir -p /mnt/boot
mount ${DISK}1 /mnt/boot

# === 写入系统文件 ===
if [ -f /rootfs.tar.gz ]; then
    echo "[INFO] 解压 rootfs 到 /mnt ..."
    tar -xpf /rootfs.tar.gz -C /mnt
else
    echo "[ERROR] 未找到 /rootfs.tar.gz"
    exit 1
fi

# === 写入网络配置 ===
mkdir -p /mnt/etc/config
cat > /mnt/etc/config/network <<EOF
config interface 'lan'
        option device '$IFACE'
        option proto 'static'
        option ipaddr '$IPADDR'
        option netmask '$NETMASK'
        option gateway '$GATEWAY'
        option dns '223.5.5.5'
EOF

# === 安装引导 ===
grub-install --target=i386-pc --boot-directory=/mnt/boot $DISK
grub-mkconfig -o /mnt/boot/grub/grub.cfg

echo "✅ 安装完成！系统已成功写入磁盘。"
echo "💻 IP 地址: $IPADDR"
echo "🌐 网关: $GATEWAY"
echo "将在 5 秒后自动重启..."
sleep 5
reboot
