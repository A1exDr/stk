#!/usr/bin/env bash
#Getting a CDR file from the PBX using SFTP and transform it to the approtiate format.
#
#set -eu
#Configs
PBX_ADDRESS='x.x.x.x'
PBX_USERNAME=''
BILL_CDR_PATH="/app/asr_billing/var/cdrs"
PBX_CDR_PATH="/ATS/TARIF/CDR"
TMP_DIR="/tmp/cdr_process"
#Flags
LOG_SYSLOG=1
LOG_CONSOLE=1
LOG_FACILITY="user"

#Format colors
NO_FORMAT="\033[0m"
F_BOLD="\033[1m"
C_WHITE="\033[38;5;15m"
C_TEAL="\033[48;5;6m"
C_RED="\033[48;5;9m"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

log() {
    EXCODE=$1
    MESSAGE=$2
    if [ "$EXCODE" -eq 0 ]; then
        [ "$LOG_CONSOLE" -eq "1" ] && printf "${F_BOLD}${C_WHITE}${C_TEAL}OK: ${NO_FORMAT} %s\n" "${MESSAGE}"
        [ "$LOG_SYSLOG" -eq "1" ] && logger -p "${LOG_FACILITY}.info" "${MESSAGE}"
    else
        [ "$LOG_CONSOLE" -eq "1" ] && printf "${F_BOLD}${C_WHITE}${C_RED}ERROR: ${NO_FORMAT} %s\n" "${MESSAGE}"
        [ "$LOG_SYSLOG" -eq "1" ] && logger -p "${LOG_FACILITY}.err" "${MESSAGE}"
        exit 1
    fi

}

cleanup (){
  rm -rf $TMP_DIR
  [ -n "$agent_pid" ] && kill "$agent_pid"
}

genkey() {
  log "0" "Couldn't find the SSH key, generating a new one..."
  if ssh-keygen -q -t ed25519 -f "${SCRIPT_DIR}/cdr_ssh.key" -N ""; then
    log "0" "The key was successfully generated, please put the public part into the 'authorized_keys' file on the PBX and rerun the script"
    exit 0
  else
    log "1" "Can't generate a new SSH key"
    exit 1
  fi
}

runagent(){
  eval "$(ssh-agent -s)"
  agent_pid="$SSH_AGENT_PID"
}

trap cleanup 1 2 3 6
today=$(date -d "yesterday 13:00" '+%d_%m_%Y')
cdr_file_name="cdr_log_${today}.log"
ready_file_name="${TMP_DIR}/${cdr_file_name}.ready"

[ ! -d $TMP_DIR ] && mkdir $TMP_DIR
[ ! -e "${SCRIPT_DIR}/cdr_ssh.key" ] && genkey
[ -z "$SSH_AUTH_SOCK" ] && runagent

ssh-add "${SCRIPT_DIR}/cdr_ssh.key" || log "1" "Couldn't add the key to ssh-agent, exiting.."

if scp_error=$(scp -o "StrictHostKeyChecking=no" "${PBX_USERNAME}@${PBX_ADDRESS}:${PBX_CDR_PATH}/${cdr_file_name}" $TMP_DIR/ 2>&1); then
  if (sed -e 's/^.//g' < "${TMP_DIR}/${cdr_file_name}" | awk '{printf("%s;%s;%s;%s;%s %s;%s;%s\n", $1, $2, $3, $4, $5, $6, $7, $8) }' > "$ready_file_name"); then
        cp "$ready_file_name" $BILL_CDR_PATH/
        log "0" "File ${cdr_file_name} was successfully processed"
    else
        log "1" "There was an error processing the CDR file"
    fi
  else
    log "1" "Couldn't get the file: ${scp_error}"
fi

cleanup
