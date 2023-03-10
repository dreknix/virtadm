#!/usr/bin/env bash

function _virtadm_help() {
  echo "NAME:"
  echo "   ${progname:-virtadm} - A wrapper for QEMU/KVM written in Bash"
  echo ""
  echo "USAGE:"
  echo "   ${progname}: [global options] command [command options] [ arguments...]"
  echo ""
  echo "COMMAND:"
  echo "   check          Check if QEMU/KVM is installed and configured"
  echo "   cleanup        Eject boot CDROMs and remove created ISOs"
  echo "   connect        Connect to running VM"
  echo "   create         Create a new VM"
  echo "   destroy        Shutdown and delete a VM"
  echo "   list           List all VMs"
  echo "   ssh            Start a SSH session into VM"
  echo "   help           Show a list of commands"
  echo ""
  echo "GLOBAL OPTIONS:"
  echo "   --help,-h      Show help"
  echo ""
}

export _virtadm_help
