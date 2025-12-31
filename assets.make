#!/bin/bash

# TODO:
#   - 2.12.2021:  update of multi-package PKGBUILD? Install should work, but deletion of old packages (thus updating) doesn't!
#   - better epoch handling?

source /etc/eos-color.conf

Color2() { eos-color "$1" 2; }       # Color to stderr
Color1() { eos-color "$1"; }         # Color to stdout
# echo2info() { Color2 info; echo2 "==>" "$@"; Color2 reset; }

echoreturn() { echo "$@" ; }     # for "return" values!

echo2()      { echo   "$@" >&2 ; }    # output to stderr
printf2()    { printf "$@" >&2 ; }    # output to stderr

DIE() {
    Color2 error
    echo2 "Error: $@"
    echo2 "Call stack lines: ${BASH_LINENO[*]}"
    if [ "${FUNCNAME[1]}" = "Main" ] ; then
        Color2 tip
        Usage
    fi
    Color2
    Destructor
    exit 1
}
WARN()       { Color2 warning; echo2 -n "Warning: " ; echo2 "$@" ; Color2; }

FileSizePrint() {
    # Print size of file in bytes, numbers are is groups of three.
    # Examples:
    #       43854 ==> 43 854
    #    52341928 ==> 52 341 928
    # Note: user must align right if needed.

    local file="$1"
    local nr nr2="" nrtail
    local left remove=3

    nr=$(stat -c %s "$file")
    left=${#nr}
    while [ $left -gt 0 ] ; do
        if [ $remove -gt $left ] ; then
            remove=$left
        fi
        ((left -= remove))
        nrtail="${nr: -remove}"
        nr="${nr:: -remove}"
        nr2="$nrtail $nr2"
    done
    [ "${nr2::1}" = " " ]  && nr2="${nr2:1}"         # skip leading space
    [ "${nr2: -1}" = " " ] && nr2="${nr2:: -1}"      # skip trailing space

    echo "$nr2"
}

read2() {
    # Special handling for option -t (and -p).
    # The read value goes to the REPLY variable only.

    local name=""
    local prompt=""
    local count=0
    local cr=$'\r'
    local args=()
    local arg
    local has_t_opt="no"
    local prev=""
    local retval=0

    OPTIND=1   # for some reason this is required!

    # get the prompt and timeout (=count) values, if they exist
    while getopts ersa:d:i:n:N:p:t:u: name ; do
        case $name in
            t) count="$OPTARG" ; has_t_opt="yes" ;;
            p) prompt="$OPTARG" ;;
        esac
    done

    # add parameters from "$@" to the "args" array, except -t and -p and their values 
    for arg in "$@" ; do
        case "$arg" in
            -t)  prev=t ;;
            -t*) ;;
            -p)  prev=p ;;
            -p*) ;;
            *)
                case "$prev" in
                    t|p) prev="" ;;
                    *)   args+=("$arg") ;;
                esac
                ;;
        esac
    done

    # read value
    if [ "$has_t_opt" = "yes" ] ; then
        # while reading, show a seconds counter
        while [ $count -gt 0 ] ; do
            printf2 "%s[%s] " "$cr" "$count"
            read -t 1 -p "$prompt" "${args[@]}" >&2
            retval=$?
            test $retval -eq 0 && break
            test -n "$REPLY" && break
            ((count--))
        done
    else
        # just read the value, no special handling
        read -p "$prompt" "${args[@]}" >&2
        retval=$?
    fi
    test -z "$REPLY" && echo2 ""
    return $retval
}

Pushd() { pushd "$@" >/dev/null || DIE "${FUNCNAME[1]}: pushd $* failed" ; }

Popd()  {
    local count=1 xx
    case "$1" in
        -c=*) count=${1:3} ; shift ;;
        -c*)  count=${1:2} ; shift ;;
    esac
    for ((xx=0;xx<count;xx++)) ; do
        popd  "$@" >/dev/null || DIE "${FUNCNAME[1]}: popd $* failed"
    done
}

GetPkgbuildValue() {       # this is used in assets.conf too!
    #
    # Extract one or more values from variables of file PKGBUILD into respective user variables.
    #
    # Usage: GetPkgbuildValue PKGBUILD toVariable pkgbuildVariable [torVariable pkgbuildVariable [toVariable pkgbuildVariable] ...]
    #
    # Example:
    #    local Pkgver Pkgrel   # user variables
    #    GetPkgbuildValue $mydir/PKGBUILD Pkgver "pkgver" Pkgrel "pkgrel"
    #        will return values of 'pkgver' and 'pkgrel' from $mydir/PKGBUILD into Pkgver and Pkgrel, respectively
    #

    local PKGBUILD="$1"
    shift

    while declare -F pkgver &> /dev/null ; do
        unset -f pkgver                        # remove possible function from another PKGBUILD
    done

    source "$PKGBUILD" || return 1   # reading PKGBUILD may fail

    while [ "$1" ] ; do
        [ "$2" ] || DIE "$FUNCNAME: internal error: number of call parameters is not even!"
        local -n retvar_for_all="$1"
        GetPkgbuildValue1 "$2" retvar_for_all
        unset -n retvar_for_all
        shift 2
    done
}

CursorLeft() { local num="$1"; echo2 -en "\033[${num}D"; }  # move cursor left $num chars

