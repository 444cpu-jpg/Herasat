import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sing_box/sing_box.dart';

const _sources = <String>[
  'https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/sub_merge.txt',
  'https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/v2ray.txt',
  'https://raw.githubusercontent.com/peasoft/NoMoreWalls/master/list.txt',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var ready = false;
  String? initError;
  try {
    await SingBox.instance.initialize(const SingBoxOptions(
      logMaxLines: 1500,
      android: SingBoxAndroidOptions(
        notificationTitle: 'Herasat',
        stopActionTitle: 'قطع اتصال',
        showTrafficInNotification: true,
      ),
    ));
    ready = true;
  } catch (e) {
    initError = e.toString();
  }
  runApp(HerasatApp(coreReady: ready, initError: initError));
}

class ProxyNode {
  const ProxyNode(this.link, this.source);
  final String link;
  final String source;

  String get protocol => link.substring(0, link.indexOf('://')).toUpperCase();

  String get name {
    try {
      final uri = Uri.parse(link);
      final fragment = Uri.decodeComponent(uri.fragment);
      if (fragment.isNotEmpty) return fragment;
      return uri.host.isNotEmpty ? uri.host : protocol;
    } catch (_) {
      return protocol;
    }
  }

  String get host {
    try {
      return Uri.parse(link).host;
    } catch (_) {
      return '';
    }
  }
}

List<String> _extractLinks(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return const [];

  const schemes = [
    'vless://', 'vmess://', 'trojan://', 'ss://',
    'hysteria2://', 'hy2://', 'hysteria://', 'tuic://',
    'anytls://', 'wireguard://', 'wg://', 'socks://',
    'socks5://', 'socks4://', 'http://', 'https://',
  ];

  if (!schemes.any(text.contains)) {
    try {
      final normalized = base64.normalize(text.replaceAll(RegExp(r'\s+'), ''));
      text = utf8.decode(base64.decode(normalized), allowMalformed: true);
    } catch (_) {
      // It may already be plain text or an unsupported subscription format.
    }
  }

  final matcher = RegExp(
    r'(?:vless|vmess|trojan|ss|hysteria2|hy2|hysteria|tuic|anytls|wireguard|wg|socks5|socks4|socks|https?)://[^\s"\x27<>]+',
    caseSensitive: false,
  );
  final found = <String>{};
  for (final match in matcher.allMatches(text)) {
    var link = match.group(0)!.trim();
    link = link.replaceAll(RegExp(r'[),;]+$'), '');
    if (link.length > 12) found.add(link);
  }
  return found.toList();
}

