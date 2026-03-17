import 'deploy_export_api.dart';

Future<DeployExportResult> writeDeployLibrary({
  required String targetDirectory,
  required String indexJson,
  required Map<String, String> filesByRelativePath,
}) async {
  return const DeployExportResult(
    supported: false,
    writtenFiles: 0,
    message:
        'Deploy export writes folders on desktop builds only. Run PathPlanA on macOS, Windows, or Linux for this export mode.',
  );
}

Future<DeployWorkspaceReadResult> readDeployWorkspace({
  required String targetDirectory,
}) async {
  return const DeployWorkspaceReadResult(
    supported: false,
    workspaceJson: null,
  );
}

Future<void> writeDeployWorkspace({
  required String targetDirectory,
  required String workspaceJson,
}) async {}
