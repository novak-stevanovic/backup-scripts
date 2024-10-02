#!/bin/bash

function print_debug() {
	if [[ $DEBUG_ENABLED -eq 1 ]]; then
		echo "[#] $1"
	fi
}

function print_important() {
	echo "[.] $1"
}

function print_error() {
	echo "[!] $1" >&2
}

function print_setting() {
	echo "[*] $1"
}

function exit_with_error() {
	print_error "$1"
	cleanup 1
	exit 1
}

function cleanup() {
	print_important "Cleaning up..."
	exit_code=$1
	if [[ $exit_code -eq 1 ]]; then
	for file in $created_files; do
		if [[ -e $file ]] && [[ -w $file ]]; then
			rm -rf $file
			print_debug "Cleaned up: $file"
		fi
	done
	fi
	for file in $created_temp_files; do
		if [[ -e $file ]] && [[ -w $file ]]; then
			rm -rf $file
			print_debug "Cleaned up: $file"
		fi
	done
	print_important "Cleanup finished."
}

function execute_with_output() {
	
	backup_maker_errors_tmp_filepath="/tmp/bm_errors.tmp"
	touch $backup_maker_errors_tmp_filepath
	command="$1 2>> $backup_maker_errors_tmp_filepath"

	eval $command
	while read -r line; do
		print_error "$line"
	done < "$backup_maker_errors_tmp_filepath"

	rm $backup_maker_errors_tmp_filepath

}

function execute_without_output() {

	command="$1 2> /dev/null"

	if [[ ! -e /dev/null ]]; then
		print_error "/dev/null doesn't exist. Exiting."
	fi

	eval $command
}

function validate_arguments() {
	if [[ $# -eq 4 ]]; then
		if [[ ! -f $1 ]]; then
			exit_with_error "Invalid input info file. Exiting."
		fi

		if [[ ! -f $2 ]]; then
			exit_with_error "Invalid ouput info file. Exiting."
		fi

		if [[ $(echo "$3" | grep -E "/") ]]; then
			exit_with_error "Invalid backup directory name. It must not be a path."
		fi

		print_debug "Input info file validated: $1"
		print_debug "Output info file validated: $2"
		print_debug "Resulting directory name validated: $3"
	else
		exit_with_error "Invalid input. Expected input: arg1 - input info filepath | arg2 - output info filepath | arg3 - backup directory name | arg4 - debug flag(0 or 1)."
	fi
}

trap 'exit_with_error "SIGNAL TO STOP RECEIVED"' SIGINT

is_sudo=0
if [[ $EUID -eq 0 ]]; then
	is_sudo=1
fi

if [[ $is_sudo -eq 1 ]]; then
	exit_with_error "This script may not be ran with sudo privileges. Exiting."
fi

print_important "Validating provided arguments..."
validate_arguments "$@"


readonly SCRIPT_DIRECTORY="$(dirname $BASH_SOURCE)"
readonly INPUT_INFO_FILEPATH=$1
readonly OUTPUT_INFO_FILEPATH=$2
readonly BACKUP_DIRNAME=$3
readonly DEBUG_ENABLED=$4
created_files=""
created_temp_files=""

echo
echo "[.] - INFORMATION | [!] - ERROR | [*] - SETTING | [#] - DEBUG"
echo
echo "----------------------------------------------------------------"
echo


if [[ $DEBUG_ENABLED -eq 1 ]]; then
	print_setting "Debug Mode: ENABLED."
else
	print_setting "Debug Mode: DISABLED."
fi

function is_line_comment() {
	if [[ $(echo "$1" | grep -E "#") ]]; then
		echo 1
	else
		echo 0
	fi
}

function load_files() {
	local_input_filepaths=""

	while read -r line; do
		if [[ $(is_line_comment "$line") -eq 1 ]] || [[ -z $line ]]; then
			continue
		fi
		local_input_filepaths+="$line "

	done < "$1"

	echo $local_input_filepaths
}

readonly INPUT_FILEPATHS=$(load_files $INPUT_INFO_FILEPATH)
readonly OUTPUT_DIRS=$(load_files $OUTPUT_INFO_FILEPATH)

function validate_input_filepaths() {
	for input_file in $INPUT_FILEPATHS; do
		if [[ ! -e $input_file ]]; then
			exit_with_error "Invalid input filepath: "$input_file". Exiting."
		fi
		print_debug "Validated input filepath: $input_file."

	done
}

function validate_output_dirs() {
	for output_dir in $OUTPUT_DIRS; do
		if [[ ! -d $output_dir ]]; then
			exit_with_error "Invalid output directory: "$output_dir". Exiting."
		fi

		print_debug "Validated output directory: $output_dir."
	done
}

print_important "Validating provided files for backup."
validate_input_filepaths
print_important "Validating provided destination directories."
validate_output_dirs

# ---------------------------------------------------------------------------

readonly TEMP_DIRECTORY_PATH="/tmp/backup_maker"

if [[ ! -d "/tmp" ]]; then
	exit_with_error "/tmp doesn't exist. Exiting."
fi

if [[ -d $TEMP_DIRECTORY_PATH ]]; then
	if [[ -w $TEMP_DIRECTORY_PATH ]]; then
		rm -rf $TEMP_DIRECTORY_PATH
	else
		exit_with_error "No permission to remove: $TEMP_DIRECTORY_PATH. Exiting."
	fi
fi

mkdir $TEMP_DIRECTORY_PATH
chmod +rwx $TEMP_DIRECTORY_PATH
print_debug "Created temporary directory: $TEMP_DIRECTORY_PATH."
created_temp_files+="$TEMP_DIRECTORY_PATH "

function copy_input_filepaths_into_temp_dir() {
	cd $TEMP_DIRECTORY_PATH

	for filepath in $INPUT_FILEPATHS; do
		print_debug "Copying: $filepath into temporary directory."

		filepath_basename="$(basename $filepath)"

		if [[ ! -e $filepath_basename ]]; then
			if [[ $DEBUG_ENABLED -eq 1 ]]; then
				execute_with_output "cp -r $filepath ."
			else
				execute_without_output "cp -r $filepath ."
			fi
		fi
	done

	cd $SCRIPT_DIRECTORY
}

print_important "Making temporary copies..."
copy_input_filepaths_into_temp_dir

function redistribute_temp_backup() {

	for dir in $OUTPUT_DIRS; do
		temp_directory_basename="$(basename $TEMP_DIRECTORY_PATH)"
		output_dir="$dir/$BACKUP_DIRNAME" 

		if [[ -d $output_dir ]]; then
			if [[ -w $output_dir ]]; then
				print_debug "Removing existing backup in: $dir."
				rm -rf "$output_dir"
			else
				exit_with_error "No permission to remove: $output_dir. Exiting."
			fi
		fi

		mkdir $output_dir
		print_debug "Created new backup directory in: $dir."
		created_files+="$output_dir "

		print_important "Creating backup in: $dir."

		execute_with_output "cp -r $TEMP_DIRECTORY_PATH/. $output_dir"
		
	done
}

redistribute_temp_backup

cleanup 0
print_important "Success."
exit 0
