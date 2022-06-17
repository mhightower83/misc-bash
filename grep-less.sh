#!/bin/bash
#
#   Copyright 2017 M Hightower
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# grep-less.sh
#
# WIP

# set config file
DIALOGRC=/home/mhightow/.dialogrc.dark
if [[ ! -s "$DIALOGRC" ]]; then
  unset DIALOGRC
fi

namesh="${0##*/}"
cmd_args="$@"

unset ignore_case
if [[ "-" == "${1:0:1}" ]]; then
  grep_pattern=$(echo -n "${2}" | sed 's/(/\\(/g; s/)/\\)/g' )
  if [[ "-i" == "${1:0:2}" ]]; then
    ignore_case="-i"
  fi
else
  grep_pattern=$(echo -n "${1}" | sed 's/(/\\(/g; s/)/\\)/g' )
fi

function print_help() {
  cat <<EOF
Recursive search for files with matching patterns. Use dialog to present
resulting lines containing matches. From the menu you can view/diff/edit.

$namesh pattern [ [-iv] pattern2 ] [ [-iv] pattern3 ]
EOF
}

declare -a filehistory
function add2filehistory() {
  filehistory[${#filehistory[@]}]="$1"
}

function statusfile2() {
  # prop=$( stat --print="%.19y %8s %h" "${1}" )
  # sha1sum $1 | sed "s/  /\t${prop}\t/"
  sha1sum "$1" | cut -d' ' -f1 | tr "\n" "\t"
  stat --print="%.19y %8s %h\t%N\n" "${1}"
}
function statusfile() {
  sha1sum "$1" | sed 's: .*/:  :' | tr "\n" " "
  stat --print=" %.19y %8s %h  %N\n" "${1}"
}
export -f statusfile

grep_tree() {
  search_tree_output=$(mktemp)
  search_tree_output_in=$(mktemp)
  unset options
  if [[ "-" == "${1:0:1}" ]]; then
    options="${1:1}"
    shift
  fi
  if [[ -z "${1}" ]]; then
    return
  fi
  grep -rRnIT${options} -Dskip "${1}" 2>/dev/null >${search_tree_output}
  shift
  while [ -n "${1}" ]; do
    mv ${search_tree_output} ${search_tree_output_in}
    if [[ "-" == "${1:0:1}" ]]; then
      if [[ -n "${2}" ]]; then
        grep ${1} "${2}" <${search_tree_output_in} 2>/dev/null >${search_tree_output}
        shift
      else
        mv ${search_tree_output_in} ${search_tree_output}
        echo "${0}:1: stray command line option \"${1}\" without pattern" >>${search_tree_output}
      fi
    else
      grep "${1}" <${search_tree_output_in} 2>/dev/null >${search_tree_output}
    fi
    shift
  done
  [ -f $search_tree_output ] && cat ${search_tree_output}
  [ -f $search_tree_output ] && rm $search_tree_output
  [ -f ${search_tree_output_in} ] && rm ${search_tree_output_in}
}

function do_again() {
  #launch the dialog, get the output in the menu_output file
  # --no-cancel
  # --column-separator "|-|-|-|"
  dialog \
    --no-collapse \
    --clear \
    --extra-label "Diff Previous" \
    --extra-button \
    --help-label "Edit" \
    --help-button \
    --cancel-label "Exit" \
    --ok-label "View" \
    --column-separator "|-|-|-|" \
    --title "Recursive Grep Results" \
    --default-item $menu_item \
    --menu "Pick a file to view" 0 0 0 \
    --file $menu_config 2>$menu_output

  rc=$?

  # recover the output value
  menu_item=$(<$menu_output)
  echo "$menu_item"

  if [[ $rc == 0 ]]; then
    # the Yes or OK button.
    # we use this for view/less
    :
  elif [[ $rc == 2 ]]; then
    # --help-button was pressed.
    # Repurpose for edit, skip "HELP " to get to the menu number
    menu_item=${menu_item#* }
  elif [[ $rc == 3 ]]; then
    # --extra-button was pressed.
    # We use this for diff
    :
  else
    # Exit/No/Cancel, ESC and everything else
    return $rc
  fi

  # recover the associated line in the output of the command
  # Format "* branch/tdescription"
  entry=$(sed -n "${menu_item}p" $command_output)

  #replace echo with whatever you want to process the chosen entry
  echo "You selected: $entry"
  jumpto=$( echo "$entry" | cut -d':' -f2 | xargs )
  file=$( echo "$entry" | cut -d':' -f1 )
  file=$( realpath "$file" )

  if [[ $rc == 0 ]]; then
    # echo -n "$file" | xclip -selection clipboard
    add2filehistory "$file"
    less +$jumpto -p"${grep_pattern}" $ignore_case "$file"
    lastfile="$file"
  elif [[ $rc == 3 ]]; then
    if [[ -n "${lastfile}" ]]; then
      add2filehistory "$file"
      diff -w "${lastfile}" "${file}" | less
    fi
    lastfile="${file}"
  elif [[ $rc == 2 ]]; then
    add2filehistory "$file"
    gedit "$file" +$jumpto
    # less $menu_output
    lastfile="$file"
  fi
  return $rc
}

function make_menu() {
  #replace ls with what you want
  # search_tree "--no-color" | sed 's/ *$//g' >$command_output
  grep_tree "$@" |
    sed '/^.git/d' |
    sed 's/\t/|-|-|-|/' |
    sed 's/\\/\\\\/g' |
    sed 's/"/\\"/g' >$command_output

  if [[ -s $command_output ]]; then
    #build a dialog configuration file
    cat $command_output |
      awk '{print NR " \"" $0 "\""}' |
      tr "\n" " " >$menu_config
  else
    return 1
  fi
  return 0
}

################################################################################
# main - grep-less.sh
#

# From https://unix.stackexchange.com/a/70868

#make some temporary files
command_output=$(mktemp)
menu_config=$(mktemp)
menu_output=$(mktemp)
lastfile=""
menu_item=1

#make sure the temporary files are removed even in case of interruption
trap "rm $command_output;
      rm $menu_output;
      rm $menu_config;" SIGHUP SIGINT SIGTERM

if [[ -z "${1}" ]]; then
  print_help
  exit 255
fi

if make_menu "$@"; then
  while :; do
    do_again
    rc=$?
    if [[ $rc == 0 ]]; then     # OK
      :
    elif [[ $rc == 1 ]]; then   # Cancel
      clear
      break
    elif [[ $rc == 2 ]]; then   # Help
      :
    elif [[ $rc == 3 ]]; then   # Extra
      :
    else
      clear
      echo "Error: $rc"
      cat $menu_output
      break
    fi
  done
  echo "$namesh "${cmd_args[@]}
  echo " grep_pattern: \"${grep_pattern}\""
  printf '  %s\n' "${filehistory[@]}"
else
  echo "Empty search results for:"
  echo "  $namesh "${cmd_args[@]}
fi

#clean the temporary files
[ -f $command_output ] && rm $command_output
[ -f $menu_output ] && rm $menu_output
[ -f $menu_config ] && rm $menu_config