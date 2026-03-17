# PathPlanA

PathPlanA is a Flutter planner app for REBUILT autonomous authoring.

It is intended to replace path editing on the operator-board web page. The app authors planner autos locally, then exports a JSON package that the operator board can import and stage to the robot.

## Features

- operator-board-inspired dark UI
- local autos gallery
- field preview/editor surface
- start-pose, step, and waypoint authoring tools
- planner tuning and robot envelope settings
- live route/state preview with per-step requested states
- JSON import/export using the PathPlanA package contract

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

The robot/dashboard side in `season2026` expects the exported package to contain an `autos` array with queue-compatible `startPose`, `steps`, and `routeWaypoints`.

## Integration

- app/contract note: [docs/INTEGRATION.md](docs/INTEGRATION.md)
- robot-side integration note: `season2026/docs/PATHPLANA_INTEGRATION.md`
