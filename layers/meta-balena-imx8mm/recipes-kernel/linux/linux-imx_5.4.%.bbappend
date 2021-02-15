RDEPENDS_kernel-image_iot-gate-imx8=""

KBRANCH = "imx_5.4.24_2.1.0"

do_kernel_metadata() {
    set +ex
    cd ${S}
    export KMETA=${KMETA}
    # if kernel tools are available in-tree, they are preferred
    # and are placed on the path before any external tools. Unless
    # the external tools flag is set, in that case we do nothing.
    if [ -f "${S}/scripts/util/configme" ]; then
	if [ -z "${EXTERNAL_KERNEL_TOOLS}" ]; then
	    PATH=${S}/scripts/util:${PATH}
	fi
    fi

    machine_branch="${@ get_machine_branch(d, "${KBRANCH}" )}"
    machine_srcrev="${SRCREV_machine}"
    if [ -z "${machine_srcrev}" ]; then
	# fallback to SRCREV if a non machine_meta tree is being built
	machine_srcrev="${SRCREV}"
    fi
    # In a similar manner to the kernel itself:
    #
    #   defconfig: $(obj)/conf
    #   ifeq ($(KBUILD_DEFCONFIG),)
    #	$< --defconfig $(Kconfig)
    #   else
    #	@echo "*** Default configuration is based on '$(KBUILD_DEFCONFIG)'"
    #	$(Q)$< --defconfig=arch/$(SRCARCH)/configs/$(KBUILD_DEFCONFIG) $(Kconfig)
    #   endif
    #
    # If a defconfig is specified via the KBUILD_DEFCONFIG variable, we copy it
    # from the source tree, into a common location and normalized "defconfig" name,
    # where the rest of the process will include and incoroporate it into the build
    #
    # If the fetcher has already placed a defconfig in WORKDIR (from the SRC_URI),
    # we don't overwrite it, but instead warn the user that SRC_URI defconfigs take
    # precendence.
    #
    if [ -n "${KBUILD_DEFCONFIG}" ]; then
	if [ -f "${S}/arch/${ARCH}/configs/${KBUILD_DEFCONFIG}" ]; then
	    if [ -f "${WORKDIR}/defconfig" ]; then
		# If the two defconfig's are different, warn that we didn't overwrite the
		# one already placed in WORKDIR by the fetcher.
		cmp "${WORKDIR}/defconfig" "${S}/arch/${ARCH}/configs/${KBUILD_DEFCONFIG}"
		if [ $? -ne 0 ]; then
		    bbwarn "defconfig detected in WORKDIR. ${KBUILD_DEFCONFIG} skipped"
		else
		    cp -f ${S}/arch/${ARCH}/configs/${KBUILD_DEFCONFIG} ${WORKDIR}/defconfig
		fi
	    else
		cp -f ${S}/arch/${ARCH}/configs/${KBUILD_DEFCONFIG} ${WORKDIR}/defconfig
	    fi
	    sccs="${WORKDIR}/defconfig"
	else
	    bbfatal "A KBUILD_DEFCONFIG '${KBUILD_DEFCONFIG}' was specified, but not present in the source tree"
	fi
    fi

    # was anyone trying to patch the kernel meta data ?, we need to do
    # this here, since the scc commands migrate the .cfg fragments to the
    # kernel source tree, where they'll be used later.
    check_git_config
    patches="${@" ".join(find_patches(d,'kernel-meta'))}"
    for p in $patches; do
        (
	cd ${WORKDIR}/kernel-meta
	git am -s $p
        )
    done

    sccs_from_src_uri="${@" ".join(find_sccs(d))}"
    patches="${@" ".join(find_patches(d,''))}"
    feat_dirs="${@" ".join(find_kernel_feature_dirs(d))}"

    # a quick check to make sure we don't have duplicate defconfigs
    # If there's a defconfig in the SRC_URI, did we also have one from
    # the KBUILD_DEFCONFIG processing above ?
    if [ -n "$sccs" ]; then
        # we did have a defconfig from above. remove any that might be in the src_uri
        sccs_from_src_uri=$(echo $sccs_from_src_uri | awk '{ if ($0!="defconfig") { print $0 } }' RS=' ')
    fi
    sccs="$sccs $sccs_from_src_uri"

    # check for feature directories/repos/branches that were part of the
    # SRC_URI. If they were supplied, we convert them into include directives
    # for the update part of the process
    for f in ${feat_dirs}; do
	if [ -d "${WORKDIR}/$f/meta" ]; then
	    includes="$includes -I${WORKDIR}/$f/kernel-meta"
	elif [ -d "${WORKDIR}/../oe-local-files/$f" ]; then
	    includes="$includes -I${WORKDIR}/../oe-local-files/$f"
            elif [ -d "${WORKDIR}/$f" ]; then
	    includes="$includes -I${WORKDIR}/$f"
	fi
    done
    for s in ${sccs} ${patches}; do
	sdir=$(dirname $s)
	includes="$includes -I${sdir}"
                # if a SRC_URI passed patch or .scc has a subdir of "kernel-meta",
                # then we add it to the search path
                if [ -d "${sdir}/kernel-meta" ]; then
	    includes="$includes -I${sdir}/kernel-meta"
                fi
    done

    # expand kernel features into their full path equivalents
    bsp_definition=$(spp ${includes} --find -DKMACHINE=${KMACHINE} -DKTYPE=${LINUX_KERNEL_TYPE})
    if [ -z "$bsp_definition" ]; then
	echo "$sccs" | grep -q defconfig
	if [ $? -ne 0 ]; then
	    bbfatal_log "Could not locate BSP definition for ${KMACHINE}/${LINUX_KERNEL_TYPE} and no defconfig was provided"
	fi
    fi
    meta_dir=$(kgit --meta)

    # run1: pull all the configuration fragments, no matter where they come from
    elements="`echo -n ${bsp_definition} ${sccs} ${patches} ${KERNEL_FEATURES}`"
    if [ -n "${elements}" ]; then
	echo "${bsp_definition}" > ${S}/${meta_dir}/bsp_definition
	scc --force -o ${S}/${meta_dir}:cfg,merge,meta ${includes} ${bsp_definition} ${sccs} ${patches} ${KERNEL_FEATURES}
	#if [ $? -ne 0 ]; then
	#    bbfatal_log "Could not generate configuration queue for ${KMACHINE}."
	#fi
    fi

    # run2: only generate patches for elements that have been passed on the SRC_URI
    elements="`echo -n ${sccs} ${patches} ${KERNEL_FEATURES}`"
    if [ -n "${elements}" ]; then
	scc --force -o ${S}/${meta_dir}:patch --cmds patch ${includes} ${sccs} ${patches} ${KERNEL_FEATURES}
	#if [ $? -ne 0 ]; then
	#    bbfatal_log "Could not generate configuration queue for ${KMACHINE}."
	#fi
    fi
}

