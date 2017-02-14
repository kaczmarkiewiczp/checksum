#!/bin/bash
# rhash: recursively scan specified directory for files. Create a hash (md5)
# of all the files and append them to a specified output file

VERSION=1.2 
EXE="$(basename $0)"
DEBUG=false
HASH_COMMAND=""
ALGORITHM="md5"
FILES=""
DIRECTORIES=()
OUTPUT_FILE=""
TOTAL_FILES=0
FLAG_SORT=true
FLAG_NO_TAG=false
FLAG_OUT2STDOUT=false

# prints program usage
function usage() {
	underline="\e[4m"
	norm="\e[0m"

	echo -en "$EXE [option...] "
	echo -en "$underline""output file$norm "
	echo -en "$underline""directory...$norm\n"
	echo -en "Options:\n"
	echo -en "  -a, --append\t\tappend to output file instead of" \
		 "overwriting it\n"
	echo -en "  -s, --sort-output\tsort the output file (default " \
		 "behaviour)\n"
	echo -en "  -S, --no-sort\t\tdon't sort the output file\n"
	echo -en "      --no-tag\tdo not create a BSD-style checksum\n"
	echo -en "  -A ALGORITHM,\n"
	echo -en "      --[ALGORITHM],\n"
	echo -en "      --algorithm=[ALGORITHM]\n"
	echo -en "\t\t\tuses the specified algorithm.\n"
	echo -en "\t\t\tThe following options are available:\n"
	echo -en "\t\t\t  md5\n\t\t\t  sha1\n\t\t\t  sha224\n\t\t\t  sha256\n"
	echo -en "\t\t\t  sha384\n\t\t\t  sha512\n"
	echo -en "  -o, --out2stdout\toutput hashes directly to stdout\n"
	echo -en "  -h, --help\t\tdisplay this message and quit\n"
	echo -en "      --version\t\tprint version information and exit\n"
}

# output message for getting help
function try_help() {
	echo "Try '$EXE --help' for more information"
}

