#!/bin/sh

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

# test if there is any args
usage() {
	echo "poudriere ports [parameters] [options]"
	cat <<EOF

Parameters:
    -c          -- create a portstree
    -d          -- delete a portstree
    -u          -- update a portstree
    -l          -- lists all available portstrees

Options:
    -f          -- when used with -c, only create the needed ZFS
                   filesystems and directories, but do not populare
                   them.
    -p tree     -- specifies on which portstree we work. If not
                   specified, work on a portstree called "default".
EOF

	exit 1
}

create_base_fs() {
	msg_n "Creating basefs:"
	zfs create -o mountpoint=${BASEFS:=/usr/local/poudriere} ${ZPOOL}/poudriere >/dev/null 2>&1 || err 1 " Fail" && echo " done"
}

#Test if the default FS for poudriere exists if not creates it
zfs list ${ZPOOL}/poudriere >/dev/null 2>&1 || create_base_fs

CREATE=0; FAKE=0
UPDATE=0;
DELETE=0;
LIST=0;
while getopts "cfudlp:" FLAG; do
	case "${FLAG}" in
		c)
			CREATE=1
			;;
		f)
			FAKE=1
			;;
		u)
			UPDATE=1
			;;
		p)
			PTNAME=${OPTARG}
			;;
		d)
			DELETE=1
			;;
		l)
			LIST=1
			;;
		*)
			usage
		;;
	esac
done

if [ $(( CREATE + UPDATE + DELETE + LIST )) -lt 1 ]; then
	usage
fi

PTNAME=${PTNAME:-default}

if [ ${LIST} -eq 1 ]; then
	PTNAMES=`zfs list -rH ${ZPOOL}/poudriere | awk '$1 ~ /^'${ZPOOL}'\/poudriere\/ports-[^\/]*$/ { sub(/^'${ZPOOL}'\/poudriere\/ports-/, "", $1); print $1 }'`
	for PTNAME in ${PTNAMES}; do
		echo $PTNAME
	done
else
	test -z "${PTNAME}" && usage
fi
if [ ${CREATE} -eq 1 ]; then
	# test if it already exists
	zfs list -r ${ZPOOL}/poudriere/ports-${PTNAME} >/dev/null 2>&1 && err 2 "The ports tree ${PTNAME} already exists"
	PTBASE=${BASEFS:=/usr/local/poudriere}/ports/${PTNAME}
	msg_n "Creating ports-${PTNAME} fs..."
	zfs create -o mountpoint=${PTBASE} ${ZPOOL}/poudriere/ports-${PTNAME} > /dev/null 2>&1 || err 1 " Fail" && echo " done"
	mkdir ${PTBASE}/ports
	if [ $FAKE -eq 0 ]; then
		mkdir ${PTBASE}/snap
		msg "Extracting portstree \"${PTNAME}\"..."
		/usr/sbin/portsnap -d ${PTBASE}/snap -p ${PTBASE}/ports fetch extract || \
		/usr/sbin/portsnap -d ${PTBASE}/snap -p ${PTBASE}/ports fetch extract || \
		{
			zfs destroy ${ZPOOL}/poudriere/ports-${PTNAME}
			err 1 " Fail"
		}
	fi
fi

if [ ${DELETE} -eq 1 ]; then
	/sbin/mount -t nullfs | /usr/bin/grep -q "${PTNAME}/ports on" \
		&& err 1 "Ports tree \"${PTNAME}\" is already used."
	zfs list -r ${ZPOOL}/poudriere/ports-${PTNAME} >/dev/null 2>&1 || err 2 "No such ports tree ${PTNAME}"
	msg "Deleting portstree \"${PTNAME}\""
	zfs destroy ${ZPOOL}/poudriere/ports-${PTNAME}
fi

if [ ${UPDATE} -eq 1 ]; then
	/sbin/mount -t nullfs | /usr/bin/grep -q "${PTNAME}/ports on" \
		&& err 1 "Ports tree \"${PTNAME}\" is already used."
	PTBASE=$(zfs list -H -o mountpoint ${ZPOOL}/poudriere/ports-${PTNAME})
	msg "Updating portstree \"${PTNAME}\""
	/usr/sbin/portsnap -d ${PTBASE}/snap -p ${PTBASE}/ports fetch update
fi