do_kernel_configme() {
    set +e

    # translate the kconfig_mode into something that merge_config.sh
    # understands
    case ${KCONFIG_MODE} in
	*allnoconfig)
	    config_flags="-n"
	    ;;
	*alldefconfig)
	    config_flags=""
	    ;;
        *)
	if [ -f ${WORKDIR}/defconfig ]; then
	    config_flags="-n"
	fi
        ;;
    esac

    cd ${S}

    meta_dir=$(kgit --meta)
    configs="$(scc --configs -o ${meta_dir})"
#    if [ $? -ne 0 ]; then
#	bberror "${configs}"
#	bbfatal_log "Could not find configuration queue (${meta_dir}/config.queue)"
#    fi

    CFLAGS="${CFLAGS} ${TOOLCHAIN_OPTIONS}"	HOSTCC="${BUILD_CC} ${BUILD_CFLAGS} ${BUILD_LDFLAGS}" HOSTCPP="${BUILD_CPP}" CC="${KERNEL_CC}" ARCH=${ARCH} merge_config.sh -O ${B} ${config_flags} ${configs} > ${meta_dir}/cfg/merge_config_build.log 2>&1
#    if [ $? -ne 0 ]; then
#	bbfatal_log "Could not configure ${KMACHINE}-${LINUX_KERNEL_TYPE}"
#    fi

    echo "# Global settings from linux recipe" >> ${B}/.config
    echo "CONFIG_LOCALVERSION="\"${LINUX_VERSION_EXTENSION}\" >> ${B}/.config
}
