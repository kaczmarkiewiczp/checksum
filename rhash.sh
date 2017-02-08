#!/bin/bash

DEBUG=true
FILES=()
DIR=""
OUTPUT_FILE=""

function usage() {
	program=(${0//\.\//})
	echo"$program [-h] directory output_file"
}

function process_args() {

	while getopts ":h" opt; do
		case $opt in
			h)
				usage
				exit 101
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

	if [ ! -e "$1" ] || [ ! -d $1 ]; then
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

function rhash() {
	file_num=1
	total=${#FILES[@]}
	
	for file in "${FILES[@]}"; do
		term_w=`tput cols`

		echo -ne "\r\033[K$file\t[$file_num out of $total]"
		if [ $DEBUG = true ]; then
			sleep 1
		else
			md5sum "$file" >> $OUTPUT_FILE
		fi
		((file_num++))
	done
	echo ""
}

process_args $@
get_all_files
rhash
