import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'deploy_export_api.dart';
import 'deploy_export_stub.dart'
    if (dart.library.io) 'deploy_export_io.dart' as deploy_export;

const double fieldLengthMeters = 16.54048;
const double fieldWidthMeters = 8.06958;
const double robotSideInches = 27.5;
const double defaultRobotSizeMeters = robotSideInches * 0.0254;
const String plannerIconAsset = 'assets/branding/pathplana_icon.svg';
const String fieldBackgroundAsset = 'assets/field/pathplanner_field26.png';
const Size fieldBackgroundImageSize = Size(3508, 1814);
const EdgeInsets fieldBackgroundInsets = EdgeInsets.fromLTRB(59, 89, 60, 90);
const String _workspacePrefsKey = 'pathplana.workspace';
const String _selectedAutoPrefsKey = 'pathplana.selectedAutoIndex';
const String _deployDirectoryPrefsKey = 'pathplana.deployDirectory';

Rect resolveFieldImageRect(Size canvasSize) {
  final FittedSizes fitted = applyBoxFit(
    BoxFit.contain,
    fieldBackgroundImageSize,
    canvasSize,
  );
  return Alignment.center.inscribe(
    fitted.destination,
    Offset.zero & canvasSize,
  );
}

Rect resolvePlayableFieldRect(Size canvasSize) {
  final Rect imageRect = resolveFieldImageRect(canvasSize);
  final double scaleX = imageRect.width / fieldBackgroundImageSize.width;
  final double scaleY = imageRect.height / fieldBackgroundImageSize.height;
  return Rect.fromLTRB(
    imageRect.left + (fieldBackgroundInsets.left * scaleX),
    imageRect.top + (fieldBackgroundInsets.top * scaleY),
    imageRect.right - (fieldBackgroundInsets.right * scaleX),
    imageRect.bottom - (fieldBackgroundInsets.bottom * scaleY),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PathPlanAApp());
}

class PathPlanAApp extends StatelessWidget {
  const PathPlanAApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0E14);
    const panel = Color(0xFF11161F);
    const line = Color(0xFF273246);
    const text = Color(0xFFE8EEFC);
    const muted = Color(0xFF94A0B8);
    const accent = Color(0xFFFFD166);

    return MaterialApp(
      title: 'PathPlanA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: Color(0xFF39D98A),
          surface: panel,
          onSurface: text,
        ),
        textTheme: Typography.whiteMountainView.apply(
          bodyColor: text,
          displayColor: text,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: text,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          color: panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: line),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF151C28),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: accent),
          ),
          labelStyle: const TextStyle(color: muted),
        ),
      ),
      home: const PlannerHomePage(),
    );
  }
}

enum PlannerTool { select, startPose, addStep, addWaypoint }

enum PlannerSection {
  library,
  editor,
  events,
  obstacles,
  commands,
  settings,
}

enum RequestedState {
  idling('IDLING', Color(0xFFE8EEFC)),
  intaking('INTAKING', Color(0xFF39D98A)),
  shooting('SHOOTING', Color(0xFFFFD166)),
  shootIntake('SHOOT_INTAKE', Color(0xFFFF8C69)),
  ferrying('FERRYING', Color(0xFF90CDF4)),
  testing('TESTING', Color(0xFFF78FB3));

  const RequestedState(this.token, this.color);
  final String token;
  final Color color;

  static RequestedState fromToken(String value) {
    return RequestedState.values.firstWhere(
      (state) => state.token == value,
      orElse: () => RequestedState.idling,
    );
  }
}

class PlannerCommandProfile {
  const PlannerCommandProfile({
    required this.id,
    required this.name,
    required this.requestedState,
    required this.colorHex,
    this.description = '',
  });

  final String id;
  final String name;
  final String requestedState;
  final String colorHex;
  final String description;

  Color get color =>
      parseHexColor(colorHex) ?? requestedStateColor(requestedState);

  PlannerCommandProfile copyWith({
    String? id,
    String? name,
    String? requestedState,
    String? colorHex,
    String? description,
  }) {
    return PlannerCommandProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      requestedState: requestedState ?? this.requestedState,
      colorHex: colorHex ?? this.colorHex,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'requestedState': requestedState,
    'colorHex': colorHex,
    'description': description,
  };

  static PlannerCommandProfile fromJson(Map<String, dynamic> json) {
    return PlannerCommandProfile(
      id: json['id'] as String? ?? 'command',
      name: json['name'] as String? ?? 'Command',
      requestedState: json['requestedState'] as String? ?? 'IDLING',
      colorHex: json['colorHex'] as String? ?? '#E8EEFC',
      description: json['description'] as String? ?? '',
    );
  }
}

Color requestedStateColor(String stateToken) {
  return RequestedState.fromToken(stateToken).color;
}

Color? parseHexColor(String value) {
  final String trimmed = value.trim().replaceFirst('#', '');
  if (trimmed.length != 6 && trimmed.length != 8) {
    return null;
  }
  final String normalized = trimmed.length == 6 ? 'FF$trimmed' : trimmed;
  final int? parsed = int.tryParse(normalized, radix: 16);
  return parsed == null ? null : Color(parsed);
}

String colorToHex(Color color) {
  return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}

List<PlannerCommandProfile> defaultCommandProfiles() {
  return <PlannerCommandProfile>[
    PlannerCommandProfile(
      id: 'cmd-idle',
      name: 'Hold Idle',
      requestedState: 'IDLING',
      colorHex: '#E8EEFC',
      description: 'Keep the superstructure parked.',
    ),
    PlannerCommandProfile(
      id: 'cmd-intake',
      name: 'Rear Intake',
      requestedState: 'INTAKING',
      colorHex: '#39D98A',
      description: 'Drive in with the intake on the back.',
    ),
    PlannerCommandProfile(
      id: 'cmd-score',
      name: 'Shoot Cycle',
      requestedState: 'SHOOTING',
      colorHex: '#FFD166',
      description: 'Prepare to score at the target.',
    ),
    PlannerCommandProfile(
      id: 'cmd-ferry',
      name: 'Ferry Move',
      requestedState: 'FERRYING',
      colorHex: '#90CDF4',
      description: 'Transit while staged for a ferry action.',
    ),
  ];
}

PlannerCommandProfile? findCommandProfileById(
  List<PlannerCommandProfile> profiles,
  String id,
) {
  for (final PlannerCommandProfile profile in profiles) {
    if (profile.id == id) {
      return profile;
    }
  }
  return null;
}

double poseDistanceMeters(PlannerPose a, PlannerPose b) {
  final double dx = b.xMeters - a.xMeters;
  final double dy = b.yMeters - a.yMeters;
  return math.sqrt(dx * dx + dy * dy);
}

PlannerPose clampPoseToField(PlannerPose pose) {
  return PlannerPose(
    xMeters: pose.xMeters.clamp(0.0, fieldLengthMeters),
    yMeters: pose.yMeters.clamp(0.0, fieldWidthMeters),
    headingDeg: pose.headingDeg,
  );
}

PlannerZone clampPlannerZoneToField(PlannerZone zone) {
  const double minSizeMeters = 0.2;
  final double normalizedXMin = math.min(zone.xMinMeters, zone.xMaxMeters);
  final double normalizedXMax = math.max(zone.xMinMeters, zone.xMaxMeters);
  final double normalizedYMin = math.min(zone.yMinMeters, zone.yMaxMeters);
  final double normalizedYMax = math.max(zone.yMinMeters, zone.yMaxMeters);
  final double clampedXMin = normalizedXMin.clamp(
    0.0,
    fieldLengthMeters - minSizeMeters,
  );
  final double clampedYMin = normalizedYMin.clamp(
    0.0,
    fieldWidthMeters - minSizeMeters,
  );
  final double clampedXMax = normalizedXMax.clamp(
    clampedXMin + minSizeMeters,
    fieldLengthMeters,
  );
  final double clampedYMax = normalizedYMax.clamp(
    clampedYMin + minSizeMeters,
    fieldWidthMeters,
  );
  return zone.copyWith(
    xMinMeters: clampedXMin,
    yMinMeters: clampedYMin,
    xMaxMeters: clampedXMax,
    yMaxMeters: clampedYMax,
  );
}

PlannerEventZone clampEventZoneToField(PlannerEventZone zone) {
  const double minSizeMeters = 0.2;
  final double normalizedXMin = math.min(zone.xMinMeters, zone.xMaxMeters);
  final double normalizedXMax = math.max(zone.xMinMeters, zone.xMaxMeters);
  final double normalizedYMin = math.min(zone.yMinMeters, zone.yMaxMeters);
  final double normalizedYMax = math.max(zone.yMinMeters, zone.yMaxMeters);
  final double clampedXMin = normalizedXMin.clamp(
    0.0,
    fieldLengthMeters - minSizeMeters,
  );
  final double clampedYMin = normalizedYMin.clamp(
    0.0,
    fieldWidthMeters - minSizeMeters,
  );
  final double clampedXMax = normalizedXMax.clamp(
    clampedXMin + minSizeMeters,
    fieldLengthMeters,
  );
  final double clampedYMax = normalizedYMax.clamp(
    clampedYMin + minSizeMeters,
    fieldWidthMeters,
  );
  return zone.copyWith(
    xMinMeters: clampedXMin,
    yMinMeters: clampedYMin,
    xMaxMeters: clampedXMax,
    yMaxMeters: clampedYMax,
  );
}

List<PlannerPose> buildAutoRoutePoints(PlannerAuto auto) {
  final List<PlannerPose> points = <PlannerPose>[auto.startPose];
  for (final PlannerStep step in auto.steps) {
    points.addAll(
      step.routeWaypoints.map((PlannerWaypoint waypoint) => waypoint.pose),
    );
    points.add(step.pose);
  }
  return points;
}

PlannerPose resolvePointPose(
  PlannerAuto auto, {
  required bool startPoseSelected,
  required PlannerWaypointRef? ref,
}) {
  if (startPoseSelected || ref == null) {
    return auto.startPose;
  }
  if (ref.routeWaypointIndex == null) {
    return auto.steps[ref.stepIndex].pose;
  }
  return auto.steps[ref.stepIndex].routeWaypoints[ref.routeWaypointIndex!].pose;
}

PlannerPointConstraintProfile resolvePointConstraintProfile(
  PlannerAuto auto, {
  required bool startPoseSelected,
  required PlannerWaypointRef? ref,
}) {
  if (startPoseSelected || ref == null) {
    return auto.startPoseConstraintProfile;
  }
  if (ref.routeWaypointIndex == null) {
    return auto.steps[ref.stepIndex].anchorConstraintProfile;
  }
  return auto
      .steps[ref.stepIndex]
      .routeWaypoints[ref.routeWaypointIndex!]
      .constraintProfile;
}

PlannerPose resolveEventMarkerPose(PlannerAuto auto, PlannerEventMarker marker) {
  switch (marker.targetType) {
    case PlannerEventMarkerTargetType.startPose:
      return auto.startPose;
    case PlannerEventMarkerTargetType.stepAnchor:
      final int index = (marker.stepIndex ?? 0).clamp(0, auto.steps.length - 1);
      return auto.steps[index].pose;
    case PlannerEventMarkerTargetType.routeWaypoint:
      final int stepIndex =
          (marker.stepIndex ?? 0).clamp(0, auto.steps.length - 1);
      final List<PlannerWaypoint> waypoints = auto.steps[stepIndex].routeWaypoints;
      if (waypoints.isEmpty) {
        return auto.steps[stepIndex].pose;
      }
      final int waypointIndex =
          (marker.routeWaypointIndex ?? 0).clamp(0, waypoints.length - 1);
      return waypoints[waypointIndex].pose;
  }
}

String describeMarkerTarget(PlannerAuto auto, PlannerEventMarker marker) {
  switch (marker.targetType) {
    case PlannerEventMarkerTargetType.startPose:
      return 'Start Pose';
    case PlannerEventMarkerTargetType.stepAnchor:
      final int index = marker.stepIndex ?? 0;
      if (index < 0 || index >= auto.steps.length) {
        return 'Anchor';
      }
      return '${auto.steps[index].label} Anchor';
    case PlannerEventMarkerTargetType.routeWaypoint:
      final int stepIndex = marker.stepIndex ?? 0;
      final int waypointIndex = marker.routeWaypointIndex ?? 0;
      if (stepIndex < 0 || stepIndex >= auto.steps.length) {
        return 'Waypoint';
      }
      return '${auto.steps[stepIndex].label} WP ${waypointIndex + 1}';
  }
}

double _constraintFactorForProfile(PlannerPointConstraintProfile profile) {
  return profile.numericValue('constraintFactor') ?? 1.0;
}

Iterable<PlannerWaypointRef> allPointRefs(PlannerAuto auto) sync* {
  for (int stepIndex = 0; stepIndex < auto.steps.length; stepIndex += 1) {
    yield PlannerWaypointRef(stepIndex: stepIndex);
    for (
      int waypointIndex = 0;
      waypointIndex < auto.steps[stepIndex].routeWaypoints.length;
      waypointIndex += 1
    ) {
      yield PlannerWaypointRef(
        stepIndex: stepIndex,
        routeWaypointIndex: waypointIndex,
      );
    }
  }
}

String describePointRef(PlannerAuto auto, PlannerWaypointRef ref) {
  final PlannerStep step = auto.steps[ref.stepIndex];
  if (ref.routeWaypointIndex == null) {
    return '${step.label} Anchor';
  }
  final PlannerWaypoint waypoint = step.routeWaypoints[ref.routeWaypointIndex!];
  return '${step.label} ${waypoint.type == PlannerWaypointType.translation ? "Trans" : "Pose"} ${ref.routeWaypointIndex! + 1}';
}

double computeAutoDistanceMeters(PlannerAuto auto) {
  final List<PlannerPose> points = buildAutoRoutePoints(auto);
  double total = 0;
  for (int i = 1; i < points.length; i += 1) {
    total += poseDistanceMeters(points[i - 1], points[i]);
  }
  return total;
}

double _constraintFactorAtProgress(PlannerAuto auto, double progress) {
  double factor = 1.0;
  for (final PlannerConstraintZone zone in auto.constraintZones) {
    final double start = math.min(zone.startProgress, zone.endProgress);
    final double end = math.max(zone.startProgress, zone.endProgress);
    if (progress >= start && progress <= end) {
      factor = math.min(factor, zone.constraintFactor);
    }
  }
  return factor;
}

double _constraintFactorForSegment(
  PlannerAuto auto,
  PlannerPose start,
  PlannerPose end,
) {
  final PlannerPointConstraintProfile? startProfile =
      _profileForPose(auto, start);
  final PlannerPointConstraintProfile? endProfile = _profileForPose(auto, end);
  double factor = 1.0;
  if (startProfile != null) {
    factor = math.min(factor, _constraintFactorForProfile(startProfile));
  }
  if (endProfile != null) {
    factor = math.min(factor, _constraintFactorForProfile(endProfile));
  }
  return factor;
}

PlannerPointConstraintProfile? _profileForPose(PlannerAuto auto, PlannerPose pose) {
  if (auto.startPose == pose) {
    return auto.startPoseConstraintProfile;
  }
  for (final PlannerStep step in auto.steps) {
    if (step.pose == pose) {
      return step.anchorConstraintProfile;
    }
    for (final PlannerWaypoint waypoint in step.routeWaypoints) {
      if (waypoint.pose == pose) {
        return waypoint.constraintProfile;
      }
    }
  }
  return null;
}

double computeEstimatedTimeSeconds(PlannerAuto auto) {
  final List<PlannerPose> points = buildAutoRoutePoints(auto);
  if (points.length < 2) {
    return 0;
  }
  final double totalDistance = computeAutoDistanceMeters(auto);
  if (totalDistance <= 1e-6) {
    return auto.steps.fold(
      0.0,
      (double sum, PlannerStep step) => sum + step.waitSeconds,
    );
  }
  double traversed = 0;
  double seconds = 0;
  for (int i = 1; i < points.length; i += 1) {
    final double segmentDistance = poseDistanceMeters(points[i - 1], points[i]);
    if (segmentDistance <= 1e-6) {
      continue;
    }
    final double midpointProgress =
        ((traversed + (segmentDistance / 2)) / totalDistance).clamp(0.0, 1.0);
    final double factor = math.min(
      _constraintFactorAtProgress(auto, midpointProgress),
      _constraintFactorForSegment(auto, points[i - 1], points[i]),
    );
    final double limitedVelocity = math.min(
      auto.settings.maxVelocityMps,
      auto.settings.maxVelocityMps * factor,
    );
    final double effectiveVelocity = math.max(
      limitedVelocity * auto.settings.constraintFactor,
      0.35,
    );
    seconds += segmentDistance / effectiveVelocity;
    traversed += segmentDistance;
  }
  for (final PlannerStep step in auto.steps) {
    seconds += step.waitSeconds;
  }
  return seconds;
}

PlannerPose sampleAutoPoseAtProgress(PlannerAuto auto, double progress) {
  final List<PlannerPose> points = buildAutoRoutePoints(auto);
  if (points.isEmpty) {
    return const PlannerPose(xMeters: 0, yMeters: 0, headingDeg: 0);
  }
  if (points.length == 1) {
    return points.first;
  }
  final double clampedProgress = progress.clamp(0.0, 1.0);
  final double totalDistance = computeAutoDistanceMeters(auto);
  if (totalDistance <= 1e-6) {
    return points.last;
  }
  final double targetDistance = totalDistance * clampedProgress;
  double traversed = 0;
  for (int i = 1; i < points.length; i += 1) {
    final PlannerPose start = points[i - 1];
    final PlannerPose end = points[i];
    final double segmentDistance = poseDistanceMeters(start, end);
    if (traversed + segmentDistance >= targetDistance) {
      final double local = segmentDistance <= 1e-6
          ? 0
          : (targetDistance - traversed) / segmentDistance;
      return PlannerPose(
        xMeters: start.xMeters + ((end.xMeters - start.xMeters) * local),
        yMeters: start.yMeters + ((end.yMeters - start.yMeters) * local),
        headingDeg:
            start.headingDeg + ((end.headingDeg - start.headingDeg) * local),
      );
    }
    traversed += segmentDistance;
  }
  return points.last;
}

String formatDurationSeconds(double seconds) {
  final int whole = seconds.floor();
  final int minutes = whole ~/ 60;
  final int remaining = whole % 60;
  final int tenths = ((seconds - whole) * 10).round();
  if (minutes > 0) {
    return '$minutes:${remaining.toString().padLeft(2, '0')}.${tenths.toString()}';
  }
  return '${whole.toString()}.${tenths.toString()}s';
}

class PlannerPose {
  const PlannerPose({
    required this.xMeters,
    required this.yMeters,
    required this.headingDeg,
  });

  final double xMeters;
  final double yMeters;
  final double headingDeg;

  PlannerPose copyWith({double? xMeters, double? yMeters, double? headingDeg}) {
    return PlannerPose(
      xMeters: xMeters ?? this.xMeters,
      yMeters: yMeters ?? this.yMeters,
      headingDeg: headingDeg ?? this.headingDeg,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'xMeters': xMeters,
    'yMeters': yMeters,
    'headingDeg': headingDeg,
  };

  static PlannerPose fromJson(Map<String, dynamic> json) {
    return PlannerPose(
      xMeters: (json['xMeters'] as num?)?.toDouble() ?? 0,
      yMeters: (json['yMeters'] as num?)?.toDouble() ?? 0,
      headingDeg: (json['headingDeg'] as num?)?.toDouble() ?? 0,
    );
  }
}

enum PlannerWaypointType { translation, pose }

enum PlannerEventMarkerTargetType { startPose, stepAnchor, routeWaypoint }

enum PlannerConstraintValueType { numeric, toggle }

class PlannerConstraintDefinition {
  const PlannerConstraintDefinition({
    required this.id,
    required this.label,
    required this.type,
    this.unit = '',
    this.min,
    this.max,
  });

  final String id;
  final String label;
  final PlannerConstraintValueType type;
  final String unit;
  final double? min;
  final double? max;
}

const List<PlannerConstraintDefinition> plannerConstraintCatalog =
    <PlannerConstraintDefinition>[
      PlannerConstraintDefinition(
        id: 'maxLinearVelocityMps',
        label: 'Max Linear Velocity',
        type: PlannerConstraintValueType.numeric,
        unit: 'm/s',
        min: 0,
        max: 8,
      ),
      PlannerConstraintDefinition(
        id: 'minLinearVelocityMps',
        label: 'Min Linear Velocity',
        type: PlannerConstraintValueType.numeric,
        unit: 'm/s',
        min: 0,
        max: 8,
      ),
      PlannerConstraintDefinition(
        id: 'maxLinearAccelerationMpsSq',
        label: 'Max Linear Acceleration',
        type: PlannerConstraintValueType.numeric,
        unit: 'm/s²',
        min: 0,
        max: 10,
      ),
      PlannerConstraintDefinition(
        id: 'maxAngularVelocityDegPerSec',
        label: 'Max Angular Velocity',
        type: PlannerConstraintValueType.numeric,
        unit: 'deg/s',
        min: 0,
        max: 1080,
      ),
      PlannerConstraintDefinition(
        id: 'maxAngularAccelerationDegPerSecSq',
        label: 'Max Angular Acceleration',
        type: PlannerConstraintValueType.numeric,
        unit: 'deg/s²',
        min: 0,
        max: 2160,
      ),
      PlannerConstraintDefinition(
        id: 'curvatureVelocityLimitMps',
        label: 'Curvature Velocity Limit',
        type: PlannerConstraintValueType.numeric,
        unit: 'm/s',
        min: 0,
        max: 8,
      ),
      PlannerConstraintDefinition(
        id: 'maxCentripetalAccelerationMpsSq',
        label: 'Max Centripetal Accel',
        type: PlannerConstraintValueType.numeric,
        unit: 'm/s²',
        min: 0,
        max: 10,
      ),
      PlannerConstraintDefinition(
        id: 'nominalVoltage',
        label: 'Nominal Voltage',
        type: PlannerConstraintValueType.numeric,
        unit: 'V',
        min: 0,
        max: 16,
      ),
      PlannerConstraintDefinition(
        id: 'maxMotorTorqueNm',
        label: 'Motor Torque Limit',
        type: PlannerConstraintValueType.numeric,
        unit: 'Nm',
        min: 0,
        max: 20,
      ),
      PlannerConstraintDefinition(
        id: 'maxWheelForceN',
        label: 'Wheel Force Limit',
        type: PlannerConstraintValueType.numeric,
        unit: 'N',
        min: 0,
        max: 400,
      ),
      PlannerConstraintDefinition(
        id: 'currentLimitAmps',
        label: 'Current Limit',
        type: PlannerConstraintValueType.numeric,
        unit: 'A',
        min: 0,
        max: 200,
      ),
      PlannerConstraintDefinition(
        id: 'powerLimitWatts',
        label: 'Power Limit',
        type: PlannerConstraintValueType.numeric,
        unit: 'W',
        min: 0,
        max: 5000,
      ),
      PlannerConstraintDefinition(
        id: 'frictionConeCoefficient',
        label: 'Friction Cone Coeff',
        type: PlannerConstraintValueType.numeric,
        min: 0,
        max: 2,
      ),
      PlannerConstraintDefinition(
        id: 'maxJerkMpsCubed',
        label: 'Jerk Limit',
        type: PlannerConstraintValueType.numeric,
        unit: 'm/s³',
        min: 0,
        max: 30,
      ),
      PlannerConstraintDefinition(
        id: 'finalVelocityMps',
        label: 'Final Velocity',
        type: PlannerConstraintValueType.numeric,
        unit: 'm/s',
        min: 0,
        max: 8,
      ),
      PlannerConstraintDefinition(
        id: 'finalAccelerationMpsSq',
        label: 'Final Acceleration',
        type: PlannerConstraintValueType.numeric,
        unit: 'm/s²',
        min: -10,
        max: 10,
      ),
      PlannerConstraintDefinition(
        id: 'constraintFactor',
        label: 'Constraint Factor',
        type: PlannerConstraintValueType.numeric,
        min: 0,
        max: 2,
      ),
      PlannerConstraintDefinition(
        id: 'timeWeight',
        label: 'Time Weight',
        type: PlannerConstraintValueType.numeric,
        min: 0,
        max: 10,
      ),
      PlannerConstraintDefinition(
        id: 'maxModuleSpeedMps',
        label: 'Max Module Speed',
        type: PlannerConstraintValueType.numeric,
        unit: 'm/s',
        min: 0,
        max: 8,
      ),
      PlannerConstraintDefinition(
        id: 'massKg',
        label: 'Robot Mass',
        type: PlannerConstraintValueType.numeric,
        unit: 'kg',
        min: 0,
        max: 100,
      ),
      PlannerConstraintDefinition(
        id: 'inertiaKgM2',
        label: 'Robot Inertia',
        type: PlannerConstraintValueType.numeric,
        unit: 'kg·m²',
        min: 0,
        max: 20,
      ),
      PlannerConstraintDefinition(
        id: 'toleranceMeters',
        label: 'Pose Tolerance',
        type: PlannerConstraintValueType.numeric,
        unit: 'm',
        min: 0,
        max: 1,
      ),
      PlannerConstraintDefinition(
        id: 'poseBlendWeight',
        label: 'Pose Blend Weight',
        type: PlannerConstraintValueType.numeric,
        min: 0,
        max: 1,
      ),
      PlannerConstraintDefinition(
        id: 'continuousCurvature',
        label: 'Continuous Curvature',
        type: PlannerConstraintValueType.toggle,
      ),
      PlannerConstraintDefinition(
        id: 'angularTranslationalCoupling',
        label: 'Angular/Trans Coupling',
        type: PlannerConstraintValueType.toggle,
      ),
      PlannerConstraintDefinition(
        id: 'continuousPose',
        label: 'Continuous Pose',
        type: PlannerConstraintValueType.toggle,
      ),
      PlannerConstraintDefinition(
        id: 'timeOptimization',
        label: 'Time Optimization',
        type: PlannerConstraintValueType.toggle,
      ),
      PlannerConstraintDefinition(
        id: 'obstacleAvoidance',
        label: 'Obstacle Avoidance',
        type: PlannerConstraintValueType.toggle,
      ),
      PlannerConstraintDefinition(
        id: 'drivetrainKinematics',
        label: 'Drivetrain Kinematics',
        type: PlannerConstraintValueType.toggle,
      ),
      PlannerConstraintDefinition(
        id: 'nonlinearOptimization',
        label: 'Nonlinear Optimization',
        type: PlannerConstraintValueType.toggle,
      ),
      PlannerConstraintDefinition(
        id: 'continuityConstraint',
        label: 'Continuity Constraint',
        type: PlannerConstraintValueType.toggle,
      ),
    ];

class PlannerPointConstraintProfile {
  const PlannerPointConstraintProfile({
    this.numericValues = const <String, double>{},
    this.toggleValues = const <String, bool>{},
  });

