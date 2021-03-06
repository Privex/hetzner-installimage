#!/usr/bin/env bash

#
# cpanel functions
#
# (c) 2008-2016, Hetzner Online GmbH
#

# is_cpanel_install()
# is this a cpanel install?
is_cpanel_install() {
  [[ "${OPT_INSTALL,,}" == cpanel ]] || [[ "${IMAGENAME,,}" == *cpanel ]]
}

# cpanel_setup_mainip()
cpanel_setup_mainip() {
  local mainip_file=/var/cpanel/mainip

  debug "# setting up ${mainip_file}"
  echo -n "${IPADDR}" > "${FOLD}/hdd/${mainip_file}"
  debug "set up ${mainip_file}"
}

# cpanel_setup_wwwacct_conf()
cpanel_setup_wwwacct_conf() {
  local wwwacct_conf; wwwacct_conf=/etc/wwwacct.conf

  debug "# setting up ${wwwacct_conf}"
  sed --expression='/^ADDR\s/d' \
    --expression='/^HOST\s/d' \
    --expression='/^NS[[:digit:]]*\s/d' \
    --in-place "${FOLD}/hdd/${wwwacct_conf}"
  {
    echo
    echo "### ${COMPANY} installimage"
    echo "ADDR ${IPADDR}"
    echo "HOST ${NEWHOSTNAME}"
    echo "NS ${AUTH_DNS1}"
    echo "NS2 ${AUTH_DNS2}"
    echo "NS3 ${AUTH_DNS3}"
    echo 'NS4'
  } >> "${FOLD}/hdd/${wwwacct_conf}"
  debug "set up ${wwwacct_conf}"
}

# randomize_cpanel_passwords()
randomize_cpanel_passwords() {
  debug '# randomizing cpanel passwords'

  # passwords of the following database users must be randomized
  # * root
  # * cphulkd
  # * eximstats
  # * leechprotect
  # * modsec
  # * roundcube

  local root_password; root_password=$(generate_password)
  local cphulkd_password; cphulkd_password=$(generate_password)
  local eximstats_password; eximstats_password=$(generate_password)
  local leechprotect_password; leechprotect_password=$(generate_password)
  local roundcube_password; roundcube_password=$(generate_password)

  reset_mysql_root_password "$root_password" || return 1

  set_mysql_password cphulkd "${cphulkd_password}" || return 1
  set_mysql_password eximstats "${eximstats_password}" || return 1
  set_mysql_password leechprotect "${leechprotect_password}" || return 1
  set_mysql_password roundcube "${roundcube_password}" || return 1

  echo "${cphulkd_password}" > "${FOLD}/hdd/var/cpanel/hulkd/password"
  echo "${eximstats_password}" > "${FOLD}/hdd/var/cpanel/eximstatspass"
  echo "${leechprotect_password}" > "${FOLD}/hdd/var/cpanel/leechprotectpass"
  echo "${roundcube_password}" > "${FOLD}/hdd/var/cpanel/roundcubepass"

  systemd_nspawn /usr/local/cpanel/bin/updateeximstats || return 1
  systemd_nspawn /usr/local/cpanel/bin/updateleechprotect || return 1
  systemd_nspawn /usr/local/cpanel/bin/modsecpass || return 1
  systemd_nspawn /usr/local/cpanel/bin/update-roundcube --force || return 1

  poweroff_systemd_nspawn

  debug 'randomized cpanel passwords'
}

# setup_cpanel()
setup_cpanel() {
  debug '# setting up cpanel'
  cpanel_setup_mainip
  cpanel_setup_wwwacct_conf
  randomize_cpanel_passwords || return 1
  debug 'set up cpanel'
}

# install_cpanel()
install_cpanel() {
  local temp_file="/cpanel-installer"

  debug "# downloading cpanel installer ${CPANEL_INSTALLER_SRC}/${IMAGENAME}"
  curl --location --output "${FOLD}/hdd/${temp_file}" --silent --write-out '%{response_code}' "${CPANEL_INSTALLER_SRC}/${IMAGENAME}" \
    | grep --quiet 200 || return 1
  chmod a+x "${FOLD}/hdd/${temp_file}"
  debug 'downloaded cpanel installer'

  debug '# installing cpanel'
  local command="${temp_file} --force"
  if installed_os_uses_systemd && ! systemd_nspawn_booted; then
    boot_systemd_nspawn || return 1
  fi
  execute_command "${command}" || return 1
  systemd_nspawn_booted && poweroff_systemd_nspawn

  debug '# setting up cpanel'
  cpanel_setup_wwwacct_conf
  debug 'set up cpanel'
  debug 'installed cpanel'
}

# vim: ai:ts=2:sw=2:et
