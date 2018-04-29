#!/bin/bash

# Auto Connect to any Open WiFi network via CLI Command Line
# see: https://unix.stackexchange.com/questions/250562/auto-connect-to-any-open-wifi-network-via-cli-command-line

declare BASH_UTILS_URL="https://raw.githubusercontent.com/nicholasadamou/bash-utils/master/utils.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

declare skipQuestions=false

trap "exit 1" TERM
export TOP_PID=$$

declare APP_NAME="Raspberry AnyFi"
declare MONIKER="4d4m0u"

declare STATION=wlan1
declare AP=wlan0
declare OPEN=open_wifi

setup_anyfi() {
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
  $(tput bold ; tput setaf 4)         $APP_NAME$(tput sgr0)
  $(tput bold ; tput setaf 4)               by $(tput setaf 5)$MONIKER$(tput sgr0)
  "

  echo "$(tput setaf 6)This script will configure your Raspberry Pi as a wireless access point and to connect to any OPEN WiFi access point.$(tput sgr0)"
  
  if [ "$TRAVIS" != "true" ]; then
    read -r -p "$(tput bold ; tput setaf 2)Press [Enter] to begin, [Ctrl-C] to abort...$(tput sgr0)"
  fi

  update
  upgrade

  declare -a PKGS=(
    "hostapd"
    "isc-dhcp-server"
    "iptables-persistent"
  )

  for PKG in "${PKGS[@]}"; do
      install_package "$PKG" "$PKG"
  done

  FILE=/etc/dhcp/dhcpd.conf
  cp "$FILE" "$FILE".bak

  sudo sed -i -e 's/option domain-name "example.org"/# option domain-name "example.org"/g' "$FILE"
  sudo sed -i -e 's/option domain-name-servers ns1.example.org/# option domain-name-servers ns1.example.org/g' "$FILE"
  sudo sed -i -e 's/#authoritative;/authoritative;/g' "$FILE"

  cat > "$FILE" <<- EOL
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

  FILE=/etc/default/isc-dhcp-server
  sudo cp "$FILE" "$FILE".bak

  sudo sed -i -e "s/INTERFACES=\"\"/INTERFACES=\"$AP\"/g" "$FILE"

  FILE=/etc/network/interfaces

  sudo ifdown "$AP"

  sudo mv "$FILE" "$FILE".bak
  cat > "$FILE" <<- EOL
	auto lo

	iface lo inet loopback
	iface eth0 inet dhcp

	allow-hotplug $AP
	iface $AP inet static
		address 192.168.42.1
		netmask 255.255.255.0

	allow-hotplug $STATION
	iface $STATION inet dhcp
	wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
		iface $OPEN inet dhcp
EOL

  sudo ifconfig "$AP" 192.168.42.1

  FILE=/etc/hostapd/hostapd.conf

  if [ "$TRAVIS" != "true" ]; then
      print_question "Enter an SSID for the HostAPD Hotspot: "
      SSID="$(read -r)"

      PASSWD1="0"
      PASSWD2="1"
      until [ $PASSWD1 == $PASSWD2 ]; do
          print_question "Type a password to access your $SSID, then press [ENTER]: "
          read -s -r PASSWD1
          print_question "Verify password to access your $SSID, then press [ENTER]: "
          read -s -r PASSWD2
      done

      if [ "$PASSWD1" == "$PASSWD2" ]; then
          print_success "Password set. Edit $FILE to change."
      fi
  fi

  cat > "$FILE" <<- EOL
	interface=$AP
	driver=rtl871xdrv
	ssid=$SSID
	hw_mode=g
	channel=6
	macaddr_acl=0
	auth_algs=1
	ignore_broadcast_ssid=0
	wpa=2
	wpa_passphrase=$PASSWD1
	wpa_key_mgmt=WPA2-PSK
	wpa_pairwise=TKIP
	rsn_pairwise=CCMP
EOL

  FILE=/etc/default/hostapd
  sudo cp "$FILE" "$FILE".bak
  sudo sed -i -e 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/g' "$FILE"

  FILE=/etc/sysctl.conf
  sudo cp "$FILE" "$FILE".bak
  echo "net.ipv4.ip_forward=1" >> "$FILE"

  FILE=/etc/network/interfaces
  echo "up iptables-restore < /etc/iptables.ipv4.nat" >> "$FILE"

  sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

  sudo iptables -t nat -A POSTROUTING -o "$STATION" -j MASQUERADE
  sudo iptables -A FORWARD -i "$STATION" -o "$AP" -m state --state RELATED,ESTABLISHED -j ACCEPT
  sudo iptables -A FORWARD -i "$AP" -o "$STATION" -j ACCEPT

  sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"
  sudo sudo systemctl enable netfilter-persistent

  wget http://www.adafruit.com/downloads/adafruit_hostapd.zip

  sudo unzip adafruit_hostapd.zip

  FILE=/usr/sbin/hostapd
  sudo mv "$FILE" "$FILE".ORIG
  sudo mv hostapd /usr/sbin
  sudo chmod 755 /usr/sbin/hostapd

  sudo rm adafruit_hostapd.zip

  sudo service hostapd start
  sudo service isc-dhcp-server start

  sudo update-rc.d hostapd enable
  sudo update-rc.d isc-dhcp-server enable

  FILE=/etc/wpa_supplicant/wpa_supplicant.conf

	cat > "$FILE" <<- EOL
	ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
	update_config=1

	network={
		ssid=""
		key_mgmt=NONE
		id_str="$OPEN"
	}
EOL

	sudo chmod 600 "$FILE"

  sudo mv /usr/share/dbus-1/system-services/fi.epitest.hostap.WPASupplicant.service ~/

  sudo ifconfig "$STATION" down && \
	sudo ifconfig "$STATION" up

  sudo wpa_cli -i "$STATION" status
}

restart() {
    ask_for_confirmation "Do you want to restart?"
    
    if answer_is_yes; then
        sudo shutdown -r now &> /dev/null
    fi
}

main() {
    # Ensure that the following actions
    # are made relative to this file's path.

    cd "$(dirname "${BASH_SOURCE[0]}")" \
        && source <(curl -s "$BASH_UTILS_URL") \
        || exit 1

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    skip_questions "$@" \
        && skipQuestions=true

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    ask_for_sudo

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    setup_anyfi

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    
    if ! $skipQuestions; then
        restart
    fi
}

main "$@"
