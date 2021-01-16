#!/usr/bin/env bash
# Build portable fio distribution
# Copyright 2021 林博仁(Buo-ren, Lin) <Buo.Ren.Lin@gmail.com>
# SPDX-License-Identifier: GPL-2.0-only

set \
    -o errexit \
    -o errtrace \
    -o pipefail

DEBUG="${DEBUG:-false}"

main(){
    if test "${DEBUG}" == true; then
        set -o xtrace
    fi

    local \
        script_dir \
        script_file="${BASH_SOURCE[0]}" \
        script_filename="${BASH_SOURCE[0]##*/}" \
        script_name
    script_dir="${script_file%/*}"
    script_name="${script_filename%%.*}"

    print_progress \
        'Creating temporary folder for building...'
    if test "${DEBUG}" == true; then
        temp_dir="${TMPDIR:-/tmp}/${script_name}"
        mkdir \
            --parents \
            --verbose \
            "${temp_dir}"
    else
        temp_dir="$(
            mktemp \
                --tmpdir \
                --directory \
                "${script_name}".XXXXXX
        )"
    fi

    local \
        build_dir="${temp_dir}"/build \
        cache_dir="${temp_dir}"/cache \
        dist_dir="${temp_dir}"/dist \
        source_dir="${temp_dir}"/source
    rm \
        --recursive \
        --force \
        --verbose \
        "${build_dir}" \
        "${dist_dir}" \
        "${source_dir}"
    mkdir \
        --parents \
        --verbose \
        "${build_dir}" \
        "${cache_dir}" \
        "${dist_dir}" \
        "${source_dir}"

    print_progress \
        'Installing build dependencies...'
    yum install \
        -y \
        centos-release-scl
    yum install \
        -y \
        curl \
        devtoolset-7 \
        git \
        libaio-devel \
        zlib-devel \
        xz

    print_progress \
        'Determining latest fio release...'
    local \
        fio_latest_version \
        fio_latest_release_tag \
        fio_downloaded_tarball
    fio_latest_release_tag="$(
        git ls-remote \
            --tags \
            git://git.kernel.dk/fio.git \
            | awk \
                '{print $2}' \
            | awk \
                --field-separator '/' \
                '{print $3}' \
            | grep \
                --invert-match '{}' \
            | grep \
                --extended-regexp \
                --invert-match \
                '(rc|a)$' \
            | grep '^fio-' \
            | sort \
                --version-sort \
                --reverse \
            | head \
                --lines=1
    )"
    fio_latest_version="${fio_latest_release_tag#fio-}"
    echo fio latest version determined to be "${fio_latest_version}"

    print_progress \
        'Downloading fio source archive...'
    pushd "${cache_dir}" >/dev/null
        if ! test -e fio-"${fio_latest_release_tag}"-*.tar.gz; then
            curl \
                --location \
                --remote-name \
                --remote-header-name \
                "https://git.kernel.dk/?p=fio.git;a=snapshot;h=${fio_latest_release_tag};sf=tgz"
        fi
    popd >/dev/null
    fio_downloaded_tarball="$(echo -n "${cache_dir}"/fio-"${fio_latest_release_tag}"-*.tar.gz)"

    print_progress \
        'Extracting fio source archive...'
    tar \
        --directory "${source_dir}" \
        --extract \
        --file "${fio_downloaded_tarball}" \
        --strip-components=1 \
        --verbose

    print_progress \
        'Creating distribution folder...'
    git_describe="$(
        git describe \
            --always \
            --dirty \
            --tags
    )"
    dist_name=fio-"${fio_latest_version}"-dist-g"${git_describe#v}"-amd64

    mkdir \
        --verbose \
        "${dist_dir}"/"${dist_name}"

    print_progress \
        'Building fio...'
    # FALSE POSITIVE: External resource
    # shellcheck disable=SC1091
    source /opt/rh/devtoolset-7/enable
    pushd "${build_dir}" > /dev/null
        "${source_dir}"/configure \
            --disable-native \
            --prefix=/opt/"${dist_name}"
        make \
            --jobs="$(nproc)"
        make \
            INSTALL_PREFIX="${dist_dir}"/"${dist_name}" \
            install
        strip \
            "${dist_dir}"/"${dist_name}"/bin/* \
            2>&1 \
            | grep \
                --invert-match \
                'File format not recognized' \
            || test "${?}" == 1
    popd >/dev/null

    print_progress \
        'Installing release archive assets...'
    sed \
        "s/__DIST_NAME__/${dist_name}/" \
        "${script_dir}"/dist-resources/install.sh.in \
        > "${dist_dir}"/"${dist_name}"/install.sh
    chmod +x "${dist_dir}"/"${dist_name}"/install.sh

    print_progress \
        'Creating release archive...'
    tar \
        --directory "${dist_dir}" \
        --create \
        --file "${dist_name}".tar.xz \
        --verbose \
        --xz \
        "${dist_name}"

    print_progress \
        'Release archive created at the current working directory.' \
        'Build process completed without error.'
    exit 0
}

print_progress(){
    local -i arg_no
    echo # Separate with previous message output
    echo ============================================================
    for (( arg_no=1; arg_no <= "${#}"; arg_no+=1 )); do
    echo "${!arg_no}"
    done
    echo ============================================================
}

trap_err(){
    printf \
        '\nScript prematurely aborted at line %s of the %s function with the exit status %u.\n' \
        "${BASH_LINENO[0]}" \
        "${FUNCNAME[1]}" \
        "${?}" \
        1>&2
}
trap trap_err ERR

declare temp_dir

trap_exit(){
    if test -v temp_dir \
        && test "${DEBUG}" != true; then
        rm -rf "${temp_dir}"
    fi
}
trap trap_exit EXIT

main "${0}" "${@}"
