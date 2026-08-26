import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import 'notification_settings_screen.dart';

/// No real notification backend exists yet (see
/// `notifications_provider.dart`'s own doc comment) — this screen shows an
/// honest empty state rather than fabricated notification content.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim Merkezim'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsScreen(),
                ),
              );
            },
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: const SafeArea(
        child: EmptyView(
          icon: Icons.notifications_none_rounded,
          message: 'Henüz bir bildiriminiz bulunmuyor.',
        ),
      ),
    );
  }
}
