import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers.dart';
import '../domain/update_policy.dart';
import 'app_config_controller.dart';

/// Storage key of the `latest_version` whose optional update prompt the
/// user dismissed.
const String kDismissedUpdateVersionKey = 'update_prompt.dismissed_version';

/// What the running app must do about its version, recomputed live whenever
/// remote config changes (so a force update also hits mid-session).
final updateRequirementProvider = Provider<UpdateRequirement>((ref) {
  final config = ref.watch(appConfigControllerProvider);
  return UpdatePolicy.evaluate(
    currentVersion: ref.watch(appVersionProvider),
    minSupportedVersion: config.minSupportedVersion,
    latestVersion: config.latestVersion,
  );
});

/// The `latest_version` for which the optional prompt was dismissed.
/// Hydrated in `main.dart` so the prompt doesn't flash on startup.
final dismissedUpdateVersionProvider =
    NotifierProvider<DismissedUpdateVersionController, String?>(
        DismissedUpdateVersionController.new);

class DismissedUpdateVersionController extends Notifier<String?> {
  @override
  String? build() => null;

  void hydrate(String? version) => state = version;

  /// "Later": don't nag again for this [latestVersion]. A newer
  /// `latest_version` shows the prompt again.
  Future<void> dismiss(String latestVersion) async {
    state = latestVersion;
    await ref
        .read(keyValueStoreProvider)
        .setString(kDismissedUpdateVersionKey, latestVersion);
  }
}

/// Wraps the whole app (MaterialApp.builder), so it covers every route.
/// * required -> full-screen, non-dismissible "Update required" page;
/// * optional -> dismissible card, not shown again for the same version.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requirement = ref.watch(updateRequirementProvider);
    final config = ref.watch(appConfigControllerProvider);

    if (requirement == UpdateRequirement.required) {
      // The navigator (and every route on it) is replaced, so there is
      // nothing to go "back" to.
      return UpdateRequiredScreen(updateUrl: config.updateUrl);
    }

    final dismissed = ref.watch(dismissedUpdateVersionProvider);
    final showPrompt = requirement == UpdateRequirement.optional &&
        dismissed != config.latestVersion;
    return Stack(
      children: [
        child,
        if (showPrompt)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: _OptionalUpdateCard(
                latestVersion: config.latestVersion,
                updateUrl: config.updateUrl,
              ),
            ),
          ),
      ],
    );
  }
}

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.updateUrl});

  final String updateUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('⬆️',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text('Update required',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'This version of QuickKart is no longer supported. Please '
                'update the app to keep ordering.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Builder(
                builder: (context) => FilledButton(
                  onPressed: () => openUpdateUrl(context, updateUrl),
                  child: const Text('Update now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionalUpdateCard extends ConsumerWidget {
  const _OptionalUpdateCard(
      {required this.latestVersion, required this.updateUrl});

  final String latestVersion;
  final String updateUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('A new version ($latestVersion) is available',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text('Update for the latest fixes and features.'),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(dismissedUpdateVersionProvider.notifier)
                      .dismiss(latestVersion),
                  child: const Text('Later'),
                ),
                FilledButton.tonal(
                  onPressed: () => openUpdateUrl(context, updateUrl),
                  child: const Text('Update'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the store / download page. If that is impossible (bad URL from the
/// console, no browser), the link is copied so the user is never stuck.
Future<void> openUpdateUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Uri.tryParse(url);
  var opened = false;
  if (uri != null && uri.hasScheme) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
  }
  if (opened) return;
  if (url.isNotEmpty) await Clipboard.setData(ClipboardData(text: url));
  messenger?.showSnackBar(SnackBar(
    content: Text(url.isEmpty
        ? 'Please update QuickKart from your app store.'
        : 'Could not open the link. It was copied: $url'),
  ));
}
