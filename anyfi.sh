#!/bin/bash
# Auto Connect to any Open WiFi network via CLI Command Line
# see: https://unix.stackexchange.com/questions/250562/auto-connect-to-any-open-wifi-network-via-cli-command-line

app_name="Raspberry AnyFi"
moniker="4d4m0u"

station=wlan1
AP=wlan0
open=open_wifi

root_check() {
	if (( $EUID != 0 )); then
		echo "This must be run as root. Try 'sudo bash $0'."
		exit 1
	fi
}

init() {
	echo -e "     
	$(tput setaf 6)   /         $(tput setaf 2)'. \ ' ' / .'$(tput setaf 6)         \\
	$(tput setaf 6)  |   /       $(tput setaf 1).~ .~~~..~.$(tput setaf 6)       \   |
	$(tput setaf 6) |   |   /  $(tput setaf 1) : .~.'~'.~. :$(tput setaf 6)   \   |   |
	$(tput setaf 6)|   |   |   $(tput setaf 1)~ (   ) (   ) ~$(tput setaf 6)   |   |   |
	$(tput setaf 6)|   |  |   $(tput setaf 1)( : '~'.~.'~' : )$(tput setaf 6)   |  |   |
	$(tput setaf 6)|   |   |   $(tput setaf 1)~ .~ (   ) ~. ~ $(tput setaf 6)  |   |   |
	$(tput setaf 6) |   |   \   $(tput setaf 1)(  : '~' :  )$(tput setaf 6)   /   |   |
	$(tput setaf 6)  |   \       $(tput setaf 1)'~ .~~~. ~'$(tput setaf 6)       /   |
	$(tput setaf 6)   \              $(tput setaf 1)'~'$(tput setaf 6)              /
	$(tput bold ; tput setaf 4)         $app_name$(tput sgr0)
	$(tput bold ; tput setaf 4)               by $(tput setaf 5)$moniker$(tput sgr0)
	"

	echo "$(tput setaf 6)This script will configure your Raspberry Pi as a wireless access point and to connect to any OPEN WiFi access point.$(tput sgr0)"
	read -p "$(tput bold ; tput setaf 2)Press [Enter] to begin, [Ctrl-C] to abort...$(tput sgr0)"
}

update_pkgs() {
  echo "$(tput setaf 6)Updating packages...$(tput sgr0)"
  apt-get update -q -y
}

install_pkgs() {
  echo "$(tput setaf 6)Installing hostapd...$(tput sgr0)"
  apt-get install hostapd -y

  echo "$(tput setaf 6)Installing ISC DHCP server...$(tput sgr0)"
  apt-get install isc-dhcp-server -y
}

configure_dhcp() {
  echo "$(tput setaf 6)Configuring ISC DHCP server...$(tput sgr0)"

  x=/etc/dhcp/dhcpd.conf
  cp $x $x.bak

  sed -i -e 's/option domain-name "example.org"/# option domain-name "example.org"/g' $x
  sed -i -e 's/option domain-name-servers ns1.example.org/# option domain-name-servers ns1.example.org/g' $x
  sed -i -e 's/#authoritative;/authoritative;/g' $x

  cat > $x <<- EOL
	subnet 192.168.42.0 netmask 255.255.255.0 {
  range 192.168.42.10 192.168.42.50;
  option broadcast-address 192.168.42.255;
  option routers 192.168.42.1;
  default-lease-time 600;
  max-lease-time 7200;
  option domain-name \042local\042;
  option domain-name-servers 8.8.8.8, 8.8.4.4;
  }
	EOL

  x=/etc/default/isc-dhcp-server
  cp $x $x.bak

  sed -i -e 's/INTERFACES=""/INTERFACES="$AP"/g' $x
}

configure_interfaces() {
  x=/etc/network/interfaces

  echo "$(tput setaf 6)Configuring '$x'...$(tput sgr0)"
  echo "$(tput setaf 6)Turning off $AP if active...$(tput sgr0)"
  ifdown $AP

  echo "$(tput setaf 6)Updating network interfaces...$(tput sgr0)"
  mv $x $x.bak
  cat > $x <<- EOL
	auto lo

  iface lo inet loopback
  iface eth0 inet dhcp

  allow-hotplug $AP
  iface $AP inet static
    address 192.168.42.1
    netmask 255.255.255.0

  allow-hotplug $station
  iface $station inet dhcp
  wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
	iface $open inet dhcp
  EOL

  echo "$(tput setaf 6)Assigning static IP address 192.168.42.1 to $AP...$(tput sgr0)"
  ifconfig $AP 192.168.42.1
}

