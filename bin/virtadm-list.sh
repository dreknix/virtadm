#!/usr/bin/env bash

function _virtadm_list() {

  for vm_name in $(virsh list --all | awk 'FNR>2{print $2}')
  do
    printf "%- 25s" "${vm_name}"
    local state
    state="$(virsh domstate "${vm_name}")"
    case "${state}" in
      "running")
        tput setaf 2
        ;;
      "shut off")
        tput setaf 3
        ;;
      *)
        tput setaf 9
        ;;
    esac
    printf "%- 10s"  "${state}"
    tput sgr0
    if [ "${state}" == "running" ]
    then
      if ! virsh guestinfo "${vm_name}" --os &> /dev/null
      then
        tput setaf 9
        printf "%- 35s"  "guest-agent is missing"
        tput sgr0
      else
        printf "%- 35s"  "$(virsh guestinfo "${vm_name}" --os | grep "^os.version " | cut -c23-)"
      fi
      if ! virsh domdisplay "${vm_name}" &> /dev/null
      then
        tput setaf 3
        printf "%- 35s"  "no graphical display"
        tput sgr0
      else
        printf "%- 35s"  "$(virsh domdisplay "${vm_name}")"
      fi
    fi
    printf "\n"
  done

}

export _virtadm_list
