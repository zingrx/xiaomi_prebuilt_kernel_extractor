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
    local MOUNT_POINT="./${IMAGE_TYPE}/"
    format_message "Extracting ${IMAGE_TYPE} modules..." "1;34"
    mkdir -p ${MOUNT_POINT}
    mkdir -p ${OUT}/${IMAGE_TYPE}
    sudo mount -o ro,loop ${IMAGE_TYPE}.img ${MOUNT_POINT}
    find ${MOUNT_POINT} \( -name "*.load" -o -name "*.ko" \) -exec cp {} ${OUT}/${IMAGE_TYPE}/ \;
    sudo umount ${MOUNT_POINT}
    sudo rm -rf ${MOUNT_POINT} ${IMAGE_TYPE}.img
    print_separator
}

# Function to check and extract archive files
check_and_extract_archive() {
    local ARCHIVE_FILE=$1
    local HASH_FILE="${IN}/archive_info.txt"

    # Get current name and size of the archive file
    local CURRENT_NAME
    CURRENT_NAME=$(basename "${ARCHIVE_FILE}")

    # Read the stored info if it exists
    local STORED_NAME=""
    if [ -f "${HASH_FILE}" ]; then
        read -r STORED_NAME < "${HASH_FILE}"
    fi

    # Check if necessary files are present
    local FILES_PRESENT=true
    for FILE in "boot.img" "dtbo.img" "vendor_boot.img"; do
        if ! find "${IN}" -type f -name "${FILE}*" 1>/dev/null 2>&1; then
            FILES_PRESENT=false
            break
        fi
    done

    # If the archive file hasn't changed and all necessary files are present, skip extraction
    if [ "${CURRENT_NAME}" = "${STORED_NAME}" ] && [ "${FILES_PRESENT}" = true ]; then
        format_message "Archive file unchanged and necessary files present. Skipping extraction..." "1;32"
        return
    fi

    # If we reach this point, either the archive file has changed or necessary files are missing
    format_message "New or updated archive file detected or necessary files missing. Extracting files..." "1;33"
    if [[ "${ARCHIVE_FILE}" == *.zip ]]; then
        find "${IN}" -type f ! \( -name "*.zip" -o -name "*.tgz" \) -delete
        find "${IN}" -type d -delete
        unzip -o "${ARCHIVE_FILE}" -d "${IN}/"
    elif [[ "${ARCHIVE_FILE}" == *.tgz ]]; then
        find "${IN}" -type f ! \( -name "*.zip" -o -name "*.tgz" \) -delete
        find "${IN}" -type d -delete
        tar -xzvf "${ARCHIVE_FILE}" -C "${IN}/"
    fi
    echo "${CURRENT_NAME}" > "${HASH_FILE}"
}

BIN="bin/linux/x86_64/"
VENDOR_RAMDISK="vendor_ramdisk"
DTBS="dtb"
OUT="output"
IN="input"

# Clean old outputs
format_message "Cleaning old runs..." "1;31"
rm -rf ${OUT}
mkdir -p ${OUT}
print_separator

# Check for and extract ZIP or TGZ files
ARCHIVE_FILE=$(find ${IN} -maxdepth 1 \( -name "*.zip" -o -name "*.tgz" \) | head -n 1)
if [ -n "${ARCHIVE_FILE}" ]; then
    check_and_extract_archive "${ARCHIVE_FILE}"
else
    format_message "No archive file found in the input folder. Exiting..." "1;31"
    exit 1
fi
print_separator

# Check if payload.bin exists and extract using payload-dumper-go if it does
if [ -f "${IN}/payload.bin" ]; then
    SYSTEM_DLKM="system_dlkm"
    VENDOR_DLKM="vendor_dlkm"
    format_message "Found payload.bin. Downloading and using payload-dumper-go..." "1;33"
    wget https://github.com/ssut/payload-dumper-go/releases/download/1.2.2/payload-dumper-go_1.2.2_linux_amd64.tar.gz -O payload-dumper-go.tar.gz
    tar -xzf payload-dumper-go.tar.gz -C "${IN}"
    cd "${IN}" || exit 1
    cp "${IN}/payload.bin" .
    ./payload-dumper-go payload.bin
    mv extracted*/*.img .
    mv ${SYSTEM_DLKM}.img ../
    mv ${VENDOR_DLKM}.img ../
    cd - || exit 1
    rm -rf "${IN}/payload-dumper-go_1.2.2_linux_amd64"
    rm payload-dumper-go.tar.gz
    print_separator

else
    # Concatenate super.img then convert to unsparsed format
    format_message "Converting super.img to unsparsed image..." "1;33"
    SYSTEM_DLKM="system_dlkm_a"
    VENDOR_DLKM="vendor_dlkm_a"
    SUPER_IMG_FILES=$(find ${IN} -type f -name "super.img*" | sort)

    if echo "${SUPER_IMG_FILES}" | grep -q 'super.img\.[0-9]'; then
        simg2img ${SUPER_IMG_FILES} super.unsparsed.img
        if [ ! -s super.unsparsed.img ]; then
            format_message "Failed to create super.unsparsed.img or file is empty. Exiting..." "1;31"
            exit 1
        fi 
    else
        SUPER_IMG=$(find ${IN} -type f -name "super.img")
        if [ ! -s ${SUPER_IMG} ]; then
            format_message "super.img not found or file is empty. Exiting..." "1;31"
            exit 1
        fi
        if file "${SUPER_IMG}" | grep -q "sparse"; then
            simg2img ${SUPER_IMG} super.unsparsed.img
        else
            mv ${SUPER_IMG} super.unsparsed.img
        fi
    fi

    # Extracting system_dlkm and vendor_dlkm from super.img
    format_message "Extracting ${SYSTEM_DLKM} and ${VENDOR_DLKM} images..." "1;34"
    ${BIN}/lpunpack -p ${SYSTEM_DLKM} super.unsparsed.img
    ${BIN}/lpunpack -p ${VENDOR_DLKM} super.unsparsed.img
    print_separator
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

# Extract system_dlkm modules
extract_images ${SYSTEM_DLKM}
cd ${OUT}/${SYSTEM_DLKM};rm -r modules.load; find * > modules.load;cd - 1>/dev/null 2>&1;

# Extract vendor_dlkm modules
extract_images ${VENDOR_DLKM}
cd ${OUT}/${VENDOR_DLKM};sort modules.load | uniq > tmp.txt && mv tmp.txt modules.load;cd - 1>/dev/null 2>&1;

# Clean up
format_message "Cleaning working directories..." "1;31"
# Prompt the user for their choice
ARCHIVE_FILE=$(find "${IN}" -type f \( -name "*.zip" -o -name "*.tgz" \) -size +3G -printf "%f\n")
format_message "Choose an option:" "1;32"
echo "1. Delete extracted images and keep ROM >> ${ARCHIVE_FILE}"
echo "2. Delete all files"
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
        format_message "Deleted all files." "1;34"
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
rm -rf super.unsparsed.img
print_separator
format_message "Full prebuilt kernel has been extracted to ${OUT} folder" "1;32"
print_separator
