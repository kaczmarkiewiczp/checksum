#!/bin/bash

# TODO (2) leave comments everywhere

DEBUG=false
FILES=()
DIR=""
OUTPUT_FILE=""

function usage() {
	underline="\e[4m"
	norm="\e[0m"
	program=(${0//\.\//})

	echo -en "$program [-h] "
	echo -en "$underline""directory$norm "
	echo -en "$underline""output file$norm"
	echo ""
}

function process_args() {

	while getopts ":h" opt; do
		case $opt in
			h)
				usage
				exit 0
				;;
			\?)
				usage
				exit 102
				;;
		esac
	done

	if [ "$#" -ne 2 ]; then
		usage
		exit 110
	fi

	if [ ! -e "$1" ] || [ ! -d "$1" ]; then
		echo "$1 does not exists or is not a directory"
		exit 111;
	fi

	DIR=$1
	OUTPUT_FILE=$2
}

function get_all_files() {
	for file in $(find $DIR -type f); do
		FILES+=($file)
	done
}

function output_progress() {
	file=$1
	file_num=$2
	total=$3

	term_w=`tput cols`
	prefix="$file"
	postfix=" [$file_num out of $total]"
	length=$(( ${#prefix} + ${#postfix}))

	if [ $length -gt $term_w ]; then
		aval_w=$(( $term_w - ${#postfix} - 5))
		remove=$(( ${#prefix} - $aval_w))
		first_half="${prefix:0:$((${#prefix} / 2))}"
		first_half="${first_half::-$(($remove / 2))}"

		second_half="${prefix:$((${#prefix} / 2)):${#prefix}}"
		second_half="${second_half:$(($remove / 2))}"

		prefix="$first_half...$second_half"
	fi

	aval_w=$((${#prefix} + ${#postfix}))
	aval_w=$(($term_w - $aval_w - 1))
	
	if [ $aval_w -gt 1 ]; then
		padding=`for ((i=1; i<=$aval_w; i++)); do echo -n " "; done`
	else
		padding=""
	fi

	echo -ne "\r\033[K$prefix$padding$postfix"
}

function rhash() {
	file_num=1
	total=${#FILES[@]}

	for file in "${FILES[@]}"; do
		output_progress $file $file_num $total

		if [ $DEBUG = true ]; then
			sleep 1
		else
			md5sum "$file" >> $OUTPUT_FILE
		fi
		((file_num++))
	done
	echo ""
}

process_args "$@"
get_all_files
rhash
