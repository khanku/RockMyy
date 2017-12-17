#!/bin/bash -x

export ARCH=arm
#export CROSS_COMPILE=armv7a-hardfloat-linux-gnueabi-

export KERNEL_GIT_URL='https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'

# 4.14.6
export KERNEL_SERIES=v4.14
export KERNEL_BRANCH=linux-4.14.y
export LOCALVERSION=-c201

export DTB_FILES="rk3288-veyron-speedy.dtb"

export PATCHES_DIR=patches
export KERNEL_PATCHES_DIR=$PATCHES_DIR/kernel/$KERNEL_SERIES
export KERNEL_PATCHES_DTS_DIR=$KERNEL_PATCHES_DIR/DTS
export CONFIG_FILE_PATH=config/$KERNEL_SERIES/config-latest

export BASE_FILES_URL=https://raw.githubusercontent.com/$GITHUB_REPO/$GIT_BRANCH
export KERNEL_PATCHES_DIR_URL=$BASE_FILES_URL/$KERNEL_PATCHES_DIR
export KERNEL_DTS_PATCHES_DIR_URL=$BASE_FILES_URL/$KERNEL_PATCHES_DTS_DIR
export CONFIG_FILE_URL=$BASE_FILES_URL/config/$KERNEL_SERIES/config-latest

export KERNEL_PATCHES="
0001-drivers-Integrating-Mali-Midgard-video-and-gpu-drive.patch
0002-clk-rockchip-add-all-known-operating-points-to-the-a.patch
0003-clk-rockchip-rk3288-prefer-vdpu-for-vcodec-clock-sou.patch
0004-Remove-the-dependency-to-the-clk_mali-symbol.patch
0006-soc-rockchip-power-domain-export-idle-request.patch
"

export KERNEL_DTS_PATCHES="
0001-dts-rk3288-miqi-Enabling-the-Mali-GPU-node.patch
0002-ARM-dts-rockchip-fix-the-regulator-s-voltage-range-o.patch
0003-ARM-dts-rockchip-add-the-MiQi-board-s-fan-definition.patch
0004-ARM-dts-rockchip-add-support-for-1800-MHz-operation-.patch
0005-Readapt-ARM-dts-rockchip-miqi-add-turbo-mode-operati.patch
0006-ARM-DTSI-rk3288-Missing-GRF-handles.patch
0007-RK3288-DTSI-rk3288-Add-missing-SPI2-pinctrl.patch
0008-Added-support-for-Tinkerboard-s-SPI-interface.patch
0010-ARM-DTSI-rk3288-Adding-cells-addresses-and-size.patch
0011-ARM-DTSI-rk3288-Adding-missing-EDP-power-domain.patch
0013-ARM-DTSI-rk3288-Adding-missing-VOPB-registers.patch
0014-ARM-DTSI-rk3288-Fixed-the-SPDIF-node-address.patch
0015-ARM-DTS-rk3288-tinker-Enabling-SDIO-Wireless-and.patch
0016-ARM-DTS-rk3288-tinker-Improving-the-CPU-max-volt.patch
0017-ARM-DTS-rk3288-tinker-Setting-up-the-SD-regulato.patch
0018-ARM-DTS-rk3288-tinker-Defined-the-I2C-interfaces.patch
0019-ARM-DTS-rk3288-tinker-Add-the-MIPI-DSI-node.patch
0020-ARM-DTS-rk3288-tinker-Defining-the-SPI-interface.patch
0021-ARM-DTS-rk3288-tinker-Defining-SDMMC-properties.patch
0022-ARM-DTSI-rk3288-Define-the-VPU-services.patch
0023-ARM-DTS-rk3288-miqi-Enable-the-Video-encoding-MM.patch
0024-ARM-DTS-rk3288-tinker-Enable-the-Video-encoding-MMU-.patch
0025-ARM-DTSI-rk3288-firefly-Enable-the-Video-encoding-MM.patch
0026-ARM-DTSI-rk3288-veyron-Enable-the-Video-encoding-MMU.patch
0027-ARM-DTSI-rk3288-fix-errors-in-IOMMU-interrupts-prope.patch
"

# -- Helper functions

function die_on_error {
	if [ ! $? = 0 ]; then
		echo $1
		exit 1
	fi
}

function download_patches {
	base_url=$1
	patches=${@:2}
	for patch in $patches; do
		wget $base_url/$patch ||
		{ echo "Could not download $patch"; exit 1; }
	done
}

function download_and_apply_patches {
	base_url=$1
	patches=${@:2}
	download_patches $base_url $patches
	git apply $patches
	die_on_error "Could not apply the downloaded patches"
	rm $patches
}

function copy_and_apply_patches {
	patch_base_dir=$1
	patches=${@:2}
	
	apply_dir=$PWD
	cd $patch_base_dir
	cp $patches $apply_dir || 
	{ echo "Could not copy $patch"; exit 1; }
	cd $apply_dir
	git apply $patches
	die_on_error "Could not apply the copied patches"
	rm $patches
}

# Get the kernel

# If we haven't already clone the Linux Kernel tree, clone it and move
# into the linux folder created during the cloning.
if [ ! -d "linux" ]; then
  git clone --depth 1 --branch $KERNEL_BRANCH $KERNEL_GIT_URL linux
  die_on_error "Could not git the kernel"
fi
cd linux
export SRC_DIR=$PWD

# Check if the tree is patched
if [ ! -e "PATCHED" ]; then
  # If not, cleanup, apply the patches, commit and mark the tree as 
  # patched
  
  # Remove all untracked files. These are residues from failed runs
  git clean -fdx &&
  # Rewind modified files to their initial state.
  git checkout -- .

  # Cleanup, get the configuration file and mark the tree as patched
  echo "RockMyy" > PATCHED &&
  git add . &&
  git commit -m "Apply ALL THE PATCHES !"
fi

# Download a .config file if none present
if [ ! -e ".config" ]; then
  make mrproper
  if [ ! -f "../$CONFIG_FILE_PATH" ]; then
    wget -O .config $CONFIG_FILE_URL
  else
    cp "../$CONFIG_FILE_PATH" .config
  fi
  die_on_error "Could not get the configuration file..."
fi

if [ -z ${MAKE_CONFIG+x} ]; then
  export MAKE_CONFIG=oldconfig
fi

make $MAKE_CONFIG

set -e
make -j1 modules
make -j1 zImage
make -j1 "$DTB_FILES"

mkimage -D "-I dts -O dtb -p 2048" -f kernel.its vmlinux.uimg
dd if=/dev/zero of=bootloader.bin bs=512 count=1
vbutil_kernel --pack vmlinux.kpart \
              --version 1 \
              --vmlinuz vmlinux.uimg \
              --arch arm \
              --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
              --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
              --config ../cmdline \
              --bootloader bootloader.bin
