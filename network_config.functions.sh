#!/usr/bin/env bash

#
# network config functions
#
# (c) 2016, Hetzner Online GmbH
#

# setup /etc/sysconfig/network
setup_etc_sysconfig_network() {
  debug '# setup /etc/sysconfig/network'

  {
    echo "### $COMPANY installimage"
    echo
    echo "NETWORKING=yes"
  } > "$FOLD/hdd/etc/sysconfig/network"
}

# list network interfaces
network_interfaces() {
  for file in /sys/class/net/*; do
    echo "${file##*/}"
  done
}

# check whether network interface is virtual
# $1 <network_interface>
network_interface_is_virtual() {
  local network_interface="$1"
  [[ -d "/sys/devices/virtual/net/$network_interface" ]]
}

# list physical network interfaces
physical_network_interfaces() {
  while read network_interface; do
    network_interface_is_virtual "$network_interface" && continue
    echo "$network_interface"
  done < <(network_interfaces)
}

# get ip addr without suffix
# $1 <ip_addr>
ip_addr_without_suffix() {
  local ip_addr="$1"
  echo "${ip_addr%%/*}"
}

# get ip addr suffix
# $1 <ip_addr>
ip_addr_suffix() {
  local ip_addr="$1"
  if [[ "$ip_addr" =~ / ]]; then
    echo "${ip_addr##*/}"
  # assume /32 unless $ip_addr contains /
  else
    echo 32
  fi
}

# conv ipv4 addr to int
# $1 <ipv4_addr>
ipv4_addr_to_int() {
  local ipv4_addr="$1"
  local ipv4_addr_without_suffix="$(ip_addr_without_suffix "$ipv4_addr")"
  { IFS=. read a b c d; } <<< "$ipv4_addr_without_suffix"
  echo "$(((((((a << 8) | b) << 8) | c) << 8) | d))"
}

# conv int to ipv4 addr
# $1 <int>
int_to_ipv4_addr() {
  local int="$1"
  echo "$(((int >> 24) & 0xff)).$(((int >> 16) & 0xff)).$(((int >> 8) & 0xff)).$((int & 0xff))/32"
}

# calc ipv4 addr network
# $1 <ipv4_addr>
ipv4_addr_network() {
  local ipv4_addr="$1"
  local ipv4_addr_suffix="$(ip_addr_suffix "$ipv4_addr")"
  local int="$(ipv4_addr_to_int "$ipv4_addr")"
  local network_without_suffix="$(ip_addr_without_suffix "$(int_to_ipv4_addr "$((int & (0xffffffff << (32 - ipv4_addr_suffix))))")")"
  echo "$network_without_suffix/$ipv4_addr_suffix"
}

# check whether network contains ipv4 addr
# $1 <network>
# $2 <ipv4_addr>
network_contains_ipv4_addr() {
  local network="$1"
  local ipv4_addr="$2"
  ipv4_addr="$(ip_addr_without_suffix "$ipv4_addr")/$(ip_addr_suffix "$network")"
  [[ "$(ipv4_addr_network "$ipv4_addr")" == "$network" ]]
}

# check whether ipv4 addr is a shared addr (rfc6598)
# $1 <ipv4_addr>
ipv4_addr_is_shared_addr() {
  local ipv4_addr="$1"
  network_contains_ipv4_addr 100.64.0.0/10 "$ipv4_addr"
}

# get network interface ipv4 addrs
# $1 <network_interface>
network_interface_ipv4_addrs() {
  local network_interface="$1"
  while read line; do
    [[ "$line" =~ ^\ *inet\ ([^\ ]+) ]] || continue
    local ipv4_addr="${BASH_REMATCH[1]}"
    # ignore shared addrs
    ipv4_addr_is_shared_addr "$ipv4_addr" && continue
    echo "$ipv4_addr"
  done < <(ip -4 a s "$network_interface")
}

# check whether ipv6 addr is a link local unicast addr
# $1 <ipv6_addr>
ipv6_addr_is_link_local_unicast_addr() {
  local ipv6_addr="$1"
  [[ "$ipv6_addr" =~ ^fe80: ]]
}

# get network interface ipv6 addrs
# $1 <network_interface>
network_interface_ipv6_addrs() {
  local network_interface="$1"
  while read line; do
    [[ "$line" =~ ^\ *inet6\ ([^\ ]+) ]] || continue
    local ipv6_addr="${BASH_REMATCH[1]}"
    # ignore link local unicast addrs
    ipv6_addr_is_link_local_unicast_addr "$ipv6_addr" && continue
    echo "$ipv6_addr"
  done < <(ip -6 a s "$network_interface")
}