  final Map<String, double> numericValues;
  final Map<String, bool> toggleValues;

  bool get hasAnyValues =>
      numericValues.isNotEmpty ||
      toggleValues.values.any((bool enabled) => enabled);

  double? numericValue(String id) => numericValues[id];

  bool toggleValue(String id) => toggleValues[id] ?? false;

  List<String> get activeConstraintIds => <String>[
    ...numericValues.keys,
    ...toggleValues.entries
        .where((MapEntry<String, bool> entry) => entry.value)
        .map((MapEntry<String, bool> entry) => entry.key),
  ];

  PlannerPointConstraintProfile copyWith({
    Map<String, double>? numericValues,
    Map<String, bool>? toggleValues,
  }) {
    return PlannerPointConstraintProfile(
      numericValues: numericValues ?? this.numericValues,
      toggleValues: toggleValues ?? this.toggleValues,
    );
  }

  PlannerPointConstraintProfile setNumeric(String id, double? value) {
    final Map<String, double> next = <String, double>{...numericValues};
    if (value == null) {
      next.remove(id);
    } else {
      next[id] = value;
    }
    return copyWith(numericValues: next);
  }

  PlannerPointConstraintProfile setToggle(String id, bool enabled) {
    final Map<String, bool> next = <String, bool>{...toggleValues};
    if (enabled) {
      next[id] = true;
    } else {
      next.remove(id);
    }
    return copyWith(toggleValues: next);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'numericValues': numericValues,
    'toggleValues': toggleValues,
  };

  static PlannerPointConstraintProfile fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PlannerPointConstraintProfile();
    }
    return PlannerPointConstraintProfile(
      numericValues:
          (json['numericValues'] as Map<String, dynamic>? ?? const <String, dynamic>{})
              .map(
                (String key, dynamic value) =>
                    MapEntry<String, double>(key, (value as num).toDouble()),
              ),
      toggleValues:
          (json['toggleValues'] as Map<String, dynamic>? ?? const <String, dynamic>{})
              .map(
                (String key, dynamic value) =>
                    MapEntry<String, bool>(key, value as bool? ?? false),
              ),
    );
  }
}

class PlannerWaypoint {
  const PlannerWaypoint({
    required this.pose,
    this.type = PlannerWaypointType.translation,
    this.bendStrength = 0.5,
    this.constraintProfile = const PlannerPointConstraintProfile(),
  });

  final PlannerPose pose;
  final PlannerWaypointType type;
  final double bendStrength;
  final PlannerPointConstraintProfile constraintProfile;

  PlannerWaypoint copyWith({
    PlannerPose? pose,
    PlannerWaypointType? type,
    double? bendStrength,
    PlannerPointConstraintProfile? constraintProfile,
  }) {
    return PlannerWaypoint(
      pose: pose ?? this.pose,
      type: type ?? this.type,
      bendStrength: bendStrength ?? this.bendStrength,
      constraintProfile: constraintProfile ?? this.constraintProfile,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    'bendStrength': bendStrength,
    'pose': pose.toJson(),
    'constraintProfile': constraintProfile.toJson(),
  };

  static PlannerWaypoint fromJson(Map<String, dynamic> json) {
    final String rawType = json['type'] as String? ?? 'translation';
    return PlannerWaypoint(
      type: rawType == PlannerWaypointType.pose.name
          ? PlannerWaypointType.pose
          : PlannerWaypointType.translation,
      bendStrength: (json['bendStrength'] as num?)?.toDouble() ?? 0.5,
      pose: PlannerPose.fromJson(
        json['pose'] as Map<String, dynamic>? ??
            <String, dynamic>{
              'xMeters': (json['xMeters'] as num?)?.toDouble() ?? 0,
              'yMeters': (json['yMeters'] as num?)?.toDouble() ?? 0,
              'headingDeg': (json['headingDeg'] as num?)?.toDouble() ?? 0,
            },
      ),
      constraintProfile: PlannerPointConstraintProfile.fromJson(
        json['constraintProfile'] as Map<String, dynamic>?,
      ),
    );
  }
}

class PlannerWaypointRef {
  const PlannerWaypointRef({required this.stepIndex, this.routeWaypointIndex});

  final int stepIndex;
  final int? routeWaypointIndex;

  bool get isAnchor => routeWaypointIndex == null;
}

class PlannerNamedPose {
  const PlannerNamedPose({
    required this.id,
    required this.name,
    required this.pose,
  });

  final String id;
  final String name;
  final PlannerPose pose;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'pose': pose.toJson(),
  };

