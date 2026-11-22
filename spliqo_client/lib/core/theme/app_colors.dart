import 'package:flutter/material.dart';

/// Centralized color palette for Spliqo.
/// Modern, aesthetic, colourful and cute fintech aesthetic.
abstract final class AppColors {
  // Brand Radiant Accents
  static const Color radiantViolet = Color(0xFF7C3AED);
  static const Color radiantVioletLight = Color(0xFF8B5CF6);
  static const Color radiantVioletSoft = Color(0xFFEDE9FE);

  static const Color bubblegumPink = Color(0xFFEC4899);
  static const Color bubblegumPinkLight = Color(0xFFF472B6);
  static const Color bubblegumPinkSoft = Color(0xFFFDF2F8);

  static const Color electricSky = Color(0xFF0EA5E9);
  static const Color electricSkyLight = Color(0xFF38BDF8);
  static const Color electricSkySoft = Color(0xFFF0F9FF);

  static const Color mintFresh = Color(0xFF10B981);
  static const Color mintFreshLight = Color(0xFF34D399);
  static const Color mintFreshSoft = Color(0xFFECFDF5);

  static const Color sunbeamAmber = Color(0xFFF59E0B);
  static const Color sunbeamAmberLight = Color(0xFFFBBF24);
  static const Color sunbeamAmberSoft = Color(0xFFFFFBEB);

  // Neutral & Canvas (Light)
  static const Color canvasLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF1F5F9);

  // Neutral & Canvas (Dark)
  static const Color canvasDark = Color(0xFF090D16);
  static const Color surfaceDark = Color(0xFF131A29);
  static const Color surfaceVariantDark = Color(0xFF1E293B);

  // Typography Colors
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textMutedLight = Color(0xFF94A3B8);

  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textMutedDark = Color(0xFF64748B);

  // Crystal Glass Tints & Specular Highlights
  static const Color crystalFrostLight = Color(0xCCFFFFFF);
  static const Color crystalFrostDark = Color(0xB3131A29);
  static const Color crystalBorderLight = Color(0x40FFFFFF);
  static const Color crystalBorderDark = Color(0x26FFFFFF);
  static const Color crystalHighlight = Color(0x80FFFFFF);

  // State Badges
  static const Color estimatedBadgeBackground = Color(0xFFFEF3C7);
  static const Color estimatedBadgeText = Color(0xFFB45309);

  static const Color finalBadgeBackground = Color(0xFFD1FAE5);
  static const Color finalBadgeText = Color(0xFF065F46);

  static const Color errorRed = Color(0xFFEF4444);
  static const Color errorRedSoft = Color(0xFFFEF2F2);
}
