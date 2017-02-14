#!/bin/bash
# rhash: recursively scan specified directory for files. Create a hash (md5)
# of all the files and append them to a specified output file
#
# TODO: add flag for printing hashes to stdout
# TODO: change output if execution time >=86,400 (24 hours)
# TODO: change output if execution time is exactly one minutes or hour

DEBUG=false
HASH_COMMAND=""
ALGORITHM="md5"
FILES=""
DIRECTORIES=()
OUTPUT_FILE=""
FLAG_SORT=true
FLAG_SIMP_OUT=false

# prints program usage
function usage() {
	underline="\e[4m"
	norm="\e[0m"
	program=$(basename $0)

	echo -en "$program [option...] "
	echo -en "$underline""output file$norm "
	echo -en "$underline""directory...$norm\n"
	echo -en "Options:\n"
	echo -en "  -a, --append\t\tappend to output file instead of overwriting it\n"
	echo -en "  -s, --sort-output\tsort the output file (default behaviour)\n"
	echo -en "  -S, --no-sort\t\tdon't sort the output file\n"
	echo -en "  --simple-output\tdo not create a BSD-style checksum\n"
	echo -en "  -[algorithm], -A [algorithm], --algorithm=[algorithm]\n"
	echo -en "\t\t\tuses the specified algorithm.\n"
	echo -en "\t\t\tThe following options are available:\n"
	echo -en "\t\t\t  md5\n\t\t\t  sha1\n\t\t\t  sha224\n\t\t\t  sha256\n"
	echo -en "\t\t\t  sha384\n\t\t\t  sha512\n"
	echo -en "  -h, --help\t\tdisplay this message and quit\n"
}

# process arguments
function process_args() {
	append_output=false
	expect_a=false
	flag_count=0

	for opt in "${@}"; do
		if [ $expect_a = true ]; then
			opt="-$opt"
		fi

		case $opt in
			-a|--append)
				append_output=true
				((flag_count++))
				;;
			-s|--sort-output)
				FLAG_SORT=true
				((flag_count++))
				;;
			-S|--no-sort)
				FLAG_SORT=false
				;;
			-md5|-sha1|-sha224|-sha256|-sha384|-sha512)
				ALGORITHM=${opt:1}
				;;
			-A)
				ALGORITHM=""
				expect_a=true
				continue
				;;
			--algorithm=*)
				ALGORITHM=$(echo $opt | cut -d '=' -f2)
				if [ -z $ALGORITHM ]; then
					expect_a=true;
					continue
				elif 	[ $ALGORITHM = "md5" ] || 
					[ $ALGORITHM = "sha256" ] ||
					[ $ALGORITHM = "sha384" ] ||
					[ $ALGORITHM = "sha512" ]; then
					: # don't do anything
				else
					usage
					exit 104
				fi
				;;
			--simple-output)
				FLAG_SIMP_OUT=true
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

		if [ $expect_a = true ]; then
			if [ -z ALGORITHM ]; then
				usage
				exit 103
			fi
			expect_a=false
		fi
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

# creates appropriate hash command
function create_hash_command() {
	HASH_COMMAND=$ALGORITHM
	HASH_COMMAND+="sum "
	
	if [ $FLAG_SIMP_OUT = false ]; then
		HASH_COMMAND+="--tag "
	fi
}

# get all the files from specified dir and save them into an array
function get_all_files() {
	dir="$1"
	FILES="" # clear variable

	# check if dir is a dir and if it exists
	if [ ! -e "$dir" ] || [ ! -d "$dir" ]; then
		echo "$dir does not exists or is not a directory."
		return
	fi

	FILES=$(find "$dir" -type f)
}

# outputs progress of files processed
function output_progress() {
	file="$1"
	file_num="$2"
	total="$3"

	term_w=$(tput cols)
	prefix="$file"
	postfix=" [$file_num of $total]"
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
		padding=$(for ((i=1; i<=$aval_w; i++)); do echo -n " "; done)
	else
		padding=""
	fi

	echo -ne "\r\033[K$prefix$padding$postfix"
}

# hash files in the array of files
function rhash() {
	file_num=1
	total=$(echo "$FILES" | wc -l)

	while read file; do
		output_progress "$file" $file_num $total

		if [ $DEBUG = true ]; then
			sleep 0.05
			$(echo "HASHED  $file" >> $OUTPUT_FILE)
		else
			$HASH_COMMAND "$file" >> $OUTPUT_FILE
		fi
		((file_num++))
	done <<< "$FILES"
	echo ""
}

# prints execution time
function print_runtime() {
	if [ $1 -lt 60 ]; then
		runtime=$(date -u -d @${1} +"%S")
		echo "$runtime seconds"
	elif [ $1 -ge 60 ] && [ $1 -lt 3600 ]; then
		runtime=$(date -u -d @${1} +"%M:%S")
		echo "$runtime minutes"
	else
		runtime=$(date -u -d @${1} +"%T")
		echo "$runtime hours"
	fi
}

function main() {
	start=$(date +%s)
	process_args "$@"
	create_hash_command
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

	end=$(date +%s)
	runtime=$(($end - $start))
	echo -n "Hashed $total_files files in "
	print_runtime $runtime
}

main "$@"
