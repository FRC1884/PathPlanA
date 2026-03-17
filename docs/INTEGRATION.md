# PathPlanA Integration

`PathPlanA` authors REBUILT autos locally and exports them as a JSON package.

## Workflow

1. Create autos in the Flutter app.
2. Export `pathplana_autos.json`.
3. Import that package into the Season2026 operator board auto tab.
4. Preview/select the imported auto on the dashboard.
5. Stage the selected auto to the robot queue.
6. Execute on the robot through `RebuiltAutoQueue` and `AutoAlignToPoseCommand`.

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

## Vendordep note

The vendordep is metadata-only right now. It exists so the planner ecosystem has a stable shared identifier and URL, not because the Flutter app ships Java/JNI robot code.