  static PlannerNamedPose fromJson(Map<String, dynamic> json) {
    return PlannerNamedPose(
      id: json['id'] as String? ?? 'start',
      name: json['name'] as String? ?? 'Start',
      pose: PlannerPose.fromJson(
        json['pose'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class PlannerNamedValue {
  const PlannerNamedValue({
    required this.id,
    required this.name,
    required this.value,
    this.unit = '',
  });

  final String id;
  final String name;
  final double value;
  final String unit;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'value': value,
    'unit': unit,
  };

  static PlannerNamedValue fromJson(Map<String, dynamic> json) {
    return PlannerNamedValue(
      id: json['id'] as String? ?? 'value',
      name: json['name'] as String? ?? 'Value',
      value: (json['value'] as num?)?.toDouble() ?? 0,
      unit: json['unit'] as String? ?? '',
    );
  }
}

class PlannerZone {
  const PlannerZone({
    required this.id,
    required this.label,
    required this.xMinMeters,
    required this.yMinMeters,
    required this.xMaxMeters,
    required this.yMaxMeters,
    this.locked = false,
  });

  final String id;
  final String label;
  final double xMinMeters;
  final double yMinMeters;
  final double xMaxMeters;
  final double yMaxMeters;
  final bool locked;

  PlannerZone copyWith({
    String? id,
    String? label,
    double? xMinMeters,
    double? yMinMeters,
    double? xMaxMeters,
    double? yMaxMeters,
    bool? locked,
  }) {
    return PlannerZone(
      id: id ?? this.id,
      label: label ?? this.label,
      xMinMeters: xMinMeters ?? this.xMinMeters,
      yMinMeters: yMinMeters ?? this.yMinMeters,
      xMaxMeters: xMaxMeters ?? this.xMaxMeters,
      yMaxMeters: yMaxMeters ?? this.yMaxMeters,
      locked: locked ?? this.locked,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'xMinMeters': xMinMeters,
    'yMinMeters': yMinMeters,
    'xMaxMeters': xMaxMeters,
    'yMaxMeters': yMaxMeters,
    'locked': locked,
  };

  static PlannerZone fromJson(Map<String, dynamic> json) {
    return PlannerZone(
      id: json['id'] as String? ?? 'zone',
      label: json['label'] as String? ?? 'Keep-Out',
      xMinMeters: (json['xMinMeters'] as num?)?.toDouble() ?? 0,
      yMinMeters: (json['yMinMeters'] as num?)?.toDouble() ?? 0,
      xMaxMeters: (json['xMaxMeters'] as num?)?.toDouble() ?? 0,
      yMaxMeters: (json['yMaxMeters'] as num?)?.toDouble() ?? 0,
      locked: json['locked'] as bool? ?? false,
    );
  }
}

class PlannerEventMarker {
  const PlannerEventMarker({
    required this.id,
    required this.name,
    required this.targetType,
    this.commandId = '',
    this.notes = '',
    this.stepIndex,
    this.routeWaypointIndex,
  });

  final String id;
  final String name;
  final PlannerEventMarkerTargetType targetType;
  final String commandId;
  final String notes;
  final int? stepIndex;
  final int? routeWaypointIndex;

  PlannerEventMarker copyWith({
    String? id,
    String? name,
    PlannerEventMarkerTargetType? targetType,
    String? commandId,
    String? notes,
    int? stepIndex,
    int? routeWaypointIndex,
  }) {
    return PlannerEventMarker(
      id: id ?? this.id,
      name: name ?? this.name,
      targetType: targetType ?? this.targetType,
      commandId: commandId ?? this.commandId,
      notes: notes ?? this.notes,
      stepIndex: stepIndex ?? this.stepIndex,
      routeWaypointIndex: routeWaypointIndex ?? this.routeWaypointIndex,
    );
  }

  bool targetsSelection({
    required bool startPoseSelected,
    required PlannerWaypointRef? selectedWaypointRef,
  }) {
    if (startPoseSelected) {
      return targetType == PlannerEventMarkerTargetType.startPose;
    }
    if (selectedWaypointRef == null) {
      return false;
    }
    if (selectedWaypointRef.routeWaypointIndex == null) {
      return targetType == PlannerEventMarkerTargetType.stepAnchor &&
          stepIndex == selectedWaypointRef.stepIndex;
    }
    return targetType == PlannerEventMarkerTargetType.routeWaypoint &&
        stepIndex == selectedWaypointRef.stepIndex &&
        routeWaypointIndex == selectedWaypointRef.routeWaypointIndex;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'targetType': targetType.name,
    'commandId': commandId,
    'notes': notes,
    'stepIndex': stepIndex,
    'routeWaypointIndex': routeWaypointIndex,
  };

  static PlannerEventMarker fromJson(Map<String, dynamic> json) {
    final String rawTargetType =
        json['targetType'] as String? ??
        (json.containsKey('progress')
            ? PlannerEventMarkerTargetType.startPose.name
            : PlannerEventMarkerTargetType.stepAnchor.name);
    return PlannerEventMarker(
      id: json['id'] as String? ?? 'marker',
      name: json['name'] as String? ?? 'Marker',
      targetType: PlannerEventMarkerTargetType.values.firstWhere(
        (PlannerEventMarkerTargetType value) => value.name == rawTargetType,
        orElse: () => PlannerEventMarkerTargetType.stepAnchor,
      ),
      commandId: json['commandId'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      stepIndex: (json['stepIndex'] as num?)?.toInt(),
      routeWaypointIndex: (json['routeWaypointIndex'] as num?)?.toInt(),
    );
  }
}

class PlannerEventZone {
  const PlannerEventZone({
    required this.id,
    required this.name,
    required this.xMinMeters,
    required this.yMinMeters,
    required this.xMaxMeters,
    required this.yMaxMeters,
    this.enterCommandId = '',
    this.exitCommandId = '',
    this.activeCommandId = '',
    this.colorHex = '#FF8C69',
  });

  final String id;
  final String name;
  final double xMinMeters;
  final double yMinMeters;
  final double xMaxMeters;
  final double yMaxMeters;
  final String enterCommandId;
  final String exitCommandId;
  final String activeCommandId;
  final String colorHex;

  Color get color => parseHexColor(colorHex) ?? const Color(0xFFFF8C69);

  PlannerEventZone copyWith({
    String? id,
    String? name,
    double? xMinMeters,
    double? yMinMeters,
    double? xMaxMeters,
    double? yMaxMeters,
    String? enterCommandId,
    String? exitCommandId,
    String? activeCommandId,
    String? colorHex,
  }) {
    return PlannerEventZone(
      id: id ?? this.id,
      name: name ?? this.name,
      xMinMeters: xMinMeters ?? this.xMinMeters,
      yMinMeters: yMinMeters ?? this.yMinMeters,
      xMaxMeters: xMaxMeters ?? this.xMaxMeters,
      yMaxMeters: yMaxMeters ?? this.yMaxMeters,
      enterCommandId: enterCommandId ?? this.enterCommandId,
      exitCommandId: exitCommandId ?? this.exitCommandId,
      activeCommandId: activeCommandId ?? this.activeCommandId,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'xMinMeters': xMinMeters,
    'yMinMeters': yMinMeters,
    'xMaxMeters': xMaxMeters,
    'yMaxMeters': yMaxMeters,
    'enterCommandId': enterCommandId,
    'exitCommandId': exitCommandId,
    'activeCommandId': activeCommandId,
    'colorHex': colorHex,
  };

  static PlannerEventZone fromJson(Map<String, dynamic> json) {
    final double fallbackProgress =
        ((json['startProgress'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    final double fallbackCenterX = fallbackProgress * fieldLengthMeters;
    const double fallbackHalfWidth = 0.5;
    const double fallbackHalfHeight = 0.55;
    return PlannerEventZone(
      id: json['id'] as String? ?? 'event-zone',
      name: json['name'] as String? ?? 'Zone',
      xMinMeters:
          (json['xMinMeters'] as num?)?.toDouble() ??
          (fallbackCenterX - fallbackHalfWidth),
      yMinMeters:
          (json['yMinMeters'] as num?)?.toDouble() ??
          ((fieldWidthMeters / 2) - fallbackHalfHeight),
      xMaxMeters:
          (json['xMaxMeters'] as num?)?.toDouble() ??
          (fallbackCenterX + fallbackHalfWidth),
      yMaxMeters:
          (json['yMaxMeters'] as num?)?.toDouble() ??
          ((fieldWidthMeters / 2) + fallbackHalfHeight),
      enterCommandId: json['enterCommandId'] as String? ?? '',
      exitCommandId: json['exitCommandId'] as String? ?? '',
      activeCommandId: json['activeCommandId'] as String? ?? '',
      colorHex: json['colorHex'] as String? ?? '#FF8C69',
    );
  }
}

class PlannerConstraintZone {
  const PlannerConstraintZone({
    required this.id,
    required this.name,
    required this.startProgress,
    required this.endProgress,
    this.maxVelocityMps = 2.0,
    this.maxAccelerationMpsSq = 2.0,
    this.constraintFactor = 0.65,
    this.maxAngularVelocityDegPerSec = 180,
    this.maxAngularAccelerationDegPerSecSq = 270,
    this.toleranceMetersOverride = 0.06,
    this.poseBlendWeightOverride = 0.35,
  });

  final String id;
  final String name;
  final double startProgress;
  final double endProgress;
  final double maxVelocityMps;
  final double maxAccelerationMpsSq;
  final double constraintFactor;
  final double maxAngularVelocityDegPerSec;
  final double maxAngularAccelerationDegPerSecSq;
  final double toleranceMetersOverride;
  final double poseBlendWeightOverride;

  PlannerConstraintZone copyWith({
    String? id,
    String? name,
    double? startProgress,
    double? endProgress,
    double? maxVelocityMps,
    double? maxAccelerationMpsSq,
    double? constraintFactor,
    double? maxAngularVelocityDegPerSec,
    double? maxAngularAccelerationDegPerSecSq,
    double? toleranceMetersOverride,
    double? poseBlendWeightOverride,
  }) {
    return PlannerConstraintZone(
      id: id ?? this.id,
      name: name ?? this.name,
      startProgress: startProgress ?? this.startProgress,
      endProgress: endProgress ?? this.endProgress,
      maxVelocityMps: maxVelocityMps ?? this.maxVelocityMps,
      maxAccelerationMpsSq: maxAccelerationMpsSq ?? this.maxAccelerationMpsSq,
      constraintFactor: constraintFactor ?? this.constraintFactor,
      maxAngularVelocityDegPerSec:
          maxAngularVelocityDegPerSec ?? this.maxAngularVelocityDegPerSec,
      maxAngularAccelerationDegPerSecSq:
          maxAngularAccelerationDegPerSecSq ??
          this.maxAngularAccelerationDegPerSecSq,
      toleranceMetersOverride:
          toleranceMetersOverride ?? this.toleranceMetersOverride,
      poseBlendWeightOverride:
          poseBlendWeightOverride ?? this.poseBlendWeightOverride,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'startProgress': startProgress,
    'endProgress': endProgress,
    'maxVelocityMps': maxVelocityMps,
    'maxAccelerationMpsSq': maxAccelerationMpsSq,
    'constraintFactor': constraintFactor,
    'maxAngularVelocityDegPerSec': maxAngularVelocityDegPerSec,
    'maxAngularAccelerationDegPerSecSq': maxAngularAccelerationDegPerSecSq,
    'toleranceMetersOverride': toleranceMetersOverride,
    'poseBlendWeightOverride': poseBlendWeightOverride,
  };

  static PlannerConstraintZone fromJson(Map<String, dynamic> json) {
    return PlannerConstraintZone(
      id: json['id'] as String? ?? 'constraint-zone',
      name: json['name'] as String? ?? 'Constraint Zone',
      startProgress: ((json['startProgress'] as num?)?.toDouble() ?? 0).clamp(
        0.0,
        1.0,
      ),
      endProgress: ((json['endProgress'] as num?)?.toDouble() ?? 1).clamp(
        0.0,
        1.0,
      ),
      maxVelocityMps: (json['maxVelocityMps'] as num?)?.toDouble() ?? 2.0,
      maxAccelerationMpsSq:
          (json['maxAccelerationMpsSq'] as num?)?.toDouble() ?? 2.0,
      constraintFactor: (json['constraintFactor'] as num?)?.toDouble() ?? 0.65,
      maxAngularVelocityDegPerSec:
          (json['maxAngularVelocityDegPerSec'] as num?)?.toDouble() ?? 180,
      maxAngularAccelerationDegPerSecSq:
          (json['maxAngularAccelerationDegPerSecSq'] as num?)?.toDouble() ??
          270,
      toleranceMetersOverride:
          (json['toleranceMetersOverride'] as num?)?.toDouble() ?? 0.06,
      poseBlendWeightOverride:
          (json['poseBlendWeightOverride'] as num?)?.toDouble() ?? 0.35,
    );
  }
}

class PlannerSettings {
  const PlannerSettings({
    this.visionCorrectionEnabled = true,
    this.poseBlendWeight = 0.35,
    this.constraintFactor = 0.8,
    this.toleranceMeters = 0.06,
    this.timeoutSeconds = 1.6,
    this.endVelocityMps = 1.2,
    this.controlRateHz = 50,
    this.robotWidthMeters = defaultRobotSizeMeters,
    this.robotLengthMeters = defaultRobotSizeMeters,
    this.allowReverse = false,
    this.holdHeading = true,
    this.previewSmoothing = 0.72,
    this.maxVelocityMps = 4.6,
    this.maxAccelerationMpsSq = 3.5,
  });

  final bool visionCorrectionEnabled;
  final double poseBlendWeight;
  final double constraintFactor;
  final double toleranceMeters;
  final double timeoutSeconds;
  final double endVelocityMps;
  final double controlRateHz;
  final double robotWidthMeters;
  final double robotLengthMeters;
  final bool allowReverse;
  final bool holdHeading;
  final double previewSmoothing;
  final double maxVelocityMps;
  final double maxAccelerationMpsSq;

  PlannerSettings copyWith({
    bool? visionCorrectionEnabled,
    double? poseBlendWeight,
    double? constraintFactor,
    double? toleranceMeters,
    double? timeoutSeconds,
    double? endVelocityMps,
    double? controlRateHz,
    double? robotWidthMeters,
    double? robotLengthMeters,
    bool? allowReverse,
    bool? holdHeading,
    double? previewSmoothing,
    double? maxVelocityMps,
    double? maxAccelerationMpsSq,
  }) {
    return PlannerSettings(
      visionCorrectionEnabled:
          visionCorrectionEnabled ?? this.visionCorrectionEnabled,
      poseBlendWeight: poseBlendWeight ?? this.poseBlendWeight,
      constraintFactor: constraintFactor ?? this.constraintFactor,
      toleranceMeters: toleranceMeters ?? this.toleranceMeters,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      endVelocityMps: endVelocityMps ?? this.endVelocityMps,
      controlRateHz: controlRateHz ?? this.controlRateHz,
      robotWidthMeters: robotWidthMeters ?? this.robotWidthMeters,
      robotLengthMeters: robotLengthMeters ?? this.robotLengthMeters,
      allowReverse: allowReverse ?? this.allowReverse,
      holdHeading: holdHeading ?? this.holdHeading,
      previewSmoothing: previewSmoothing ?? this.previewSmoothing,
      maxVelocityMps: maxVelocityMps ?? this.maxVelocityMps,
      maxAccelerationMpsSq: maxAccelerationMpsSq ?? this.maxAccelerationMpsSq,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'visionCorrection': <String, dynamic>{
      'enabled': visionCorrectionEnabled,
      'poseBlendWeight': poseBlendWeight,
    },
    'autoAlign': <String, dynamic>{
      'constraintFactor': constraintFactor,
      'toleranceMeters': toleranceMeters,
      'timeoutSeconds': timeoutSeconds,
      'endVelocityMps': endVelocityMps,
    },
    'planner': <String, dynamic>{
      'controlRateHz': controlRateHz,
      'robotWidthMeters': robotWidthMeters,
      'robotLengthMeters': robotLengthMeters,
      'allowReverse': allowReverse,
      'holdHeading': holdHeading,
      'previewSmoothing': previewSmoothing,
      'maxVelocityMps': maxVelocityMps,
      'maxAccelerationMpsSq': maxAccelerationMpsSq,
    },
  };

  static PlannerSettings fromJson(Map<String, dynamic>? json) {
    final vision =
        json?['visionCorrection'] as Map<String, dynamic>? ?? const {};
    final align = json?['autoAlign'] as Map<String, dynamic>? ?? const {};
    final planner = json?['planner'] as Map<String, dynamic>? ?? const {};
    return PlannerSettings(
      visionCorrectionEnabled: vision['enabled'] as bool? ?? true,
      poseBlendWeight: (vision['poseBlendWeight'] as num?)?.toDouble() ?? 0.35,
      constraintFactor: (align['constraintFactor'] as num?)?.toDouble() ?? 0.8,
      toleranceMeters: (align['toleranceMeters'] as num?)?.toDouble() ?? 0.06,
      timeoutSeconds: (align['timeoutSeconds'] as num?)?.toDouble() ?? 1.6,
      endVelocityMps: (align['endVelocityMps'] as num?)?.toDouble() ?? 1.2,
      controlRateHz: (planner['controlRateHz'] as num?)?.toDouble() ?? 50,
      robotWidthMeters:
          (planner['robotWidthMeters'] as num?)?.toDouble() ??
          defaultRobotSizeMeters,
      robotLengthMeters:
          (planner['robotLengthMeters'] as num?)?.toDouble() ??
          defaultRobotSizeMeters,
      allowReverse: planner['allowReverse'] as bool? ?? false,
      holdHeading: planner['holdHeading'] as bool? ?? true,
      previewSmoothing:
          (planner['previewSmoothing'] as num?)?.toDouble() ?? 0.72,
      maxVelocityMps: (planner['maxVelocityMps'] as num?)?.toDouble() ?? 4.6,
      maxAccelerationMpsSq:
          (planner['maxAccelerationMpsSq'] as num?)?.toDouble() ?? 3.5,
    );
  }
}

class PlannerStep {
  const PlannerStep({
    required this.id,
    required this.label,
    required this.requestedState,
    required this.pose,
    this.group = 'LANE',
    this.spotId = '',
    this.commandId = '',
    this.commandName = '',
    this.routeWaypoints = const <PlannerWaypoint>[],
    this.waitSeconds = 0,
    this.anchorConstraintProfile = const PlannerPointConstraintProfile(),
  });

  final String id;
  final String label;
  final RequestedState requestedState;
  final PlannerPose pose;
  final String group;
  final String spotId;
  final String commandId;
  final String commandName;
  final List<PlannerWaypoint> routeWaypoints;
  final double waitSeconds;
  final PlannerPointConstraintProfile anchorConstraintProfile;

  PlannerStep copyWith({
    String? id,
    String? label,
    RequestedState? requestedState,
    PlannerPose? pose,
    String? group,
    String? spotId,
    String? commandId,
    String? commandName,
    List<PlannerWaypoint>? routeWaypoints,
    double? waitSeconds,
    PlannerPointConstraintProfile? anchorConstraintProfile,
  }) {
    return PlannerStep(
      id: id ?? this.id,
      label: label ?? this.label,
      requestedState: requestedState ?? this.requestedState,
      pose: pose ?? this.pose,
      group: group ?? this.group,
      spotId: spotId ?? this.spotId,
      commandId: commandId ?? this.commandId,
      commandName: commandName ?? this.commandName,
      routeWaypoints: routeWaypoints ?? this.routeWaypoints,
      waitSeconds: waitSeconds ?? this.waitSeconds,
      anchorConstraintProfile:
          anchorConstraintProfile ?? this.anchorConstraintProfile,
    );
  }

  Map<String, dynamic> toJson(PlannerSettings settings) => <String, dynamic>{
    'spotId': spotId,
    'label': label,
    'group': group,
    'commandId': commandId,
    'commandName': commandName,
    'requestedState': requestedState.token,
    'xMeters': pose.xMeters,
    'yMeters': pose.yMeters,
    'headingDeg': pose.headingDeg,
    'constraintFactor': settings.constraintFactor,
    'toleranceMeters': settings.toleranceMeters,
    'timeoutSeconds': settings.timeoutSeconds,
    'endVelocityMps': settings.endVelocityMps,
    'waitSeconds': waitSeconds,
    'anchorConstraintProfile': anchorConstraintProfile.toJson(),
    'routeWaypoints': routeWaypoints
        .map((PlannerWaypoint waypoint) => waypoint.toJson())
        .toList(),
  };

  static PlannerStep fromJson(Map<String, dynamic> json) {
    return PlannerStep(
      id: (json['id'] as String?) ?? UniqueKey().toString(),
      label: json['label'] as String? ?? 'Step',
      requestedState: RequestedState.fromToken(
        json['requestedState'] as String? ?? 'IDLING',
      ),
      pose: PlannerPose(
        xMeters: (json['xMeters'] as num?)?.toDouble() ?? 0,
        yMeters: (json['yMeters'] as num?)?.toDouble() ?? 0,
        headingDeg: (json['headingDeg'] as num?)?.toDouble() ?? 0,
      ),
      group: json['group'] as String? ?? 'LANE',
      spotId: json['spotId'] as String? ?? '',
      commandId: json['commandId'] as String? ?? '',
      commandName: json['commandName'] as String? ?? '',
      waitSeconds: (json['waitSeconds'] as num?)?.toDouble() ?? 0,
      anchorConstraintProfile: PlannerPointConstraintProfile.fromJson(
        json['anchorConstraintProfile'] as Map<String, dynamic>?,
      ),
      routeWaypoints: (json['routeWaypoints'] as List<dynamic>? ?? const [])
          .map(
            (dynamic waypoint) =>
                PlannerWaypoint.fromJson(waypoint as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class PlannerAuto {
  const PlannerAuto({
    required this.id,
    required this.name,
    required this.folder,
    required this.updatedAt,
    required this.startPose,
    required this.steps,
    required this.settings,
    this.customZones = const <PlannerZone>[],
    this.eventMarkers = const <PlannerEventMarker>[],
    this.eventZones = const <PlannerEventZone>[],
    this.constraintZones = const <PlannerConstraintZone>[],
    this.startPoseConstraintProfile = const PlannerPointConstraintProfile(),
  });

  final String id;
  final String name;
  final String folder;
  final DateTime updatedAt;
  final PlannerPose startPose;
  final List<PlannerStep> steps;
  final PlannerSettings settings;
  final List<PlannerZone> customZones;
  final List<PlannerEventMarker> eventMarkers;
  final List<PlannerEventZone> eventZones;
  final List<PlannerConstraintZone> constraintZones;
  final PlannerPointConstraintProfile startPoseConstraintProfile;

  PlannerAuto copyWith({
    String? id,
    String? name,
    String? folder,
    DateTime? updatedAt,
    PlannerPose? startPose,
    List<PlannerStep>? steps,
    PlannerSettings? settings,
    List<PlannerZone>? customZones,
    List<PlannerEventMarker>? eventMarkers,
    List<PlannerEventZone>? eventZones,
    List<PlannerConstraintZone>? constraintZones,
    PlannerPointConstraintProfile? startPoseConstraintProfile,
  }) {
    return PlannerAuto(
      id: id ?? this.id,
      name: name ?? this.name,
      folder: folder ?? this.folder,
      updatedAt: updatedAt ?? this.updatedAt,
      startPose: startPose ?? this.startPose,
      steps: steps ?? this.steps,
      settings: settings ?? this.settings,
      customZones: customZones ?? this.customZones,
      eventMarkers: eventMarkers ?? this.eventMarkers,
      eventZones: eventZones ?? this.eventZones,
      constraintZones: constraintZones ?? this.constraintZones,
      startPoseConstraintProfile:
          startPoseConstraintProfile ?? this.startPoseConstraintProfile,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'folder': folder,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'startPose': startPose.toJson(),
    'customZones': customZones.map((zone) => zone.toJson()).toList(),
    'eventMarkers': eventMarkers.map((event) => event.toJson()).toList(),
    'eventZones': eventZones.map((event) => event.toJson()).toList(),
    'constraintZones': constraintZones.map((zone) => zone.toJson()).toList(),
    'startPoseConstraintProfile': startPoseConstraintProfile.toJson(),
    'plannerSettings': settings.toJson(),
    'steps': steps.map((step) => step.toJson(settings)).toList(),
  };

  static PlannerAuto fromJson(Map<String, dynamic> json) {
    return PlannerAuto(
      id: json['id'] as String? ?? UniqueKey().toString(),
      name: json['name'] as String? ?? 'Imported Auto',
      folder: json['folder'] as String? ?? 'Autos',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      startPose: PlannerPose.fromJson(
        json['startPose'] as Map<String, dynamic>? ?? const {},
      ),
      settings: PlannerSettings.fromJson(
        json['plannerSettings'] as Map<String, dynamic>?,
      ),
      customZones: (json['customZones'] as List<dynamic>? ?? const [])
          .map(
            (dynamic zone) =>
                PlannerZone.fromJson(zone as Map<String, dynamic>),
          )
          .toList(),
      eventMarkers: (json['eventMarkers'] as List<dynamic>? ?? const [])
          .map(
            (dynamic event) =>
                PlannerEventMarker.fromJson(event as Map<String, dynamic>),
          )
          .toList(),
      eventZones: (json['eventZones'] as List<dynamic>? ?? const [])
          .map(
            (dynamic event) =>
                PlannerEventZone.fromJson(event as Map<String, dynamic>),
          )
          .toList(),
      constraintZones: (json['constraintZones'] as List<dynamic>? ?? const [])
          .map(
            (dynamic zone) =>
                PlannerConstraintZone.fromJson(zone as Map<String, dynamic>),
          )
          .toList(),
      startPoseConstraintProfile: PlannerPointConstraintProfile.fromJson(
        json['startPoseConstraintProfile'] as Map<String, dynamic>?,
      ),
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map(
            (dynamic step) =>
                PlannerStep.fromJson(step as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  static PlannerAuto sample() {
    return PlannerAuto(
      id: 'hub-cycle-upper',
      name: 'Hub Cycle Upper',
      folder: 'Cycle Autos',
      updatedAt: DateTime.now(),
      startPose: const PlannerPose(
        xMeters: 1.55,
        yMeters: 5.75,
        headingDeg: 180,
      ),
      settings: const PlannerSettings(),
      customZones: const <PlannerZone>[
        PlannerZone(
          id: 'hub',
          label: 'Hub',
          xMinMeters: 3.55,
          yMinMeters: 2.72,
          xMaxMeters: 5.72,
          yMaxMeters: 5.33,
          locked: true,
        ),
      ],
      eventMarkers: const <PlannerEventMarker>[
        PlannerEventMarker(
          id: 'marker-1',
          name: 'Spin Intake',
          targetType: PlannerEventMarkerTargetType.stepAnchor,
          stepIndex: 0,
          commandId: 'cmd-intake',
        ),
        PlannerEventMarker(
          id: 'marker-2',
          name: 'Prep Shot',
          targetType: PlannerEventMarkerTargetType.routeWaypoint,
          stepIndex: 1,
          routeWaypointIndex: 1,
          commandId: 'cmd-score',
        ),
      ],
      eventZones: const <PlannerEventZone>[
        PlannerEventZone(
          id: 'zone-1',
          name: 'Collect Window',
          xMinMeters: 1.12,
          yMinMeters: 5.18,
          xMaxMeters: 2.38,
          yMaxMeters: 6.3,
          enterCommandId: 'cmd-intake',
          activeCommandId: 'cmd-intake',
          colorHex: '#39D98A',
        ),
      ],
      constraintZones: const <PlannerConstraintZone>[
        PlannerConstraintZone(
          id: 'constraint-1',
          name: 'Approach Slowdown',
          startProgress: 0.62,
          endProgress: 0.96,
          maxVelocityMps: 2.3,
          maxAccelerationMpsSq: 1.9,
          constraintFactor: 0.55,
        ),
      ],
      steps: const <PlannerStep>[
        PlannerStep(
          id: 'step-1',
          label: 'Depot Intake',
          group: 'DEPOT',
          requestedState: RequestedState.intaking,
          pose: PlannerPose(xMeters: 1.82, yMeters: 5.92, headingDeg: 180),
          routeWaypoints: <PlannerWaypoint>[
            PlannerWaypoint(
              pose: PlannerPose(xMeters: 1.44, yMeters: 5.38, headingDeg: 180),
            ),
          ],
          commandId: 'cmd-intake',
          commandName: 'Rear Intake',
        ),
        PlannerStep(
          id: 'step-2',
          label: 'Hub Left',
          group: 'HUB',
          requestedState: RequestedState.shooting,
          pose: PlannerPose(xMeters: 4.61, yMeters: 5.48, headingDeg: -90),
          routeWaypoints: <PlannerWaypoint>[
            PlannerWaypoint(
              pose: PlannerPose(xMeters: 2.7, yMeters: 5.66, headingDeg: 0),
            ),
            PlannerWaypoint(
              pose: PlannerPose(xMeters: 3.88, yMeters: 5.66, headingDeg: -60),
              type: PlannerWaypointType.pose,
            ),
          ],
          commandId: 'cmd-score',
          commandName: 'Shoot Cycle',
          waitSeconds: 0.25,
        ),
      ],
    );
  }
}

class PlannerPackage {
  const PlannerPackage({
    required this.version,
    required this.generator,
    required this.autos,
    required this.commandProfiles,
    this.globalStartPoses = const <PlannerNamedPose>[],
    this.globalVariables = const <PlannerNamedValue>[],
  });

  final String version;
  final String generator;
  final List<PlannerAuto> autos;
  final List<PlannerCommandProfile> commandProfiles;
  final List<PlannerNamedPose> globalStartPoses;
  final List<PlannerNamedValue> globalVariables;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'generator': generator,
    'commandProfiles': commandProfiles
        .map((PlannerCommandProfile command) => command.toJson())
        .toList(),
    'globalStartPoses': globalStartPoses
        .map((PlannerNamedPose pose) => pose.toJson())
        .toList(),
    'globalVariables': globalVariables
        .map((PlannerNamedValue value) => value.toJson())
        .toList(),
    'autos': autos.map((auto) => auto.toJson()).toList(),
  };

  String prettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  static PlannerPackage sample() {
    return PlannerPackage(
      version: '2026.1',
      generator: 'PathPlanA',
      commandProfiles: defaultCommandProfiles(),
      globalStartPoses: const <PlannerNamedPose>[
        PlannerNamedPose(
          id: 'start-upper-left',
          name: 'Upper Left Start',
          pose: PlannerPose(xMeters: 1.55, yMeters: 5.75, headingDeg: 180),
        ),
        PlannerNamedPose(
          id: 'start-lower-left',
          name: 'Lower Left Start',
          pose: PlannerPose(xMeters: 1.10, yMeters: 1.08, headingDeg: 180),
        ),
      ],
      globalVariables: const <PlannerNamedValue>[
        PlannerNamedValue(
          id: 'default-intake-approach',
          name: 'Default Intake Approach',
          value: 0.55,
          unit: 'm',
        ),
        PlannerNamedValue(
          id: 'default-shot-buffer',
          name: 'Default Shot Buffer',
          value: 0.25,
          unit: 's',
        ),
      ],
      autos: <PlannerAuto>[
        PlannerAuto.sample(),
        PlannerAuto.sample().copyWith(
          id: 'hub-cycle-lower',
          name: 'Hub Cycle Lower',
          folder: 'Cycle Autos',
          startPose: const PlannerPose(
            xMeters: 1.1,
            yMeters: 1.08,
            headingDeg: 180,
          ),
          steps: const <PlannerStep>[
            PlannerStep(
              id: 'step-1b',
              label: 'Outpost Intake',
              group: 'OUTPOST',
              requestedState: RequestedState.intaking,
              pose: PlannerPose(xMeters: 1.24, yMeters: 0.82, headingDeg: 180),
              routeWaypoints: <PlannerWaypoint>[
                PlannerWaypoint(
                  pose: PlannerPose(
                    xMeters: 1.68,
                    yMeters: 1.18,
                    headingDeg: 180,
                  ),
                ),
              ],
            ),
            PlannerStep(
              id: 'step-2b',
              label: 'Hub Right',
              group: 'HUB',
              requestedState: RequestedState.shooting,
              pose: PlannerPose(xMeters: 4.61, yMeters: 2.58, headingDeg: 90),
              routeWaypoints: <PlannerWaypoint>[
                PlannerWaypoint(
                  pose: PlannerPose(xMeters: 2.46, yMeters: 2.1, headingDeg: 0),
                ),
                PlannerWaypoint(
                  pose: PlannerPose(
                    xMeters: 3.92,
                    yMeters: 2.26,
                    headingDeg: 50,
                  ),
                  type: PlannerWaypointType.pose,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static PlannerPackage fromJsonString(String raw) {
    final dynamic parsed = jsonDecode(raw);
    if (parsed is List<dynamic>) {
      return PlannerPackage(
        version: '2026.1',
        generator: 'Imported',
        commandProfiles: defaultCommandProfiles(),
        globalStartPoses: const <PlannerNamedPose>[],
        globalVariables: const <PlannerNamedValue>[],
        autos: parsed
            .map(
              (dynamic auto) =>
                  PlannerAuto.fromJson(auto as Map<String, dynamic>),
            )
            .toList(),
      );
    }
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException(
        'Planner package must be an object or an array.',
      );
    }
    final List<PlannerCommandProfile> importedProfiles =
        (parsed['commandProfiles'] as List<dynamic>? ?? const [])
            .map(
              (dynamic command) => PlannerCommandProfile.fromJson(
                command as Map<String, dynamic>,
              ),
            )
            .toList();
    return PlannerPackage(
      version: parsed['version'] as String? ?? '2026.1',
      generator: parsed['generator'] as String? ?? 'Imported',
      commandProfiles: importedProfiles.isEmpty
          ? defaultCommandProfiles()
          : importedProfiles,
      globalStartPoses:
          (parsed['globalStartPoses'] as List<dynamic>? ?? const [])
              .map(
                (dynamic pose) =>
                    PlannerNamedPose.fromJson(pose as Map<String, dynamic>),
              )
              .toList(),
      globalVariables: (parsed['globalVariables'] as List<dynamic>? ?? const [])
          .map(
            (dynamic value) =>
                PlannerNamedValue.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
      autos: (parsed['autos'] as List<dynamic>? ?? const [])
          .map(
            (dynamic auto) =>
                PlannerAuto.fromJson(auto as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class _DeployLibraryBundle {
  const _DeployLibraryBundle({
    required this.indexJson,
    required this.filesByRelativePath,
  });

  final String indexJson;
  final Map<String, String> filesByRelativePath;
}

class _PlannerWorkspaceSnapshot {
  const _PlannerWorkspaceSnapshot({
    required this.package,
    required this.selectedAutoIndex,
    required this.selectedStepIndex,
    required this.selectedWaypointRef,
    required this.startPoseSelected,
    required this.selectedSection,
  });

  final PlannerPackage package;
  final int selectedAutoIndex;
  final int? selectedStepIndex;
  final PlannerWaypointRef? selectedWaypointRef;
  final bool startPoseSelected;
  final PlannerSection selectedSection;
}

class PlannerHomePage extends StatefulWidget {
  const PlannerHomePage({super.key});

  @override
  State<PlannerHomePage> createState() => _PlannerHomePageState();
}

class _PlannerHomePageState extends State<PlannerHomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  PlannerPackage _package = PlannerPackage.sample();
  int _selectedAutoIndex = 0;
  int? _selectedStepIndex;
  PlannerWaypointRef? _selectedWaypointRef;
  bool _startPoseSelected = false;
  int? _selectedZoneIndex;
  int? _selectedMarkerIndex;
  int? _selectedEventZoneIndex;
  int? _selectedConstraintZoneIndex;
  PlannerTool _tool = PlannerTool.select;
  PlannerSection _selectedSection = PlannerSection.library;
  String _draftCommandId = 'cmd-intake';
  double _draftHeadingDeg = 180;
  late final AnimationController _previewController;
  bool _previewPlaying = false;
  double _previewProgress = 0;
  String _statusMessage = 'Ready to author autos locally.';
  String _schemaSummary = 'Loading schema...';
  String? _deployExportDirectory;
  final List<_PlannerWorkspaceSnapshot> _undoStack =
      <_PlannerWorkspaceSnapshot>[];
  final List<_PlannerWorkspaceSnapshot> _redoStack =
      <_PlannerWorkspaceSnapshot>[];

  PlannerAuto get _selectedAuto => _package.autos[_selectedAutoIndex];
  List<PlannerCommandProfile> get _commandProfiles => _package.commandProfiles;
  PlannerCommandProfile get _draftCommand =>
      _resolveCommandProfileById(_draftCommandId) ?? _commandProfiles.first;
  double get _estimatedTimeSeconds =>
      computeEstimatedTimeSeconds(_selectedAuto);

  PlannerWaypointRef? _defaultWaypointRefForAuto(PlannerAuto auto) {
    if (auto.steps.isEmpty) {
      return null;
    }
    return const PlannerWaypointRef(stepIndex: 0);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _previewController = AnimationController(vsync: this)
      ..addListener(() {
        if (!mounted) {
          return;
        }
        setState(() {
          _previewProgress = _previewController.value;
        });
      })
      ..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _previewPlaying = false;
          });
        }
      });
    _loadSchemaSummary();
    _configurePreviewAnimation();
    _loadPersistedWorkspace();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistWorkspace();
    _previewController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistWorkspace();
    }
  }

  Future<void> _loadSchemaSummary() async {
    final String raw = await rootBundle.loadString(
      'assets/contracts/pathplana_autos.schema.json',
    );
    final Map<String, dynamic> schema = jsonDecode(raw) as Map<String, dynamic>;
    setState(() {
      _schemaSummary =
          '${schema['title']} • ${(schema['\$defs'] as Map<String, dynamic>).keys.length} defs';
    });
  }

  void _setStatus(String message, {bool notify = true}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _statusMessage = message;
    });
    if (!notify) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _loadPersistedWorkspace() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? deployDirectory = prefs.getString(_deployDirectoryPrefsKey);
    String? rawWorkspace;
    if (deployDirectory != null && deployDirectory.isNotEmpty) {
      final DeployWorkspaceReadResult deployWorkspace =
          await deploy_export.readDeployWorkspace(
            targetDirectory: deployDirectory,
          );
      rawWorkspace = deployWorkspace.workspaceJson;
    }
    rawWorkspace ??= prefs.getString(_workspacePrefsKey);
    if (rawWorkspace == null || rawWorkspace.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deployExportDirectory = deployDirectory;
      });
      return;
    }
    try {
      final PlannerPackage restored = PlannerPackage.fromJsonString(rawWorkspace);
      if (!mounted || restored.autos.isEmpty) {
        return;
      }
      final int restoredAutoIndex = prefs.getInt(_selectedAutoPrefsKey) ?? 0;
      setState(() {
        _package = restored;
        _selectedAutoIndex = restoredAutoIndex.clamp(
          0,
          restored.autos.length - 1,
        );
        _selectedStepIndex = restored.autos[_selectedAutoIndex].steps.isEmpty
            ? null
            : 0;
        _selectedWaypointRef = _defaultWaypointRefForAuto(
          restored.autos[_selectedAutoIndex],
        );
        _startPoseSelected = restored.autos[_selectedAutoIndex].steps.isEmpty;
        _deployExportDirectory = deployDirectory;
        _statusMessage = deployDirectory == null || deployDirectory.isEmpty
            ? 'Restored local workspace.'
            : 'Restored local workspace. Deploy folder: $deployDirectory';
      });
      _configurePreviewAnimation();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deployExportDirectory = deployDirectory;
        _statusMessage = 'Local workspace restore failed. Kept current sample.';
      });
    }
  }

  Future<void> _persistWorkspace() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String workspaceJson = _package.prettyJson();
    await prefs.setString(_workspacePrefsKey, workspaceJson);
    await prefs.setInt(_selectedAutoPrefsKey, _selectedAutoIndex);
    if (_deployExportDirectory != null && _deployExportDirectory!.isNotEmpty) {
      await prefs.setString(_deployDirectoryPrefsKey, _deployExportDirectory!);
      await deploy_export.writeDeployWorkspace(
        targetDirectory: _deployExportDirectory!,
        workspaceJson: workspaceJson,
      );
    } else {
      await prefs.remove(_deployDirectoryPrefsKey);
    }
  }

  PlannerCommandProfile? _resolveCommandProfileById(String id) {
    for (final PlannerCommandProfile profile in _commandProfiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return null;
  }

  _PlannerWorkspaceSnapshot _createSnapshot() {
    return _PlannerWorkspaceSnapshot(
      package: PlannerPackage.fromJsonString(_package.prettyJson()),
      selectedAutoIndex: _selectedAutoIndex,
      selectedStepIndex: _selectedStepIndex,
      selectedWaypointRef: _selectedWaypointRef,
      startPoseSelected: _startPoseSelected,
      selectedSection: _selectedSection,
    );
  }

  void _pushUndoSnapshot() {
    _undoStack.add(_createSnapshot());
    if (_undoStack.length > 40) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _restoreSnapshot(_PlannerWorkspaceSnapshot snapshot, String message) {
    setState(() {
      _package = snapshot.package;
      _selectedAutoIndex = math.min(
        snapshot.selectedAutoIndex,
        snapshot.package.autos.length - 1,
      );
      final int stepCount = _package.autos[_selectedAutoIndex].steps.length;
      _selectedStepIndex = stepCount == 0 || snapshot.selectedStepIndex == null
          ? null
          : math.min(snapshot.selectedStepIndex!, stepCount - 1);
      _selectedWaypointRef = snapshot.selectedWaypointRef;
      _startPoseSelected = snapshot.startPoseSelected;
      _selectedZoneIndex = _selectedAuto.customZones.isEmpty
          ? null
          : math.min(
              _selectedZoneIndex ?? 0,
              _selectedAuto.customZones.length - 1,
            );
      _selectedMarkerIndex = _selectedAuto.eventMarkers.isEmpty
          ? null
          : math.min(
              _selectedMarkerIndex ?? 0,
              _selectedAuto.eventMarkers.length - 1,
            );
      _selectedEventZoneIndex = _selectedAuto.eventZones.isEmpty
          ? null
          : math.min(
              _selectedEventZoneIndex ?? 0,
              _selectedAuto.eventZones.length - 1,
            );
      _selectedConstraintZoneIndex = _selectedAuto.constraintZones.isEmpty
          ? null
          : math.min(
              _selectedConstraintZoneIndex ?? 0,
              _selectedAuto.constraintZones.length - 1,
            );
      _selectedSection = snapshot.selectedSection;
      _previewProgress = 0;
      _previewPlaying = false;
      _statusMessage = message;
    });
    _previewController.value = 0;
    _configurePreviewAnimation();
    _persistWorkspace();
  }

  void _undo() {
    if (_undoStack.isEmpty) {
      return;
    }
    _redoStack.add(_createSnapshot());
    _restoreSnapshot(_undoStack.removeLast(), 'Undid last change.');
  }

  void _redo() {
    if (_redoStack.isEmpty) {
      return;
    }
    _undoStack.add(_createSnapshot());
    _restoreSnapshot(_redoStack.removeLast(), 'Restored change.');
  }

  void _configurePreviewAnimation() {
    final int milliseconds = math.max(
      400,
      (_estimatedTimeSeconds * 1000).round(),
    );
    _previewController.duration = Duration(milliseconds: milliseconds);
  }

  void _togglePreviewPlayback() {
    _configurePreviewAnimation();
    if (_previewPlaying) {
      _previewController.stop();
      setState(() {
        _previewPlaying = false;
      });
      return;
    }
    if (_previewProgress >= 0.999) {
      _previewController.value = 0;
    }
    _previewController.forward(from: _previewController.value);
    setState(() {
      _previewPlaying = true;
    });
  }

  void _setPreviewProgress(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    _previewController.stop();
    _previewController.value = clamped;
    setState(() {
      _previewPlaying = false;
      _previewProgress = clamped;
    });
  }

  Future<void> _importPackage() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'JSON', extensions: <String>['json']),
      ],
    );
    if (file == null) {
      _setStatus('Import canceled.');
      return;
    }
    try {
      final String contents = await file.readAsString();
      final PlannerPackage imported = PlannerPackage.fromJsonString(contents);
    if (imported.autos.isEmpty) {
      _setStatus('Import skipped. No autos found.');
      return;
    }
    _pushUndoSnapshot();
    setState(() {
      _package = imported;
      _selectedAutoIndex = 0;
      _selectedStepIndex = imported.autos.first.steps.isNotEmpty ? 0 : null;
      _selectedWaypointRef = _defaultWaypointRefForAuto(imported.autos.first);
      _startPoseSelected = imported.autos.first.steps.isEmpty;
      _selectedZoneIndex = imported.autos.first.customZones.isNotEmpty
          ? 0
          : null;
      _selectedMarkerIndex = imported.autos.first.eventMarkers.isNotEmpty
          ? 0
          : null;
      _selectedEventZoneIndex = imported.autos.first.eventZones.isNotEmpty
          ? 0
          : null;
      _selectedConstraintZoneIndex =
          imported.autos.first.constraintZones.isNotEmpty ? 0 : null;
      _draftCommandId = imported.commandProfiles.first.id;
      _previewProgress = 0;
      _previewPlaying = false;
      _statusMessage =
          'Imported ${imported.autos.length} auto${imported.autos.length == 1 ? '' : 's'} from ${file.name}.';
    });
    _previewController.value = 0;
    _configurePreviewAnimation();
    _persistWorkspace();
    _setStatus(
      'Imported ${imported.autos.length} auto${imported.autos.length == 1 ? '' : 's'} from ${file.name}.',
    );
    } catch (error) {
      _setStatus('Import failed: $error');
    }
  }

  Future<void> _exportPackage() async {
    try {
      final FileSaveLocation? location = await getSaveLocation(
      suggestedName: 'pathplana_autos.json',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'JSON', extensions: <String>['json']),
      ],
    );
    final String json = _package.prettyJson();
    if (location == null) {
      await Clipboard.setData(ClipboardData(text: json));
      _setStatus('Export canceled. JSON copied to clipboard instead.');
      return;
    }
    final Uint8List fileData = Uint8List.fromList(utf8.encode(json));
    final XFile file = XFile.fromData(
      fileData,
      name: 'pathplana_autos.json',
      mimeType: 'application/json',
    );
    await file.saveTo(location.path);
    _setStatus('Exported planner package.');
    _persistWorkspace();
    } catch (error) {
      _setStatus('Export failed: $error');
    }
  }

  Future<void> _chooseDeployFolder() async {
    if (kIsWeb) {
      _setStatus('Deploy folder selection is available on desktop builds only.');
      return;
    }
    try {
      final String? directory = await getDirectoryPath(
      confirmButtonText: 'Use Deploy Folder',
      initialDirectory: _deployExportDirectory,
    );
    if (directory == null || directory.isEmpty) {
      _setStatus('Deploy folder selection canceled.');
      return;
    }
    setState(() {
      _deployExportDirectory = directory;
      _statusMessage = 'Deploy folder set to $directory';
    });
    final DeployWorkspaceReadResult deployWorkspace =
        await deploy_export.readDeployWorkspace(targetDirectory: directory);
    if (deployWorkspace.workspaceJson != null &&
        deployWorkspace.workspaceJson!.isNotEmpty) {
      try {
        final PlannerPackage restored = PlannerPackage.fromJsonString(
          deployWorkspace.workspaceJson!,
        );
        if (restored.autos.isNotEmpty) {
      setState(() {
        _package = restored;
        _selectedAutoIndex = 0;
            _selectedStepIndex = restored.autos.first.steps.isEmpty ? null : 0;
            _selectedWaypointRef = _defaultWaypointRefForAuto(
              restored.autos.first,
            );
            _startPoseSelected = restored.autos.first.steps.isEmpty;
            _statusMessage = 'Loaded workspace from deploy folder $directory';
          });
          _setStatus('Loaded workspace from deploy folder $directory');
        }
      } catch (_) {
        _setStatus(
          'Deploy folder set, but workspace.json could not be parsed.',
        );
      }
    }
    _persistWorkspace();
    if (deployWorkspace.workspaceJson == null ||
        deployWorkspace.workspaceJson!.isEmpty) {
      _setStatus('Deploy folder set to $directory');
    }
    } catch (error) {
      _setStatus('Could not open folder picker: $error');
    }
  }

  Future<void> _exportDeployLibrary() async {
    if (kIsWeb) {
      _setStatus(
        'Deploy export writes folders on desktop builds only. Use PathPlanA on macOS to export directly into deploy.',
      );
      return;
    }
    try {
      String? directory = _deployExportDirectory;
      if (directory == null || directory.isEmpty) {
        directory = await getDirectoryPath(
        confirmButtonText: 'Export Deploy Library',
        initialDirectory: '.',
      );
      if (directory == null || directory.isEmpty) {
        _setStatus('Deploy export canceled.');
        return;
      }
      _deployExportDirectory = directory;
    }

    final _DeployLibraryBundle bundle = _buildDeployLibraryBundle();
    final DeployExportResult result = await deploy_export.writeDeployLibrary(
      targetDirectory: directory,
      indexJson: bundle.indexJson,
      filesByRelativePath: bundle.filesByRelativePath,
    );
    setState(() {
      _statusMessage = result.message;
    });
    _persistWorkspace();
    _setStatus(result.message);
    } catch (error) {
      _setStatus('Deploy export failed: $error');
    }
  }

  _DeployLibraryBundle _buildDeployLibraryBundle() {
    final JsonEncoder encoder = const JsonEncoder.withIndent('  ');
    final Map<String, String> filesByRelativePath = <String, String>{};
    final List<Map<String, dynamic>> manifestAutos = <Map<String, dynamic>>[];
    final Set<String> usedFolders = <String>{};

    for (int index = 0; index < _package.autos.length; index += 1) {
      final PlannerAuto auto = _package.autos[index];
      final String folderName = _uniqueAutoFolderName(auto, usedFolders, index);
      final String relativePath = '$folderName/auto.json';
      filesByRelativePath[relativePath] = encoder.convert(auto.toJson());
      manifestAutos.add(<String, dynamic>{
        'id': auto.id,
        'name': auto.name,
        'folder': auto.folder,
        'relativePath': relativePath,
        'updatedAt': auto.updatedAt.millisecondsSinceEpoch,
      });
    }

    final String indexJson = encoder.convert(<String, dynamic>{
      'version': _package.version,
      'generator': _package.generator,
      'autos': manifestAutos,
    });
    filesByRelativePath['workspace.json'] = _package.prettyJson();
    return _DeployLibraryBundle(
      indexJson: indexJson,
      filesByRelativePath: filesByRelativePath,
    );
  }

  String _uniqueAutoFolderName(
    PlannerAuto auto,
    Set<String> usedFolders,
    int fallbackIndex,
  ) {
    final String baseName = _sanitizeDeployPathSegment(auto.id, fallbackIndex);
    String candidate = baseName;
    int suffix = 2;
    while (usedFolders.contains(candidate)) {
      candidate = '$baseName-$suffix';
      suffix += 1;
    }
    usedFolders.add(candidate);
    return candidate;
  }

  String _sanitizeDeployPathSegment(String value, int fallbackIndex) {
    final String normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return normalized.isEmpty ? 'auto-${fallbackIndex + 1}' : normalized;
  }

  void _createAuto() {
    _pushUndoSnapshot();
    final DateTime now = DateTime.now();
    final PlannerAuto auto = PlannerAuto.sample().copyWith(
      id: 'auto-${now.millisecondsSinceEpoch}',
      name: 'New Auto ${_package.autos.length + 1}',
      folder: 'Autos',
      updatedAt: now,
      steps: const <PlannerStep>[],
    );
    setState(() {
      _package = PlannerPackage(
        version: _package.version,
        generator: _package.generator,
        autos: <PlannerAuto>[..._package.autos, auto],
        commandProfiles: _package.commandProfiles,
        globalStartPoses: _package.globalStartPoses,
        globalVariables: _package.globalVariables,
      );
      _selectedAutoIndex = _package.autos.length - 1;
      _selectedStepIndex = null;
      _selectedWaypointRef = null;
      _startPoseSelected = true;
      _selectedZoneIndex = auto.customZones.isNotEmpty ? 0 : null;
      _selectedMarkerIndex = auto.eventMarkers.isNotEmpty ? 0 : null;
      _selectedEventZoneIndex = auto.eventZones.isNotEmpty ? 0 : null;
      _selectedConstraintZoneIndex = auto.constraintZones.isNotEmpty ? 0 : null;
      _selectedSection = PlannerSection.editor;
      _previewProgress = 0;
      _previewPlaying = false;
      _statusMessage = 'Created ${auto.name}.';
    });
    _previewController.value = 0;
    _configurePreviewAnimation();
    _persistWorkspace();
  }

  void _deleteSelectedAuto() {
    if (_package.autos.length == 1) {
      return;
    }
    _pushUndoSnapshot();
    final List<PlannerAuto> autos = <PlannerAuto>[..._package.autos]
      ..removeAt(_selectedAutoIndex);
    setState(() {
      _package = PlannerPackage(
        version: _package.version,
        generator: _package.generator,
        autos: autos,
        commandProfiles: _package.commandProfiles,
        globalStartPoses: _package.globalStartPoses,
        globalVariables: _package.globalVariables,
      );
      _selectedAutoIndex = math.min(_selectedAutoIndex, autos.length - 1);
      _selectedStepIndex = autos[_selectedAutoIndex].steps.isEmpty ? null : 0;
      _selectedWaypointRef = _defaultWaypointRefForAuto(
        autos[_selectedAutoIndex],
      );
      _startPoseSelected = autos[_selectedAutoIndex].steps.isEmpty;
      _selectedZoneIndex = autos[_selectedAutoIndex].customZones.isEmpty
          ? null
          : 0;
      _selectedMarkerIndex = autos[_selectedAutoIndex].eventMarkers.isEmpty
          ? null
          : 0;
      _selectedEventZoneIndex = autos[_selectedAutoIndex].eventZones.isEmpty
          ? null
          : 0;
      _selectedConstraintZoneIndex =
          autos[_selectedAutoIndex].constraintZones.isEmpty ? null : 0;
      _previewProgress = 0;
      _previewPlaying = false;
      _statusMessage = 'Deleted selected auto.';
    });
    _previewController.value = 0;
    _configurePreviewAnimation();
    _persistWorkspace();
  }

  void _selectAuto(int index) {
    setState(() {
      _selectedAutoIndex = index;
      _selectedStepIndex = _selectedAuto.steps.isEmpty ? null : 0;
      _selectedWaypointRef = _defaultWaypointRefForAuto(_selectedAuto);
      _startPoseSelected = _selectedAuto.steps.isEmpty;
      _selectedZoneIndex = _selectedAuto.customZones.isEmpty ? null : 0;
      _selectedMarkerIndex = _selectedAuto.eventMarkers.isEmpty ? null : 0;
      _selectedEventZoneIndex = _selectedAuto.eventZones.isEmpty ? null : 0;
      _selectedConstraintZoneIndex = _selectedAuto.constraintZones.isEmpty
          ? null
          : 0;
      _selectedSection = PlannerSection.editor;
      _previewProgress = 0;
      _previewPlaying = false;
      _statusMessage = 'Previewing ${_selectedAuto.name}.';
    });
    _previewController.value = 0;
    _configurePreviewAnimation();
    _persistWorkspace();
  }

  void _updateSelectedAuto(PlannerAuto nextAuto, {bool recordHistory = true}) {
    if (recordHistory) {
      _pushUndoSnapshot();
    }
    final List<PlannerAuto> autos = <PlannerAuto>[..._package.autos];
    autos[_selectedAutoIndex] = nextAuto.copyWith(updatedAt: DateTime.now());
    setState(() {
      _package = PlannerPackage(
        version: _package.version,
        generator: _package.generator,
        autos: autos,
        commandProfiles: _package.commandProfiles,
        globalStartPoses: _package.globalStartPoses,
        globalVariables: _package.globalVariables,
      );
    });
    _configurePreviewAnimation();
    _persistWorkspace();
  }

  void _handleCanvasTap(Offset fieldPose) {
    final PlannerPose pose = PlannerPose(
      xMeters: fieldPose.dx.clamp(0, fieldLengthMeters),
      yMeters: fieldPose.dy.clamp(0, fieldWidthMeters),
      headingDeg: _draftHeadingDeg,
    );
    switch (_tool) {
      case PlannerTool.select:
        _pickNearestStep(pose);
      case PlannerTool.startPose:
        _updateSelectedAuto(_selectedAuto.copyWith(startPose: pose));
        setState(() {
          _startPoseSelected = true;
          _selectedWaypointRef = null;
          _selectedStepIndex = null;
          _statusMessage = 'Updated start pose.';
        });
      case PlannerTool.addStep:
        final List<PlannerStep> steps = <PlannerStep>[
          ..._selectedAuto.steps,
          PlannerStep(
            id: 'step-${DateTime.now().microsecondsSinceEpoch}',
            label: 'Step ${_selectedAuto.steps.length + 1}',
            requestedState: RequestedState.fromToken(
              _draftCommand.requestedState,
            ),
            pose: pose,
            group: 'LANE',
            commandId: _draftCommand.id,
            commandName: _draftCommand.name,
          ),
        ];
        _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
        setState(() {
          _selectedStepIndex = steps.length - 1;
          _selectedWaypointRef = PlannerWaypointRef(
            stepIndex: steps.length - 1,
          );
          _startPoseSelected = false;
          _statusMessage = 'Added ${_draftCommand.name} step.';
        });
      case PlannerTool.addWaypoint:
        if (_selectedStepIndex == null) {
          setState(() {
            _statusMessage = 'Select a step before adding waypoints.';
          });
          return;
        }
        final PlannerStep step = _selectedAuto.steps[_selectedStepIndex!];
        final List<PlannerStep> steps = <PlannerStep>[..._selectedAuto.steps];
        steps[_selectedStepIndex!] = step.copyWith(
          routeWaypoints: <PlannerWaypoint>[
            ...step.routeWaypoints,
            PlannerWaypoint(pose: pose),
          ],
        );
        _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
        setState(() {
          _selectedWaypointRef = PlannerWaypointRef(
            stepIndex: _selectedStepIndex!,
            routeWaypointIndex:
                steps[_selectedStepIndex!].routeWaypoints.length - 1,
          );
          _startPoseSelected = false;
          _statusMessage = 'Added waypoint to ${step.label}.';
        });
    }
  }

  void _pickNearestStep(PlannerPose pose) {
    if (_selectedAuto.steps.isEmpty) {
      setState(() {
        _startPoseSelected = true;
        _selectedWaypointRef = null;
        _selectedStepIndex = null;
        _statusMessage = 'Selected start pose.';
      });
      return;
    }
    final double startDistance = math.sqrt(
      math.pow(_selectedAuto.startPose.xMeters - pose.xMeters, 2) +
          math.pow(_selectedAuto.startPose.yMeters - pose.yMeters, 2),
    );
    int nearestIndex = 0;
    double nearestDistance = startDistance;
    for (int i = 0; i < _selectedAuto.steps.length; i += 1) {
      final PlannerStep step = _selectedAuto.steps[i];
      final double distance = math.sqrt(
        math.pow(step.pose.xMeters - pose.xMeters, 2) +
            math.pow(step.pose.yMeters - pose.yMeters, 2),
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }
    setState(() {
      if (startDistance <= nearestDistance) {
        _startPoseSelected = true;
        _selectedStepIndex = null;
        _selectedWaypointRef = null;
        _statusMessage = 'Selected start pose.';
        return;
      }
      _startPoseSelected = false;
      _selectedStepIndex = nearestIndex;
      _selectedWaypointRef = PlannerWaypointRef(stepIndex: nearestIndex);
      _statusMessage = 'Selected ${_selectedAuto.steps[nearestIndex].label}.';
    });
  }

  void _updateCommandProfiles(List<PlannerCommandProfile> profiles) {
    _pushUndoSnapshot();
    setState(() {
      _package = PlannerPackage(
        version: _package.version,
        generator: _package.generator,
        autos: _package.autos,
        commandProfiles: profiles,
        globalStartPoses: _package.globalStartPoses,
        globalVariables: _package.globalVariables,
      );
      if (!profiles.any(
        (PlannerCommandProfile profile) => profile.id == _draftCommandId,
      )) {
        _draftCommandId = profiles.first.id;
      }
    });
    _persistWorkspace();
  }

  void _addZone() {
    _pushUndoSnapshot();
    final List<PlannerZone> zones = <PlannerZone>[
      ..._selectedAuto.customZones,
      PlannerZone(
        id: 'zone-${DateTime.now().microsecondsSinceEpoch}',
        label: 'Keep-Out ${_selectedAuto.customZones.length + 1}',
        xMinMeters: 6.2,
        yMinMeters: 2.2,
        xMaxMeters: 7.2,
        yMaxMeters: 3.2,
      ),
    ];
    _updateSelectedAuto(
      _selectedAuto.copyWith(customZones: zones),
      recordHistory: false,
    );
    setState(() {
      _selectedZoneIndex = zones.length - 1;
      _selectedSection = PlannerSection.obstacles;
      _statusMessage = 'Added a new keep-out box.';
    });
  }

  void _updateZone(int index, PlannerZone zone) {
    _pushUndoSnapshot();
    final List<PlannerZone> zones = <PlannerZone>[..._selectedAuto.customZones];
    zones[index] = clampPlannerZoneToField(zone);
    _updateSelectedAuto(
      _selectedAuto.copyWith(customZones: zones),
      recordHistory: false,
    );
  }

  void _deleteZone(int index) {
    _pushUndoSnapshot();
    final List<PlannerZone> zones = <PlannerZone>[..._selectedAuto.customZones]
      ..removeAt(index);
    _updateSelectedAuto(
      _selectedAuto.copyWith(customZones: zones),
      recordHistory: false,
    );
    setState(() {
      _selectedZoneIndex = zones.isEmpty
          ? null
          : math.min(index, zones.length - 1);
    });
  }

  void _addEventMarker() {
    _pushUndoSnapshot();
    final PlannerEventMarker marker;
    if (_startPoseSelected || _selectedWaypointRef == null) {
      marker = PlannerEventMarker(
        id: 'marker-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Marker ${_selectedAuto.eventMarkers.length + 1}',
        targetType: PlannerEventMarkerTargetType.startPose,
        commandId: _draftCommand.id,
      );
    } else if (_selectedWaypointRef!.routeWaypointIndex == null) {
      marker = PlannerEventMarker(
        id: 'marker-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Marker ${_selectedAuto.eventMarkers.length + 1}',
        targetType: PlannerEventMarkerTargetType.stepAnchor,
        stepIndex: _selectedWaypointRef!.stepIndex,
        commandId: _draftCommand.id,
      );
    } else {
      marker = PlannerEventMarker(
        id: 'marker-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Marker ${_selectedAuto.eventMarkers.length + 1}',
        targetType: PlannerEventMarkerTargetType.routeWaypoint,
        stepIndex: _selectedWaypointRef!.stepIndex,
        routeWaypointIndex: _selectedWaypointRef!.routeWaypointIndex,
        commandId: _draftCommand.id,
      );
    }
    final List<PlannerEventMarker> markers = <PlannerEventMarker>[
      ..._selectedAuto.eventMarkers,
      marker,
    ];
    _updateSelectedAuto(
      _selectedAuto.copyWith(eventMarkers: markers),
      recordHistory: false,
    );
    setState(() {
      _selectedMarkerIndex = markers.length - 1;
      _selectedSection = PlannerSection.events;
    });
  }

  void _updateSelectedPointConstraintProfile(
    PlannerPointConstraintProfile profile,
  ) {
    if (_startPoseSelected || _selectedWaypointRef == null) {
      _updateSelectedAuto(
        _selectedAuto.copyWith(startPoseConstraintProfile: profile),
      );
      return;
    }
    final PlannerWaypointRef ref = _selectedWaypointRef!;
    final List<PlannerStep> steps = <PlannerStep>[..._selectedAuto.steps];
    if (ref.routeWaypointIndex == null) {
      steps[ref.stepIndex] = steps[ref.stepIndex].copyWith(
        anchorConstraintProfile: profile,
      );
    } else {
      final List<PlannerWaypoint> waypoints = <PlannerWaypoint>[
        ...steps[ref.stepIndex].routeWaypoints,
      ];
      waypoints[ref.routeWaypointIndex!] = waypoints[ref.routeWaypointIndex!]
          .copyWith(constraintProfile: profile);
      steps[ref.stepIndex] = steps[ref.stepIndex].copyWith(
        routeWaypoints: waypoints,
      );
    }
    _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
  }

  void _selectStartPose() {
    setState(() {
      _startPoseSelected = true;
      _selectedStepIndex = null;
      _selectedWaypointRef = null;
    });
  }

  void _moveStartPose(PlannerPose pose) {
    _updateSelectedAuto(
      _selectedAuto.copyWith(startPose: clampPoseToField(pose)),
      recordHistory: false,
    );
    setState(() {
      _startPoseSelected = true;
      _selectedWaypointRef = null;
      _selectedStepIndex = null;
    });
  }

  void _deleteSelectedPoint() {
    if (_startPoseSelected || _selectedWaypointRef == null) {
      setState(() {
        _statusMessage = 'Start pose cannot be deleted.';
      });
      return;
    }
    final PlannerWaypointRef ref = _selectedWaypointRef!;
    final List<PlannerStep> steps = <PlannerStep>[..._selectedAuto.steps];
    if (ref.routeWaypointIndex == null) {
      steps.removeAt(ref.stepIndex);
      _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
      setState(() {
        if (steps.isEmpty) {
          _startPoseSelected = true;
          _selectedStepIndex = null;
          _selectedWaypointRef = null;
        } else {
          final int nextIndex = math.min(ref.stepIndex, steps.length - 1);
          _startPoseSelected = false;
          _selectedStepIndex = nextIndex;
          _selectedWaypointRef = PlannerWaypointRef(stepIndex: nextIndex);
        }
        _statusMessage = 'Deleted selected anchor step.';
      });
      return;
    }
    final List<PlannerWaypoint> waypoints = <PlannerWaypoint>[
      ...steps[ref.stepIndex].routeWaypoints,
    ]..removeAt(ref.routeWaypointIndex!);
    steps[ref.stepIndex] = steps[ref.stepIndex].copyWith(
      routeWaypoints: waypoints,
    );
    _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
    setState(() {
      _startPoseSelected = false;
      _selectedStepIndex = ref.stepIndex;
      _selectedWaypointRef = waypoints.isEmpty
          ? PlannerWaypointRef(stepIndex: ref.stepIndex)
          : PlannerWaypointRef(
              stepIndex: ref.stepIndex,
              routeWaypointIndex: math.min(
                ref.routeWaypointIndex!,
                waypoints.length - 1,
              ),
            );
      _statusMessage = 'Deleted selected waypoint.';
    });
  }

  void _applyNamedPoseToSelection(PlannerPose pose) {
    if (_startPoseSelected || _selectedWaypointRef == null) {
      _moveStartPose(pose);
      return;
    }
    final PlannerWaypointRef ref = _selectedWaypointRef!;
    final List<PlannerStep> steps = <PlannerStep>[..._selectedAuto.steps];
    if (ref.routeWaypointIndex == null) {
      steps[ref.stepIndex] = steps[ref.stepIndex].copyWith(pose: pose);
    } else {
      final List<PlannerWaypoint> waypoints = <PlannerWaypoint>[
        ...steps[ref.stepIndex].routeWaypoints,
      ];
      waypoints[ref.routeWaypointIndex!] = waypoints[ref.routeWaypointIndex!]
          .copyWith(pose: pose);
      steps[ref.stepIndex] = steps[ref.stepIndex].copyWith(
        routeWaypoints: waypoints,
      );
    }
    _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
  }

  void _saveSelectedPointAsNamedPose() {
    final PlannerPose pose = resolvePointPose(
      _selectedAuto,
      startPoseSelected: _startPoseSelected,
      ref: _selectedWaypointRef,
    );
    final String baseName = _startPoseSelected
        ? 'Start Pose'
        : _selectedWaypointRef?.routeWaypointIndex == null
        ? (_selectedStepIndex == null
              ? 'Anchor'
              : '${_selectedAuto.steps[_selectedStepIndex!].label} Anchor')
        : (_selectedStepIndex == null
              ? 'Waypoint'
              : '${_selectedAuto.steps[_selectedStepIndex!].label} Waypoint ${(_selectedWaypointRef?.routeWaypointIndex ?? 0) + 1}');
    final List<PlannerNamedPose> poses = <PlannerNamedPose>[
      ..._package.globalStartPoses,
      PlannerNamedPose(
        id: 'pose-${DateTime.now().microsecondsSinceEpoch}',
        name: baseName,
        pose: pose,
      ),
    ];
    setState(() {
      _package = PlannerPackage(
        version: _package.version,
        generator: _package.generator,
        autos: _package.autos,
        commandProfiles: _package.commandProfiles,
        globalStartPoses: poses,
        globalVariables: _package.globalVariables,
      );
      _statusMessage = 'Saved $baseName as a pose variable.';
    });
    _persistWorkspace();
  }

  void _updateEventMarker(int index, PlannerEventMarker marker) {
    _pushUndoSnapshot();
    final List<PlannerEventMarker> markers = <PlannerEventMarker>[
      ..._selectedAuto.eventMarkers,
    ];
    markers[index] = marker;
    _updateSelectedAuto(
      _selectedAuto.copyWith(eventMarkers: markers),
      recordHistory: false,
    );
  }

  void _deleteEventMarker(int index) {
    _pushUndoSnapshot();
    final List<PlannerEventMarker> markers = <PlannerEventMarker>[
      ..._selectedAuto.eventMarkers,
    ]..removeAt(index);
    _updateSelectedAuto(
      _selectedAuto.copyWith(eventMarkers: markers),
      recordHistory: false,
    );
    setState(() {
      _selectedMarkerIndex = markers.isEmpty
          ? null
          : math.min(index, markers.length - 1);
    });
  }

  void _addEventZone() {
    _pushUndoSnapshot();
    final List<PlannerEventZone> zones = <PlannerEventZone>[
      ..._selectedAuto.eventZones,
      PlannerEventZone(
        id: 'event-zone-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Event Zone ${_selectedAuto.eventZones.length + 1}',
        xMinMeters: 1.35,
        yMinMeters: 2.1,
        xMaxMeters: 2.65,
        yMaxMeters: 3.55,
        enterCommandId: _draftCommand.id,
        activeCommandId: _draftCommand.id,
      ),
    ];
    _updateSelectedAuto(
      _selectedAuto.copyWith(eventZones: zones),
      recordHistory: false,
    );
    setState(() {
      _selectedEventZoneIndex = zones.length - 1;
      _selectedSection = PlannerSection.events;
    });
  }

  void _updateEventZone(int index, PlannerEventZone zone) {
    _pushUndoSnapshot();
    final List<PlannerEventZone> zones = <PlannerEventZone>[
      ..._selectedAuto.eventZones,
    ];
    zones[index] = clampEventZoneToField(zone);
    _updateSelectedAuto(
      _selectedAuto.copyWith(eventZones: zones),
      recordHistory: false,
    );
  }

  void _deleteEventZone(int index) {
    _pushUndoSnapshot();
    final List<PlannerEventZone> zones = <PlannerEventZone>[
      ..._selectedAuto.eventZones,
    ]..removeAt(index);
    _updateSelectedAuto(
      _selectedAuto.copyWith(eventZones: zones),
      recordHistory: false,
    );
    setState(() {
      _selectedEventZoneIndex = zones.isEmpty
          ? null
          : math.min(index, zones.length - 1);
    });
  }

  void _addConstraintZone() {
    _pushUndoSnapshot();
    final List<PlannerConstraintZone> zones = <PlannerConstraintZone>[
      ..._selectedAuto.constraintZones,
      PlannerConstraintZone(
        id: 'constraint-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Constraint ${_selectedAuto.constraintZones.length + 1}',
        startProgress: 0.55,
        endProgress: 0.85,
      ),
    ];
    _updateSelectedAuto(
      _selectedAuto.copyWith(constraintZones: zones),
      recordHistory: false,
    );
    setState(() {
      _selectedConstraintZoneIndex = zones.length - 1;
      _selectedSection = PlannerSection.editor;
    });
  }

// ignore: unused_element
  void _updateConstraintZone(int index, PlannerConstraintZone zone) {
    _pushUndoSnapshot();
    final List<PlannerConstraintZone> zones = <PlannerConstraintZone>[
      ..._selectedAuto.constraintZones,
    ];
    zones[index] = zone;
    _updateSelectedAuto(
      _selectedAuto.copyWith(constraintZones: zones),
      recordHistory: false,
    );
  }

// ignore: unused_element
  void _deleteConstraintZone(int index) {
    _pushUndoSnapshot();
    final List<PlannerConstraintZone> zones = <PlannerConstraintZone>[
      ..._selectedAuto.constraintZones,
    ]..removeAt(index);
    _updateSelectedAuto(
      _selectedAuto.copyWith(constraintZones: zones),
      recordHistory: false,
    );
    setState(() {
      _selectedConstraintZoneIndex = zones.isEmpty
          ? null
          : math.min(index, zones.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF11161F),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF273246)),
              ),
              child: SvgPicture.asset(plannerIconAsset),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('PathPlanA'),
                Text(
                  'Local REBUILT auto authoring',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A0B8)),
                ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _createAuto,
            icon: const Icon(Icons.add),
            label: const Text('New Auto'),
          ),
          TextButton.icon(
            onPressed: _importPackage,
            icon: const Icon(Icons.upload_file),
            label: const Text('Import'),
          ),
          TextButton.icon(
            onPressed: _exportPackage,
            icon: const Icon(Icons.download),
            label: const Text('Export JSON'),
          ),
          TextButton.icon(
            onPressed: _chooseDeployFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Set Deploy Folder'),
          ),
          TextButton.icon(
            onPressed: _exportDeployLibrary,
            icon: const Icon(Icons.folder_zip),
            label: const Text('Export Deploy'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 0, 16),
            child: NavigationRail(
              selectedIndex: _selectedSection.index,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedSection = PlannerSection.values[index];
                });
              },
              backgroundColor: const Color(0xFF11161F),
              indicatorColor: const Color(0x26FFD166),
              extended: false,
              destinations: const <NavigationRailDestination>[
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_customize_outlined),
                  selectedIcon: Icon(Icons.dashboard_customize),
                  label: Text('Library'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.route_outlined),
                  selectedIcon: Icon(Icons.route),
                  label: Text('Editor'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bolt_outlined),
                  selectedIcon: Icon(Icons.bolt),
                  label: Text('Events'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.crop_square_outlined),
                  selectedIcon: Icon(Icons.crop_square),
                  label: Text('Obstacles'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: Text('Commands'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
              child: IndexedStack(
                index: _selectedSection.index,
                children: <Widget>[
                  _LibrarySection(
                    package: _package,
                    selectedAutoIndex: _selectedAutoIndex,
                    statusMessage: _statusMessage,
                    schemaSummary: _schemaSummary,
                    onSelectAuto: _selectAuto,
                    onDeleteSelectedAuto: _deleteSelectedAuto,
                  ),
                  _EditorSection(
                    autos: _package.autos,
                    selectedAutoIndex: _selectedAutoIndex,
                    auto: _selectedAuto,
                    commandProfiles: _commandProfiles,
                    selectedStepIndex: _selectedStepIndex,
                    selectedWaypointRef: _selectedWaypointRef,
                    startPoseSelected: _startPoseSelected,
                    globalStartPoses: _package.globalStartPoses,
                    globalVariables: _package.globalVariables,
                    tool: _tool,
                    draftCommandId: _draftCommandId,
                    draftHeadingDeg: _draftHeadingDeg,
                    estimatedTimeSeconds: _estimatedTimeSeconds,
                    playbackProgress: _previewProgress,
                    previewPlaying: _previewPlaying,
                    onToolChanged: (PlannerTool tool) =>
                        setState(() => _tool = tool),
                    onDraftCommandChanged: (String value) =>
                        setState(() => _draftCommandId = value),
                    onHeadingChanged: (double value) =>
                        setState(() => _draftHeadingDeg = value),
                    onUndo: _undo,
                    onRedo: _redo,
                    canUndo: _undoStack.isNotEmpty,
                    canRedo: _redoStack.isNotEmpty,
                    onAddEventMarker: _addEventMarker,
                    onAddEventZone: _addEventZone,
                    onAddConstraintZone: _addConstraintZone,
                    onAddObstacleZone: _addZone,
                    onTogglePlayback: _togglePreviewPlayback,
                    onPlaybackScrub: _setPreviewProgress,
                    onBeginDragEdit: _pushUndoSnapshot,
                    onSelectAutoFromBrowser: _selectAuto,
                    onOpenEvents: () => setState(
                      () => _selectedSection = PlannerSection.events,
                    ),
                    onOpenObstacles: () => setState(
                      () => _selectedSection = PlannerSection.obstacles,
                    ),
                    onOpenCommands: () => setState(
                      () => _selectedSection = PlannerSection.commands,
                    ),
                    onOpenSettings: () => setState(
                      () => _selectedSection = PlannerSection.settings,
                    ),
                    onTap: _handleCanvasTap,
                    onSelectStep: (int index) => setState(() {
                      _startPoseSelected = false;
                      _selectedStepIndex = index;
                      _selectedWaypointRef = PlannerWaypointRef(
                        stepIndex: index,
                      );
                    }),
                    onSelectWaypoint: (PlannerWaypointRef ref) => setState(() {
                      _startPoseSelected = false;
                      _selectedStepIndex = ref.stepIndex;
                      _selectedWaypointRef = ref;
                    }),
                    onSelectStartPose: _selectStartPose,
                    onMoveStartPose: _moveStartPose,
                    onMoveStep: (int index, PlannerPose pose) {
                      final List<PlannerStep> steps = <PlannerStep>[
                        ..._selectedAuto.steps,
                      ];
                      steps[index] = steps[index].copyWith(
                        pose: clampPoseToField(pose),
                      );
                      _updateSelectedAuto(
                        _selectedAuto.copyWith(steps: steps),
                        recordHistory: false,
                      );
                      setState(() {
                        _startPoseSelected = false;
                        _selectedStepIndex = index;
                        _selectedWaypointRef = PlannerWaypointRef(
                          stepIndex: index,
                        );
                      });
                    },
                    onMoveWaypoint:
                        (int stepIndex, int waypointIndex, PlannerPose pose) {
                          final List<PlannerStep> steps = <PlannerStep>[
                            ..._selectedAuto.steps,
                          ];
                          final List<PlannerWaypoint> waypoints =
                              <PlannerWaypoint>[
                                ...steps[stepIndex].routeWaypoints,
                              ];
                          waypoints[waypointIndex] = waypoints[waypointIndex]
                              .copyWith(pose: clampPoseToField(pose));
                          steps[stepIndex] = steps[stepIndex].copyWith(
                            routeWaypoints: waypoints,
                          );
                          _updateSelectedAuto(
                            _selectedAuto.copyWith(steps: steps),
                            recordHistory: false,
                          );
                          setState(() {
                            _startPoseSelected = false;
                            _selectedStepIndex = stepIndex;
                            _selectedWaypointRef = PlannerWaypointRef(
                              stepIndex: stepIndex,
                              routeWaypointIndex: waypointIndex,
                            );
                          });
                        },
                    onDeleteStep: (int index) {
                      final List<PlannerStep> steps = <PlannerStep>[
                        ..._selectedAuto.steps,
                      ]..removeAt(index);
                      _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
                      setState(() {
                        _selectedStepIndex = steps.isEmpty
                            ? null
                            : math.min(index, steps.length - 1);
                        _startPoseSelected = steps.isEmpty;
                        _selectedWaypointRef = steps.isEmpty
                            ? null
                            : PlannerWaypointRef(
                                stepIndex: math.min(index, steps.length - 1),
                              );
                      });
                    },
                    onRenameAuto: (String value) => _updateSelectedAuto(
                      _selectedAuto.copyWith(name: value),
                    ),
                    onFolderChanged: (String value) => _updateSelectedAuto(
                      _selectedAuto.copyWith(folder: value),
                    ),
                    onApplyGlobalStartPose: (PlannerPose pose) =>
                        _updateSelectedAuto(
                          _selectedAuto.copyWith(startPose: pose),
                        ),
                    onApplyNamedPoseToSelection: _applyNamedPoseToSelection,
                    onSaveSelectedPointAsNamedPose:
                        _saveSelectedPointAsNamedPose,
                    onUpdateSettings: (PlannerSettings settings) =>
                        _updateSelectedAuto(
                          _selectedAuto.copyWith(settings: settings),
                        ),
                    onUpdateSelectedPointConstraintProfile:
                        _updateSelectedPointConstraintProfile,
                    onUpdateWaypoint:
                        (PlannerWaypointRef ref, PlannerWaypoint waypoint) {
                          final List<PlannerStep> steps = <PlannerStep>[
                            ..._selectedAuto.steps,
                          ];
                          if (ref.routeWaypointIndex == null) {
                            steps[ref.stepIndex] = steps[ref.stepIndex]
                                .copyWith(
                                  pose: clampPoseToField(waypoint.pose),
                                  anchorConstraintProfile:
                                      waypoint.constraintProfile,
                                );
                          } else {
                            final List<PlannerWaypoint> waypoints =
                                <PlannerWaypoint>[
                                  ...steps[ref.stepIndex].routeWaypoints,
                                ];
                            waypoints[ref.routeWaypointIndex!] = waypoint
                                .copyWith(
                                  pose: clampPoseToField(waypoint.pose),
                                );
                            steps[ref.stepIndex] = steps[ref.stepIndex]
                                .copyWith(routeWaypoints: waypoints);
                          }
                          _updateSelectedAuto(
                            _selectedAuto.copyWith(steps: steps),
                          );
                        },
                    onUpdateStep: (PlannerStep step) {
                      if (_selectedStepIndex == null) {
                        return;
                      }
                      final List<PlannerStep> steps = <PlannerStep>[
                        ..._selectedAuto.steps,
                      ];
                      steps[_selectedStepIndex!] = step;
                      _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
                    },
                    onUpdateEventMarker: _updateEventMarker,
                    onDeleteEventMarker: _deleteEventMarker,
                    onDeleteSelectedPoint: _deleteSelectedPoint,
                  ),
                  _EventsSection(
                    auto: _selectedAuto,
                    commandProfiles: _commandProfiles,
                    selectedMarkerIndex: _selectedMarkerIndex,
                    selectedEventZoneIndex: _selectedEventZoneIndex,
                    onBeginDragEdit: _pushUndoSnapshot,
                    onSelectMarker: (int index) =>
                        setState(() => _selectedMarkerIndex = index),
                    onSelectEventZone: (int index) =>
                        setState(() => _selectedEventZoneIndex = index),
                    onAddMarker: _addEventMarker,
                    onAddEventZone: _addEventZone,
                    onUpdateMarker: _updateEventMarker,
                    onDeleteMarker: _deleteEventMarker,
                    onUpdateEventZone: _updateEventZone,
                    onDeleteEventZone: _deleteEventZone,
                  ),
                  _ObstacleSection(
                    auto: _selectedAuto,
                    selectedZoneIndex: _selectedZoneIndex,
                    onBeginDragEdit: _pushUndoSnapshot,
                    onSelectZone: (int index) =>
                        setState(() => _selectedZoneIndex = index),
                    onAddZone: _addZone,
                    onUpdateZone: _updateZone,
                    onDeleteZone: _deleteZone,
                  ),
                  _CommandsSection(
                    commandProfiles: _commandProfiles,
                    onUpdateProfiles: _updateCommandProfiles,
                  ),
                  _SettingsPanel(
                    auto: _selectedAuto,
                    commandProfiles: _commandProfiles,
                    selectedStepIndex: _selectedStepIndex,
                    onRenameAuto: (String value) => _updateSelectedAuto(
                      _selectedAuto.copyWith(name: value),
                    ),
                    onUpdateSettings: (PlannerSettings settings) =>
                        _updateSelectedAuto(
                          _selectedAuto.copyWith(settings: settings),
                        ),
                    onUpdateStep: (PlannerStep step) {
                      if (_selectedStepIndex == null) {
                        return;
                      }
                      final List<PlannerStep> steps = <PlannerStep>[
                        ..._selectedAuto.steps,
                      ];
                      steps[_selectedStepIndex!] = step;
                      _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibrarySection extends StatelessWidget {
  const _LibrarySection({
    required this.package,
    required this.selectedAutoIndex,
    required this.statusMessage,
    required this.schemaSummary,
    required this.onSelectAuto,
    required this.onDeleteSelectedAuto,
  });

  final PlannerPackage package;
  final int selectedAutoIndex;
  final String statusMessage;
  final String schemaSummary;
  final ValueChanged<int> onSelectAuto;
  final VoidCallback onDeleteSelectedAuto;

  @override
  Widget build(BuildContext context) {
    final Set<String> folders = package.autos
        .map((PlannerAuto auto) => auto.folder)
        .toSet();
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 84,
                        height: 84,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B0E14),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFF273246)),
                        ),
                        child: SvgPicture.asset(plannerIconAsset),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Auto Library',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Start here, pick an auto, then open the editor.',
                              style: TextStyle(color: Color(0xFF94A0B8)),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              statusMessage,
                              style: const TextStyle(color: Color(0xFFE8EEFC)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              schemaSummary,
                              style: const TextStyle(
                                color: Color(0xFF94A0B8),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: folders
                                  .map(
                                    (String folder) => Chip(
                                      label: Text(folder),
                                      backgroundColor: const Color(0xFF151C28),
                                      side: const BorderSide(
                                        color: Color(0xFF273246),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: onDeleteSelectedAuto,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete selected auto',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.1,
            ),
            itemCount: package.autos.length,
            itemBuilder: (BuildContext context, int index) {
              final PlannerAuto auto = package.autos[index];
              return _AutoGalleryCard(
                auto: auto,
                selected: index == selectedAutoIndex,
                onTap: () => onSelectAuto(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.autos,
    required this.selectedAutoIndex,
    required this.auto,
    required this.commandProfiles,
    required this.selectedStepIndex,
    required this.selectedWaypointRef,
    required this.startPoseSelected,
    required this.globalStartPoses,
    required this.globalVariables,
    required this.tool,
    required this.draftCommandId,
    required this.draftHeadingDeg,
    required this.estimatedTimeSeconds,
    required this.playbackProgress,
    required this.previewPlaying,
    required this.onToolChanged,
    required this.onDraftCommandChanged,
    required this.onHeadingChanged,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
    required this.onAddEventMarker,
    required this.onAddEventZone,
    required this.onAddConstraintZone,
    required this.onAddObstacleZone,
    required this.onTogglePlayback,
    required this.onPlaybackScrub,
    required this.onBeginDragEdit,
    required this.onSelectAutoFromBrowser,
    required this.onOpenEvents,
    required this.onOpenObstacles,
    required this.onOpenCommands,
    required this.onOpenSettings,
    required this.onTap,
    required this.onSelectStartPose,
    required this.onSelectStep,
    required this.onSelectWaypoint,
    required this.onMoveStartPose,
    required this.onMoveStep,
    required this.onMoveWaypoint,
    required this.onDeleteStep,
    required this.onRenameAuto,
    required this.onFolderChanged,
    required this.onApplyGlobalStartPose,
    required this.onApplyNamedPoseToSelection,
    required this.onSaveSelectedPointAsNamedPose,
    required this.onUpdateSelectedPointConstraintProfile,
    required this.onUpdateWaypoint,
    required this.onUpdateSettings,
    required this.onUpdateStep,
    required this.onUpdateEventMarker,
    required this.onDeleteEventMarker,
    required this.onDeleteSelectedPoint,
  });

  final List<PlannerAuto> autos;
  final int selectedAutoIndex;
  final PlannerAuto auto;
  final List<PlannerCommandProfile> commandProfiles;
  final int? selectedStepIndex;
  final PlannerWaypointRef? selectedWaypointRef;
  final bool startPoseSelected;
  final List<PlannerNamedPose> globalStartPoses;
  final List<PlannerNamedValue> globalVariables;
  final PlannerTool tool;
  final String draftCommandId;
  final double draftHeadingDeg;
  final double estimatedTimeSeconds;
  final double playbackProgress;
  final bool previewPlaying;
  final ValueChanged<PlannerTool> onToolChanged;
  final ValueChanged<String> onDraftCommandChanged;
  final ValueChanged<double> onHeadingChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onAddEventMarker;
  final VoidCallback onAddEventZone;
  final VoidCallback onAddConstraintZone;
  final VoidCallback onAddObstacleZone;
  final VoidCallback onTogglePlayback;
  final ValueChanged<double> onPlaybackScrub;
  final VoidCallback onBeginDragEdit;
  final ValueChanged<int> onSelectAutoFromBrowser;
  final VoidCallback onOpenEvents;
  final VoidCallback onOpenObstacles;
  final VoidCallback onOpenCommands;
  final VoidCallback onOpenSettings;
  final ValueChanged<Offset> onTap;
  final VoidCallback onSelectStartPose;
  final ValueChanged<int> onSelectStep;
  final ValueChanged<PlannerWaypointRef> onSelectWaypoint;
  final ValueChanged<PlannerPose> onMoveStartPose;
  final void Function(int index, PlannerPose pose) onMoveStep;
  final void Function(int stepIndex, int waypointIndex, PlannerPose pose)
  onMoveWaypoint;
  final ValueChanged<int> onDeleteStep;
  final ValueChanged<String> onRenameAuto;
  final ValueChanged<String> onFolderChanged;
  final ValueChanged<PlannerPose> onApplyGlobalStartPose;
  final ValueChanged<PlannerPose> onApplyNamedPoseToSelection;
  final VoidCallback onSaveSelectedPointAsNamedPose;
  final ValueChanged<PlannerPointConstraintProfile>
  onUpdateSelectedPointConstraintProfile;
  final void Function(PlannerWaypointRef ref, PlannerWaypoint waypoint)
  onUpdateWaypoint;
  final ValueChanged<PlannerSettings> onUpdateSettings;
  final ValueChanged<PlannerStep> onUpdateStep;
  final void Function(int index, PlannerEventMarker marker) onUpdateEventMarker;
  final ValueChanged<int> onDeleteEventMarker;
  final VoidCallback onDeleteSelectedPoint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 270,
          child: _ProjectSidebar(
            autos: autos,
            selectedAutoIndex: selectedAutoIndex,
            auto: auto,
            commandProfiles: commandProfiles,
            selectedWaypointRef: selectedWaypointRef,
            startPoseSelected: startPoseSelected,
            onSelectAuto: onSelectAutoFromBrowser,
            onSelectStartPose: onSelectStartPose,
            onSelectWaypoint: onSelectWaypoint,
            onOpenEvents: onOpenEvents,
            onOpenObstacles: onOpenObstacles,
            onOpenCommands: onOpenCommands,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: <Widget>[
              _ToolStrip(
                tool: tool,
                commandProfiles: commandProfiles,
                draftCommandId: draftCommandId,
                draftHeadingDeg: draftHeadingDeg,
                onToolChanged: onToolChanged,
                onDraftCommandChanged: onDraftCommandChanged,
                onHeadingChanged: onHeadingChanged,
                onUndo: onUndo,
                onRedo: onRedo,
                canUndo: canUndo,
                canRedo: canRedo,
                onAddEventMarker: onAddEventMarker,
                onAddEventZone: onAddEventZone,
                onAddConstraintZone: onAddConstraintZone,
                onAddObstacleZone: onAddObstacleZone,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          _MetricChip(
                            label: 'ETA',
                            value: formatDurationSeconds(estimatedTimeSeconds),
                          ),
                          const SizedBox(width: 10),
                          _MetricChip(
                            label: 'Distance',
                            value:
                                '${computeAutoDistanceMeters(auto).toStringAsFixed(2)} m',
                          ),
                          const SizedBox(width: 10),
                          _MetricChip(
                            label: 'Commands',
                            value:
                                '${auto.eventMarkers.length + auto.eventZones.length}',
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: onTogglePlayback,
                            icon: Icon(
                              previewPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            label: Text(previewPlaying ? 'Pause' : 'Animate'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          const Text(
                            'Path Preview',
                            style: TextStyle(color: Color(0xFF94A0B8)),
                          ),
                          Expanded(
                            child: Slider(
                              value: playbackProgress.clamp(0.0, 1.0),
                              onChanged: onPlaybackScrub,
                            ),
                          ),
                          Text(
                            '${(playbackProgress * 100).round()}%',
                            style: const TextStyle(color: Color(0xFF94A0B8)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                auto.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              '${auto.steps.length} steps',
                              style: const TextStyle(color: Color(0xFF94A0B8)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                flex: 6,
                                child: _FieldEditor(
                                  auto: auto,
                                  tool: tool,
                                  startPoseSelected: startPoseSelected,
                                  selectedStepIndex: selectedStepIndex,
                                  selectedWaypointRef: selectedWaypointRef,
                                  onSelectStep: onSelectStep,
                                  onSelectStartPose: onSelectStartPose,
                                  onSelectWaypoint: onSelectWaypoint,
                                  onMoveStartPose: onMoveStartPose,
                                  onMoveStep: onMoveStep,
                                  onMoveWaypoint: onMoveWaypoint,
                                  onBeginDragEdit: onBeginDragEdit,
                                  playbackProgress: playbackProgress,
                                  onTap: onTap,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 4,
                                child: _StepListPanel(
                                  auto: auto,
                                  commandProfiles: commandProfiles,
                                  selectedStepIndex: selectedStepIndex,
                                  onSelectStep: onSelectStep,
                                  onDeleteStep: onDeleteStep,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 350,
          child: _EditorInspector(
            auto: auto,
            commandProfiles: commandProfiles,
            selectedStepIndex: selectedStepIndex,
            selectedWaypointRef: selectedWaypointRef,
            startPoseSelected: startPoseSelected,
            globalStartPoses: globalStartPoses,
            globalVariables: globalVariables,
            estimatedTimeSeconds: estimatedTimeSeconds,
            onRenameAuto: onRenameAuto,
            onFolderChanged: onFolderChanged,
            onApplyGlobalStartPose: onApplyGlobalStartPose,
            onApplyNamedPoseToSelection: onApplyNamedPoseToSelection,
            onSaveSelectedPointAsNamedPose: onSaveSelectedPointAsNamedPose,
            onUpdateSelectedPointConstraintProfile:
                onUpdateSelectedPointConstraintProfile,
            onUpdateWaypoint: onUpdateWaypoint,
            onUpdateSettings: onUpdateSettings,
            onUpdateStep: onUpdateStep,
            onUpdateEventMarker: onUpdateEventMarker,
            onDeleteEventMarker: onDeleteEventMarker,
            onDeleteSelectedPoint: onDeleteSelectedPoint,
            onOpenSettings: onOpenSettings,
          ),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151C28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF273246)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A0B8),
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ProjectSidebar extends StatelessWidget {
  const _ProjectSidebar({
    required this.autos,
    required this.selectedAutoIndex,
    required this.auto,
    required this.commandProfiles,
    required this.selectedWaypointRef,
    required this.startPoseSelected,
    required this.onSelectAuto,
    required this.onSelectStartPose,
    required this.onSelectWaypoint,
    required this.onOpenEvents,
    required this.onOpenObstacles,
    required this.onOpenCommands,
  });

  final List<PlannerAuto> autos;
  final int selectedAutoIndex;
  final PlannerAuto auto;
  final List<PlannerCommandProfile> commandProfiles;
  final PlannerWaypointRef? selectedWaypointRef;
  final bool startPoseSelected;
  final ValueChanged<int> onSelectAuto;
  final VoidCallback onSelectStartPose;
  final ValueChanged<PlannerWaypointRef> onSelectWaypoint;
  final VoidCallback onOpenEvents;
  final VoidCallback onOpenObstacles;
  final VoidCallback onOpenCommands;

  @override
  Widget build(BuildContext context) {
    final Map<String, List<MapEntry<int, PlannerAuto>>> autosByFolder =
        <String, List<MapEntry<int, PlannerAuto>>>{};
    for (int index = 0; index < autos.length; index += 1) {
      final PlannerAuto entry = autos[index];
      autosByFolder
          .putIfAbsent(entry.folder, () => <MapEntry<int, PlannerAuto>>[])
          .add(MapEntry<int, PlannerAuto>(index, entry));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Project Browser',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),
            const Text(
              'Autos',
              style: TextStyle(color: Color(0xFF94A0B8), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: autosByFolder.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.key,
                          style: const TextStyle(
                            color: Color(0xFFFFD166),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...entry.value.map((autoEntry) {
                          final bool selected =
                              autoEntry.key == selectedAutoIndex;
                          final PlannerAuto plannedAuto = autoEntry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: selected
                                  ? const Color(0x1A39D98A)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => onSelectAuto(autoEntry.key),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        plannedAuto.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${plannedAuto.steps.length} steps • ${plannedAuto.eventMarkers.length} markers',
                                        style: const TextStyle(
                                          color: Color(0xFF94A0B8),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Route Points',
              style: TextStyle(color: Color(0xFF94A0B8), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Material(
              color: startPoseSelected
                  ? const Color(0x26FFD166)
                  : const Color(0xFF151C28),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onSelectStartPose,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.play_arrow, color: Color(0xFFFFD166)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Start Pose',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${auto.startPoseConstraintProfile.activeConstraintIds.length} constraints • ${auto.eventMarkers.where((PlannerEventMarker marker) => marker.targetType == PlannerEventMarkerTargetType.startPose).length} markers',
                              style: const TextStyle(
                                color: Color(0xFF94A0B8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: ListView.separated(
                itemCount: allPointRefs(auto).length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final PlannerWaypointRef ref = allPointRefs(auto).elementAt(
                    index,
                  );
                  final bool selected =
                      !startPoseSelected &&
                      selectedWaypointRef?.stepIndex == ref.stepIndex &&
                      selectedWaypointRef?.routeWaypointIndex ==
                          ref.routeWaypointIndex;
                  final PlannerPointConstraintProfile profile =
                      resolvePointConstraintProfile(
                        auto,
                        startPoseSelected: false,
                        ref: ref,
                      );
                  final int markerCount = auto.eventMarkers.where(
                    (PlannerEventMarker marker) => marker.targetsSelection(
                      startPoseSelected: false,
                      selectedWaypointRef: ref,
                    ),
                  ).length;
                  return Material(
                    color: selected
                        ? const Color(0x2639D98A)
                        : const Color(0xFF151C28),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onSelectWaypoint(ref),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              ref.routeWaypointIndex == null
                                  ? Icons.crop_5_4
                                  : auto
                                            .steps[ref.stepIndex]
                                            .routeWaypoints[ref.routeWaypointIndex!]
                                            .type ==
                                        PlannerWaypointType.translation
                                  ? Icons.more_horiz
                                  : Icons.square_outlined,
                              color: const Color(0xFF39D98A),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    describePointRef(auto, ref),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${profile.activeConstraintIds.length} constraints • $markerCount markers',
                                    style: const TextStyle(
                                      color: Color(0xFF94A0B8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Assets',
              style: TextStyle(color: Color(0xFF94A0B8), fontSize: 12),
            ),
            const SizedBox(height: 8),
            _BrowserLinkTile(
              icon: Icons.bolt,
              title: 'Events',
              subtitle:
                  '${auto.eventMarkers.length} markers • ${auto.eventZones.length} zones',
              onTap: onOpenEvents,
            ),
            const SizedBox(height: 8),
            _BrowserLinkTile(
              icon: Icons.tune,
              title: 'Named Commands',
              subtitle: '${commandProfiles.length} command profiles',
              onTap: onOpenCommands,
            ),
            const SizedBox(height: 8),
            _BrowserLinkTile(
              icon: Icons.crop_square,
              title: 'Obstacles',
              subtitle: '${auto.customZones.length} keep-out boxes',
              onTap: onOpenObstacles,
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserLinkTile extends StatelessWidget {
  const _BrowserLinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF151C28),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: <Widget>[
              Icon(icon, color: const Color(0xFFFFD166)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF94A0B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorInspector extends StatelessWidget {
  const _EditorInspector({
    required this.auto,
    required this.commandProfiles,
    required this.selectedStepIndex,
    required this.selectedWaypointRef,
    required this.startPoseSelected,
    required this.globalStartPoses,
    required this.globalVariables,
    required this.estimatedTimeSeconds,
    required this.onRenameAuto,
    required this.onFolderChanged,
    required this.onApplyGlobalStartPose,
    required this.onApplyNamedPoseToSelection,
    required this.onSaveSelectedPointAsNamedPose,
    required this.onUpdateSelectedPointConstraintProfile,
    required this.onUpdateWaypoint,
    required this.onUpdateSettings,
    required this.onUpdateStep,
    required this.onUpdateEventMarker,
    required this.onDeleteEventMarker,
    required this.onDeleteSelectedPoint,
    required this.onOpenSettings,
  });

  final PlannerAuto auto;
  final List<PlannerCommandProfile> commandProfiles;
  final int? selectedStepIndex;
  final PlannerWaypointRef? selectedWaypointRef;
  final bool startPoseSelected;
  final List<PlannerNamedPose> globalStartPoses;
  final List<PlannerNamedValue> globalVariables;
  final double estimatedTimeSeconds;
  final ValueChanged<String> onRenameAuto;
  final ValueChanged<String> onFolderChanged;
  final ValueChanged<PlannerPose> onApplyGlobalStartPose;
  final ValueChanged<PlannerPose> onApplyNamedPoseToSelection;
  final VoidCallback onSaveSelectedPointAsNamedPose;
  final ValueChanged<PlannerPointConstraintProfile>
  onUpdateSelectedPointConstraintProfile;
  final void Function(PlannerWaypointRef ref, PlannerWaypoint waypoint)
  onUpdateWaypoint;
  final ValueChanged<PlannerSettings> onUpdateSettings;
  final ValueChanged<PlannerStep> onUpdateStep;
  final void Function(int index, PlannerEventMarker marker) onUpdateEventMarker;
  final ValueChanged<int> onDeleteEventMarker;
  final VoidCallback onDeleteSelectedPoint;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final PlannerWaypointRef? selectedRef = selectedWaypointRef;
    final PlannerWaypoint? selectedWaypoint = startPoseSelected
        ? PlannerWaypoint(
            pose: auto.startPose,
            type: PlannerWaypointType.pose,
            constraintProfile: auto.startPoseConstraintProfile,
          )
        : selectedRef == null
        ? null
        : selectedRef.routeWaypointIndex == null
        ? PlannerWaypoint(
            pose: auto.steps[selectedRef.stepIndex].pose,
            type: PlannerWaypointType.pose,
            constraintProfile: auto.steps[selectedRef.stepIndex]
                .anchorConstraintProfile,
          )
        : auto.steps[selectedRef.stepIndex].routeWaypoints[selectedRef
              .routeWaypointIndex!];
    final List<MapEntry<int, PlannerEventMarker>> selectedMarkers = auto
        .eventMarkers
        .asMap()
        .entries
        .where(
          (MapEntry<int, PlannerEventMarker> entry) => entry.value
              .targetsSelection(
                startPoseSelected: startPoseSelected,
                selectedWaypointRef: selectedRef,
              ),
        )
        .toList();
    final PlannerPose selectedPose = resolvePointPose(
      auto,
      startPoseSelected: startPoseSelected,
      ref: selectedRef,
    );
    final List<PlannerEventZone> overlappingZones = auto.eventZones.where((
      PlannerEventZone zone,
    ) {
      return selectedPose.xMeters >= math.min(zone.xMinMeters, zone.xMaxMeters) &&
          selectedPose.xMeters <= math.max(zone.xMinMeters, zone.xMaxMeters) &&
          selectedPose.yMeters >= math.min(zone.yMinMeters, zone.yMaxMeters) &&
          selectedPose.yMeters <= math.max(zone.yMinMeters, zone.yMaxMeters);
    }).toList();
    final Set<String> effectiveCommandIds = <String>{
      ...selectedMarkers.map((MapEntry<int, PlannerEventMarker> entry) {
        return entry.value.commandId;
      }).where((String id) => id.isNotEmpty),
      ...overlappingZones
          .expand(
            (PlannerEventZone zone) => <String>[
              zone.enterCommandId,
              zone.activeCommandId,
              zone.exitCommandId,
            ],
          )
          .where((String id) => id.isNotEmpty),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ListView(
          children: <Widget>[
            const Text(
              'Inspector',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey<String>('auto-name-${auto.id}'),
              initialValue: auto.name,
              decoration: const InputDecoration(labelText: 'Auto Name'),
              onChanged: onRenameAuto,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey<String>('auto-folder-${auto.id}'),
              initialValue: auto.folder,
              decoration: const InputDecoration(labelText: 'Folder'),
              onChanged: (String value) =>
                  onFolderChanged(value.isEmpty ? 'Autos' : value),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _MetricChip(
                    label: 'Estimated Runtime',
                    value: formatDurationSeconds(estimatedTimeSeconds),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricChip(
                    label: 'Path Distance',
                    value:
                        '${computeAutoDistanceMeters(auto).toStringAsFixed(2)} m',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SettingsSection(
              title: 'Quick Dynamics',
              child: Column(
                children: <Widget>[
                  _LabeledSlider(
                    label: 'Constraint Factor',
                    value: auto.settings.constraintFactor,
                    min: 0.3,
                    max: 1.4,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(constraintFactor: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Max Velocity MPS',
                    value: auto.settings.maxVelocityMps,
                    min: 0.5,
                    max: 6.0,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(maxVelocityMps: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Max Accel MPS²',
                    value: auto.settings.maxAccelerationMpsSq,
                    min: 0.5,
                    max: 6.0,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(maxAccelerationMpsSq: value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SettingsSection(
              title: 'Global Starts',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Current start: ${auto.startPose.xMeters.toStringAsFixed(2)}, ${auto.startPose.yMeters.toStringAsFixed(2)} • ${auto.startPose.headingDeg.toStringAsFixed(0)}°',
                    style: const TextStyle(color: Color(0xFF94A0B8)),
                  ),
                  if (globalStartPoses.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>('start-pose-${auto.id}'),
                      decoration: const InputDecoration(
                        labelText: 'Apply Global Start',
                      ),
                      items: globalStartPoses
                          .map(
                            (PlannerNamedPose namedPose) =>
                                DropdownMenuItem<String>(
                                  value: namedPose.id,
                                  child: Text(namedPose.name),
                                ),
                          )
                          .toList(),
                      onChanged: (String? id) {
                        if (id == null) {
                          return;
                        }
                        for (final PlannerNamedPose namedPose
                            in globalStartPoses) {
                          if (namedPose.id == id) {
                            onApplyGlobalStartPose(namedPose.pose);
                            break;
                          }
                        }
                      },
                    ),
                  ],
                  if (selectedWaypoint != null && globalStartPoses.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'apply-pose-variable-${startPoseSelected ? "start" : "${selectedRef?.stepIndex}-${selectedRef?.routeWaypointIndex}"}',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Apply Pose Variable To Selection',
                      ),
                      items: globalStartPoses
                          .map(
                            (PlannerNamedPose namedPose) =>
                                DropdownMenuItem<String>(
                                  value: namedPose.id,
                                  child: Text(namedPose.name),
                                ),
                          )
                          .toList(),
                      onChanged: (String? id) {
                        if (id == null) {
                          return;
                        }
                        for (final PlannerNamedPose namedPose
                            in globalStartPoses) {
                          if (namedPose.id == id) {
                            onApplyNamedPoseToSelection(namedPose.pose);
                            break;
                          }
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            if (selectedWaypoint != null) ...<Widget>[
              const SizedBox(height: 12),
              _SettingsSection(
                title: startPoseSelected
                    ? 'Selected Start Pose'
                    : selectedRef?.routeWaypointIndex == null
                    ? 'Selected Anchor'
                    : 'Selected Waypoint',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      startPoseSelected
                          ? 'Start pose'
                          : selectedRef?.routeWaypointIndex == null
                          ? 'Robot pose + heading'
                          : selectedWaypoint.type ==
                                    PlannerWaypointType.translation
                          ? 'Translation control point'
                          : 'Pose control point',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    if (!startPoseSelected &&
                        selectedRef?.routeWaypointIndex != null)
                      DropdownButtonFormField<PlannerWaypointType>(
                        key: ValueKey<String>(
                          'type-${selectedRef!.stepIndex}-${selectedRef.routeWaypointIndex}',
                        ),
                        initialValue: selectedWaypoint.type,
                        decoration: const InputDecoration(
                          labelText: 'Waypoint Type',
                        ),
                        items: const <DropdownMenuItem<PlannerWaypointType>>[
                          DropdownMenuItem(
                            value: PlannerWaypointType.translation,
                            child: Text('Translation'),
                          ),
                          DropdownMenuItem(
                            value: PlannerWaypointType.pose,
                            child: Text('Pose + Heading'),
                          ),
                        ],
                        onChanged: (PlannerWaypointType? value) {
                          if (value == null) {
                            return;
                          }
                          onUpdateWaypoint(
                            selectedRef,
                            selectedWaypoint.copyWith(type: value),
                          );
                        },
                      ),
                    if (!startPoseSelected &&
                        selectedRef?.routeWaypointIndex != null)
                      const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextFormField(
                            key: ValueKey<String>(
                              'x-${startPoseSelected ? "start" : "${selectedRef?.stepIndex}-${selectedRef?.routeWaypointIndex}"}-${selectedWaypoint.pose.xMeters.toStringAsFixed(3)}',
                            ),
                            initialValue: selectedWaypoint.pose.xMeters
                                .toStringAsFixed(2),
                            decoration: const InputDecoration(labelText: 'X'),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  signed: true,
                                  decimal: true,
                                ),
                            onChanged: (String value) {
                              final PlannerWaypoint updated =
                                  selectedWaypoint.copyWith(
                                    pose: selectedWaypoint.pose.copyWith(
                                      xMeters:
                                          double.tryParse(value) ??
                                          selectedWaypoint.pose.xMeters,
                                    ),
                                  );
                              if (startPoseSelected) {
                                onApplyGlobalStartPose(updated.pose);
                              } else {
                                onUpdateWaypoint(selectedRef!, updated);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey<String>(
                              'y-${startPoseSelected ? "start" : "${selectedRef?.stepIndex}-${selectedRef?.routeWaypointIndex}"}-${selectedWaypoint.pose.yMeters.toStringAsFixed(3)}',
                            ),
                            initialValue: selectedWaypoint.pose.yMeters
                                .toStringAsFixed(2),
                            decoration: const InputDecoration(labelText: 'Y'),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  signed: true,
                                  decimal: true,
                                ),
                            onChanged: (String value) {
                              final PlannerWaypoint updated =
                                  selectedWaypoint.copyWith(
                                    pose: selectedWaypoint.pose.copyWith(
                                      yMeters:
                                          double.tryParse(value) ??
                                          selectedWaypoint.pose.yMeters,
                                    ),
                                  );
                              if (startPoseSelected) {
                                onApplyGlobalStartPose(updated.pose);
                              } else {
                                onUpdateWaypoint(selectedRef!, updated);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (startPoseSelected ||
                        selectedRef?.routeWaypointIndex == null ||
                        selectedWaypoint.type == PlannerWaypointType.pose)
                      TextFormField(
                        key: ValueKey<String>(
                          'heading-${startPoseSelected ? "start" : "${selectedRef?.stepIndex}-${selectedRef?.routeWaypointIndex}"}-${selectedWaypoint.pose.headingDeg.toStringAsFixed(2)}',
                        ),
                        initialValue: selectedWaypoint.pose.headingDeg
                            .toStringAsFixed(0),
                        decoration: const InputDecoration(
                          labelText: 'Heading',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        onChanged: (String value) {
                          final PlannerWaypoint updated = selectedWaypoint
                              .copyWith(
                                pose: selectedWaypoint.pose.copyWith(
                                  headingDeg:
                                      double.tryParse(value) ??
                                      selectedWaypoint.pose.headingDeg,
                                ),
                              );
                          if (startPoseSelected) {
                            onApplyGlobalStartPose(updated.pose);
                          } else {
                            onUpdateWaypoint(selectedRef!, updated);
                          }
                        },
                      ),
                    if (!startPoseSelected &&
                        selectedRef?.routeWaypointIndex != null &&
                        selectedWaypoint.type ==
                            PlannerWaypointType.translation) ...<Widget>[
                      const SizedBox(height: 10),
                      _LabeledSlider(
                        label: 'Bend Strength',
                        value: selectedWaypoint.bendStrength,
                        min: 0.1,
                        max: 1.0,
                        onChanged: (double value) => onUpdateWaypoint(
                          selectedRef!,
                          selectedWaypoint.copyWith(bendStrength: value),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: startPoseSelected ? null : onDeleteSelectedPoint,
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  selectedRef?.routeWaypointIndex == null
                      ? 'Delete Selected Anchor Step'
                      : 'Delete Selected Waypoint',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onSaveSelectedPointAsNamedPose,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save As Pose Variable'),
              ),
              const SizedBox(height: 12),
              _SettingsSection(
                title: 'Constraint Sidebar',
                child: _PointConstraintProfileEditor(
                  profile: resolvePointConstraintProfile(
                    auto,
                    startPoseSelected: startPoseSelected,
                    ref: selectedRef,
                  ),
                  onChanged: onUpdateSelectedPointConstraintProfile,
                ),
              ),
              const SizedBox(height: 12),
              _SettingsSection(
                title: 'Event Markers',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Markers stack with overlapping zones. They do not replace zone commands.',
                      style: const TextStyle(
                        color: Color(0xFF94A0B8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (selectedMarkers.isEmpty)
                      const Text(
                        'No point markers on this point yet. Use the Marker button in the toolbar to add one to the current selection.',
                        style: TextStyle(color: Color(0xFF94A0B8)),
                      )
                    else
                      ...selectedMarkers.map(
                        (MapEntry<int, PlannerEventMarker> entry) =>
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PointEventMarkerEditor(
                                marker: entry.value,
                                commandProfiles: commandProfiles,
                                onChanged: (PlannerEventMarker next) =>
                                    onUpdateEventMarker(entry.key, next),
                                onDelete: () => onDeleteEventMarker(entry.key),
                              ),
                            ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsSection(
                title: 'Combined Active Commands',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: effectiveCommandIds.isEmpty
                          ? const <Widget>[
                              Text(
                                'No direct markers or active event zones at this point.',
                                style: TextStyle(color: Color(0xFF94A0B8)),
                              ),
                            ]
                          : effectiveCommandIds.map((String id) {
                              final PlannerCommandProfile? profile =
                                  findCommandProfileById(commandProfiles, id);
                              return Chip(
                                label: Text(profile?.name ?? id),
                                backgroundColor: (profile?.color ??
                                        const Color(0xFF151C28))
                                    .withValues(alpha: 0.2),
                                side: BorderSide(
                                  color: profile?.color ??
                                      const Color(0xFF273246),
                                ),
                              );
                            }).toList(),
                    ),
                    if (overlappingZones.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        'Overlapping zones: ${overlappingZones.map((PlannerEventZone zone) => zone.name).join(", ")}',
                        style: const TextStyle(
                          color: Color(0xFF94A0B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (globalVariables.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _SettingsSection(
                title: 'Global Variables',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: globalVariables
                      .map(
                        (PlannerNamedValue value) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${value.name}: ${value.value.toStringAsFixed(2)} ${value.unit}',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onOpenSettings,
              child: const Text('Open Full Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventsSection extends StatelessWidget {
  const _EventsSection({
    required this.auto,
    required this.commandProfiles,
    required this.selectedMarkerIndex,
    required this.selectedEventZoneIndex,
    required this.onBeginDragEdit,
    required this.onSelectMarker,
    required this.onSelectEventZone,
    required this.onAddMarker,
    required this.onAddEventZone,
    required this.onUpdateMarker,
    required this.onDeleteMarker,
    required this.onUpdateEventZone,
    required this.onDeleteEventZone,
  });

  final PlannerAuto auto;
  final List<PlannerCommandProfile> commandProfiles;
  final int? selectedMarkerIndex;
  final int? selectedEventZoneIndex;
  final VoidCallback onBeginDragEdit;
  final ValueChanged<int> onSelectMarker;
  final ValueChanged<int> onSelectEventZone;
  final VoidCallback onAddMarker;
  final VoidCallback onAddEventZone;
  final void Function(int index, PlannerEventMarker marker) onUpdateMarker;
  final ValueChanged<int> onDeleteMarker;
  final void Function(int index, PlannerEventZone zone) onUpdateEventZone;
  final ValueChanged<int> onDeleteEventZone;

  @override
  Widget build(BuildContext context) {
    final PlannerEventMarker? selectedMarker = selectedMarkerIndex == null
        ? null
        : auto.eventMarkers[selectedMarkerIndex!];
    final PlannerEventZone? selectedZone = selectedEventZoneIndex == null
        ? null
        : auto.eventZones[selectedEventZoneIndex!];
    return Row(
      children: <Widget>[
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Event Markers',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: onAddMarker,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Marker'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 220,
                    child: _FieldEditor(
                      auto: auto,
                      tool: PlannerTool.select,
                      startPoseSelected: false,
                      selectedStepIndex: null,
                      selectedWaypointRef: null,
                      selectedEventZoneIndex: selectedEventZoneIndex,
                      onSelectEventZone: onSelectEventZone,
                      onMoveEventZone: (int index, PlannerEventZone zone) =>
                          onUpdateEventZone(index, zone),
                      onBeginDragEdit: onBeginDragEdit,
                      playbackProgress: 0,
                      onTap: (_) {},
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: auto.eventMarkers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final PlannerEventMarker marker =
                            auto.eventMarkers[index];
                        final PlannerCommandProfile? profile =
                            findCommandProfileById(
                              commandProfiles,
                              marker.commandId,
                            );
                        return Material(
                          color: index == selectedMarkerIndex
                              ? const Color(0x26FFD166)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onSelectMarker(index),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: <Widget>[
                                  const Icon(Icons.flag_circle_outlined),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(marker.name),
                                        Text(
                                          '${describeMarkerTarget(auto, marker)} • ${profile?.name ?? "No command"}',
                                          style: const TextStyle(
                                            color: Color(0xFF94A0B8),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => onDeleteMarker(index),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (selectedMarker != null)
                    _EventMarkerEditor(
                      marker: selectedMarker,
                      commandProfiles: commandProfiles,
                      onChanged: (PlannerEventMarker marker) =>
                          onUpdateMarker(selectedMarkerIndex!, marker),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Event Zones',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: onAddEventZone,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Zone'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: auto.eventZones.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final PlannerEventZone zone = auto.eventZones[index];
                        return Material(
                          color: index == selectedEventZoneIndex
                              ? zone.color.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onSelectEventZone(index),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: <Widget>[
                                  Icon(Icons.timeline, color: zone.color),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(zone.name),
                                        Text(
                                          '${zone.xMinMeters.toStringAsFixed(2)}, ${zone.yMinMeters.toStringAsFixed(2)} → ${zone.xMaxMeters.toStringAsFixed(2)}, ${zone.yMaxMeters.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: Color(0xFF94A0B8),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => onDeleteEventZone(index),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (selectedZone != null)
                    _EventZoneEditor(
                      zone: selectedZone,
                      commandProfiles: commandProfiles,
                      onChanged: (PlannerEventZone zone) =>
                          onUpdateEventZone(selectedEventZoneIndex!, zone),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _ConstraintSection extends StatelessWidget {
  const _ConstraintSection({
    required this.auto,
    required this.selectedConstraintZoneIndex,
    required this.onSelectConstraintZone,
    required this.onAddConstraintZone,
    required this.onUpdateConstraintZone,
    required this.onDeleteConstraintZone,
  });

  final PlannerAuto auto;
  final int? selectedConstraintZoneIndex;
  final ValueChanged<int> onSelectConstraintZone;
  final VoidCallback onAddConstraintZone;
  final void Function(int index, PlannerConstraintZone zone)
  onUpdateConstraintZone;
  final ValueChanged<int> onDeleteConstraintZone;

  @override
  Widget build(BuildContext context) {
    final PlannerConstraintZone? selected = selectedConstraintZoneIndex == null
        ? null
        : auto.constraintZones[selectedConstraintZoneIndex!];
    return Row(
      children: <Widget>[
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Constraint Zones',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: onAddConstraintZone,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: auto.constraintZones.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final PlannerConstraintZone zone =
                            auto.constraintZones[index];
                        return Material(
                          color: index == selectedConstraintZoneIndex
                              ? const Color(0x2659B6F8)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onSelectConstraintZone(index),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: <Widget>[
                                  const Icon(
                                    Icons.speed,
                                    color: Color(0xFF90CDF4),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(zone.name),
                                        Text(
                                          '${zone.maxVelocityMps.toStringAsFixed(1)} m/s • ${(zone.constraintFactor * 100).round()}%',
                                          style: const TextStyle(
                                            color: Color(0xFF94A0B8),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        onDeleteConstraintZone(index),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: selected == null
                  ? const Center(
                      child: Text(
                        'Select a constraint zone to edit it.',
                        style: TextStyle(color: Color(0xFF94A0B8)),
                      ),
                    )
                  : _ConstraintZoneEditor(
                      zone: selected,
                      onChanged: (PlannerConstraintZone zone) =>
                          onUpdateConstraintZone(
                            selectedConstraintZoneIndex!,
                            zone,
                          ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ObstacleSection extends StatelessWidget {
  const _ObstacleSection({
    required this.auto,
    required this.selectedZoneIndex,
    required this.onBeginDragEdit,
    required this.onSelectZone,
    required this.onAddZone,
    required this.onUpdateZone,
    required this.onDeleteZone,
  });

  final PlannerAuto auto;
  final int? selectedZoneIndex;
  final VoidCallback onBeginDragEdit;
  final ValueChanged<int> onSelectZone;
  final VoidCallback onAddZone;
  final void Function(int index, PlannerZone zone) onUpdateZone;
  final ValueChanged<int> onDeleteZone;

  @override
  Widget build(BuildContext context) {
    final PlannerZone? selectedZone = selectedZoneIndex == null
        ? null
        : auto.customZones[selectedZoneIndex!];
    return Row(
      children: <Widget>[
        Expanded(
          flex: 5,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _FieldEditor(
                auto: auto,
                tool: PlannerTool.select,
                startPoseSelected: false,
                selectedStepIndex: null,
                selectedWaypointRef: null,
                selectedZoneIndex: selectedZoneIndex,
                onSelectZone: onSelectZone,
                onMoveZone: onUpdateZone,
                onBeginDragEdit: onBeginDragEdit,
                playbackProgress: 0,
                onTap: (_) {},
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Obstacle Boxes',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: onAddZone,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: auto.customZones.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final PlannerZone zone = auto.customZones[index];
                        final bool selected = index == selectedZoneIndex;
                        return Material(
                          color: selected
                              ? const Color(0x26FF6384)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onSelectZone(index),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          zone.label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          '${zone.xMinMeters.toStringAsFixed(2)}, ${zone.yMinMeters.toStringAsFixed(2)} → ${zone.xMaxMeters.toStringAsFixed(2)}, ${zone.yMaxMeters.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: Color(0xFF94A0B8),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => onDeleteZone(index),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (selectedZone != null)
                    _ZoneEditor(
                      zone: selectedZone,
                      onChanged: (PlannerZone zone) =>
                          onUpdateZone(selectedZoneIndex!, zone),
                    )
                  else
                    const Text(
                      'Add or select a keep-out box to edit it.',
                      style: TextStyle(color: Color(0xFF94A0B8)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommandsSection extends StatelessWidget {
  const _CommandsSection({
    required this.commandProfiles,
    required this.onUpdateProfiles,
  });

  final List<PlannerCommandProfile> commandProfiles;
  final ValueChanged<List<PlannerCommandProfile>> onUpdateProfiles;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Named Commands',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    final List<PlannerCommandProfile> profiles =
                        <PlannerCommandProfile>[
                          ...commandProfiles,
                          PlannerCommandProfile(
                            id: 'cmd-${DateTime.now().microsecondsSinceEpoch}',
                            name: 'New Command',
                            requestedState: 'IDLING',
                            colorHex: '#E8EEFC',
                          ),
                        ];
                    onUpdateProfiles(profiles);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: commandProfiles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  final PlannerCommandProfile profile = commandProfiles[index];
                  return _CommandProfileCard(
                    profile: profile,
                    onChanged: (PlannerCommandProfile next) {
                      final List<PlannerCommandProfile> profiles =
                          <PlannerCommandProfile>[...commandProfiles];
                      profiles[index] = next;
                      onUpdateProfiles(profiles);
                    },
                    onDelete: commandProfiles.length <= 1
                        ? null
                        : () {
                            final List<PlannerCommandProfile> profiles =
                                <PlannerCommandProfile>[...commandProfiles]
                                  ..removeAt(index);
                            onUpdateProfiles(profiles);
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoGalleryCard extends StatelessWidget {
  const _AutoGalleryCard({
    required this.auto,
    required this.selected,
    required this.onTap,
  });

  final PlannerAuto auto;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0x1A39D98A) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFF39D98A)
                  : const Color(0xFF273246),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                auto.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                auto.folder,
                style: const TextStyle(
                  color: Color(0xFFFFD166),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${auto.steps.length} steps • ${auto.updatedAt.hour.toString().padLeft(2, '0')}:${auto.updatedAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Color(0xFF94A0B8), fontSize: 12),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 90,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ColoredBox(
                      color: const Color(0xFF0B0E14),
                      child: Center(
                        child: Image.asset(
                          fieldBackgroundAsset,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    CustomPaint(
                      painter: _FieldPreviewPainter(
                        auto: auto,
                        startPoseSelected: false,
                        selectedStepIndex: null,
                        selectedWaypointRef: null,
                        selectedZoneIndex: null,
                        selectedEventZoneIndex: null,
                        mini: true,
                        playbackProgress: 0,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip({
    required this.tool,
    required this.commandProfiles,
    required this.draftCommandId,
    required this.draftHeadingDeg,
    required this.onToolChanged,
    required this.onDraftCommandChanged,
    required this.onHeadingChanged,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
    required this.onAddEventMarker,
    required this.onAddEventZone,
    required this.onAddConstraintZone,
    required this.onAddObstacleZone,
  });

  final PlannerTool tool;
  final List<PlannerCommandProfile> commandProfiles;
  final String draftCommandId;
  final double draftHeadingDeg;
  final ValueChanged<PlannerTool> onToolChanged;
  final ValueChanged<String> onDraftCommandChanged;
  final ValueChanged<double> onHeadingChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onAddEventMarker;
  final VoidCallback onAddEventZone;
  final VoidCallback onAddConstraintZone;
  final VoidCallback onAddObstacleZone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: canUndo ? onUndo : null,
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
            ),
            FilledButton.tonalIcon(
              onPressed: canRedo ? onRedo : null,
              icon: const Icon(Icons.redo),
              label: const Text('Redo'),
            ),
            const SizedBox(width: 6),
            _ToolButton(
              label: 'Select',
              active: tool == PlannerTool.select,
              onTap: () => onToolChanged(PlannerTool.select),
            ),
            _ToolButton(
              label: 'Start Pose',
              active: tool == PlannerTool.startPose,
              onTap: () => onToolChanged(PlannerTool.startPose),
            ),
            _ToolButton(
              label: 'Add Step',
              active: tool == PlannerTool.addStep,
              onTap: () => onToolChanged(PlannerTool.addStep),
            ),
            _ToolButton(
              label: 'Add Waypoint',
              active: tool == PlannerTool.addWaypoint,
              onTap: () => onToolChanged(PlannerTool.addWaypoint),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onAddEventMarker,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Marker'),
            ),
            FilledButton.tonalIcon(
              onPressed: onAddEventZone,
              icon: const Icon(Icons.linear_scale),
              label: const Text('Event Zone'),
            ),
            FilledButton.tonalIcon(
              onPressed: onAddConstraintZone,
              icon: const Icon(Icons.speed),
              label: const Text('Constraint'),
            ),
            FilledButton.tonalIcon(
              onPressed: onAddObstacleZone,
              icon: const Icon(Icons.crop_square),
              label: const Text('Obstacle'),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: draftCommandId,
              onChanged: (String? commandId) {
                if (commandId != null) {
                  onDraftCommandChanged(commandId);
                }
              },
              items: commandProfiles
                  .map(
                    (PlannerCommandProfile profile) => DropdownMenuItem<String>(
                      value: profile.id,
                      child: Text(profile.name),
                    ),
                  )
                  .toList(),
            ),
            SizedBox(
              width: 110,
              child: TextFormField(
                initialValue: draftHeadingDeg.toStringAsFixed(0),
                decoration: const InputDecoration(labelText: 'Heading'),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                onChanged: (String value) =>
                    onHeadingChanged(double.tryParse(value) ?? draftHeadingDeg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: active
            ? const Color(0x26FFD166)
            : const Color(0xFF151C28),
        foregroundColor: active
            ? const Color(0xFFFFE8AD)
            : const Color(0xFFE8EEFC),
        side: BorderSide(
          color: active ? const Color(0xFFFFD166) : const Color(0xFF273246),
        ),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}

enum _FieldDragTargetType {
  startPose,
  step,
  waypoint,
  obstacleMove,
  obstacleLeft,
  obstacleRight,
  obstacleTop,
  obstacleBottom,
  eventZoneMove,
  eventZoneLeft,
  eventZoneRight,
  eventZoneTop,
  eventZoneBottom,
}

class _FieldDragTarget {
  const _FieldDragTarget({
    required this.type,
    required this.index,
    this.secondaryIndex,
  });

  final _FieldDragTargetType type;
  final int index;
  final int? secondaryIndex;
}

class _FieldEditor extends StatefulWidget {
  const _FieldEditor({
    required this.auto,
    required this.tool,
    required this.startPoseSelected,
    required this.selectedStepIndex,
    required this.selectedWaypointRef,
    required this.playbackProgress,
    required this.onTap,
    this.onBeginDragEdit,
    this.onSelectStartPose,
    this.onSelectStep,
    this.onSelectWaypoint,
    this.onMoveStartPose,
    this.onMoveStep,
    this.onMoveWaypoint,
    this.selectedZoneIndex,
    this.onSelectZone,
    this.onMoveZone,
    this.selectedEventZoneIndex,
    this.onSelectEventZone,
    this.onMoveEventZone,
  });

  final PlannerAuto auto;
  final PlannerTool tool;
  final bool startPoseSelected;
  final int? selectedStepIndex;
  final PlannerWaypointRef? selectedWaypointRef;
  final double playbackProgress;
  final ValueChanged<Offset> onTap;
  final VoidCallback? onBeginDragEdit;
  final VoidCallback? onSelectStartPose;
  final ValueChanged<int>? onSelectStep;
  final ValueChanged<PlannerWaypointRef>? onSelectWaypoint;
  final ValueChanged<PlannerPose>? onMoveStartPose;
  final void Function(int index, PlannerPose pose)? onMoveStep;
  final void Function(int stepIndex, int waypointIndex, PlannerPose pose)?
  onMoveWaypoint;
  final int? selectedZoneIndex;
  final ValueChanged<int>? onSelectZone;
  final void Function(int index, PlannerZone zone)? onMoveZone;
  final int? selectedEventZoneIndex;
  final ValueChanged<int>? onSelectEventZone;
  final void Function(int index, PlannerEventZone zone)? onMoveEventZone;

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  _FieldDragTarget? _dragTarget;
  PlannerPose? _dragFieldPose;
  PlannerZone? _dragObstacleStart;
  PlannerEventZone? _dragEventZoneStart;
  String? _dragLabel;

  PlannerPose _offsetToFieldPose(Offset localPosition, Size size) {
    final Rect fieldRect = resolvePlayableFieldRect(size);
    final double normalizedX =
        ((localPosition.dx - fieldRect.left) / fieldRect.width).clamp(0.0, 1.0);
    final double normalizedY =
        ((localPosition.dy - fieldRect.top) / fieldRect.height).clamp(0.0, 1.0);
    return PlannerPose(
      xMeters: normalizedX * fieldLengthMeters,
      yMeters: fieldWidthMeters - (normalizedY * fieldWidthMeters),
      headingDeg: 0,
    );
  }

  Offset _fieldPoseToCanvas(PlannerPose pose, Size size) {
    final Rect fieldRect = resolvePlayableFieldRect(size);
    return Offset(
      fieldRect.left + (pose.xMeters / fieldLengthMeters * fieldRect.width),
      fieldRect.bottom - (pose.yMeters / fieldWidthMeters * fieldRect.height),
    );
  }

  Rect _zoneToCanvasRect(
    double xMin,
    double yMin,
    double xMax,
    double yMax,
    Size size,
  ) {
    final Rect fieldRect = resolvePlayableFieldRect(size);
    return Rect.fromLTRB(
      fieldRect.left + (xMin / fieldLengthMeters * fieldRect.width),
      fieldRect.bottom - (yMax / fieldWidthMeters * fieldRect.height),
      fieldRect.left + (xMax / fieldLengthMeters * fieldRect.width),
      fieldRect.bottom - (yMin / fieldWidthMeters * fieldRect.height),
    );
  }

  _FieldDragTarget? _hitTestRectHandles(
    Offset localPosition,
    Rect rect,
    int index, {
    required bool obstacle,
  }) {
    const double handleRadius = 16;
    final Map<_FieldDragTargetType, Offset> handles =
        <_FieldDragTargetType, Offset>{
          obstacle
              ? _FieldDragTargetType.obstacleLeft
              : _FieldDragTargetType.eventZoneLeft: Offset(
            rect.left,
            rect.center.dy,
          ),
          obstacle
              ? _FieldDragTargetType.obstacleRight
              : _FieldDragTargetType.eventZoneRight: Offset(
            rect.right,
            rect.center.dy,
          ),
          obstacle
              ? _FieldDragTargetType.obstacleTop
              : _FieldDragTargetType.eventZoneTop: Offset(
            rect.center.dx,
            rect.top,
          ),
          obstacle
              ? _FieldDragTargetType.obstacleBottom
              : _FieldDragTargetType.eventZoneBottom: Offset(
            rect.center.dx,
            rect.bottom,
          ),
        };
    for (final MapEntry<_FieldDragTargetType, Offset> entry
        in handles.entries) {
      if ((entry.value - localPosition).distance <= handleRadius) {
        return _FieldDragTarget(type: entry.key, index: index);
      }
    }
    if (rect.contains(localPosition)) {
      return _FieldDragTarget(
        type: obstacle
            ? _FieldDragTargetType.obstacleMove
            : _FieldDragTargetType.eventZoneMove,
        index: index,
      );
    }
    return null;
  }

  _FieldDragTarget? _hitTest(Offset localPosition, Size size) {
    const double pointHitRadius = 18;
    if (widget.onMoveZone != null && widget.auto.customZones.isNotEmpty) {
      if (widget.selectedZoneIndex != null) {
        final PlannerZone selectedZone =
            widget.auto.customZones[widget.selectedZoneIndex!];
        final _FieldDragTarget? selectedHandle = _hitTestRectHandles(
          localPosition,
          _zoneToCanvasRect(
            selectedZone.xMinMeters,
            selectedZone.yMinMeters,
            selectedZone.xMaxMeters,
            selectedZone.yMaxMeters,
            size,
          ),
          widget.selectedZoneIndex!,
          obstacle: true,
        );
        if (selectedHandle != null) {
          return selectedHandle;
        }
      }
      for (
        int index = widget.auto.customZones.length - 1;
        index >= 0;
        index -= 1
      ) {
        final PlannerZone zone = widget.auto.customZones[index];
        final Rect rect = _zoneToCanvasRect(
          zone.xMinMeters,
          zone.yMinMeters,
          zone.xMaxMeters,
          zone.yMaxMeters,
          size,
        );
        if (rect.inflate(8).contains(localPosition)) {
          widget.onSelectZone?.call(index);
          return _FieldDragTarget(
            type: _FieldDragTargetType.obstacleMove,
            index: index,
          );
        }
      }
    }
    if (widget.onMoveEventZone != null && widget.auto.eventZones.isNotEmpty) {
      if (widget.selectedEventZoneIndex != null) {
        final PlannerEventZone selectedZone =
            widget.auto.eventZones[widget.selectedEventZoneIndex!];
        final _FieldDragTarget? selectedHandle = _hitTestRectHandles(
          localPosition,
          _zoneToCanvasRect(
            selectedZone.xMinMeters,
            selectedZone.yMinMeters,
            selectedZone.xMaxMeters,
            selectedZone.yMaxMeters,
            size,
          ),
          widget.selectedEventZoneIndex!,
          obstacle: false,
        );
        if (selectedHandle != null) {
          return selectedHandle;
        }
      }
      for (
        int index = widget.auto.eventZones.length - 1;
        index >= 0;
        index -= 1
      ) {
        final PlannerEventZone zone = widget.auto.eventZones[index];
        final Rect rect = _zoneToCanvasRect(
          zone.xMinMeters,
          zone.yMinMeters,
          zone.xMaxMeters,
          zone.yMaxMeters,
          size,
        );
        if (rect.inflate(8).contains(localPosition)) {
          widget.onSelectEventZone?.call(index);
          return _FieldDragTarget(
            type: _FieldDragTargetType.eventZoneMove,
            index: index,
          );
        }
      }
    }
    if (widget.tool != PlannerTool.select) {
      return null;
    }
    double bestDistance = double.infinity;
    _FieldDragTarget? bestTarget;
    final double startDistance =
        (_fieldPoseToCanvas(widget.auto.startPose, size) - localPosition)
            .distance;
    if (startDistance < pointHitRadius) {
      bestDistance = startDistance;
      bestTarget = const _FieldDragTarget(
        type: _FieldDragTargetType.startPose,
        index: -1,
      );
    }
    for (
      int stepIndex = 0;
      stepIndex < widget.auto.steps.length;
      stepIndex += 1
    ) {
      final PlannerStep step = widget.auto.steps[stepIndex];
      final double stepDistance =
          (_fieldPoseToCanvas(step.pose, size) - localPosition).distance;
      if (stepDistance < pointHitRadius && stepDistance < bestDistance) {
        bestDistance = stepDistance;
        bestTarget = _FieldDragTarget(
          type: _FieldDragTargetType.step,
          index: stepIndex,
        );
      }
      for (
        int waypointIndex = 0;
        waypointIndex < step.routeWaypoints.length;
        waypointIndex += 1
      ) {
        final double waypointDistance =
            (_fieldPoseToCanvas(step.routeWaypoints[waypointIndex].pose, size) -
                    localPosition)
                .distance;
        if (waypointDistance < pointHitRadius &&
            waypointDistance < bestDistance) {
          bestDistance = waypointDistance;
          bestTarget = _FieldDragTarget(
            type: _FieldDragTargetType.waypoint,
            index: stepIndex,
            secondaryIndex: waypointIndex,
          );
        }
      }
    }
    return bestTarget;
  }

  void _startDrag(DragStartDetails details, Size size) {
    final _FieldDragTarget? target = _hitTest(details.localPosition, size);
    if (target == null) {
      return;
    }
    widget.onBeginDragEdit?.call();
    _dragTarget = target;
    _dragFieldPose = _offsetToFieldPose(details.localPosition, size);
    _dragObstacleStart = target.type.name.startsWith('obstacle')
        ? widget.auto.customZones[target.index]
        : null;
    _dragEventZoneStart = target.type.name.startsWith('eventZone')
        ? widget.auto.eventZones[target.index]
        : null;
  }

  void _updateDrag(DragUpdateDetails details, Size size) {
    if (_dragTarget == null || _dragFieldPose == null) {
      return;
    }
    final PlannerPose currentPose = _offsetToFieldPose(
      details.localPosition,
      size,
    );
    final _FieldDragTarget target = _dragTarget!;
    switch (target.type) {
      case _FieldDragTargetType.startPose:
        widget.onSelectStartPose?.call();
        widget.onMoveStartPose?.call(
          clampPoseToField(
            widget.auto.startPose.copyWith(
              xMeters: currentPose.xMeters,
              yMeters: currentPose.yMeters,
            ),
          ),
        );
        _dragLabel =
            'Start Pose  x ${currentPose.xMeters.toStringAsFixed(2)}  y ${currentPose.yMeters.toStringAsFixed(2)}';
        break;
      case _FieldDragTargetType.step:
        final PlannerStep step = widget.auto.steps[target.index];
        widget.onSelectWaypoint?.call(
          PlannerWaypointRef(stepIndex: target.index),
        );
        widget.onSelectStep?.call(target.index);
        widget.onMoveStep?.call(
          target.index,
          clampPoseToField(
            step.pose.copyWith(
              xMeters: currentPose.xMeters,
              yMeters: currentPose.yMeters,
            ),
          ),
        );
        _dragLabel =
            '${step.label}  x ${currentPose.xMeters.toStringAsFixed(2)}  y ${currentPose.yMeters.toStringAsFixed(2)}';
        break;
      case _FieldDragTargetType.waypoint:
        widget.onSelectWaypoint?.call(
          PlannerWaypointRef(
            stepIndex: target.index,
            routeWaypointIndex: target.secondaryIndex,
          ),
        );
        widget.onSelectStep?.call(target.index);
        widget.onMoveWaypoint?.call(
          target.index,
          target.secondaryIndex!,
          clampPoseToField(currentPose),
        );
        _dragLabel =
            'Waypoint ${target.secondaryIndex! + 1}  x ${currentPose.xMeters.toStringAsFixed(2)}  y ${currentPose.yMeters.toStringAsFixed(2)}';
        break;
      case _FieldDragTargetType.obstacleMove:
      case _FieldDragTargetType.obstacleLeft:
      case _FieldDragTargetType.obstacleRight:
      case _FieldDragTargetType.obstacleTop:
      case _FieldDragTargetType.obstacleBottom:
        final PlannerZone start = _dragObstacleStart!;
        final double dx = currentPose.xMeters - _dragFieldPose!.xMeters;
        final double dy = currentPose.yMeters - _dragFieldPose!.yMeters;
        PlannerZone moved = start;
        switch (target.type) {
          case _FieldDragTargetType.obstacleMove:
            moved = start.copyWith(
              xMinMeters: start.xMinMeters + dx,
              xMaxMeters: start.xMaxMeters + dx,
              yMinMeters: start.yMinMeters + dy,
              yMaxMeters: start.yMaxMeters + dy,
            );
            break;
          case _FieldDragTargetType.obstacleLeft:
            moved = start.copyWith(xMinMeters: currentPose.xMeters);
            break;
          case _FieldDragTargetType.obstacleRight:
            moved = start.copyWith(xMaxMeters: currentPose.xMeters);
            break;
          case _FieldDragTargetType.obstacleTop:
            moved = start.copyWith(yMaxMeters: currentPose.yMeters);
            break;
          case _FieldDragTargetType.obstacleBottom:
            moved = start.copyWith(yMinMeters: currentPose.yMeters);
            break;
          default:
            break;
        }
        final PlannerZone clamped = clampPlannerZoneToField(moved);
        widget.onSelectZone?.call(target.index);
        widget.onMoveZone?.call(target.index, clamped);
        _dragLabel =
            '${clamped.label}  ${clamped.xMinMeters.toStringAsFixed(2)}, ${clamped.yMinMeters.toStringAsFixed(2)} → ${clamped.xMaxMeters.toStringAsFixed(2)}, ${clamped.yMaxMeters.toStringAsFixed(2)}';
        break;
      case _FieldDragTargetType.eventZoneMove:
      case _FieldDragTargetType.eventZoneLeft:
      case _FieldDragTargetType.eventZoneRight:
      case _FieldDragTargetType.eventZoneTop:
      case _FieldDragTargetType.eventZoneBottom:
        final PlannerEventZone start = _dragEventZoneStart!;
        final double dx = currentPose.xMeters - _dragFieldPose!.xMeters;
        final double dy = currentPose.yMeters - _dragFieldPose!.yMeters;
        PlannerEventZone moved = start;
        switch (target.type) {
          case _FieldDragTargetType.eventZoneMove:
            moved = start.copyWith(
              xMinMeters: start.xMinMeters + dx,
              xMaxMeters: start.xMaxMeters + dx,
              yMinMeters: start.yMinMeters + dy,
              yMaxMeters: start.yMaxMeters + dy,
            );
            break;
          case _FieldDragTargetType.eventZoneLeft:
            moved = start.copyWith(xMinMeters: currentPose.xMeters);
            break;
          case _FieldDragTargetType.eventZoneRight:
            moved = start.copyWith(xMaxMeters: currentPose.xMeters);
            break;
          case _FieldDragTargetType.eventZoneTop:
            moved = start.copyWith(yMaxMeters: currentPose.yMeters);
            break;
          case _FieldDragTargetType.eventZoneBottom:
            moved = start.copyWith(yMinMeters: currentPose.yMeters);
            break;
          default:
            break;
        }
        final PlannerEventZone clamped = clampEventZoneToField(moved);
        widget.onSelectEventZone?.call(target.index);
        widget.onMoveEventZone?.call(target.index, clamped);
        _dragLabel =
            '${clamped.name}  ${clamped.xMinMeters.toStringAsFixed(2)}, ${clamped.yMinMeters.toStringAsFixed(2)} → ${clamped.xMaxMeters.toStringAsFixed(2)}, ${clamped.yMaxMeters.toStringAsFixed(2)}';
        break;
    }
    setState(() {});
  }

  void _endDrag() {
    setState(() {
      _dragTarget = null;
      _dragFieldPose = null;
      _dragObstacleStart = null;
      _dragEventZoneStart = null;
      _dragLabel = null;
    });
  }

  void _handleTap(TapUpDetails details, Size size) {
    final _FieldDragTarget? target = _hitTest(details.localPosition, size);
    if (target != null && widget.tool == PlannerTool.select) {
      switch (target.type) {
        case _FieldDragTargetType.startPose:
          widget.onSelectStartPose?.call();
          break;
        case _FieldDragTargetType.step:
          widget.onSelectWaypoint?.call(
            PlannerWaypointRef(stepIndex: target.index),
          );
          widget.onSelectStep?.call(target.index);
          break;
        case _FieldDragTargetType.waypoint:
          widget.onSelectWaypoint?.call(
            PlannerWaypointRef(
              stepIndex: target.index,
              routeWaypointIndex: target.secondaryIndex,
            ),
          );
          widget.onSelectStep?.call(target.index);
          break;
        case _FieldDragTargetType.obstacleMove:
        case _FieldDragTargetType.obstacleLeft:
        case _FieldDragTargetType.obstacleRight:
        case _FieldDragTargetType.obstacleTop:
        case _FieldDragTargetType.obstacleBottom:
          widget.onSelectZone?.call(target.index);
          break;
        case _FieldDragTargetType.eventZoneMove:
        case _FieldDragTargetType.eventZoneLeft:
        case _FieldDragTargetType.eventZoneRight:
        case _FieldDragTargetType.eventZoneTop:
        case _FieldDragTargetType.eventZoneBottom:
          widget.onSelectEventZone?.call(target.index);
          break;
      }
      return;
    }
    final PlannerPose pose = _offsetToFieldPose(details.localPosition, size);
    widget.onTap(Offset(pose.xMeters, pose.yMeters));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size fieldSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF0F141D),
            border: Border.all(color: const Color(0xFF273246)),
          ),
          child: GestureDetector(
            onPanStart: (DragStartDetails details) =>
                _startDrag(details, fieldSize),
            onPanUpdate: (DragUpdateDetails details) =>
                _updateDrag(details, fieldSize),
            onPanEnd: (_) => _endDrag(),
            onPanCancel: _endDrag,
            onTapUp: (TapUpDetails details) => _handleTap(details, fieldSize),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(
                  color: const Color(0xFF0B0E14),
                  child: Center(
                    child: Image.asset(
                      fieldBackgroundAsset,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _FieldPreviewPainter(
                    auto: widget.auto,
                    startPoseSelected: widget.startPoseSelected,
                    selectedStepIndex: widget.selectedStepIndex,
                    selectedWaypointRef: widget.selectedWaypointRef,
                    selectedZoneIndex: widget.selectedZoneIndex,
                    selectedEventZoneIndex: widget.selectedEventZoneIndex,
                    mini: false,
                    playbackProgress: widget.playbackProgress,
                  ),
                  child: const SizedBox.expand(),
                ),
                if (_dragLabel != null)
                  Positioned(
                    left: 14,
                    top: 14,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xE611161F),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF273246)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          _dragLabel!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FieldPreviewPainter extends CustomPainter {
  _FieldPreviewPainter({
    required this.auto,
    required this.startPoseSelected,
    required this.selectedStepIndex,
    required this.selectedWaypointRef,
    required this.selectedZoneIndex,
    required this.selectedEventZoneIndex,
    required this.mini,
    required this.playbackProgress,
  });

  final PlannerAuto auto;
  final bool startPoseSelected;
  final int? selectedStepIndex;
  final PlannerWaypointRef? selectedWaypointRef;
  final int? selectedZoneIndex;
  final int? selectedEventZoneIndex;
  final bool mini;
  final double playbackProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Rect fieldRect = resolvePlayableFieldRect(size);
    final Paint border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = mini ? 1 : 1.4
      ..color = const Color(0xFF273246);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(mini ? 1 : 2),
        const Radius.circular(18),
      ),
      border,
    );

    final Paint centerLine = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    final double safeX =
        fieldRect.left + ((8.15 / fieldLengthMeters) * fieldRect.width);
    canvas.drawLine(
      Offset(safeX, fieldRect.top),
      Offset(safeX, fieldRect.bottom),
      centerLine,
    );

    for (final PlannerZone zone in auto.customZones) {
      final Rect zoneRect = Rect.fromLTRB(
        fieldRect.left +
            (zone.xMinMeters / fieldLengthMeters * fieldRect.width),
        fieldRect.bottom -
            (zone.yMaxMeters / fieldWidthMeters * fieldRect.height),
        fieldRect.left +
            (zone.xMaxMeters / fieldLengthMeters * fieldRect.width),
        fieldRect.bottom -
            (zone.yMinMeters / fieldWidthMeters * fieldRect.height),
      );
      canvas.drawRect(zoneRect, Paint()..color = const Color(0x30FF6384));
      canvas.drawRect(
        zoneRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xAAFF6384)
          ..strokeWidth = 1,
      );
    }
    if (!mini &&
        selectedZoneIndex != null &&
        selectedZoneIndex! < auto.customZones.length) {
      final PlannerZone zone = auto.customZones[selectedZoneIndex!];
      _drawSelectionHandles(
        canvas,
        Rect.fromLTRB(
          fieldRect.left +
              (zone.xMinMeters / fieldLengthMeters * fieldRect.width),
          fieldRect.bottom -
              (zone.yMaxMeters / fieldWidthMeters * fieldRect.height),
          fieldRect.left +
              (zone.xMaxMeters / fieldLengthMeters * fieldRect.width),
          fieldRect.bottom -
              (zone.yMinMeters / fieldWidthMeters * fieldRect.height),
        ),
        const Color(0xFFFF6384),
      );
    }

    for (final PlannerConstraintZone zone in auto.constraintZones) {
      _drawProgressBand(
        canvas,
        size,
        zone.startProgress,
        zone.endProgress,
        const Color(0x4459B6F8),
      );
    }

    for (final PlannerEventZone zone in auto.eventZones) {
      final Rect zoneRect = Rect.fromLTRB(
        fieldRect.left +
            (zone.xMinMeters / fieldLengthMeters * fieldRect.width),
        fieldRect.bottom -
            (zone.yMaxMeters / fieldWidthMeters * fieldRect.height),
        fieldRect.left +
            (zone.xMaxMeters / fieldLengthMeters * fieldRect.width),
        fieldRect.bottom -
            (zone.yMinMeters / fieldWidthMeters * fieldRect.height),
      );
      canvas.drawRect(
        zoneRect,
        Paint()..color = zone.color.withValues(alpha: 0.16),
      );
      canvas.drawRect(
        zoneRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = mini ? 1 : 1.5
          ..color = zone.color,
      );
    }
    if (!mini &&
        selectedEventZoneIndex != null &&
        selectedEventZoneIndex! < auto.eventZones.length) {
      final PlannerEventZone zone = auto.eventZones[selectedEventZoneIndex!];
      _drawSelectionHandles(
        canvas,
        Rect.fromLTRB(
          fieldRect.left +
              (zone.xMinMeters / fieldLengthMeters * fieldRect.width),
          fieldRect.bottom -
              (zone.yMaxMeters / fieldWidthMeters * fieldRect.height),
          fieldRect.left +
              (zone.xMaxMeters / fieldLengthMeters * fieldRect.width),
          fieldRect.bottom -
              (zone.yMinMeters / fieldWidthMeters * fieldRect.height),
        ),
        zone.color,
      );
    }

    final List<PlannerPose> route = <PlannerPose>[auto.startPose];
    for (final PlannerStep step in auto.steps) {
      route.addAll(
        step.routeWaypoints.map((PlannerWaypoint waypoint) => waypoint.pose),
      );
      route.add(step.pose);
    }

    PlannerPose previous = auto.startPose;
    for (int i = 0; i < auto.steps.length; i += 1) {
      final PlannerStep step = auto.steps[i];
      final List<PlannerPose> segment = <PlannerPose>[
        previous,
        ...step.routeWaypoints.map((PlannerWaypoint waypoint) => waypoint.pose),
        step.pose,
      ];
      final Paint pathPaint = Paint()
        ..color = step.requestedState.color
        ..strokeWidth = mini ? 1.8 : 3.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final Path path = Path();
      for (int j = 0; j < segment.length; j += 1) {
        final Offset point = _toCanvas(segment[j], fieldRect);
        if (j == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, pathPaint);
      previous = step.pose;
    }

    _drawRobotBox(
      canvas,
      fieldRect,
      auto.startPose,
      startPoseSelected
          ? const Color(0xFFFFD166)
          : const Color(0xFFFFE8AD),
      mini ? 0.55 : 0.85,
    );
    _drawPointBadges(
      canvas,
      fieldRect,
      auto.startPose,
      markerCount: auto.eventMarkers
          .where(
            (PlannerEventMarker marker) =>
                marker.targetType == PlannerEventMarkerTargetType.startPose,
          )
          .length,
      hasConstraints: auto.startPoseConstraintProfile.hasAnyValues,
      selected: startPoseSelected,
    );

    for (int i = 0; i < auto.steps.length; i += 1) {
      final PlannerStep step = auto.steps[i];
      for (final PlannerWaypoint waypoint in step.routeWaypoints) {
        _drawRobotBox(
          canvas,
          fieldRect,
          waypoint.pose,
          step.requestedState.color,
          mini ? 0.35 : 0.48,
        );
        _drawPointBadges(
          canvas,
          fieldRect,
          waypoint.pose,
          markerCount: auto.eventMarkers
              .where(
                (PlannerEventMarker marker) =>
                    marker.targetType ==
                        PlannerEventMarkerTargetType.routeWaypoint &&
                    marker.stepIndex == i &&
                    marker.routeWaypointIndex == step.routeWaypoints.indexOf(
                      waypoint,
                    ),
              )
              .length,
          hasConstraints: waypoint.constraintProfile.hasAnyValues,
          selected:
              selectedWaypointRef?.stepIndex == i &&
              selectedWaypointRef?.routeWaypointIndex ==
                  step.routeWaypoints.indexOf(waypoint),
        );
      }
      _drawRobotBox(
        canvas,
        fieldRect,
        step.pose,
        step.requestedState.color,
        i == selectedStepIndex ? (mini ? 0.6 : 0.92) : (mini ? 0.5 : 0.72),
      );
      _drawPointBadges(
        canvas,
        fieldRect,
        step.pose,
        markerCount: auto.eventMarkers
            .where(
              (PlannerEventMarker marker) =>
                  marker.targetType == PlannerEventMarkerTargetType.stepAnchor &&
                  marker.stepIndex == i,
            )
            .length,
        hasConstraints: step.anchorConstraintProfile.hasAnyValues,
        selected:
            !startPoseSelected &&
            selectedWaypointRef?.stepIndex == i &&
            selectedWaypointRef?.routeWaypointIndex == null,
      );
    }

    if (!mini) {
      _drawRobotBox(
        canvas,
        fieldRect,
        sampleAutoPoseAtProgress(auto, playbackProgress),
        const Color(0xFFE8EEFC),
        0.94,
      );
    }
  }

  Offset _toCanvas(PlannerPose pose, Rect fieldRect) {
    return Offset(
      fieldRect.left + (pose.xMeters / fieldLengthMeters * fieldRect.width),
      fieldRect.bottom - (pose.yMeters / fieldWidthMeters * fieldRect.height),
    );
  }

  void _drawRobotBox(
    Canvas canvas,
    Rect fieldRect,
    PlannerPose pose,
    Color color,
    double scale,
  ) {
    final Offset center = _toCanvas(pose, fieldRect);
    final double width =
        (auto.settings.robotLengthMeters / fieldLengthMeters) *
        fieldRect.width *
        scale;
    final double height =
        (auto.settings.robotWidthMeters / fieldWidthMeters) *
        fieldRect.height *
        scale;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-pose.headingDeg * math.pi / 180);
    final Rect rect = Rect.fromCenter(
      center: Offset.zero,
      width: width,
      height: height,
    );
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = mini ? 1 : 1.8
        ..color = color,
    );
    canvas.drawLine(
      Offset.zero,
      Offset(width / 2, 0),
      Paint()
        ..color = color
        ..strokeWidth = mini ? 1 : 1.6,
    );
    canvas.restore();
  }

  void _drawProgressBand(
    Canvas canvas,
    Size size,
    double startProgress,
    double endProgress,
    Color color,
  ) {
    final PlannerPose startPose = sampleAutoPoseAtProgress(
      auto,
      math.min(startProgress, endProgress),
    );
    final PlannerPose endPose = sampleAutoPoseAtProgress(
      auto,
      math.max(startProgress, endProgress),
    );
    final Rect fieldRect = resolvePlayableFieldRect(size);
    final Offset start = _toCanvas(startPose, fieldRect);
    final Offset end = _toCanvas(endPose, fieldRect);
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = mini ? 8 : 16,
    );
  }

  @override
  bool shouldRepaint(covariant _FieldPreviewPainter oldDelegate) {
    return oldDelegate.auto != auto ||
        oldDelegate.startPoseSelected != startPoseSelected ||
        oldDelegate.selectedStepIndex != selectedStepIndex ||
        oldDelegate.selectedWaypointRef != selectedWaypointRef ||
        oldDelegate.selectedZoneIndex != selectedZoneIndex ||
        oldDelegate.selectedEventZoneIndex != selectedEventZoneIndex ||
        oldDelegate.mini != mini ||
        oldDelegate.playbackProgress != playbackProgress;
  }

  void _drawPointBadges(
    Canvas canvas,
    Rect fieldRect,
    PlannerPose pose, {
    required int markerCount,
    required bool hasConstraints,
    required bool selected,
  }) {
    if (!hasConstraints && markerCount <= 0) {
      return;
    }
    final Offset center = _toCanvas(pose, fieldRect);
    final Offset markerOffset = center + const Offset(14, -14);
    if (hasConstraints) {
      canvas.drawCircle(
        center + const Offset(-14, -14),
        mini ? 4 : 6,
        Paint()..color = const Color(0xFF59B6F8),
      );
    }
    if (markerCount > 0) {
      canvas.drawCircle(
        markerOffset,
        mini ? 5 : 8,
        Paint()..color = const Color(0xFFFFD166),
      );
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: markerCount.toString(),
          style: TextStyle(
            color: const Color(0xFF0B0E14),
            fontSize: mini ? 7 : 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          markerOffset.dx - (painter.width / 2),
          markerOffset.dy - (painter.height / 2),
        ),
      );
    }
    if (selected && !mini) {
      canvas.drawCircle(
        center,
        16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xAAE8EEFC),
      );
    }
  }

  void _drawSelectionHandles(Canvas canvas, Rect rect, Color color) {
    final Paint outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.95);
    canvas.drawRect(rect, outline);
    final Paint fill = Paint()..color = color;
    final List<Offset> handleCenters = <Offset>[
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      Offset(rect.center.dx, rect.top),
      Offset(rect.center.dx, rect.bottom),
    ];
    for (final Offset center in handleCenters) {
      canvas.drawCircle(center, 6, fill);
      canvas.drawCircle(
        center,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF0B0E14),
      );
    }
    final Paint arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(rect.left - 10, rect.center.dy),
      Offset(rect.left - 2, rect.center.dy),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.left - 10, rect.center.dy),
      Offset(rect.left - 6, rect.center.dy - 4),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.left - 10, rect.center.dy),
      Offset(rect.left - 6, rect.center.dy + 4),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.right + 10, rect.center.dy),
      Offset(rect.right + 2, rect.center.dy),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.right + 10, rect.center.dy),
      Offset(rect.right + 6, rect.center.dy - 4),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.right + 10, rect.center.dy),
      Offset(rect.right + 6, rect.center.dy + 4),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.center.dx, rect.top - 10),
      Offset(rect.center.dx, rect.top - 2),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.center.dx, rect.top - 10),
      Offset(rect.center.dx - 4, rect.top - 6),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.center.dx, rect.top - 10),
      Offset(rect.center.dx + 4, rect.top - 6),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.center.dx, rect.bottom + 10),
      Offset(rect.center.dx, rect.bottom + 2),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.center.dx, rect.bottom + 10),
      Offset(rect.center.dx - 4, rect.bottom + 6),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(rect.center.dx, rect.bottom + 10),
      Offset(rect.center.dx + 4, rect.bottom + 6),
      arrowPaint,
    );
  }
}

class _StepListPanel extends StatelessWidget {
  const _StepListPanel({
    required this.auto,
    required this.commandProfiles,
    required this.selectedStepIndex,
    required this.onSelectStep,
    required this.onDeleteStep,
  });

  final PlannerAuto auto;
  final List<PlannerCommandProfile> commandProfiles;
  final int? selectedStepIndex;
  final ValueChanged<int> onSelectStep;
  final ValueChanged<int> onDeleteStep;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Steps',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: auto.steps.isEmpty
                  ? const Center(
                      child: Text(
                        'Use Add Step on the field to create the route.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF94A0B8)),
                      ),
                    )
                  : ListView.separated(
                      itemBuilder: (BuildContext context, int index) {
                        final PlannerStep step = auto.steps[index];
                        PlannerCommandProfile? profile;
                        for (final PlannerCommandProfile entry
                            in commandProfiles) {
                          if (entry.id == step.commandId) {
                            profile = entry;
                            break;
                          }
                        }
                        final Color stepColor =
                            profile?.color ?? step.requestedState.color;
                        final String stepName = step.commandName.isNotEmpty
                            ? step.commandName
                            : profile?.name ?? step.requestedState.token;
                        return Material(
                          color: index == selectedStepIndex
                              ? stepColor.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onSelectStep(index),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: stepColor.withValues(alpha: 0.18),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text('${index + 1}'),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          step.label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          '$stepName • ${step.routeWaypoints.length} wp',
                                          style: const TextStyle(
                                            color: Color(0xFF94A0B8),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => onDeleteStep(index),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 8),
                      itemCount: auto.steps.length,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.auto,
    required this.commandProfiles,
    required this.selectedStepIndex,
    required this.onRenameAuto,
    required this.onUpdateSettings,
    required this.onUpdateStep,
  });

  final PlannerAuto auto;
  final List<PlannerCommandProfile> commandProfiles;
  final int? selectedStepIndex;
  final ValueChanged<String> onRenameAuto;
  final ValueChanged<PlannerSettings> onUpdateSettings;
  final ValueChanged<PlannerStep> onUpdateStep;

  @override
  Widget build(BuildContext context) {
    final PlannerStep? selectedStep = selectedStepIndex == null
        ? null
        : auto.steps[selectedStepIndex!];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ListView(
          children: <Widget>[
            const Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: auto.name,
              decoration: const InputDecoration(labelText: 'Auto Name'),
              onChanged: onRenameAuto,
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: 'Planner Tuning',
              child: Column(
                children: <Widget>[
                  _LabeledSlider(
                    label: 'Pose Blend Weight',
                    value: auto.settings.poseBlendWeight,
                    min: 0,
                    max: 1,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(poseBlendWeight: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Constraint Factor',
                    value: auto.settings.constraintFactor,
                    min: 0.3,
                    max: 1.4,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(constraintFactor: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Tolerance Meters',
                    value: auto.settings.toleranceMeters,
                    min: 0.01,
                    max: 0.2,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(toleranceMeters: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Timeout Seconds',
                    value: auto.settings.timeoutSeconds,
                    min: 0.5,
                    max: 4,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(timeoutSeconds: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'End Velocity MPS',
                    value: auto.settings.endVelocityMps,
                    min: 0,
                    max: 3,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(endVelocityMps: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Control Rate HZ',
                    value: auto.settings.controlRateHz,
                    min: 20,
                    max: 120,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(controlRateHz: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Preview Smoothing',
                    value: auto.settings.previewSmoothing,
                    min: 0,
                    max: 1,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(previewSmoothing: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Max Velocity MPS',
                    value: auto.settings.maxVelocityMps,
                    min: 0.5,
                    max: 6.0,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(maxVelocityMps: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Max Accel MPS²',
                    value: auto.settings.maxAccelerationMpsSq,
                    min: 0.5,
                    max: 6.0,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(maxAccelerationMpsSq: value),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: auto.settings.visionCorrectionEnabled,
                    title: const Text('Vision Correction Enabled'),
                    onChanged: (bool value) => onUpdateSettings(
                      auto.settings.copyWith(visionCorrectionEnabled: value),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: auto.settings.holdHeading,
                    title: const Text('Hold Heading Through Route'),
                    onChanged: (bool value) => onUpdateSettings(
                      auto.settings.copyWith(holdHeading: value),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: auto.settings.allowReverse,
                    title: const Text('Allow Reverse Segments'),
                    onChanged: (bool value) => onUpdateSettings(
                      auto.settings.copyWith(allowReverse: value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: 'Robot Envelope',
              child: Column(
                children: <Widget>[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Default box: 27.5 in × 27.5 in = 0.6985 m × 0.6985 m',
                      style: TextStyle(color: Color(0xFF94A0B8), fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _LabeledSlider(
                    label: 'Robot Width Meters',
                    value: auto.settings.robotWidthMeters,
                    min: 0.5,
                    max: 1.0,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(robotWidthMeters: value),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Robot Length Meters',
                    value: auto.settings.robotLengthMeters,
                    min: 0.5,
                    max: 1.0,
                    onChanged: (double value) => onUpdateSettings(
                      auto.settings.copyWith(robotLengthMeters: value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: 'Selected Step',
              child: selectedStep == null
                  ? const Text(
                      'Select a step on the field or in the step list to edit it.',
                      style: TextStyle(color: Color(0xFF94A0B8)),
                    )
                  : Column(
                      children: <Widget>[
                        TextFormField(
                          initialValue: selectedStep.label,
                          decoration: const InputDecoration(
                            labelText: 'Step Label',
                          ),
                          onChanged: (String value) =>
                              onUpdateStep(selectedStep.copyWith(label: value)),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: selectedStep.commandId.isNotEmpty
                              ? selectedStep.commandId
                              : commandProfiles.first.id,
                          decoration: const InputDecoration(
                            labelText: 'Named Command',
                          ),
                          items: commandProfiles
                              .map(
                                (
                                  PlannerCommandProfile profile,
                                ) => DropdownMenuItem<String>(
                                  value: profile.id,
                                  child: Text(
                                    '${profile.name} → ${profile.requestedState}',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (String? commandId) {
                            if (commandId != null) {
                              final PlannerCommandProfile profile =
                                  commandProfiles.firstWhere(
                                    (PlannerCommandProfile entry) =>
                                        entry.id == commandId,
                                    orElse: () => commandProfiles.first,
                                  );
                              onUpdateStep(
                                selectedStep.copyWith(
                                  commandId: profile.id,
                                  commandName: profile.name,
                                  requestedState: RequestedState.fromToken(
                                    profile.requestedState,
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        _LabeledSlider(
                          label: 'Wait Seconds',
                          value: selectedStep.waitSeconds,
                          min: 0,
                          max: 3,
                          onChanged: (double value) => onUpdateStep(
                            selectedStep.copyWith(waitSeconds: value),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Pose x=${selectedStep.pose.xMeters.toStringAsFixed(2)} y=${selectedStep.pose.yMeters.toStringAsFixed(2)} h=${selectedStep.pose.headingDeg.toStringAsFixed(0)}',
                          style: const TextStyle(color: Color(0xFF94A0B8)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Waypoints: ${selectedStep.routeWaypoints.length}',
                          style: const TextStyle(color: Color(0xFF94A0B8)),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneEditor extends StatelessWidget {
  const _ZoneEditor({required this.zone, required this.onChanged});

  final PlannerZone zone;
  final ValueChanged<PlannerZone> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          initialValue: zone.label,
          decoration: const InputDecoration(labelText: 'Zone Label'),
          onChanged: (String value) => onChanged(
            zone.copyWith(label: value.isEmpty ? zone.label : value),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextFormField(
                initialValue: zone.xMinMeters.toStringAsFixed(2),
                decoration: const InputDecoration(labelText: 'Min X'),
                onChanged: (String value) => onChanged(
                  zone.copyWith(
                    xMinMeters: double.tryParse(value) ?? zone.xMinMeters,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: zone.xMaxMeters.toStringAsFixed(2),
                decoration: const InputDecoration(labelText: 'Max X'),
                onChanged: (String value) => onChanged(
                  zone.copyWith(
                    xMaxMeters: double.tryParse(value) ?? zone.xMaxMeters,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextFormField(
                initialValue: zone.yMinMeters.toStringAsFixed(2),
                decoration: const InputDecoration(labelText: 'Min Y'),
                onChanged: (String value) => onChanged(
                  zone.copyWith(
                    yMinMeters: double.tryParse(value) ?? zone.yMinMeters,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: zone.yMaxMeters.toStringAsFixed(2),
                decoration: const InputDecoration(labelText: 'Max Y'),
                onChanged: (String value) => onChanged(
                  zone.copyWith(
                    yMaxMeters: double.tryParse(value) ?? zone.yMaxMeters,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: zone.locked,
          title: const Text('Locked'),
          onChanged: (bool value) => onChanged(zone.copyWith(locked: value)),
        ),
      ],
    );
  }
}

class _PointConstraintProfileEditor extends StatelessWidget {
  const _PointConstraintProfileEditor({
    required this.profile,
    required this.onChanged,
  });

  final PlannerPointConstraintProfile profile;
  final ValueChanged<PlannerPointConstraintProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: plannerConstraintCatalog.map((PlannerConstraintDefinition def) {
        if (def.type == PlannerConstraintValueType.toggle) {
          return SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(def.label),
            value: profile.toggleValue(def.id),
            onChanged: (bool enabled) =>
                onChanged(profile.setToggle(def.id, enabled)),
          );
        }
        final double? value = profile.numericValue(def.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Checkbox(
                value: value != null,
                onChanged: (bool? enabled) => onChanged(
                  profile.setNumeric(
                    def.id,
                    enabled ?? false ? (def.min ?? 0) : null,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(def.label),
                    const SizedBox(height: 6),
                    if (value != null)
                      TextFormField(
                        key: ValueKey<String>(
                          'constraint-${def.id}-${value.toStringAsFixed(4)}',
                        ),
                        initialValue: value.toStringAsFixed(2),
                        decoration: InputDecoration(
                          labelText: def.unit.isEmpty
                              ? 'Value'
                              : 'Value (${def.unit})',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        onChanged: (String raw) {
                          final double? parsed = double.tryParse(raw);
                          if (parsed == null) {
                            return;
                          }
                          onChanged(profile.setNumeric(def.id, parsed));
                        },
                      )
                    else
                      Text(
                        'Disabled',
                        style: const TextStyle(
                          color: Color(0xFF94A0B8),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _PointEventMarkerEditor extends StatelessWidget {
  const _PointEventMarkerEditor({
    required this.marker,
    required this.commandProfiles,
    required this.onChanged,
    required this.onDelete,
  });

  final PlannerEventMarker marker;
  final List<PlannerCommandProfile> commandProfiles;
  final ValueChanged<PlannerEventMarker> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF151C28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF273246)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Point Marker',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextFormField(
              key: ValueKey<String>('marker-name-${marker.id}-${marker.name}'),
              initialValue: marker.name,
              decoration: const InputDecoration(labelText: 'Marker Name'),
              onChanged: (String value) => onChanged(
                marker.copyWith(name: value.isEmpty ? marker.name : value),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: marker.commandId.isNotEmpty ? marker.commandId : null,
              decoration: const InputDecoration(labelText: 'Command'),
              items: commandProfiles
                  .map(
                    (PlannerCommandProfile profile) => DropdownMenuItem<String>(
                      value: profile.id,
                      child: Text(profile.name),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) =>
                  onChanged(marker.copyWith(commandId: value ?? '')),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey<String>('marker-notes-${marker.id}-${marker.notes}'),
              initialValue: marker.notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              onChanged: (String value) => onChanged(marker.copyWith(notes: value)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventMarkerEditor extends StatelessWidget {
  const _EventMarkerEditor({
    required this.marker,
    required this.commandProfiles,
    required this.onChanged,
  });

  final PlannerEventMarker marker;
  final List<PlannerCommandProfile> commandProfiles;
  final ValueChanged<PlannerEventMarker> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          initialValue: marker.name,
          decoration: const InputDecoration(labelText: 'Marker Name'),
          onChanged: (String value) => onChanged(
            marker.copyWith(name: value.isEmpty ? marker.name : value),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Target • ${marker.targetType.name}',
          style: const TextStyle(color: Color(0xFF94A0B8)),
        ),
        DropdownButtonFormField<String>(
          initialValue: marker.commandId.isNotEmpty ? marker.commandId : null,
          decoration: const InputDecoration(labelText: 'Command'),
          items: commandProfiles
              .map(
                (PlannerCommandProfile profile) => DropdownMenuItem<String>(
                  value: profile.id,
                  child: Text(profile.name),
                ),
              )
              .toList(),
          onChanged: (String? value) =>
              onChanged(marker.copyWith(commandId: value ?? '')),
        ),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: marker.notes,
          decoration: const InputDecoration(labelText: 'Notes'),
          onChanged: (String value) => onChanged(marker.copyWith(notes: value)),
        ),
      ],
    );
  }
}

class _EventZoneEditor extends StatelessWidget {
  const _EventZoneEditor({
    required this.zone,
    required this.commandProfiles,
    required this.onChanged,
  });

  final PlannerEventZone zone;
  final List<PlannerCommandProfile> commandProfiles;
  final ValueChanged<PlannerEventZone> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          initialValue: zone.name,
          decoration: const InputDecoration(labelText: 'Zone Name'),
          onChanged: (String value) =>
              onChanged(zone.copyWith(name: value.isEmpty ? zone.name : value)),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextFormField(
                initialValue: zone.xMinMeters.toStringAsFixed(2),
                decoration: const InputDecoration(labelText: 'Min X'),
                onChanged: (String value) => onChanged(
                  zone.copyWith(
                    xMinMeters: double.tryParse(value) ?? zone.xMinMeters,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: zone.xMaxMeters.toStringAsFixed(2),
                decoration: const InputDecoration(labelText: 'Max X'),
                onChanged: (String value) => onChanged(
                  zone.copyWith(
                    xMaxMeters: double.tryParse(value) ?? zone.xMaxMeters,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextFormField(
                initialValue: zone.yMinMeters.toStringAsFixed(2),
                decoration: const InputDecoration(labelText: 'Min Y'),
                onChanged: (String value) => onChanged(
                  zone.copyWith(
                    yMinMeters: double.tryParse(value) ?? zone.yMinMeters,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: zone.yMaxMeters.toStringAsFixed(2),
                decoration: const InputDecoration(labelText: 'Max Y'),
                onChanged: (String value) => onChanged(
                  zone.copyWith(
                    yMaxMeters: double.tryParse(value) ?? zone.yMaxMeters,
                  ),
                ),
              ),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          initialValue: zone.enterCommandId.isNotEmpty
              ? zone.enterCommandId
              : null,
          decoration: const InputDecoration(labelText: 'Enter Command'),
          items: commandProfiles
              .map(
                (PlannerCommandProfile profile) => DropdownMenuItem<String>(
                  value: profile.id,
                  child: Text(profile.name),
                ),
              )
              .toList(),
          onChanged: (String? value) =>
              onChanged(zone.copyWith(enterCommandId: value ?? '')),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: zone.activeCommandId.isNotEmpty
              ? zone.activeCommandId
              : null,
          decoration: const InputDecoration(labelText: 'While Active Command'),
          items: commandProfiles
              .map(
                (PlannerCommandProfile profile) => DropdownMenuItem<String>(
                  value: profile.id,
                  child: Text(profile.name),
                ),
              )
              .toList(),
          onChanged: (String? value) =>
              onChanged(zone.copyWith(activeCommandId: value ?? '')),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: zone.exitCommandId.isNotEmpty
              ? zone.exitCommandId
              : null,
          decoration: const InputDecoration(labelText: 'Exit Command'),
          items: commandProfiles
              .map(
                (PlannerCommandProfile profile) => DropdownMenuItem<String>(
                  value: profile.id,
                  child: Text(profile.name),
                ),
              )
              .toList(),
          onChanged: (String? value) =>
              onChanged(zone.copyWith(exitCommandId: value ?? '')),
        ),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: zone.colorHex,
          decoration: const InputDecoration(labelText: 'Zone Color Hex'),
          onChanged: (String value) => onChanged(
            zone.copyWith(colorHex: value.isEmpty ? zone.colorHex : value),
          ),
        ),
      ],
    );
  }
}

class _ConstraintZoneEditor extends StatelessWidget {
  const _ConstraintZoneEditor({required this.zone, required this.onChanged});

  final PlannerConstraintZone zone;
  final ValueChanged<PlannerConstraintZone> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          initialValue: zone.name,
          decoration: const InputDecoration(labelText: 'Zone Name'),
          onChanged: (String value) =>
              onChanged(zone.copyWith(name: value.isEmpty ? zone.name : value)),
        ),
        const SizedBox(height: 10),
        Text(
          'Start • ${(zone.startProgress * 100).round()}%',
          style: const TextStyle(color: Color(0xFF94A0B8)),
        ),
        Slider(
          value: zone.startProgress.clamp(0.0, 1.0),
          onChanged: (double value) =>
              onChanged(zone.copyWith(startProgress: value)),
        ),
        Text(
          'End • ${(zone.endProgress * 100).round()}%',
          style: const TextStyle(color: Color(0xFF94A0B8)),
        ),
        Slider(
          value: zone.endProgress.clamp(0.0, 1.0),
          onChanged: (double value) =>
              onChanged(zone.copyWith(endProgress: value)),
        ),
        _LabeledSlider(
          label: 'Max Velocity MPS',
          value: zone.maxVelocityMps,
          min: 0.5,
          max: 5.5,
          onChanged: (double value) =>
              onChanged(zone.copyWith(maxVelocityMps: value)),
        ),
        _LabeledSlider(
          label: 'Max Accel MPS²',
          value: zone.maxAccelerationMpsSq,
          min: 0.5,
          max: 5.0,
          onChanged: (double value) =>
              onChanged(zone.copyWith(maxAccelerationMpsSq: value)),
        ),
        _LabeledSlider(
          label: 'Constraint Factor',
          value: zone.constraintFactor,
          min: 0.2,
          max: 1.0,
          onChanged: (double value) =>
              onChanged(zone.copyWith(constraintFactor: value)),
        ),
        _LabeledSlider(
          label: 'Max Angular Vel Deg/S',
          value: zone.maxAngularVelocityDegPerSec,
          min: 30,
          max: 540,
          onChanged: (double value) =>
              onChanged(zone.copyWith(maxAngularVelocityDegPerSec: value)),
        ),
        _LabeledSlider(
          label: 'Max Angular Accel Deg/S²',
          value: zone.maxAngularAccelerationDegPerSecSq,
          min: 30,
          max: 720,
          onChanged: (double value) => onChanged(
            zone.copyWith(maxAngularAccelerationDegPerSecSq: value),
          ),
        ),
        _LabeledSlider(
          label: 'Tolerance Override',
          value: zone.toleranceMetersOverride,
          min: 0.01,
          max: 0.25,
          onChanged: (double value) =>
              onChanged(zone.copyWith(toleranceMetersOverride: value)),
        ),
        _LabeledSlider(
          label: 'Pose Blend Override',
          value: zone.poseBlendWeightOverride,
          min: 0,
          max: 1,
          onChanged: (double value) =>
              onChanged(zone.copyWith(poseBlendWeightOverride: value)),
        ),
      ],
    );
  }
}

class _CommandProfileCard extends StatelessWidget {
  const _CommandProfileCard({
    required this.profile,
    required this.onChanged,
    required this.onDelete,
  });

  final PlannerCommandProfile profile;
  final ValueChanged<PlannerCommandProfile> onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF151C28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF273246)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: profile.color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: profile.name,
                    decoration: const InputDecoration(
                      labelText: 'Command Name',
                    ),
                    onChanged: (String value) => onChanged(
                      profile.copyWith(
                        name: value.isEmpty ? profile.name : value,
                      ),
                    ),
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<RequestedState>(
                    initialValue: RequestedState.fromToken(
                      profile.requestedState,
                    ),
                    decoration: const InputDecoration(labelText: 'Robot State'),
                    items: RequestedState.values
                        .map(
                          (RequestedState state) =>
                              DropdownMenuItem<RequestedState>(
                                value: state,
                                child: Text(state.token),
                              ),
                        )
                        .toList(),
                    onChanged: (RequestedState? state) {
                      if (state == null) {
                        return;
                      }
                      onChanged(
                        profile.copyWith(
                          requestedState: state.token,
                          colorHex: colorToHex(state.color),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    initialValue: profile.colorHex,
                    decoration: const InputDecoration(labelText: 'Color Hex'),
                    onChanged: (String value) => onChanged(
                      profile.copyWith(
                        colorHex: value.isEmpty ? profile.colorHex : value,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: profile.description,
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (String value) =>
                  onChanged(profile.copyWith(description: value)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF273246)),
        color: const Color(0xFF151C28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label • ${value.toStringAsFixed(2)}'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
