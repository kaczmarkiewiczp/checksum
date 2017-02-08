#!/bin/bash

DEBUG=true
FILES=()
DIR=""
OUTPUT_FILE=""

function usage() {
	program=(${0//\.\//})
	echo $program
}

function process_args() {
	temp=`getopt -o h --long help -- "$@"`
	eval set --"$TEMP"

	while true; do
		case "$1" in
			-h|--help)
				usage
				exit 0
				;;
			/?)
				usage
				exit 1
				;;
			:)
				usage
				exit 1
				;;
			*)
				echo "Internal error!"
				exit 1
				;;
		esac
	done

	if [ "$#" -ne 3 ]; then
		usage
		exit 1
	fi

	if [ ! -e "$1" ] || [ ! -d $1 ]; then
		echo "$1 does not exists or is not a directory"
		exit 1;
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
		echo -ne "\r\033[K$file\t[$file_num out of $total]"
		if [ $DEBUG = true ]; then
			echo "$file" >> $OUTPUT_FILE
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
