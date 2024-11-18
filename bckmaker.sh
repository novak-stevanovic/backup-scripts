#!/bin/bash

# ------ DECLARATION ------

readonly EXPECTED_ARG_COUNT=6
readonly SCRIPT_DIRECTORY="$(dirname $BASH_SOURCE)"
readonly INPUT_INFO_FILEPATH=$1
readonly OUTPUT_INFO_FILEPATH=$2
readonly BACKUP_DIRNAME=$3
readonly DEBUG_ENABLED=$4
readonly PRESERVE_DESTINATION_GITFILES=$5
readonly REMOVE_INPUT_GITFILES=$6
readonly TEMP_DIRECTORY_PATH="/tmp/backup_maker"

created_files=""
created_temp_files=""

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

function validate_flag() {
    readonly VAL=$1
    if [[ $VAL -eq 0 ]] || [[ $VAL -eq 1 ]]; then
        echo 1
    else
        echo 0
    fi
}

function validate_arguments() {
    if [[ $# -eq $EXPECTED_ARG_COUNT ]]; then
        if [[ ! -f $1 ]]; then
            exit_with_error "Invalid input info file. Exiting."
        fi

        if [[ ! -f $2 ]]; then
            exit_with_error "Invalid ouput info file. Exiting."
        fi

        if [[ $(echo "$3" | grep -E "/") ]]; then
            exit_with_error "Invalid backup directory name. It must not be a path. Exiting."
        fi

        if [[ $(validate_flag $4) -ne 1 ]]; then
            exit_with_error "Invalid debug mode flag. It must be 0 or 1. Exiting."
        fi

        if [[ $(validate_flag $5) -ne 1 ]]; then
            exit_with_error "Invalid preserve destination gitfiles flag. It must be 0 or 1. Exiting."
        fi

        if [[ $(validate_flag $6) -ne 1 ]]; then
            exit_with_error "Invalid remove input gitfiles flag. It must be 0 or 1. Exiting."
        fi

        print_debug "Input info file validated: $1"
        print_debug "Output info file validated: $2"
        print_debug "Backup directory name validated: $3"
        print_debug "Debug mode flag validated: $4"
        print_debug "Preserve destination gitfiles flag validated: $5"
        print_debug "Remove source gitfiles flag validated: $6"
    else
        exit_with_error "Invalid input. Expected input: bckmaker [input_file_filepath] [output_file_filepath] [backup_dirname] [debug_flag] [preserve_dest_gitfiles_flag] [skip_src_gitfiles_flag]. Exiting."
    fi
}

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
        if [[ $(is_line_comment "$line") -eq 1 ]] || [[ -z "$line" ]]; then
            continue
        fi
        current_filename=$(readlink -f $line)
        local_input_filepaths+="$current_filename "

    done < "$1"

    echo $local_input_filepaths
}

function validate_input_filepaths() {
    for input_file in $INPUT_FILEPATHS; do
        if [[ ! -e "$input_file" ]]; then
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

function remove_input_gitfiles() {
    gitfile_paths="$(find $TEMP_DIRECTORY_PATH)"

    for file in $gitfile_paths; do
        if [[ "$file" == *".git"* ]]; then
            print_debug "Removing gitfile: $file."
            rm -rf $file
        fi
    done
}

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

    if [[ $REMOVE_INPUT_GITFILES -eq 1 ]]; then
        remove_input_gitfiles
    fi

    cd $SCRIPT_DIRECTORY
}

function redistribute_temp_backup() {

    for dir in $OUTPUT_DIRS; do
        temp_directory_basename="$(basename $TEMP_DIRECTORY_PATH)"
        output_dir="$dir/$BACKUP_DIRNAME" 

        if [[ -d $output_dir ]]; then
            if [[ -w $output_dir ]] && [[ -r $output_dir ]]; then
                if [[ $PRESERVE_DESTINATION_GITFILES -eq 1 ]]; then
                    print_debug "Removing existing backup in: $output_dir. Gitfiles are preserved."
                    find $output_dir -maxdepth 1 -mindepth 1 -not -name ".gitignore" -not -name ".git" -exec rm -rf {} \;
                else
                    print_debug "Removing existing backup in: $output_dir. Gitfiles are not preserved."
                    find $output_dir -maxdepth 1 -mindepth 1 -exec rm -rf {} \;
                fi
            else
                exit_with_error "No permission to remove or read: $output_dir. Exiting."
            fi
        else
            mkdir $output_dir
            print_debug "Created new backup directory in: $dir."
        fi

        created_files+="$output_dir "
        print_important "Creating backup in: $dir."
        execute_with_output "cp -r $TEMP_DIRECTORY_PATH/. $output_dir"

    done
}

# ------ VALIDATION ------

is_sudo=0
if [[ $EUID -eq 0 ]]; then
    is_sudo=1
fi

if [[ $is_sudo -eq 1 ]]; then
    exit_with_error "This script may not be ran with sudo privileges. Exiting."
fi


echo
echo "[.] - INFORMATION | [!] - ERROR | [*] - SETTING | [#] - DEBUG"
echo
echo "----------------------------------------------------------------"
echo

print_important "Validating provided arguments..."

validate_arguments "$@"

trap 'exit_with_error "SIGNAL TO STOP RECEIVED"' SIGINT

if [[ $DEBUG_ENABLED -eq 1 ]]; then
    print_setting "Debug Mode: ENABLED."
else
    print_setting "Debug Mode: DISABLED."
fi

if [[ $PRESERVE_DESTINATION_GITFILES -eq 1 ]]; then
    print_setting "Preserve destination gitfiles: ENABLED."
else
    print_setting "Preserve destination gitfiles: DISABLED."
fi

if [[ $REMOVE_INPUT_GITFILES -eq 1 ]]; then
    print_setting "Remove input gitfiles: ENABLED."
else
    print_setting "Remove input gitfiles: DISABLED."
fi

readonly INPUT_FILEPATHS=$(load_files $INPUT_INFO_FILEPATH)
readonly OUTPUT_DIRS=$(load_files $OUTPUT_INFO_FILEPATH)

print_important "Validating provided files for backup."
validate_input_filepaths
print_important "Validating provided destination directories."
validate_output_dirs

# ------ MAIN ------

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

print_important "Making temporary copies..."
copy_input_filepaths_into_temp_dir

redistribute_temp_backup

cleanup 0
print_important "Success."
exit 0
