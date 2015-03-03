{ stdenv, fetchurl, mono }:

stdenv.mkDerivation rec {
  name = "nuget-${version}";
  version = "2.8.2";

  src = fetchurl {
    url = "https://az320820.vo.msecnd.net/downloads/nuget.exe";
    sha256 = "0hvlb0kva1ii9ij4lfqpck8ra1w0s4sakfjngk3nxp2rhsy6v1xh";
  };

  inherit mono;

  builder = ./builder.sh;

  buildInputs = [ mono ];

  meta = {
    description = "NuGet package manager";
    license = stdenv.lib.licenses.asl20;
  };
}