#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
# 设置默认防火墙规则，方便虚拟机首次访问 WebUI
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"


# 计算网卡数量
count=3
for iface in /sys/class/net/*; do
  iface_name=$(basename "$iface")
  # 检查是否为物理网卡（排除回环设备和无线设备）
  if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
    count=$((count + 1))
  fi
done

# 检查配置文件pppoe-settings是否存在 该文件由build.sh动态生成
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >> $LOGFILE
else
   # 读取pppoe信息($enable_pppoe、$pppoe_account、$pppoe_password)
   . "$SETTINGS_FILE"
fi

# 检查配置文件system-core-settings是否存在 该文件由build.sh动态生成
SYSTEM_SETTINGS_FILE="/etc/config/system-core-settings"
if [ ! -f "$SYSTEM_SETTINGS_FILE" ]; then
    echo "System settings file not found. Skipping." >> $LOGFILE
else
   # 读取System信息($lan_ip、$gateway_ip、$dns_main)
   . "$SYSTEM_SETTINGS_FILE"
fi

# 网络设置 (网卡数量写死为2 走 elif 多网卡模式)
if [ "$count" -eq 1 ]; then
   # 单网口设备 类似于NAS模式 动态获取ip模式 具体ip地址取决于上一级路由器给它分配的ip 也方便后续你使用web页面设置旁路由
   # 单网口设备 不支持修改ip 不要在此处修改ip 
   uci set network.lan.proto='dhcp'
elif [ "$count" -gt 1 ]; then
   # 多网口设备 支持修改为别的ip地址
   uci set network.lan.proto='static'
   uci set network.lan.ipaddr="$lan_ip"
   uci set network.lan.netmask='255.255.255.0'
   uci set network.lan.gateway="$gateway_ip"
   # 设置默认DHCP功能
   uci del dhcp.lan.ra
   uci del dhcp.lan.ra_slaac
   uci del dhcp.lan.ra_flags
   uci del dhcp.lan.max_preferred_lifetime
   uci del dhcp.lan.max_valid_lifetime
   uci del dhcp.lan.dhcpv6
   uci del network.lan.ip6assign
   uci set dhcp.lan.ignore='1'
   uci set dhcp.lan.dynamicdhcp='0'
   uci set network.lan.delegate='0'
   # 添加默认DNS配置
   uci set network.lan.peerdns='0'  # 关闭自动获取 DNS
   uci set network.lan.dns='$dns_main 223.5.5.5 8.8.8.8 114.114.114.114 8.8.4.4'

   # 设置默认 DNS
   echo "nameserver 223.5.5.5" > /etc/resolv.conf
   echo "nameserver 8.8.8.8" >> /etc/resolv.conf
   echo "nameserver 114.114.114.114" >> /etc/resolv.conf
   echo "nameserver 8.8.4.4" >> /etc/resolv.conf

   uci commit network
   echo "set $lan_ip at $(date)" >> $LOGFILE
   # 判断是否启用 PPPoE
   echo "print enable_pppoe value=== $enable_pppoe" >> $LOGFILE
   if [ "$enable_pppoe" = "yes" ]; then
      echo "PPPoE is enabled at $(date)" >> $LOGFILE
      # 设置宽带拨号信息
      uci set network.wan.proto='pppoe'                
      uci set network.wan.username=$pppoe_account     
      uci set network.wan.password=$pppoe_password     
      uci set network.wan.peerdns='1'                  
      uci set network.wan.auto='1' 
      echo "PPPoE configuration completed successfully." >> $LOGFILE
   else
      echo "PPPoE is not enabled. Skipping configuration." >> $LOGFILE
   fi
fi

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Compiled by GeekOut.Net"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

exit 0
