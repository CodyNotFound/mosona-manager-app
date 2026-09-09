import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart' show ApiException;
import '../../core/api/api_services.dart' show apiProvider;
import '../../core/models/models.dart';
import '../../core/state/controllers.dart' show serverConfigProvider;
import '../../core/state/session.dart' show mutationBusProvider, teamDataProvider;
import '../../core/theme/mcolors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';

/// Add / edit server full-page form (web 3.4b parity).
///
/// - add: mode selector (0 SSH / 1 active agent / 2 passive agent),
///   SSH host-key confirmation flow, agent install-params result view
/// - edit: load ServerFull, type read-only, PUT with blank-password-keeps
///   semantics and optimistic-lock (ssh_host_key_state_changed) handling.
class ServerFormPage extends ConsumerStatefulWidget {
  const ServerFormPage({super.key, this.editServerId, this.copyFrom});

  final int? editServerId;
  final Map<String, dynamic>? copyFrom;

  @override
  ConsumerState<ServerFormPage> createState() => _ServerFormPageState();
}

class _ServerFormPageState extends ConsumerState<ServerFormPage> {
  final _formKey = GlobalKey<FormState>();

  bool get _isEdit => widget.editServerId != null;

  bool _loading = false;
  bool _submitting = false;
  bool _retriedStateChange = false;
  ServerFull? _info;
  AgentInstallParams? _install;
  String? _hostKey;

  int _mode = 0; // 0 SSH / 1 active / 2 passive (add mode only)
  int _category = 0;
  int _keyId = 0;
  int _cycle = -1;
  int _trafficType = -1;
  bool _allowMonitor = true;
  bool _allowTerminal = true;
  bool _publicVisible = false;
  bool _autoRenew = false;
  DateTime? _start;
  DateTime? _end;

