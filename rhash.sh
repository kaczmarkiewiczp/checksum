#!/bin/bash
# rhash: recursively scan specified directory for files. Create a hash of all
# the files and append them to a specified output file

VERSION=2.0.9 # program version
EXE="$(basename $0)" # program name
HASH_COMMAND="" # command with appropriate flags used for hashing (i.e md5sum)
ALGORITHM="" # algorithm used for hashing
FILES="" # all the files inside a directory
INPUT_FILES=() # all the specified directories
OUTPUT_FILE="" # user specified output file
TOTAL_FILES=0 # total files hashed

# flags from processing command line arguments
FLAG_SORT=true # sort output
FLAG_APPEND=false # whether to append to output or overwrite it
FLAG_NO_TAG=false # --tag flag for HASH_COMMAND
FLAG_OUT2STDOUT=false # output to stdout instead of file
FLAG_QUIET=false # no output (except for -o and stderr)
FLAG_PROGRESS=true # display progress during hahing
FLAG_SUMMARY=true # print summary at the end
FLAG_CHECK=false # check checksums inside file(s)
FLAG_DETECT_ALG=false # try to detect algorithm for checking
FLAG_IGNORE_MISS=false # ignore missing files when checking
FLAG_IGNORE_ERR=false # ignore improperly formatted lines

# prints program usage
function usage() {
	if [ $FLAG_QUIET = true ]; then
		return
	fi

	echo -en "Usage: $EXE [OPTION]... OUTPUT FILE...\n"
	echo -en "  or:  $EXE [OPTION]... -o FILE...\n"
	echo -en "  or:  $EXE [OPTION]... -c FILE...\n"

	echo -en "Recursively create or check hashes of files inside supplied" \
		 "directory\n"

	echo -en "Options useful when creating and veryfying checksums:\n"
	echo -en "  -A ALGORITHM,  --ALGORITHM,  --algorithm=ALGORITHM"
	echo -en "   use specified algorithm\n"
	echo -en "\t\t\tThe following options are available:\n"
	echo -en "\t\t\t    md5 (default)\n\t\t\t    sha1\n\t\t\t    sha224\n "
	echo -en "\t\t\t    sha256\n\t\t\t    sha384\n\t\t\t    sha512\n"
	echo -en "      --no-summary\tdon't display summary at the end\n"
	echo -en "  -P, --no-progress\tdon't display progress\n"
	echo -en "  -q, --quiet\t\tsuppress non-error messages" \
		 "(excluding -o output)\n"
	echo -en "  -h, --help\t\tdisplay this message and quit\n"
	echo -en "      --version\t\tprint version information and exit\n"

	echo -en "\nOptions useful only when creating checksums:\n"
	echo -en "  -a, --append\t\tappend to output file instead of" \
		 "overwriting it\n"
	echo -en "  -o, --out2stdout\toutput hashes directly to stdout\n"
	echo -en "      --no-sort\t\tdon't sort output file (default" \
		 " behavior is to sort)\n"
	echo -en "      --no-tag\t\tdo not create a BSD-style checksum\n"

	echo -en "\nOptions useful only when veryfying checksums:\n"
	echo -en "  -c, --check\t\tread checksums from FILEs and check them\n"
	echo -en "      --detect-algorithm try to detect algorithm used\n"
	echo -en "      --ignore-missing\tdon't fail or report status for" \
		 "missing files\n"
	echo -en "      --ignore-errors\tignore improperly formatted lines\n"
}

# output message for getting help
function try_help() {
	if [ $FLAG_QUIET = true ]; then
		return
	fi

	echo "Try '$EXE --help' for more information" 1>&2
}

