# Third-party notices

Siftly's Windows client uses open-source components. The exact resolved versions are recorded in `package-lock.json` and `src-tauri/Cargo.lock`.

- Tauri, Wry, Tao and the Tauri dialog plugin: MIT / Apache-2.0.
- React, Vite, Zustand, i18next, TanStack Virtual and Tailwind CSS: MIT.
- Lucide icons: ISC.
- Rawler 0.8: LGPL-2.1. Its license is included in `licenses/`.
- image: MIT / Apache-2.0; kamadak-exif: BSD-2-Clause.
- trash: MIT; windows-rs: MIT / Apache-2.0.
- Other transitive libraries retain the licenses included in their source distributions.

## RAW decoder source and relinking

Rawler is statically linked into the desktop executable. It is available at <https://github.com/dnglab/dnglab/tree/main/rawler> and <https://crates.io/crates/rawler/0.8.0>.

The Windows packaging script produces a matching source archive including Siftly's Windows build inputs and vendored Rust dependencies, including Rawler's source and license. Keep that source archive together with distributed binaries. The desktop crate is built as an ordinary Cargo binary; there is no signing or technical restriction on rebuilding it with a modified decoder.

To rebuild: extract the matching source archive, install the prerequisites in README.md, run `npm ci`, then `npm run tauri -- build --bundles nsis,msi`. Cargo uses the dependencies in `vendor/`. For a modified decoder, copy `vendor/rawler` to a separate directory and add a `[patch.crates-io]` path override for `rawler` in `src-tauri/Cargo.toml`, then rebuild without `--locked` so Cargo can update that local override. The other libraries' source and license files are included under `vendor/` as well.

The source archive's dependency directory is solely for reproducible builds; the Git repository does not check in third-party Rust source.