# process arguments
function process_args() {
	append_output=false
	expect_a=false
	flag_count=0

	args=("$@") # put arguments into array

	for (( i=0; i<${#args[@]}; i++)); do
		opt="${args[i]}"

		# split grouped options (-abc -> -a -b -c)
		if [[ $opt = -* ]] && [[ ! $opt = --* ]] && [ ${#opt} -gt 2 ]; 
		then
			while [ ${#opt} -gt 2 ]; do
				if [ "${opt: -1}" = 'A' ]; then
					echo "$EXE: option -A cannot be" \
					"grouped together with other options"
					exit 110
				fi
				args+=("-${opt: -1}")
				opt="${opt: :-1}"
			done
		fi

		# expecting option for -A or --algorithm
		if [ $expect_a = true ]; then
			opt="--$opt"
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
			-o|--out2stdout)
				FLAG_OUT2STDOUT=true
				;;
			--md5|--sha1|--sha224|--sha256|--sha384|--sha512)
				ALGORITHM=${opt:2}
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
				elif [ -e $ALGORITHM ]; then
					echo "$EXE: missing argument to" \
					     "'--algorithm'"
					try_help
					exit 111
				else
					echo "$EXE: unknown argument to" \
					     "--algorithm: '$ALGORITHM'"
					try_help
					exit 112
				fi
				;;
			--no-tag)
				FLAG_NO_TAG=true
				;;
			-h|--help)
				usage
				exit 0
				;;
			--version)
				echo "$EXE version $VERSION"
				exit 0
				;;
			-*|--*)
				if [ $expect_a = true ]; then
					: # don't do anything
				else
					echo -n "$EXE: unknown option "
					if [[ $opt = --* ]]; then
						echo "'$opt'"
					else
						echo "'${opt:1}'"
					fi
					try_help
					exit 113
				fi
				;;
			*)
				if [ -z $OUTPUT_FILE ] && 
				   [ $FLAG_OUT2STDOUT = false ]; then
					OUTPUT_FILE="$opt"
				else
					DIRECTORIES+=("$opt")
				fi
				;;
		esac

		if [ $expect_a = true ]; then
			if [ -z $ALGORITHM ]; then
				echo "$EXE: missing argument to '-A," \
				     "--algorithm'"
				try_help
				exit 114
			fi
			expect_a=false
		fi
	done

	# no output file specified or output file is a dir
	if [ -z $OUTPUT_FILE -o -d $OUTPUT_FILE ] && 
	   [ $FLAG_OUT2STDOUT = false ]; then
		echo "$EXE: missing output file"
		try_help
		exit 115
	fi

	# output to stdout; our output file is part of directories to hash
	if [ $FLAG_OUT2STDOUT = true ] && [ ! -z $OUTPUT_FILE ]; then
		DIRECTORIES+=("$OUTPUT_FILE")
		OUTPUT_FILE=""
	fi

	# check at least one directory was specified
	if [ ${#DIRECTORIES[@]} -eq 0 ]; then
		echo "$EXE: missing files/directories for hashing"
		try_help
		exit 116
	fi

	# clear file if it doesn't exists and append flag is not specified
	if [ $FLAG_OUT2STDOUT = false ] && [ $append_output = false ] && 
	   [ -e $OUTPUT_FILE ]; then
		> $OUTPUT_FILE
	fi
}

# creates appropriate hash command
function create_hash_command() {
	HASH_COMMAND=$ALGORITHM
	HASH_COMMAND+="sum "
	
	if [ $FLAG_NO_TAG = false ]; then
		HASH_COMMAND+="--tag "
	fi
}

# get all the files from specified dir and save them into an array
function get_all_files() {
	dir="$1"
	FILES="" # clear variable

	if [ -d "$dir" ]; then
		FILES=$(find "$dir" -type f)
	elif [ -f "$dir" ]; then
		FILES="$dir"
	else
		echo "$dir does not exists or is not a directory."
	fi
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

	if [ -z "$FILES" ]; then
		return
	fi

	((TOTAL_FILES+=$total))

	while read file; do
		if [ $FLAG_OUT2STDOUT = false ]; then
			output_progress "$file" $file_num $total
		fi

		if [ $DEBUG = true ]; then
			sleep 0.05
			$(echo "HASHED  $file" >> $OUTPUT_FILE)
		elif [ $FLAG_OUT2STDOUT = true ]; then
			$HASH_COMMAND "$file"
		else
			$HASH_COMMAND "$file" >> $OUTPUT_FILE
		fi
		((file_num++))
	done <<< "$FILES"
	if [ $FLAG_OUT2STDOUT = false ]; then 
		echo ""
	fi
}

# prints execution time
function print_runtime() {
	if [ $1 -lt 60 ]; then
		runtime=$(date -u -d @${1} +"%S")
		echo "$runtime seconds"
	elif [ $1 -ge 60 ] && [ $1 -lt 3600 ]; then
		runtime=$(date -u -d @${1} +"%M:%S")
		echo "$runtime minutes"
	elif [ $1 -ge 3600 ] && [ $1 -lt 86400 ]; then
		runtime=$(date -u -d @${1} +"%T")
		echo "$runtime hours"
	else
		echo "more than a day"
	fi
}

function main() {
	start=$(date +%s)
	process_args "$@"
	create_hash_command
	# go through each dir one-by-one
	for dir in "${DIRECTORIES[@]}"; do
		get_all_files "$dir"
		rhash
	done

	if [ $FLAG_SORT = true ] && [ $FLAG_OUT2STDOUT = false ]; then
		sort -k2 "$OUTPUT_FILE" -o "$OUTPUT_FILE"
	fi

	end=$(date +%s)
	runtime=$(($end - $start))
	if [ $FLAG_OUT2STDOUT = false ]; then
		echo -n "Hashed $TOTAL_FILES files in "
		print_runtime $runtime
	fi
}

main "$@"
