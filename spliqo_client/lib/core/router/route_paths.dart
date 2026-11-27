/// Centralized route paths for Spliqo navigation.
abstract final class AppRoutes {
  // Launch & Auth
  static const String splash = '/splash';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String verifyOtp = '/verify-otp';

  // Root Tabs
  static const String home = '/';
  static const String create = '/create';
  static const String scan = '/create'; // Alias for backward compatibility
  static const String join = '/join';
  static const String profile = '/profile';

  // Deep Link Join
  static const String joinWithToken = '/join/:token';
  static String joinToken(String token) => '/join/$token';

  // Active Session & Flow
  static const String activeRoom = '/room/:id';
  static String room(String id) => '/room/$id';

  static const String hostReview = '/room/:id/review';
  static String review(String id) => '/room/$id/review';

  static const String settlement = '/room/:id/settle';
  static String settle(String id) => '/room/$id/settle';
}
