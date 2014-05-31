with import <nix/config.nix>;
let
  builder = builtins.toFile "unpack-github-tarball.sh" ''
    mkdir -p $out/$channelName/nixpkgs
    ${gzip} -d <$src | ${tar} -xf - -C $out/$channelName/nixpkgs --strip-components=1
    echo -n "$uri" >$out/$channelName/nixpkgs/.git-uri
    echo -n "$refid" >$out/$channelName/nixpkgs/.git-revision
    echo -n ".$refid" >$out/$channelName/nixpkgs/.version-suffix
    if [ -n "$binaryCacheURL" ]; then
      mkdir $out/binary-caches
      echo -n "$binaryCacheURL" > $out/binary-caches/$channelName
    fi
  '';
in
{ uri, refid, channelName, src, binaryCacheURL ? "" }:
derivation {
  name = channelName;
  system = builtins.currentSystem;
  builder = shell;
  args = [ "-e" builder ];
  inherit uri refid channelName src binaryCacheURL;
  PATH = "${nixBinDir}:${coreutils}";
  preferLocalBuild = true;
  __noChroot = true;
}
