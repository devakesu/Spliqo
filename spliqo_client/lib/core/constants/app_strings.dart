/// Centralized string catalog for Spliqo.
abstract final class AppStrings {
  // App Info
  static const String appName = 'Spliqo';
  static const String appTagline = 'Fair bill coordination without the math';

  // Navigation Tabs
  static const String navHome = 'Activity';
  static const String navScan = 'Split';
  static const String navJoin = 'Join';
  static const String navProfile = 'Profile';

  // Home Screen
  static const String welcomeBack = 'Hey there! ✨';
  static const String activeSessionsTitle = 'Active Splits';
  static const String recentSessionsTitle = 'Past Gatherings';
  static const String startNewSplitCTA = 'Start a New Split';
  static const String joinWithCodeCTA = 'Join with Code';
  static const String noActiveSessions = 'No active splits right now.';
  static const String noActiveSessionsSubtitle =
      'Snap a restaurant receipt or join a table using a 6-character room code.';

  // Receipt Review Screen (Screen 1)
  static const String receiptReviewTitle = 'Receipt Draft';
  static const String parseReceiptButton = 'Upload Receipt Image';
  static const String activateSessionCTA = 'Activate Room & Invite Friends';
  static const String lineItemsHeader = 'Detected Items';
  static const String billSummaryHeader = 'Bill Summary';

  // Active Room Screen (Screen 2)
  static const String activeRoomTitle = 'Dinner Room';
  static const String liveSessionBadge = 'Live session';
  static const String reviewingPhaseBadge = 'Reviewing Phase';
  static const String estimatedShareTitle = 'YOUR CURRENT ESTIMATED SHARE';
  static const String estimatedTag = 'Estimated';
  static const String doneSelectingCTA = 'Done Selecting';
  static const String selectionCompleted = 'Selection Completed';
  static const String selectionLockedNotice =
      'Your selections are locked. Share updates live as others finish.';
  static const String reviewAndFinalizeTooltip = 'Review & Finalise';

  // Host Review Screen (Screen 3)
  static const String hostReviewTitle = 'Host Final Review';
  static const String unresolvedCostsBanner = 'Unresolved Items';
  static const String finalizeBillCTA = 'Finalise Bill & Generate Shares';
  static const String resolveUnclaimedCTA = 'Resolve Unclaimed Items';

  // Settlement Screen (Screen 4)
  static const String settlementTitle = 'Final Settlement';
  static const String finalShareTitle = 'YOUR FINAL SHARE';
  static const String finalTag = 'Final';
  static const String payMyShare = 'Pay my share';
  static const String letHostCover = 'Let host cover';
  static const String payWithUpiApp = 'Pay with UPI App';
  static const String markAsPaid = 'Mark as Paid (Notify Host)';
  static const String waitingForHostConfirmation =
      'Waiting for host to confirm your payment.';
  static const String paymentConfirmedByHost = 'Payment confirmed by host!';
  static const String hostCoveredShare = 'Host has covered your share!';

  // Profile / Settings Screen
  static const String profileTitle = 'My Profile';
  static const String payoutSettingsTitle = 'Host Payout UPI ID';
  static const String payoutSettingsSubtitle =
      'Encrypted with hardware KeyStore/Keychain (FLE). Friends pay you directly via UPI.';
  static const String saveUpiCTA = 'Save UPI ID';
  static const String securityBadge = 'Hardware-Encrypted Secure Storage Active';

  // Join Screen
  static const String joinTitle = 'Join a Split';
  static const String enterRoomCodePlaceholder = 'Enter 6-character room code';
  static const String displayNamePlaceholder = 'Your Name at Table';
  static const String joinRoomCTA = 'Join Room';

  // Errors & Fallbacks
  static const String genericError = 'Something unexpected happened.';
  static const String upiAppNotAvailableTitle = 'UPI App Not Available';
  static const String upiFallbackMessage =
      'No installed UPI app could open this payment intent. You can copy the payment URI string below to pay via your bank app:';
  static const String copyIntentCTA = 'Copy Intent';

  // Authentication & Onboarding
  static const String loginTitle = 'Welcome back';
  static const String loginSubtitle =
      'Sign in to split restaurant bills fairly with your table.';
  static const String signupTitle = 'Create account';
  static const String signupSubtitle =
      'Join Spliqo to host receipts, claim items, and settle via UPI.';
  static const String continueWithGoogle = 'Continue with Google';
  static const String signUpWithGoogle = 'Sign up with Google';
  static const String verifyOtpTitle = 'Verify your code';
  static const String verifyEmailOtpSubtitle =
      'Enter the 6-digit verification code sent to';
  static const String verifyPhoneOtpSubtitle =
      'Enter the 6-digit SMS code sent to';
  static const String privacyClaimsNotice =
      'Item claims and your display name are visible to session members to enable shared splits. Your phone number is encrypted at rest.';
  static const String rateLimitNotice =
      'Too many attempts. Please wait a moment before trying again.';
}
