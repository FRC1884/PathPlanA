import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

const double fieldLengthMeters = 17.548;
const double fieldWidthMeters = 8.052;
const String plannerIconAsset = 'assets/branding/pathplana_icon.svg';
const String fieldBackgroundAsset = 'assets/field/rebuilt_field.svg';

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

enum PlannerSection { library, editor, obstacles, commands, settings }

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

class PlannerSettings {
  const PlannerSettings({
    this.visionCorrectionEnabled = true,
    this.poseBlendWeight = 0.35,
    this.constraintFactor = 0.8,
    this.toleranceMeters = 0.06,
    this.timeoutSeconds = 1.6,
    this.endVelocityMps = 1.2,
    this.controlRateHz = 50,
    this.robotWidthMeters = 0.6985,
    this.robotLengthMeters = 0.6985,
    this.allowReverse = false,
    this.holdHeading = true,
    this.previewSmoothing = 0.72,
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
          (planner['robotWidthMeters'] as num?)?.toDouble() ?? 0.6985,
      robotLengthMeters:
          (planner['robotLengthMeters'] as num?)?.toDouble() ?? 0.6985,
      allowReverse: planner['allowReverse'] as bool? ?? false,
      holdHeading: planner['holdHeading'] as bool? ?? true,
      previewSmoothing:
          (planner['previewSmoothing'] as num?)?.toDouble() ?? 0.72,
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
    required this.updatedAt,
    required this.startPose,
    required this.steps,
    required this.settings,
    this.customZones = const <PlannerZone>[],
  });

  final String id;
  final String name;
  final DateTime updatedAt;
  final PlannerPose startPose;
  final List<PlannerStep> steps;
  final PlannerSettings settings;
  final List<PlannerZone> customZones;

