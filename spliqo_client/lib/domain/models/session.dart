/// Enums and domain models for Spliqo sessions, participants, claims, and settlements.
library;

enum SessionStatus {
  draft,
  active,
  reviewing,
  finalized,
  cancelled;

  static SessionStatus fromString(String value) {
    return SessionStatus.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => SessionStatus.draft,
    );
  }
}

enum ParticipantRole {
  host,
  participant;

  static ParticipantRole fromString(String value) {
    return ParticipantRole.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => ParticipantRole.participant,
    );
  }
}

enum ClaimSource {
  self,
  hostAssigned;

  static ClaimSource fromString(String value) {
    return value.toLowerCase() == 'host_assigned'
        ? ClaimSource.hostAssigned
        : ClaimSource.self;
  }
}

enum PayPreference {
  undecided,
  selfPay,
  hostPays;

  static PayPreference fromString(String value) {
    switch (value.toLowerCase()) {
      case 'self_pay':
        return PayPreference.selfPay;
      case 'host_pays':
        return PayPreference.hostPays;
      default:
        return PayPreference.undecided;
    }
  }

  String toApiString() {
    switch (this) {
      case PayPreference.selfPay:
        return 'self_pay';
      case PayPreference.hostPays:
        return 'host_pays';
      case PayPreference.undecided:
        return 'undecided';
    }
  }
}

enum PayStatus {
  unpaid,
  pending,
  paid,
  waived;

  static PayStatus fromString(String value) {
    return PayStatus.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => PayStatus.unpaid,
    );
  }
}

/// Representation of an expense coordination session.
class SessionModel {
  const new({
    required this.id,
    required this.hostId,
    required this.title,
    required this.currency,
    required this.subtotalPaise,
    required this.taxPaise,
    required this.serviceChargePaise,
    required this.discountPaise,
    required this.roundOffPaise,
    required this.totalPaise,
    required this.status,
    required this.revision,
    this.items = const <BillItemModel>[],
  });

  factory fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => BillItemModel.fromJson(item as Map<String, dynamic>))
        .toList();

    return SessionModel(
      id: json['id'] as String,
      hostId: json['host_id'] as String,
      title: json['title'] as String,
      currency: json['currency'] as String? ?? 'INR',
      subtotalPaise: json['subtotal_paise'] as int,
      taxPaise: json['tax_paise'] as int? ?? 0,
      serviceChargePaise: json['service_charge_paise'] as int? ?? 0,
      discountPaise: json['discount_paise'] as int? ?? 0,
      roundOffPaise: json['round_off_paise'] as int? ?? 0,
      totalPaise: json['total_paise'] as int,
      status: SessionStatus.fromString(json['status'] as String),
      revision: json['revision'] as int? ?? 0,
      items: itemsList,
    );
  }

  final String id;
  final String hostId;
  final String title;
  final String currency;
  final int subtotalPaise;
  final int taxPaise;
  final int serviceChargePaise;
  final int discountPaise;
  final int roundOffPaise;
  final int totalPaise;
  final SessionStatus status;
  final int revision;
  final List<BillItemModel> items;

  SessionModel copyWith({
    String? id,
    String? hostId,
    String? title,
    String? currency,
    int? subtotalPaise,
    int? taxPaise,
    int? serviceChargePaise,
    int? discountPaise,
    int? roundOffPaise,
    int? totalPaise,
    SessionStatus? status,
    int? revision,
    List<BillItemModel>? items,
  }) {
    return SessionModel(
      id: id ?? this.id,
      hostId: hostId ?? this.hostId,
      title: title ?? this.title,
      currency: currency ?? this.currency,
      subtotalPaise: subtotalPaise ?? this.subtotalPaise,
      taxPaise: taxPaise ?? this.taxPaise,
      serviceChargePaise: serviceChargePaise ?? this.serviceChargePaise,
      discountPaise: discountPaise ?? this.discountPaise,
      roundOffPaise: roundOffPaise ?? this.roundOffPaise,
      totalPaise: totalPaise ?? this.totalPaise,
      status: status ?? this.status,
      revision: revision ?? this.revision,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'host_id': hostId,
      'title': title,
      'currency': currency,
      'subtotal_paise': subtotalPaise,
      'tax_paise': taxPaise,
      'service_charge_paise': serviceChargePaise,
      'discount_paise': discountPaise,
      'round_off_paise': roundOffPaise,
      'total_paise': totalPaise,
      'status': status.name,
      'revision': revision,
      'items': items.map((i) => i.toJson()).toList(),
    };
  }
}

/// A line item in the session receipt.
class BillItemModel {
  const new({
    required this.id,
    required this.sessionId,
    required this.position,
    required this.name,
    required this.pricePaise,
  });

  factory fromJson(Map<String, dynamic> json) {
    return BillItemModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      position: json['position'] as int? ?? 0,
      name: json['name'] as String,
      pricePaise: json['price_paise'] as int,
    );
  }

  final String id;
  final String sessionId;
  final int position;
  final String name;
  final int pricePaise;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'position': position,
      'name': name,
      'price_paise': pricePaise,
    };
  }
}

/// A participant participating in a session.
class ParticipantModel {
  const new({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.role,
    required this.displayName,
    this.selectionCompletedAt,
  });

  factory fromJson(Map<String, dynamic> json) {
    final completedAtStr = json['selection_completed_at'] as String?;
    return ParticipantModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      role: ParticipantRole.fromString(json['role'] as String? ?? 'participant'),
      displayName: json['display_name'] as String,
      selectionCompletedAt: completedAtStr != null ? DateTime.parse(completedAtStr) : null,
    );
  }

  final String id;
  final String sessionId;
  final String userId;
  final ParticipantRole role;
  final String displayName;
  final DateTime? selectionCompletedAt;

  bool get isSelectionCompleted => selectionCompletedAt != null;

  ParticipantModel copyWith({
    String? id,
    String? sessionId,
    String? userId,
    ParticipantRole? role,
    String? displayName,
    DateTime? selectionCompletedAt,
  }) {
    return ParticipantModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      displayName: displayName ?? this.displayName,
      selectionCompletedAt: selectionCompletedAt ?? this.selectionCompletedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'user_id': userId,
      'role': role.name,
      'display_name': displayName,
      'selection_completed_at': selectionCompletedAt?.toIso8601String(),
    };
  }
}

/// A claim on a bill item by a participant.
class ClaimModel {
  const new({
    required this.id,
    required this.sessionId,
    required this.itemId,
    required this.participantId,
    required this.source,
  });

  factory fromJson(Map<String, dynamic> json) {
    return ClaimModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      itemId: json['item_id'] as String,
      participantId: json['participant_id'] as String,
      source: ClaimSource.fromString(json['source'] as String? ?? 'self'),
    );
  }

  final String id;
  final String sessionId;
  final String itemId;
  final String participantId;
  final ClaimSource source;
}

/// Settlement details for a participant after session finalization.
class SettlementModel {
  const new({
    required this.participantId,
    required this.sessionId,
    required this.payPreference, required this.payStatus, this.finalAmountPaise,
  });

  factory fromJson(Map<String, dynamic> json) {
    return SettlementModel(
      participantId: json['participant_id'] as String,
      sessionId: json['session_id'] as String,
      finalAmountPaise: json['final_amount_paise'] as int?,
      payPreference: PayPreference.fromString(json['pay_preference'] as String? ?? 'undecided'),
      payStatus: PayStatus.fromString(json['pay_status'] as String? ?? 'unpaid'),
    );
  }

  final String participantId;
  final String sessionId;
  final int? finalAmountPaise;
  final PayPreference payPreference;
  final PayStatus payStatus;
}
