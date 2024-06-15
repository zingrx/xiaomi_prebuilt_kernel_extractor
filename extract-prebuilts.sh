#!/bin/bash

# Function to format messages in bold and with different colors
format_message() {
    echo -e "\033[$2m$1\033[0m"
}

# Function to print a separator
print_separator() {
    echo -e "\033[1;37m----------------------------------------\033[0m"
}

# Function to extract images
extract_images() {
    local IMAGE_TYPE=$1
    local MOUNT_POINT="/mnt/${IMAGE_TYPE}/"
    format_message "Extracting ${IMAGE_TYPE} modules..." "1;34"
    sudo mkdir -p ${MOUNT_POINT}
    mkdir -p ${OUT}/${IMAGE_TYPE}
    sudo mount -o ro,loop ${IMAGE_TYPE}_a.img ${MOUNT_POINT}
    find ${MOUNT_POINT} \( -name "*.load" -o -name "*.ko" \) -exec cp {} ${OUT}/${IMAGE_TYPE}/ \;
    sudo umount ${MOUNT_POINT}
    print_separator
}

# Function to check and extract ZIP files
check_and_extract_zip() {
    local ZIP_FILE=$1
    local HASH_FILE="${IN}/zip_info.txt"

    # # Check if necessary files already exist
    # if [ -f "${IN}/images/boot.img" ] && [ -f "${IN}/images/dtbo.img" ] && [ -f "${IN}/images/vendor_boot.img" ] && ls "${IN}/images/super.img"* 1>/dev/null 2>&1; then
    #     format_message "Necessary files already exist. Skipping extraction..." "1;32"
    #     return
    # fi
    
    # Get current name and size of the ZIP file
    local CURRENT_NAME
    CURRENT_NAME=$(basename "${ZIP_FILE}")
    local CURRENT_SIZE
    CURRENT_SIZE=$(stat -c "%s" "${ZIP_FILE}")

    # Read the stored info if it exists
    local STORED_NAME=""
    local STORED_SIZE=""
    if [ -f "${HASH_FILE}" ]; then
        read -r STORED_NAME STORED_SIZE < "${HASH_FILE}"
    fi

    # Check if necessary files are missing and the ZIP file hasn't changed
    if [ "${CURRENT_NAME}" = "${STORED_NAME}" ] && [ "${CURRENT_SIZE}" = "${STORED_SIZE}" ]; then
        if [ -f "${IN}/images/boot.img" ] && [ -f "${IN}/images/dtbo.img" ] && [ -f "${IN}/images/vendor_boot.img" ] && ls "${IN}/images/super.img"* 1>/dev/null 2>&1; then
            format_message "ZIP file unchanged, but necessary files are missing. Extracting files..." "1;33"
            unzip -o "${ZIP_FILE}" -d "${IN}/"
        else
            format_message "ZIP file unchanged and necessary files present. Skipping extraction..." "1;32"
        fi
    else
        format_message "New or updated ZIP file detected. Extracting files..." "1;33"
        unzip -o "${ZIP_FILE}" -d "${IN}/"
        echo "${CURRENT_NAME} ${CURRENT_SIZE}" > "${HASH_FILE}"
    fi

    # Keep only the necessary files
    find "${IN}" -type f ! \( -name "boot.img" -o -name "dtbo.img" -o -name "vendor_boot.img" -o -name "super.img*" -o -name "*.zip" \) -delete
    find "${IN}" -type d ! \( -name "images" \) -delete
}

BIN="bin/linux/x86_64/"
SYSTEM_DLKM="system_dlkm"
VENDOR_DLKM="vendor_dlkm"
VENDOR_RAMDISK="vendor_ramdisk"
DTBS="dtb"
OUT="output"
IN="input"

# Clean old outputs
format_message "Cleaning old runs..." "1;31"
rm -rf ${OUT}
mkdir ${OUT}
print_separator

# Check for and extract ZIP files
format_message "Checking if the input zip file is changed..." "1;34"
ZIP_FILE=$(find ${IN} -maxdepth 1 -name "*.zip" | head -n 1)
if [ -n "${ZIP_FILE}" ]; then
    check_and_extract_zip "${ZIP_FILE}"
