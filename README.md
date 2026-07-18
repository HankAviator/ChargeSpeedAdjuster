# ChargeSpeedAdjuster

ChargeSpeedAdjuster generates relaxed Xiaomi charging thermal profiles from
the files supplied by the currently installed OS. It does not keep stock
backups and does not copy generated files into Xiaomi's real configuration
directory.

## Boot design

1. Magisk runs `post-fs-data.sh` after `/data` is available.
2. `edit.sh` mounts the immutable vendor, ODM, and root block devices read-only,
   bypassing all active Magisk overlays.
3. For every live profile in `/data/vendor/thermal/config`, the generator picks
   the same-named immutable source (ODM, then vendor, then system). A genuinely
   data-only profile is used only when no immutable source exists.
4. The source manifest, build identity, converter, and patcher are hashed.
5. Changed sources are decrypted, schema-validated, patched, encrypted, and
   decrypted again to prove an exact crypto round trip.
6. Validated encrypted outputs are bind-mounted over the existing `/data`
   profile files before Xiaomi starts `mi_thermald` on the Android `boot`
   trigger.

If generation or validation fails, no generated profiles are mounted. The OS
therefore uses its current files unchanged. Bind mounts disappear on reboot,
so disabling or removing the module restores the real files automatically.

On a phone previously modified by v4.2, those real `/data` files may already
contain v4.2's permanent copies. This redesign never writes another restoration
over them. It generates clean mounted profiles from immutable current sources;
an OS/vendor reset of the writable thermal cache is the safe way to remove that
pre-existing legacy state.

## Charging patch

Only sections whose header ends in `-BAT]` are considered. A section must have
one of the known schemas:

- `algo_type monitor` with `device battery`
- `algo_type sic` with `device thermal_fcc_override`

The first `trig` and `clr` threshold lists in a validated section are replaced
with their field names without values. Other fields—including `proportion`,
`target`, `ks`, `ki`, and `kc`—are preserved.

The generated audit files are stored under the module's `runtime` directory:

- `source-manifest.txt`: filename, selected source layer, and source SHA-256
- `source.signature`: cache identity for the complete current source set
- `patch-manifest.txt`: every patched or unchanged file and section
- `generator.log`: generation and mount decisions

The legacy `thermal-bat` binary is not used and is removed from the installed
module during installation.

## Converter

The Xiaomi AES-CBC converter is source-controlled in `tools/miui-thermal`.
Build the Android ARM64 binary with:

```sh
cd tools/miui-thermal
GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
  go build -trimpath -buildvcs=false -ldflags='-s -w' -o ../../miui-thermal .
```

The converter uses the Xiaomi-compatible key and IV `thermalopenssl.h`, strict
PKCS#7 padding validation, atomic output writes, and mode `0755` for newly
created directories.

## Publishing a release

1. Replace the development version in `module.prop` with the intended release
   tag, for example `version=v4.3`, and commit the change.
2. Create and push the matching tag: `git tag v4.3` followed by
   `git push origin v4.3`.

The release workflow builds a minimal Magisk-installable ZIP, verifies its
contents, creates a SHA-256 checksum, and publishes both files in a GitHub
Release with generated release notes. A tag that does not exactly match
`module.prop` is rejected.
