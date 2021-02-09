
#PACKAGE_EXCLUDE = "kernel-image"
#PACKAGE_EXCLUDE = "kernel-image-image"

#RPROVIDES_remove = " kernel-image"
#RPROVIDES_remove = " kernel-image-image"


#PACKAGECONFIG_remove = "kernel-image"

ALLOW_EMPTY_${PN} = "1"
ALLOW_EMPTY_kernel-image = "1"
ALLOW_EMPTY_kernel-image-image = "1"


FILES_kernel-image = ""
FILES_kernel-image-image = ""

PACKAGES_DYNAMIC_remove = "^kernel-image-.*"


do_install_append() {
    #rm ${D}/boot/Image
}