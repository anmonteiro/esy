#!/bin/bash
# The MIT License (MIT)
#
# Copyright (c) 2014 Michael Kropat
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

realpath() {
    canonicalize_path "$(resolve_symlinks "$1")"
}
export -f realpath

resolve_symlinks() {
    _resolve_symlinks "$1"
}
export -f resolve_symlinks

_resolve_symlinks() {
    _assert_no_path_cycles "$@" || return

    local dir_context path
    path=$(readlink -- "$1")
    if [ $? -eq 0 ]; then
        dir_context=$(dirname -- "$1")
        _resolve_symlinks "$(_prepend_dir_context_if_necessary "$dir_context" "$path")" "$@"
    else
        printf '%s\n' "$1"
    fi
}
export -f _resolve_symlinks

_prepend_dir_context_if_necessary() {
    if [ "$1" = . ]; then
        printf '%s\n' "$2"
    else
        _prepend_path_if_relative "$1" "$2"
    fi
}
export -f _prepend_dir_context_if_necessary

_prepend_path_if_relative() {
    case "$2" in
        /* ) printf '%s\n' "$2" ;;
         * ) printf '%s\n' "$1/$2" ;;
    esac
}
export -f _prepend_path_if_relative

_assert_no_path_cycles() {
    local target path

    target=$1
    shift

    for path in "$@"; do
        if [ "$path" = "$target" ]; then
            return 1
        fi
    done
}
export -f _assert_no_path_cycles

canonicalize_path() {
    if [ -d "$1" ]; then
        _canonicalize_dir_path "$1"
    else
        _canonicalize_file_path "$1"
    fi
}
export -f canonicalize_path

_canonicalize_dir_path() {
    (cd "$1" 2>/dev/null && pwd -P)
}
export -f _canonicalize_dir_path

_canonicalize_file_path() {
    local dir file
    dir=$(dirname -- "$1")
    file=$(basename -- "$1")
    (cd "$dir" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$file")
}
export -f _canonicalize_file_path

# Optionally, you may also want to include:

### readlink emulation ###

readlink() {
    if _has_command readlink; then
        _system_readlink "$@"
    else
        _emulated_readlink "$@"
    fi
}
export -f readlink

_has_command() {
    hash -- "$1" 2>/dev/null
}
export -f _has_command

_system_readlink() {
    command readlink "$@"
}
export -f _system_readlink

_emulated_readlink() {
    if [ "$1" = -- ]; then
        shift
    fi

    _gnu_stat_readlink "$@" || _bsd_stat_readlink "$@"
}
export -f _emulated_readlink

_gnu_stat_readlink() {
    local output
    output=$(stat -c %N -- "$1" 2>/dev/null) &&

    printf '%s\n' "$output" |
        sed "s/^�[^�]*� -> �\(.*\)�/\1/
             s/^'[^']*' -> '\(.*\)'/\1/"
    # FIXME: handle newlines
}
export -f _gnu_stat_readlink

_bsd_stat_readlink() {
    stat -f %Y -- "$1" 2>/dev/null
}
export -f _bsd_stat_readlink
