#! @shell@

if [ -x "@shell@" ]; then export SHELL="@shell@"; fi;

set -e

showSyntax() {
    exec man nixos-rebuild
    exit 1
}


# Parse the command line.
origArgs=("$@")
extraBuildFlags=()
action=
buildNix=1
rollback=
upgrade=
repair=
profile=/nix/var/nix/profiles/system

while [ "$#" -gt 0 ]; do
    i="$1"; shift 1
    case "$i" in
      --help)
        showSyntax
        ;;
      switch|boot|test|build|dry-run|build-vm|build-vm-with-bootloader)
        action="$i"
        ;;
      --install-grub)
        export NIXOS_INSTALL_GRUB=1
        ;;
      --no-build-nix)
        buildNix=
        ;;
      --rollback)
        rollback=1
        ;;
      --upgrade)
        upgrade=1
        ;;
      --repair)
        repair=1
        extraBuildFlags+=("$i")
        ;;
      --show-trace|--no-build-hook|--keep-failed|-K|--keep-going|-k|--verbose|-v|-vv|-vvv|-vvvv|-vvvvv|--fallback|--repair|--no-build-output|-Q)
        extraBuildFlags+=("$i")
        ;;
      --max-jobs|-j|--cores|-I)
        j="$1"; shift 1
        extraBuildFlags+=("$i" "$j")
        ;;
      --option)
        j="$1"; shift 1
        k="$1"; shift 1
        extraBuildFlags+=("$i" "$j" "$k")
        ;;
      --fast)
        buildNix=
        extraBuildFlags+=(--show-trace)
        ;;
      --profile-name|-p)
        if [ -z "$1" ]; then
            echo "$0: ‘--profile-name’ requires an argument"
            exit 1
        fi
        if [ "$1" != system ]; then
            profile="/nix/var/nix/profiles/system-profiles/$1"
            mkdir -p -m 0755 "$(dirname "$profile")"
        fi
        shift 1
        ;;
      *)
        echo "$0: unknown option \`$i'"
        exit 1
        ;;
    esac
done

if [ -z "$action" ]; then showSyntax; fi

repeatable=
repo=
refid=
if [ "$(nix-instantiate --eval -A config.system.repeatableBuild.enable '<nixpkgs/nixos>' 2>/dev/null)" = 'true' ]; then
  echo "$0: using repeatable build" >&2
  repeatable=true
fi


# Validate arguments
if [ -n "$repeatable" -a -n "$upgrade" ]; then
  echo "$0: cannot have --update with repeatable configuration" >&2
  exit 1
fi


# Only run shell scripts from the Nixpkgs tree if the action is
# "switch", "boot", or "test". With other actions (such as "build"),
# the user may reasonably expect that no code from the Nixpkgs tree is
# executed, so it's safe to run nixos-rebuild against a potentially
# untrusted tree.
canRun=
if [ "$action" = switch -o "$action" = boot -o "$action" = test ]; then
    canRun=1
fi


# If ‘--upgrade’ is given, run ‘nix-channel --update nixos’.
if [ -n "$upgrade" -a -z "$_NIXOS_REBUILD_REEXEC" ]; then
    nix-channel --update nixos
fi

