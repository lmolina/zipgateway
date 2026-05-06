#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# The status of the network and ZIP/GW is not clear, nor consistent after the experiments, thus the
# need to remove what we can.

source ./conf

/etc/init.d/zipgateway stop
apt purge zipgateway

find / -iname "*zipgateway*" \
  -not -path "/home/*" \
  -not -path "/var/lib/dpkg/*" \
  -not -path "/proc/*" \
  -print0 | xargs -0 rm -r

echo "zipgateway zipgateway/restart_nw select I will reboot later" > /tmp/preseed.txt
debconf-set-selections < /tmp/preseed.txt
DEBIAN_FRONTEND=noninteractive apt install -f "${ZIP_GATEWAY}"

# Deactivate STP on the bridge
sed -i "/bridge_stp*/d" "/etc/network/interfaces.d/br-lan"

# As configure on zipgateway.cfg
GW_CONFFILE="/usr/local/etc/zipgateway.cfg"
sed -i "/#SerialLog*/d" "${GW_CONFFILE}"
sed -i "/SerialLog*/d" "${GW_CONFFILE}"
echo "SerialLog=/var/log/ziprouter.serlog" >> "${GW_CONFFILE}"

sed -i "/ZipLanGw6*/d" "${GW_CONFFILE}"
echo "ZipLanGw6=${ZipLanGw6}" >> "${GW_CONFFILE}"

sed -i "/ZipLanIp6*/d" "${GW_CONFFILE}"
echo "ZipLanIp6=${ZipLanIp6}" >> "${GW_CONFFILE}"

sed -i "/ZipPanIp6*/d" "${GW_CONFFILE}"
echo "ZipPanIp6=${ZipPanIp6}" >> "${GW_CONFFILE}"

sed -i "/ZipPSK*/d" "${GW_CONFFILE}"
echo "ZipPSK=${ZipPSK}" >> "${GW_CONFFILE}"

sed -i "/ZWRFRegion/d" "${GW_CONFFILE}"
echo "ZWRFRegion=${REGION}" >> "${GW_CONFFILE}"

sed -i "/ZipSerialAPIPortName*/d" "${GW_CONFFILE}"
echo "ZipSerialAPIPortName=${ZipSerialAPIPortName}" >> "${GW_CONFFILE}"

rm -f /etc/logrotate.d/zipgateway
#cat > /etc/logrotate.d/zipgateway <<EOF
#"/var/log/zipgateway.log" "/var/log/zipgateway-serialapi.log" {
#        size 10000M
#        missingok
#}
#EOF
