# BahariHost CSF Changelog

## 1.2.9 - 2026-06-17

- Added explicit repair for existing plain Linux installs with cPanel Perl shebangs.
- Added setup version output to confirm servers are running the latest Linux installer.

## 1.2.8 - 2026-06-17

- Fixed plain Linux installer shebangs so CSF/lfd use the system Perl instead of cPanel Perl.
- Added broken install detection and repair for previous plain Linux installs.

## 1.2.7 - 2026-06-17

- Changed plain Linux installer to use the GitHub repository archive instead of `download.configserver.com`.

## 1.2.6 - 2026-06-17

- Added `setup-linux.sh` for plain Linux servers without cPanel/WHM.

## 1.2.5 - 2026-06-17

- Added setup preflight replacement for existing non-BIT/non-BahariHost CSF installs before applying the hardened build.

## 1.2.4 - 2026-06-17

- Hardened dashboard command execution so missing server tools report cleanly instead of causing a WHM 500 page.

## 1.2.3 - 2026-06-17

- Added cPHulk and Imunify360 baseline buttons to the CSF dashboard.
- Added standalone bash scripts for applying cPHulk and Imunify360 recommended baselines.

## 1.2.2 - 2026-06-17

- Renamed dashboard labels from BahariHost to BIT for the build/control header.

## 1.2.1 - 2026-06-17

- Clarified dashboard block counts by separating active CSF blocks from recent lfd log activity.
- Added recent attack IP/event counts to the dashboard.

## 1.2.0 - 2026-06-17

- Added WHM changelog page.
- Added release discipline: every future change should update `BAHARI_VERSION` and this changelog.

## 1.1.0 - 2026-06-17

- Added BahariHost update management in WHM.
- Added `BAHARI_VERSION` tracking and setup installer version stamping.

## 1.0.0 - 2026-06-17

- Initial BahariHost CSF custom layer.
- Added WHM rescue tools, DDoS controls, safe admin IP tools, dashboard styling, config search, attack dashboard filtering, setup installer, and BahariHost branding.
