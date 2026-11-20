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
          fillColor: const Color(0xFF151