# check for invalid combination of flags
function check_flags() {
	if [ $FLAG_DETECT_ALG = true -o $FLAG_IGNORE_MISS = true -o \
		$FLAG_IGNORE_ERR = true ] && [ $FLAG_CHECK = false ]; then
		echo -n "$EXE the " 1>&2
		if [ $FLAG_DETECT_ALG = true ]; then
			echo -n "--detect-algorithm " 1>&2
		elif [ $FLAG_IGNORE_MISS = true ]; then
			echo -n "--ignore-missing " 1>&2
		elif [ $FLAG_IGNORE_ERR = true ]; then
			echo -n "--ignore-errors " 1>&2
		fi
		echo "options is meaningful only when verifying checksums" 1>&2
		try_help
		exit 110
	fi

	if [ $FLAG_CHECK = true ]; then
		if [ $FLAG_APPEND = true ]; then
			echo "$EXE: the --append option is meaningless when" \
			     "verifying checksums" 1>&2
			try_help
			exit 111
		elif [ $FLAG_OUT2STDOUT = true ]; then
			echo "$EXE: the --out2stdout option is meaningless" \
			     "when verifying checksums" 1>&2
			try_help
			exit 112
		elif [ $FLAG_SORT = false ]; then
			echo "$EXE: the --no-sort option is meaningless when" \
			     "verifying checksums" 1>&2
			try_help
			exit 113
		elif [ $FLAG_NO_TAG = true ]; then
			echo "$EXE: the --tag option is meaningless when" \
			     "verifying checksums" 1>&2
			try_help
			exit 114
		fi
	fi

	if [ $FLAG_APPEND = true ] && [ $FLAG_OUT2STDOUT = true ]; then
		echo "$EXE: the --append option is meaningless when printing" \
		     "to stdout" 1>&2
		try_help
		exit 115
	fi

	if [ ! -z $ALGORITHM ] && [ $FLAG_DETECT_ALG = true ]; then
		echo "$EXE: the --detect-algorithm option is meaningless" \
			"when an algorithm has been specified" 1>&2
		try_help
		exit 116
	fi

	if [ $FLAG_OUT2STDOUT = true ] && [ $FLAG_SORT = false ]; then
		echo "$EXE: the --no-sort option is meaningless when printing" \
			"to stdout" 1>&2
		try_help
		exit 117
	fi
}

