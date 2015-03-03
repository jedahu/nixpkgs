source "$stdenv/setup"

# "${mono}/bin/mozroots" --import --sync
mkdir -p "$out/lib"
mkdir -p "$out/bin"
cp "$src" "$out/lib/nuget.exe"
cp "${mono}/lib/mono/4.0/Microsoft.Build.dll" "$out/lib"

cat >"$out/bin/nuget" <<EOF
  #!/usr/bin/env bash
  DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
  exec "${mono}/bin/mono" --runtime=v4.0.30319 --gc=sgen "\$DIR/../lib/nuget.exe" "\$@"
EOF

chmod 755 "$out/bin/nuget"