  late final _name = TextEditingController();
  late final _weight = TextEditingController(text: '0');
  late final _provider = TextEditingController();
  late final _amount = TextEditingController();
  late final _bandwidth = TextEditingController();
  late final _traffic = TextEditingController();
  late final _note = TextEditingController();
  late final _notePublic = TextEditingController();
  late final _address = TextEditingController();
  late final _port = TextEditingController(text: '22');
  late final _username = TextEditingController();
  late final _password = TextEditingController();
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loading = _isEdit;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _weight.dispose();
    _provider.dispose();
    _amount.dispose();
    _bandwidth.dispose();
    _traffic.dispose();
    _note.dispose();
    _notePublic.dispose();
    _address.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!ref.read(teamDataProvider).loaded) {
      await ref.read(teamDataProvider.notifier).refresh();
    }
    if (_isEdit) {
      await _load();
    }
  }

  Future<void> _load() async {
    try {
      final info = await ref.read(apiProvider).serverInfo(widget.editServerId!);
      if (!mounted) return;
      setState(() {
        _info = info;
        _name.text = info.name;
        _category = info.category;
        _keyId = info.keyId;
        _allowMonitor = info.allowMonitor;
        _allowTerminal = info.allowTerminal;
        _publicVisible = info.publicVisible;
        _weight.text = '${info.weight}';
        _provider.text = info.provider ?? '';
        _cycle = info.cycle ?? -1;
        _start = info.startTime;
        _end = info.endTime;
        _amount.text = info.amount ?? '';
        _autoRenew = info.autoRenew;
        _bandwidth.text = info.bandwidth ?? '';
        _traffic.text = info.traffic ?? '';
        _trafficType = info.trafficType ?? -1;
        _note.text = info.note ?? '';
        _notePublic.text = info.notePublic ?? '';
        _address.text = info.address;
        _port.text = info.port > 0 ? '${info.port}' : '22';
        _username.text = info.username;
        // password intentionally left blank: blank = keep on the backend
        _startCtrl.text =
            _start == null ? '' : DateFormat('yyyy-MM-dd').format(_start!);
        _endCtrl.text =
            _end == null ? '' : DateFormat('yyyy-MM-dd').format(_end!);
        _loading = false;
        _retriedStateChange = false;
      });
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
      context.pop();
    }
  }

  // ---------------------------------------------------------------- submit

  Map<String, dynamic> _addForm() => {
        'name': _name.text.trim(),
        'mode': _mode,
        'category_id': _category,
        'allow_monitor': _allowMonitor,
        'allow_terminal': _allowTerminal,
        'public_visible': _publicVisible,
        'weight': _weight.text.trim().isEmpty ? '0' : _weight.text.trim(),
        'note': _note.text,
        'provider': _provider.text,
        'cycle': _cycle,
        'start_time': _start?.toUtc().toIso8601String() ?? '',
        'end_time': _end?.toUtc().toIso8601String() ?? '',
        'amount': _amount.text,
        'auto_renew': _autoRenew,
        'bandwidth': _bandwidth.text,
        'traffic': _traffic.text,
        'traffic_type': _trafficType,
        'note_public': _notePublic.text,
        if (_mode == 0) ...{
          'address': _address.text.trim(),
          'port': int.tryParse(_port.text.trim()) ?? 22,
          'username': _username.text,
          'password': _password.text,
          'key_id': _keyId,
          if (_hostKey != null) 'host_key': _hostKey,
        },
      };

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    _retriedStateChange = false;
    try {
      if (_isEdit) {
        await _doEdit();
      } else {
        await _doAdd();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _doAdd() async {
    var env = await ref.read(apiProvider).serverAdd(_addForm());
    if (env.code == 'ssh_host_key_confirmation_required') {
      if (!mounted) return;
      final hk = await _confirmHostKey(env.data);
      if (hk == null) return;
      _hostKey = hk;
      env = await ref.read(apiProvider).serverAdd(_addForm());
    }
    if (!mounted) return;
    if (!env.isOk) {
      showApiError(context, ApiException(env.code, env.msg, data: env.data));
      return;
    }
    ref.read(mutationBusProvider).notifyServersChanged();
    ref.read(teamDataProvider.notifier).refresh();
    if (_mode > 0 && env.data != null) {
      setState(() => _install = AgentInstallParams.fromJson(env.data));
    } else {
      context.pop();
    }
  }

  Future<void> _doEdit() async {
    final info = _info!;
    final m = info.toEditJson()
      ..['name'] = _name.text.trim()
      ..['category'] = _category
      ..['allow_monitor'] = _allowMonitor
      ..['allow_terminal'] = _allowTerminal
      ..['public_visible'] = _publicVisible
      ..['weight'] = int.tryParse(_weight.text.trim()) ?? 0
      ..['note'] = _note.text
      ..['provider'] = _provider.text
      ..['cycle'] = _cycle
      ..['start_time'] = _start?.toUtc().toIso8601String() ?? ''
      ..['end_time'] = _end?.toUtc().toIso8601String() ?? ''
      ..['amount'] = _amount.text
      ..['auto_renew'] = _autoRenew
      ..['bandwidth'] = _bandwidth.text
      ..['traffic'] = _traffic.text
      ..['traffic_type'] = _trafficType
      ..['note_public'] = _notePublic.text
      ..['address'] = _address.text.trim()
      ..['port'] = int.tryParse(_port.text.trim()) ?? 22
      ..['username'] = _username.text
      // blank password = keep existing credential on the backend
      ..['password'] = _password.text
      ..['key_id'] = _keyId;
    if (_hostKey != null) m['host_key'] = _hostKey;

    try {
      await ref.read(apiProvider).serverEdit(info.id, m);
      if (!mounted) return;
      toastSuccess(context);
      ref.read(mutationBusProvider).notifyServersChanged();
      ref.read(teamDataProvider.notifier).refresh();
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ssh_host_key_state_changed') {
        // optimistic lock: re-fetch latest state, then resubmit once.
        toastWarn(context,
            t(context, 'Server changed elsewhere; reloaded latest state.', '服务器已在别处修改，已重新加载最新状态。'));
        await _load();
        if (!mounted) return;
        if (!_retriedStateChange) {
          _retriedStateChange = true;
          return _doEdit();
        }
        return;
      }
      if (e.code == 'ssh_host_key_confirmation_required') {
        final hk = await _confirmHostKey(e.data);
        if (hk != null && mounted) {
          _hostKey = hk;
          return _doEdit();
        }
        return;
      }
      showApiError(context, e);
    }
  }

  /// Host-key fingerprint confirmation; returns the host_key to resend.
  Future<String?> _confirmHostKey(dynamic data) async {
    final m = data is Map ? data : const {};
    final fingerprint = (m['fingerprint'] ?? '').toString();
    final hostKey = (m['host_key'] ?? '').toString();
    final changed = m['changed'] == true;
    final res = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
            changed
                ? t(dialogCtx, 'Host key changed', '主机密钥已变化')
                : t(dialogCtx, 'Unknown host key', '未知主机密钥'),
            style: const TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              changed
                  ? t(dialogCtx,
                      'The server host key changed since the last connection. Verify the fingerprint before trusting it:',
                      '服务器主机密钥与上次连接相比已变化。请核对指纹后再信任：')
                  : t(dialogCtx,
                      'This is the first time connecting to this server. Verify the host key fingerprint:',
                      '首次连接该服务器。请核对主机密钥指纹：'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(dialogCtx).colorScheme.secondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                fingerprint,
                style: monoStyle(dialogCtx, size: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(t(dialogCtx, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(t(dialogCtx, 'Trust & Continue', '信任并继续')),
          ),
        ],
      ),
    );
    return res == true ? hostKey : null;
  }

  // ---------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    final title = _isEdit
        ? t(context, 'Edit Server', '编辑服务器')
        : t(context, 'Add Server', '添加服务器');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _install != null
                ? _installView(context)
                : _formView(context),
      ),
    );
  }

  InputDecoration _dec(
    BuildContext context,
    String label, {
    String? hint,
    String? suffix,
    Widget? suffixIcon,
    String? helper,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        suffixText: suffix,
        suffixIcon: suffixIcon,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _sectionTitle(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(s,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
      );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(label, style: const TextStyle(fontSize: 13)),
        value: value,
        onChanged: onChanged,
      );

  Widget _formView(BuildContext context) {
    final team = ref.watch(teamDataProvider);
    final info = _info;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!_isEdit) ...[
            _sectionTitle(context, t(context, 'Mode', '模式')),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: const Text('SSH')),
                ButtonSegment(
                    value: 1, label: Text(t(context, 'Agent (active)', '主动 Agent'))),
                ButtonSegment(
                    value: 2,
                    label: Text(t(context, 'Agent (passive)', '被动 Agent'))),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ],
          if (_isEdit && info != null) ...[
            _sectionTitle(context, t(context, 'Type', '类型')),
            MCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.dns_outlined,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(serverTypeLabel(info.type),
                      style: const TextStyle(fontSize: 13)),
                  const Spacer(),
                  if (info.agentStatus > 0)
                    MBadge(
                      small: true,
                      color: MColors.online,
                      backgroundColor: MColors.badgeGreen,
                      child: Text(info.agentVersion?.isNotEmpty == true
                          ? 'Agent ${info.agentVersion}'
                          : t(context, 'Agent installed', '已安装 Agent')),
                    ),
                ],
              ),
            ),
          ],
          _sectionTitle(context, t(context, 'Basic', '基础')),
          MCard(
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  decoration:
                      _dec(context, t(context, 'Name', '名称'), hint: 'web-01'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? t(context, 'Required', '必填') : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _category == 0 ||
                          team.categories.any((c) => c.id == _category)
                      ? _category
                      : null,
                  isDense: true,
                  decoration: _dec(context, t(context, 'Category', '分类')),
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(t(context, 'None', '未分组')),
                    ),
                    ...team.categories.map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? 0),
                ),
                _switch(t(context, 'Allow monitor', '允许监控'), _allowMonitor,
                    (v) => setState(() => _allowMonitor = v)),
                _switch(t(context, 'Allow terminal', '允许终端'), _allowTerminal,
                    (v) => setState(() => _allowTerminal = v)),
                _switch(t(context, 'Public visible', '公开展示'), _publicVisible,
                    (v) => setState(() => _publicVisible = v)),
                TextFormField(
                  controller: _weight,
                  keyboardType: TextInputType.number,
                  decoration:
                      _dec(context, t(context, 'Weight', '权重')),
                ),
              ],
            ),
          ),
          if (!_isEdit) ...[
            _sectionTitle(context, t(context, 'Connection', '连接')),
            MCard(
              child: Column(
                children: [
                  if (_mode == 2)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t(context,
                                  'No connection settings needed. After adding, copy the enroll token to the agent.',
                                  '无需连接配置。添加完成后复制注册令牌给 Agent 使用。'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    TextFormField(
                      controller: _address,
                      decoration: _dec(context, t(context, 'Address', '地址'),
                          hint: _mode == 0 ? '192.168.1.10' : 'hub.example.com'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? t(context, 'Required', '必填')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: _dec(context, t(context, 'Port', '端口')),
                      validator: (v) {
                        final p = int.tryParse(v ?? '');
                        if (v != null && v.isNotEmpty && (p == null || p <= 0)) {
                          return t(context, 'Invalid port', '端口无效');
                        }
                        return null;
                      },
                    ),
                    if (_mode == 0) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        decoration:
                            _dec(context, t(context, 'Username', '用户名'), hint: 'root'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? t(context, 'Required', '必填')
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: _dec(context,
                            t(context, 'Password (optional)', '密码（可选）')),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue:
                            _keyId == 0 || team.keys.any((k) => k.id == _keyId)
                                ? _keyId
                                : null,
                        isDense: true,
                        decoration: _dec(context, t(context, 'SSH key', 'SSH 密钥')),
                        items: [
                          DropdownMenuItem(
                            value: 0,
                            child: Text(t(context, 'Password only', '仅密码')),
                          ),
                          ...team.keys.map((k) =>
                              DropdownMenuItem(value: k.id, child: Text(k.name))),
                        ],
                        onChanged: (v) => setState(() => _keyId = v ?? 0),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
          _sectionTitle(context, t(context, 'Billing', '计费')),
          MCard(
            child: Column(
              children: [
                TextFormField(
                  controller: _provider,
                  decoration: _dec(context, t(context, 'Provider', '供应商')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _cycle,
                  isDense: true,
                  decoration: _dec(context, t(context, 'Cycle', '周期')),
                  items: [
                    DropdownMenuItem(
                        value: -1, child: Text(t(context, 'None', '无'))),
                    DropdownMenuItem(
                        value: 0, child: Text(t(context, 'One-time', '一次性'))),
                    DropdownMenuItem(
                        value: 1, child: Text(t(context, 'Monthly', '月付'))),
                    DropdownMenuItem(
                        value: 2, child: Text(t(context, 'Quarterly', '季付'))),
                    DropdownMenuItem(
                        value: 3, child: Text(t(context, 'Semi-annually', '半年付'))),
                    DropdownMenuItem(
                        value: 4, child: Text(t(context, 'Yearly', '年付'))),
                  ],
                  onChanged: (v) => setState(() => _cycle = v ?? -1),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _dateField(context, start: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _dateField(context, start: false)),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _dec(context, t(context, 'Amount', '金额'),
                      helper: '"0" = ${t(context, "Free", "免费")}, "-1" = PAYG'),
                ),
                _switch(t(context, 'Auto renew', '自动续费'), _autoRenew,
                    (v) => setState(() => _autoRenew = v)),
                TextFormField(
                  controller: _bandwidth,
                  decoration: _dec(context, t(context, 'Bandwidth', '带宽'),
                      hint: '500M'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _traffic,
                  decoration: _dec(context, t(context, 'Traffic', '流量'),
                      hint: '2T'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _trafficType,
                  isDense: true,
                  decoration:
                      _dec(context, t(context, 'Traffic type', '流量方向')),
                  items: [
                    DropdownMenuItem(
                        value: -1, child: Text(t(context, 'None', '无'))),
                    DropdownMenuItem(
                        value: 0, child: Text(t(context, 'Inbound', '入'))),
                    DropdownMenuItem(
                        value: 1, child: Text(t(context, 'Outbound', '出'))),
                    DropdownMenuItem(
                        value: 2, child: Text(t(context, 'Both', '双向'))),
                  ],
                  onChanged: (v) => setState(() => _trafficType = v ?? -1),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  maxLines: 2,
                  decoration:
                      _dec(context, t(context, 'Note (private)', '备注（私有）')),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notePublic,
                  maxLines: 2,
                  decoration:
                      _dec(context, t(context, 'Note (public)', '备注（公开）')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: LoadingButton(
              label: _isEdit
                  ? t(context, 'Save', '保存')
                  : t(context, 'Create', '创建'),
              loading: _submitting,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField(BuildContext context, {required bool start}) {
    final value = start ? _start : _end;
    return TextFormField(
      controller: start ? _startCtrl : _endCtrl,
      readOnly: true,
      showCursor: false,
      decoration: _dec(
        context,
        start ? t(context, 'Start date', '开始日期') : t(context, 'End date', '到期日期'),
        suffixIcon: value == null
            ? const Icon(Icons.calendar_today_outlined, size: 16)
            : IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  setState(() {
                    if (start) {
                      _start = null;
                      _startCtrl.text = '';
                    } else {
                      _end = null;
                      _endCtrl.text = '';
                    }
                  });
                },
              ),
      ),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (d == null || !mounted) return;
        setState(() {
          if (start) {
            _start = d;
            _startCtrl.text = DateFormat('yyyy-MM-dd').format(d);
          } else {
            _end = d;
            _endCtrl.text = DateFormat('yyyy-MM-dd').format(d);
          }
        });
      },
    );
  }

  // ---------------------------------------------------------------- install

  Widget _installView(BuildContext context) {
    final p = _install!;
    final base = ref.watch(serverConfigProvider);
    final active = p.agentUid != null || p.publicKey != null;
    final command = 'curl -fsSL $base/install.sh | sh';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: MColors.online, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t(context, 'Server created', '服务器已创建'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                t(context,
                    'Copy the parameters below to install the agent on the target machine.',
                    '请复制以下参数，在目标机器上安装 Agent。'),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (active) ...[
                _copyRow(context, t(context, 'Host', '主机'), p.host ?? ''),
                _copyRow(context, t(context, 'Port', '端口'), '${p.port ?? ''}'),
                _copyRow(context, 'Agent UID', p.agentUid ?? ''),
                _copyRow(context, t(context, 'Public key', '公钥'),
                    p.publicKey ?? '', maxLines: 4),
                _copyRow(context, t(context, 'Install command', '安装命令'), command),
              ] else ...[
                _copyRow(context, 'Hub', p.hub ?? ''),
                _copyRow(context, t(context, 'Enroll token', '注册令牌'),
                    p.enrollToken ?? '', maxLines: 3),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: LoadingButton(
            label: t(context, 'Done', '完成'),
            onPressed: () => context.pop(),
          ),
        ),
      ],
    );
  }

  Widget _copyRow(BuildContext context, String label, String value,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 15),
                  tooltip: t(context, 'Copy', '复制'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (!context.mounted) return;
                    toastSuccess(context, t(context, 'Copied', '已复制'));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              value,
              style: monoStyle(context, size: 11),
              maxLines: maxLines,
            ),
          ),
        ],
      ),
    );
  }
}
