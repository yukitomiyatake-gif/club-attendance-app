import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase/supabase.dart';

import 'models.dart';

const _supabaseUrl = 'https://msnzoxbjfskbgihtxywv.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1zbnpveGJqZnNrYmdpaHR4eXd2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE5Mjk5MjksImV4cCI6MjA5NzUwNTkyOX0.2cP3Wp8zRCTrqRayKHt4MsrEfH6FnRIXEijT98uqo4Y';

const _maxNameLength = 40;
const _minPasswordLength = 4;
const _maxPasswordLength = 72;
const _maxReasonLength = 200;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ClubAttendanceApp());
}

final supabaseClient = SupabaseClient(_supabaseUrl, _supabaseAnonKey);

enum LoginMode { member, admin }

class ClubAttendanceApp extends StatelessWidget {
  const ClubAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '部活動参加記録',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _adminNameController = TextEditingController(text: 'admin');
  final _adminPasswordController = TextEditingController();
  final _newMemberNameController = TextEditingController();
  final _newMemberPasswordController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  bool _authLoading = false;
  bool _adminLoading = false;
  bool _isAdmin = false;
  LoginMode _loginMode = LoginMode.member;
  AppData _data = AppData.initial();
  Member? _currentMember;
  String? _message;

  SupabaseClient get _client => supabaseClient;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _adminNameController.dispose();
    _adminPasswordController.dispose();
    _newMemberNameController.dispose();
    _newMemberPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final membersResult = await _client
          .from('members_public')
          .select('id, name, sort_order')
          .order('sort_order');
      final members = (membersResult as List<dynamic>)
          .map(
            (row) => Member(
              id: row['id'] as String,
              name: row['name'] as String,
            ),
          )
          .toList();

