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
6. During installation, the validated files are staged under
   `system/vendor/etc`, reproducing v4.2's Magisk vendor-overlay coverage.
7. During early boot, the overlay backing files are refreshed in place and the
   complete validated output directory is bind-mounted over
   `/data/vendor/thermal/config`. After Kitsune establishes its magic mounts, a
   late read-only check verifies every generated file byte-for-byte at
   `/vendor/etc`. This works whether Xiaomi's real writable profile directory
   is empty or already populated.
8. After the overlays are verified, `service.sh` enables Xiaomi's wired and
   wireless driver thermal-removal controls, validates their readback, and
   listens for charging-path events so it can reassert a value if Xiaomi
   resets it.

If generation or early vendor-backing refresh fails, the writable profile
directory is not mounted. The late visible-overlay audit records any mismatch
in `runtime/vendor-overlay.log`. Magisk overlays and bind mounts disappear on
reboot, so disabling or removing the module restores the real files
automatically.

On a phone previously modified by v4.2, the real `/data` files may already
contain v4.2's permanent copies. This redesign never writes another restoration
over them. It generates clean mounted profiles from immutable current sources;
an OS/vendor reset of the writable thermal cache is the safe way to remove that
pre-existing legacy state.

## Charging patch

Only charging-specific sections are considered. A section must have one of the
known schemas:

- `algo_type monitor` with `device battery`
- `algo_type sic` with `device thermal_fcc_override`
- `algo_type monitor` with `device wireless_charge`

The patcher retains v4.2 behavior where appropriate, but replaces its disabled
FCC/SIC controller with an explicit relaxed curve:

- In `monitor`/`battery` sections, the first `trig` and `clr` threshold lists
  are replaced by empty `trig` and `clr` fields.
- In `sic`/`thermal_fcc_override` sections, the stock controller is replaced
  with the following battery-side current curve. Power figures use 4.3 V and
  are approximate; input power and displayed charger power are different.

| Virtual temperature band | Target | FCC range | Approx. battery power |
| --- | --- | --- | --- |
| Below 40 C | Unregulated by this profile | Up to 20.9 A | Up to 90 W |
| 40-41.3 C | 40.5 C | 9.3-13.95 A | 40-60 W |
| 41.3-43.5 C | 42.5 C | 6.98-11.63 A | 30-50 W |
| 43.5-44.5 C | 44 C | 4.65-9.3 A | 20-40 W |
| 44.5-47 C | 45 C | 3.5-8.14 A | 15-35 W |
| 47 C and above | 47 C | 2.33-4.65 A | 10-20 W |

  Each transition clears 0.5 C below its trigger to avoid rapid band changes.
- In `monitor`/`wireless_charge` sections, stock mitigation states are mapped
  to the FCC temperature bands:

| Virtual temperature trigger | Wireless mitigation state |
| --- | --- |
| 40 C | 705 |
| 41.3 C | 1008 |
| 43.5 C | 1413 |
| 44.5 C | 1515 |
| 47 C | 1515 |

  These packed firmware states are not watts. `1515` is the strongest state
  observed in the current stock profiles, so FCC/SIC supplies the additional
  battery-current reduction at 47 C and above.

The temperatures used here come from Xiaomi's composite `VIRTUAL-SENSOR0`, not
necessarily the battery temperature shown by Android. Unknown charging schemas
fail generation instead of being guessed. CPU, GPU, modem, display, and
emergency platform thermal controls are not modified.

Xiaomi's charging firmware also exposes independent wired and wireless thermal
votes outside the encrypted profiles. The module sets wired removal to `1`,
but keeps wireless removal at `0` so the mapped wireless monitor can operate:

```text
/sys/class/qcom-battery/thermal_remove
/sys/class/qcom-battery/wls_thermal_remove
```

Xiaomi can reset these controls when a charging path is detached or
reconfigured. The service blocks on kernel USB/wireless power-supply events;
it has no periodic polling timer and holds no wakelock. On a relevant event it
checks immediately, then after one and three seconds to catch a delayed reset,
and restores wired to `1` and wireless to `0` only when needed. If the module is disabled, the
event handler no longer reapplies the controls. Uninstall stops the listener
and attempts to restore both controls immediately.

`StepChgJeit` is separate from these controls. It is the battery firmware's
temperature-, voltage-, and state-of-charge-dependent FCC/FV safety curve. The
module does not set Xiaomi's distinct `remove_temp_limit` property, so JEITA
recovery limits and emergency charging suspension remain available.

The generated audit files are stored under the module's `runtime` directory:

- `source-manifest.txt`: filename, selected source layer, and source SHA-256
- `source.signature`: cache identity for the complete current source set
- `patch-manifest.txt`: every patched or unchanged file and section
- `generator.log`: generation and mount decisions
- `vendor-overlay.log`: late byte-for-byte verification of `/vendor/etc`
- `charge-controls.log`: driver thermal-removal writes and readback validation

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
   `version=v4.5`, and commit the change.
2. Create and push the matching tag: `git tag v4.5` followed by
   `git push origin v4.5`.

The release workflow builds a minimal Magisk-installable ZIP, verifies its
contents, creates a SHA-256 checksum, and publishes both files in a GitHub
Release with generated release notes. A tag that does not exactly match
`module.prop` is rejected.
