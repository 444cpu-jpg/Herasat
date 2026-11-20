import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sing_box/sing_box.dart';

const _sources = <String>[
  'https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/sub_merge.txt',
  'https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/v2ray.txt',
  'https://raw.githubusercontent.com/peasoft/NoMoreWalls/master/list.txt',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0B1020),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

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

enum NodeTestState { unknown, testing, reachable, failed, unsupported }

class ProxyNode {
  ProxyNode(this.link, this.source);
  final String link;
  final String source;
  NodeTestState testState = NodeTestState.unknown;
  num? latencyMs;
  String? testMessage;

  String get protocol {
    final idx = link.indexOf('://');
    if (idx <= 0) return 'UNKNOWN';
    return link.substring(0, idx).toUpperCase();
  }

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
    } catch (_) {}
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

Color _protocolColor(String protocol) {
  switch (protocol.toUpperCase()) {
    case 'VLESS':
      return const Color(0xFF55D6BE);
    case 'VMESS':
      return const Color(0xFF6C9BFF);
    case 'TROJAN':
      return const Color(0xFFFF8A65);
    case 'SS':
    case 'SHADOWSOCKS':
      return const Color(0xFFFFD54F);
    case 'HYSTERIA':
    case 'HYSTERIA2':
    case 'HY2':
      return const Color(0xFFCE93D8);
    case 'TUIC':
      return const Color(0xFF80CBC4);
    case 'WIREGUARD':
    case 'WG':
      return const Color(0xFF90CAF9);
    default:
      return const Color(0xFF90A4AE);
  }
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
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B1020),
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF151D31),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF151D31),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF55D6BE), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
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

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _subscriptionController = TextEditingController();
  final _searchController = TextEditingController();
  final _client = http.Client();
  final _core = SingBox.instance;
  final List<ProxyNode> _nodes = [];
  StreamSubscription<SingBoxConnectionStatus>? _statusSubscription;
  StreamSubscription<SingBoxConnectionStats>? _statsSubscription;
  StreamSubscription<dynamic>? _stateSubscription;

  SingBoxConnectionStatus _status = SingBoxConnectionStatus.disconnected;
  SingBoxConnectionStats? _stats;
  String? _selectedLink;
  bool _busy = false;
  bool _loadingSources = false;
  bool _testingServers = false;
  bool _english = false;
  String? _lastConnectionError;
  String _searchQuery = '';

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool get _active =>
      _status == SingBoxConnectionStatus.connected ||
      _status == SingBoxConnectionStatus.connecting;

  List<ProxyNode> get _filteredNodes {
    if (_searchQuery.trim().isEmpty) return _nodes;
    final q = _searchQuery.toLowerCase();
    return _nodes.where((n) {
      return n.name.toLowerCase().contains(q) ||
          n.host.toLowerCase().contains(q) ||
          n.protocol.toLowerCase().contains(q) ||
          n.source.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.coreReady) {
      _status = _core.status;
      _statusSubscription = _core.watchConnectionStatus().listen((value) {
        if (mounted) {
          setState(() => _status = value);
          _updatePulse();
        }
      });
      _statsSubscription = _core.watchConnectionStats().listen((value) {
        if (mounted) setState(() => _stats = value);
      });
      _stateSubscription = _core.watchConnectionState().listen((value) {
        if (!mounted) return;
        setState(() => _lastConnectionError = value.error?.toString());
      });
      _restoreSavedServers();
      _updatePulse();
    }
  }

  void _updatePulse() {
    if (_status == SingBoxConnectionStatus.connected ||
        _status == SingBoxConnectionStatus.connecting) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statusSubscription?.cancel();
    _statsSubscription?.cancel();
    _stateSubscription?.cancel();
    _subscriptionController.dispose();
    _searchController.dispose();
    _client.close();
    super.dispose();
  }

  String t(String fa, String en) => _english ? en : fa;

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  Future<void> _refreshSources() async {
    if (_loadingSources) return;
    setState(() => _loadingSources = true);
    var added = 0;
    var failed = 0;
    for (final source in _sources) {
      try {
        final response = await _client
            .get(Uri.parse(source), headers: {'User-Agent': 'Herasat-Android/0.3'})
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
    if (widget.coreReady && _nodes.isNotEmpty) {
      try {
        await _syncSavedServers();
      } catch (_) {
        failed++;
      }
    }
    if (mounted) {
      setState(() => _loadingSources = false);
      _notify(t(
        '$added سرور جدید اضافه شد؛ خطای منبع: $failed',
        '$added new servers added; source errors: $failed',
      ));
    }
    if (widget.coreReady && _nodes.isNotEmpty) await _testServers();
  }

  Future<void> _restoreSavedServers() async {
    try {
      final saved = await _core.getServerConfigs();
      if (!mounted || _nodes.isNotEmpty) return;
      for (final profile in saved) {
        final outbound = profile.outbound;
        if (outbound == null) continue;
        final link = SingBoxShareLink.toLink(outbound);
        if (!_nodes.any((n) => n.link == link)) {
          _nodes.add(ProxyNode(link, t('ذخیره‌شده', 'Saved profile')));
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _syncSavedServers() async {
    if (_nodes.isEmpty) return;
    await _core.importServerConfigs(
      _nodes.map((n) => n.link).join('\n'),
      subscriptionId: 'herasat-discovered',
    );
  }

  bool _requiresTunnelTest(ProxyNode n) {
    final p = n.protocol;
    return p == 'HYSTERIA' ||
        p == 'HYSTERIA2' ||
        p == 'HY2' ||
        p == 'TUIC' ||
        p == 'WIREGUARD' ||
        p == 'WG';
  }

  Future<void> _testServers() async {
    if (!widget.coreReady || _testingServers || _nodes.isEmpty) return;
    setState(() {
      _testingServers = true;
      for (final n in _nodes) {
        n.testState = NodeTestState.testing;
        n.latencyMs = null;
        n.testMessage = null;
      }
    });
    var tested = 0;
    var reachable = 0;
    try {
      final profiles = await _core.importServerConfigs(
        _nodes.map((n) => n.link).join('\n'),
        subscriptionId: 'herasat-discovered',
      );
      final byId = <String, ProxyNode>{};
      final count = profiles.length < _nodes.length ? profiles.length : _nodes.length;
      for (var i = 0; i < count; i++) {
        byId[profiles[i].id] = _nodes[i];
      }
      if (byId.isEmpty) {
        throw StateError(t('هیچ پروفایل معتبری برای آزمایش ساخته نشد', 'No valid profiles to test'));
      }
      for (final n in _nodes) {
        if (_requiresTunnelTest(n)) {
          n.testState = NodeTestState.unsupported;
          n.testMessage = t('پروتکل UDP؛ نیازمند آزمون تونل', 'UDP protocol; tunnel test required');
        }
      }
      final tcp = profiles
          .where((p) => byId[p.id] != null && !_requiresTunnelTest(byId[p.id]!))
          .toList();
      await for (final result in _core.pingServers(tcp, concurrency: 6)) {
        final n = byId[result.serverId];
        if (n == null) continue;
        tested++;
        n.testState = result.success ? NodeTestState.reachable : NodeTestState.failed;
        n.latencyMs = result.success ? result.ping : null;
        n.testMessage = result.success
            ? t('پاسخ TCP دریافت شد', 'TCP response received')
            : (result.errorMessage ?? t('بدون پاسخ', 'No response'));
        if (result.success) reachable++;
        if (mounted) setState(() {});
      }
      _nodes.sort((a, b) {
        int rank(ProxyNode n) {
          switch (n.testState) {
            case NodeTestState.reachable:
              return 0;
            case NodeTestState.unsupported:
              return 1;
            case NodeTestState.testing:
              return 2;
            case NodeTestState.unknown:
              return 3;
            case NodeTestState.failed:
              return 4;
          }
        }
        final r = rank(a).compareTo(rank(b));
        return r != 0
            ? r
            : (a.latencyMs ?? 1 << 30).compareTo(b.latencyMs ?? 1 << 30);
      });
      if (_selectedLink == null) {
        final best = _nodes.where((n) => n.testState == NodeTestState.reachable).toList();
        if (best.isNotEmpty) _selectedLink = best.first.link;
      }
      if (mounted) {
        setState(() {});
        _notify(t(
          'آزمایش پایان یافت: $reachable از $tested سرور پاسخ TCP دادند؛ تضمین اتصال VPN نیست.',
          'Test complete: $reachable of $tested servers answered TCP; this does not guarantee a working VPN tunnel.',
        ));
      }
    } catch (e) {
      for (final n in _nodes) {
        if (n.testState == NodeTestState.testing) {
          n.testState = NodeTestState.failed;
          n.testMessage = e.toString();
        }
      }
      if (mounted) {
        _notify(t('خطا در آزمایش سرورها: $e', 'Server test error: $e'));
      }
    } finally {
      if (mounted) setState(() => _testingServers = false);
    }
  }

  String _nodeTestLabel(ProxyNode n) {
    switch (n.testState) {
      case NodeTestState.unknown:
        return t('آزمایش نشده', 'Not tested');
      case NodeTestState.testing:
        return t('در حال آزمایش…', 'Testing…');
      case NodeTestState.reachable:
        return '${n.latencyMs ?? '—'} ms • ${t('پاسخ TCP', 'TCP reachable')}';
      case NodeTestState.failed:
        return t('بدون پاسخ TCP', 'TCP unreachable');
      case NodeTestState.unsupported:
        return t('نیازمند آزمون هنگام اتصال', 'Requires tunnel test');
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
      if (widget.coreReady) {
        try {
          await _syncSavedServers();
        } catch (_) {}
      }
      if (mounted) setState(() {});
      _notify(t('$added سرور از ورودی اضافه شد', '$added servers imported'));
      if (added > 0 && widget.coreReady) await _testServers();
    } catch (e) {
      _notify(t('خطا در دریافت اشتراک: $e', 'Subscription error: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(ProxyNode node) async {
    if (!widget.coreReady || _busy || _testingServers) return;
    setState(() {
      _busy = true;
      _selectedLink = node.link;
    });
    try {
      await _core.connect(node.link);
      if (_core.status != SingBoxConnectionStatus.connected) {
        throw StateError(t('تونل به وضعیت متصل نرسید', 'Tunnel did not reach connected state'));
      }
      _lastConnectionError = null;
      _notify(t('اتصال برقرار شد', 'Connected'));
    } catch (e) {
      _lastConnectionError = e.toString();
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

  Widget _buildStatusRing(Color accent) {
    final isConnected = _status == SingBoxConnectionStatus.connected;
    final isConnecting = _status == SingBoxConnectionStatus.connecting;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final scale = (isConnected || isConnecting) ? _pulseAnimation.value : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  isConnected ? accent.withOpacity(0.22) : const Color(0xFF151D31),
                  const Color(0xFF0B1020),
                ],
              ),
              border: Border.all(
                color: isConnected
                    ? accent
                    : isConnecting
                        ? accent.withOpacity(0.6)
                        : Colors.white.withOpacity(0.12),
                width: isConnected ? 3.5 : 2.5,
              ),
              boxShadow: isConnected
                  ? [
                      BoxShadow(
                        color: accent.withOpacity(0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isConnected ? Icons.shield : Icons.shield_outlined,
                  color: isConnected ? accent : Colors.white70,
                  size: 44,
                ),
                const SizedBox(height: 10),
                Text(
                  _statusLabel(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isConnected ? accent : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpeedRow(Color accent) {
    if (_stats == null || _status != SingBoxConnectionStatus.connected) {
      return const SizedBox(height: 28);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF151D31),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_downward_rounded, size: 16, color: accent),
          const SizedBox(width: 4),
          Text(
            _speed(_stats!.downloadSpeed),
            style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(width: 16),
          Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.orangeAccent.shade200),
          const SizedBox(width: 4),
          Text(
            _speed(_stats!.uploadSpeed),
            style: TextStyle(
              color: Colors.orangeAccent.shade200,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    bool loading = false,
    bool primary = false,
    Color? color,
  }) {
    final child = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          )
        : Icon(icon, size: 20);

    if (primary) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: child,
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          style: FilledButton.styleFrom(
            backgroundColor: color ?? const Color(0xFF55D6BE),
            foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.white12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: child,
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withOpacity(0.12)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildServerCard(ProxyNode node, Color accent) {
    final selected = _selectedLink == node.link;
    final protoColor = _protocolColor(node.protocol);

    Color statusDot;
    switch (node.testState) {
      case NodeTestState.reachable:
        statusDot = const Color(0xFF69F0AE);
        break;
      case NodeTestState.failed:
        statusDot = Colors.redAccent;
        break;
      case NodeTestState.testing:
        statusDot = Colors.amber;
        break;
      case NodeTestState.unsupported:
        statusDot = Colors.purpleAccent;
        break;
      case NodeTestState.unknown:
        statusDot = Colors.white38;
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1A2E3A) : const Color(0xFF151D31),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? accent.withOpacity(0.55) : Colors.white.withOpacity(0.05),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _selectedLink = node.link),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: protoColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      node.protocol.length > 4
                          ? node.protocol.substring(0, 4)
                          : node.protocol,
                      style: TextStyle(
                        color: protoColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        node.host.isNotEmpty ? node.host : node.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: statusDot,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _nodeTestLabel(node),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.65),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: t('اتصال به این سرور', 'Connect to this server'),
                  onPressed: _busy || !widget.coreReady ? null : () => _connect(node),
                  icon: Icon(
                    Icons.play_circle_filled_rounded,
                    color: accent,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final filtered = _filteredNodes;

    return Directionality(
      textDirection: _english ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'HERASAT',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
              fontSize: 18,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: TextButton(
                onPressed: () => setState(() => _english = !_english),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(
                  _english ? 'فارسی' : 'EN',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            color: accent,
            backgroundColor: const Color(0xFF151D31),
            onRefresh: () async {
              if (!_loadingSources) await _refreshSources();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
              children: [
                Center(
                  child: Column(
                    children: [
                      Text(
                        t('اتصال امن، با انتخاب شما', 'Secure connection, your choice'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.85),
                            ),
                      ),
                      const SizedBox(height: 20),
                      _buildStatusRing(accent),
                      const SizedBox(height: 14),
                      _buildSpeedRow(accent),
                      const SizedBox(height: 18),
                      _buildActionButton(
                        onPressed: !widget.coreReady || _busy || _testingServers
                            ? null
                            : (_active
                                ? _disconnect
                                : (_selectedLink == null
                                    ? null
                                    : () {
                                        final chosen = _nodes
                                            .where((n) => n.link == _selectedLink)
                                            .toList();
                                        if (chosen.isNotEmpty) _connect(chosen.first);
                                      })),
                        icon: _active ? Icons.power_settings_new_rounded : Icons.lock_rounded,
                        label: _active
                            ? t('قطع اتصال', 'Disconnect')
                            : (_selectedLink == null
                                ? t('ابتدا یک سرور انتخاب کنید', 'Select a server first')
                                : t('اتصال به سرور انتخاب‌شده', 'Connect to selected server')),
                        primary: true,
                        color: _active ? Colors.redAccent : accent,
                        loading: _busy,
                      ),
                      if (_lastConnectionError != null && !_active)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _lastConnectionError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                if (!widget.coreReady)
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t(
                              'هسته VPN راه‌اندازی نشد: ${widget.initError ?? "خطای نامشخص"}',
                              'VPN core failed to initialize: ${widget.initError ?? "Unknown error"}',
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  t('دریافت سرورها', 'Discover servers'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        onPressed: _loadingSources ? null : _refreshSources,
                        icon: Icons.cloud_download_outlined,
                        label: _loadingSources
                            ? t('در حال دریافت…', 'Fetching…')
                            : t('سرورهای رایگان', 'Free servers'),
                        loading: _loadingSources,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildActionButton(
                        onPressed: _testingServers || _nodes.isEmpty ? null : _testServers,
                        icon: Icons.speed_rounded,
                        label: _testingServers
                            ? t('آزمایش…', 'Testing…')
                            : t('آزمایش سرورها', 'Test servers'),
                        loading: _testingServers,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  t('افزودن لینک یا اشتراک', 'Add link or subscription'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _subscriptionController,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: t(
                      'لینک اشتراک یا vless:// و vmess:// را وارد کنید',
                      'Paste subscription URL or vless:// / vmess:// link',
                    ),
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                    prefixIcon: Icon(Icons.link_rounded, color: Colors.white.withOpacity(0.4)),
                  ),
                ),
                const SizedBox(height: 10),
                _buildActionButton(
                  onPressed: _busy ? null : _addSubscription,
                  icon: Icons.add_link_rounded,
                  label: t('افزودن سرورها', 'Import servers'),
                  primary: false,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('فهرست سرورها', 'Server list'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '\( {filtered.length} \){_searchQuery.isNotEmpty ? ' / ${_nodes.length}' : ''}',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_nodes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: t('جستجو در نام، هاست یا پروتکل…', 'Search name, host or protocol…'),
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                      prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.4)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_nodes.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151D31),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.dns_outlined,
                          size: 42,
                          color: Colors.white.withOpacity(0.25),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t(
                            'هنوز سروری اضافه نشده است.\nروی «سرورهای رایگان» بزنید یا لینک وارد کنید.',
                            'No servers yet.\nTap “Free servers” or paste a link.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        t('نتیجه‌ای پیدا نشد', 'No results found'),
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                    ),
                  )
                else
                  ...filtered.map((node) => _buildServerCard(node, accent)),
                const SizedBox(height: 18),
                Text(
                  t(
                    'هشدار امنیتی: سرورهای عمومی ناشناس و غیرقابل اعتمادند. برای حساب‌های بانکی، اطلاعات حساس یا ورودهای مهم از آن‌ها استفاده نکنید. اتصال فقط با لمس دکمه کنار سرور آغاز می‌شود.',
                    'Security: public community servers are untrusted. Do not use them for banking, sensitive data, or important logins. A tunnel starts only when you tap a server Connect button.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.orangeAccent.withOpacity(0.9),
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Herasat 0.3.0 • sing-box core',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white38,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
