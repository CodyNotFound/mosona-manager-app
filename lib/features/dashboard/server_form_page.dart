import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart' show ApiException;
import '../../core/api/api_services.dart' show apiProvider;
import '../../core/models/models.dart';
import '../../core/sse/sse_client.dart' show monitorProvider;
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

  int _mode = 0; // 0 SSH / 1 active / 2 passive (add mode only)
  int _category = 0;
  int _keyId = 0;
  int _cycle = -1;
  int _trafficType = -1;
  bool _allowMonitor = true;
  bool _allowTerminal = true;
  bool _publicVisible = true; // web add.tsx:484 defaultChecked
  bool _autoRenew = true; // web add.tsx:638 defaultChecked
  DateTime? _start;
  DateTime? _end;

  // Install-command generator state (web agent-install.tsx:55-58).
  String _instOs = 'linux';
  String _instArch = 'amd64';
  String _instIp = 'none'; // none | ipv4 | ipv6 (passive only)
  bool _instSudo = true;
  bool _installAllowMonitor = true;
  bool _installAllowTerminal = true;
  AgentInstallParams? _install;
  String? _hostKey;

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
  late final _username = TextEditingController(text: 'root');
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
      return;
    }
    // web add.tsx:88-92 — category defaults to the first category.
    if (!mounted) return;
    final cats = [...ref.read(teamDataProvider).categories]
      ..sort((a, b) => a.sort.compareTo(b.sort));
    if (cats.isNotEmpty) {
      setState(() => _category = cats.first.id);
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
        _username.text = info.username.isEmpty ? 'root' : info.username;
        // password intentionally left blank: blank = keep on the backend
        _startCtrl.text =
            _start == null ? '' : DateFormat('yyyy-MM-dd').format(_start!);
        _endCtrl.text =
            _end == null ? '' : DateFormat('yyyy-MM-dd').format(_end!);
        _loading = false;
        // note: _retriedStateChange stays as-is — a reload must not re-arm
        // the one-shot optimistic-lock retry, or a persistent conflict loops
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
        // web add.tsx:481-486 — only meaningful while monitoring is enabled.
        'public_visible': _allowMonitor && _publicVisible,
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
    // web hook.ts:365-370 — resubscribe SSE after mutations.
    ref.read(monitorProvider.notifier).subscribe();
    toastSuccess(context, t(context, 'Server added', '服务器添加成功'));
    if (_mode > 0 && env.data != null) {
      setState(() {
        _install = AgentInstallParams.fromJson(env.data);
        _installAllowMonitor = _allowMonitor;
        _installAllowTerminal = _allowTerminal;
        _instOs = _guessAgentOs();
      });
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
      // web edit.tsx:164 — public visibility requires monitoring access.
      ..['public_visible'] = _allowMonitor && _publicVisible
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
      ref.read(monitorProvider.notifier).subscribe();
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

  Widget _sectionTitle(BuildContext context, String s, {Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(s,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
            ),
            ?trailing,
          ],
        ),
      );

  Widget _helpIcon(BuildContext context, VoidCallback onTap) => IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: Icon(Icons.help_outline,
            size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
        tooltip: t(context, 'Help', '帮助'),
        onPressed: onTap,
      );

  /// web help/agent-mode.tsx — active vs passive explanation.
  Future<void> _showAgentModeHelp() {
    return showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(t(dlgCtx, 'About agent modes', 'Agent 模式介绍'),
            style: const TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(dlgCtx, 'Active mode', '主动模式'),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              t(dlgCtx,
                  'The hub actively connects to the agent. Suited for servers with a public IP, or on the same LAN as the hub.',
                  'Hub 会主动连接 Agent。适用于有公网 IP，或与 Mosona Manager Hub 处于同一局域网的服务器。'),
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Text(t(dlgCtx, 'Passive mode', '被动模式'),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              t(dlgCtx,
                  'The agent connects to the hub on its own. Suited for devices behind NAT or firewalls; no inbound port needed.',
                  'Agent 会主动连接 Hub。适合位于 NAT 或防火墙后的设备，无需开放入站端口。'),
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(),
            child: Text(t(dlgCtx, 'Close', '关闭')),
          ),
        ],
      ),
    );
  }

  /// web help/auto-renew.tsx — what auto renew does and when it applies.
  Future<void> _showAutoRenewHelp() {
    return showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(t(dlgCtx, 'About auto renew', '自动续费介绍'),
            style: const TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(dlgCtx, 'Effect', '效果'),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              t(dlgCtx,
                  'When the end time is reached, the hub automatically extends it to the end of the next cycle. Expiry alerts keep working.',
                  '到达结束时间后，Hub 会自动将其延长到下一周期结束。针对此服务器或全局配置的到期告警仍会照常工作。'),
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Text(t(dlgCtx, 'Condition', '条件'),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              t(dlgCtx,
                  'Auto renew only applies when a recurring cycle (not one-time or none) and an end time are configured.',
                  '自动续费仅在配置了有效循环周期（不支持一次性或无）并设置了结束时间时生效。'),
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(),
            child: Text(t(dlgCtx, 'Close', '关闭')),
          ),
        ],
      ),
    );
  }

  /// web add.tsx:280-284 — quick add-category from inside the form.
  Future<void> _quickAddCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(t(dlgCtx, 'New category', '新增分类'),
            style: const TextStyle(fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t(dlgCtx, 'Name', '名称'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onSubmitted: (v) => Navigator.of(dlgCtx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(null),
            child: Text(t(dlgCtx, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dlgCtx).pop(ctrl.text),
            child: Text(t(dlgCtx, 'Create', '创建')),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    try {
      await ref.read(apiProvider).categoryCreate(trimmed);
      await ref.read(teamDataProvider.notifier).refresh();
      if (!mounted) return;
      final created = ref
          .read(teamDataProvider)
          .categories
          .where((c) => c.name == trimmed)
          .firstOrNull;
      setState(() {
        if (created != null) _category = created.id;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

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
    // Connection-section shape (web add.tsx / edit.tsx).
    final editType = _isEdit ? info?.type : null;
    final listenMode = !_isEdit && _mode == 1;
    final showConn = _isEdit
        ? (editType == 0 || editType == 1)
        : _mode != 2;
    final connLocked = _isEdit && editType == 1; // web edit.tsx:266,281
    final showAuth = _isEdit ? editType == 0 : _mode == 0;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!_isEdit) ...[
            _sectionTitle(
              context,
              t(context, 'Mode', '模式'),
              trailing: _mode > 0
                  ? _helpIcon(context, _showAgentModeHelp)
                  : null,
            ),
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
              onSelectionChanged: (s) => setState(() {
                _mode = s.first;
                // web add.tsx:449 — active agent listens on 52819 by default.
                if (_mode == 1 && (int.tryParse(_port.text) ?? 22) == 22) {
                  _port.text = '52819';
                }
              }),
            ),
            if (_mode == 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 15,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t(context,
                            'No connection settings needed. The install command will be generated after the server is added.',
                            '无需连接配置。添加服务器后将生成安装命令。'),
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (_isEdit && info != null) ...[
            _sectionTitle(context, t(context, 'Type', '类型')),
            MCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dns_outlined,
                          size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(serverTypeLabel(info.type),
                          style: const TextStyle(fontSize: 13)),
                      const Spacer(),
                      if (info.type != 0)
                        _helpIcon(context, _showAgentModeHelp),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    switch (info.type) {
                      1 => t(context,
                          'The hub actively connects to the agent.',
                          'Hub 会主动连接 Agent。'),
                      2 => t(context,
                          'The agent passively connects to the hub.',
                          'Agent 会主动连接 Hub。'),
                      _ => t(context,
                          'Connect to the server via SSH protocol.',
                          '通过 SSH 协议连接服务器。'),
                    },
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (info.type == 1) ...[
              const SizedBox(height: 12),
              // web edit.tsx:368-377 — read-only agent UUID.
              TextFormField(
                initialValue: info.agentUuid,
                enabled: false,
                decoration: _dec(context, 'UUID',
                    hint: t(context, 'Not initialized', '未初始化')),
              ),
            ],
            if (info.type != 0) ...[
              const SizedBox(height: 12),
              // web edit.tsx:378-429 — agent status + reinstall entry.
              MCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      info.agentStatus == 0
                          ? Icons.remove_circle_outline
                          : Icons.verified_outlined,
                      size: 20,
                      color: info.agentStatus == 0
                          ? MColors.warning
                          : MColors.online,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.agentStatus == 0
                                ? t(context, 'Not installed', '未安装')
                                : t(context, 'Installed', '已安装'),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          if (info.agentStatus != 0 &&
                              (info.agentVersion?.isNotEmpty ?? false))
                            Text('v${info.agentVersion}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _openReinstall,
                      child: Text(t(context, 'Reinstall', '重新安装')),
                    ),
                  ],
                ),
              ),
            ],
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
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
                    ),
                    const SizedBox(width: 6),
                    // web add.tsx:280-284 — inline add-category entry.
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: t(context, 'New category', '新增分类'),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: _quickAddCategory,
                      ),
                    ),
                  ],
                ),
                // web add.tsx:470-497 — monitor / terminal are mutually
                // exclusive: at least one stays enabled.
                _switch(t(context, 'Allow monitor', '允许监控'), _allowMonitor,
                    (v) => setState(() {
                          _allowMonitor = v;
                          if (!v) _allowTerminal = true;
                        })),
                _switch(t(context, 'Allow terminal', '允许终端'), _allowTerminal,
                    (v) => setState(() {
                          _allowTerminal = v;
                          if (!v) _allowMonitor = true;
                        })),
                if (_allowMonitor)
                  _switch(
                      t(context, 'Public visible', '公开展示'), _publicVisible,
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
          // Connection — add: per selected mode; edit: address/port for SSH
          // and active-agent types, auth only for SSH (web edit.tsx:257-367).
          if (showConn) ...[
            _sectionTitle(context, t(context, 'Connection', '连接')),
            MCard(
              child: Column(
                children: [
                  TextFormField(
                    controller: _address,
                    enabled: !connLocked,
                    decoration: _dec(
                      context,
                      t(context, listenMode ? 'Listen address' : 'Address',
                          listenMode ? '监听 IP / 主机名' : 'IP / 主机名'),
                      hint: '1.2.3.4',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? t(context, 'Required', '必填')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _port,
                    enabled: !connLocked,
                    keyboardType: TextInputType.number,
                    decoration: _dec(context, t(context, 'Port', '端口')),
                    validator: (v) {
                      final p = int.tryParse(v ?? '');
                      if (p == null || p < 1 || p > 65535) {
                        // web add.tsx:313-327 — min 1 / max 65535.
                        return t(context,
                            'Port must be between 1 and 65535',
                            '端口须在 1-65535 之间');
                      }
                      return null;
                    },
                  ),
                  if (listenMode) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 15,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t(context,
                                'The install command will be generated after the server is added.',
                                '添加服务器后将生成安装命令。'),
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (showAuth) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _username,
                      decoration: _dec(
                          context, t(context, 'Username', '用户名'), hint: 'root'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? t(context, 'Required', '必填')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      // web edit.tsx:298-307 — switching to a password clears
                      // the selected key.
                      onChanged: (v) {
                        if (v.isNotEmpty && _keyId != 0) {
                          setState(() => _keyId = 0);
                        }
                      },
                      decoration: _dec(
                        context,
                        t(context, 'Password', '密码'),
                        hint: _isEdit
                            ? t(context,
                                'Leave blank to keep the current password',
                                '留空则不修改当前密码')
                            : t(context, 'Optional', '可选'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _keyId == 0 ||
                                    team.keys.any((k) => k.id == _keyId)
                                ? _keyId
                                : null,
                            isDense: true,
                            decoration: _dec(
                                context, t(context, 'SSH key', 'SSH 密钥')),
                            items: [
                              DropdownMenuItem(
                                value: 0,
                                child: Text(t(context, 'None', '无')),
                              ),
                              ...team.keys.map((k) =>
                                  DropdownMenuItem(value: k.id, child: Text(k.name))),
                            ],
                            onChanged: (v) => setState(() {
                              _keyId = v ?? 0;
                              // Selecting a key clears the password.
                              if (_keyId != 0) _password.clear();
                            }),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // web add.tsx:391-398 — inline add-key entry.
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: t(context, 'Manage keys', '管理密钥'),
                            icon: const Icon(Icons.key_outlined, size: 20),
                            onPressed: () async {
                              await context.push('/keychain');
                              if (mounted) {
                                await ref
                                    .read(teamDataProvider.notifier)
                                    .refresh();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
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
                  inputFormatters: [LengthLimitingTextInputFormatter(255)],
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
                // web add.tsx:603-624 — Free / PAYG quick buttons.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(t(context, 'Free', '免费'),
                          style: const TextStyle(fontSize: 11)),
                      onPressed: () => setState(() => _amount.text = '0'),
                    ),
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('PAYG',
                          style: TextStyle(fontSize: 11)),
                      onPressed: () => setState(() => _amount.text = '-1'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [LengthLimitingTextInputFormatter(255)],
                  decoration: _dec(context, t(context, 'Amount', '金额'),
                      helper: '"0" = ${t(context, "Free", "免费")}, "-1" = PAYG'),
                ),
                // web add.tsx:633-639 + help/auto-renew.tsx — auto renew
                // defaults to on with a help dialog.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(t(context, 'Auto renew', '自动续费'),
                            style: const TextStyle(fontSize: 13)),
                      ),
                      _helpIcon(context, _showAutoRenewHelp),
                      SizedBox(
                        width: 40,
                        height: 24,
                        child: Switch(
                          value: _autoRenew,
                          onChanged: (v) => setState(() => _autoRenew = v),
                        ),
                      ),
                    ],
                  ),
                ),
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
                  inputFormatters: [LengthLimitingTextInputFormatter(255)],
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
            // web add.tsx:42-47,110-119 — infer end date from the cycle.
            final months = switch (_cycle) {
              1 => 1,
              2 => 3,
              3 => 6,
              4 => 12,
              _ => 0,
            };
            if (months > 0) {
              _end = DateTime(d.year, d.month + months, d.day);
              _endCtrl.text = DateFormat('yyyy-MM-dd').format(_end!);
            }
          } else {
            _end = d;
            _endCtrl.text = DateFormat('yyyy-MM-dd').format(d);
          }
        });
      },
    );
  }

  // ---------------------------------------------------------------- install

  /// Reinstall Agent (web reinstall.tsx): address/port for active mode,
  /// monitor/terminal switches, POST /server/:id/reinstall and success
  /// falls through to the install-command view. Backend error codes
  /// invalid_mode / invalid_agent_address / invalid_server_type /
  /// mode_mismatch surface via showApiError.
  Future<void> _openReinstall() async {
    final info = _info;
    if (info == null || info.type == 0) return;
    final active = info.type == 1;
    final addrCtrl = TextEditingController(text: info.address);
    final portCtrl = TextEditingController(
        text: info.port > 0 ? '${info.port}' : (active ? '52819' : ''));
    var mon = _allowMonitor;
    var term = _allowTerminal;
    var busy = false;

    await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setD) => AlertDialog(
          title: Text(t(dlgCtx, 'Reinstall Agent', '重新安装 Agent'),
              style: const TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(dlgCtx,
                    'This marks the agent as not installed, revokes the existing key and generates a new key for reinstallation.',
                    '此操作会将 Agent 标记为未安装，撤销现有密钥，并生成新的密钥用于重新安装。'),
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              if (active) ...[
                TextField(
                  controller: addrCtrl,
                  decoration: _dec(dlgCtx,
                      t(dlgCtx, 'Listen address', '监听 IP / 主机名')),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: portCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _dec(dlgCtx, t(dlgCtx, 'Port', '端口')),
                ),
                const SizedBox(height: 4),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(t(dlgCtx, 'Monitor access', '监控权限'),
                    style: const TextStyle(fontSize: 13)),
                value: mon,
                onChanged: (v) => setD(() {
                  mon = v;
                  if (!v) term = true;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(t(dlgCtx, 'Terminal access', '终端权限'),
                    style: const TextStyle(fontSize: 13)),
                value: term,
                onChanged: (v) => setD(() {
                  term = v;
                  if (!v) mon = true;
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(dlgCtx).pop(false),
              child: Text(t(dlgCtx, 'Cancel', '取消')),
            ),
            LoadingButton(
              label: t(dlgCtx, 'Confirm reinstall', '确认重新安装'),
              loading: busy,
              onPressed: busy
                  ? null
                  : () async {
                      final addr = addrCtrl.text.trim();
                      final port = int.tryParse(portCtrl.text.trim()) ?? 0;
                      // web reinstall.tsx:70-76 — active requires both.
                      if (active && (addr.isEmpty || port <= 0)) {
                        toastWarn(
                            context,
                            '${t(context, 'Missing required fields', '未填写')}\n'
                            '${t(context, 'Active mode needs both a listen address and a port.', '主动模式下请同时提供监听 IP / 主机名和端口。')}');
                        return;
                      }
                      setD(() => busy = true);
                      try {
                        final env = await ref.read(apiProvider).serverReinstall(
                              info.id,
                              mode: info.type,
                              address: active ? addr : null,
                              port: active ? port : null,
                            );
                        if (!mounted) return;
                        if (!env.isOk) {
                          showApiError(context,
                              ApiException(env.code, env.msg, data: env.data));
                          if (dlgCtx.mounted) setD(() => busy = false);
                          return;
                        }
                        setState(() {
                          _install = AgentInstallParams.fromJson(env.data);
                          _installAllowMonitor = mon;
                          _installAllowTerminal = term;
                          _instOs = _guessAgentOs();
                        });
                        toastSuccess(
                            context,
                            t(context, 'Reinstall started',
                                '已成功发起 Agent 重新安装。'));
                        if (dlgCtx.mounted) Navigator.of(dlgCtx).pop(true);
                      } catch (e) {
                        if (mounted) showApiError(context, e);
                        if (dlgCtx.mounted) setD(() => busy = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// Best-effort OS detection from the live monitor snapshot (reinstall
  /// flow only; a freshly added server is not in the snapshot yet).
  String _guessAgentOs() {
    final id = _info?.id;
    final snap = ref.read(monitorProvider);
    if (id != null && snap != null) {
      for (final s in snap.servers) {
        if (s.id != id) continue;
        final os = (s.os ?? '').toLowerCase();
        if (os.contains('windows')) return 'windows';
        if (os.contains('darwin') || os.contains('mac os') || os.contains('macos')) {
          return 'darwin';
        }
        break;
      }
    }
    return 'linux';
  }

  /// Install command assembly — web agent-install.tsx:55-84.
  String _buildInstallCommand() {
    final p = _install!;
    final active = p.agentUid != null || p.publicKey != null;
    final os = _instOs;
    final binary = 'agent${os == 'windows' ? '.exe' : ''}';
    final download =
        'https://github.com/mosona-labs/mosona-manager/releases/latest/download/agent_${os}_$_instArch${os == 'windows' ? '.exe' : ''}';
    final useSudo = _instSudo ? 'sudo ' : '';
    final parts = <String>[
      os == 'windows'
          ? 'curl -L -o $binary $download && ./$binary install'
          : 'curl -L -o $binary $download && ${useSudo}chmod +x ./$binary && $useSudo./$binary install',
      active ? 'active' : 'passive',
    ];
    if (!_installAllowMonitor) parts.add('--no-monitor');
    if (!_installAllowTerminal) parts.add('--no-terminal');
    parts.add(active
        ? '${p.agentUid} ${p.publicKey} ${p.host} ${p.port}'
        : '"${p.hub}" "${p.enrollToken}"');
    if (!active && _instIp != 'none') parts.add('--$_instIp');
    return parts.join(' ');
  }

  Future<void> _copyCommand() async {
    await Clipboard.setData(ClipboardData(text: _buildInstallCommand()));
    if (!mounted) return;
    toastSuccess(
        context,
        t(context, 'Install command copied to clipboard',
            '安装命令已复制到剪贴板。'));
  }

  Widget _installView(BuildContext context) {
    final p = _install!;
    final active = p.agentUid != null || p.publicKey != null;
    final modeLabel =
        active ? t(context, 'active', '主动') : t(context, 'passive', '被动');
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
                    'Run the command below on the server to install the agent.',
                    '请在服务器上运行以下命令以安装 Agent。'),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Install command generator (web agent-install.tsx:94-176).
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${t(context, 'Install Agent', '安装 Agent')} · $modeLabel',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _instOs,
                      isDense: true,
                      decoration: _dec(context, 'OS'),
                      items: const [
                        DropdownMenuItem(value: 'linux', child: Text('Linux')),
                        DropdownMenuItem(value: 'darwin', child: Text('Darwin')),
                        DropdownMenuItem(
                            value: 'windows', child: Text('Windows')),
                      ],
                      onChanged: (v) => setState(() => _instOs = v ?? 'linux'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _instArch,
                      isDense: true,
                      decoration: _dec(context, 'Arch'),
                      items: const [
                        DropdownMenuItem(value: 'amd64', child: Text('amd64')),
                        DropdownMenuItem(value: 'arm64', child: Text('arm64')),
                      ],
                      onChanged: (v) => setState(() => _instArch = v ?? 'amd64'),
                    ),
                  ),
                ],
              ),
              if (!active) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _instIp,
                  isDense: true,
                  decoration: _dec(context, t(context, 'IP version', 'IP 版本')),
                  items: [
                    DropdownMenuItem(
                        value: 'none',
                        child: Text(t(context, 'No preference', '无偏好'))),
                    DropdownMenuItem(
                        value: 'ipv4',
                        child: Text(t(context, 'Use IPv4', '使用 IPv4'))),
                    DropdownMenuItem(
                        value: 'ipv6',
                        child: Text(t(context, 'Use IPv6', '使用 IPv6'))),
                  ],
                  onChanged: (v) => setState(() => _instIp = v ?? 'none'),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(t(context, 'Use sudo', '使用 sudo'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  SizedBox(
                    width: 40,
                    height: 24,
                    child: Switch(
                      value: _instSudo,
                      onChanged: (v) => setState(() => _instSudo = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _buildInstallCommand(),
                  style: monoStyle(context, size: 11),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _copyCommand,
                  icon: const Icon(Icons.copy, size: 15),
                  label: Text(t(context, 'Copy install command', '复制安装命令')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (active) ...[
                _copyRow(context, t(context, 'Host', '主机'), p.host ?? ''),
                _copyRow(context, t(context, 'Port', '端口'), '${p.port ?? ''}'),
                _copyRow(context, 'Agent UID', p.agentUid ?? ''),
                _copyRow(context, t(context, 'Public key', '公钥'),
                    p.publicKey ?? '', maxLines: 4),
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