# check whether to use predictable network interface names
use_predictable_network_interface_names() {
  [[ "$IAM" == 'centos' ]] && ((IMG_VERSION >= 73)) && return
  return 1
}

# get network interface driver
network_interface_driver() {
  local network_interface="$1"
  basename "$(readlink -f "/sys/class/net/$network_interface/device/driver")"
}

# predict network interface name
# $1 <network_interface>
predict_network_interface_name() {
  local network_interface="$1"
  local network_interface_driver="$(network_interface_driver "$network_interface")"
  if ! use_predictable_network_interface_names || [[ "$network_interface_driver" == 'virtio_net' ]]; then
    echo "$network_interface"
    return
  fi
  local d="$(echo; udevadm test-builtin net_id "/sys/class/net/$network_interface" 2>/dev/null)"
  [[ "$d" =~ $'\n'ID_NET_NAME_ONBOARD=([^$'\n']+) ]] && echo "${BASH_REMATCH[1]}" && return
  [[ "$d" =~ $'\n'ID_NET_NAME_SLOT=([^$'\n']+) ]] && echo "${BASH_REMATCH[1]}" && return
  # we need to convert ID_NET_NAME_PATH to ID_NET_NAME_SLOT for e1000 and 8139cp network interfaces
  [[ "$network_interface_driver" =~ ^(e1000|8139cp)$ ]] && [[ "$d" =~ $'\n'ID_NET_NAME_PATH=([a-z]{2})p0([^$'\n']+) ]] && echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}" && return
  [[ "$d" =~ $'\n'ID_NET_NAME_PATH=([^$'\n']+) ]] && echo "${BASH_REMATCH[1]}" && return
  [[ "$d" =~ $'\n'ID_NET_NAME_MAC=([^$'\n']+) ]] && echo "${BASH_REMATCH[1]}" && return
  return 1
}

# check whether ipv4 addr is private
# $1 <ipv4_addr>
ipv4_addr_is_private() {
  local ipv4_addr="$1"
  network_contains_ipv4_addr 10.0.0.0/8 "$ipv4_addr" ||
  network_contains_ipv4_addr 172.16.0.0/12 "$ipv4_addr" ||
  network_contains_ipv4_addr 192.168.0.0/16 "$ipv4_addr"
}

# calc ipv4 addr netmask
# $1 <ipv4_addr>
ipv4_addr_netmask() {
  local ipv4_addr="$1"
  local ipv4_addr_suffix="$(ip_addr_suffix "$ipv4_addr")"
  ip_addr_without_suffix "$(int_to_ipv4_addr "$((0xffffffff << (32 - ipv4_addr_suffix)))")"
}

# get network interface ipv4 gateway
# $1 <network_interface>
network_interface_ipv4_gateway() {
  local network_interface="$1"
  [[ "$(ip -4 r l 0/0 dev "$network_interface")" =~ ^default\ via\ ([^\ $'\n']+) ]] && echo "${BASH_REMATCH[1]}"
}

# get network interface ipv6 gateway
# $1 <network_interface>
network_interface_ipv6_gateway() {
  local network_interface="$1"
  [[ "$(ip -6 r l ::/0 dev "$network_interface")" =~ ^default\ via\ ([^\ $'\n']+) ]] && echo "${BASH_REMATCH[1]}"
}

