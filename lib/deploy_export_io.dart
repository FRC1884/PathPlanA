import 'dart:io';

import 'deploy_export_api.dart';

Future<DeployExportResult> writeDeployLibrary({
  required String targetDirectory,
  required String indexJson,
  required Map<String, String> filesByRelativePath,
}) async {
  final Directory root = Directory(targetDirectory);
  await root.create(recursive: true);
  final File indexFile = File('${root.path}/index.json');
  await indexFile.writeAsString(indexJson);
  for (final MapEntry<String, String> entry in filesByRelativePath.entries) {
    final File file = File('${root.path}/${entry.key}');
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }
  return DeployExportResult(
    supported: true,
    writtenFiles: filesByRelativePath.length + 1,
    message:
        'Exported deploy library with ${filesByRelativePath.length} auto${filesByRelativePath.length == 1 ? '' : 's'} to ${root.path}.',
  );
}

Future<DeployWorkspaceReadResult> readDeployWorkspace({
  required String targetDirectory,
}) async {
  final File workspaceFile = File('$targetDirectory/workspace.json');
  if (!await workspaceFile.exists()) {
    return const DeployWorkspaceReadResult(
      supported: true,
      workspaceJson: null,
    );
  }
  return DeployWorkspaceReadResult(
    supported: true,
    workspaceJson: await workspaceFile.readAsString(),
  );
}

Future<void> writeDeployWorkspace({
  required String targetDirectory,
  required String workspaceJson,
}) async {
  final Directory root = Directory(targetDirectory);
  await root.create(recursive: true);
  final File workspaceFile = File('${root.path}/workspace.json');
  await workspaceFile.writeAsString(workspaceJson);
}
