#!/usr/bin/env bash
set -eo pipefail

function main {
  common::initialize
  common::parse_cmdline "$@"
  terraform_fmt_ "${ARGS[*]}" "${FILES[@]}"
}

function common::initialize {
  local SCRIPT_DIR
  # get directory containing this script
  SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

  # source getopt function
  # shellcheck source=lib_getopt
  . "$SCRIPT_DIR/lib_getopt"
}

function common::parse_cmdline {
  # common global arrays.
  # Populated via `common::parse_cmdline` and can be used inside hooks' functions
  declare -g -a ARGS=() FILES=() HOOK_CONFIG=()

  local argv
  argv=$(getopt -o a:,h: --long args:,hook-config: -- "$@") || return
  eval "set -- $argv"

  for argv; do
    case $argv in
      -a | --args)
        shift
        ARGS+=("$1")
        shift
        ;;
      -h | --hook-config)
        shift
        HOOK_CONFIG+=("$1;")
        shift
        ;;
      --)
        shift
        FILES=("$@")
        break
        ;;
    esac
  done
}

function terraform_fmt_ {
  local -r args="$1"
  shift 1
  local -a -r files=("$@")
  # consume modified files passed from pre-commit so that
  # hook runs against only those relevant directories
  local index=0
  for file_with_path in "${files[@]}"; do
    file_with_path="${file_with_path// /__REPLACED__SPACE__}"

    dir_paths[index]=$(dirname "$file_with_path")
    # TODO Unique part
    if [[ "$file_with_path" == *".tfvars" ]]; then
      tfvars_files+=("$file_with_path")
    fi
    #? End for unique part
    ((index += 1))
  done

  # preserve errexit status
  shopt -qo errexit && ERREXIT_IS_SET=true
  # allow hook to continue if exit_code is greater than 0
  set +e
  local final_exit_code=0

  # run hook for each path
  for dir_path in $(echo "${dir_paths[*]}" | tr ' ' '\n' | sort -u); do
    dir_path="${dir_path//__REPLACED__SPACE__/ }"
    pushd "$dir_path" > /dev/null

    per_dir_hook_unique_part "$args" "$dir_path"

    local exit_code=$?
    if [ "$exit_code" != 0 ]; then
      final_exit_code=$exit_code
    fi

    popd > /dev/null
  done

  # TODO: Unique part
  # terraform.tfvars are excluded by `terraform fmt`
  for tfvars_file in "${tfvars_files[@]}"; do
    tfvars_file="${tfvars_file//__REPLACED__SPACE__/ }"

    terraform fmt "${ARGS[@]}" "$tfvars_file"
    local exit_code=$?
    if [ "$exit_code" != 0 ]; then
      final_exit_code=$exit_code
    fi
  done
  #? End for unique part
  # restore errexit if it was set before the "for" loop
  [[ $ERREXIT_IS_SET ]] && set -e
  # return the hook final exit_code
  exit $final_exit_code

}

function per_dir_hook_unique_part {
  # common logic located in common::per_dir_hook
  local -r args="$1"
  local -r dir_path="$2"

  # pass the arguments to hook
  # shellcheck disable=SC2068 # hook fails when quoting is used ("$arg[@]")
  terraform fmt ${args[@]}

  # return exit code to common::per_dir_hook
  local exit_code=$?
  return $exit_code
}

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
