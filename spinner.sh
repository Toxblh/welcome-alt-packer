# Source: https://github.com/tteck/Proxmox/blob/main/vm/haos-vm.sh

SPINNER_PID=""

function spinner() {
  printf "\e[?25l"
  spinner="◐◓◑◒"
  spin_i=0
  while true; do
    printf "\b%s" "${spinner:spin_i++%${#spinner}:1}"
    sleep 0.1
  done
}

function spinner_start() {
  spinner &
  SPINNER_PID=$!
}

function spinner_stop() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID > /dev/null; then kill $SPINNER_PID > /dev/null; fi
  printf "\e[?25h"
}