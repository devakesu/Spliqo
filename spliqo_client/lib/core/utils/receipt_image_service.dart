import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:spliqo/core/errors/failures.dart';

/// Representation of a validated receipt image.
@immutable
class ReceiptImageFile {
  const new({
    required this.bytes,
    required this.filename,
    required this.mimeType,
    required this.sizeInBytes,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
  final int sizeInBytes;

  double get sizeInMb => sizeInBytes / (1024 * 1024);
}

/// Service enforcing magic-byte validation and compression for receipt uploads.
/// JPEG magic bytes: [0xFF, 0xD8, 0xFF]
/// PNG magic bytes:  [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
class ReceiptImageService {
  const new({this.picker});

  final ImagePicker? picker;

  ImagePicker get _effectivePicker => picker ?? ImagePicker();

  /// Validates magic bytes of raw image bytes and returns a [ReceiptImageFile].
  ReceiptImageFile validateBytes(List<int> rawBytes, {String? filename}) {
    if (rawBytes.length < 4) {
      throw const Failure(
        code: 'invalid_image_file',
        message: 'The selected file is too small or empty.',
      );
    }

    final bytes = rawBytes is Uint8List ? rawBytes : Uint8List.fromList(rawBytes);

    // Check JPEG magic bytes: 0xFF, 0xD8, 0xFF
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

    // Check PNG magic bytes: 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;

    if (!isJpeg && !isPng) {
      throw const Failure(
        code: 'invalid_magic_bytes',
        message: 'Unsupported image format. Please capture a real JPEG or PNG receipt photo.',
      );
    }

    final mimeType = isJpeg ? 'image/jpeg' : 'image/png';
    final resolvedFilename = filename ?? (isJpeg ? 'receipt.jpg' : 'receipt.png');

    return ReceiptImageFile(
      bytes: bytes,
      filename: resolvedFilename,
      mimeType: mimeType,
      sizeInBytes: bytes.length,
    );
  }

  /// Captures or picks a receipt image from [source] and validates its magic bytes.
  Future<ReceiptImageFile?> pickAndValidateReceipt({
    required ImageSource source,
  }) async {
    final pickedFile = await _effectivePicker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );

    if (pickedFile == null) {
      return null;
    }

    final bytes = await pickedFile.readAsBytes();
    return validateBytes(bytes, filename: pickedFile.name);
  }
}
