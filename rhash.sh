#!/bin/bash
# rhash: recursively scan specified directory for files. Create a hash of all
# the files and append them to a specified output file

VERSION=1.3 # program version
EXE="$(basename $0)" # program name
DEBUG=false # debugging mode
HASH_COMMAND="" # command with appropriate flags used for hashing (i.e md5sum)
ALGORITHM="md5" # algorithm used for hashing
FILES="" # all the files inside a directory
DIRECTORIES=() # all the specified directories
OUTPUT_FILE="" # user specified output file
TOTAL_FILES=0 # total files hashed
# flags from processing command line arguments
FLAG_SORT=true # sort output
FLAG_NO_TAG=false # --tag flag for HASH_COMMAND
FLAG_OUT2STDOUT=false # output to stdout instead of file
FLAG_QUIET=false # no output (except for -o and stderr)

# prints program usage
function usage() {
	echo -en "Usage: $EXE [OPTION]... OUTPUT FILE...\n"
	echo -en "  or:  $EXE [OPTION]... -o FILE...\n"
	echo -en "Recursively create hashes of files inside supplied" \
		 "directory\n"
	echo -en "Options:\n"
	echo -en "  -a, --append\t\tappend to output file instead of" \
		 "overwriting it\n"
	echo -en "  -A ALGORITHM,  --ALGORITHM,  --algorithm=ALGORITHM"
	echo -en "   use specified algorithm\n"
	echo -en "\t\t\tThe following options are available:\n"
	echo -en "\t\t\t    md5 (default)\n\t\t\t    sha1\n\t\t\t    sha224\n "
	echo -en "\t\t\t    sha256\n\t\t\t    sha384\n\t\t\t    sha512\n"
	echo -en "  -o, --out2stdout\toutput hashes directly to stdout\n"
	echo -en "  -s, --sort-output\tsort the output file (default " \
		 "behaviour)\n"
	echo -en "  -S, --no-sort\t\tdon't sort the output file\n"
	echo -en "      --no-tag\t\tdo not create a BSD-style checksum\n"
	echo -en "  -q, --quiet\t\tsuppress non-error messages" \
		 "(excluding -o output)\n"
	echo -en "  -h, --help\t\tdisplay this message and quit\n"
	echo -en "      --version\t\tprint version information and exit\n"
}

# output message for getting help
function try_help() {
	echo "Try '$EXE --help' for more information" 1>&2
}

# process arguments
function process_args() {
	files=() # all non-flag arguments (output and input files)
	append_output=false
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
					exit 110
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
				append_output=true
				;;
			-s|--sort-output)
				FLAG_SORT=true
				;;
			-S|--no-sort)
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
					exit 111
				else
					echo "$EXE: unknown argument to" \
					     "--algorithm: '$ALGORITHM'" 1>&2
					try_help
					exit 112
				fi
				;;
			--no-tag)
				FLAG_NO_TAG=true
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
					exit 113
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
				exit 114
			fi
			expect_a=false
		fi
	done

	# if output to stdout, check that at least one file specified
	if [ $FLAG_OUT2STDOUT = true ]; then
		if [ ${#files[@]} -ge 1 ]; then
			DIRECTORIES=("${files[@]}")
		else
			echo "$EXE: missing files/directories" 1>&2
			try_help
			exit 115
		fi
	else # output to file
		# check that at least two files (output and input)
		if [ ${#files[@]} -ge 2 ] && [ ! -d "${files[0]}" ]; then
			OUTPUT_FILE="${files[0]}"
			DIRECTORIES=("${files[@]:1}")
		elif [ -d "${files[0]}" ]; then
			echo "$EXE: missing output file" 1>&2
			try_help
			exit 116
		else
			echo "$EXE: missing files/directories" 1>&2
			try_help
			exit 117
		fi

		# clear file if it exists and append flag is not specified
		if [ $append_output = false ] && [ -e $OUTPUT_FILE ]; then
			> $OUTPUT_FILE
		fi
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
		return 0
	elif [ -f "$dir" ]; then
		FILES="$dir"
		return 0
	else
		echo "$dir does not exists or is not a directory." 1>&2
		return 210
	fi
}

# outputs progress of files processed
function output_progress() {
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

# hash files in the array of files
function rhash() {
	file_num=1 # keep track of which file is being hashed
	total=$(echo "$FILES" | wc -l) # total number of files for current dir

	((TOTAL_FILES+=$total))

	while read file; do
		if [ $FLAG_OUT2STDOUT = false ] && [ $FLAG_QUIET = false ]; then
			output_progress "$file" $file_num $total
		fi

		if [ $DEBUG = true ]; then
			sleep 0.05
			$(echo "HASHED  $file" >> $OUTPUT_FILE)
		elif [ $FLAG_OUT2STDOUT = true ]; then
			$HASH_COMMAND "$file"
		else # output to stdout
			$HASH_COMMAND "$file" >> $OUTPUT_FILE
		fi
		((file_num++))
	done <<< "$FILES"
	if [ $FLAG_OUT2STDOUT = false ] && [ $FLAG_QUIET = false ]; then 
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

# sets everything up and calls appropriate functions
function main() {
	start=$(date +%s)
	process_args "$@"
	create_hash_command
	# go through each dir one-by-one
	for dir in "${DIRECTORIES[@]}"; do
		get_all_files "$dir"
		if [ $? -eq 0 ] && [ ! -z "$FILES" ]; then
			rhash
		fi
	done

	# check if we should sort the output
	if [ $FLAG_SORT = true ] && [ $FLAG_OUT2STDOUT = false ]; then
		sort -k2 "$OUTPUT_FILE" -o "$OUTPUT_FILE"
	fi

	end=$(date +%s)
	runtime=$(($end - $start))
	if [ $FLAG_OUT2STDOUT = false ] && [ $FLAG_QUIET = false ]; then
		echo -n "Hashed $TOTAL_FILES files in "
		print_runtime $runtime
	fi
}

main "$@"