# If configuration is repeatable, fetch the correct nixpkgs revision.
if [ -n "$repeatable" -a -z "$_NIXOS_REBUILD_REEXEC" ]; then
  echo "$0: fetching for repeatable build" >&2
  repo_=$(nix-instantiate --eval -A config.system.repeatableBuild.uri '<nixpkgs/nixos>' 2>/dev/null || echo "")
  refid_=$(nix-instantiate --eval -A config.system.repeatableBuild.refid '<nixpkgs/nixos>' 2>/dev/null || echo "")
  binaryCacheUrl_=$(nix-instantiate --eval -A config.system.repeatableBuild.binaryCache '<nixpkgs/nixos>' 2>/dev/null || echo "")
  repo=${repo_:1:-1}
  refid=${refid_:1:-1}
  binaryCacheUrl=${binaryCacheUrl_:1:-1}
  user_profile="/nix/var/nix/profiles/per-user/$USER/channels"
  if [ -z "$repo" -o -z "$refid" ]; then
    echo "$0: system.repeatableBuild without uri or refid" >&2
    exit 1
  fi
  if [[ -e "$user_profile/nixos/nixpkgs/.git-revision" \
    && "$(<"$user_profile/nixos/nixpkgs/.git-revision")" = "$refid" \
    && -e "$user_profile/nixos/nixpkgs/.git-uri" \
    && "$(<"$user_profile/nixos/nixpkgs/.git-uri")" = "$repo" ]]; then
    echo "$0: this revision already downloaded"
  else
    if [[ "$repo" =~ ^[^/]+/[^/]+$ ]]; then # Fetch from github
      github_tarball_url="https://codeload.github.com/$repo/tar.gz/$refid"
      echo "$0: fetching $github_tarball_url" >&2
      github_tarball_info=($(PRINT_PATH=1 QUIET=1 nix-prefetch-url "$github_tarball_url"))
      github_tarball_hash=${github_tarball_info[0]}
      github_tarball_path=${github_tarball_info[1]}
      # Unpack into nix store
      echo "$0: unpacking into $user_profile" >&2
      nix-env --profile "$user_profile" \
        -f '<nixpkgs/nixos/modules/installer/tools/unpack-nixpkgs-tarball.nix>' \
        -i \
        --quiet \
        -E "f: f { uri = \"$repo\"; refid = \"$refid\"; channelName = \"nixos\"; src = builtins.storePath \"$github_tarball_path\"; binaryCacheURL = \"$binaryCacheUrl\"; }"
    elif [[ "$repo" == ssh:*
      || "$repo" == git:* ]]; then # Fetch from remote git
      echo "$0: fetching git archive from remote $repo @ $refid" >&2
      tmpdir=$(mktemp -d)
      git archive \
        --format=tar \
        --remote="$repo" \
        --prefix="nixpkgs/" \
        "$rev" \
        >"$tmpdir/nixos-$refid.tar.gz"
      git_tarball_path=$(nix-store --add "$tmpdir/nixos-$refid.tar.gz")
      rm -rf "$tmpdir"
      nix-env --profile "$user_profile" \
        -f '<nixpkgs/nixos/modules/installer/tools/unpack-nixpkgs-tarball.nix>' \
        -i \
        --quiet \
        -E "f: f { uri = \"$repo\"; refid = \"$refid\"; channelName = \"nixos\"; src = builtins.storePath \"$git_tarball_path\"; binaryCacheURL = \"$binaryCacheUrl\"; }"
    else # Fetch from local repo
      echo "$0: fetching git archive from local $repo @ $refid" >&2
      tmpdir=$(mktemp -d)
      $(cd "$repo"
        git archive \
          --format=tar \
          --prefix="nixpkgs/" \
          "$refid" \
          | gzip >"$tmpdir/nixos-$refid.tar.gz")
      git_tarball_path=$(nix-store --add "$tmpdir/nixos-$refid.tar.gz")
      rm -rf "$tmpdir"
      nix-env --profile "$user_profile" \
        -f '<nixpkgs/nixos/modules/installer/tools/unpack-nixpkgs-tarball.nix>' \
        -i \
        --quiet \
        -E "f: f { uri = \"$repo\"; refid = \"$refid\"; channelName = \"nixos\"; src = builtins.storePath \"$git_tarball_path\"; binaryCacheURL = \"$binaryCacheUrl\"; }"
    fi
  fi
fi

# Re-execute nixos-rebuild from the Nixpkgs tree.
if [ -z "$_NIXOS_REBUILD_REEXEC" -a -n "$canRun" ]; then
    if p=$(nix-instantiate --find-file nixpkgs/nixos/modules/installer/tools/nixos-rebuild.sh "${extraBuildFlags[@]}"); then
        export _NIXOS_REBUILD_REEXEC=1
        exec $SHELL -e $p "${origArgs[@]}"
        exit 1
    fi
fi


tmpDir=$(mktemp -t -d nixos-rebuild.XXXXXX)
trap 'rm -rf "$tmpDir"' EXIT


# If the Nix daemon is running, then use it.  This allows us to use
# the latest Nix from Nixpkgs (below) for expression evaluation, while
# still using the old Nix (via the daemon) for actual store access.
# This matters if the new Nix in Nixpkgs has a schema change.  It
# would upgrade the schema, which should only happen once we actually
# switch to the new configuration.
# If --repair is given, don't try to use the Nix daemon, because the
# flag can only be used directly.
if [ -z "$repair" ] && systemctl show nix-daemon.socket nix-daemon.service | grep -q ActiveState=active; then
    export NIX_REMOTE=${NIX_REMOTE:-daemon}
