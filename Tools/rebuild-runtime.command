#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
task_root="$PWD"
(cd Licenses/Sources && shasum -a 256 -c SHA256SUMS)
for task_tool in autoconf automake pkg-config make perl clang python3; do
  command -v "$task_tool" >/dev/null || { print -u2 "Missing $task_tool. Install the build dependencies listed in Tools/rebuild-runtime.md."; exit 1; }
done
command -v glibtoolize >/dev/null && export LIBTOOLIZE=glibtoolize
task_pkg_bin=$(command -v pkg-config)
export ACLOCAL_PATH="${task_pkg_bin:h:h}/share/aclocal${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
export MACOSX_DEPLOYMENT_TARGET=13.0
export CFLAGS='-O2 -g0 -mmacosx-version-min=13.0'
export CXXFLAGS="$CFLAGS"
export LDFLAGS='-mmacosx-version-min=13.0'
task_work=$(mktemp -d /private/tmp/FluxaRuntime.XXXXXX)
trap 'rm -rf "$task_work"' EXIT
task_prefix="$task_work/prefix"
task_ssl="${FLUXA_SSL_PREFIX:-$task_work/ssl}"
mkdir -p "$task_prefix" "$task_ssl" "$task_work/openssl"
task_archive="${FLUXA_OPENSSL_ARCHIVE:-$task_work/openssl.tar.gz}"
if [[ ! -f "$task_archive" ]]; then
  curl --fail --location --retry 2 --output "$task_archive" 'https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz'
fi
task_hash=$(shasum -a 256 "$task_archive" | awk '{print $1}')
[[ "$task_hash" == 603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a ]] || { print -u2 'OpenSSL SHA256 mismatch'; exit 1; }
if [[ -z "${FLUXA_SSL_PREFIX:-}" ]]; then
tar -xzf "$task_archive" --strip-components=1 -C "$task_work/openssl"
(
  cd "$task_work/openssl"
  ./Configure darwin64-arm64-cc shared no-tests no-apps --prefix="$task_ssl"
  make -j2
  make install_sw
)
fi
export PKG_CONFIG_PATH="$task_prefix/lib/pkgconfig:$task_ssl/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
for task_spec in 'libplist:2.8.0' 'libimobiledevice-glue:1.3.3' 'libusbmuxd:2.1.1' 'libtatsu:1.0.5' 'libimobiledevice:1.4.0'; do
  task_name="${task_spec%%:*}"; task_version="${task_spec#*:}"
  task_source="$task_work/$task_name"
  mkdir -p "$task_source"
  tar -xzf "$task_root/Licenses/Sources/$task_name-$task_version.tar.gz" --strip-components=1 -C "$task_source"
  (
    cd "$task_source"
    task_arguments=(--prefix="$task_prefix" --disable-static --enable-shared)
    if [[ "$task_name" == libtatsu ]]; then
      export libcurl_CFLAGS="-I$(xcrun --show-sdk-path)/usr/include"
      export libcurl_LIBS='-lcurl'
    fi
    if [[ "$task_name" == libimobiledevice ]]; then
      print -r -- "$task_version" > .tarball-version
      patch -p1 < "$task_root/Licenses/Sources/Fluxa-read-only-handshake.patch"
      task_arguments+=(--without-cython --with-openssl)
    else
      print -r -- "$task_version" > .tarball-version
      [[ "$task_name" == libplist ]] && task_arguments+=(--without-cython)
    fi
    ./autogen.sh "${task_arguments[@]}"
    make -j2
    make install
  )
done
task_output="$task_work/runtime"
mkdir -p "$task_output/lib" "$task_output/bin"
for task_pair in 'libplist-2.0.dylib:libplist.dylib' 'libimobiledevice-glue-1.0.dylib:libimobiledevice-glue.dylib' 'libusbmuxd-2.0.dylib:libusbmuxd.dylib' 'libtatsu.dylib:libtatsu.dylib' 'libimobiledevice-1.0.dylib:libimobiledevice.dylib'; do
  cp -L "$task_prefix/lib/${task_pair%%:*}" "$task_output/lib/${task_pair#*:}"
done
cp "$task_ssl/lib/libssl.3.dylib" "$task_ssl/lib/libcrypto.3.dylib" "$task_output/lib/"
cp "$task_prefix/bin/idevice_id" "$task_output/bin/"
python3 - "$task_output" <<'PY'
import pathlib, subprocess, sys, re
root = pathlib.Path(sys.argv[1])
for path in list((root / 'lib').glob('*.dylib')) + list((root / 'bin').iterdir()):
    dependencies = subprocess.check_output(['/usr/bin/otool', '-L', str(path)], text=True).splitlines()[1:]
    for line in dependencies:
        name = line.strip().split(' (', 1)[0]
        if name.startswith('/private/tmp/Fluxa'):
            basename = pathlib.Path(name).name
            prefixes = {'libplist-2.0': 'libplist.dylib', 'libimobiledevice-glue-1.0': 'libimobiledevice-glue.dylib', 'libusbmuxd-2.0': 'libusbmuxd.dylib', 'libimobiledevice-1.0': 'libimobiledevice.dylib', 'libtatsu': 'libtatsu.dylib'}
            basename = next((value for key, value in prefixes.items() if basename.startswith(key)), basename)
            subprocess.run(['/usr/bin/install_name_tool', '-change', name, '@executable_path/../lib/' + basename, str(path)], check=True)
    if path.suffix == '.dylib':
        subprocess.run(['/usr/bin/install_name_tool', '-id', '@executable_path/../lib/' + path.name, str(path)], check=True)
    metadata = subprocess.check_output(['/usr/bin/vtool', '-show-build', str(path)], text=True)
    if not re.search(r'\bminos 13\.0\b', metadata):
        raise SystemExit('Incorrect deployment target: ' + path.name)
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(path)], check=True)
PY
mkdir -p "$task_root/Resources/libimobiledevice/lib" "$task_root/Resources/libimobiledevice/bin"
mv "$task_root/Resources/libimobiledevice/lib" "$task_work/previous-libraries"
mv "$task_output/lib" "$task_root/Resources/libimobiledevice/lib"
cp "$task_output/bin/idevice_id" "$task_root/Resources/libimobiledevice/bin/"
print 'Rebuilt runtime for Apple silicon / macOS 13.0. Only idevice_id and shared libraries are copied.'