GetPkgbuildValue1() {
    local varname="$1"
    local -n retvar="$2"
    local retval2=""

    case "$varname" in
        arch)          retvar=("${arch[@]}") ;;
        backup)        retvar=("${backup[@]}") ;;
        conflicts)     retvar=("${conflicts[@]}") ;;
        depends)       retvar=("${depends[@]}") ;;
        makedepends)   retvar=("${makedepends[@]}") ;;
        optdepends)    retvar=("${optdepends[@]}") ;;
        pkgname)       retvar=("${pkgname[@]}") ;;
        provides)      retvar=("${provides[@]}") ;;
        replaces)      retvar=("${replaces[@]}") ;;
        source)        retvar=("${source[@]}") ;;
        validpgpkeys)  retvar=("${validpgpkeys[@]}") ;;

        epoch)         retvar="$epoch" ;;
        install)       retvar="$install" ;;
        pkgdesc)       retvar="$pkgdesc" ;;
        pkgrel)        retvar="$pkgrel" ;;
        url)           retvar="$url" ;;

        _ver)          retvar="$_ver" ;;

        pkgver)
            if declare -F pkgver &> /dev/null ; then
                # printf2 " running function pkgver() ... "
                if [ $listing_updates = yes ] ; then
                    CursorLeft 2
                    HookIndicator "$hook_pkgver_func" yes
                    # echo2 -n "p "
                fi

                # We want to run pkgver() to get the correct pkgver.
                # But first we must run makepkg because the needed git stuff hasn't been fetched yet...

                Pushd ${PKGBUILD%/*}

                makepkg --skipinteg -od &> /dev/null || DIE "$FUNCNAME: cannot determine 'pkgver' from $PKGBUILD."

                # sed -E -i "$PKGBUILD" -e "s|^pkgrel=[0-9\.]+|pkgrel=$pkgrel|"       # Prevents makepkg from changing pkgrel to 1.

                if false ; then
                    unset -f pkgver
                    source "$PKGBUILD"
                    retvar="$(pkgver)"
                else
                    retvar=$(grep ^pkgver= "$PKGBUILD")   # pkgver=something
                    retvar=${retvar#*=}                   # remove pkgver=
                    retvar=${retvar%% *}                  # remove all after space
                    retvar=${retvar//[\'\"]/}             # remove all quote marks
                fi
                unset -f pkgver

                Popd
                retval2="$(echo "$retvar" | tail -n1)"   # $retvar may have 2 items in 2 lines !?
                [ -n "$retval2" ] && retvar="$retval2"
            else
                retvar="$pkgver"
            fi
            ;;
        *)
            WARN "$FUNCNAME: unsupported variable name '$varname'"
            return 1
            ;;
    esac
}

IsListedPackage() {
    # Is a package one of the listed packages in PKGNAMES?
    local Pkgname="$1"
    printf "%s\n" "${PKGNAMES[@]}" | grep -P "^$Pkgname/aur$|^$Pkgname$" >/dev/null
}

IsAurPackage() {
    # Determine AUR from PKGNAMES array directly since we don't have PKGBUILD yet.
    local Pkgname="$1"
    printf "%s\n" "${PKGNAMES[@]}" | grep "^$Pkgname/aur$" >/dev/null
}

HandlePossibleEpoch() {
    # Github release assets cannot have colon (:) in the file name.
    # So if a package has an epoch value in PKGBUILD, return a new fixed name for a package
    # fetched from github release assets.

    local Pkgname="$1"  # e.g. welcome
    local pkg="$2"      # e.g. welcome-2.3.9.6-1-any.pkg.tar.zst  # assumes: epoch=2
    local -n Newname="$3"
    local cwd=""
    local Epoch=""

    if [ ! -r PKGBUILD ] ; then
        cwd="$PWD"

        if [ ! -r "$PKGBUILD_ROOTDIR/$Pkgname/PKGBUILD" ] ; then
            if IsAurPackage "$Pkgname" ; then
                cd "$PKGBUILD_ROOTDIR"
                $helper -Ga "$Pkgname" >/dev/null || DIE "fetching PKGBUILD of '$Pkgname' failed."
            else
                DIE "sorry, getting PKGBUILD of '$Pkgname' not supported yet."
            fi
        fi
        cd "$PKGBUILD_ROOTDIR/$Pkgname"
    fi

    GetPkgbuildValue "PKGBUILD" Epoch "epoch"

    if [ -z "$Epoch" ] ; then
        Newname="$pkg"
    else
        Newname=$(echo "$pkg" | sed "s|\(${Pkgname}-[0-9][0-9]*\)\.\(.*\)|\1:\2|")
    fi

    if [ -n "$cwd" ] ; then
        cd "$cwd"
        [ -n "$tmpdir" ] && rm -rf $tmpdir
    fi
}

IncludesOption() {
    local where="$1"     # list of options, e.g. "-r --rmdeps"
    local opt="$2"       # e.g. "-r"

    printf "%s\n" $where | grep -w "\\$opt" >/dev/null
}

Build()
{
    local pkgdirname="$1"
    local assetsdir="$2"
    local pkgbuilddir="$3"
    local Pkgname
    local pkg pkgs
    local workdir=$(mktemp -d)
    local log=$workdir/buildlog-"$pkgdirname".log
    local missdeps="Missing dependencies"
    local opts=""
    local msg=""

    if [ "${#PKG_MAKEPKG_OPTIONS[@]}" -gt 0 ] ; then
        if [ -n "${PKG_MAKEPKG_OPTIONS[$pkgdirname]}" ] ; then   # from assets.conf
            opts="${PKG_MAKEPKG_OPTIONS[$pkgdirname]}"
        fi
    fi

    Pushd "$workdir"
      cp -r "$pkgbuilddir" .
      Pkgname="$(PkgBuildName "$pkgdirname")"
      Pushd "$workdir/$pkgdirname"

      # now build, assume we have PKGBUILD
      # special handling for missing dependencies
      local exitcode=0
      LANG=C makepkg --clean $opts 2>/dev/null >"$log" || {
          exitcode=$?
          if [ -z "$(grep "$missdeps:" "$log")" ] ; then
              Popd -c2
              DIE "makepkg for '$Pkgname' failed (makepkg code=$exitcode, missing deps, see $log and files at $workdir/$pkgdirname)"
          fi
          msg="Installing $(echo "$missdeps" | tr [:upper:] [:lower:])"
          if IncludesOption "$opts" "--rmdeps" || IncludesOption "$opts" "-r" ; then
              msg+=" and removing them right after build"
          fi
          echo2 "$msg:"
          # grep -A100 "$missdeps:" "$log" | grep "^  -> " >&2

          # use special pacman wrapper in the makepkg call below
          local wrapper=/usr/bin/pacman-for-assets.make
          [ -x "$wrapper" ] || DIE "sorry, $wrapper does not exist!"

          PACMAN=$wrapper makepkg --syncdeps --clean $opts >"$log" || { Popd -c2 ; DIE "makepkg for '$Pkgname' failed (see $log)" ; }
      }
      pkgs=(*.pkg.tar.$_COMPRESSOR)
      case "$pkgs" in
          "" | "*.pkg.tar.$_COMPRESSOR") DIE "$pkgdirname: build failed" ;;
      esac
      for pkg in "${pkgs[@]}" ; do
          # HandlePossibleEpoch "$Pkgname" "$pkg" pkg     # not needed here since makepkg should handle epoch OK (?)
          mv $pkg "$assetsdir"
          built+=("$assetsdir/$pkg")
          built_under_this_pkgname+=("$pkg")
      done
      Popd
    Popd
    rm -rf "$workdir"
}

PkgBuildName()
{
    local pkgdirname="$1"
    source "$PKGBUILD_ROOTDIR"/"$(JustPkgname "$pkgdirname")"/PKGBUILD
    echoreturn "$pkgname"
}

PkgBuildVersion()
{
    local _pkgdirname="$1"
    local _srcfile="$PKGBUILD_ROOTDIR"/"$(JustPkgname "$_pkgdirname")"/PKGBUILD

    if [ ! -r "$_srcfile" ] ; then
        DIE "'$_srcfile' does not exist."
    fi

    local Epoch="" Pkgver="" Pkgrel=""

    # GetPkgbuildValue "$_srcfile" Epoch "epoch" Pkgver "pkgver" Pkgrel "pkgrel"
    GetPkgbuildValue "$_srcfile" Epoch "epoch"
    GetPkgbuildValue "$_srcfile" Pkgver "pkgver"
    GetPkgbuildValue "$_srcfile" Pkgrel "pkgrel"

    if [ -n "$Epoch" ] ; then
        echoreturn "$Epoch:${Pkgver}-$Pkgrel"
    else
        echoreturn "${Pkgver}-$Pkgrel"
    fi
}

LocalVersion()
{
    local Pkgname="$1"
    local pkgs
    local xx
    
    Pkgname="$(JustPkgname "$Pkgname")"

    for xx in zst xz ; do         # order is important because of change to zstd!
        pkgs=$(ListPkgsWithName "$ASSETSDIR/$Pkgname" "$xx")
        test -n "$pkgs" && break
    done

    [ "$pkgs" ] || { echoreturn "0"; return; }
    case "$(echo "$pkgs" | wc -l)" in
        0) echoreturn "0" ; return ;;
        1) ;;
        *) echo2 -n "$hook_multiversion "
           # WARN -n "$Pkgname: many local versions, using the latest. "
           pkgs="$(echo "$pkgs" | tail -n 1)"
           ;;
    esac

    pkg-name-components --real EVR "$pkgs"
}

AurMarkingFail() {
    local fakepath="$1"     # no more: "aur/pkgname"
    DIE "marking AUR packages as $fakepath is no more supported!"
}

JustPkgname()
{
    local fakepath="$1"
    case "$fakepath" in
        ./*)      fakepath="${fakepath:2}" ;;
        */aur)    fakepath="${fakepath:: -4}" ;;
        aur/*)    AurMarkingFail "$fakepath" ;;
        # *)      fakepath="${fakepath}"   ;;
    esac
    echoreturn ${fakepath##*/}
}

HookIndicator() {
    local mark="$1"
    local force="$2"
    if [ "$fetch" = "yes" ] || [ "$force" = "yes" ] ; then
        echo2 -n "$mark "
    fi
}

ExplainHookMarks() {
    Color2 tip
    printf2 "\nPossible markings above mean indications from %s:\n" "$ASSETS_CONF"
    printf2 "    %s = a package hook changed pkgver in PKGBUILD.\n" "$hook_pkgver"
    printf2 "    %s = execute pkgver() from PKGBUILD.\n" "$hook_pkgver_func"                             # not a hook!
    printf2 "    %s = a package hook found many local versions, used latest.\n" "$hook_multiversion"
    printf2 "    %s = a package hook was executed.\n" "$hook_yes"
    printf2 "    %s = compare new and existing PKGBUILD files from AUR.\n" "$hook_compare"
    printf2 "\n"
    Color2
}

ShowPkgListWithTitle() {   # Show lines like: $title name [name...]
    local title="$1"
    shift
    local name
    local line=""
    local columns="$COLUMNS"
    [ "$columns" ] || columns=80

    for name in "$@" ; do
        [ "$line" ] || line="$title"
        line+=" $name"
        if [ ${#line} -gt $((columns-10)) ]  ; then
            printf2 "%s\n" "$line"
            line=""
        fi
    done
    [ "$line" ] && printf2 "%s\n" "$line"
}

AurSource() {
    # Use AUR if possible, otherwise use the backup repo at github.
    local -n _refvar="$1"
    [ "$_refvar" != aur ] && return
    local url=https://aur.archlinux.org/packages

    /bin/curl --fail -Lsm 5 $url >/dev/null && _refvar=aur || _refvar=repo
}
FetchAurPkgs() {
    DebugBreak
    local pkgs
    readarray -t pkgs < <(printf "%s\n" "${PKGNAMES[@]}" | /bin/grep /aur | /bin/sed 's|/aur||')
    if [ "${pkgs[0]}" ] ; then
        rm -rf "${pkgs[@]}"
        AurSource aur_src
        case "$aur_src" in
            aur)
                Color2 info; echo2 "  -> $helper -Ga ${pkgs[*]}"; Color2
                $helper -Ga "${pkgs[@]}" &>/dev/null && return
                ;;
            repo)
                Color2 info; echo2 "  -> aur-pkgs-fetch ${pkgs[*]}"; Color2
                Color2 warning; echo2 "  -> please wait..."; Color2
                aur-pkgs-fetch "${pkgs[@]}" && return
                ;;
            local)
                Color2 info; echo2 "  -> copy from '${AURSRCDIR/$HOME/\~}/$REPONAME'"; Color2
                for pkg in "${pkgs[@]}" ; do
                    if [ -d "$AURSRCDIR/$REPONAME/$pkg" ] ; then
                        cp -r "$AURSRCDIR/$REPONAME/$pkg" ./
                    else
                        WARN "folder '$AURSRCDIR/$REPONAME/$pkg' is not found!"
                    fi
                done
                return
                ;;
        esac
        DIE "fetching ${pkgs[*]} failed."
    fi
}

ListNameToPkgName()
{
    # "returns" pkgdirname and hookout
    #
    # PKGNAMES array (from $ASSETS_CONF) uses certain syntax for package names
    # to mark where they come from, either local or AUR packages.
    # AUR packages are fetched from AUR, local packages
    # are simply used from a local folder.
    #
    # Supported syntax:
    #    pkgname          local package
    #    ./pkgname        local package (emphasis)
    #    aur/pkgname      AUR package                           "aur/pkgname" NO MORE SUPPORTED!
    #    pkgname/aur      AUR package  (another way)

    local xx="$1"
    local run_hook="$2"
    local Pkgname
    local hook
    local hookretval=0

    hookout=""

    Pkgname=$(JustPkgname "$xx")

    [ "${xx::4}" = "aur/" ] && AurMarkingFail "$xx"

    # if [ "${xx: -4}" = "/aur" ] ; then
    #     case "$run_hook" in
    #         yes)
    #             rm -rf "$Pkgname"
    #             $helper -Ga "$Pkgname" >/dev/null || DIE "'$helper -Ga $Pkgname' failed."
    #             # Compare "$Pkgname" "$Pkgname/PKGBUILD" || return 1
    #             ;;
    #     esac
    # fi

    # A pkg may need some changes:
    hook="${ASSET_PACKAGE_HOOKS[$Pkgname]}"
    if [ -n "$hook" ] ; then
        if [ "$run_hook" = "yes" ] ; then
            hookout=$($hook) || hookretval=$?
            case $hookretval in
                0) HookIndicator "$hook_yes" ;;          # OK
                11) HookIndicator "$hook_pkgver" ;;      # pkgver was updated by hook
                1) HookIndicator "?" ;;                  # failed
                *) HookIndicator "??" ;;                 # unknown error
            esac
        fi
    else
        HookIndicator "$hook_no"
    fi

    pkgdirname="$Pkgname"
    return $hookretval
}

