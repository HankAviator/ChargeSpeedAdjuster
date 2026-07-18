# ChargeSpeedAdjuster

ChargeSpeedAdjuster generates relaxed Xiaomi charging thermal profiles from
the files supplied by the currently installed OS. It does not keep stock
backups and does not copy generated files into Xiaomi's real configuration
directory.

## Boot design

1. Magisk runs `post-fs-data.sh` after `/data` is available.
2. `edit.sh` mounts the immutable vendor, ODM, and root block devices read-only,
   bypassing all active Magisk overlays.
3. The generator inventories current immutable `thermal-*.conf` sources using
   ODM, vendor, then system precedence. AES block candidates must pass strict
   decryption and exact re-encryption; adjacent plaintext control files remain
   untouched.
4. The source manifest, build identity, converter, and patcher are hashed.
5. Changed sources are decrypted, schema-validated, patched, encrypted, and
   decrypted again to prove an exact crypto round trip.
6. The complete validated output directory is bind-mounted over
   `/data/vendor/thermal/config` before Xiaomi starts `mi_thermald` on the
   Android `boot` trigger. This works whether Xiaomi's real directory is empty
   or already populated.

If generation or validation fails, no generated profiles are mounted. The OS
therefore uses its current files unchanged. Bind mounts disappear on reboot,
so disabling or removing the module restores the real files automatically.

On a phone previously modified by v4.2, the real `/data` files may already
contain v4.2's permanent copies. This redesign never writes another restoration
over them. It generates clean mounted profiles from immutable current sources;
an OS/vendor reset of the writable thermal cache is the safe way to remove that
pre-existing legacy state.

## Charging patch

Only sections whose header ends in `-BAT]` are considered. A section must have
one of the known schemas:

- `algo_type monitor` with `device battery`
- `algo_type sic` with `device thermal_fcc_override`

The patcher deliberately reproduces the output of the v4.2 `thermal-bat`
binary rather than only approximating its apparent intent:

- In `monitor`/`battery` sections, the first `trig` and `clr` threshold lists
  are replaced by empty `trig` and `clr` fields.
- In `sic`/`thermal_fcc_override` sections, the `proportion` line becomes an
  empty `trig` field, the original `trig` line becomes an empty `clr` field,
  and the original populated `clr` line remains. Other fields are preserved.

The second transformation is intentionally unusual. It matches v4.2
byte-for-byte on the current stock profile corpus and may cause Xiaomi's
thermal parser to ignore or ineffectively initialize that SIC controller.
Unknown BAT schemas fail generation instead of being guessed.

The generated audit files are stored under the module's `runtime` directory:

- `source-manifest.txt`: filename, selected source layer, and source SHA-256
- `source.signature`: cache identity for the complete current source set
- `patch-manifest.txt`: every patched or unchanged file and section
- `generator.log`: generation and mount decisions

The legacy `thermal-bat` binary is used only as a development reference. It is
not run by the module and is removed from the installed module during
installation.

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

1. Set `version=` in `module.prop` to the intended release tag, for example
   `version=v4.4`, and commit the change.
2. Create and push the matching tag: `git tag v4.4` followed by
   `git push origin v4.4`.

The release workflow builds a minimal Magisk-installable ZIP, verifies its
contents, creates a SHA-256 checksum, and publishes both files in a GitHub
Release with generated release notes. A tag that does not exactly match
`module.prop` is rejected.
