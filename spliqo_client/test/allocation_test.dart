import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/domain/allocation/allocation.dart';

void main() {
  late Map<String, dynamic> vectorsData;

  setUpAll(() {
    // Look for shared/allocation_vectors.json
    var file = File('../shared/allocation_vectors.json');
    if (!file.existsSync()) {
      file = File('shared/allocation_vectors.json');
    }
    if (!file.existsSync()) {
      file = File('../../shared/allocation_vectors.json');
    }
    expect(file.existsSync(), isTrue, reason: 'shared/allocation_vectors.json must exist');
    vectorsData = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  group('Shared Golden Vectors', () {
    test('calculateSplit matches all shared golden vectors', () {
      final vectors = vectorsData['vectors'] as List<dynamic>;
      for (final rawVec in vectors) {
        final vec = rawVec as Map<String, dynamic>;
        final itemsRaw = vec['items'] as Map<String, dynamic>;
        final items = itemsRaw.map((k, v) => MapEntry(k, v as int));

        final claimsRaw = vec['claims'] as Map<String, dynamic>;
        final claims = claimsRaw.map(
          (k, v) => MapEntry(k, (v as List<dynamic>).map((e) => e as String).toList()),
        );

        final participants = (vec['participants'] as List<dynamic>).map((e) => e as String).toList();
        final subtotalPaise = vec['subtotal_paise'] as int;
        final totalPaise = vec['total_paise'] as int;
        final expectedFinalRaw = vec['expected_final'] as Map<String, dynamic>;
        final expectedFinal = expectedFinalRaw.map((k, v) => MapEntry(k, v as int));

        final result = calculateSplit(
          items: items,
          claims: claims,
          participants: participants,
          subtotalPaise: subtotalPaise,
          totalPaise: totalPaise,
        );

        expect(result, equals(expectedFinal), reason: 'Mismatch in vector: ${vec['name']}');

        // Sum invariant
        var sumResult = 0;
        for (final v in result.values) {
          sumResult += v;
        }
        expect(sumResult, equals(totalPaise));
      }
    });

    test('estimateSharePaise matches all shared estimate vectors', () {
      final estimates = vectorsData['estimates'] as List<dynamic>;
      for (final rawEst in estimates) {
        final est = rawEst as Map<String, dynamic>;
        final itemsPaise = est['items_paise'] as int;
        final subtotalPaise = est['subtotal_paise'] as int;
        final totalPaise = est['total_paise'] as int;
        final expectedEstimate = est['expected_estimate'] as int;

        final result = estimateSharePaise(
          itemsPaise: itemsPaise,
          subtotalPaise: subtotalPaise,
          totalPaise: totalPaise,
        );

        expect(result, equals(expectedEstimate), reason: 'Mismatch in estimate: ${est['name']}');
      }
    });

    test('estimateSharePaise throws on invalid inputs', () {
      expect(
        () => estimateSharePaise(itemsPaise: 10, subtotalPaise: 0, totalPaise: 100),
        throwsArgumentError,
      );
      expect(
        () => estimateSharePaise(itemsPaise: -1, subtotalPaise: 100, totalPaise: 100),
        throwsArgumentError,
      );
    });
  });

  group('splitExact invariants', () {
    test('Sums to exact amount and breaks ties deterministically', () {
      final result = splitExact(100, {'a': 1, 'b': 1, 'c': 1});
      expect(result, equals({'a': 34, 'b': 33, 'c': 33}));
      var sum = 0;
      for (final v in result.values) {
        sum += v;
      }
      expect(sum, equals(100));
    });

    test('Zero amount splits to zero shares', () {
      final result = splitExact(0, {'a': 1, 'b': 2});
      expect(result, equals({'a': 0, 'b': 0}));
    });

    test('Negative amount throws ArgumentError', () {
      expect(() => splitExact(-10, {'a': 1}), throwsArgumentError);
    });

    test('Zero total weight throws ArgumentError', () {
      expect(() => splitExact(100, {'a': 0, 'b': 0}), throwsArgumentError);
    });

    test('Negative weight throws ArgumentError', () {
      expect(() => splitExact(100, {'a': -1, 'b': 2}), throwsArgumentError);
    });
  });

  group('calculateSplit error conditions', () {
    test('Throws if any item is unclaimed', () {
      expect(
        () => calculateSplit(
          items: {'i1': 5000, 'i2': 3000},
          claims: {'i1': ['a']}, // i2 unclaimed
          participants: ['a', 'b'],
          subtotalPaise: 8000,
          totalPaise: 8000,
        ),
        throwsArgumentError,
      );
    });

    test('Throws if items do not match subtotal', () {
      expect(
        () => calculateSplit(
          items: {'i1': 5000},
          claims: {'i1': ['a']},
          participants: ['a'],
          subtotalPaise: 6000,
          totalPaise: 6000,
        ),
        throwsArgumentError,
      );
    });

    test('Throws if total is out of range', () {
      expect(
        () => calculateSplit(
          items: {'i1': 100},
          claims: {'i1': ['a']},
          participants: ['a'],
          subtotalPaise: 100,
          totalPaise: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => calculateSplit(
          items: {'i1': 100},
          claims: {'i1': ['a']},
          participants: ['a'],
          subtotalPaise: 100,
          totalPaise: maxReceiptTotalPaise + 1,
        ),
        throwsArgumentError,
      );
    });
  });
}