Compare() {
    # Compare new PKGBUILD from AUR to the saved PKGBUILD.

    local PKGNAME="$1"
    local pkgbuild_new="$2"
    local pkgbuild_old="$HOME/.aur-pkgbuilds/$PKGNAME/PKGBUILD"

    mkdir -p "${pkgbuild_old%/*}"

    if [ -e "$pkgbuild_old" ] ; then
        diff "$pkgbuild_old" "$pkgbuild_new" >/dev/null && return   # return if identical
    fi

    HookIndicator "$hook_compare"
    /bin/meld "$pkgbuild_old" "$pkgbuild_new"

    if [ -e "$pkgbuild_old" ] ; then
        # Skip copying if package is marked as unacceptable, or user wants to skip.

        if [ "${SKIP_UNACCEPTABLE_PKGBUILD[$PKGNAME]}" ] ; then
            Color2 warning; echo2 "SKIP (unacceptable PKGBUILD)"; Color2
            return 1
        else
            Color2 info; read -p "Continue $PROGNAME (Y/n): " >&2; Color2
            case "$REPLY" in
                [Nn]*) DIE "stopped due to the unacceptable PKGBUILD of $PKGNAME" ;;
            esac
        fi
    fi

    /bin/cp "$pkgbuild_new" "$pkgbuild_old"
}

LogStuff() {
    case "$mode" in
        dryrun-local) return ;;  # avoid unnecessary pw asking
        # dryrun) return ;;  # avoid unnecessary pw asking
    esac
    if which logstuff >& /dev/null ; then
        if ! logstuff state ; then
            Color2 info; echo2 "==> logstuff on"; Color2
            logstuff on
        fi
    fi
}

HubRelease() {
    hub release "$@"
}

HubReleaseShow() {
    # also convert characters:
    #    %2B ==> +
    #    %3A ==> :
    HubRelease show "$@" | sed -e 's|%2B|+|g'     # -e 's|%3A|:|g'
}

GetRemoteAssetNames() {
    GetFromGit() {
        local dir="$1"

        if [ -r "$dir/$REPONAME.db" ] && [ -d "$GITDIR/.git" ] ; then
            Pushd "$dir"
            git pull >& /dev/null
            remote_files=$(ls -1 | sort)
            Popd
            return 0
        else
            return 1
        fi
    }

    if [ "$PREFER_GIT_OVER_RELEASE" = "yes" ] ; then
        names_from_git=yes
        case "$REPONAME" in
            endeavouros)               GetFromGit "$GITDIR/$REPONAME/$ARCH" && return ;;
            endeavouros-testing-dev)   GetFromGit "$GITDIR/$REPONAME"       && return ;;
            *)                         GetFromGit "$GITDIR/repo"            && return ;;
        esac
    fi

    # fallback to release assets
    remote_files=$(release-asset-names ${RELEASE_TAGS[0]} | sort)
    names_from_git=no
}

AskFetchingFromGithub() {
    local -r msg="Fetch assets from github (Y=only if different, n=no, f=yes)? "
    if [ "$fetch_timeout" ] ; then
        read2 -p "$msg" -t "$fetch_timeout"
    else
        printf2 "\n%s " "$msg"
        read2
    fi
    case "$REPLY" in
        [yY]*|"")
            echo2 "==> Using remote assets if there are differences, otherwise local."
            ;;
        [fF]*|"")
            echo2 "==> Using remote assets."
            return 0
            ;;
        *)
            echo2 "==> Using local assets."
            echo2 ""
            return 1
            ;;
    esac

    # Selected using remote assets with checks.
    # Check if there differences between local and remote file names.
    # If not, use local assets.

    DebugBreak "remote assets with checking"

    local local_files=""
    local remote_files=""
    local diffs=none        # what kind of diffs, if any?

    if [ "$use_release_assets" = "yes" ] ; then
        local_files=$(ls -1 *.{db,files,zst,xz,sig} 2> /dev/null | sort)   # $asset_file_endings
        GetRemoteAssetNames
    fi

    if [ "$local_files" != "$remote_files" ] ; then
        # There are differences in file names.
        # Could be the epoch related file name change, they will be fixed later.

        if [ "$names_from_git" = "yes" ] ; then
            diffs=real
        elif OnlyEpochDiffs ; then
            diffs=epoch      # because of github
        else
            diffs=real
        fi

        if [ $diffs = real ] ; then
            local tmpdir_local=$(mktemp -d /tmp/local.XXX)
            local tmpdir_remote=$(mktemp -d /tmp/remote.XXX)

            touch $(echo "$local_files"  | sed "s|^|$tmpdir_local/|")
            touch $(echo "$remote_files" | sed "s|^|$tmpdir_remote/|")

            LANG=C diff $tmpdir_local $tmpdir_remote | sed -E \
                                                           -e "s|^Only in /tmp/remote[^:]+: |Only in REMOTE: |" \
                                                           -e "s|^Only in /tmp/local[^:]+: |Only in LOCAL:  |"
            rm -rf $tmpdir_local $tmpdir_remote
        fi
    fi

    case "$diffs" in
        none)  return 1 ;;         # no diffs               ==> local
        epoch) return 1 ;;         # only epoch no diffs    ==> local
        real)  return 0 ;;         # real diffs             ==> remote
    esac
}

OnlyEpochDiffs() {
    # input: $local_files and $remote_files
    local count_ll=$(echo "$local_files" | wc -l)
    local count_rr=$(echo "$remote_files" | wc -l)
    local loc rem
    local ll rr ix
    local epoch_diff_count=0

    [ "$count_ll" != "$count_rr" ] && return 1

    readarray -t loc < <(echo "$local_files")
    readarray -t rem < <(echo "$remote_files")

    # epoch test: change first colon in local to dot and compare to remote

    for ((ix=0; ix < count_ll; ix++)) ; do
        ll="${loc[$ix]}"
        rr="${rem[$ix]}"
        [ "${ll}" = "$rr" ] && continue            # local = remote
        [ "${ll/:/.}" = "$rr" ] && {
            ((epoch_diff_count++))
            continue                               # only epoch diff, will be fixed later
        }
        return 1                                   # real diff found
    done
    if [ $epoch_diff_count -gt 0 ] ; then
        echo2 "Local and remote file names have only epoch diffs (because of github limitations) and they will be fixed automatically."
        echo2 ""
    fi
    return 0
}