class HerasatApp extends StatelessWidget {
  const HerasatApp({super.key, required this.coreReady, this.initError});
  final bool coreReady;
  final String? initError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Herasat',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF55D6BE),
          brightness: Brightness.dark,
          surface: const Color(0xFF151D31),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1020),
        useMaterial3: true,
      ),
      home: HomePage(coreReady: coreReady, initError: initError),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.coreReady, this.initError});
  final bool coreReady;
  final String? initError;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _subscriptionController = TextEditingController();
  final _client = http.Client();
  final _core = SingBox.instance;
  final List<ProxyNode> _nodes = [];
  StreamSubscription<SingBoxConnectionStatus>? _statusSubscription;
  StreamSubscription<SingBoxConnectionStats>? _statsSubscription;

  SingBoxConnectionStatus _status = SingBoxConnectionStatus.disconnected;
  SingBoxConnectionStats? _stats;
  String? _selectedLink;
  String? _message;
  bool _busy = false;
  bool _loadingSources = false;
  bool _english = false;

  bool get _active => _status == SingBoxConnectionStatus.connected ||
      _status == SingBoxConnectionStatus.connecting;

  @override
  void initState() {
    super.initState();
    if (widget.coreReady) {
      _status = _core.status;
      _statusSubscription = _core.watchConnectionStatus().listen((value) {
        if (mounted) setState(() => _status = value);
      });
      _statsSubscription = _core.watchConnectionStats().listen((value) {
        if (mounted) setState(() => _stats = value);
      });
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _statsSubscription?.cancel();
    _subscriptionController.dispose();
    _client.close();
    super.dispose();
  }

  String t(String fa, String en) => _english ? en : fa;

  void _notify(String message) {
    if (!mounted) return;
    setState(() => _message = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshSources() async {
    if (_loadingSources) return;
    setState(() {
      _loadingSources = true;
      _message = null;
    });
    var added = 0;
    var failed = 0;
    for (final source in _sources) {
      try {
        final response = await _client
            .get(Uri.parse(source), headers: {'User-Agent': 'Herasat-Android/0.2'})
            .timeout(const Duration(seconds: 18));
        if (response.statusCode != 200) {
          failed++;
          continue;
        }
        final links = _extractLinks(response.body);
        for (final link in links) {
          if (!_nodes.any((node) => node.link == link)) {
            _nodes.add(ProxyNode(link, Uri.parse(source).host));
            added++;
          }
        }
      } catch (_) {
        failed++;
      }
      if (mounted) setState(() {});
    }
    if (mounted) {
      setState(() => _loadingSources = false);
      _notify(t('$added سرور جدید اضافه شد؛ خطای منبع: $failed',
          '$added new servers added; source errors: $failed'));
    }
  }

  Future<void> _addSubscription() async {
    final input = _subscriptionController.text.trim();
    if (input.isEmpty) return;
    setState(() => _busy = true);
    try {
      String body = input;
      final uri = Uri.tryParse(input);
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        final response = await _client.get(uri).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        body = response.body;
      }
      final links = _extractLinks(body);
      var added = 0;
      for (final link in links) {
        if (!_nodes.any((node) => node.link == link)) {
          _nodes.add(ProxyNode(link, t('اشتراک شخصی', 'Custom subscription')));
          added++;
        }
      }
      _subscriptionController.clear();
      if (mounted) setState(() {});
      _notify(t('$added سرور از ورودی اضافه شد', '$added servers imported'));
    } catch (e) {
      _notify(t('خطا در دریافت اشتراک: $e', 'Subscription error: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(ProxyNode node) async {
    if (!widget.coreReady || _busy) return;
    setState(() {
      _busy = true;
      _selectedLink = node.link;
    });
    try {
      await _core.connect(node.link);
      _notify(t('اتصال برقرار شد', 'Connected'));
    } catch (e) {
      _notify(t('اتصال ناموفق: $e', 'Connection failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _core.disconnect();
      _notify(t('اتصال قطع شد', 'Disconnected'));
    } catch (e) {
      _notify(t('خطا در قطع اتصال: $e', 'Disconnect error: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel() {
    switch (_status) {
      case SingBoxConnectionStatus.connected:
        return t('متصل', 'Connected');
      case SingBoxConnectionStatus.connecting:
        return t('در حال اتصال', 'Connecting');
      case SingBoxConnectionStatus.disconnecting:
        return t('در حال قطع اتصال', 'Disconnecting');
      case SingBoxConnectionStatus.disconnected:
        return t('قطع', 'Disconnected');
    }
  }

  String _speed(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B/s';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Directionality(
      textDirection: _english ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('HERASAT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
          actions: [
            TextButton(
              onPressed: () => setState(() => _english = !_english),
              child: Text(_english ? 'فارسی' : 'EN'),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            children: [
              Center(
                child: Column(
                  children: [
                    Text(t('اتصال امن، با انتخاب شما', 'Secure connection, your choice'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 18),
                    Container(
                      width: 148,
                      height: 148,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent.withValues(alpha: .65), width: 3),
                        color: const Color(0xFF151D31),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_status == SingBoxConnectionStatus.connected ? Icons.shield : Icons.shield_outlined,
                              color: accent, size: 42),
                          const SizedBox(height: 8),
                          Text(_statusLabel(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_stats != null && _status == SingBoxConnectionStatus.connected)
                      Text('↓ ${_speed(_stats!.downloadSpeed)}     ↑ ${_speed(_stats!.uploadSpeed)}',
                          style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: !widget.coreReady || _busy ? null : (_active ? _disconnect : null),
                        icon: Icon(_active ? Icons.power_settings_new : Icons.lock),
                        label: Text(_active
                            ? t('قطع اتصال', 'Disconnect')
                            : t('برای اتصال یک سرور انتخاب کنید', 'Choose a server below to connect')),
                        style: FilledButton.styleFrom(
                          backgroundColor: _active ? Colors.redAccent : accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                    if (_busy) const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (!widget.coreReady)
                Card(
                  color: Colors.red.withValues(alpha: .12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(t('هسته VPN راه‌اندازی نشد: ${widget.initError ?? "خطای نامشخص"}',
                        'VPN core failed to initialize: ${widget.initError ?? "Unknown error"}')),
                  ),
                ),
              Text(t('دریافت خودکار سرورها', 'Discover public servers'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loadingSources ? null : _refreshSources,
                icon: _loadingSources
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_download_outlined),
                label: Text(_loadingSources
                    ? t('در حال دریافت و بررسی منابع…', 'Fetching and parsing sources…')
                    : t('جست‌وجوی سرورهای رایگان', 'Fetch free servers')),
              ),
              const SizedBox(height: 18),
              Text(t('افزودن لینک یا اشتراک', 'Add a link or subscription'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _subscriptionController,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: t('لینک اشتراک یا vless:// و vmess:// را وارد کنید',
                      'Paste a subscription URL or vless:// / vmess:// link'),
                  filled: true,
                  fillColor: const Color(0xFF151D31),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _addSubscription,
                icon: const Icon(Icons.add_link),
                label: Text(t('افزودن سرورها', 'Import servers')),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(t('فهرست سرورها', 'Server list'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  Text('${_nodes.length}', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              if (_nodes.isEmpty)
                Card(
                  color: const Color(0xFF151D31),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(t('هنوز سروری اضافه نشده است. دریافت خودکار را بزنید.',
                        'No servers yet. Tap Fetch free servers.')),
                  ),
                )
              else
                ..._nodes.map((node) {
                  final selected = _selectedLink == node.link;
                  return Card(
                    color: selected ? const Color(0xFF1C3440) : const Color(0xFF151D31),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: accent.withValues(alpha: .15),
                        child: Icon(Icons.dns_outlined, color: accent),
                      ),
                      title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${node.protocol} • ${node.host}\n${node.source}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: t('اتصال به این سرور', 'Connect to this server'),
                        onPressed: _busy || !widget.coreReady ? null : () => _connect(node),
                        icon: const Icon(Icons.play_circle_fill),
                        color: accent,
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 14),
              Text(
                t('هشدار امنیتی: سرورهای عمومی ناشناس و غیرقابل اعتمادند. برای حساب‌های بانکی، اطلاعات حساس یا ورودهای مهم از آن‌ها استفاده نکنید. اتصال فقط با لمس دکمه کنار سرور آغاز می‌شود.',
                    'Security: public community servers are untrusted. Do not use them for banking, sensitive data, or important logins. A tunnel starts only when you tap a server Connect button.'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orangeAccent),
              ),
              const SizedBox(height: 6),
              Text('Herasat 0.2.0 • sing-box core',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}
