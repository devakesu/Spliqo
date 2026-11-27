import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for the global SupabaseClient.
final Provider<SupabaseClient> supabaseClientProvider =
    Provider<SupabaseClient>((ref) {
  try {
    return Supabase.instance.client;
  } on Object catch (_) {
    // Fallback client for isolated widget/unit tests when Supabase.initialize
    // was not invoked at startup.
    final url = AppConfig.current.supabaseUrl.isNotEmpty
        ? AppConfig.current.supabaseUrl
        : 'https://placeholder.supabase.co';
    final key = AppConfig.current.supabasePublishableKey.isNotEmpty
        ? AppConfig.current.supabasePublishableKey
        : 'sb_publishable_test_placeholder';

    final client = SupabaseClient(
      url,
      key,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    ref.onDispose(client.dispose);
    return client;
  }
});
