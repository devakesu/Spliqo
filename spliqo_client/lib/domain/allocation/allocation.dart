/// Pure allocation engine for Spliqo.
///
/// Implements the Largest Remainder Method (Hamilton-Hare) for exact paise splits
/// and live share estimation. No I/O, no floats, no datetime, no randomness.
/// Mirrors backend/app/domain/allocation.py. Validated by shared/allocation_vectors.json.
library;

const int maxReceiptTotalPaise = 10000000;

/// Largest Remainder split of a non-negative integer amount.
///
/// [amount] is a non-negative integer in paise to split.
/// [weights] maps keys (lowercase UUID strings) to non-negative integer weights.
/// At least one weight must be positive.
Map<String, int> splitExact(int amount, Map<String, int> weights) {
  var totalW = 0;
  for (final w in weights.values) {
    if (w < 0) {
      throw ArgumentError('invalid_split_input: negative weight');
    }
    totalW += w;
  }
  if (amount < 0 || totalW <= 0) {
    throw ArgumentError('invalid_split_input: amount < 0 or totalW <= 0');
  }

  final base = <String, int>{};
  final rem = <String, int>{};

  var baseSum = 0;
  for (final entry in weights.entries) {
    final key = entry.key;
    final w = entry.value;
    final quota = amount * w;
    final b = quota ~/ totalW;
    final r = quota % totalW;
    base[key] = b;
    rem[key] = r;
    baseSum += b;
  }

  final leftover = amount - baseSum;

  final sortedKeys = weights.keys.toList()
    ..sort((a, b) {
      final remA = rem[a]!;
      final remB = rem[b]!;
      final remComp = remB.compareTo(remA); // descending rem
      if (remComp != 0) {
        return remComp;
      }
      return a.compareTo(b); // ascending key
    });

  for (var i = 0; i < leftover; i++) {
    final key = sortedKeys[i];
    base[key] = base[key]! + 1;
  }

  return base;
}

/// Authoritative final amounts for all participants in a finalized session.
Map<String, int> calculateSplit({
  required Map<String, int> items,
  required Map<String, List<String>> claims,
  required List<String> participants,
  required int subtotalPaise,
  required int totalPaise,
}) {
  var itemsSum = 0;
  for (final price in items.values) {
    itemsSum += price;
  }
  if (itemsSum != subtotalPaise || subtotalPaise < 1) {
    throw ArgumentError('items_do_not_match_subtotal');
  }
  if (totalPaise < 1 || totalPaise > maxReceiptTotalPaise) {
    throw ArgumentError('total_out_of_range');
  }

  final itemsTotal = <String, int>{
    for (final p in participants) p: 0,
  };

  for (final entry in items.entries) {
    final itemId = entry.key;
    final price = entry.value;
    final claimants = claims[itemId];
    if (claimants == null || claimants.isEmpty) {
      throw ArgumentError('unclaimed_item');
    }
    final claimantWeights = <String, int>{
      for (final c in claimants) c: 1,
    };
    final shares = splitExact(price, claimantWeights);
    for (final shareEntry in shares.entries) {
      final p = shareEntry.key;
      itemsTotal[p] = (itemsTotal[p] ?? 0) + shareEntry.value;
    }
  }

  final adjustment = totalPaise - subtotalPaise;
  final absAdj = adjustment.abs();

  var totalWeight = 0;
  for (final v in itemsTotal.values) {
    totalWeight += v;
  }

  final Map<String, int> adj;
  if (absAdj > 0 && totalWeight > 0) {
    adj = splitExact(absAdj, itemsTotal);
  } else {
    adj = {for (final p in participants) p: 0};
  }

  final sign = adjustment < 0 ? -1 : 1;
  final finalMap = <String, int>{};
  var finalSum = 0;

  for (final p in participants) {
    final pTotal = itemsTotal[p]! + sign * (adj[p] ?? 0);
    if (pTotal < 0) {
      throw StateError('negative_share');
    }
    finalMap[p] = pTotal;
    finalSum += pTotal;
  }

  if (finalSum != totalPaise) {
    throw StateError('sum_invariant_failed');
  }

  return finalMap;
}

/// Live provisional estimate for one participant during active session.
int estimateSharePaise({
  required int itemsPaise,
  required int subtotalPaise,
  required int totalPaise,
}) {
  if (subtotalPaise < 1) {
    throw ArgumentError('invalid_subtotal_paise');
  }
  if (itemsPaise < 0) {
    throw ArgumentError('invalid_items_paise');
  }
  final adjustment = totalPaise - subtotalPaise;
  final a = adjustment.abs();
  final adj = (a * itemsPaise + subtotalPaise ~/ 2) ~/ subtotalPaise;
  return itemsPaise + (adjustment >= 0 ? adj : -adj);
}
