import 'package:flutter/foundation.dart';

enum AttendanceStatus { present, late, absent }

extension AttendanceStatusLabel on AttendanceStatus {
  String get label => switch (this) {
        AttendanceStatus.present => '参加',
        AttendanceStatus.late => '遅刻',
        AttendanceStatus.absent => '不参加',
      };
}

@immutable
class Member {
  final String id;
  final String name;

  const Member({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(id: json['id'] as String, name: json['name'] as String);
  }
}

@immutable
class AttendanceRecord {
  final String id;
  final String dateKey;
  final String memberId;
  final String memberName;
  final AttendanceStatus status;
  final String reason;

  const AttendanceRecord({
    required this.id,
    required this.dateKey,
    required this.memberId,
    required this.memberName,
    required this.status,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateKey': dateKey,
        'memberId': memberId,
        'memberName': memberName,
        'status': status.name,
        'reason': reason,
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'] as String,
      dateKey: json['dateKey'] as String,
      memberId: json['memberId'] as String,
      memberName: json['memberName'] as String,
      status: AttendanceStatus.values.byName(json['status'] as String),
      reason: (json['reason'] as String?) ?? '',
    );
  }
}

@immutable
class DaySummary {
  final int presentCount;
  final int absentCount;

  const DaySummary({required this.presentCount, required this.absentCount});
}

@immutable
class MonthSummary {
  final int presentDays;
  final int absentDays;

  const MonthSummary({required this.presentDays, required this.absentDays});
}

@immutable
class MemberMonthSummary {
  final int presentDays;
  final int lateDays;
  final int absentDays;

  const MemberMonthSummary({
    required this.presentDays,
    required this.lateDays,
    required this.absentDays,
  });

  int get activeDays => presentDays + lateDays;

  int get recordedDays => activeDays + absentDays;
}

@immutable
class AppData {
  final List<Member> members;
  final List<AttendanceRecord> records;

  const AppData({required this.members, required this.records});

  factory AppData.initial() => const AppData(members: [], records: []);

  AppData copyWith({List<Member>? members, List<AttendanceRecord>? records}) {
    return AppData(
      members: members ?? this.members,
      records: records ?? this.records,
    );
  }

  Map<String, dynamic> toJson() => {
        'members': members.map((e) => e.toJson()).toList(),
        'records': records.map((e) => e.toJson()).toList(),
      };

  factory AppData.fromJson(Map<String, dynamic> json) {
    return AppData(
      members: (json['members'] as List<dynamic>? ?? [])
          .map((e) => Member.fromJson(e as Map<String, dynamic>))
          .toList(),
      records: (json['records'] as List<dynamic>? ?? [])
          .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static String dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DaySummary dailySummary(DateTime date) {
    final key = dateKey(date);
    var present = 0;
    var absent = 0;
    for (final record in records.where((r) => r.dateKey == key)) {
      if (record.status == AttendanceStatus.absent) {
        absent++;
      } else {
        present++;
      }
    }
    return DaySummary(presentCount: present, absentCount: absent);
  }

  MonthSummary monthlySummary(DateTime date) {
    final prefix =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
    final presentDays = <String>{};
    final absentDays = <String>{};

    for (final record in records.where((r) => r.dateKey.startsWith(prefix))) {
      if (record.status == AttendanceStatus.absent) {
        absentDays.add(record.dateKey);
      } else {
        presentDays.add(record.dateKey);
      }
    }

    return MonthSummary(
      presentDays: presentDays.length,
      absentDays: absentDays.length,
    );
  }

  MemberMonthSummary memberMonthlySummary(Member member, DateTime date) {
    final prefix =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
    final presentDays = <String>{};
    final lateDays = <String>{};
    final absentDays = <String>{};

    for (final record in records.where(
      (r) => r.memberId == member.id && r.dateKey.startsWith(prefix),
    )) {
      switch (record.status) {
        case AttendanceStatus.present:
          presentDays.add(record.dateKey);
        case AttendanceStatus.late:
          lateDays.add(record.dateKey);
        case AttendanceStatus.absent:
          absentDays.add(record.dateKey);
      }
    }

    return MemberMonthSummary(
      presentDays: presentDays.length,
      lateDays: lateDays.length,
      absentDays: absentDays.length,
    );
  }
}