      final memberNames = {
        for (final member in members) member.id: member.name
      };
      final recordsResult = await _client
          .from('attendance_records')
          .select('id, member_id, date, status, reason')
          .order('date');
      final records = (recordsResult as List<dynamic>)
          .map(
            (row) => AttendanceRecord(
              id: row['id'] as String,
              dateKey: row['date'] as String,
              memberId: row['member_id'] as String,
              memberName: memberNames[row['member_id']] ?? '',
              status: AttendanceStatus.values.byName(row['status'] as String),
              reason: (row['reason'] as String?) ?? '',
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _data = AppData(members: members, records: records);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'データを読み込めませんでした。Supabaseの設定を確認してください。';
        _loading = false;
      });
    }
  }

  AttendanceRecord? _recordOf(Member member) {
    final dateKey = AppData.dateKey(_selectedDate);
    for (final record in _data.records) {
      if (record.dateKey == dateKey && record.memberId == member.id) {
        return record;
      }
    }
    return null;
  }

  List<AttendanceRecord> _recordsForMemberMonth(Member member, DateTime month) {
    final prefix =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final records = _data.records
        .where((r) => r.memberId == member.id && r.dateKey.startsWith(prefix))
        .toList();
    records.sort((a, b) => a.dateKey.compareTo(b.dateKey));
    return records;
  }

  Future<void> _startOrRegister() async {
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    if (name.isEmpty || password.isEmpty) {
      setState(() => _message = '名前とパスワードを入力してください。');
      return;
    }
    if (name.length > _maxNameLength) {
      setState(() => _message = '名前は$_maxNameLength文字以内で入力してください。');
      return;
    }
    if (password.length < _minPasswordLength ||
        password.length > _maxPasswordLength) {
      setState(() => _message =
          'パスワードは$_minPasswordLength〜$_maxPasswordLength文字で入力してください。');
      return;
    }

    setState(() {
      _authLoading = true;
      _message = null;
    });

    try {
      final verified = await _client.rpc(
        'verify_member_password',
        params: {'member_name': name, 'plain_password': password},
      );
      final verifiedRows = verified as List<dynamic>;

      if (verifiedRows.isEmpty) {
        throw Exception('invalid member');
      }

      final row = verifiedRows.first as Map<String, dynamic>;
      _currentMember = Member(
        id: row['member_id'] as String,
        name: row['name'] as String,
      );

      await _loadData();
      if (!mounted) return;
      setState(() {
        _authLoading = false;
        _message = '${_currentMember!.name} さんとして開始しました。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authLoading = false;
        _message = '登録済みの名前とパスワードを確認してください。';
      });
    }
  }

  Future<void> _adminLogin() async {
    final adminName = _adminNameController.text.trim();
    final password = _adminPasswordController.text;
    if (adminName.isEmpty || password.isEmpty) {
      setState(() => _message = '管理者名と管理者パスワードを入力してください。');
      return;
    }
    if (adminName.length > _maxNameLength ||
        password.length < _minPasswordLength ||
        password.length > _maxPasswordLength) {
      setState(() => _message = '入力内容の長さを確認してください。');
      return;
    }

    setState(() {
      _adminLoading = true;
      _message = null;
    });

    try {
      final ok = await _client.rpc(
        'verify_admin_password',
        params: {'admin_name': adminName, 'plain_password': password},
      );
      if (ok != true) {
        throw Exception('invalid admin');
      }
      await _loadData();
      if (!mounted) return;
      setState(() {
        _isAdmin = true;
        _currentMember = null;
        _adminLoading = false;
        _message = '管理者としてログインしました。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _adminLoading = false;
        _message = '管理者名または管理者パスワードが違います。';
      });
    }
  }

  Future<void> _addMemberAsAdmin() async {
    final memberName = _newMemberNameController.text.trim();
    final memberPassword = _newMemberPasswordController.text;
    if (memberName.isEmpty || memberPassword.isEmpty) {
      setState(() => _message = '追加する部員の名前とパスワードを入力してください。');
      return;
    }
    if (memberName.length > _maxNameLength ||
        memberPassword.length < _minPasswordLength ||
        memberPassword.length > _maxPasswordLength) {
      setState(() => _message = '名前は40文字以内、パスワードは4〜72文字にしてください。');
      return;
    }

    setState(() => _adminLoading = true);
    try {
      await _client.rpc(
        'admin_create_member_with_password',
        params: {
          'admin_name': _adminNameController.text.trim(),
          'admin_password': _adminPasswordController.text,
          'member_name': memberName,
          'member_password': memberPassword,
        },
      );
      _newMemberNameController.clear();
      _newMemberPasswordController.clear();
      await _loadData();
      if (!mounted) return;
      setState(() {
        _adminLoading = false;
        _message = '部員を追加しました。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _adminLoading = false;
        _message = '部員を追加できませんでした。名前の重複や入力内容を確認してください。';
      });
    }
  }

  Future<void> _deleteMemberAsAdmin(Member member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('部員を削除'),
        content: Text('${member.name} さんを削除しますか？出欠記録も削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _adminLoading = true);
    try {
      await _client.rpc(
        'admin_delete_member',
        params: {
          'admin_name': _adminNameController.text.trim(),
          'admin_password': _adminPasswordController.text,
          'target_member_id': member.id,
        },
      );
      await _loadData();
      if (!mounted) return;
      setState(() {
        _adminLoading = false;
        _message = '部員を削除しました。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _adminLoading = false;
        _message = '部員を削除できませんでした。';
      });
    }
  }

  Future<void> _moveMemberAsAdmin(Member member, int direction) async {
    setState(() => _adminLoading = true);
    try {
      await _client.rpc(
        'admin_move_member',
        params: {
          'admin_name': _adminNameController.text.trim(),
          'admin_password': _adminPasswordController.text,
          'target_member_id': member.id,
          'move_direction': direction,
        },
      );
      await _loadData();
      if (!mounted) return;
      setState(() => _adminLoading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _adminLoading = false;
        _message = '並べ替えできませんでした。';
      });
    }
  }

  Future<void> _saveMyRecord(AttendanceStatus status, String reason) async {
    final member = _currentMember;
    final password = _passwordController.text;
    if (member == null || password.isEmpty) return;
    if (reason.trim().length > _maxReasonLength) {
      setState(() => _message = '理由・メモは$_maxReasonLength文字以内で入力してください。');
      return;
    }

    try {
      await _client.rpc(
        'save_member_attendance',
        params: {
          'member_name': member.name,
          'plain_password': password,
          'record_date': AppData.dateKey(_selectedDate),
          'record_status': status.name,
          'record_reason': reason.trim(),
        },
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '保存できませんでした。入力内容を確認してください。');
    }
  }

  Future<void> _openReasonDialog() async {
    final member = _currentMember;
    if (member == null) return;
    final current = _recordOf(member);
    final reasonController = TextEditingController(text: current?.reason ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${member.name} の理由'),
          content: TextField(
            controller: reasonController,
            autofocus: true,
            maxLength: _maxReasonLength,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_maxReasonLength),
            ],
            decoration: const InputDecoration(
              labelText: '理由・メモ',
              hintText: '遅刻・不参加などの理由を入力',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _saveMyRecord(
        current?.status ?? AttendanceStatus.present,
        reasonController.text,
      );
    }
    reasonController.dispose();
  }

  Future<void> _openMemberMonthDialog(Member member) async {
    final monthLabel = DateFormat('y年M月').format(_selectedMonth);
    final summary = _data.memberMonthlySummary(member, _selectedMonth);
    final records = _recordsForMemberMonth(member, _selectedMonth);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${member.name} の月別記録'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(monthLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('参加 ${summary.presentDays}回')),
                    Chip(label: Text('遅刻 ${summary.lateDays}回')),
                    Chip(label: Text('不参加 ${summary.absentDays}回')),
                    Chip(label: Text('活動日数 ${summary.activeDays}日')),
                  ],
                ),
                const SizedBox(height: 12),
                if (records.isEmpty)
                  const Text('この月の記録はまだありません。')
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: records.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final record = records[index];
                        final parsedDate = DateTime.parse(record.dateKey);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(DateFormat('M月d日').format(parsedDate)),
                          subtitle: record.reason.isEmpty
                              ? null
                              : Text(record.reason),
                          trailing: Text(record.status.label),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  void _changeSelectedMonth(int monthOffset) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + monthOffset,
      );
    });
  }

  void _jumpToThisMonth() {
    final now = DateTime.now();
    setState(() => _selectedMonth = DateTime(now.year, now.month));
  }

  void _signOut() {
    setState(() {
      _currentMember = null;
      _isAdmin = false;
      _passwordController.clear();
      _adminPasswordController.clear();
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedMonthLabel = DateFormat('y年M月').format(_selectedMonth);
    final dailySummary = _data.dailySummary(_selectedDate);
    final currentMember = _currentMember;
    final currentRecord =
        currentMember == null ? null : _recordOf(currentMember);

    return Scaffold(
      appBar: AppBar(
        title: const Text('部活動参加記録'),
        actions: [
          IconButton(
            tooltip: '更新',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
          if (currentMember != null || _isAdmin)
            IconButton(
              tooltip: '終了',
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (currentMember == null && !_isAdmin)
                  _buildStartCard()
                else if (_isAdmin) ...[
                  _buildAdminCard(),
                  const SizedBox(height: 16),
                  _buildMonthlySummaryCard(selectedMonthLabel),
                  const SizedBox(height: 16),
                  _buildDateCard(dailySummary),
                  const SizedBox(height: 16),
                  _buildDailyStatusCard(),
                ] else ...[
                  Text(
                    '${currentMember!.name} さん',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _buildMonthlySummaryCard(selectedMonthLabel),
                  const SizedBox(height: 16),
                  _buildDateCard(dailySummary),
                  const SizedBox(height: 16),
                  _buildMyRecordCard(currentRecord),
                  const SizedBox(height: 16),
                  _buildDailyStatusCard(),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(_message!),
                ],
              ],
            ),
    );
  }

  Widget _buildStartCard() {
    final isAdminLogin = _loginMode == LoginMode.admin;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAdminLogin ? '管理者ログイン' : '部員ログイン',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SegmentedButton<LoginMode>(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(92, 40)),
              ),
              segments: const [
                ButtonSegment(
                  value: LoginMode.member,
                  label: Text('部員'),
                  icon: Icon(Icons.person),
                ),
                ButtonSegment(
                  value: LoginMode.admin,
                  label: Text('管理者'),
                  icon: Icon(Icons.admin_panel_settings),
                ),
              ],
              selected: {_loginMode},
              onSelectionChanged: (selected) {
                setState(() {
                  _loginMode = selected.first;
                  _message = null;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: isAdminLogin ? _adminNameController : _nameController,
              maxLength: _maxNameLength,
              inputFormatters: [
                LengthLimitingTextInputFormatter(_maxNameLength),
              ],
              decoration: InputDecoration(
                labelText: isAdminLogin ? '管理者名' : '名前',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller:
                  isAdminLogin ? _adminPasswordController : _passwordController,
              obscureText: true,
              maxLength: _maxPasswordLength,
              inputFormatters: [
                LengthLimitingTextInputFormatter(_maxPasswordLength),
              ],
              decoration: InputDecoration(
                labelText: isAdminLogin ? '管理者パスワード' : 'パスワード',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isAdminLogin
                  ? (_adminLoading ? null : _adminLogin)
                  : (_authLoading ? null : _startOrRegister),
              child: Text(
                isAdminLogin
                    ? (_adminLoading ? '確認中...' : '管理者として開始')
                    : (_authLoading ? '確認中...' : '開始'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '部員の管理',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newMemberNameController,
              maxLength: _maxNameLength,
              inputFormatters: [
                LengthLimitingTextInputFormatter(_maxNameLength),
              ],
              decoration: const InputDecoration(labelText: '追加する部員名'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newMemberPasswordController,
              obscureText: true,
              maxLength: _maxPasswordLength,
              inputFormatters: [
                LengthLimitingTextInputFormatter(_maxPasswordLength),
              ],
              decoration: const InputDecoration(labelText: '初期パスワード'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _adminLoading ? null : _addMemberAsAdmin,
              icon: const Icon(Icons.person_add),
              label: Text(_adminLoading ? '処理中...' : '部員を追加'),
            ),
            const SizedBox(height: 16),
            if (_data.members.isEmpty)
              const Text('部員がまだ登録されていません。')
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _data.members.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final member = _data.members[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(member.name),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: '上へ',
                          onPressed: index == 0 || _adminLoading
                              ? null
                              : () => _moveMemberAsAdmin(member, -1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: '下へ',
                          onPressed:
                              index == _data.members.length - 1 || _adminLoading
                                  ? null
                                  : () => _moveMemberAsAdmin(member, 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          tooltip: '削除',
                          onPressed: _adminLoading
                              ? null
                              : () => _deleteMemberAsAdmin(member),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlySummaryCard(String selectedMonthLabel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '部員ごとの月別参加回数',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Tooltip(
                  message: '前の月',
                  child: IconButton(
                    onPressed: () => _changeSelectedMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                ),
                Text(selectedMonthLabel),
                Tooltip(
                  message: '次の月',
                  child: IconButton(
                    onPressed: () => _changeSelectedMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ),
                TextButton(
                  onPressed: _jumpToThisMonth,
                  child: const Text('今月'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_data.members.isEmpty)
              const Text('部員がまだ登録されていません。')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('部員')),
                    DataColumn(numeric: true, label: Text('参加')),
                    DataColumn(numeric: true, label: Text('遅刻')),
                    DataColumn(numeric: true, label: Text('不参加')),
                    DataColumn(numeric: true, label: Text('活動日数')),
                  ],
                  rows: _data.members.map((member) {
                    final summary =
                        _data.memberMonthlySummary(member, _selectedMonth);
                    return DataRow(
                      onSelectChanged: (_) => _openMemberMonthDialog(member),
                      cells: [
                        DataCell(Text(member.name)),
                        DataCell(Text('${summary.presentDays}')),
                        DataCell(Text('${summary.lateDays}')),
                        DataCell(Text('${summary.absentDays}')),
                        DataCell(Text('${summary.activeDays}')),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateCard(DaySummary dailySummary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '日付を選ぶ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(DateFormat('y年M月d日').format(_selectedDate)),
                const Spacer(),
                OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDate = picked;
                        _selectedMonth = DateTime(picked.year, picked.month);
                      });
                    }
                  },
                  child: const Text('変更'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '日別集計: 参加 ${dailySummary.presentCount}人 / 不参加 ${dailySummary.absentCount}人',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyRecordCard(AttendanceRecord? currentRecord) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '自分の参加状態を登録',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final status in AttendanceStatus.values)
                  ChoiceChip(
                    label: Text(status.label),
                    selected: currentRecord?.status == status,
                    onSelected: (_) => _saveMyRecord(
                      status,
                      currentRecord?.status == status
                          ? currentRecord?.reason ?? ''
                          : '',
                    ),
                  ),
                TextButton.icon(
                  onPressed: currentRecord == null ? null : _openReasonDialog,
                  icon: const Icon(Icons.edit_note),
                  label: Text(
                    currentRecord?.reason.isEmpty ?? true ? '理由' : '理由を編集',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'その日の状態',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_data.members.isEmpty)
              const Text('部員がまだ登録されていません。')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('部員')),
                    DataColumn(label: Text('状態')),
                    DataColumn(label: Text('理由・メモ')),
                  ],
                  rows: _data.members.map((member) {
                    final record = _recordOf(member);
                    return DataRow(
                      cells: [
                        DataCell(Text(member.name)),
                        DataCell(Text(record?.status.label ?? '未入力')),
                        DataCell(Text(record?.reason ?? '')),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
