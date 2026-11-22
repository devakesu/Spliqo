import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/core/errors/failures.dart';
import 'package:spliqo/core/utils/receipt_image_service.dart';

void main() {
  group('ReceiptImageService Magic Byte Validation Tests', () {
    const service = ReceiptImageService();

    test('accepts valid JPEG magic bytes (FF D8 FF)', () {
      final validJpegBytes = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00,
        ...List.filled(50, 1),
      ]);

      final result = service.validateBytes(validJpegBytes, filename: 'bill.jpg');

      expect(result.mimeType, equals('image/jpeg'));
      expect(result.filename, equals('bill.jpg'));
      expect(result.sizeInBytes, equals(validJpegBytes.length));
    });

    test('accepts valid PNG magic bytes (89 50 4E 47 0D 0A 1A 0A)', () {
      final validPngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        ...List.filled(50, 2),
      ]);

      final result = service.validateBytes(validPngBytes, filename: 'receipt.png');

      expect(result.mimeType, equals('image/png'));
      expect(result.filename, equals('receipt.png'));
      expect(result.sizeInBytes, equals(validPngBytes.length));
    });

    test('rejects unsupported file formats (e.g. PDF, GIF, plain text)', () {
      final pdfBytes = Uint8List.fromList([
        0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x35, // %PDF-1.5
      ]);

      expect(
        () => service.validateBytes(pdfBytes),
        throwsA(
          isA<Failure>().having(
            (f) => f.code,
            'code',
            equals('invalid_magic_bytes'),
          ),
        ),
      );
    });

    test('rejects empty or truncated bytes', () {
      final tinyBytes = Uint8List.fromList([0xFF, 0xD8]);

      expect(
        () => service.validateBytes(tinyBytes),
        throwsA(
          isA<Failure>().having(
            (f) => f.code,
            'code',
            equals('invalid_image_file'),
          ),
        ),
      );
    });
  });
}