else
    format_message "No ZIP file found in the input folder. Exiting..." "1;31"
    exit 1
fi

print_separator

# Concatenate super.img then convert to unsparsed format
format_message "Converting super.img to unsparsed image..." "1;33"
simg2img "${IN}"/images/super.img.* super.unsparsed.img

if [ ! -s super.unsparsed.img ]; then
    format_message "Failed to create super.unsparsed.img or file is empty. Exiting..." "1;31"
    exit 1
fi

format_message "Getting dtbo image..." "1;33"
cp $(find ${IN} -type f -name "dtbo.img") ${OUT}/
print_separator

# Extract prebuilt kernel from boot.img
format_message "Extracting kernel..." "1;34"
BOOT_IMG=$(find "${IN}" -type f -name "boot.img")
./unpackimg.sh "${BOOT_IMG}"
cp split_img/boot.img-kernel ./${OUT}/kernel
print_separator

# Extract vendor_boot ramdisk
format_message "Extracting ${VENDOR_RAMDISK} modules..." "1;34"
VENDOR_BOOT_IMG=$(find "${IN}" -type f -name "vendor_boot.img")
./unpackimg.sh "${VENDOR_BOOT_IMG}"
mkdir -p ${OUT}/${VENDOR_RAMDISK}
cp -R ramdisk/lib/modules/* ${OUT}/${VENDOR_RAMDISK}/
print_separator

# Extract dtbs from vendor_boot.img
format_message "Extracting ${DTBS} from vendor_boot..." "1;34"
git clone https://github.com/PabloCastellano/extract-dtb
./extract-dtb/extract_dtb/extract_dtb.py split_img/vendor_boot.img-dtb -o ${OUT}/${DTBS}
print_separator

# Extracting system_dlkm and vendor_dlkm from super.img
format_message "Extracting ${SYSTEM_DLKM} and ${VENDOR_DLKM} images..." "1;34"
${BIN}/lpunpack -p ${SYSTEM_DLKM}_a super.unsparsed.img
${BIN}/lpunpack -p ${VENDOR_DLKM}_a super.unsparsed.img
print_separator

# Extract system_dlkm modules
extract_images ${SYSTEM_DLKM}

# Extract vendor_dlkm modules
extract_images ${VENDOR_DLKM}

# Clean up
format_message "Cleaning working directories..." "1;31"
# Prompt the user for their choice
ARCHIVE_FILE=$(find "${IN}" -type f \( -name "*.zip" -o -name "*.tgz" \) -size +3G -printf "%f\n")
format_message "Choose an option:" "1;32"
echo "1. Delete extracted images and keep ROM >> ${ARCHIVE_FILE}"
echo "2. Delete extracted images and ROM >> ${ARCHIVE_FILE}"
echo "3. Keep all files"
read -p "Enter your choice (1/2/3): " choice
choice=${choice:-1}
case $choice in
    1)
        # Delete all files in the working directory except the rom file
        find ${IN} ! -name ${ARCHIVE_FILE} -delete
        format_message "Deleted images files in ${IN} except ${ARCHIVE_FILE}." "1;34"
        ;;
    2)
        # Delete all files in the working directory including the rom file
        rm -rf "${IN}"/*
        format_message "Deleted images files in ${IN} and ${ARCHIVE_FILE}." "1;34"
        ;;
    3)
        # Keep all files
        format_message "No files were deleted." "1;34"
        ;;
    *)
        format_message "Invalid choice. No files were deleted." "1;31"
        ;;
esac
./cleanup.sh
rm -rf extract-dtb
sudo rm -rf /mnt/${SYSTEM_DLKM}
sudo rm -rf /mnt/${VENDOR_DLKM}
rm -rf ${VENDOR_DLKM}_a.img
rm -rf ${SYSTEM_DLKM}_a.img
rm -rf super.unsparsed.img
print_separator
format_message "Full prebuilt kernel has been extracted to ${OUT} folder" "1;32"
print_separator