#!/bin/sh
# Copyright 2014 The Rust Project Developers. See the COPYRIGHT
# file at the top-level directory of this distribution and at
# http://rust-lang.org/COPYRIGHT.
#
# Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
# http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
# <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
# option. This file may not be copied, modified, or distributed
# except according to those terms.

set -u

msg() {
    echo "gen-installer: ${1-}"
}

step_msg() {
    msg
    msg "$1"
    msg
}

warn() {
    echo "gen-installer: WARNING: $1" >&2
}

err() {
    echo "gen-installer: error: $1" >&2
    exit 1
}

need_ok() {
    if [ $? -ne 0 ]
    then
        err "$1"
    fi
}

need_cmd() {
    if command -v $1 >/dev/null 2>&1
    then msg "found $1"
    else err "need $1"
    fi
}

putvar() {
    local t
    local tlen
    eval t=\$$1
    eval tlen=\${#$1}
    if [ $tlen -gt 35 ]
    then
        printf "gen-installer: %-20s := %.35s ...\n" $1 "$t"
    else
        printf "gen-installer: %-20s := %s %s\n" $1 "$t"
    fi
}

valopt() {
    VAL_OPTIONS="$VAL_OPTIONS $1"

    local op=$1
    local default=$2
    shift
    shift
    local doc="$*"
    if [ $HELP -eq 0 ]
    then
        local uop=$(echo $op | tr '[:lower:]' '[:upper:]' | tr '\-' '\_')
        local v="CFG_${uop}"
        eval $v="$default"
        for arg in $CFG_ARGS
        do
            if echo "$arg" | grep -q -- "--$op="
            then
                local val=$(echo "$arg" | cut -f2 -d=)
                eval $v=$val
            fi
        done
        putvar $v
    else
        if [ -z "$default" ]
        then
            default="<none>"
        fi
        op="${default}=[${default}]"
        printf "    --%-30s %s\n" "$op" "$doc"
    fi
}

opt() {
    BOOL_OPTIONS="$BOOL_OPTIONS $1"

    local op=$1
    local default=$2
    shift
    shift
    local doc="$*"
    local flag=""

    if [ $default -eq 0 ]
    then
        flag="enable"
    else
        flag="disable"
        doc="don't $doc"
    fi

    if [ $HELP -eq 0 ]
    then
        for arg in $CFG_ARGS
        do
            if [ "$arg" = "--${flag}-${op}" ]
            then
                op=$(echo $op | tr 'a-z-' 'A-Z_')
                flag=$(echo $flag | tr 'a-z' 'A-Z')
                local v="CFG_${flag}_${op}"
                eval $v=1
                putvar $v
            fi
        done
    else
        if [ ! -z "$META" ]
        then
            op="$op=<$META>"
        fi
        printf "    --%-30s %s\n" "$flag-$op" "$doc"
     fi
}

flag() {
    BOOL_OPTIONS="$BOOL_OPTIONS $1"

    local op=$1
    shift
    local doc="$*"

    if [ $HELP -eq 0 ]
    then
        for arg in $CFG_ARGS
        do
            if [ "$arg" = "--${op}" ]
            then
                op=$(echo $op | tr 'a-z-' 'A-Z_')
                local v="CFG_${op}"
                eval $v=1
                putvar $v
            fi
        done
    else
        if [ ! -z "$META" ]
        then
            op="$op=<$META>"
        fi
        printf "    --%-30s %s\n" "$op" "$doc"
     fi
}

validate_opt () {
    for arg in $CFG_ARGS
    do
        local is_arg_valid=0
        for option in $BOOL_OPTIONS
        do
            if test --disable-$option = $arg
            then
                is_arg_valid=1
            fi
            if test --enable-$option = $arg
            then
                is_arg_valid=1
            fi
            if test --$option = $arg
            then
                is_arg_valid=1
            fi
        done
        for option in $VAL_OPTIONS
        do
            if echo "$arg" | grep -q -- "--$option="
            then
                is_arg_valid=1
            fi
        done
        if [ "$arg" = "--help" ]
        then
            echo
            echo "No more help available for Configure options,"
            echo "check the Wiki or join our IRC channel"
            break
        else
            if test $is_arg_valid -eq 0
            then
                err "Option '$arg' is not recognized"
            fi
        fi
    done
}

msg "looking for programs"
msg

need_cmd tar
need_cmd cp
need_cmd rm
need_cmd mkdir
need_cmd echo
need_cmd tr
need_cmd awk

CFG_ARGS="$@"

HELP=0
if [ "$1" = "--help" ]
then
    HELP=1
    shift
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo
else
    step_msg "processing arguments"
fi

OPTIONS=""
BOOL_OPTIONS=""
VAL_OPTIONS=""

valopt product-name "Product" "The name of the product, for display"
valopt component-name "component" "The name of the component, distinct from other installed components"
valopt package-name "package" "The name of the package, tarball"
valopt verify-bin "" "The command to run with --version to verify the install works"
valopt rel-manifest-dir "${CFG_PACKAGE_NAME}lib" "The directory under lib/ where the manifest lives"
valopt success-message "Installed." "The string to print after successful installation"
valopt legacy-manifest-dirs "" "Places to look for legacy manifests to uninstall"
valopt non-installed-prefixes "" "Path prefixes that should be included but not installed"
valopt bulk-dirs "" "Path prefixes of directories that should be installed/uninstalled in bulk"
valopt image-dir "./install-image" "The directory containing the installation medium"
valopt work-dir "./workdir" "The directory to do temporary work"
valopt output-dir "./dist" "The location to put the final image and tarball"

if [ $HELP -eq 1 ]
then
    echo
    exit 0
fi

step_msg "validating arguments"
validate_opt

src_dir="$(cd $(dirname "$0") && pwd)"

rust_installer_version=`cat "$src_dir/rust-installer-version"`

if [ ! -d "$CFG_IMAGE_DIR" ]
then
    err "image dir $CFG_IMAGE_DIR does not exist"
fi

mkdir -p "$CFG_WORK_DIR"
need_ok "couldn't create work dir"

rm -Rf "$CFG_WORK_DIR/$CFG_PACKAGE_NAME"
need_ok "couldn't delete work package dir"

mkdir -p "$CFG_WORK_DIR/$CFG_PACKAGE_NAME"
need_ok "couldn't create work package dir"

cp -r "$CFG_IMAGE_DIR/"* "$CFG_WORK_DIR/$CFG_PACKAGE_NAME"
need_ok "couldn't copy source image"

# Create the manifest
manifest=`(cd "$CFG_WORK_DIR/$CFG_PACKAGE_NAME" && find . -type f | sed 's/^\.\///') | sort`

# Remove non-installed files from manifest
non_installed_prefixes=`echo "$CFG_NON_INSTALLED_PREFIXES" | tr "," " "`
for prefix in $non_installed_prefixes; do
    # This adds the escapes to '/' in paths to make them '\/' so sed doesn't puke.
    # I figured this out by adding backslashes until it worked. holy shit.
    prefix=`echo "$prefix" | sed s/\\\//\\\\\\\\\\\//g`
    manifest=`echo "$manifest" | sed /^$prefix/d`
done

# Remove files in bulk dirs
bulk_dirs=`echo "$CFG_BULK_DIRS" | tr "," " "`
for bulk_dir in $bulk_dirs; do
    bulk_dir=`echo "$bulk_dir" | sed s/\\\//\\\\\\\\\\\//g`
    manifest=`echo "$manifest" | sed /^$bulk_dir/d`
done

# Add 'file:' installation directives.
# The -n prevents adding a blank file: if the manifest is empty
manifest=`/bin/echo -n "$manifest" | sed s/^/file:/`

# Add 'dir:' directives
for bulk_dir in $bulk_dirs; do
    manifest=`echo "$manifest" && echo "dir:$bulk_dir"`
done

# The above step may have left a leading empty line if there were only
# bulk dirs. Remove it.
manifest=`echo "$manifest" | sed /^$/d`

manifest_file="$CFG_WORK_DIR/$CFG_PACKAGE_NAME/manifest-$CFG_COMPONENT_NAME.in"
component_file="$CFG_WORK_DIR/$CFG_PACKAGE_NAME/components"
version_file="$CFG_WORK_DIR/$CFG_PACKAGE_NAME/rust-installer-version"

# Write the manifest
echo "$manifest" > "$manifest_file"

# Write the component name
echo "$CFG_COMPONENT_NAME" > "$component_file"

# Write the installer version (only used by combine-installers.sh)
echo "$rust_installer_version" > "$version_file"

# Generate the install script
"$src_dir/gen-install-script.sh" \
    --product-name="$CFG_PRODUCT_NAME" \
    --verify-bin="$CFG_VERIFY_BIN" \
    --rel-manifest-dir="$CFG_REL_MANIFEST_DIR" \
    --success-message="$CFG_SUCCESS_MESSAGE" \
    --legacy-manifest-dirs="$CFG_LEGACY_MANIFEST_DIRS" \
    --output-script="$CFG_WORK_DIR/$CFG_PACKAGE_NAME/install.sh"

need_ok "failed to generate install script"    

mkdir -p "$CFG_OUTPUT_DIR"
need_ok "couldn't create output dir"

rm -Rf "$CFG_OUTPUT_DIR/$CFG_PACKAGE_NAME.tar.gz"
need_ok "couldn't delete old tarball"

# Make a tarball
tar -czf "$CFG_OUTPUT_DIR/$CFG_PACKAGE_NAME.tar.gz" -C "$CFG_WORK_DIR" "$CFG_PACKAGE_NAME"
need_ok "failed to tar"
