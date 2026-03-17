import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double fieldLengthMeters = 17.548;
const double fieldWidthMeters = 8.052;

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
    this.routeWaypoints = const <PlannerPose>[],
  });

  final String id;
  final String label;
  final RequestedState requestedState;
  final PlannerPose pose;
  final String group;
  final String spotId;
  final List<PlannerPose> routeWaypoints;

  PlannerStep copyWith({
    String? id,
    String? label,
    RequestedState? requestedState,
    PlannerPose? pose,
    String? group,
    String? spotId,
    List<PlannerPose>? routeWaypoints,
  }) {
    return PlannerStep(
      id: id ?? this.id,
      label: label ?? this.label,
      requestedState: requestedState ?? this.requestedState,
      pose: pose ?? this.pose,
      group: group ?? this.group,
      spotId: spotId ?? this.spotId,
      routeWaypoints: routeWaypoints ?? this.routeWaypoints,
    );
  }

  Map<String, dynamic> toJson(PlannerSettings settings) => <String, dynamic>{
    'spotId': spotId,
    'label': label,
    'group': group,
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
  });

  final String version;
  final String generator;
  final List<PlannerAuto> autos;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'generator': generator,
    'autos': autos.map((auto) => auto.toJson()).toList(),
  };

  String prettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  static PlannerPackage sample() {
    return PlannerPackage(
      version: '2026.1',
      generator: 'PathPlanA',
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
    return PlannerPackage(
      version: parsed['version'] as String? ?? '2026.1',
      generator: parsed['generator'] as String? ?? 'Imported',
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
  PlannerTool _tool = PlannerTool.select;
  RequestedState _draftState = RequestedState.intaking;
  double _draftHeadingDeg = 180;
  String _statusMessage = 'Ready to author autos locally.';
  String _schemaSummary = 'Loading schema...';

  PlannerAuto get _selectedAuto => _package.autos[_selectedAutoIndex];

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
      );
      _selectedAutoIndex = _package.autos.length - 1;
      _selectedStepIndex = null;
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
      );
      _selectedAutoIndex = math.min(_selectedAutoIndex, autos.length - 1);
      _selectedStepIndex = autos[_selectedAutoIndex].steps.isEmpty ? null : 0;
      _statusMessage = 'Deleted selected auto.';
    });
  }

  void _selectAuto(int index) {
    setState(() {
      _selectedAutoIndex = index;
      _selectedStepIndex = _selectedAuto.steps.isEmpty ? null : 0;
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
            requestedState: _draftState,
            pose: pose,
            group: 'LANE',
          ),
        ];
        _updateSelectedAuto(_selectedAuto.copyWith(steps: steps));
        setState(() {
          _selectedStepIndex = steps.length - 1;
          _statusMessage = 'Added ${_draftState.token} step.';
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

  @override
  Widget build(BuildContext context) {
    final Color textMuted = const Color(0xFF94A0B8);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('PathPlanA'),
            Text(
              'Local REBUILT auto authoring',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A0B8)),
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
          SizedBox(
            width: 320,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
              child: Column(
                children: <Widget>[
                  _StatusBanner(
                    message: _statusMessage,
                    schemaSummary: _schemaSummary,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                const Text(
                                  'Autos',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                IconButton(
                                  onPressed: _deleteSelectedAuto,
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Delete selected auto',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: ListView.separated(
                                itemBuilder: (BuildContext context, int index) {
                                  final PlannerAuto auto =
                                      _package.autos[index];
                                  return _AutoGalleryCard(
                                    auto: auto,
                                    selected: index == _selectedAutoIndex,
                                    onTap: () => _selectAuto(index),
                                  );
                                },
                                separatorBuilder:
                                    (BuildContext context, int index) =>
                                        const SizedBox(height: 10),
                                itemCount: _package.autos.length,
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
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
              child: Column(
                children: <Widget>[
                  _ToolStrip(
                    tool: _tool,
                    draftState: _draftState,
                    draftHeadingDeg: _draftHeadingDeg,
                    onToolChanged: (PlannerTool tool) =>
                        setState(() => _tool = tool),
                    onStateChanged: (RequestedState state) =>
                        setState(() => _draftState = state),
                    onHeadingChanged: (double value) =>
                        setState(() => _draftHeadingDeg = value),
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
                                    _selectedAuto.name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${_selectedAuto.steps.length} steps',
                                  style: TextStyle(color: textMuted),
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
                                      auto: _selectedAuto,
                                      selectedStepIndex: _selectedStepIndex,
                                      onTap: _handleCanvasTap,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 3,
                                    child: _StepListPanel(
                                      auto: _selectedAuto,
                                      selectedStepIndex: _selectedStepIndex,
                                      onSelectStep: (int index) => setState(
                                        () => _selectedStepIndex = index,
                                      ),
                                      onDeleteStep: (int index) {
                                        final List<PlannerStep> steps =
                                            <PlannerStep>[
                                              ..._selectedAuto.steps,
                                            ]..removeAt(index);
                                        _updateSelectedAuto(
                                          _selectedAuto.copyWith(steps: steps),
                                        );
                                        setState(() {
                                          _selectedStepIndex = steps.isEmpty
                                              ? null
                                              : math.min(
                                                  index,
                                                  steps.length - 1,
                                                );
                                        });
                                      },
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
          ),
          SizedBox(
            width: 360,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
              child: _SettingsPanel(
                auto: _selectedAuto,
                selectedStepIndex: _selectedStepIndex,
                onRenameAuto: (String value) =>
                    _updateSelectedAuto(_selectedAuto.copyWith(name: value)),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.schemaSummary});

  final String message;
  final String schemaSummary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Planner Status',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),
            Text(message),
            const SizedBox(height: 6),
            Text(
              schemaSummary,
              style: const TextStyle(color: Color(0xFF94A0B8), fontSize: 12),
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
    required this.draftState,
    required this.draftHeadingDeg,
    required this.onToolChanged,
    required this.onStateChanged,
    required this.onHeadingChanged,
  });

  final PlannerTool tool;
  final RequestedState draftState;
  final double draftHeadingDeg;
  final ValueChanged<PlannerTool> onToolChanged;
  final ValueChanged<RequestedState> onStateChanged;
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
            DropdownButton<RequestedState>(
              value: draftState,
              onChanged: (RequestedState? state) {
                if (state != null) {
                  onStateChanged(state);
                }
              },
              items: RequestedState.values
                  .map(
                    (RequestedState state) => DropdownMenuItem<RequestedState>(
                      value: state,
                      child: Text(state.token),
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
            child: CustomPaint(
              painter: _FieldPreviewPainter(
                auto: auto,
                selectedStepIndex: selectedStepIndex,
                mini: false,
              ),
              child: const SizedBox.expand(),
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
    final Paint background = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[Color(0xFF0E1420), Color(0xFF0A1018)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      background,
    );

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
    final double width = (0.6985 / fieldLengthMeters) * size.width * scale;
    final double height = (0.6985 / fieldWidthMeters) * size.height * scale;
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
    required this.selectedStepIndex,
    required this.onSelectStep,
    required this.onDeleteStep,
  });

  final PlannerAuto auto;
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
                        return Material(
                          color: index == selectedStepIndex
                              ? step.requestedState.color.withValues(
                                  alpha: 0.12,
                                )
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
                                      color: step.requestedState.color
                                          .withValues(alpha: 0.18),
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
                                          '${step.requestedState.token} • ${step.routeWaypoints.length} wp',
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
    required this.selectedStepIndex,
    required this.onRenameAuto,
    required this.onUpdateSettings,
    required this.onUpdateStep,
  });

  final PlannerAuto auto;
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
                        DropdownButtonFormField<RequestedState>(
                          initialValue: selectedStep.requestedState,
                          decoration: const InputDecoration(
                            labelText: 'Requested State',
                          ),
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
                            if (state != null) {
                              onUpdateStep(
                                selectedStep.copyWith(requestedState: state),
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
