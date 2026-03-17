# PathPlanA

PathPlanA is a Flutter planner app for REBUILT autonomous authoring.

It is intended to replace path editing on the operator-board web page. The app authors planner autos locally, then exports either:

- a JSON package for interchange/debugging
- a deploy library for `season2026/src/main/deploy/pathplana/autos`

## Features

- operator-board-inspired dark UI
- local autos gallery
- field preview/editor surface
- start-pose, step, and waypoint authoring tools
- planner tuning and robot envelope settings
- live route/state preview with per-step requested states
- JSON import/export using the PathPlanA package contract
- desktop deploy export that writes `index.json` plus one folder per auto

## Run

```bash
cd tools/pathplana_app
flutter pub get
flutter run -d chrome
```

For macOS:

```bash
cd tools/pathplana_app
flutter run -d macos
```

## Export contract

The app ships the contract schema at:

- `assets/contracts/pathplana_autos.schema.json`
- `vendor/PathPlanA.json`

The robot/dashboard side in `season2026` expects either:

- a package JSON with an `autos` array
- or the deploy library layout:
  - `pathplana/autos/index.json`
  - `pathplana/autos/<auto-id>/auto.json`

Use `Export Deploy` on desktop builds to write the deploy library directly.

## Integration

- app/contract note: [docs/INTEGRATION.md](docs/INTEGRATION.md)
- robot-side integration note: `season2026/docs/PATHPLANA_INTEGRATION.md`