Assets_clone()
{
    local names_from_git=no

    if [ "$mode" = "dryrun-local" ] && [ "$REPONAME" != "endeavouros_calamares" ] ; then
        return
    fi
    if [ "$use_release_assets" = "no" ] ; then
        if [ -n "$GITREPOURL" ] && [ -n "$GITREPODIR" ] ; then
            AskFetchingFromGithub || return 0
            echo2 "==> Copying files from the git repo to local dir."
            local tmpdir=$(mktemp -d)
            Pushd $tmpdir
            git clone  "$GITREPOURL" >& /dev/null || DIE "cloning '$GITREPOURL' failed"
            rm -f "$ASSETSDIR"/*.{db,files,zst,xz,sig,txt,old}      # $asset_file_endings
            if true ; then
                local srcfiles=()
                readarray -t srcfiles < <(/bin/ls "$GITREPODIR"/*.{db,files,zst,xz,sig} 2>/dev/null)
                if [ "$srcfiles" ] ; then
                    cp "${srcfiles[@]}" "$ASSETSDIR"
                else
                    DIE "$FUNCNAME: no files in $GITREPODIR to copy to $ASSETSDIR!"
                fi
            else
                cp "$GITREPODIR"/*.{db,files,zst,xz,sig} "$ASSETSDIR"   # $asset_file_endings
            fi
            sync
            Popd
            rm -rf $tmpdir
        else
            DIE "GITREPOURL and/or GITREPODIR missing for $REPONAME while USE_RELEASE_ASSETS = '$use_release_assets'"
        fi
        return
    fi

    local xx yy hook

    # It is possible that your local release assets in folder $ASSETSDIR
    # are not in sync with github.
    # If so, you can delete your local assets and fetch assets from github now.

    case "$REPONAME" in
        endeavouros_calamares) ;;  # many maintainers, so make sure we have the same assets!
        *)
            if [ "$repoup" = "1" ] ; then
                echo2 "==> Using local assets."
                return
            fi
            AskFetchingFromGithub || return 0
            ;;
    esac

    Pushd "$ASSETSDIR"

    local tag
    local remotes remote
    local waittime=30

    for tag in "${RELEASE_TAGS[@]}" ; do
        remotes="$(HubReleaseShow -f %as%n $tag | sed 's|^.*/||')"
        for remote in $remotes ; do
            [ -r $remote ] || break
        done
        break
    done

    DebugBreak "remote asset checking"

    if [ -r $remote ] ; then
        read2 -p "Asset names at github are the same as here, fetch anyway (y/N)? " -t $waittime
        case "$REPLY" in
            [yY]*) ;;
            *) Popd ; return ;;
        esac
    fi

    save_folder=$(mktemp -d "$PWD"/SAVED.XXX)
    echo2 "==> Saving current local assets to '$save_folder' ..."

    # $pkgname in PKGBUILD may not be the same as values in $PKGNAMES,
    # so delete all packages and databases.

    # rm -f *.{db,files,zst,xz,sig,txt,old}                                   # $asset_file_endings
    mv *.{db,files,zst,xz,sig,txt,old} "$save_folder"/ 2>/dev/null            # $asset_file_endings
    local leftovers="$(command ls *.{db,files,zst,xz,sig,old} 2>/dev/null)"   # $asset_file_endings
    test -z "$leftovers" || DIE "removing local assets failed!"

    echo2 "==> Fetching all github assets..."

    hook="${ASSET_PACKAGE_HOOKS[assets_mirrors]}"
    for xx in "${RELEASE_TAGS[@]}" ; do
        if [ "$names_from_git" = "yes" ] ; then
            local cpdir=""
            case "$REPONAME" in
                endeavouros)              cpdir="$GITDIR/$REPONAME/$ARCH" ;;
                endeavouros-testing-dev)  cpdir="$GITDIR/$REPONAME" ;;
                *)                        cpdir="$GITDIR/repo" ;;
            esac
            [ -n "$cpdir" ] || DIE "git dir is empty, cannot copy files"
            echo2 "==> Copying files from '$cpdir' ..."
            cp "$cpdir"/* .
        else
            HubRelease download $xx
            sleep 1

            # Unfortunately github release assets cannot contain a colon (epoch mark) in file name, so rename those packages locally
            # after fetching them above.

            local oldname newname Pkgname

            for oldname in *.pkg.tar.{zst,xz} ; do
                case "$oldname" in
                    "*.pkg."*) continue ;;
                esac
                Pkgname=$(pkg-name-components N "$oldname")
                IsListedPackage "$Pkgname" || continue
                HandlePossibleEpoch "$Pkgname" "$oldname" newname
                if [ "$newname" != "$oldname" ] ; then
                    echo2 "==> Fix: $oldname     --> $newname"
                    echo2 "==> Fix: $oldname.sig --> $newname.sig"
                    mv $oldname $newname
                    mv $oldname.sig $newname.sig
                fi
            done
        fi
        test -n "$hook" && { $hook && break ; }  # we need assets from only one tag since assets in other tags are the same
    done

    Popd
}

PkgbuildExists() {
    local Pkgname="$1"                         # a name from "${PKGNAMES[@]}"
    local special="$2"
    local yy=$(JustPkgname "$Pkgname")

    if [ -r "$PKGBUILD_ROOTDIR/$yy/PKGBUILD" ] ; then
        return 0
    else
        ((no_pkgbuild_count++))
        if [ "$special" != "" ] ; then
            local files=$(ls -l "$PKGBUILD_ROOTDIR/$yy" 2>/dev/null)
            printf2 "$WARNING (${PROGNAME}, $special): no PKGBUILD!\n"
            if [ -n "$files" ] ; then
                printf2 "File listing:\n"
                echo2 "$files" | sed 's|^|    ==> |'
            fi
        fi
        return 1
    fi
}

IsEmptyString() {
    local name="$1"
    local value="${!name}"
    test -n "$value" || DIE "value of variable '$name' is empty"
}
DirExists() {
    local name="$1"
    local docreate="$2"
    local value="${!name}"

    case "$docreate" in
        yes) mkdir -p "$value" ;;
        *)   test -d "$value" || {
                 DIE "variable '$name' has folder name value '$value' - the folder does not exist"
             } ;;
    esac
}

ShowIndented() {
    # shows the "head" of a listed value, possibly indented

    local txt="$1"
    local indent_level="$2"    # optional number >= 0
    local xx
    local ind=""

    case "$indent_level" in
        "") ;;
        *)
            for ((xx=0; xx < indent_level; xx++)) ; do
                ind+="    "
            done
            ;;
    esac
    printf2 "%s%-35s : " "$ind" "$1"
}

RationalityTests()
{
    ShowIndented "Checking values in $ASSETS_CONF"

    IsEmptyString ASSETSDIR
    IsEmptyString PKGBUILD_ROOTDIR
    IsEmptyString GITDIR
    IsEmptyString PKGNAMES
    IsEmptyString REPONAME
    IsEmptyString RELEASE_TAGS
    IsEmptyString SIGNER
    DirExists ASSETSDIR
    DirExists PKGBUILD_ROOTDIR yes  # silently create the dir
    DirExists GITDIR

    if [ -z "$REPO_COMPRESSOR" ] ; then
        REPO_COMPRESSOR=xz
    fi

    echo2 "done."
}

Constructor()
{
    # make sure proper .git symlink exists; create new or change existing if necessary

    if [ ! "$GITDIR"/.git -ef "$ASSETSDIR"/.git ] ; then
        echo2 "Warning: '$ASSETSDIR/.git' ($(ls -l $ASSETSDIR/.git)) does not refer to proper place, fixing..."
        rm -f "$ASSETSDIR"/.git                || DIE "failed to remove: '$ASSETSDIR/.git'"
        ln -s "$GITDIR"/.git "$ASSETSDIR"/.git || DIE "failed to symlink: '$ASSETSDIR/.git' -> '$GITDIR/.git'"
    fi
}

Destructor()
{
    [ -n "$save_folder" ] && rm -rf "$save_folder"
    test -n "$buildsavedir" && rm -rf "$buildsavedir"
}

ShowOldCompressedPackages() {
    # If we have *both* .zst and .xz package, show the .xz package.

    local pkg pkgdir Pkgname
    local pkg2 pkg22

    for pkg in $(ls "$ASSETSDIR"/*.pkg.tar.zst 2>/dev/null) ; do
        Pkgname=${pkg##*/}
        pkgdir=${pkg%/*}
        pkg2="$pkgdir/$(echo "$Pkgname" | sed 's|\-[0-9].*$||')"
        pkg22="$(ls "$pkg2"-*.pkg.tar.xz 2>/dev/null)"
        if [ -n "$pkg22" ] ; then
            for pkg2 in $pkg22 ; do
                printf2 "Remove old packages:\n    %s\n    %s\n" "$pkg2" "$pkg2.sig"
                rm -i "$pkg2" "$pkg2.sig"
            done
        fi
    done
}

_ASSERT_() {
    local ret=0
    "$@" &> /dev/null || ret=$?
    if [ $ret -ne 0 ] ; then
       echo2 "'$*' failed"
       exit $ret
    fi
}

_pkgbuilds_alt_hook() {
    if [ -d "$ASSETSDIR/.$REPONAME/.git" ] ; then
        _ASSERT_ pushd "$ASSETSDIR/.$REPONAME"
        printf2 "git pull... "
        _ASSERT_ git pull
    else
        _ASSERT_ pushd "$ASSETSDIR"
        _ASSERT_ rmdir "$PKGBUILD_ROOTDIR"
        _ASSERT_ rm -f "${PKGBUILD_ROOTDIR##*/}"
        printf2 "git clone... "
        _ASSERT_ git clone "$GITREPOURL" ".$REPONAME"
        _ASSERT_ ln -s ".$REPONAME/${PKGBUILD_ROOTDIR##*/}"
    fi
    _ASSERT_ popd
    echo2 "done."
}

PkgAdjusted() { printf2 "$pkg: planned adjustment. "; }

Fix_PKGBUILD_if_changed() {
    local out=$(/bin/git diff)        # used for detecting local changes in PKGBUILD files
    local pkg
    local changed_pkgs                # list of package names that have a changed PKGBUILD
    local left                        # number of changed packages that have no "fix" yet

    changed_pkgs="$(echo "$out" | grep -E "^... b/.*/PKGBUILD$" | sed -E 's|^... b/(.*)/PKGBUILD$|\1|')"   # which PKGBUILDs have changed
    if [ "$changed_pkgs" ] ; then
        left=$(echo "$changed_pkgs" | wc -l)
    else
        left=0
    fi

    case "$REPONAME" in
        endeavouros-testing-dev)
            for pkg in $changed_pkgs ; do
                case "$pkg" in
                    calamares-git)
                        # Special handling for calamares-git in repo endavouros-testing-dev because its PKGBUILD has line:
                        #    pkgver=.
                        ((left--))                                                            # this is a known thing, we fix it here
                        if [ "$(echo "$out" | grep "^-pkgver=\.$")" ] ; then                  # line 'pkgver=.' replaced?
                            sed -i calamares-git/PKGBUILD -e "s|^pkgver=.*$|pkgver=.|"        # set it back to 'pkgver=.' before 'git pull'
                            PkgAdjusted
                        fi
                        ;;
                    # add possible other 'endeavouros-testing-dev' package PKGBUILD management here
                esac
            done
            ;;
        endeavouros)
            for pkg in $changed_pkgs ; do
                case "$pkg" in
                    eos-lightdm-gtk-theme)                                                    # the package was copied from ARM, just accept it here
                        ((left--))
                        PkgAdjusted
                        ;;
                    # add possible other 'endeavouros' package PKGBUILD management here
                esac
            done
            ;;
    esac

    if [ $left -gt 0 ] ; then
        # show unknown changes and let user fix them
        echo2 "local $REPONAME/$PKGBUILDS has differences with the repository, please fix it if possible"
        /bin/meld .
        WantToContinue
    fi
}

WantToContinue() {
    while true ; do
        read -p "==> Want to continue (Y/n)? " >&2
        case "$REPLY" in
            "" | [Yy]*) break ;;
            [Nn]*) DIE "user wanted to stop now" ;;
        esac
    done
}

_pkgbuilds_eos_hook()
{
    # A hook function to make sure local EndeavourOS PKGBUILDS are up to date.

    local PKGBUILDS=PKGBUILDS

    if [ -d "$ASSETSDIR/.$REPONAME/$PKGBUILDS/.git" ] ; then
        _ASSERT_ pushd "$ASSETSDIR/.$REPONAME/$PKGBUILDS"
        Fix_PKGBUILD_if_changed
        printf2 "git pull... "
        _ASSERT_ git pull
    else
        local GITPKGBUILDSURL=https://github.com/endeavouros-team/$PKGBUILDS.git
        _ASSERT_ pushd "$ASSETSDIR"
        if [ -d $PKGBUILDS ] && [ ! -L $PKGBUILDS ] ; then
            rmdir $PKGBUILDS
        fi
        printf2 "git clone... "
        _ASSERT_ git clone "$GITPKGBUILDSURL" ".$REPONAME/$PKGBUILDS"
        _ASSERT_ ln -s ".$REPONAME/$PKGBUILDS"
    fi
    echo2 "done"
    _ASSERT_ popd
}