fi


# First build Nix, since NixOS may require a newer version than the
# current one.
if [ -n "$rollback" -o "$action" = dry-run ]; then
    buildNix=
fi

if [ -n "$buildNix" ]; then
    echo "building Nix..." >&2
    if ! nix-build '<nixpkgs/nixos>' -A config.nix.package -o $tmpDir/nix "${extraBuildFlags[@]}" > /dev/null; then
        if ! nix-build '<nixpkgs/nixos>' -A nixFallback -o $tmpDir/nix "${extraBuildFlags[@]}" > /dev/null; then
            if ! nix-build '<nixpkgs>' -A nix -o $tmpDir/nix "${extraBuildFlags[@]}" > /dev/null; then
                machine="$(uname -m)"
                if [ "$machine" = x86_64 ]; then
                    nixStorePath=/nix/store/d34q3q2zj9nriq4ifhn3dnnngqvinjb3-nix-1.7
                elif [[ "$machine" =~ i.86 ]]; then
                    nixStorePath=/nix/store/qlah0darpcn6sf3lr2226rl04l1gn4xz-nix-1.7
                else
                    echo "$0: unsupported platform"
                    exit 1
                fi
                if ! nix-store -r $nixStorePath --add-root $tmpDir/nix --indirect \
                    --option extra-binary-caches http://cache.nixos.org/; then
                    echo "warning: don't know how to get latest Nix" >&2
                fi
                # Older version of nix-store -r don't support --add-root.
                [ -e $tmpDir/nix ] || ln -sf $nixStorePath $tmpDir/nix
            fi
        fi
    fi
    PATH=$tmpDir/nix/bin:$PATH
fi


# Update the version suffix if we're building from Git (so that
# nixos-version shows something useful).
if [ -n "$canRun" ]; then
    if nixpkgs=$(nix-instantiate --find-file nixpkgs "${extraBuildFlags[@]}"); then
        suffix=$($SHELL $nixpkgs/nixos/modules/installer/tools/get-version-suffix "${extraBuildFlags[@]}" || true)
        if [ -n "$suffix" ]; then
            echo -n "$suffix" > "$nixpkgs/.version-suffix" || true
        fi
    fi
fi


if [ "$action" = dry-run ]; then
    extraBuildFlags+=(--dry-run)
fi


# Either upgrade the configuration in the system profile (for "switch"
# or "boot"), or just build it and create a symlink "result" in the
# current directory (for "build" and "test").
if [ -z "$rollback" ]; then
    echo "building the system configuration..." >&2
    if [ "$action" = switch -o "$action" = boot ]; then
        nix-env "${extraBuildFlags[@]}" -p "$profile" -f '<nixpkgs/nixos>' --set -A system
        pathToConfig="$profile"
    elif [ "$action" = test -o "$action" = build -o "$action" = dry-run ]; then
        nix-build '<nixpkgs/nixos>' -A system -K -k "${extraBuildFlags[@]}" > /dev/null
        pathToConfig=./result
    elif [ "$action" = build-vm ]; then
        nix-build '<nixpkgs/nixos>' -A vm -K -k "${extraBuildFlags[@]}" > /dev/null
        pathToConfig=./result
    elif [ "$action" = build-vm-with-bootloader ]; then
        nix-build '<nixpkgs/nixos>' -A vmWithBootLoader -K -k "${extraBuildFlags[@]}" > /dev/null
        pathToConfig=./result
    else
        showSyntax
    fi
else # [ -n "$rollback" ]
    if [ "$action" = switch -o "$action" = boot ]; then
        nix-env --rollback -p "$profile"
        pathToConfig="$profile"
    elif [ "$action" = test -o "$action" = build ]; then
        systemNumber=$(
            nix-env -p "$profile" --list-generations |
            sed -n '/current/ {g; p;}; s/ *\([0-9]*\).*/\1/; h'
        )
        ln -sT "$profile"-${systemNumber}-link ./result
        pathToConfig=./result
    else
        showSyntax
    fi
fi


# If we're not just building, then make the new configuration the boot
# default and/or activate it now.
if [ "$action" = switch -o "$action" = boot -o "$action" = test ]; then
    $pathToConfig/bin/switch-to-configuration "$action"
fi


if [ "$action" = build-vm ]; then
    cat >&2 <<EOF

Done.  The virtual machine can be started by running $(echo $pathToConfig/bin/run-*-vm).
EOF
fi
