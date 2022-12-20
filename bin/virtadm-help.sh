#!/usr/bin/env bash

function _virtadm_help() {
  echo "NAME:"
  echo "   ${progname} - A wrapper for QEMU/KVM written in Bash"
  echo ""
  echo "USAGE:"
  echo "   ${progname}: [global options] command [command options] [ arguments...]"
  echo ""
  echo "COMMAND:"
  echo "   check          Check if QEMU/KVM is installed and configured"
  echo "   create         Create a new VM"
  echo "   help           Show a list of commands"
  echo ""
  echo "GLOBAL OPTIONS:"
  echo "   --help,-h      Show help"
  echo ""
}

export _virtadm_help
