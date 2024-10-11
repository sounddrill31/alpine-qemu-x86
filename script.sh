#!/bin/bash

VM_NAME="via_eden_vm"
RAM_SIZE="128M"
STORAGE_SIZE="64M"
IMAGE_FILE="${VM_NAME}.img"

create_vm() {
    echo "Creating VM image..."
    qemu-img create -f qcow2 $IMAGE_FILE $STORAGE_SIZE
    if [ $? -ne 0 ]; then
        echo "Failed to create VM image."
        exit 1
    fi
    echo "VM image created successfully."
}

start_vm() {
    echo "Starting VM and connecting to it..."
    qemu-system-i386 -m $RAM_SIZE -cpu qemu32 -drive file=$IMAGE_FILE,format=qcow2 -cdrom ${VM_NAME}.iso -boot d -nographic -serial mon:stdio

#    qemu-system-i386 -m $RAM_SIZE -cpu qemu32 -drive file=$IMAGE_FILE,format=qcow2 -nographic -serial mon:stdio
}
download_rootfs() {
    ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86/alpine-minirootfs-3.20.3-x86.tar.gz"
    ROOTFS_FILE="alpine-minirootfs-3.20.3-x86.tar.gz"
    echo "Downloading Alpine Linux rootfs..."
    wget $ROOTFS_URL -O $ROOTFS_FILE
    if [ $? -ne 0 ]; then
        echo "Failed to download rootfs."
        exit 1
    fi
    echo "Rootfs downloaded successfully."
}

setup_rootfs() {
    echo "Setting up rootfs..."
    mkdir -p rootfs
    tar -xzf alpine-minirootfs-3.20.3-x86.tar.gz -C rootfs
    if [ $? -ne 0 ]; then
        echo "Failed to extract rootfs."
        exit 1
    fi
    echo "Rootfs set up successfully."
}

compile_kernel() {
    KERNEL_REPO="https://github.com/torvalds/linux.git"
    KERNEL_DIR="linux"
    echo "Cloning Linux kernel repository..."

    if [ -d "$KERNEL_DIR" ]; then
        echo "Kernel directory already exists. Skipping clone."
    else
        git clone $KERNEL_REPO $KERNEL_DIR --depth=1
        if [ $? -ne 0 ]; then
            echo "Failed to clone Linux kernel repository."
            exit 1
        fi
    fi

    # deps: flex, bc, libelf-devel, libssl-dev    sudo apt-get install libssl-dev
    if [ "$1" == "--rebuild-kernel" ] || [ ! -f "$KERNEL_DIR/arch/x86/boot/*Image" ]; then
        cd $KERNEL_DIR
        make mrproper
        scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_SIZE
        echo "Configuring and compiling the kernel..."
        make ARCH=x86 defconfig
        make ARCH=x86 INSTALL_MOD_STRIP=1 KCFLAGS="-Os" -j$(nproc)
        if [ $? -ne 0 ]; then
            echo "Failed to compile the kernel."
            exit 1
        fi
        echo "Kernel compiled successfully."
        echo "Size:"
        ls -lh arch/x86/boot/*Image
        cd ..
    else
        echo "Kernel image already exists. Skipping rebuild."
    fi
}

setup_boot() {
    echo "Setting up boot configuration..."
    KERNEL_IMAGE="linux/arch/x86/boot/bzImage"
    mkdir -p rootfs/boot/
    cp $KERNEL_IMAGE rootfs/boot/
    if [ $? -ne 0 ]; then
        echo "Failed to copy kernel image."
        exit 1
    fi
    echo "Boot configuration set up successfully."
}

# deps: e2fsprogs, genisoimage
create_vm() {
    echo "Creating VM image..."
    qemu-img create -f qcow2 $IMAGE_FILE $STORAGE_SIZE
    if [ $? -ne 0 ]; then
        echo "Failed to create VM image."
        exit 1
    fi
    echo "VM image created successfully."

    download_rootfs
    setup_rootfs
    compile_kernel
    setup_boot

    echo "Creating ISO image..."
    mkdir -p iso_root
    cp -r rootfs/* iso_root/
    mkisofs -o ${VM_NAME}.iso -b boot/bzImage -c boot/boot.catalog -no-emul-boot -boot-load-size 4 -boot-info-table iso_root
    if [ $? -ne 0 ]; then
        echo "Failed to create ISO image."
        exit 1
    fi
    echo "ISO image created successfully."
}
list_vms() {
    echo "Listing running VMs..."
    pgrep -a qemu-system
}

connect_vm() {
    echo "Connecting to VM..."
    # Assuming you want to connect to the first running VM
    VM_PID=$(pgrep -o qemu-system)
    if [ -n "$VM_PID" ]; then
        echo "Connecting to VM with PID $VM_PID..."
        # Use screen or another terminal multiplexer to connect
        screen -r $VM_PID
    else
        echo "No running VMs found."
    fi
}

if [ "$1" == "--create" ]; then
    create_vm "$2"
elif [ "$1" == "--list" ]; then
    list_vms
elif [ "$1" == "--connect" ]; then
    connect_vm
else
    start_vm
fi
