import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

const double fieldLengthMeters = 17.548;
const double fieldWidthMeters = 8.052;
const double robotSideInches = 27.5;
const double defaultRobotSizeMeters = robotSideInches * 0.0254;
const String plannerIconAsset = 'assets/branding/pathplana_icon.svg';
const String fieldBackgroundAsset = 'assets/field/rebuilt_topdown.png';

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
  constraints,
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

List<PlannerPose> buildAutoRoutePoints(PlannerAuto auto) {
  final List<PlannerPose> points = <PlannerPose>[auto.startPose];
  for (final PlannerStep step in auto.steps) {
    points.addAll(step.routeWaypoints);
    points.add(step.pose);
  }
  return points;
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
    final double factor = _constraintFactorAtProgress(auto, midpointProgress);
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
    required this.progress,
    this.commandId = '',
    this.notes = '',
  });

  final String id;
  final String name;
  final double progress;
  final String commandId;
  final String notes;

  PlannerEventMarker copyWith({
    String? id,
    String? name,
    double? progress,
    String? commandId,
    String? notes,
  }) {
    return PlannerEventMarker(
      id: id ?? this.id,
      name: name ?? this.name,
      progress: progress ?? this.progress,
      commandId: commandId ?? this.commandId,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'progress': progress,
    'commandId': commandId,
    'notes': notes,
  };

  static PlannerEventMarker fromJson(Map<String, dynamic> json) {
    return PlannerEventMarker(
      id: json['id'] as String? ?? 'marker',
      name: json['name'] as String? ?? 'Marker',
      progress: ((json['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      commandId: json['commandId'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }
}

class PlannerEventZone {
  const PlannerEventZone({
    required this.id,
    required this.name,
    required this.startProgress,
    required this.endProgress,
    this.enterCommandId = '',
    this.exitCommandId = '',
    this.activeCommandId = '',
    this.colorHex = '#FF8C69',
  });

  final String id;
  final String name;
  final double startProgress;
  final double endProgress;
  final String enterCommandId;
  final String exitCommandId;
  final String activeCommandId;
  final String colorHex;

  Color get color => parseHexColor(colorHex) ?? const Color(0xFFFF8C69);

  PlannerEventZone copyWith({
    String? id,
    String? name,
    double? startProgress,
    double? endProgress,
    String? enterCommandId,
    String? exitCommandId,
    String? activeCommandId,
    String? colorHex,
  }) {
    return PlannerEventZone(
      id: id ?? this.id,
      name: name ?? this.name,
      startProgress: startProgress ?? this.startProgress,
      endProgress: endProgress ?? this.endProgress,
      enterCommandId: enterCommandId ?? this.enterCommandId,
      exitCommandId: exitCommandId ?? this.exitCommandId,
      activeCommandId: activeCommandId ?? this.activeCommandId,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'startProgress': startProgress,
    'endProgress': endProgress,
    'enterCommandId': enterCommandId,
    'exitCommandId': exitCommandId,
    'activeCommandId': activeCommandId,
    'colorHex': colorHex,
  };

  static PlannerEventZone fromJson(Map<String, dynamic> json) {
    return PlannerEventZone(
      id: json['id'] as String? ?? 'event-zone',
      name: json['name'] as String? ?? 'Zone',
      startProgress: ((json['startProgress'] as num?)?.toDouble() ?? 0).clamp(
        0.0,
        1.0,
      ),
      endProgress: ((json['endProgress'] as num?)?.toDouble() ?? 1).clamp(
        0.0,
        1.0,
      ),
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
  });

  final String id;
  final String name;
  final double startProgress;
  final double endProgress;
  final double maxVelocityMps;
  final double maxAccelerationMpsSq;
  final double constraintFactor;

  PlannerConstraintZone copyWith({
    String? id,
    String? name,
    double? startProgress,
    double? endProgress,
    double? maxVelocityMps,
    double? maxAccelerationMpsSq,
    double? constraintFactor,
  }) {
    return PlannerConstraintZone(
      id: id ?? this.id,
      name: name ?? this.name,
      startProgress: startProgress ?? this.startProgress,
      endProgress: endProgress ?? this.endProgress,
      maxVelocityMps: maxVelocityMps ?? this.maxVelocityMps,
      maxAccelerationMpsSq: maxAccelerationMpsSq ?? this.maxAccelerationMpsSq,
      constraintFactor: constraintFactor ?? this.constraintFactor,
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
    this.routeWaypoints = const <PlannerPose>[],
    this.waitSeconds = 0,
  });

  final String id;
  final String label;
  final RequestedState requestedState;
  final PlannerPose pose;
  final String group;
  final String spotId;
  final String commandId;
  final String commandName;
  final List<PlannerPose> routeWaypoints;
  final double waitSeconds;

  PlannerStep copyWith({
    String? id,
    String? label,
    RequestedState? requestedState,
    PlannerPose? pose,
    String? group,
    String? spotId,
    String? commandId,
    String? commandName,
    List<PlannerPose>? routeWaypoints,
    double? waitSeconds,
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
    'routeWaypoints': routeWaypoints.map((pose) => pose.toJson()).toList(),
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
      routeWaypoints: (json['routeWaypoints'] as List<dynamic>? ?? const [])
          .map(
            (dynamic pose) =>
                PlannerPose.fromJson(pose as Map<String, dynamic>),
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
          progress: 0.18,
          commandId: 'cmd-intake',
        ),
        PlannerEventMarker(
          id: 'marker-2',
          name: 'Prep Shot',
          progress: 0.78,
          commandId: 'cmd-score',
        ),
      ],
      eventZones: const <PlannerEventZone>[
        PlannerEventZone(
          id: 'zone-1',
          name: 'Collect Window',
          startProgress: 0.08,
          endProgress: 0.34,
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
          routeWaypoints: <PlannerPose>[
            PlannerPose(xMeters: 1.44, yMeters: 5.38, headingDeg: 180),
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
          routeWaypoints: <PlannerPose>[
            PlannerPose(xMeters: 2.7, yMeters: 5.66, headingDeg: 0),
            PlannerPose(xMeters: 3.88, yMeters: 5.66, headingDeg: -60),
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
  });

  final String version;
  final String generator;
  final List<PlannerAuto> autos;
  final List<PlannerCommandProfile> commandProfiles;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'generator': generator,
    'commandProfiles': commandProfiles
        .map((PlannerCommandProfile command) => command.toJson())
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
              routeWaypoints: <PlannerPose>[
                PlannerPose(xMeters: 1.68, yMeters: 1.18, headingDeg: 180),
              ],
            ),
            PlannerStep(
              id: 'step-2b',
              label: 'Hub Right',
              group: 'HUB',
              requestedState: RequestedState.shooting,
              pose: PlannerPose(xMeters: 4.61, yMeters: 2.58, headingDeg: 90),
              routeWaypoints: <PlannerPose>[
                PlannerPose(xMeters: 2.46, yMeters: 2.1, headingDeg: 0),
                PlannerPose(xMeters: 3.92, yMeters: 2.26, headingDeg: 50),
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
      autos: (parsed['autos'] as List<dynamic>? ?? const [])
          .map(
            (dynamic auto) =>
                PlannerAuto.fromJson(auto as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class _PlannerWorkspaceSnapshot {
  const _PlannerWorkspaceSnapshot({
    required this.package,
    required this.selectedAutoIndex,
    required this.selectedStepIndex,
    required this.selectedSection,
  });

  final PlannerPackage package;
  final int selectedAutoIndex;
  final int? selectedStepIndex;
  final PlannerSection selectedSection;
}

class PlannerHomePage extends StatefulWidget {
  const PlannerHomePage({super.key});

  @override
  State<PlannerHomePage> createState() => _PlannerHomePageState();
}

class _PlannerHomePageState extends State<PlannerHomePage>
    with SingleTickerProviderStateMixin {
  PlannerPackage _package = PlannerPackage.sample();
  int _selectedAutoIndex = 0;
  int? _selectedStepIndex;
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

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
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
      return;
    }
    final String contents = await file.readAsString();
    final PlannerPackage imported = PlannerPackage.fromJsonString(contents);
    if (imported.autos.isEmpty) {
      setState(() {
        _statusMessage = 'Import skipped. No autos found.';
      });
      return;
    }
    _pushUndoSnapshot();
    setState(() {
      _package = imported;
      _selectedAutoIndex = 0;
      _selectedStepIndex = imported.autos.first.steps.isNotEmpty ? 0 : null;
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
  }

  Future<void> _exportPackage() async {
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: 'pathplana_autos.json',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'JSON', extensions: <String>['json']),
      ],
    );
    final String json = _package.prettyJson();
    if (location == null) {
      await Clipboard.setData(ClipboardData(text: json));
      setState(() {
        _statusMessage = 'Export canceled. JSON copied to clipboard instead.';
      });
      return;
    }
    final Uint8List fileData = Uint8List.fromList(utf8.encode(json));
    final XFile file = XFile.fromData(
      fileData,
      name: 'pathplana_autos.json',
      mimeType: 'application/json',
    );
    await file.saveTo(location.path);
    setState(() {
      _statusMessage = 'Exported planner package.';
    });
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
      );
      _selectedAutoIndex = _package.autos.length - 1;
      _selectedStepIndex = null;
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
      );
      _selectedAutoIndex = math.min(_selectedAutoIndex, autos.length - 1);
      _selectedStepIndex = autos[_selectedAutoIndex].steps.isEmpty ? null : 0;
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
  }

  void _selectAuto(int index) {
    setState(() {
      _selectedAutoIndex = index;
      _selectedStepIndex = _selectedAuto.steps.isEmpty ? null : 0;
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
      );
    });
    _configurePreviewAnimation();
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
          routeWaypoints: <PlannerPose>[...step.routeWaypoints, pose],
        );
        _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
        setState(() {
          _statusMessage = 'Added waypoint to ${step.label}.';
        });
    }
  }

  void _pickNearestStep(PlannerPose pose) {
    if (_selectedAuto.steps.isEmpty) {
      return;
    }
    int nearestIndex = 0;
    double nearestDistance = double.infinity;
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
      _selectedStepIndex = nearestIndex;
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
      );
      if (!profiles.any(
        (PlannerCommandProfile profile) => profile.id == _draftCommandId,
      )) {
        _draftCommandId = profiles.first.id;
      }
    });
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
    zones[index] = zone;
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
    final List<PlannerEventMarker> markers = <PlannerEventMarker>[
      ..._selectedAuto.eventMarkers,
      PlannerEventMarker(
        id: 'marker-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Marker ${_selectedAuto.eventMarkers.length + 1}',
        progress: 0.5,
        commandId: _draftCommand.id,
      ),
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
        startProgress: 0.2,
        endProgress: 0.45,
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
    zones[index] = zone;
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
      _selectedSection = PlannerSection.constraints;
    });
  }

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
            label: const Text('Export'),
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
                  icon: Icon(Icons.speed_outlined),
                  selectedIcon: Icon(Icons.speed),
                  label: Text('Constraints'),
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
                    onSelectAutoFromBrowser: _selectAuto,
                    onOpenEvents: () => setState(
                      () => _selectedSection = PlannerSection.events,
                    ),
                    onOpenConstraints: () => setState(
                      () => _selectedSection = PlannerSection.constraints,
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
                    onSelectStep: (int index) =>
                        setState(() => _selectedStepIndex = index),
                    onDeleteStep: (int index) {
                      final List<PlannerStep> steps = <PlannerStep>[
                        ..._selectedAuto.steps,
                      ]..removeAt(index);
                      _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
                      setState(() {
                        _selectedStepIndex = steps.isEmpty
                            ? null
                            : math.min(index, steps.length - 1);
                      });
                    },
                    onRenameAuto: (String value) => _updateSelectedAuto(
                      _selectedAuto.copyWith(name: value),
                    ),
                    onFolderChanged: (String value) => _updateSelectedAuto(
                      _selectedAuto.copyWith(folder: value),
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
                  _EventsSection(
                    auto: _selectedAuto,
                    commandProfiles: _commandProfiles,
                    selectedMarkerIndex: _selectedMarkerIndex,
                    selectedEventZoneIndex: _selectedEventZoneIndex,
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
                  _ConstraintSection(
                    auto: _selectedAuto,
                    selectedConstraintZoneIndex: _selectedConstraintZoneIndex,
                    onSelectConstraintZone: (int index) =>
                        setState(() => _selectedConstraintZoneIndex = index),
                    onAddConstraintZone: _addConstraintZone,
                    onUpdateConstraintZone: _updateConstraintZone,
                    onDeleteConstraintZone: _deleteConstraintZone,
                  ),
                  _ObstacleSection(
                    auto: _selectedAuto,
                    selectedZoneIndex: _selectedZoneIndex,
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
    required this.onSelectAutoFromBrowser,
    required this.onOpenEvents,
    required this.onOpenConstraints,
    required this.onOpenObstacles,
    required this.onOpenCommands,
    required this.onOpenSettings,
    required this.onTap,
    required this.onSelectStep,
    required this.onDeleteStep,
    required this.onRenameAuto,
    required this.onFolderChanged,
    required this.onUpdateSettings,
    required this.onUpdateStep,
  });

  final List<PlannerAuto> autos;
  final int selectedAutoIndex;
  final PlannerAuto auto;
  final List<PlannerCommandProfile> commandProfiles;
  final int? selectedStepIndex;
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
  final ValueChanged<int> onSelectAutoFromBrowser;
  final VoidCallback onOpenEvents;
  final VoidCallback onOpenConstraints;
  final VoidCallback onOpenObstacles;
  final VoidCallback onOpenCommands;
  final VoidCallback onOpenSettings;
  final ValueChanged<Offset> onTap;
  final ValueChanged<int> onSelectStep;
  final ValueChanged<int> onDeleteStep;
  final ValueChanged<String> onRenameAuto;
  final ValueChanged<String> onFolderChanged;
  final ValueChanged<PlannerSettings> onUpdateSettings;
  final ValueChanged<PlannerStep> onUpdateStep;

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
            onSelectAuto: onSelectAutoFromBrowser,
            onOpenEvents: onOpenEvents,
            onOpenConstraints: onOpenConstraints,
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
                                  selectedStepIndex: selectedStepIndex,
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
            estimatedTimeSeconds: estimatedTimeSeconds,
            onRenameAuto: onRenameAuto,
            onFolderChanged: onFolderChanged,
            onUpdateSettings: onUpdateSettings,
            onUpdateStep: onUpdateStep,
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
    required this.onSelectAuto,
    required this.onOpenEvents,
    required this.onOpenConstraints,
    required this.onOpenObstacles,
    required this.onOpenCommands,
  });

  final List<PlannerAuto> autos;
  final int selectedAutoIndex;
  final PlannerAuto auto;
  final List<PlannerCommandProfile> commandProfiles;
  final ValueChanged<int> onSelectAuto;
  final VoidCallback onOpenEvents;
  final VoidCallback onOpenConstraints;
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
              icon: Icons.speed,
              title: 'Constraint Zones',
              subtitle: '${auto.constraintZones.length} active overrides',
              onTap: onOpenConstraints,
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
    required this.estimatedTimeSeconds,
    required this.onRenameAuto,
    required this.onFolderChanged,
    required this.onUpdateSettings,
    required this.onUpdateStep,
    required this.onOpenSettings,
  });

  final PlannerAuto auto;
  final List<PlannerCommandProfile> commandProfiles;
  final int? selectedStepIndex;
  final double estimatedTimeSeconds;
  final ValueChanged<String> onRenameAuto;
  final ValueChanged<String> onFolderChanged;
  final ValueChanged<PlannerSettings> onUpdateSettings;
  final ValueChanged<PlannerStep> onUpdateStep;
  final VoidCallback onOpenSettings;

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
              'Inspector',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
            const SizedBox(height: 12),
            if (selectedStep == null) ...<Widget>[
              TextFormField(
                initialValue: auto.name,
                decoration: const InputDecoration(labelText: 'Auto Name'),
                onChanged: onRenameAuto,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: auto.folder,
                decoration: const InputDecoration(labelText: 'Folder'),
                onChanged: (String value) =>
                    onFolderChanged(value.isEmpty ? 'Autos' : value),
              ),
              const SizedBox(height: 12),
              _MetricChip(
                label: 'Estimated Runtime',
                value: formatDurationSeconds(estimatedTimeSeconds),
              ),
              const SizedBox(height: 10),
              _MetricChip(
                label: 'Path Distance',
                value:
                    '${computeAutoDistanceMeters(auto).toStringAsFixed(2)} m',
              ),
              const SizedBox(height: 10),
              _MetricChip(
                label: 'Behavior Assets',
                value:
                    '${auto.eventMarkers.length} markers / ${auto.eventZones.length} zones / ${auto.constraintZones.length} constraints',
              ),
              const SizedBox(height: 14),
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
                title: 'Start Pose',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('X ${auto.startPose.xMeters.toStringAsFixed(2)} m'),
                    Text('Y ${auto.startPose.yMeters.toStringAsFixed(2)} m'),
                    Text(
                      'Heading ${auto.startPose.headingDeg.toStringAsFixed(0)}°',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onOpenSettings,
                child: const Text('Open Full Settings'),
              ),
            ] else ...<Widget>[
              const Text(
                'Selected Step',
                style: TextStyle(color: Color(0xFF94A0B8), fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: selectedStep.label,
                decoration: const InputDecoration(labelText: 'Step Label'),
                onChanged: (String value) =>
                    onUpdateStep(selectedStep.copyWith(label: value)),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedStep.commandId.isNotEmpty
                    ? selectedStep.commandId
                    : commandProfiles.first.id,
                decoration: const InputDecoration(labelText: 'Named Command'),
                items: commandProfiles
                    .map(
                      (PlannerCommandProfile profile) =>
                          DropdownMenuItem<String>(
                            value: profile.id,
                            child: Text(
                              '${profile.name} → ${profile.requestedState}',
                            ),
                          ),
                    )
                    .toList(),
                onChanged: (String? commandId) {
                  if (commandId == null) {
                    return;
                  }
                  final PlannerCommandProfile profile = commandProfiles
                      .firstWhere(
                        (PlannerCommandProfile entry) => entry.id == commandId,
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
                },
              ),
              const SizedBox(height: 10),
              _LabeledSlider(
                label: 'Wait Seconds',
                value: selectedStep.waitSeconds,
                min: 0,
                max: 3,
                onChanged: (double value) =>
                    onUpdateStep(selectedStep.copyWith(waitSeconds: value)),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      initialValue: selectedStep.pose.xMeters.toStringAsFixed(
                        2,
                      ),
                      decoration: const InputDecoration(labelText: 'X'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      onChanged: (String value) => onUpdateStep(
                        selectedStep.copyWith(
                          pose: selectedStep.pose.copyWith(
                            xMeters:
                                double.tryParse(value) ??
                                selectedStep.pose.xMeters,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      initialValue: selectedStep.pose.yMeters.toStringAsFixed(
                        2,
                      ),
                      decoration: const InputDecoration(labelText: 'Y'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      onChanged: (String value) => onUpdateStep(
                        selectedStep.copyWith(
                          pose: selectedStep.pose.copyWith(
                            yMeters:
                                double.tryParse(value) ??
                                selectedStep.pose.yMeters,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: selectedStep.pose.headingDeg.toStringAsFixed(0),
                decoration: const InputDecoration(labelText: 'Heading'),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                onChanged: (String value) => onUpdateStep(
                  selectedStep.copyWith(
                    pose: selectedStep.pose.copyWith(
                      headingDeg:
                          double.tryParse(value) ??
                          selectedStep.pose.headingDeg,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _SettingsSection(
                title: 'Pose Summary',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('X ${selectedStep.pose.xMeters.toStringAsFixed(2)} m'),
                    Text('Y ${selectedStep.pose.yMeters.toStringAsFixed(2)} m'),
                    Text(
                      'Heading ${selectedStep.pose.headingDeg.toStringAsFixed(0)}°',
                    ),
                    Text('Waypoints ${selectedStep.routeWaypoints.length}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onOpenSettings,
                child: const Text('Open Full Properties'),
              ),
            ],
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
                                          '${(marker.progress * 100).round()}% • ${profile?.name ?? "No command"}',
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
                                          '${(zone.startProgress * 100).round()}% → ${(zone.endProgress * 100).round()}%',
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
    required this.onSelectZone,
    required this.onAddZone,
    required this.onUpdateZone,
    required this.onDeleteZone,
  });

  final PlannerAuto auto;
  final int? selectedZoneIndex;
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
                selectedStepIndex: null,
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
                    Padding(
                      padding: EdgeInsets.zero,
                      child: Image.asset(
                        fieldBackgroundAsset,
                        fit: BoxFit.fill,
                      ),
                    ),
                    CustomPaint(
                      painter: _FieldPreviewPainter(
                        auto: auto,
                        selectedStepIndex: null,
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

class _FieldEditor extends StatelessWidget {
  const _FieldEditor({
    required this.auto,
    required this.selectedStepIndex,
    required this.playbackProgress,
    required this.onTap,
  });

  final PlannerAuto auto;
  final int? selectedStepIndex;
  final double playbackProgress;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF0F141D),
            border: Border.all(color: const Color(0xFF273246)),
          ),
          child: GestureDetector(
            onTapDown: (TapDownDetails details) {
              final RenderBox box = context.findRenderObject()! as RenderBox;
              final Offset local = details.localPosition;
              final Size size = box.size;
              final Offset field = Offset(
                (local.dx / size.width) * fieldLengthMeters,
                fieldWidthMeters -
                    ((local.dy / size.height) * fieldWidthMeters),
              );
              onTap(field);
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.zero,
                  child: Image.asset(fieldBackgroundAsset, fit: BoxFit.fill),
                ),
                CustomPaint(
                  painter: _FieldPreviewPainter(
                    auto: auto,
                    selectedStepIndex: selectedStepIndex,
                    mini: false,
                    playbackProgress: playbackProgress,
                  ),
                  child: const SizedBox.expand(),
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
    required this.selectedStepIndex,
    required this.mini,
    required this.playbackProgress,
  });

  final PlannerAuto auto;
  final int? selectedStepIndex;
  final bool mini;
  final double playbackProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
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
    final double safeX = (8.15 / fieldLengthMeters) * size.width;
    canvas.drawLine(Offset(safeX, 0), Offset(safeX, size.height), centerLine);

    for (final PlannerZone zone in auto.customZones) {
      final Rect zoneRect = Rect.fromLTRB(
        zone.xMinMeters / fieldLengthMeters * size.width,
        size.height - (zone.yMaxMeters / fieldWidthMeters * size.height),
        zone.xMaxMeters / fieldLengthMeters * size.width,
        size.height - (zone.yMinMeters / fieldWidthMeters * size.height),
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
      _drawProgressBand(
        canvas,
        size,
        zone.startProgress,
        zone.endProgress,
        zone.color.withValues(alpha: 0.18),
      );
    }

    final List<PlannerPose> route = <PlannerPose>[auto.startPose];
    for (final PlannerStep step in auto.steps) {
      route.addAll(step.routeWaypoints);
      route.add(step.pose);
    }

    PlannerPose previous = auto.startPose;
    for (int i = 0; i < auto.steps.length; i += 1) {
      final PlannerStep step = auto.steps[i];
      final List<PlannerPose> segment = <PlannerPose>[
        previous,
        ...step.routeWaypoints,
        step.pose,
      ];
      final Paint pathPaint = Paint()
        ..color = step.requestedState.color
        ..strokeWidth = mini ? 1.8 : 3.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final Path path = Path();
      for (int j = 0; j < segment.length; j += 1) {
        final Offset point = _toCanvas(segment[j], size);
        if (j == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, pathPaint);
      previous = step.pose;
    }

    for (final PlannerEventMarker marker in auto.eventMarkers) {
      final PlannerPose pose = sampleAutoPoseAtProgress(auto, marker.progress);
      final Offset point = _toCanvas(pose, size);
      canvas.drawCircle(
        point,
        mini ? 3.5 : 6,
        Paint()..color = const Color(0xFFFFD166),
      );
      canvas.drawCircle(
        point,
        mini ? 5.5 : 9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = mini ? 1 : 1.5
          ..color = const Color(0x88FFE8AD),
      );
    }

    _drawRobotBox(
      canvas,
      size,
      auto.startPose,
      const Color(0xFFFFE8AD),
      mini ? 0.55 : 0.85,
    );

    for (int i = 0; i < auto.steps.length; i += 1) {
      final PlannerStep step = auto.steps[i];
      for (final PlannerPose waypoint in step.routeWaypoints) {
        _drawRobotBox(
          canvas,
          size,
          waypoint,
          step.requestedState.color,
          mini ? 0.35 : 0.48,
        );
      }
      _drawRobotBox(
        canvas,
        size,
        step.pose,
        step.requestedState.color,
        i == selectedStepIndex ? (mini ? 0.6 : 0.92) : (mini ? 0.5 : 0.72),
      );
    }

    if (!mini) {
      _drawRobotBox(
        canvas,
        size,
        sampleAutoPoseAtProgress(auto, playbackProgress),
        const Color(0xFFE8EEFC),
        0.94,
      );
    }
  }

  Offset _toCanvas(PlannerPose pose, Size size) {
    return Offset(
      pose.xMeters / fieldLengthMeters * size.width,
      size.height - (pose.yMeters / fieldWidthMeters * size.height),
    );
  }

  void _drawRobotBox(
    Canvas canvas,
    Size size,
    PlannerPose pose,
    Color color,
    double scale,
  ) {
    final Offset center = _toCanvas(pose, size);
    final double width =
        (auto.settings.robotLengthMeters / fieldLengthMeters) *
        size.width *
        scale;
    final double height =
        (auto.settings.robotWidthMeters / fieldWidthMeters) *
        size.height *
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
    final Offset start = _toCanvas(startPose, size);
    final Offset end = _toCanvas(endPose, size);
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
        oldDelegate.selectedStepIndex != selectedStepIndex ||
        oldDelegate.mini != mini ||
        oldDelegate.playbackProgress != playbackProgress;
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
          'Progress • ${(marker.progress * 100).round()}%',
          style: const TextStyle(color: Color(0xFF94A0B8)),
        ),
        Slider(
          value: marker.progress.clamp(0.0, 1.0),
          onChanged: (double value) =>
              onChanged(marker.copyWith(progress: value)),
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
