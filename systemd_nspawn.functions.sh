#!/usr/bin/env bash

#
# systemd_nspawn functions
#
# (c) 2015-2017, Hetzner Online GmbH
#

# systemd_nspawn_booted() { [[ -e "$FOLD/.#hdd.lck" ]]; }
systemd_nspawn_booted() { pkill -0 systemd-nspawn; }

boot_systemd_nspawn() {
  [[ -d "$SYSTEMD_NSPAWN_TMP_DIR" ]] && rm -fr "$SYSTEMD_NSPAWN_TMP_DIR"
  mkdir -p "$SYSTEMD_NSPAWN_TMP_DIR"
  for fifo in {command,in,out,return}.fifo; do
    mkfifo "$SYSTEMD_NSPAWN_TMP_DIR/$fifo"
  done
  {
    echo '#!/usr/bin/env bash'
    echo 'while :; do'
    # shellcheck disable=SC2016
    echo '  command="$(cat /var/lib/systemd_nspawn/command.fifo)"'
    # shellcheck disable=SC2016
    echo '  cat /var/lib/systemd_nspawn/in.fifo | HOME=/root /usr/bin/env bash -c "$command" &> /var/lib/systemd_nspawn/out.fifo'
    echo '  echo $? > /var/lib/systemd_nspawn/return.fifo'
    echo 'done'
  } > "$SYSTEMD_NSPAWN_TMP_DIR/runner"
  chmod +x "$SYSTEMD_NSPAWN_TMP_DIR/runner"
  {
    echo '[Unit]'
    echo '[Service]'
    echo 'ExecStart=/usr/local/bin/systemd_nspawn-runner'
  } > "$SYSTEMD_NSPAWN_TMP_DIR/systemd_nspawn-runner.service"
  systemd-nspawn -b \
    --bind-ro=/etc/resolv.conf:/run/resolvconf/resolv.conf \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/command.fifo:/var/lib/systemd_nspawn/command.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/in.fifo:/var/lib/systemd_nspawn/in.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/out.fifo:/var/lib/systemd_nspawn/out.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/return.fifo:/var/lib/systemd_nspawn/return.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/runner:/usr/local/bin/systemd_nspawn-runner" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/systemd_nspawn-runner.service:/etc/systemd/system/multi-user.target.wants/systemd_nspawn-runner.service" \
    -D "$FOLD/hdd" &> /dev/null &
  until systemd_nspawn_booted && systemd_nspawn_wo_debug : &> /dev/null; do
    sleep 1;
  done
}

systemd_nspawn_wo_debug() {
  if ! systemd_nspawn_booted; then
    systemd-nspawn --bind-ro=/etc/resolv.conf:/run/resolvconf/resolv.conf \
      -D "$FOLD/hdd" -q /usr/bin/env bash -c "$@"
    return $?
  fi
  echo "$@" > "$SYSTEMD_NSPAWN_TMP_DIR/command.fifo"
  if [[ -t 0 ]]; then
    echo -n > "$SYSTEMD_NSPAWN_TMP_DIR/in.fifo"
  else
    cat > "$SYSTEMD_NSPAWN_TMP_DIR/in.fifo"
  fi
  cat "$SYSTEMD_NSPAWN_TMP_DIR/out.fifo"
  return "$(cat "$SYSTEMD_NSPAWN_TMP_DIR/return.fifo")"
}

systemd_nspawn() {
  debug "# systemd_nspawn: $*"
  systemd_nspawn_wo_debug "$@" |& debugoutput
  return "${PIPESTATUS[0]}"
}

poweroff_systemd_nspawn() {
  systemd_nspawn_wo_debug 'systemctl --force poweroff &> /dev/null &'
  while systemd_nspawn_booted; do sleep 1; done
  rm -fr "$FOLD/hdd/"{var/lib/systemd_nspawn,usr/local/bin/systemd_nspawn-runner,etc/systemd/system/multi-user.target.wants/systemd_nspawn-runner.service}
}

# vim: ai:ts=2:sw=2:et
