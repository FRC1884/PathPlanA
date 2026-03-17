class DeployExportResult {
  const DeployExportResult({
    required this.supported,
    required this.writtenFiles,
    required this.message,
  });

  final bool supported;
  final int writtenFiles;
  final String message;
}

class DeployWorkspaceReadResult {
  const DeployWorkspaceReadResult({
    required this.supported,
    required this.workspaceJson,
  });

  final bool supported;
  final String? workspaceJson;
}