  PlannerAuto copyWith({
    String? id,
    String? name,
    DateTime? updatedAt,
    PlannerPose? startPose,
    List<PlannerStep>? steps,
    PlannerSettings? settings,
    List<PlannerZone>? customZones,
  }) {
    return PlannerAuto(
      id: id ?? this.id,
      name: name ?? this.name,
      updatedAt: updatedAt ?? this.updatedAt,
      startPose: startPose ?? this.startPose,
      steps: steps ?? this.steps,
      settings: settings ?? this.settings,
      customZones: customZones ?? this.customZones,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'startPose': startPose.toJson(),
    'customZones': customZones.map((zone) => zone.toJson()).toList(),
    'plannerSettings': settings.toJson(),
    'steps': steps.map((step) => step.toJson(settings)).toList(),
  };

  static PlannerAuto fromJson(Map<String, dynamic> json) {
    return PlannerAuto(
      id: json['id'] as String? ?? UniqueKey().toString(),
      name: json['name'] as String? ?? 'Imported Auto',
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

class PlannerHomePage extends StatefulWidget {
  const PlannerHomePage({super.key});

  @override
  State<PlannerHomePage> createState() => _PlannerHomePageState();
}

class _PlannerHomePageState extends State<PlannerHomePage> {
  PlannerPackage _package = PlannerPackage.sample();
  int _selectedAutoIndex = 0;
  int? _selectedStepIndex;
  int? _selectedZoneIndex;
  PlannerTool _tool = PlannerTool.select;
  PlannerSection _selectedSection = PlannerSection.library;
  String _draftCommandId = 'cmd-intake';
  double _draftHeadingDeg = 180;
  String _statusMessage = 'Ready to author autos locally.';
  String _schemaSummary = 'Loading schema...';

  PlannerAuto get _selectedAuto => _package.autos[_selectedAutoIndex];
  List<PlannerCommandProfile> get _commandProfiles => _package.commandProfiles;
  PlannerCommandProfile get _draftCommand =>
      _resolveCommandProfileById(_draftCommandId) ?? _commandProfiles.first;

  @override
  void initState() {
    super.initState();
    _loadSchemaSummary();
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
    setState(() {
      _package = imported;
      _selectedAutoIndex = 0;
      _selectedStepIndex = imported.autos.first.steps.isNotEmpty ? 0 : null;
      _selectedZoneIndex = imported.autos.first.customZones.isNotEmpty
          ? 0
          : null;
      _draftCommandId = imported.commandProfiles.first.id;
      _statusMessage =
          'Imported ${imported.autos.length} auto${imported.autos.length == 1 ? '' : 's'} from ${file.name}.';
    });
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
    final DateTime now = DateTime.now();
    final PlannerAuto auto = PlannerAuto.sample().copyWith(
      id: 'auto-${now.millisecondsSinceEpoch}',
      name: 'New Auto ${_package.autos.length + 1}',
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
      _selectedSection = PlannerSection.editor;
      _statusMessage = 'Created ${auto.name}.';
    });
  }

  void _deleteSelectedAuto() {
    if (_package.autos.length == 1) {
      return;
    }
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
      _statusMessage = 'Deleted selected auto.';
    });
  }

  void _selectAuto(int index) {
    setState(() {
      _selectedAutoIndex = index;
      _selectedStepIndex = _selectedAuto.steps.isEmpty ? null : 0;
      _selectedZoneIndex = _selectedAuto.customZones.isEmpty ? null : 0;
      _selectedSection = PlannerSection.editor;
      _statusMessage = 'Previewing ${_selectedAuto.name}.';
    });
  }

  void _updateSelectedAuto(PlannerAuto nextAuto) {
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
    _updateSelectedAuto(_selectedAuto.copyWith(customZones: zones));
    setState(() {
      _selectedZoneIndex = zones.length - 1;
      _selectedSection = PlannerSection.obstacles;
      _statusMessage = 'Added a new keep-out box.';
    });
  }

  void _updateZone(int index, PlannerZone zone) {
    final List<PlannerZone> zones = <PlannerZone>[..._selectedAuto.customZones];
    zones[index] = zone;
    _updateSelectedAuto(_selectedAuto.copyWith(customZones: zones));
  }

  void _deleteZone(int index) {
    final List<PlannerZone> zones = <PlannerZone>[..._selectedAuto.customZones]
      ..removeAt(index);
    _updateSelectedAuto(_selectedAuto.copyWith(customZones: zones));
    setState(() {
      _selectedZoneIndex = zones.isEmpty
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
                    auto: _selectedAuto,
                    commandProfiles: _commandProfiles,
                    selectedStepIndex: _selectedStepIndex,
                    tool: _tool,
                    draftCommandId: _draftCommandId,
                    draftHeadingDeg: _draftHeadingDeg,
                    onToolChanged: (PlannerTool tool) =>
                        setState(() => _tool = tool),
                    onDraftCommandChanged: (String value) =>
                        setState(() => _draftCommandId = value),
                    onHeadingChanged: (double value) =>
                        setState(() => _draftHeadingDeg = value),
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
    required this.auto,
    required this.commandProfiles,
    required this.selectedStepIndex,
    required this.tool,
    required this.draftCommandId,
    required this.draftHeadingDeg,
    required this.onToolChanged,
    required this.onDraftCommandChanged,
    required this.onHeadingChanged,
    required this.onTap,
    required this.onSelectStep,
    required this.onDeleteStep,
  });

  final PlannerAuto auto;
  final List<PlannerCommandProfile> commandProfiles;
  final int? selectedStepIndex;
  final PlannerTool tool;
  final String draftCommandId;
  final double draftHeadingDeg;
  final ValueChanged<PlannerTool> onToolChanged;
  final ValueChanged<String> onDraftCommandChanged;
  final ValueChanged<double> onHeadingChanged;
  final ValueChanged<Offset> onTap;
  final ValueChanged<int> onSelectStep;
  final ValueChanged<int> onDeleteStep;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _ToolStrip(
          tool: tool,
          commandProfiles: commandProfiles,
          draftCommandId: draftCommandId,
          draftHeadingDeg: draftHeadingDeg,
          onToolChanged: onToolChanged,
          onDraftCommandChanged: onDraftCommandChanged,
          onHeadingChanged: onHeadingChanged,
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
                          flex: 5,
                          child: _FieldEditor(
                            auto: auto,
                            selectedStepIndex: selectedStepIndex,
                            onTap: onTap,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
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
                '${auto.steps.length} steps • ${auto.updatedAt.hour.toString().padLeft(2, '0')}:${auto.updatedAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Color(0xFF94A0B8), fontSize: 12),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 90,
                child: CustomPaint(
                  painter: _FieldPreviewPainter(
                    auto: auto,
                    selectedStepIndex: null,
                    mini: true,
                  ),
                  child: const SizedBox.expand(),
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
  });

  final PlannerTool tool;
  final List<PlannerCommandProfile> commandProfiles;
  final String draftCommandId;
  final double draftHeadingDeg;
  final ValueChanged<PlannerTool> onToolChanged;
  final ValueChanged<String> onDraftCommandChanged;
  final ValueChanged<double> onHeadingChanged;

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
    required this.onTap,
  });

  final PlannerAuto auto;
  final int? selectedStepIndex;
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
                  padding: const EdgeInsets.all(8),
                  child: SvgPicture.asset(
                    fieldBackgroundAsset,
                    fit: BoxFit.contain,
                  ),
                ),
                CustomPaint(
                  painter: _FieldPreviewPainter(
                    auto: auto,
                    selectedStepIndex: selectedStepIndex,
                    mini: false,
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
  });

  final PlannerAuto auto;
  final int? selectedStepIndex;
  final bool mini;

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

  @override
  bool shouldRepaint(covariant _FieldPreviewPainter oldDelegate) {
    return oldDelegate.auto != auto ||
        oldDelegate.selectedStepIndex != selectedStepIndex ||
        oldDelegate.mini != mini;
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
