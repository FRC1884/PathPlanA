# PathPlanA Integration

`PathPlanA` authors REBUILT autos locally and exports them either as a JSON package or as a deploy-backed auto library.

## Workflow

1. Create autos in the Flutter app.
2. Use `Export Deploy` to write:
   - `index.json`
   - one folder per auto containing `auto.json`
3. Place that library under `Season2026/src/main/deploy/pathplana/autos/`.
4. Preview/select the deployed auto on the Season2026 operator board auto tab.
5. The dashboard publishes only the selected auto id.
6. The robot loads the selected deploy auto and executes it through `RebuiltAutoQueue` and `AutoAlignToPoseCommand`.

## Robot execution model

The robot does not run a separate spline follower here. It stays on the existing objective-based path:

- the exported start pose resets the queue start pose
- `routeWaypoints` become intermediate auto-align poses
- each step still uses live robot pose
- vision correction is still driven by the robot pose-estimation stack

This keeps the planner compatible with the existing auto-align and vision correction flow instead of replacing it.

## Contract files

- export schema: `assets/contracts/pathplana_autos.schema.json`
- vendordep metadata: `vendor/PathPlanA.json`

## Deploy library layout

- `index.json`
  - manifest with `id`, `name`, `folder`, `relativePath`, and `updatedAt`
- `<auto-id>/auto.json`
  - full per-auto spec with `startPose`, `customZones`, and `steps`

## Vendordep note

The vendordep is metadata-only right now. It exists so the planner ecosystem has a stable shared identifier and URL, not because the Flutter app ships Java/JNI robot code.
