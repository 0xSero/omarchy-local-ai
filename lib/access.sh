# Access: can Local AI start a model on this machine, and if not, what is the one thing to do about it.
#
# This file is the only place that decides. The panel, `run` and the installer all ask here, so a state can never
# show a message with no way out, and "ready" cannot mean one thing to the installer and another to a start.
# Definitions only: sourcing it changes nothing.
#
# readiness prints "<state><TAB><message>"; the state is one of READINESS_STATES:
#   ready        a model can start
#   needs-setup  the account or the NVIDIA runtime needs setup; the panel offers Set up Local AI
#   docker-down  set up, but Docker does not answer; it clears when Docker does, and the panel keeps checking
#   unsupported  this Omarchy has no Sudoless Docker helper; it clears when Omarchy is updated
#
# A login carries the groups it began with, so one that began before setup has the docker group only in /etc/group.
# docker_group_reexec runs the program again under `newgrp docker`: no root, no password, and the socket never needs a
# permission of its own for this account.

# the test that every state has a panel page reads this list
# shellcheck disable=SC2034
READINESS_STATES=(ready needs-setup docker-down unsupported)

docker_socket() { printf '%s' "${OMARCHY_DOCKER_SOCKET:-/var/run/docker.sock}"; }

# Omarchy's flag reads backwards: --configured is true while Docker still needs sudo.
sudoless_docker_on() { ! omarchy-sudo-docker --configured; }

# this process can write the daemon's socket
docker_reachable() { [[ -w $(docker_socket) ]]; }

# in_docker_group: /etc/group lists the account (or it is the account's primary group), whatever groups this login began with
in_docker_group() {
  local user line gid
  user=$(id -un)
  line=$(getent group docker) || return 1
  gid=$(cut -d: -f3 <<<"$line")
  [[ ,$(cut -d: -f4 <<<"$line"), == *,"$user",* ]] || [[ $(getent passwd "$user" | cut -d: -f4) == "$gid" ]]
}

# runtimes_have_nvidia: `docker info --format '{{json .Runtimes}}'` on stdin. The one definition of "the NVIDIA
# container runtime is there" for setup, run and the panel alike; the toolkit also registers nvidia-cdi and nvidia-legacy.
runtimes_have_nvidia() { jq -e 'keys | any(test("nvidia"))' >/dev/null 2>&1; }

# readiness_line <state> [message]
readiness_line() { printf '%s\t%s\n' "$1" "${2:-}"; }

readiness() {
  local sock info
  sock=$(docker_socket)
  command -v omarchy-sudo-docker >/dev/null || { readiness_line unsupported "This Omarchy has no Sudoless Docker helper; update Omarchy"; return; }
  sudoless_docker_on || { readiness_line needs-setup; return; }
  # a setup that did not finish is not done until it does; the panel shows its error beside the button
  [[ ! -s ${STATE:-/nonexistent}/setup-error ]] || { readiness_line needs-setup; return; }
  if ! docker_reachable; then
    in_docker_group || { readiness_line needs-setup; return; }
    if [[ -e $sock ]]; then
      readiness_line docker-down "This login cannot use Docker's socket, though the account is in the docker group"
    else
      readiness_line docker-down "Docker is not running"
    fi
    return
  fi
  info=$(docker info --format '{{json .Runtimes}}' 2>/dev/null) || { readiness_line docker-down "Docker is not answering"; return; }
  if omarchy-hw-nvidia && ! runtimes_have_nvidia <<<"$info"; then readiness_line needs-setup; return; fi
  readiness_line ready
}

# require_ready: refuse a start unless a model can start, in the words the panel uses. Needs die from the caller.
require_ready() {
  local state msg
  IFS=$'\t' read -r state msg < <(readiness)
  case $state in
  ready) ;;
  needs-setup) die "Local AI is not set up yet: choose Set up Local AI" ;;
  *) die "${msg:-Docker is not ready}" ;;
  esac
}

# docker_group_reexec <program> [args...]: when this login lacks the docker group it will get at the next login, run the
# program again under it. Once: LOCAL_AI_REEXEC stops a second try when the socket is still out of reach.
docker_group_reexec() {
  [[ -z ${LOCAL_AI_REEXEC:-} ]] || return 0
  [[ -e $(docker_socket) ]] || return 0 # no socket: Docker is not running, and no group changes that
  ! docker_reachable || return 0
  in_docker_group || return 0
  command -v newgrp >/dev/null || return 0
  export LOCAL_AI_REEXEC=1 SHELL=/bin/bash
  exec newgrp docker <<<"exec $(printf '%q ' "$@")"
}