# gen ifcfg script centos
# $1 <network_interface>
gen_ifcfg_script_centos() {
  local network_interface="$1"
  local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
  local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))

  echo "### $COMPANY installimage"
  echo
  echo "DEVICE=$predicted_network_interface_name"
  echo 'ONBOOT=yes'
  echo -n 'BOOTPROTO='
  # dhcp
  if ipv4_addr_is_private "${ipv4_addrs[0]}" && isVServer; then
    echo "configuring dhcpv4 for $predicted_network_interface_name" >&2
    echo 'dhcp'
  # static config
  else
    echo 'none'
  fi

  # static config
  if ! ipv4_addr_is_private "${ipv4_addrs[0]}" || ! isVServer; then
    local address="$(ip_addr_without_suffix "${ipv4_addrs[0]}")"
    # ! pointtopoint
    if ipv4_addr_is_private "${ipv4_addrs[0]}" || isVServer; then
      local netmask="$(ipv4_addr_netmask "${ipv4_addrs[0]}")"
    # pointtopoint
    else
      local netmask='255.255.255.255'
    fi
    local gateway="$(network_interface_ipv4_gateway "$network_interface")"

    echo "configuring ipv4 addr ${ipv4_addrs[0]} for $predicted_network_interface_name" >&2
    echo "IPADDR=$address"
    echo "NETMASK=$netmask"
    if [[ -n "$gateway" ]]; then
      # pointtopoint
      if ! ipv4_addr_is_private "${ipv4_addrs[0]}" && ! isVServer; then
        local network="$(ipv4_addr_network "${ipv4_addrs[0]}")"

        echo "configuring host route $network via $gateway" >&2
        echo "SCOPE=\"peer $gateway\""
      # ! pointtopoint
      else
        echo "configuring ipv4 gateway $gateway for $predicted_network_interface_name" >&2
        echo "GATEWAY=$gateway"
      fi
    fi
  fi

  local ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
  ((${#ipv6_addrs[@]} == 0)) && return

  echo "configuring ipv6 addr ${ipv6_addrs[0]} for $predicted_network_interface_name" >&2
  echo
  echo 'IPV6INIT=yes'
  echo "IPV6ADDR=${ipv6_addrs[0]}"

  local gatewayv6="$(network_interface_ipv6_gateway "$network_interface")"
  [[ -z "$gatewayv6" ]] && return

  echo "configuring ipv6 gateway $gatewayv6 for $predicted_network_interface_name" >&2
  echo "IPV6_DEFAULTGW=$gatewayv6"

  # always add IPV6_DEFAULTDEV
  # ipv6_addr_is_link_local_unicast_addr "$gatewayv6" || return

  echo "IPV6_DEFAULTDEV=$predicted_network_interface_name"
}

# gen route script
# $1 <gateway>
gen_route_script() {
  local gateway="$1"

  echo "### $COMPANY installimage"
  echo
  echo 'ADDRESS0=0.0.0.0'
  echo 'NETMASK0=0.0.0.0'
  echo "GATEWAY0=$gateway"
}

# setup /etc/sysconfig/network-scripts for centos
setup_etc_sysconfig_network_scripts_centos() {
  debug '# setup /etc/sysconfig/network-scripts'

  # clean up /etc/sysconfig/network-scripts
  find "$FOLD/hdd/etc/sysconfig/network-scripts" -type f \( -name 'ifcfg-*' -or -name 'route-*' \) -and -not -name 'ifcfg-lo' -delete

  while read network_interface; do
    local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
    local ip_addrs=("${ipv4_addrs[@]}" $(network_interface_ipv6_addrs "$network_interface"))
    ((${#ip_addrs[@]} == 0)) && continue

    local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
    local ifcfg_script="/etc/sysconfig/network-scripts/ifcfg-$predicted_network_interface_name"

    debug "# setting up $ifcfg_script"
    gen_ifcfg_script_centos "$network_interface" > "$FOLD/hdd/$ifcfg_script" 2> >(debugoutput)

    local gateway="$(network_interface_ipv4_gateway "$network_interface")"
    # ! pointtopoint
    if [[ -z "$gateway" ]] || ipv4_addr_is_private "${ipv4_addrs[0]}" || isVServer; then
      continue
    fi

    local route_script="/etc/sysconfig/network-scripts/route-$predicted_network_interface_name"
    debug "# setting up $route_script"
    gen_route_script "$gateway" > "$FOLD/hdd/$route_script" 2> >(debugoutput)
  done < <(physical_network_interfaces)
}

# gen ifcfg script suse
# $1 <network_interface>
gen_ifcfg_script_suse() {
  local network_interface="$1"
  local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
  local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"

  echo "### $COMPANY installimage"
  echo
  echo 'STARTMODE="auto"'
  # dhcp
  if ipv4_addr_is_private "${ipv4_addrs[0]}" && isVServer; then
    echo "configuring dhcpv4 for $predicted_network_interface_name" >&2
    echo 'BOOTPROTO="dhcp4"'
    echo 'DHCLIENT_SET_HOSTNAME="no"'
  # static config
  else
    local ipaddr="$(ip_addr_without_suffix "${ipv4_addrs[0]}")"
    # ! pointtopoint
    if ipv4_addr_is_private "${ipv4_addrs[0]}" || isVServer; then
      local netmask="$(ip_addr_suffix "${ipv4_addrs[0]}")"
    # pointtopoint
    else
      local netmask='32'
    fi
    echo "configuring ipv4 addr $ipaddr/$netmask for $predicted_network_interface_name" >&2
    echo "IPADDR=\"$ipaddr/$netmask\""

    local gateway="$(network_interface_ipv4_gateway "$network_interface")"
    # pointtopoint
    if [[ -n "$gateway" ]] && ! ipv4_addr_is_private "${ipv4_addrs[0]}" && ! isVServer; then
      local network="$(ipv4_addr_network "${ipv4_addrs[0]}")"

      echo "configuring host route $network via $gateway" >&2
      echo "REMOTE_IPADDR=\"$gateway\""
    fi
  fi

  local ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
  ((${#ipv6_addrs[@]} == 0)) && return

  echo "configuring ipv6 addr ${ipv6_addrs[0]} for $predicted_network_interface_name" >&2
  echo
  echo -n 'IPADDR'
  ((${#ipv4_addrs[@]} > 0)) && echo -n '_0'
  echo "=\"${ipv6_addrs[0]}\""
}

# gen ifroute script
# $1 <network_interface>
gen_ifroute_script() {
  local network_interface="$1"
  local gateway="$(network_interface_ipv4_gateway "$network_interface")"
  local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
  local gatewayv6="$(network_interface_ipv6_gateway "$network_interface")"

  echo "### $COMPANY installimage"
  echo
  # static config
  if [[ -n "$gateway" ]] && ! ipv4_addr_is_private "${ipv4_addrs[0]}" || ! isVServer; then
    echo "configuring ipv4 gateway $gateway for $predicted_network_interface_name" >&2
    echo "default $gateway - $predicted_network_interface_name"
  fi
  [[ -z "$gatewayv6" ]] && return
  echo "configuring ipv6 gateway $gatewayv6 for $predicted_network_interface_name" >&2
  echo "default $gatewayv6 - $predicted_network_interface_name"
}

# gen routes script
# $1 <network_interface>
gen_routes_script() {
  local network_interface="$1"
  gen_ifroute_script "$network_interface"
}

# setup /etc/sysconfig/network scripts for suse
setup_etc_sysconfig_network_scripts_suse() {
  debug '# setup /etc/sysconfig/network scripts'

  # clean up /etc/sysconfig/network
  find "$FOLD/hdd/etc/sysconfig/network" -type f \( -name 'ifcfg-*' -or -name 'ifroute-*' -or -name 'routes' \) -and -not -name 'ifcfg-lo' -delete

  while read network_interface; do
    local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
    local ip_addrs=("${ipv4_addrs[@]}" $(network_interface_ipv6_addrs "$network_interface"))
    ((${#ip_addrs[@]} == 0)) && continue

    local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
    local ifcfg_script="/etc/sysconfig/network/ifcfg-$predicted_network_interface_name"

    debug "# setting up $ifcfg_script"
    gen_ifcfg_script_suse "$network_interface" > "$FOLD/hdd/$ifcfg_script" 2> >(debugoutput)

    # local route_script="/etc/sysconfig/network/ifroute-$predicted_network_interface_name"
    local routes_script="/etc/sysconfig/network/routes"

    # debug "# setting up $route_script"
    # gen_ifroute_script "$network_interface" > "$FOLD/hdd/$route_script" 2> >(debugoutput)
    debug "# setting up $routes_script"
    gen_routes_script "$network_interface" > "$FOLD/hdd/$routes_script" 2> >(debugoutput)
  done < <(physical_network_interfaces)
}

# gen /etc/network/interfaces entry
# $1 <network_interface>
gen_etc_network_interfaces_entry() {
  local network_interface="$1"
  local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
  local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
  local ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
  ((${#ipv4_addrs[@]} == 0)) && ((${#ipv6_addrs[@]} == 0)) && return

  echo
  echo "auto $predicted_network_interface_name"
  if ((${#ipv4_addrs[@]} > 0)); then
    echo -n "iface $predicted_network_interface_name inet "
    # dhcp
    if ipv4_addr_is_private "${ipv4_addrs[0]}" && isVServer; then
      echo "configuring dhcpv4 for $predicted_network_interface_name" >&2
      echo 'dhcp'
    # static config
    else
      local address="$(ip_addr_without_suffix "${ipv4_addrs[0]}")"
      local netmask="$(ipv4_addr_netmask "${ipv4_addrs[0]}")"
      local gateway="$(network_interface_ipv4_gateway "$network_interface")"

      echo "configuring ipv4 addr ${ipv4_addrs[0]} for $predicted_network_interface_name" >&2
      echo 'static'
      echo "  address $address"
      echo "  netmask $netmask"
      if [[ -n "$gateway" ]]; then
        echo "configuring ipv4 gateway $gateway for $predicted_network_interface_name" >&2
        echo "  gateway $gateway"
      fi
      # pointtopoint
      if ! ipv4_addr_is_private "${ipv4_addrs[0]}" && ! isVServer; then
        local network="$(ipv4_addr_network "${ipv4_addrs[0]}")"
        echo "configuring host route $network via $gateway" >&2
        echo "  # route $network via $gateway"
        # echo "  up ip route add $network via $gateway dev $predicted_network_interface_name"

        local network_without_suffix="$(ip_addr_without_suffix "$network")"
        echo "  up route add -net $network_without_suffix netmask $netmask gw $gateway dev $predicted_network_interface_name"
      fi
    fi
  fi

  ((${#ipv6_addrs[@]} == 0)) && return

  ((${#ipv4_addrs[@]} > 0)) && echo

  local addressv6="$(ip_addr_without_suffix "${ipv6_addrs[0]}")"
  local netmaskv6="$(ip_addr_suffix "${ipv6_addrs[0]}")"
  local gatewayv6="$(network_interface_ipv6_gateway "$network_interface")"

  echo "configuring ipv6 addr ${ipv6_addrs[0]} for $predicted_network_interface_name" >&2
  echo "iface $predicted_network_interface_name inet6 static"
  echo "  address $addressv6"
  echo "  netmask $netmaskv6"
  if [[ -n "$gatewayv6" ]]; then
    echo "configuring ipv6 gateway $gatewayv6 for $predicted_network_interface_name" >&2
    echo "  gateway $gatewayv6"
  fi
}

# setup /etc/network/interfaces
setup_etc_network_interfaces() {
  debug '# setting up /etc/network/interfaces'

  {
    echo "### $COMPANY installimage"
    echo
    echo 'auto lo'
    echo 'iface lo inet loopback'
    echo 'iface lo inet6 loopback'
    while read network_interface; do
      gen_etc_network_interfaces_entry "$network_interface"
    done < <(physical_network_interfaces)
  } > "$FOLD/hdd/etc/network/interfaces" 2> >(debugoutput)
}

# # check whether installed os supports predictable network interface names
# installed_os_supports_predictable_network_interface_names() {
#   installed_os_uses_systemd && (($(installed_os_systemd_version) >= 197))
# }

# # disable predictable network interface names
# disable_predictable_network_interface_names() {
#   debug '# disabling predictable network interface names'
# 
#   ln -s /dev/null "$FOLD/hdd/etc/systemd/network/99-default.link"
# }

# get network interface mac
network_interface_mac() {
  local network_interface="$1"
  cat "/sys/class/net/$network_interface/address"
}

# gen persistent net rule
gen_persistent_net_rule() {
  local network_interface="$1"
  local mac="$(network_interface_mac "$network_interface")"
  printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL=="eth*", NAME="%s"\n' "$mac" "$network_interface"
}

# gen persistent net rules
gen_persistent_net_rules() {
  echo "### $COMPANY installimage"
  echo
  while read network_interface; do
    gen_persistent_net_rule "$network_interface"
  done < <(physical_network_interfaces)
}

# setup persistent net rules
setup_persistent_net_rules() {
  local persistent_net_rules_file='/etc/udev/rules.d/70-persistent-net.rules'
  debug "# setting up $persistent_net_rules_file"
  gen_persistent_net_rules > "$FOLD/hdd/$persistent_net_rules_file"
}

# setup network config
setup_network_config_new() {
  debug '# setup network config'

  case "$IAM" in
    centos)
      setup_etc_sysconfig_network
      setup_etc_sysconfig_network_scripts_centos
    ;;
    suse) setup_etc_sysconfig_network_scripts_suse;;
    debian|ubuntu) setup_etc_network_interfaces;;
    *) return 1;;
  esac

  if ! use_predictable_network_interface_names; then
    # predictable network interface names are disabled using the net.ifnames=0 kernel parameter
    # disable_predictable_network_interface_names
    setup_persistent_net_rules
  fi
}

# vim: ai:ts=2:sw=2:et
