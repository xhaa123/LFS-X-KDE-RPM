#!/bin/bash
#################################################
#	Title:	01-mk-tools			#
#        Date:	2021-04-29			#
#     Version:	1.0				#
#      Author:	baho-utot@columbus.rr.com	#
#     Options:					#
# Modified by:	xhaa123@163.com			#
#################################################
set -o errexit	# exit if error...insurance ;)
set -o nounset	# exit if variable not initalized
set +h			# disable hashall
#-----------------------------------------------------------------------------
#	Common variables
PRGNAME=${0##*/}		# script name minus the path
TOPDIR=${PWD}			# this directory
PARENT=/usr/src/LFS-RPM	# build system master directory
MKFLAGS="-j 1"		# Number of cpu to use in building pkgs default = 1
#-----------------------------------------------------------------------------
#	Common support functions
function die {
	local _red="\\033[1;31m"
	local _normal="\\033[0;39m"
	[ -n "$*" ] && printf "${_red}$*${_normal}\n"
	false
	exit 1
}
function msg {
	printf "%s\n" "${1}"
	return
}
function msg_line {
	printf "%s" "${1}"
	return
}
function msg_failure {
	local _red="\\033[1;31m"
	local _normal="\\033[0;39m"
	printf "${_red}%s${_normal}\n" "FAILURE"
	exit 2
}
function msg_success {
	local _green="\\033[1;32m"
	local _normal="\\033[0;39m"
	printf "${_green}%s${_normal}\n" "SUCCESS"
	return
}
function msg_log {
	printf "\n%s\n\n" "${1}" >> ${_logfile} 2>&1
	return
}
function end_run {
	local _green="\\033[1;32m"
	local _normal="\\033[0;39m"
	printf "${_green}%s${_normal}\n" "Run Complete - ${PRGNAME}"
	return
}
#-----------------------------------------------------------------------------
#	Local functions
function _sanity {
	[ $(whoami) = "lfs" ] || die "Not running as user lfs, you should be!"
	[ -v LFS ] || die "LFS environment variable missing/not set"
	[ "/tools/bin:/bin:/usr/bin" = "${PATH}" ] || die "PATH environment variable missing/not corrrect"
	[ -v LFS_TGT ] || die "LFS_TGT environment variable missing/not set"
	[ "${HOSTTYPE}-lfs-${OSTYPE}" = "${LFS_TGT}" ] || die "LFS_TGT environment variable incorrect"
	[ -d ${LFS} ]	 || die "${LFS} directory missing"
	[ -d ${LFS}/tools ] || die "${LFS}/tools directory missing"
	[ -h /tools ] || die "tools root symlink missing"
	[ $(stat -c %U ${LFS}/tools) = "lfs" ] || die "The tools directory not owned by user lfs"
	[ ${TOPDIR} = ${LFS}${PARENT} ] || die "Not in the correct build directory"
	[ -d "${TOPDIR}/LOGS" ] || install -dm 755 "${TOPDIR}/LOGS"
	[ -d "${TOPDIR}/BUILD" ] || install -dm 755 "${TOPDIR}/BUILD"
	return
}
function do_strip {
	msg_line "Stripping file: "
		strip --strip-debug /tools/lib/* > /dev/null 2&>1 || true
		/usr/bin/strip --strip-unneeded /tools/{,s}bin/* > /dev/null 2&>1 || true
		rm -rf /tools/{,share}/{info,man,doc}
		find /tools/{lib,libexec} -name \*.la -delete
	msg_success
	return
}
function set-mkflags {
	msg_line "Setting MKFLAGS: "
		MKFLAGS="-j 1" 						# default
		MKFLAGS="-j $(getconf _NPROCESSORS_ONLN || true)"	# how many processors on this host
		[ '-j' == "${MKFLAGS}" ] && MKFLAGS="-j 2"		# set two cpu's default
		printf "%s" "${FUNCNAME}: MKFLAGS: ${MKFLAGS}: "
	msg_success
	return
}
function unpack {
	# $1 = source package name
	local tarball=${TOPDIR}/SOURCES/${1}
	msg_line "	Unpacking: ${1}: "
		[ -e ${tarball} ] || die " File not found: FAILURE"
		tar xf ${tarball} && msg_success || msg_failure
	return 0
}
function clean-build-directory {
	msg_line "Cleaning BUILD directory: "
		rm -rf ${TOPDIR}/BUILD/*
		rm -rf ${TOPDIR}/BUILDROOT/*
	msg_success
	return
}
#-----------------------------------------------------------------------------
#	Package functions
function Binutils-Pass-1 {
	local pkg=binutils-2.36.1.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			mkdir build
			pushd build >> /dev/null 2>&1
				msg_line "	Configure: "
					../configure --prefix=/tools \
						--with-sysroot=${LFS} \
						--with-lib-path=/tools/lib \
						--target=${LFS_TGT} \
						--disable-nls \
						--disable-werror >> ${logfile} 2>&1
				msg_success
				msg_line "	     Make: "
					make ${MKFLAGS} >> ${logfile} 2>&1
				msg_success
				msg_line "	  Install: "
					install -vdm 755 /tools/lib >> ${logfile} 2>&1
					[ "x86_64" = ${HOSTTYPE} ] && ln -sv lib /tools/lib64 >> ${logfile} 2>&1
					make install >> ${logfile} 2>&1
				msg_success
			popd > /dev/null 2>&1
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function GCC-Pass-1 {
	local pkg=gcc-10.3.0.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			for file in gcc/config/{linux,i386/linux{,64}}.h; do
			  cp -uv $file{,.orig}
			  sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
			      -e 's@/usr@/tools@g' $file.orig > $file
			  echo '
			#undef STANDARD_STARTFILE_PREFIX_1
			#undef STANDARD_STARTFILE_PREFIX_2
			#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
			#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
			  touch $file.orig
			done
			case ${HOSTTYPE} in
				x86_64)	sed -e '/m64=/s/lib64/lib/'  -i.orig gcc/config/i386/t-linux64
					;;
			esac
			unpack mpfr-4.1.0.tar.xz
			unpack gmp-6.2.1.tar.xz
			unpack mpc-1.2.1.tar.gz
			mv -v mpfr-4.1.0 mpfr >> ${logfile} 2>&1
			mv -v gmp-6.2.1 gmp >> ${logfile} 2>&1
			mv -v mpc-1.2.1 mpc >> ${logfile} 2>&1
			mkdir  build
			pushd build >> /dev/null 2>&1
				msg_line "	Configure: "
					../configure \
						--target=${LFS_TGT} \
						--prefix=/tools \
						--with-glibc-version=2.11 \
						--with-sysroot=${LFS} \
						--with-newlib \
						--without-headers \
						--with-local-prefix=/tools \
						--with-native-system-header-dir=/tools/include \
						--disable-nls \
						--disable-shared \
						--disable-multilib \
						--disable-decimal-float \
						--disable-threads \
						--disable-libatomic \
						--disable-libgomp \
						--disable-libmpx \
						--disable-libquadmath \
						--disable-libssp \
						--disable-libvtv \
						--disable-libstdcxx \
						--enable-languages=c,c++ >> ${logfile} 2>&1
				msg_success
				msg_line "	     Make: "
					make ${MKFLAGS} >> ${logfile} 2>&1
				msg_success
				msg_line "	  Install: "
					make install >> ${logfile} 2>&1
				msg_success
			popd > /dev/null 2>&1
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Linux-API-Headers {
	local pkg=linux-5.12.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	     Make: "
				make mrproper  >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make headers  >> ${logfile} 2>&1
				find usr/include -name '.*' -delete  >> ${logfile} 2>&1
				rm usr/include/Makefile  >> ${logfile} 2>&1
				cp -rv usr/include/* /tools/include  >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Glibc {
	local pkg=glibc-2.33.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			mkdir build
			pushd build >> /dev/null 2>&1
				msg_line "	Configure: "
					../configure \
						--prefix=/tools \
						--host=${LFS_TGT} \
						--build=$(../scripts/config.guess) \
						--enable-kernel=3.2 \
						--with-headers=/tools/include >> ${logfile} 2>&1
				msg_success
				msg_line "	     Make: "
					make ${MKFLAGS} >> ${logfile} 2>&1
				msg_success
				msg_line "	  Install: "
					make install >> ${logfile} 2>&1
				msg_success
			popd > /dev/null 2>&1
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	msg_line " Testing glibc: "
		echo 'int main(){}' > dummy.c
		${LFS_TGT}-gcc dummy.c	>> ${logfile}.test 2>&1
		echo "Test: [Requesting program interpreter: /tools/lib64/ld-linux-x86-64.so.2]" >> ${logfile}.test 2>&1
		readelf -l a.out | grep ': /tools' >> ${logfile}.test 2>&1
		rm dummy.c a.out
	msg_success
	return
}
function Libstdc {
	local pkg=gcc-10.3.0.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
			pushd ${pkg_dir} >> /dev/null 2>&1
			mkdir build
			pushd build >> /dev/null 2>&1
				msg_line "	Configure: "
					../libstdc++-v3/configure \
						--host=${LFS_TGT} \
						--prefix=/tools \
						--disable-multilib \
						--disable-nls \
						--disable-libstdcxx-threads \
						--disable-libstdcxx-pch \
						--with-gxx-include-dir=/tools/${LFS_TGT}/include/c++/10.3.0 >> ${logfile} 2>&1
				msg_success
				msg_line "	     Make: "
					make ${MKFLAGS} >> ${logfile} 2>&1
				msg_success
				msg_line "	  Install: "
					make install >> ${logfile} 2>&1
				msg_success
			popd > /dev/null 2>&1
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Binutils-Pass-2 {
	local pkg=binutils-2.36.1.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			mkdir build
			pushd build >> /dev/null 2>&1
				msg_line "	Configure: "
					CC=${LFS_TGT}-gcc \
					AR=${LFS_TGT}-ar \
					RANLIB=${LFS_TGT}-ranlib \
					../configure \
						--prefix=/tools \
						--disable-nls \
						--disable-werror \
						--with-lib-path=/tools/lib \
						--with-sysroot >> ${logfile} 2>&1
				msg_success
				msg_line "	     Make: "
					make ${MKFLAGS} >> ${logfile} 2>&1
				msg_success
				msg_line "	  Install: "
					make install >> ${logfile} 2>&1
				msg_success
				msg_line "	Prepare the linker for Re-adjusting: "
					make -C ld clean >> ${logfile} 2>&1
					make -C ld LIB_PATH=/usr/lib:/lib >> ${logfile} 2>&1
					cp -v ld/ld-new /tools/bin >> ${logfile} 2>&1
				msg_success
			popd > /dev/null 2>&1
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function GCC-Pass-2 {
	local pkg=gcc-10.3.0.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			cat gcc/limitx.h gcc/glimits.h gcc/limity.h > `dirname $(${LFS_TGT}-gcc -print-libgcc-file-name)`/include-fixed/limits.h
			for file in gcc/config/{linux,i386/linux{,64}}.h
			do
			  cp -uv $file{,.orig}
			  sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
			      -e 's@/usr@/tools@g' $file.orig > $file
			  echo '
			#undef STANDARD_STARTFILE_PREFIX_1
			#undef STANDARD_STARTFILE_PREFIX_2
			#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
			#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
			  touch $file.orig
			done
			case ${HOSTTYPE} in
				x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
					;;
			esac
			unpack mpfr-4.1.0.tar.xz
			unpack gmp-6.2.1.tar.xz
			unpack mpc-1.2.1.tar.gz
			mv -v mpfr-4.1.0 mpfr >> ${logfile} 2>&1
			mv -v gmp-6.2.1 gmp >> ${logfile} 2>&1
			mv -v mpc-1.2.1 mpc >> ${logfile} 2>&1
			mkdir build
			pushd build >> /dev/null 2>&1
				msg_line "	Configure: "
					CC=${LFS_TGT}-gcc \
					CXX=${LFS_TGT}-g++ \
					AR=${LFS_TGT}-ar \
					RANLIB=${LFS_TGT}-ranlib \
					../configure \
						--prefix=/tools \
						--with-local-prefix=/tools \
						--with-native-system-header-dir=/tools/include \
						--enable-languages=c,c++ \
						--disable-libstdcxx-pch \
						--disable-multilib \
						--disable-bootstrap \
						--disable-libgomp >> ${logfile} 2>&1
				msg_success
				msg_line "	     Make: "
					make ${MKFLAGS} >> ${logfile} 2>&1
				msg_success
				msg_line "	  Install: "
					make install >> ${logfile} 2>&1
					ln -sv gcc /tools/bin/cc >> ${logfile} 2>&1
				msg_success
			popd > /dev/null 2>&1
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	msg_line "Testing gcc pass-2: "
		echo 'int main(){}' > dummy.c
		cc dummy.c >> ${logfile}.test 2>&1
		echo "Test: [Requesting program interpreter: /tools/lib64/ld-linux-x86-64.so.2]" >> ${logfile}.test 2>&1
		readelf -l a.out | grep ': /tools'	>> ${logfile}.test 2>&1
		rm dummy.c a.out
	msg_success
	return
}
function Tcl {
	local pkg=tcl8.6.11-src.tar.gz
	local pkg_dir=${pkg%%-src*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			cd unix
			msg_line "	Configure: "
				./configure  --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
				chmod -v u+w /tools/lib/libtcl8.6.so >> ${logfile} 2>&1
				make install-private-headers >> ${logfile} 2>&1
				ln -sv tclsh8.6 /tools/bin/tclsh >> ${logfile} 2>&1
			msg_success
			cd -
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Expect {
	local pkg=expect5.45.4.tar.gz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				cp -v configure{,.orig}  >> ${logfile} 2>&1
				sed 's:/usr/local/bin:/bin:' configure.orig > configure
				./configure \
					--prefix=/tools \
					--with-tcl=/tools/lib \
					--with-tclinclude=/tools/include>> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make SCRIPTS="" install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function DejaGNU {
	local pkg=dejagnu-1.6.2.tar.gz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
#	M4-1.4.18
function M4 {
	local pkg=m4-1.4.18.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' lib/*.c  >> ${logfile} 2>&1
				echo "#define _IO_IN_BACKUP 0x100" >> lib/stdio-impl.h
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Ncurses {
	local pkg=ncurses-6.2.tar.gz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				sed -i s/mawk// configure >> ${logfile} 2>&1
				./configure \
					--prefix=/tools \
					--with-shared \
					--without-debug \
					--without-ada \
					--enable-widec \
					--enable-overwrite >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
				ln -s libncursesw.so /tools/lib/libncurses.so >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Bash {
	local pkg=bash-5.1.tar.gz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools --without-bash-malloc >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
				ln -sv bash /tools/bin/sh >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Bison {
	local pkg=bison-3.7.6.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Bzip {
	local pkg=bzip2-1.0.8.tar.gz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				make -f Makefile-libbz2_so
				make clean
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make PREFIX=/tools install >> ${logfile} 2>&1
				cp -v bzip2-shared /tools/bin/bzip2 >> ${logfile} 2>&1
				cp -av libbz2.so* /tools/lib >> ${logfile} 2>&1
				ln -sv libbz2.so.1.0 /tools/lib/libbz2.so >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Coreutils {
	local pkg=coreutils-8.32.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools --enable-install-program=hostname >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Diffutils {
	local pkg=diffutils-3.7.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function File {
	local pkg=file-5.40.tar.gz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Findutils {
	local pkg=findutils-4.8.0.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Gawk {
	local pkg=gawk-5.1.0.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Gettext {
	local pkg=gettext-0.21.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --disable-shared >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /tools/bin >> ${logfile} 2>&1
			msg_success
			cd - > /dev/null 2>&1
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Grep {
	local pkg=grep-3.6.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Gzip {
	local pkg=gzip-1.10.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Make {
	local pkg=make-4.3.tar.gz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools --without-guile >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Patch {
	local pkg=patch-2.7.6.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Perl {
	local pkg=perl-5.32.1.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				sh Configure -des -Dprefix=/tools -Dlibs=-lm >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				# ulimit -s unlimited
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				cp -v perl cpan/podlators/scripts/pod2man /tools/bin >> ${logfile} 2>&1
				mkdir -pv /tools/lib/perl5/5.32.1 >> ${logfile} 2>&1
				cp -Rv lib/* /tools/lib/perl5/5.32.1 >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Python {
	local pkg=Python-3.9.4.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				sed -i '/def add_multiarch_paths/a \        return' setup.py
				./configure --prefix=/tools --without-ensurepip >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Sed {
	local pkg=sed-4.8.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Tar {
	local pkg=tar-1.34.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Texinfo {
	local pkg=texinfo-6.7.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Util-linux {
	local pkg=util-linux-2.36.2.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools                \
				            --without-python               \
				            --disable-makeinstall-chown    \
				            --without-systemdsystemunitdir \
				            --without-ncurses              \
				            PKG_CONFIG="" >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Xz {
	local pkg=xz-5.2.5.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
#	RPM STUFF
function Zlib {
	local pkg=zlib-1.2.11.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	install -dm 755 ${TOPDIR}/BUILDROOT
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools  >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make  install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Popt {
	local pkg=popt-1.18.tar.gz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools  >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Openssl {
	local pkg=openssl-1.1.1k.tar.gz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./config \
					--prefix=/tools \
					--openssldir=/tools/etc/ssl \
					no-shared \
					no-zlib \
					enable-md2  >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Libarchive {
	local pkg=libarchive-3.5.1.tar.xz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools --without-xml2  >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Sqlite {
	local pkg=sqlite-autoconf-3350500.tar.gz
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure --prefix=/tools     \
				            --disable-static  \
				            --enable-fts5     \
				            CPPFLAGS="-DSQLITE_ENABLE_FTS3=1  \
				            -DSQLITE_ENABLE_FTS4=1            \
				            -DSQLITE_ENABLE_COLUMN_METADATA=1 \
				            -DSQLITE_ENABLE_UNLOCK_NOTIFY=1   \
				            -DSQLITE_ENABLE_DBSTAT_VTAB=1     \
				            -DSQLITE_SECURE_DELETE=1          \
				            -DSQLITE_ENABLE_FTS3_TOKENIZER=1"  >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Libelf {
	local pkg=elfutils-0.183.tar.bz2
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	install -dm 755 ${TOPDIR}/BUILDROOT
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
				./configure \
					--prefix=/tools \
					--disable-debuginfod \
					--enable-libdebuginfod=dummy \
					--libdir=/tools/lib  >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make -C libelf install >> ${logfile} 2>&1
				install -vm644 config/libelf.pc /tools/lib/pkgconfig
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Rpm {
	local pkg=rpm-4.16.1.3.tar.bz2
	local pkg_dir=${pkg%%.tar*}
	local logfile="${TOPDIR}/LOGS/tools-${FUNCNAME}.log"
	[ -e ${logfile}.complete ] && { msg "Skipping: ${FUNCNAME}";return 0; } || msg "Building: ${FUNCNAME}"
	> ${logfile}
	pushd ${TOPDIR}/BUILD >> /dev/null 2>&1
		unpack "${pkg}"
		pushd ${pkg_dir} >> /dev/null 2>&1
			msg_line "	Configure: "
			./configure \
				--prefix=/tools \
				--program-prefix= \
				--sysconfdir=/tools/etc \
				--with-crypto=openssl \
				--without-external-db \
				--without-archive \
				--without-lua \
				--disable-dependency-tracking \
				--disable-silent-rules \
				--disable-rpath \
				--disable-plugins \
				--disable-inhibit-plugin \
				--disable-shared \
				--enable-static \
				--enable-sqlite  \
				--enable-python \
				--enable-zstd=no \
				--enable-lmdb=no >> ${logfile} 2>&1
			msg_success
			msg_line "	     Make: "
				make ${MKFLAGS} >> ${logfile} 2>&1
			msg_success
			msg_line "	  Install: "
				make install >> ${logfile} 2>&1
			msg_success
		popd > /dev/null 2>&1
	popd > /dev/null 2>&1
	#	This is for rpm and rpmbuild
	[ -d ${LFS}/tmp ]		|| install -vdm 755 ${LFS}/tmp
	[ -d ${LFS}/bin ]		|| install -vdm 755 ${LFS}/bin
	[ -d ${LFS}/usr/bin ]		|| install -vdm 755 ${LFS}/usr/bin
	[ -h ${LFS}/bin/sh ]		|| ln -sf /tools/bin/bash ${LFS}/bin/sh
	[ -h ${LFS}/bin/bash ]		|| ln -sf /tools/bin/bash ${LFS}/bin
	[ -h ${LFS}//usr/bin/getconf ]	|| ln -sf /tools/bin/getconf ${LFS}/usr/bin
	[ -d ${LFS}/tools/etc/rpm ]	|| install -vdm 755 ${LFS}/tools/etc/rpm
	cp SOURCES/macros ${LFS}/tools/etc/rpm/macros
	clean-build-directory
	mv ${logfile} ${logfile}.complete
	return
}
function Remove_files {
	msg_line "Removing unnecessary files: "
	#	/tools/bin
	rm -f  /mnt/lfs/tools/bin/c_rehash
	rm -f  /mnt/lfs/tools/bin/gendiff
	rm -f  /mnt/lfs/tools/bin/openssl
	#	/tools/lib/pkgconfig
	rm -f  /mnt/lfs/tools/lib/pkgconfig/libcrypto.pc
	rm -f  /mnt/lfs/tools/lib/pkgconfig/libelf.pc
	rm -f  /mnt/lfs/tools/lib/pkgconfig/libssl.pc
	rm -f  /mnt/lfs/tools/lib/pkgconfig/openssl.pc
	rm -f  /mnt/lfs/tools/lib/pkgconfig/popt.pc
	rm -f  /mnt/lfs/tools/lib/pkgconfig/rpm.pc
	rm -f  /mnt/lfs/tools/lib/pkgconfig/zlib.pc
	#	/tools/etc/ssl
	rm -fr /mnt/lfs/tools/etc/ssl
	#	/tools/include
	rm -fr /mnt/lfs/tools/include/elfutils
	rm -f  /mnt/lfs/tools/include/gelf.h
	rm -f  /mnt/lfs/tools/include/libelf.h
	rm -f  /mnt/lfs/tools/include/nlist.h
	rm -fr /mnt/lfs/tools/include/openssl
	rm -f  /mnt/lfs/tools/include/popt.h
	rm -fr /mnt/lfs/tools/include/rpm
	rm -f  /mnt/lfs/tools/include/zconf.h
	rm -f  /mnt/lfs/tools/include/zlib.h
	#	/tools/lib
	rm -fr /mnt/lfs/tools/lib/engines-1.1
	rm -f  /mnt/lfs/tools/lib/libcrypto.a
	rm -f  /mnt/lfs/tools/lib/libssl.a
	rm -rf /mnt/lfs/tools/lib/libz.a
	rm -f  /mnt/lfs/tools/lib/libelf.a
	rm -f  /mnt/lfs/tools/lib/libpopt.a
	rm -f  /mnt/lfs/tools/lib/librpm.a
	rm -f  /mnt/lfs/tools/lib/librpmbuild.a
	rm -f  /mnt/lfs/tools/lib/librpmio.a
	rm -f  /mnt/lfs/tools/lib/librpmsign.a
	find /tools/{lib,libexec} -name \*.la -delete
	msg_success
	return
}
#-----------------------------------------------------------------------------
#	Mainline
LIST=""
LIST+="_sanity set-mkflags clean-build-directory "
LIST+="Binutils-Pass-1 "
LIST+="GCC-Pass-1 "
LIST+="Linux-API-Headers "
LIST+="Glibc "
LIST+="Libstdc "
LIST+="Binutils-Pass-2 "
LIST+="GCC-Pass-2 "
LIST+="Tcl "
LIST+="Expect "
LIST+="DejaGNU "
LIST+="M4 "
LIST+="Ncurses "
LIST+="Bash "
LIST+="Bison "
LIST+="Bzip "
LIST+="Coreutils "
LIST+="Diffutils "
LIST+="File "
LIST+="Findutils "
LIST+="Gawk "
LIST+="Gettext "
LIST+="Grep "
LIST+="Gzip "
LIST+="Make "
LIST+="Patch "
LIST+="Perl "
LIST+="Python "
LIST+="Sed "
LIST+="Tar "
LIST+="Texinfo "
LIST+="Util-linux "
LIST+="Xz "
#	rpm stuff
LIST+="Zlib "
LIST+="Popt "
LIST+="Openssl "
LIST+="Libelf "
LIST+="Libarchive "
LIST+="Sqlite "
LIST+="Rpm "
LIST+="Remove_files "
for i in ${LIST};do ${i};done
end_run