configure_hostapd() {
  echo "$(tput setaf 6)Configuring hostapd...$(tput sgr0)"
  x=/etc/hostapd/hostapd.conf

  echo "$(tput bold ; tput setaf 2)Type a 1-32 character SSID (name) for your PiFi network, then press [ENTER]:$(tput sgr0)"
  read ssid
  echo "$(tput setaf 6)PiFi network SSID set to $(tput bold)$ssid$(tput sgr0 ; tput setaf 6). Edit $x to change.$(tput sgr0)"
  pwd1="0"
  pwd2="1"
  until [ $pwd1 == $pwd2 ]; do
    echo "$(tput bold ; tput setaf 2)Type a password to access your PiFi network, then press [ENTER]:$(tput sgr0)"
    read -s pwd1
    echo "$(tput bold ; tput setaf 2)Verify password to access your PiFi network, then press [ENTER]:$(tput sgr0)"
    read -s pwd2
  done

  if [ $pwd1 == $pwd2 ]; then
    echo "$(tput setaf 6)Password set. Edit $x to change.$(tput sgr0)"
  fi

  cat > $x << EOL
	interface=$AP
  driver=rtl871xdrv
  ssid=$ssid
  hw_mode=g
  channel=6
  macaddr_acl=0
  auth_algs=1
  ignore_broadcast_ssid=0
  wpa=2
  wpa_passphrase=$pwd1
  wpa_key_mgmt=WPA-PSK
  wpa_pairwise=TKIP
  rsn_pairwise=CCMP
	EOL

  echo "$(tput setaf 6)Setting hostapd to run at system boot...$(tput sgr0)"
  x=/etc/default/hostapd
  cp $x $x.bak
  sed -i -e 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/g' $x
}

configure_routes() {
  echo "$(tput setaf 6)Setting IP forwarding to start at system boot...$(tput sgr0)"
  x=/etc/sysctl.conf
  cp $x $x.bak
  echo "net.ipv4.ip_forward=1" >> $x

  x=/etc/network/interfaces
  echo "up iptables-restore < /etc/iptables.ipv4.nat" >> $x

  echo "$(tput setaf 6)Activating IP forwarding...$(tput sgr0)"
  sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

  echo "$(tput setaf 6)Setting up IP tables to interconnect ports...$(tput sgr0)"
  iptables -t nat -A POSTROUTING -o $station -j MASQUERADE
  iptables -A FORWARD -i $station -o $AP -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -A FORWARD -i $AP -o $station -j ACCEPT

  iptables -t nat -A POSTROUTING -o $ether -j MASQUERADE
  iptables -A FORWARD -i $ether -o $AP -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -A FORWARD -i $AP -o $ether -j ACCEPT

  echo "$(tput setaf 6)Saving IP tables...$(tput sgr0)"
  sh -c "iptables-save > /etc/iptables.ipv4.nat"
}

update_hostapd() {
  echo "$(tput setaf 6)Fetching Adafruit's updated access point software...$(tput sgr0)"
  wget http://www.adafruit.com/downloads/adafruit_hostapd.zip

  echo "$(tput setaf 6)Decompressing adafruit_hostapd.zip...$(tput sgr0)"
  unzip adafruit_hostapd.zip

  echo "$(tput setaf 6)Updating hostapd...$(tput sgr0)"
  x=/usr/sbin/hostapd
  mv $x $x.ORIG
  mv hostapd /usr/sbin
  chmod 755 /usr/sbin/hostapd

  echo "$(tput setaf 6)Cleaning up...$(tput sgr0)"
  rm adafruit_hostapd.zip
}

start() {
  echo "$(tput setaf 6)Starting hostapd service...$(tput sgr0)"
  service hostapd start

  echo "$(tput setaf 6)Starting ISC DHCP server...$(tput sgr0)"
  service isc-dhcp-server start
}

status() {
  echo "$(tput setaf 6)Checking hostapd status...$(tput sgr0)"
  service hostapd status
  hostapd_result=$?

  echo "$(tput setaf 6)Checking ISC DHCP server status...$(tput sgr0)"
  service isc-dhcp-server status
  dhcp_result=$?
}

enable_on_boot() {
  echo "$(tput setaf 6)Setting hostapd to start on system boot...$(tput sgr0)"
  update-rc.d hostapd enable

  echo "$(tput setaf 6)Setting ISC DHCP server to start on system boot...$(tput sgr0)"
  update-rc.d isc-dhcp-server enable
}

configure_wifi() {
	x=/etc/wpa_supplicant/wpa_supplicant.conf

	cat > $x <<- EOL
	ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
	update_config=1

	network={
		ssid=""
		key_mgmt=NONE
		id_str="$open"
	}
	EOL

	sudo chmod 600 $x

  echo "$(tput setaf 6)Removing WPASupplicant...$(tput sgr0)"
  mv /usr/share/dbus-1/system-services/fi.epitest.hostap.WPASupplicant.service ~/
}

reset() {
	sudo ifconfig $station down && \
	sudo ifconfig $station up
}

check() {
	sudo wpa_cli -i $station status
}

closing() {
	echo "$(tput setaf 6)Thanks for using $(tput bold ; tput setaf 5)$app_name$(tput sgr0)$(tput setaf 6) by $(tput bold ; tput setaf 5)$moniker$(tput sgr0)$(tput setaf 6)!$(tput sgr0)"
}

begin() {
	root_check
	init
	update_pkgs
	install_pkgs
	configure_dhcp
	configure_interfaces
	configure_hostapd
	configure_routes
	update_hostapd
	start
	status
	enable_on_boot
	configure_wifi
	reset
	check
	closing
	exit 0
}

begin
