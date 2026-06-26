#!/usr/bin/env bash
#
# hana_adhoc_backup.sh
#
# Run an ad-hoc SAP HANA backup as <sid>adm, tail backup.log, and list files
# created during this backup run.
#
# Inputs may be supplied as exported variables:
#
#   export _DBUSER=SYSTEM
#   export _DBPASS='password'
#   export _DBNAME_TARGET=SYSTEMDB
#   export _BACKUPLOC=/backup/adhoc/GHS4DEV
#   export _BACKUPDESC=BEFORE-NOTE-2502252
#   export _SIDADM=hddadm
#
# Or via command-line options:
#
#   ./hana_adhoc_backup.sh \
#     --db-user SYSTEM \
#     --db-pass 'password' \
#     --db-name-target SYSTEMDB \
#     --backup-location /path/to/backup/location \
#     --backup-description PRE_SUM_DOWNTIME \
#     --sid-adm hddadm
#
# Optional:
#   export _HDBSQL_INSTANCE=0
#
# Default:
#   _HDBSQL_INSTANCE=0
#

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"

log() {
  printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

warn() {
  printf '[%(%Y-%m-%d %H:%M:%S)T] WARNING: %s\n' -1 "$*" >&2
}

die() {
  printf '[%(%Y-%m-%d %H:%M:%S)T] ERROR: %s\n' -1 "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [options]

Options:
  --db-user USER
  --db-pass PASSWORD
  --db-name-target DBNAME
  --backup-location PATH
  --backup-description DESCRIPTION
  --sid-adm USER
  --hdbsql-instance NUMBER
  -h, --help

Environment variables accepted:
  _DBUSER
  _DBPASS
  _DBNAME_TARGET
  _BACKUPLOC
  _BACKUPDESC
  _SIDADM
  _HDBSQL_INSTANCE    optional; defaults to 0

Example:
  export _DBUSER=SYSTEM
  export _DBPASS='superSecretPassword'
  export _DBNAME_TARGET=SYSTEMDB
  export _BACKUPLOC=/backup/adhoc
  export _BACKUPDESC=PRE_SUM_DOWNTIME
  export _SIDADM=hddadm

  ./$SCRIPT_NAME
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --db-user)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        _DBUSER="$2"
        shift 2
        ;;
      --db-pass)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        _DBPASS="$2"
        shift 2
        ;;
      --db-name-target)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        _DBNAME_TARGET="$2"
        shift 2
        ;;
      --backup-location)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        _BACKUPLOC="$2"
        shift 2
        ;;
      --backup-description)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        _BACKUPDESC="$2"
        shift 2
        ;;
      --sid-adm)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        _SIDADM="$2"
        shift 2
        ;;
      --hdbsql-instance)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        _HDBSQL_INSTANCE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

require_var() {
  local var_name="$1"
  local value="${!var_name:-}"

  [[ -n "$value" ]] || die "Required variable $var_name is not set or is empty"
}

validate_inputs() {
  require_var _DBUSER
  require_var _DBPASS
  require_var _DBNAME_TARGET
  require_var _BACKUPLOC
  require_var _BACKUPDESC
  require_var _SIDADM

  _HDBSQL_INSTANCE="${_HDBSQL_INSTANCE:-0}"

  [[ "$_HDBSQL_INSTANCE" =~ ^[0-9]+$ ]] || die "_HDBSQL_INSTANCE must be numeric; got: $_HDBSQL_INSTANCE"

  command -v su >/dev/null 2>&1 || die "Required command not found: su"

  getent passwd "$_SIDADM" >/dev/null 2>&1 || die "OS user does not exist: $_SIDADM"

  if [[ ! -d "$_BACKUPLOC" ]]; then
    die "Backup location does not exist from current context: $_BACKUPLOC"
  fi

  if [[ ! -r "$_BACKUPLOC" || ! -x "$_BACKUPLOC" ]]; then
    warn "Current user cannot fully access $_BACKUPLOC; the $_SIDADM user may still be able to."
  fi
}

run_backup_as_sidadm() {
  log "Starting backup as user: $_SIDADM"

  local q_dbuser q_dbpass q_dbname q_backuploc q_desc q_instance
  printf -v q_dbuser '%q' "$_DBUSER"
  printf -v q_dbpass '%q' "$_DBPASS"
  printf -v q_dbname '%q' "$_DBNAME_TARGET"
  printf -v q_backuploc '%q' "$_BACKUPLOC"
  printf -v q_desc '%q' "$_BACKUPDESC"
  printf -v q_instance '%q' "${_HDBSQL_INSTANCE:-0}"

  su - "$_SIDADM" <<EOF
set -Eeuo pipefail
IFS=\$'\n\t'

_DBUSER=$q_dbuser
_DBPASS=$q_dbpass
_DBNAME_TARGET=$q_dbname
_BACKUPLOC=$q_backuploc
_BACKUPDESC=$q_desc
_HDBSQL_INSTANCE=$q_instance

log() { printf '[%(%F %T)T] %s\n' -1 "\$*"; }
die() { echo "ERROR: \$*" >&2; exit 1; }

monitor_backup_log() {
  local log_file="\$1"
  local pid="\$2"

  [[ -r "\$log_file" ]] || return 0

  set +e
  set +o pipefail

  tail -n0 -F "\$log_file" --pid="\$pid" | stdbuf -oL grep ' BACKUP '

  set -e
  set -o pipefail
}

# --- Determine DB + trace location ---
if [[ "\$_DBNAME_TARGET" == "SYSTEMDB" ]]; then
  _DN="SYSTEMDB"
  _TL="\${SAP_RETRIEVAL_PATH}/trace"
else
  _DN="\$_DBNAME_TARGET"
  _TL="\${SAP_RETRIEVAL_PATH}/trace/DB_\$_DBNAME_TARGET"
fi

[[ -n "\${SAP_RETRIEVAL_PATH:-}" ]] || die "SAP_RETRIEVAL_PATH not set"

backup_log="\$_TL/backup.log"

_MARKER="/tmp/backup_start_\${_DN}_\$\$"
touch "\$_MARKER"

start=\$(date +%s)

prefix="\${_BACKUPLOC}/\${HOSTNAME,,}-\${_DN}-\${_BACKUPDESC}-\$(date +%Y-%m-%d_%H%M)"

log "Targeting \$_DN"
log "Backup prefix: \$prefix"

hdbsql -u "\$_DBUSER" -p "\$_DBPASS" -i "\$_HDBSQL_INSTANCE" -d "\$_DN" \
  "BACKUP DATA ALL USING FILE ('\$prefix')" &
pid=\$!

monitor_backup_log "\$backup_log" "\$pid"

set +e
wait "\$pid"
rc=\$?
set -e

(( rc == 0 )) || die "hdbsql failed: \$rc"

echo -e "\nFiles created this run:"
find "\$_BACKUPLOC" -type f -name "*\$_DN*" -newer "\$_MARKER" -exec ls -lh {} +

rm -f "\$_MARKER"

sec=\$(( \$(date +%s) - start ))
printf "\nTotal Backup Time: %02dh:%02dm:%02ds\n\n" \
  \$((sec/3600)) \$((sec%3600/60)) \$((sec%60))
EOF
}

main() {
  parse_args "$@"
  validate_inputs
  run_backup_as_sidadm
}

main "$@"