#!/bin/bash

# rhash: recursively scan specified directory for files. Create a hash (md5)
# of all the files and append them to a specified output file

DEBUG=false
FILES=()
DIRECTORIES=()
OUTPUT_FILE=""
FLAG_SORT=true

# prints program usage
function usage() {
	underline="\e[4m"
	norm="\e[0m"
	program=(${0//\.\//})

	echo -en "$program [option...] "
	echo -en "$underline""output file$norm "
	echo -en "$underline""directory...$norm\n"
	echo -en "Options:\n"
	echo -en "  -a, --append\t\tappend to output file instead of overwriting it\n"
	echo -en "  -s, --sort-output\tsort the output file (default behaviour)\n"
	echo -en "  -S, --no-sort\t\tdon't sort the output file\n"
	echo -en "  -h, --help\t\tdisplay this message and quit\n"
}

# process arguments
function process_args() {
	append_output=false
	flag_count=0

	for opt in "${@}"; do
		case $opt in
			-a|--append)
				append_output=true
				((flag_count++))
				;;
			-s|--sort-output)
				flag_sort=true
				((flag_count++))
				;;
			-S|--no-sort)
				flag_sort=false
				;;
			-h|--help)
				usage
				exit 0
				;;
			-*|--*)
				usage
				exit 102
				;;
			*)
				if [ -z $OUTPUT_FILE ]; then
					OUTPUT_FILE="$opt"
				else
					DIRECTORIES+=("$opt")
				fi
				;;
		esac
	done

	# check that output file and at least one directory was specified
	if [ -z $OUTPUT_FILE ] || [ ${#DIRECTORIES[@]} -eq 0 ]; then
		usage
		exit 110
	fi

	# clear file if it doesn't exists and append flag is not specified
	if [ $append_output = false ] && [ -e $OUTPUT_FILE ]; then
		> $OUTPUT_FILE
	fi
}

# get all the files from specified dir and save them into an array
function get_all_files() {
	dir="$1"
	# check if dir is a dir and if it exists
	if [ ! -e "$dir" ] || [ ! -d "$dir" ]; then
		echo "$dir does not exists or is not a directory."
		return
	fi

	for file in $(find "$dir" -type f); do
		FILES+=("$file")
	done
}

# outputs progress of files processed
function output_progress() {
	file="$1"
	file_num="$2"
	total="$3"

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

# hash files in the array of files
function rhash() {
	file_num=1
	total=${#FILES[@]}

	for file in "${FILES[@]}"; do
		output_progress "$file" $file_num $total

		if [ $DEBUG = true ]; then
			sleep 0.1
		else
			md5sum "$file" >> $OUTPUT_FILE
		fi
		((file_num++))
	done
	echo ""
}

function main() {
	start=`date +%s`
	process_args "$@"
	total_files=0
	# go through each dir one-by-one
	for dir in "${DIRECTORIES[@]}"; do
		get_all_files "$dir"
		((total_files+=${#FILES[@]}))
		rhash
	done

	if [ $FLAG_SORT = true ]; then
		sort -k2 "$OUTPUT_FILE" -o "$OUTPUT_FILE"
	fi

	end=`date +%s`
	runtime=$(($end - $start))
	if [ $runtime -lt 3600 ]; then
		runtime=`date -u -d @${runtime} +"%M:%S"`
		echo "Hashed $total_files files in $runtime minutes"
	else
		runtime=`date -u -d @${runtime} +"%T"`
		echo "Hashed $total_files files in $runtime hours"
	fi
}

main "$@"
