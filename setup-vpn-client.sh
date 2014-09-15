#!/bin/sh

# Copyright (c) 2014 Joshua Dugie <joshuadugie@users.noreply.github.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# Creates a working L2TP/IPsec client configuration, tested on Ubuntu 14.04.1.
# Created using information provided by the following URLs:
## https://wiki.archlinux.org/index.php/L2TP/IPsec_VPN_client_setup
## https://raymii.org/s/tutorials/IPSEC_L2TP_vpn_with_Ubuntu_14.04.html
## http://www.elastichosts.com/support/tutorials/linux-l2tpipsec-vpn-client

IPSEC_PSK="key"
PPP_USERNAME="username"
PPP_PASSWORD="password"

VPN_SERVER_NAT_INTERNAL="10.0.1.20"
VPN_SERVER_EXTERNAL="1.2.3.4"
VPN_NET_CIDR="10.0.1.0/24"

CREATE_DESKTOP_SHORTCUTS=true


# Change to home directory
OPWD="$(pwd)"
cd "${HOME}"

# cache sudo credentials
/usr/bin/sudo /bin/true

/usr/bin/sudo /usr/bin/tee /etc/ipsec.conf >/dev/null 2>&1 << _EOF
version	2.0	# conforms to second version of ipsec.conf specification

config setup
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12
    plutodebug=none
    strictcrlpolicy=no
    nat_traversal=yes
    interfaces=%defaultroute
    oe=off
    protostack=netkey
    plutoopts="--interface=eth0"

conn %default
    keyingtries=3
    pfs=no
    rekey=yes
    type=transport
    left=%defaultroute
    leftprotoport=17/1701
    rightprotoport=17/1701

conn vpn
    authby=secret
    pfs=no
    right=${VPN_SERVER_EXTERNAL}
    rightid="${VPN_SERVER_NAT_INTERNAL}"
    auto=add
    keyingtries=3
    dpddelay=30
    dpdtimeout=120
    dpdaction=clear
    rekey=yes
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%defaultroute
    leftnexthop=%defaultroute
    leftprotoport=17/1701
_EOF

/usr/bin/sudo /usr/bin/tee /etc/ipsec.secrets >/dev/null 2>&1 << _EOF
%any ${VPN_SERVER_EXTERNAL}: PSK 0t${IPSEC_PSK}
_EOF

/usr/bin/sudo /usr/bin/tee /etc/xl2tpd/xl2tpd.conf >/dev/null 2>&1 << _EOF
[global]
debug avp = no
debug network = no
debug packet = no
debug state = no
debug tunnel = no


[lac vpn-connection]
lns = ${VPN_SERVER_EXTERNAL}
refuse chap = yes
refuse pap = yes
require authentication = yes
name = vpn-server
ppp debug = yes
pppoptfile = /etc/ppp/options.l2tpd.client
length bit = yes
_EOF

/usr/bin/sudo /usr/bin/tee /etc/ppp/options.l2tpd.client >/dev/null 2>&1 << _EOF
ipcp-accept-local
ipcp-accept-remote
refuse-eap
require-mschap-v2
noccp
noauth
idle 1800
mtu 1410
mru 1410
defaultroute
usepeerdns
debug
lock
connect-delay 5000
name ${PPP_USERNAME}
password ${PPP_PASSWORD}
_EOF

# Create connect/disconnect helper scripts
cat > ./connect-to-vpn.sh << _EOF
#!/bin/sh

SUDO_ASKPASS=/usr/bin/ssh-askpass /usr/bin/sudo -A true

/usr/bin/sudo /etc/init.d/ipsec start
/bin/sleep 2
/usr/bin/sudo /etc/init.d/xl2tpd start
/bin/sleep 2
/usr/bin/sudo /usr/sbin/ipsec auto --up vpn
/usr/bin/sudo /usr/bin/tee /var/run/xl2tpd/l2tp-control >/dev/null 2>&1 << _EOF2
c vpn-connection
_EOF2
/bin/sleep 2

/usr/bin/sudo /sbin/ip route add ${VPN_NET_CIDR} via ${VPN_SERVER_NAT_INTERNAL}
_EOF

cat > ./disconnect-from-vpn.sh << _EOF
#!/bin/sh

SUDO_ASKPASS=/usr/bin/ssh-askpass /usr/bin/sudo -A true

/usr/bin/sudo /sbin/ip route del ${VPN_NET_CIDR} via ${VPN_SERVER_NAT_INTERNAL}

/usr/bin/sudo /usr/sbin/ipsec auto --down vpn
/bin/sleep 2
/usr/bin/sudo /usr/bin/tee /var/run/xl2tpd/l2tp-control >/dev/null 2>&1 << _EOF2
d vpn-connection
_EOF2
/bin/sleep 2
/usr/bin/sudo /etc/init.d/xl2tpd stop
/usr/bin/sudo /etc/init.d/ipsec stop
_EOF

chmod +x ./connect-to-vpn.sh
chmod +x ./disconnect-from-vpn.sh

# If creating desktop shortcuts, hide the helper scripts
if ${CREATE_DESKTOP_SHORTCUTS}; then
    mv ./connect-to-vpn.sh ./.connect-to-vpn.sh
    mv ./disconnect-from-vpn.sh ./.disconnect-from-vpn.sh

cat > "${HOME}/Desktop/Connect to VPN.desktop" << _EOF
#!/usr/bin/env xdg-open

[Desktop Entry]
Version=1.0
Type=Application
Name=Connect to VPN
GenericName=Connect to VPN
Comment=
Exec=${HOME}/.connect-to-vpn.sh
Icon=network-transmit-receive
_EOF


cat > "${HOME}/Desktop/Disconnect from VPN.desktop" << _EOF
#!/usr/bin/env xdg-open

[Desktop Entry]
Version=1.0
Type=Application
Name=Disconnect from VPN
GenericName=Disconnect from VPN
Comment=
Exec=${HOME}/.disconnect-from-vpn.sh
Icon=network-offline
_EOF

chmod +x "${HOME}/Desktop/Connect to VPN.desktop"
chmod +x "${HOME}/Desktop/Disconnect from VPN.desktop"
fi

cd "${OPWD}"