# process arguments
function process_args() {
	files=() # all non-flag arguments (output and input files)
	expect_a=false

	args=("$@") # put arguments into array

	for (( i=0; i<${#args[@]}; i++)); do
		opt="${args[i]}"

		# split grouped options (-abc -> -a -b -c)
		if [[ $opt = -* ]] && [[ ! $opt = --* ]] && [ ${#opt} -gt 2 ]; 
		then
			while [ ${#opt} -gt 2 ]; do
				if [ "${opt: -1}" = 'A' ]; then
					echo "$EXE: option -A cannot be" \
					"grouped together with other options" \
					1>&2
					exit 100
				fi
				# append the last option at the back of array
				args+=("-${opt: -1}")
				# remove the option from the variable
				opt="${opt: :-1}"
			done
		fi

		# expecting option for -A or --algorithm
		if [ $expect_a = true ]; then
			opt="--$opt"
		fi

		case $opt in
			-a|--append)
				FLAG_APPEND=true
				;;
			-c|--check)
				FLAG_CHECK=true
				;;
			--no-sort)
				FLAG_SORT=false
				;;
			-o|--out2stdout)
				FLAG_OUT2STDOUT=true
				;;
			--md5|--sha1|--sha224|--sha256|--sha384|--sha512)
				ALGORITHM=${opt:2} # remove leading '--'
				;;
			-A)
				ALGORITHM=""
				expect_a=true
				continue
				;;
			--algorithm=*)
				# check for --algorithm=OPTION and
				# --algorithm= OPTION
				ALGORITHM=$(echo $opt | cut -d '=' -f2)
				if [ -z $ALGORITHM ]; then
					# there was space between '=' and option
					# the next element should be the option
					expect_a=true;
					continue
				elif 	[ $ALGORITHM = "md5" ] || 
					[ $ALGORITHM = "sha256" ] ||
					[ $ALGORITHM = "sha384" ] ||
					[ $ALGORITHM = "sha512" ]; then
					: # don't do anything
				elif [ -e $ALGORITHM ]; then
					echo "$EXE: missing argument to" \
					     "'--algorithm'" 1>&2
					try_help
					exit 101
				else
					echo "$EXE: unknown argument to" \
					     "--algorithm: '$ALGORITHM'" 1>&2
					try_help
					exit 102
				fi
				;;
			--no-tag)
				FLAG_NO_TAG=true
				;;
			--no-summary)
				FLAG_SUMMARY=false
				;;
			-P|--no-progress)
				FLAG_PROGRESS=false
				;;
			--detect-algorithm)
				FLAG_DETECT_ALG=true
				;;
			--ignore-missing)
				FLAG_IGNORE_MISS=true
				;;
			--ignore-errors)
				FLAG_IGNORE_ERR=true
				;;
			-q|--quiet)
				FLAG_QUIET=true
				;;
			-h|--help)
				if [ $FLAG_QUIET = false ]; then
					usage
				fi
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
					echo -n "$EXE: unknown option " 1>&2
					if [[ $opt = --* ]]; then
						echo "'$opt'" 1>&2
					else
						echo "'${opt:1}'" 1>&2
					fi
					try_help
					exit 103
				fi
				;;
			*)
				files+=("$opt")
				;;
		esac

		if [ $expect_a = true ]; then
			if [ -z $ALGORITHM ]; then
				echo -n "$EXE: mussing argument to " 1>&2
				# check previous element in the array
				# this will tell us if it was -A or long version
				if [ ${args[$i-1]} = "-A" ]; then
					echo "'-A'" 1>&2
				else echo "'--algorithm'" 1>&2
				fi
				try_help
				exit 104
			fi
			expect_a=false
		fi
	done

	check_flags

	# if output to stdout or checking file,
	# check that at least one file specified
	if [ $FLAG_OUT2STDOUT = true -o $FLAG_CHECK = true ]; then
		if [ ${#files[@]} -ge 1 ]; then
			INPUT_FILES=("${files[@]}")
		elif [ $FLAG_OUT2STDOUT = true ]; then
			echo "$EXE: missing files/directories" 1>&2
			try_help
			exit 105
		else
			echo "$EXE: missing files" 1>&2
			try_help
			exit 106
		fi
	else # output to file
		# check that at least two files (output and input)
		if [ ${#files[@]} -ge 2 ] && [ ! -d "${files[0]}" ]; then
			OUTPUT_FILE="${files[0]}"
			INPUT_FILES=("${files[@]:1}")
		elif [ -d "${files[0]}" ]; then
			echo "$EXE: missing output file" 1>&2
			try_help
			exit 107
		else
			echo "$EXE: missing files/directories" 1>&2
			try_help
			exit 108
		fi

		# clear file if it exists and append flag is not specified
		if [ $FLAG_APPEND = false ] && [ -e $OUTPUT_FILE ]; then
			> $OUTPUT_FILE
		fi
	fi

	# set default algorithm if not set
	if [ -z $ALGORITHM ] && [ $FLAG_CHECK = false ]; then
		ALGORITHM="md5"
	fi
}

################################################################################
# Functions solely used when creating checksums
################################################################################

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
		return 0
	elif [ -f "$dir" ]; then
		FILES="$dir"
		return 0
	else
		echo "$EXE: '$dir' does not exists" 1>&2
		return 210
	fi
}

# outputs progress of files processed
function print_hash_progress() {
	file="$1"
	file_num="$2"
	total="$3"

	term_w=$(tput cols) # width of terminal
	prefix="$file" # filepath part of output
	postfix=" [$file_num of $total]" # 'n of n' part of output
	length=$(( ${#prefix} + ${#postfix}))

	# if output is bigger than terminal width we have to shorten it
	if [ $length -gt $term_w ]; then
		# calculate available width for 'prefix'
		aval_w=$(( $term_w - ${#postfix} - 5))
		# how many characters we need to remove
		remove=$(( ${#prefix} - $aval_w))
		# split prefix in half
		# remove equal amount of chars from both halves
		first_half="${prefix:0:$((${#prefix} / 2))}"
		first_half="${first_half::-$(($remove / 2))}"

		second_half="${prefix:$((${#prefix} / 2)):${#prefix}}"
		second_half="${second_half:$(($remove / 2))}"

		# create new prefix
		prefix="$first_half...$second_half"
	fi

	# calculate available space for padding
	aval_pad=$((${#prefix} + ${#postfix}))
	aval_pad=$(($term_w - $aval_pad - 1))
	
	# create padding
	if [ $aval_pad -gt 1 ]; then
		padding=$(for ((i=1; i<=$aval_pad; i++)); do echo -n " "; done)
	else
		padding=""
	fi

	# print output on the same line (overwriting previous line)
	echo -ne "\r\033[K$prefix$padding$postfix"
}

# print summary of created checksum
function print_hash_summary() {
	echo -n "Hashed $TOTAL_FILES files in "
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

# hash files in the array of files
function rhash() {
	file_num=1 # keep track of which file is being hashed
	total=$(echo "$FILES" | wc -l) # total number of files for current dir

	((TOTAL_FILES+=$total))

	while read file; do
		if [ $FLAG_OUT2STDOUT = false ] && 
		   [ $FLAG_QUIET = false -a $FLAG_PROGRESS = true ]; then
			print_hash_progress "$file" $file_num $total
		fi

		if [ $FLAG_OUT2STDOUT = true ]; then
			$HASH_COMMAND "$file"
		else # output to stdout
			$HASH_COMMAND "$file" >> $OUTPUT_FILE
		fi
		((file_num++))
	done <<< "$FILES"
	if [ $FLAG_OUT2STDOUT = false ] && 
	   [ $FLAG_QUIET = false -a $FLAG_PROGRESS = true ]; then 
		echo ""
	fi
}

################################################################################
# Functions solely used when doing a checksum checks/comparisons
################################################################################

function create_check_command() {
	case "$1" in
		MD5|md5)
			HASH_COMMAND="md5sum "
			;;
		SHA1|sha1)
			HASH_COMMAND="sha1sum "
			;;
		SHA224|sha224)
			HASH_COMMAND="sha224sum "
			;;
		SHA256|sha256)
			HASH_COMMAND="sha256sum "
			;;
		SHA384|sha384)
			HASH_COMMAND="sha384sum "
			;;
		SHA512|sha512)
			HASH_COMMAND="sha512sum "
			;;
		*)
			HASH_COMMAND=""
			return
			;;
	esac

	HASH_COMMAND+="--check --ignore-missing --quiet --status -"
}

# try and detect algorithm based on hash length
function detect_algorithm() {
	case ${#1} in
		32)
			create_check_command "MD5"
			;;
		40)
			create_check_command "SHA1"
			;;
		56)
			create_check_command "SHA224"
			;;
		64)
			create_check_command "SHA256"
			;;
		96)
			create_check_command "SHA384"
			;;
		128)
			create_check_command "SHA512"
			;;
		*)
			HASH_COMMAND=""
			;;
	esac
}

# outputs progress during hash checking
function print_check_progress() {
	file_num=$1
	total_num=$2
	ok=$3
	failed=$4
	missing=$5
	error=$6

	progress="FILE: $file_num of $total_num"
	progress+="   OK: $ok"
	progress+="   FAILED: $failed"
	if [ $FLAG_IGNORE_MISS = false ]; then
		progress+="   MISSING: $missing"
	fi
	if [ $FLAG_IGNORE_ERR = false ]; then
		progress+="   ERROR: $error"
	fi

	echo -ne "\r\033[K$progress"
}

# output summary of check
function print_check_summary() {
	passed_num=$1
	error_num=$2
	failed_files=("${!3}")
	missing_files=("${!4}")
	failed_num=${#failed_files[@]}
	missing_num=${#missing_files[@]}

	echo -en "\r\033[K"
	echo -n "PASSED: $passed_num"
	echo -n "   FAILED: $failed_num"
	if [ $FLAG_IGNORE_MISS = false ]; then
		echo -n "   MISSING: $missing_num"
	fi
	if [ $FLAG_IGNORE_ERR = false ]; then
		echo -n "   ERRORED: $error_num"
	fi
	echo

	for i in "${failed_files[@]}"; do echo "[FAILED]  $i"; done

	if [ $FLAG_IGNORE_MISS = false ]; then
		for i in "${missing_files[@]}"; do echo "[MISSING]  $i"; done
	fi
}

# check hashes from a file
function check() {
	# regex for detecting checksums
	regex_tag="^(MD5|SHA1|SHA224|SHA256|SHA384|SHA512)[[:space:]]\(.+\)"
	regex_tag+="[[:space:]]=[[:space:]]([a-f]|[A-F]|[0-9])+$"

	regex_no_tag="^([a-f]|[A-F]|[0-9])+[[:space:]].+$"

	total_num=$(wc -l "$1") # total number of lines/files scanned
	total_num=$(echo $total_num | cut -d' ' -f1)
	file_num=0 # current file scanned (for progress output)
	ok_num=0 # files passed
	error_num=0 # lines with errors
	failed_files=() # checksum check failed
	missing_files=() # missing files

	while read line; do
		# ignore empty lines
		if [ -z "$line" ]; then 
			continue 
		fi

		((file_num++))

		if [ $FLAG_PROGRESS = true ] && [ $FLAG_QUIET = false ]; then
			print_check_progress "$file_num" "$total_num" \
					     "$ok_num" "${#failed_files[@]}" \
					     "${#missing_files[@]}" "$error_num"
		fi

		if [[ "$line" =~ $regex_tag ]]; then
			algorithm=$(echo "$line" | cut -d' ' -f1)
			# extract file path
			file=${line/ /\#}
			file=$(echo "$file" | cut -d\# -f2)
			file=$(echo "$file" | cut -d')' -f1)
			file=${file:1}
			create_check_command $algorithm
		elif [[ "$line" =~ $regex_no_tag ]]; then
			checksum=$(echo "$line" | cut -d' ' -f1)
			file=${line/  /\#}
			file=${file/ \*/\#}
			file=$(echo $file | cut -d\# -f2)

			if [ ! -z $ALGORITHM ]; then
				create_check_command $ALGORITHM
			elif [ $FLAG_DETECT_ALG = true ]; then
				detect_algorithm $checksum
			else
				((error_num++))
				continue
			fi
		else
			((error_num++))
			continue
		fi

		if [ -z "$HASH_COMMAND" ]; then
			((error_num++))
			continue
		fi

		if [ ! -f "$file" ]; then
			missing_files+=("$file")
			continue
		fi

		$(echo "$line" | $HASH_COMMAND 2>/dev/null)
		if [ $? -eq 0 ]; then
			((ok_num++))
		else
			failed_files+=("$file")
		fi
	done < "$1"

	if [ $FLAG_QUIET = false -a $FLAG_SUMMARY = true ]; then
		print_check_summary $ok_num $error_num "failed_files[@]" \
				    "missing_files[@]"
	elif [ $FLAG_PROGRESS = true ] && [ $FLAG_QUIET = false ]; then
		print_check_progress "$file_num" "$total_num" \
				     "$ok_num" "${#failed_files[@]}" \
				     "${#missing_files[@]}" "$error_num"
		echo
	fi

	# return appropriate exit code
	if [ ${#failed_files[@]} -gt 0 ]; then
		return 200
	elif [ ${#missing_files[@]} -gt 0 ] && [ $FLAG_IGNORE_MISS = false ];
	then
		return 201
	elif [ $error_num -gt 0 ] && [ $FLAG_IGNORE_ERR = false ]; then
		return 202
	else
		return 0
	fi
}

################################################################################
# Main
################################################################################

# sets everything up and calls appropriate functions
function main() {
	start=$(date +%s)
	process_args "$@"

	if [ $FLAG_CHECK = true ]; then
		exit_status=0

		for file in "${INPUT_FILES[@]}"; do
			if [ -f "$file" ]; then
				check "$file"

				return_val=$?
				case $return_val in
					200)
						;& # fall-through
					201)
						;& # fall-through
					202)
						if [ $exit_status -gt 0 ]; then
							exit_status=203
						else
							exit_status=$return_val
						fi
						;;
				esac
			else
				echo "$EXE: '$file' does not exists" 1>&2
			fi
		done
		exit $exit_status
	fi

	create_hash_command
	# go through each dir one-by-one
	for dir in "${INPUT_FILES[@]}"; do
		get_all_files "$dir"
		if [ $? -eq 0 ] && [ ! -z "$FILES" ]; then
			rhash
		fi
	done

	# check if we should sort the output
	if [ $FLAG_SORT = true ] && [ $FLAG_OUT2STDOUT = false ]; then
		sort -k2 "$OUTPUT_FILE" -o "$OUTPUT_FILE" 2>/dev/null
	fi

	end=$(date +%s)
	runtime=$(($end - $start))
	if [ $FLAG_OUT2STDOUT = false ] && 
	   [ $FLAG_QUIET = false -a $FLAG_SUMMARY = true ]; then
		print_hash_summary $runtime
	fi
}

main "$@"
