# Xiaomi Prebuilt Kernel Extractor

This tool helps extract all necessary files to build aosp/los ROM for xiaomi devices with a prebuilt kernel. It uses AIK for Linux + dependencies files from XDA thread package

## Steps:
### 1. Clone the full repo.
```
git clone https://github.com/zingrx/xiaomi_prebuilt_kernel_extractor
```
### 2. Copy your HyperOS zip file to the `input` folder.
Currently supported ROMs:
- Original Xiaomi CN (tgz)
- Xiaomi-EU ROMs (zip)

### 3. Run the below command.
```
./extract-prebuilts.sh
# Some steps within the script require sudo, so you'll be prompted to enter your password.
```
### 4. All the needed files will be placed in the `output` folder.
Just copy them to your prebuilt kernel tree.

## Note:
- It's not possible to build without exporting the kernel-headers from the kernel source. It's on the ToDo list for this project.
- An example of a full xiaomi prebuilt-kernel tree is [here](https://github.com/lolipuru/device_xiaomi_fuxi-kernel/).

## Credits:
- osm0sis @ [XDA-developers](https://forum.xda-developers.com/showthread.php?t=2073775)
- @SebaUbuntu for Linux support
- @lolipuru for xiaomi tree support

Tested on Xiaomi 13, Xiaomi 14 and Redmi K70 Pro ROMs.
