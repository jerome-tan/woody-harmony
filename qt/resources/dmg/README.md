# DMG installation artwork

`background.png` and `background@2x.png` are checked-in 640 × 400 point
artwork for normal and Retina displays. Builds use these assets directly;
Swift is only needed when editing/regenerating the artwork:

```sh
swift qt/resources/dmg/render-background.swift qt/resources/dmg
```

The matching Finder layout is `qt/scripts/dmg-settings.py`: Woody on the left,
Applications on the right, 96-point icons, a 640 × 432 point outer window with
400 points of content. Keep the icon/card centres aligned when changing either.

`dmgbuild` combines both densities into a hidden TIFF and writes Finder metadata
without launching or controlling Finder. The build-only dependencies and their
wheel hashes are pinned in `qt/scripts/dmg-requirements.txt`; they are installed
in `dist/dmg-tools` and are not included in the Woody application or portable ZIP.

The completed DMG is checksum-verified, mounted read-only, and its included app
is checked with `codesign --verify --deep --strict` before replacing the previous
installer. Do not set `hide_extensions` or FinderInfo on the signed `.app`:
those extra attributes cause strict signature verification to fail.

To rebuild just the installer from an existing deployed/signed application:

```sh
python3 qt/scripts/dmg.py --app dist/qt-package/staging/Woody.app \
  --output /tmp/Woody-preview.dmg
```

Use `build.py` or `package.py` for normal builds so `package-sizes.json` is also
updated. When inspecting a rebuilt image, eject the previous mounted image
before reopening it; Finder may still be showing the old mount.
