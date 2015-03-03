{ stdenv, fetchgit, mono }:

stdenv.mkDerivation rec {
  name = "omnisharp-server-git";
  src = fetchgit {
    url = git://github.com/OmniSharp/omnisharp-server.git;
    rev = "6716511fb643671a1d2c0ccbfe0933e23c7a532a";
    sha256 = "75a91c875e33ef2a01224d67a4be7c85ea65f9125af20ce4b39f50403b768b61";
  };

  inherit mono;
  buildInputs = [mono];

  #preBuild = ''
  #  git submodule update --init --recursive
  #'';

  dontStrip = true;

  prePatch = ''
    sed -i -e 's;//Unix Paths;//Unix Paths\n            @"'"$mono/lib/mono/4.5"'",;' \
      ./OmniSharp/Solution/AssemblySearch.cs
  '';

  buildPhase = ''
    xbuild
  '';

  installPhase = ''
    mkdir -p "$out/bin"
    cp -R ./OmniSharp/bin/Debug "$out/lib"
    cat >"$out/bin/omnisharp" <<EOF
    #!/bin/sh
    script=\$(readlink -f "\$0")
    path=\$(dirname "\$script")
    exec "$mono/bin/mono" "\$path/../lib/OmniSharp.exe" "\$@"
    EOF
    chmod 755 "$out/bin/omnisharp"
  '';

  meta = {
    homepage = http://github.com/OmniSharp/omnisharp-server;
    description = "HTTP wrapper around NRefactory.";
    platforms = with stdenv.lib.platforms; linux;
    license = stdenv.lib.licenses.mit;
  };
}