RunPreHooks()
{
    if [ "$repoup" = "1" ] ; then
        return
    fi

    ShowIndented "Running asset hooks..."

    case "$REPONAME" in
        endeavouros | endeavouros-testing-dev)
            _pkgbuilds_eos_hook ;;
        *)
            _pkgbuilds_alt_hook ;;
    esac
}

GitUpdate_repo() {
    [ "$PREFER_GIT_OVER_RELEASE" = "yes" ] || return

    local -r app=/usr/bin/EosGitUpdate
    local newrepodir="$GITDIR"

    if [ -n "$built" ] || [ "$repoup" = "1" ] ; then
        # if [ -e "$newrepodir/.GitUpdate" ] ; then
            FinalStopBeforeSyncing "$REPONAME repo"
            Pushd "$newrepodir"
            $app "$ARCH: $*" "$ASSETSDIR" || DIE "$app failed!"
            Popd
            ManualCheckOfAssets addition repo
        # fi
    fi
}

RunPostHooks()
{
    if [ "$repoup" = "1" ] ; then
        return
    fi
    if [ -n "$ASSET_POST_HOOKS" ] ; then
        ShowIndented "Running asset post hooks"
        local xx
        for xx in "${ASSET_POST_HOOKS[@]}" ; do
            $xx
        done
        echo2 "done."
    fi
}

Browser() {
    local browser
    for browser in firefox firefox-developer-edition exo-open kde-open xdg-open ; do
        if [ -x /usr/bin/$browser ] ; then
            /usr/bin/$browser "$@" &> /dev/null
            return
        fi
    done
}

AskYesNo() {
    local -n _answer="$1"      # return the result with this variable
    local prompt="$2"          # the question without any tail like "(Y/n)? "
    local -r default="$3"      # "yes" or "no"
    local ask_timeout="$4"     # seconds; optional; default=30

    case "$default" in
        yes) prompt+=" (Y/n)? " ;;
        no)  prompt+=" (y/N)? " ;;
        *) _answer=no; return ;;       # usage error?
    esac
    [ "$ask_timeout" ] || ask_timeout=30

    while true ; do
        eos-color warning 2                      # TODO: better "note" than "warning"
        read2 -sn1 -p "$prompt" -t $ask_timeout
        eos-color reset 2
        if [ $? -eq 0 ] ; then
            case "$REPLY" in
                [yY])    _answer=yes; return ;;
                [nN]|"") _answer=no;  return ;;
                *) ;;                            # wrong answer ==> ask again
            esac
        else
            _answer=$default                     # timeout ==> return the default
            return
        fi
    done
}

WantPkgDiffs() {
    local xx="$1"
    local pkgdirname="$2"
    local changelog_for_pkg=""    # "${PKG_CHANGELOGS[$pkgdirname]}"

    Pushd "$ASSETSDIR"
    changelog_for_pkg="$(eos-pkg-changelog --github --quiet -du "$pkgdirname")" || { Popd; return; }
    Popd

    if [ "$changelog_for_pkg" ] ; then
        if [ "$pkgdiff" = "unknown" ] ; then
            local -r ask_timeout=20
            AskYesNo pkgdiff "Want to see changelog(s)" no $ask_timeout
            echo2 "$pkgdiff"
        fi
        if [ "$pkgdiff" = "yes" ] ; then
            local urls=()
            readarray -t urls < <(echo "${changelog_for_pkg//|/$'\n'}")
            PKG_DIFFS+=("${urls[@]}")
        fi
    fi
}

ShowPkgDiffs() {
    if [ "$pkgdiff" = "yes" ] ; then
        if [ ${#PKG_DIFFS[@]} -gt 0 ] ; then
            Browser "${PKG_DIFFS[@]}"
        fi
    fi
}

Exit()
{
    local code="$1"
    Destructor
    exit "$code"
}

_SleepSeconds() {
    local sec="$1"
    local xx
    for ((xx=sec; xx>0; xx--)) ; do
        printf2 "\r%s   " "$xx"
        sleep 1
    done
    printf2 "\r%s\n" "$xx"
}

MirrorCheck() {
    if [ ! -r endeavouros.db ] ; then
        return
    fi
    local checker="/usr/share/endeavouros/scripts/mirrorcheck"
    local mirror_check="Alpix mirror check"
    local timeout
    local opt="--no-filelist"

    test "$use_filelist" = "yes" && opt=""

    if [ -n "$built" ] ; then
        timeout="$mirror_check_wait"
    else
        timeout=3
    fi
    if [ -x "$checker" ] ; then
        if [ $timeout -eq 180 ] ; then
            read2 -p "Do $mirror_check (Y/n)?"
        fi
        case "$REPLY" in
            ""|[yY]*)
                echo2 "Starting $mirror_check after countdown, please wait..."
                _SleepSeconds $timeout
                $checker $opt .
                ;;
        esac
    else
        echo2 "Sorry, checker $checker not found."
        echo2 "Cannot do $mirror_check."
    fi
}

TimeStamp() {
    local start_sec="$1"

    case "$start_sec" in
        "")
            # return starting time
            /usr/bin/date +%s
            ;;
        [0-9]*)
            # return elapsed time
            /usr/bin/date -u --date=@$(($(TimeStamp) - start_sec)) '+%Hh %Mm %Ss'
            ;;
    esac
}

Vercmp() {
    # like vercmp, but "$notexist" is always older

    if [ "$1" = "$notexist" ]; then
        echo '-1'
    elif [ "$2" = "$notexist" ]; then
        echo '1'
    else
        vercmp "$1" "$2"
    fi
}

PkgnameFilter() {
    # remove trailing parts after the 'pkgname'
    # sed 's|-[^-]*-[^-]*-[^-]*$||'    
    sed -E 's|-[^-]+-[^-]+-[^\.]+\.pkg\.tar\..*$||'
}

PkgnameFromPkg() {
    local pkg="$1"
    pkg=${pkg##*/}
    # echo "$pkg" | PkgnameFilter
    echo "$pkg" | pkg-name-components N
}

ListPkgsWithName() {
    local Pkgname="$1"
    local compr="$2"
    local name
    local tmp=""
    local dir=${Pkgname%/*}

    if [ "$Pkgname" = "$dir" ] ; then
        dir="."
    else
        Pkgname=${Pkgname##*/}
    fi

    Pushd "$dir"
    tmp=$(/bin/ls -1v "$Pkgname"-*.pkg.tar.$compr 2> /dev/null | grep -E "${Pkgname}-[^-]+-[^-]+-[^\.]+\.pkg\.tar\.$compr$")
    Popd
    [ "$tmp" ] || return

    for name in $tmp ; do
        if [ "$(echo "$name" | pkg-name-components N)" = "$Pkgname" ] ; then
            echo "$dir/$name"
        fi
    done
}

Usage() {
    cat <<EOF >&2
$PROGNAME: Build packages and transfer them to github.

$PROGNAME [ options ]
Options:
    --allow-downgrade, -ad      New package may have smaller version number.
    --dryrun-local, -n          Show what would be done, but do nothing. Use local assets.
    --dryrun, -nn               Show what would be done, but do nothing.
    --explain-hook-marks, -e    Explain markings on hooks.
    --fetch-timeout=X | -T=X    Timeout (in seconds) when asking to fetch remote assets (default: no timeout).
    --pkgnames="X"              X is a space separated list of packages to use instead of PKGNAMES array in assets.conf.
    --pkgdiff                   Show changelog for modified packages.
    --repoup                    (Advanced) Force update of repository database files.
    --no-aur                    Dont't try to use packages from the AUR (sometimes it is unavailable).
    --aursrc=X                  From where we fetch AUR packages, one of: aur (default), repo, local.
EOF
#   --versuffix=X               Append given suffix (X) to pkgver of PKGBUILD.
#   --mirrorcheck=X             X is the time (in seconds) to wait before starting the mirrorcheck.

    test -n "$1" && exit "$1"
}

IsInWaitList() {
    local pkg="$1"
    local newver="$2"  # optional!
    local xx

    if [ -n "$PKGNAMES_WAIT" ] ; then
        for xx in "${PKGNAMES_WAIT[@]}" ; do
            case "$xx" in
                "$pkg")
                    # old syntax - pkgname - still supported currently, may be deprecated later
                    return 0
                    ;;
                "$pkg|"*)
                    # New syntax: pkgname|version-to-skip[*]
                    # Note: skip_version may end with a '*' to match any tail, then e.g.
                    #     skip_version: v14.1.r*
                    #     newver:       v14.1.r13.gc504674-1
                    # match.
                    [ -n "$newver" ] || newver="$(PkgBuildVersion "$PKGBUILD_ROOTDIR/$pkgdirname")"
                    local skip_version="${xx#*|}"
                    if [ "${skip_version: -1}" = "*" ] ; then
                        # skip_version ends with a '*'
                        case "$newver" in
                            "${skip_version:: -1}"*) return 0 ;;
                        esac
                    else
                        [ "$skip_version" = "$newver" ] && return 0
                    fi
                    return 1    # $pkg handled, no match
                    ;;
            esac
        done
    fi
    return 1
}

DowngradeProbibited() {
    local cmpresult="$1"
    local allow_downgrade="$2"

    [ $cmpresult -lt 0 ] && [ "$allow_downgrade" = "no" ] && [ "${HAS_GIT_PKGVER[$pkgdirname]}" != "yes" ]
}

ShowResult() {
    local -r verdict="$1"
    local -r hookout="$2"
    local -r fastfunc="$3"

    if [ -n "$hookout" ] ; then
        if [ "$fastfunc" ] ; then
            echo2 "$verdict  [$fastfunc: $hookout]"
        else
            echo2 "$verdict  [hook: $hookout]"
        fi
    else
        echo2 "$verdict"
    fi
}

MovePackageAsLastToBuild() {
    local -r pkgname="$1"
    if [ "$(printf "%s\n" "${PKGNAMES[@]}" | grep "^$pkgname$")" ] ; then
        local tmp=()
        readarray -t tmp < <(printf "%s\n" "${PKGNAMES[@]}" | grep -v "^$pkgname$")
        tmp+=("$pkgname")
        PKGNAMES=("${tmp[@]}")
    fi
}

