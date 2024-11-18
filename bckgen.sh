#!/bin/bash

readonly CURRENT_DIR=$(pwd)
readonly INPUT_INFO_FILE_FILENAME="input_files.backup_maker"
readonly OUTPUT_INFO_FILE_FILENAME="output_files.backup_maker"
readonly BACKUP_SCRIPT_DEPLOYER_FILENAME="bckmaker_deployer.sh"
readonly BACKUP_MAKER_FILEPATH="/usr/local/bin/bckmaker"
readonly DEFAULT_BACKUP_DIRNAME="BM_BACKUP"

if [[ ! -r $CURRENT_DIR ]] || [[ ! -w $CURRENT_DIR ]]; then
    echo "No read or write permissions in current directory. Run script with sudo or run from another directory. Exiting"
    exit 1
fi

if [[ ! -f $BACKUP_MAKER_FILEPATH ]]; then
    echo "Backup maker not found. Exiting."
    exit 1
fi

if [[ ! -f $INPUT_INFO_FILE_FILENAME ]]; then
    touch $INPUT_INFO_FILE_FILENAME
    echo "Created input file."
    cat <<EOF >> "$INPUT_INFO_FILE_FILENAME"
# Comments are denoted by lines containing "#".
# Files or directories for backup should be added in each new line, as follows:
# file1,
# file2,
# directory1...

# Do not shorten paths with "~".
# If you need to backup write-protected or read-protected files, you will need sudo privileges.
EOF
fi

if [[ ! -f $OUTPUT_INFO_FILE_FILENAME ]]; then
    touch $OUTPUT_INFO_FILE_FILENAME
    echo "Created output file."
    cat <<EOF >> "$OUTPUT_INFO_FILE_FILENAME"
# Comments are denoted by lines containing "#".
# Directories for backup should be added in each new line, as follows:
# directory1,
# directory2,
# directory3...

# Do not shorten paths with "~".
# If any directories are write-protected or read-protected, you will need sudo privileges.
EOF
fi

if [[ -f $BACKUP_SCRIPT_DEPLOYER_FILENAME ]]; then
    echo "Removed deployer script."
    rm $BACKUP_SCRIPT_DEPLOYER_FILENAME
fi

touch $BACKUP_SCRIPT_DEPLOYER_FILENAME
chmod +x $BACKUP_SCRIPT_DEPLOYER_FILENAME
echo "Created deployer script."

backup_maker_basename=$(basename "$BACKUP_MAKER_FILEPATH")

echo "# Run this script to call the main BackupMaker script." >> $BACKUP_SCRIPT_DEPLOYER_FILENAME
echo "# Expected arguments: bckmaker [input_file_filepath] [output_file_filepath] [backup_dirname] [debug_flag] [preserve_dest_gitfiles_flag] [skip_source_gitfiles_flag]." >> $BACKUP_SCRIPT_DEPLOYER_FILENAME

echo $backup_maker_basename "$(readlink -f $INPUT_INFO_FILE_FILENAME)" "$(readlink -f $OUTPUT_INFO_FILE_FILENAME) $DEFAULT_BACKUP_DIRNAME 0 0 0" >> $BACKUP_SCRIPT_DEPLOYER_FILENAME

echo "Success."
exit 0

