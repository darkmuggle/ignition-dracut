#!/bin/bash -e
#
# THIS IS A REALLY CRUDE UTILITY FOR RAPID TESTING
#

DISK=${DISK:-$1}
DISK=${DISK:?envvar DISK or arg 1 must be a qcow2 disk}

my_d=$(pwd)
tmp_d=$(readlink -f $(mktemp -d initrd.XXX))
export systemdsystemunitdir="/usr/lib/systemd"
export systemdutildir="/etc/system/systemd"

mkdir -p ${tmp_d}/${systemdutildir}
mkdir -p ${tmp_d}/${systemdsystemdutildir}
mkdir -p ${tmp_d}/etc/udev/rules.d
mkdir -p ${tmp_d}/usr/lib/dracut/hooks

trap "rm -rf ${tmp_d} ${my_d}/ostree" EXIT

# mocks...
inst_multiple() { :; }
inst_simple() {
    test -e ${1} || {
        echo "File ${1} was not found";
        return;
    }
    mkdir -p "${tmp_d}/$(dirname ${2})";
    cp -a "${1}" "${tmp_d}/${2}";
}
inst_rules() { inst_simple "${1}" "/etc/udev/rules.d/$(basename ${1})"; }
inst_hook() { inst_simple "${3}" "/usr/lib/dracut/hooks/${1}/${2}-$(basename ${3})"; }
inst_script() { inst_simple "${1}" "${2}"; chmod 0755 "${tmp_d}/${2}"; }

# Now create the test disk that uses
# the real disk as a backing disk.
test_disk="${my_d}/test-$(basename ${DISK})"
rm -rvf ${test_disk}
qemu-img create -b ${DISK} -F qcow2 -f qcow2 ${test_disk}

export LIBGUESTFS_BACKEND=direct
rm -rf ostree
guestfish -a ${test_disk} <<EOM
run
mount /dev/sda1 /
copy-out /ostree ${my_d}
EOM

# Unpack the real initrd
initrd=$(readlink -f ${my_d}/ostree/*/initramfs*)
echo "Found ${initrd}"
(cd ${tmp_d}; lsinitrd --unpack ${initrd};)

# Install our new magical bits
for moddir in $(find dracut -maxdepth 1 -mindepth 1 -type d); do
    echo "Processing: ${moddir}"
    cd ${my_d}/${moddir}; moddir=$(pwd)
    . module-setup.sh
    install
done

cd ${tmp_d}
find . 2>/dev/null \
    | cpio --owner=0:0 -c -o \
    | gzip -c > "${initrd}"

guestfish -a ${test_disk} <<EOM
run
mount /dev/sda1 /
rm-rf /ostree
copy-in ${my_d}/ostree /
EOM