assert_is_number_ge_0() {
    [ "${1//[0-9]/}" ] && DIE "'$1' is not a non-negative number"
}

SetAurDelay() {
    local val="$1"
    case "$val" in
        *h) aur_delay=${val:: -1} ; assert_is_number_ge_0 "$aur_delay" ; ((aur_delay*=3600)) ;;
        *m) aur_delay=${val:: -1} ; assert_is_number_ge_0 "$aur_delay" ; ((aur_delay*=60)) ;;
        *s) aur_delay=${val:: -1} ; assert_is_number_ge_0 "$aur_delay" ;;
        *)  aur_delay=${val}      ; assert_is_number_ge_0 "$aur_delay" ;;
    esac
}

Main2() {
    test -n "$PKGEXT" && unset PKGEXT   # don't use env vars!

    local buildStartTime
    local listing_updates=""

    local mode=""
    local xx yy zz
    local repoup=0
    local explain_hooks=no
    local pkgver_suffix=""
    local pkgdiff=unknown            # yes=show AUR diff, no=don't show, unknown=need to ask for yes or no
    local filelist_txt
    local use_filelist               # yes or no
    local allow_downgrade=no
    local PKG_DIFFS=()
    local mirror_check_wait=180
    local use_release_assets         # currently only for [endeavouros] repo
    local save_folder=""
    local PKGNAMES_PARAMETER=""
    local AUR_IS_AVAILABLE=yes       # to be used also in assets.conf files
    local aur_src=aur
    local aur_delay=0
    local fetch_timeout=""
    local helper=""
    local -r config_file="/etc/eos-script-lib-yad.conf"

    source "$config_file"

    while true ; do
        if [ -z "$EOS_AUR_HELPER" ] ; then
            WARN "EOS_AUR_HELPER is empty in $config_file"
        else
            helper="$EOS_AUR_HELPER"
            [ -x "/bin/$helper" ] && break
        fi
        if [ -z "$EOS_AUR_HELPER_OTHER" ] ; then
            WARN "EOS_AUR_HELPER_OTHER is empty in $config_file"
        else
            helper="$EOS_AUR_HELPER_OTHER"
            [ -x "/bin/$helper" ] && break
        fi
        break
    done
    if [ "$helper" ] && [ ! -x "/bin/$helper" ] ; then
        WARN "AUR helper not installed? Check EOS_AUR_HELPER and EOS_AUR_HELPER_OTHER in $config_file"
        helper="yay"
    fi

    local -r hook_pkgver="#"
    local -r hook_pkgver_func="p"
    local -r hook_multiversion="+"
    local -r hook_yes="*"
    local -r hook_compare="c"
    local hook_no=""                 # will contain strlen(hook_yes) spaces
    for xx in $(seq 1 ${#hook_yes}) ; do
        hook_no+=" "
    done

    DebugBreak

    # Check given parameters:
    if [ -n "$1" ] ; then
        for xx in "$@" ; do
            case "$xx" in
                --no-aur)                  AUR_IS_AVAILABLE=no ;;
                --aursrc=*)                aur_src="${xx#*=}" ;;        # * = aur (default), repo, local.
                --aur-delay=*)             SetAurDelay "${xx#*=}" ;;    # * = <number>{s|m|h}
                --dryrun-local | -nl | -n) mode=dryrun-local ;;
                --dryrun | -nr | -nn)      mode=dryrun ;;
                --repoup)                  repoup=1 ;;                  # sync repo even when no packages are built
                --pkgdiff)                 pkgdiff=yes ;;
                -e | --explain-hook-marks) explain_hooks=yes ;;
                --allow-downgrade | -ad)   allow_downgrade=yes ;;

                --pkgnames=*)              PKGNAMES_PARAMETER="$xx" ;;
                --fetch-timeout=* | -T=*)  fetch_timeout="${xx#*=}" ;;

                --dump-options) ;;

                # currently not used!
                --mirrorcheck=*)           mirror_check_wait="${xx#*=}";;
                --versuffix=*)             pkgver_suffix="${xx#*=}" ;;

                -h | --help | *) Usage 0  ;;
            esac
        done
    fi
    eos-connection-checker || DIE "internet connection is not available."

    test -r $ASSETS_CONF || DIE "cannot find local file $ASSETS_CONF"

    local PKGNAMES=()
    local PKGNAMES_WAIT=()
    local EOS_ROOT=""                       # configures the base folder for all EOS stuff
    local _PACKAGER=""
    local REPOSIG=0                         # 1 = sign repo too, 0 = don't sign repo
    local SKIP_UNACCEPTABLE_PKGBUILD=()

    source /etc/$PROGNAME.conf     # sets the base folder of everything
    [ -n "$EOS_ROOT" ] || DIE "EOS_ROOT is not set in /etc/$PROGNAME.conf!"
    [ -n "$_PACKAGER" ] || DIE "_PACKAGER is not set in /etc/$PROGNAME.conf!"

    declare -A ASSET_FAST_UPDATE_CHECKS=()

    if false && [ $AUR_IS_AVAILABLE = yes ] && grep -E "^[ ]+[^ ]+/aur$" $ASSETS_CONF >/dev/null ; then
        echo2 -n "==> Checking AUR availability: "
        if is-aur-available --seconds=$aur_delay ; then
            echo2 success
        else
            AUR_IS_AVAILABLE=no
            echo2 failure
        fi
    fi
    source $ASSETS_CONF                     # local variables (with CAPITAL letters)

    export PACKAGER="$_PACKAGER"
    echo2 "PACKAGER: $PACKAGER"

    [ -n "$PKGNAMES_PARAMETER" ] && PKGNAMES=(${PKGNAMES_PARAMETER#*=})

    filelist_txt="$ASSETSDIR/repofiles.txt"
    use_filelist="$USE_GENERATED_FILELIST"
    test -n "$use_filelist" || use_filelist="no"
    use_release_assets="$USE_RELEASE_ASSETS"
    test -n "$use_release_assets" || use_release_assets=yes

    LogStuff

    DebugBreak "before RationalityTests"
    
    RationalityTests            # check validity of values in $ASSETS_CONF

    Constructor

    # aur-fetch-pkg-info --fetch  # get metainfo of AUR packages

    RunPreHooks                 # may/should update local PKGBUILDs
    Assets_clone                # offer getting assets from github instead of using local ones
    unset -f pkgver             # remove possible leftover pkgver() from any PKGBUILD

    # Check if we need to build new versions of packages.
    # To do that, we compare local asset versions to PKGBUILD versions.
    # Note that
    #   - Assets_clone above may have downloaded local assets from github (if user decides it is necessary)
    #   - RunPreHooks  above may/should have updated local PKGBUILDs

    local removable=()          # collected
    local removableassets=()    # collected
    local built=()              # collected
    local signed=()             # collected
    local repo_removes=()
    declare -A newv oldv
    local tmp tmpcurr
    local pkg
    local pkgdirname            # dir name for a package
    local Pkgname
    local buildsavedir          # tmp storage for built packages
    local notexist='<non-existing>'
    local cmpresult
    local total_items_to_build=0
    local items_waiting=0
    local no_pkgbuild_count=0
    local hookout=""
    local -r WARNING="$(Color1 warning)WARNING$(Color1)"
    local -r OK="$(Color1 ok)OK$(Color1)"
    local -r WAITING="$(Color1 info)UPDATE WAIT$(Color1)"
    local -r IN_WAIT_LIST="$(Color1 info)also in wait list$(Color1)"
    local -r CHANGED="$(Color1 warning)CHANGED$(Color1)"
    local ret=""
    local fastmsg=""
    local fastfunc=""

    listing_updates=yes

    DebugBreak "before check loop"

    if [ "$repoup" = "0" ] ; then

        echo2 "Finding package info ..."

        Pushd "$PKGBUILD_ROOTDIR"

        FetchAurPkgs

        for xx in "${PKGNAMES[@]}" ; do
            ShowIndented "$xx" 1                                                # show also the "/aur" suffix if available
            hookout=""
            ListNameToPkgName "$xx" yes || continue                             # sets pkgdirname and hookout
            [ -n "$pkgdirname" ] || DIE "converting or fetching '$xx' failed"
            PkgbuildExists "$pkgdirname" "line $LINENO" || continue

            # get current versions from local asset files
            Pkgname="$(PkgBuildName "$pkgdirname")"
            tmpcurr="$(LocalVersion "$ASSETSDIR/$Pkgname")"
            case "$tmpcurr" in
                "") DIE "LocalVersion for '$xx' failed" ;;
                "-" | 0)
                    # package (and version) not found
                    tmpcurr="$notexist"
                    ;;
            esac

            fastfunc="${ASSET_FAST_UPDATE_CHECKS[$pkgdirname]}"
            if [ "$fastfunc" ] ; then
                fastmsg="$($fastfunc)"
                ret=$?
                case "$ret" in
                    0) ;;    # there are changes, so carry on!
                    1) ShowResult "$OK ($tmpcurr)" "$fastmsg" "$fastfunc" ; continue ;;
                    2|3) ;;
                    *) echo2 "error: fast check hook returned $ret"; continue ;;
                esac
            fi

            # get versions from latest PKGBUILDs
            tmp="$(PkgBuildVersion "$PKGBUILD_ROOTDIR/$pkgdirname")"
            test -n "$tmp" || DIE "PkgBuildVersion for '$xx' failed"

            newv[$pkgdirname]="$tmp"
            oldv[$pkgdirname]="$tmpcurr"

            cmpresult=$(Vercmp "$tmp" "$tmpcurr")

            if IsInWaitList "$xx" "$tmp" ; then
                ((items_waiting++))
                if [ "$tmpcurr" = "$tmp" ] ; then
                    ShowResult "$OK ($tmpcurr) [$IN_WAIT_LIST]" "$hookout"
                else
                    ShowResult "$WAITING ($tmpcurr ==> $tmp)" "$hookout"
                fi
                continue
            fi
            if [ $cmpresult -eq 0 ] ; then
                ShowResult "$OK ($tmpcurr)" "$hookout"
                continue
            fi
            if DowngradeProbibited "$cmpresult" "$allow_downgrade" ; then
                ShowResult "$OK ($tmpcurr)" "$hookout"
                continue
            fi

            DebugBreak "decided to build"

            ((total_items_to_build++))
            ShowResult "$CHANGED ($tmpcurr ==> $tmp)" "$hookout"

            [ $cmpresult -gt 0 ] && WantPkgDiffs "$xx" "$pkgdirname"
        done

        DebugBreak "before building"

        [ "${#PKG_DIFFS[@]}" -gt 0 ] && ShowPkgDiffs

        Popd

        local exit_code=$total_items_to_build
        local color
        if [ $total_items_to_build -eq 0 ] ; then
            total_items_to_build=NONE
            color="${GREEN}"
        else
            color="${RED}"
        fi

        printf2 "\nItems to build: %s%s/%s%s\n" "$color" "$total_items_to_build" "${#PKGNAMES[@]}" "$(Color1)"

        if [ "$items_waiting" != "0" ] ; then
            printf2   "Items waiting:  %s\n" "$items_waiting"
        fi
        if [ "$no_pkgbuild_count" != "0" ] ; then
            printf2   "No PKGBUILD:    %s\n" "$no_pkgbuild_count"
        fi

        if [ "$explain_hooks" = "yes" ] ; then
            ExplainHookMarks
        else
            printf2 "\n"
        fi
    fi

    case "$mode" in
        dryrun | dryrun-local)
            Exit $((exit_code + 100))   # return 100 + number of items that need building
            ;;
    esac

    listing_updates=no
    
    if [ "$repoup" = "0" ] ; then
        # build if newer versions exist. When building, collect removables and builds.

        buildsavedir="$(mktemp -d "$HOME/.tmpdir.XXXXX")"

        MovePackageAsLastToBuild calamares        # if calamares will be built, make it the last to build

        local built_under_this_pkgname
        # local remove_under_this_pkgname
        echo2 "Check if building is needed..."
        for xx in "${PKGNAMES[@]}" ; do
            ListNameToPkgName "$xx" no
            PkgbuildExists "$xx" "line $LINENO ($xx)" || continue

            cmpresult=$(Vercmp "${newv[$pkgdirname]}" "${oldv[$pkgdirname]}")

            # See if we have to build.
            [ "$cmpresult" -eq 0 ] && continue

            if DowngradeProbibited "$cmpresult" "$allow_downgrade" ; then
                continue
            fi
            if IsInWaitList "$xx" "${newv[$pkgdirname]}" ; then
                echo2 "==> skipped: $xx"
                continue
            fi

            # Build the package (or possibly many packages!)
            built_under_this_pkgname=()
            # remove_under_this_pkgname=()   # we don't know only from pkgname!

            echo2 "==> $pkgdirname:"
            buildStartTime="$(TimeStamp)"

            Build "$pkgdirname" "$buildsavedir" "$PKGBUILD_ROOTDIR/$pkgdirname"

            echo2 "    ==> Build time: $(TimeStamp $buildStartTime)"
            for yy in "${built_under_this_pkgname[@]}" ; do
                printf2 "    ==> %15s %s\n" "$(FileSizePrint "$buildsavedir/$yy")" "$yy"
                #echo2  "    ==> $yy"
            done

            # determine old pkgs, may be many
            for zz in zst xz ; do
                for yy in "${built_under_this_pkgname[@]}" ; do
                    Pkgname="$(PkgnameFromPkg "$yy")"
                    # pkg="$(ls -1 "$ASSETSDIR/$Pkgname"-[0-9]*.pkg.tar.$zz 2> /dev/null)"
                    pkg=$(ListPkgsWithName "$Pkgname" "$zz")
                    if [ -n "$pkg" ] ; then
                        local xyz
                        for xyz in $pkg ; do
                            removable+=("$xyz")
                            removable+=("$xyz".sig)

                            yy=${xyz##*/}
                            removableassets+=("$yy")
                            #removableassets+=("$yy".sig)
                        done
                    fi
                done
            done
        done
    fi

    if [ -n "$built" ] || [ "$repoup" = "1" ] ; then

        # We have something built to be sent to github, or we want to update repo to github.
        
        # now we have: removable (and removableassets), built and signed

        if [ ! "$PWD" -ef "$ASSETSDIR" ] ; then
            DIE "wrong directory: $PWD != $ASSETSDIR"
        fi

        # Move built and signed to assets dir...
        if [ -n "$built" ] && [ "$repoup" = "0" ] ; then
            echo2 "Signing and putting it all together..."

            if [ -n "$built" ] ; then
                # sign built packages
                for pkg in "${built[@]}" ; do
                    gpg --local-user "$SIGNER" \
                        --output "$pkg.sig" \
                        --detach-sign "$pkg" || DIE "signing '$pkg' failed"
                    signed+=("$pkg.sig")
                done

                mv -i "${built[@]}" "${signed[@]}" "$ASSETSDIR"

                rm -rf $buildsavedir

                # ...and fix the variables 'built' and 'signed' accordingly.
                tmp=("${built[@]}")
                built=()
                for xx in "${tmp[@]}" ; do
                    built+=("${xx##*/}")
                done
                tmp=("${signed[@]}")
                signed=()
                for xx in "${tmp[@]}" ; do
                    signed+=("${xx##*/}")
                done

                for xx in "${built[@]}" ; do
                    case "$xx" in
                        *.pkg.tar.$_COMPRESSOR)
                            #pkgname="$(basename "$xx" | sed 's|\-[0-9].*$||')"
                            Pkgname="$(PkgnameFromPkg "$xx")"
                            repo_removes+=("$Pkgname")
                            ;;
                    esac
                done

                if [ -n "$removable" ] ; then
                    # Here we have some old packages after upgrading them.
                    # Save them automatically into an archive at github.
                    # Then downgrading of EOS packages can be supported with app 'eos-downgrade'.

                    if [ -n "$ARCHIVE_TAG" ] ; then
                        local archiving=success
                        local pkg_archive="$ASSETSDIR/PKG_ARCHIVE"

                        # local archiving

                        mkdir -p "$pkg_archive"                    || archiving=fail1
                        if [ "$archiving" = "success" ] ; then
                            chmod -R u+w "$pkg_archive"            || archiving=fail2
                        fi
                        if [ "$archiving" = "success" ] ; then
                            mv -f "${removable[@]}" "$pkg_archive" || archiving=fail3
                        fi

                        if [ "$archiving" = "success" ] ; then

                            # remove archiving

                            Pushd "$pkg_archive"

                            # (re)create proper symlink
                            if [ ! -e .git ] || [ -L .git ] ; then
                                if [ -d "$ARCHIVE_GIT" ] ; then
                                    rm -f .git
                                    ln -s "$ARCHIVE_GIT"
                                fi
                            fi
                            if [ -d .git ] ; then
                                case "$REPONAME" in
                                    endeavouros | endeavouros-testing-dev) archive-sync-to-remote "$ARCHIVE_TAG" ;;
                                    *)                                     add-release-assets "$ARCHIVE_TAG" "${removable[@]##*/}" ;;
                                esac
                            else
                                WARN "the .git folder of the pkg archive was not found"
                            fi

                            Popd
                        else
                            WARN "($archiving) problem moving old packages to $pkg_archive"
                        fi
                        chmod -R -w "$pkg_archive"               # do not (accidentally) delete archived packages...
                    fi
                fi
                
                if [ -n "$repo_removes" ] ; then
                    # check if repo db contains any of the packages to be removed
                    # yy="$(tar --list --exclude */desc -f "$ASSETSDIR/$REPONAME".db.tar.$REPO_COMPRESSOR | sed 's|-[0-9].*$||')"
                    yy="$(tar --list -f "$ASSETSDIR/$REPONAME".db.tar.$REPO_COMPRESSOR | grep "/desc$" | sed 's|-[^-]*-[^-]*$||')"
                    zz=()
                    for xx in "${repo_removes[@]}" ; do
                        if [ -n "$(echo "$yy" | grep "^$xx$")" ] ; then
                            zz+=("$xx")
                        fi
                    done
                    if [ -n "$zz" ] ; then
                        # packages found in the repo db, so remove them
                        repo-remove "$ASSETSDIR/$REPONAME".db.tar.$REPO_COMPRESSOR "${zz[@]}"
                        sleep 1
                    fi
                fi

                # Put changed assets (built) to db.
                repo-add --include-sigs "$ASSETSDIR/$REPONAME".db.tar.$REPO_COMPRESSOR "${built[@]}"
            fi
        fi

        if [ $REPOSIG -eq 1 ] ; then
            echo2 "Signing repo $REPONAME ..."
            repo-add --sign --key "$SIGNER" "$ASSETSDIR/$REPONAME".db.tar.$REPO_COMPRESSOR >/dev/null
        fi
        for xx in db files ; do
            rm -f "$ASSETSDIR/$REPONAME".$xx.tar.$REPO_COMPRESSOR.old{,.sig}
            rm -f "$ASSETSDIR/$REPONAME".$xx
            cp -a "$ASSETSDIR/$REPONAME".$xx.tar.$REPO_COMPRESSOR     "$ASSETSDIR/$REPONAME".$xx
            if [ $REPOSIG -eq 1 ] ; then
                rm -f "$ASSETSDIR/$REPONAME".$xx.sig
                cp -a "$ASSETSDIR/$REPONAME".$xx.tar.$REPO_COMPRESSOR.sig "$ASSETSDIR/$REPONAME".$xx.sig
            fi
        done

        # Now all is ready for syncing with github.

        GitUpdate_repo "${built[@]}"

        sleep 3

        if false ; then
            case "$REPONAME" in
                endeavouros)
                    case "$use_release_assets" in
                        yes) ManageGithubReleaseAssets ;;
                        *)   ;; # ManageGithubNormalFiles ;;
                    esac
                    ;;
                *)
                    ManageGithubReleaseAssets
                    ;;
            esac
        else
            ManageGithubReleaseAssets
        fi
    else
        echo2 "Nothing to do."
    fi

    Destructor

    ShowOldCompressedPackages   # should show nothing

    #MirrorCheck

    RunPostHooks
}

SettleDown() {
    local arg
    local ask=yes
    local msg

    for arg in "$@" ; do
        case "$arg" in
            --no-ask) ask=no ;;
            -*) WARN "$FUNCNAME: unsupported parameter '$arg'." ;;
            *) msg="$arg" ;;
        esac
    done
    test -n "$msg" && echo2 "Info: $msg"
    if [ "$ask" = "yes" ] ; then
        read2 -p "Wait, let things settle down, then press ENTER to continue: " -t 10
    fi
    echo2 ""
}

AssetCmdShow() {
    local xx
    local line="$1"            # cmd
    shift

    case "$1" in
        -*) shift ;;           # option --quietly for delete-release-assets
    esac

    line+=" for $1:"           # tag
    shift

    echo2 "$line"
    for xx in "$@" ; do
        echo2 "    $xx"
    done
}

AssetCmd() {
    local arg=""
    case "$1" in
        --no-ask) arg="$1" ; shift ;;
    esac

    # AssetCmdShow "$@"
    "$@"
    if [ $? -ne 0 ] ; then
        DIE "command '$*' failed!"
    fi

    SettleDown $arg
}
AssetCmdLast() {
    local arg=""
    if [ "$tag" = "${RELEASE_TAGS[$last_tag]}" ] ; then
        arg="--no-ask"
    else
        arg="--no-ask"   # arg=""
    fi
    AssetCmd $arg "$@"
}

ManualCheckOfAssets() {
    local op="$1"
    local what="$2"
    local timeout="$EOS_PKGBUILD_GITHUB_TIMEOUT"

    [ -n "$timeout" ] || timeout=5    # was 10

    case "$what" in
        repo) [ "$use_release_assets" = "yes" ] || return ;;
    esac

    sleep 1
    while true ; do
        case "$what" in
            assets) what="assets in $tag" ;;
        esac
        echo2 ""
        read2 -t $timeout -p "$what: Is $op OK (Y/n)? "
        case "$REPLY" in
            [yY]* | "") break ;;
            *) ;;
        esac
    done
    #echo2 ""
}

FinalStopBeforeSyncing() {
    local what="$1"
    printf2 "\n%s\n" "Final stop before syncing '$what' with github!"
    read2 -p "Continue (Y/n)? "
    case "$REPLY" in
        [yY]*|"") ;;
        *) Exit 0 ;;
    esac
}

ManageGithubReleaseAssets() {
    case "$use_release_assets" in
        no) return ;;
    esac

    echo2 "Syncing $REPONAME release assets with github:"

    local last_tag=$((${#RELEASE_TAGS[@]} - 1))
    local assets

    # Github seems to have issues with some files:
    # - too long paths when adding release assets to github ??
    # - file orders --> cache issues ??

    # Remove old assets (removable) from github and local folder.

    for tag in "${RELEASE_TAGS[@]}" ; do
        assets=()

        # delete-release-assets does not need the whole file name, only unique start!
        assets+=("$REPONAME".{db,files})

        if [ -n "$removableassets" ] ; then
            #AssetCmd delete-release-assets --quietly "$tag" "${removableassets[@]}"
            assets+=("${removableassets[@]}")

            if [ -r "$filelist_txt" ] ; then
                #AssetCmd delete-release-assets --quietly "$tag" "$(basename "$filelist_txt")"
                assets+=("${filelist_txt##*/}")
            fi
        fi

        AssetCmd --no-ask delete-release-assets --quietly "$tag" "${assets[@]}"

        if [ -r "$filelist_txt" ] ; then
            echo2 "deleting file $filelist_txt ..."
            rm -f "$filelist_txt"
        fi

        ManualCheckOfAssets deletion assets

        # Now manage new assets.

        assets=()

        if [ "$use_filelist" = "yes" ] ; then
            # create a list of package and db files that should be also on the mirror
            Pushd "$ASSETSDIR"
            pkg="$(ls -1 *.pkg.tar.* "$REPONAME".{db,files}{,.tar.$REPO_COMPRESSOR}{,.sig} 2>/dev/null)"
            if [ -n "$filelist_txt" ] ; then
                [ "$RELEASE_ASSETS_REMOTE_BASE" ] || DIE "RELEASE_ASSETS_REMOTE_BASE is not set in ${ASSETS_CONF}!"
                echo "$pkg" | sed "s|^|$RELEASE_ASSETS_REMOTE_BASE/|" > "$filelist_txt"
            fi
            popd >/dev/null
        fi

        # transfer assets (built, signed and db) to github
        if [ -n "$built" ] ; then
            #AssetCmd add-release-assets "$tag" "${signed[@]}" "${built[@]}"
            assets+=("${built[@]}")
            if [ -r "$filelist_txt" ] ; then
                #AssetCmd add-release-assets "$tag" "$filelist_txt"
                assets+=("${filelist_txt##*/}")
            fi
        fi

        assets+=(
            "$REPONAME".{db,files}
            "$REPONAME".{db,files}.tar.$REPO_COMPRESSOR
        )
        if [ $REPOSIG -eq 1 ] ; then
            assets+=("$REPONAME".{db,files}.tar.$REPO_COMPRESSOR.sig)
            assets+=("$REPONAME".{db,files}.sig)
        fi
        if [ -n "$built" ] ; then
            assets+=("${signed[@]}")
        fi

        AssetCmdLast add-release-assets "$tag" "${assets[@]}"

        if [ "$tag" = "${RELEASE_TAGS[$last_tag]}" ] ; then
            sleep 1
            break
        fi

        ManualCheckOfAssets addition assets
    done
}

ManageGithubNormalFiles() {
    return    # no more needed !!?

    case "$REPONAME" in
        endeavouros) ;;
        endeavouros-testing-dev) return ;;   # TODO: remove 'return' when the repo exists!
        *) return ;;
    esac

    local workdir="$HOME/EOS/repo"
    local targetdir="$workdir/$REPONAME"
    local cp_output

    test -d "$workdir"       || DIE "work folder $workdir does not exist."
    test -d "$targetdir"     || DIE "target folder $targetdir does not exist."

    Pushd "$workdir"
    cp_output="$(cp -uv "$ASSETSDIR"/*.{db,files,zst,xz,sig} "$targetdir")"   # $asset_file_endings
    Popd

    if [ -n "$cp_output" ] ; then
        echo2 "$cp_output"
        printf2 "\nFiles were updated. Goto $workdir and transfer changes to github (with git commands).\n"
    else
        echo2 "Nothing more to do."
    fi
}

AssetsConfLocalVal() {
    # Search file assets.conf for values like:
    #     local REPONAME="repo-name"

    local searchval="$1"
    grep "^local ${searchval}=" $ASSETS_CONF | cut -d '=' -f 2 | tr -d '"' | tr -d "'"
}

Main() {
    local PROGNAME="${0##*/}"
    [ "$PROGNAME" ] || PROGNAME="${BASH_ARGV0##*/}"
    [ "$PROGNAME" ] || PROGNAME="assets.make"

    local -r ASSETS_CONF=assets.conf   # This file must exist in the current folder when building packages.
    local -r ARCH=x86_64
    local -r _first_arg="$1"
    local fail=0

    if [[ "$*" =~ "--dump-options" ]] ; then
        local all_options=(
            --allow-downgrade
            --dryrun-local
            --dryrun
            --explain-hook-marks
            --fetch-timeout=
            --pkgnames=
            --pkgdiff
            --repoup
            --no-aur
            --aursrc=
            --aur-delay=
        )
        echo "${all_options[*]}"
        exit 0
    fi

    case "$_first_arg" in
        --dir=*)             # user wants to change to the given folder
            cd "${_first_arg#*=}" || DIE "'cd ${_first_arg#*=}' failed."
            shift
            ;;
    esac

    [ -r $ASSETS_CONF ] || DIE "file '$PWD/$ASSETS_CONF' does not exist."
    [ -L .git ]         || DIE "$PWD/.git must be a symlink to the real .git!"

    local _COMPRESSOR="$(grep "^PKGEXT=" /etc/makepkg.conf | tr -d "'" | sed 's|.*\.pkg\.tar\.||')"
    local REPO_COMPRESSOR="$(AssetsConfLocalVal REPO_COMPRESSOR)"

    test -n "$REPO_COMPRESSOR" || REPO_COMPRESSOR=xz

    if [ -z "$(grep ^PKGEXT /etc/makepkg.conf | grep zst)" ] ; then
        echo2 "/etc/makepkg.conf: please use 'zst' in variable PKGEXT"
        fail=1
    fi
    if [ -z "$(grep ^COMPRESSZST /etc/makepkg.conf | grep T0)" ] ; then
        echo2 "/etc/makepkg.conf: add -T0 -19 into variable COMPRESSZST"
        fail=1
    fi
    test $fail -eq 1 && return

    if false ; then
        local _packager="$(AssetsConfLocalVal _PACKAGER)"
        if [ -n "$_packager" ] ; then
            export PACKAGER="$_packager"
        else
            export PACKAGER="EndeavourOS <info@endeavouros.com>"
        fi
        _packager=""
        echo2 "PACKAGER: $PACKAGER"
    fi

    local -r PACKAGE_NAME=eos-pkgbuild-setup
    [ -x /bin/expac ] && echo2 "VERSION: $(expac %v $PACKAGE_NAME)"

    DebugBreak "before Main2"

    Main2 "$@"
}

DebugBreak_not_used() {
    local from_function="${FUNCNAME[1]}"

    case "$from_function" in
        source) from_function="[PROGRAM]" ;;
    esac

    case "$DEBUG_BREAK" in
        5) echo "Function '$FUNCNAME' <--- line ${BASH_LINENO[0]} function $from_function" ;;
    esac
    :  # this is the break line
}

DebugBreak() { : ; }

Main "$@"
