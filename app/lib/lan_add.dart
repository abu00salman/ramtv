import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'models.dart';
import 'store.dart';

/// Tiny LAN web page so a source can be added from a phone instead of typing with a TV remote.
/// Only runs while the "Add Source" dialog is open and requires the PIN shown on screen.
class LanAddServer {
  HttpServer? _server;
  String pin = '';
  void Function()? onAdded;
  int _lifecycle = 0;
  int _failedPins = 0;

  Future<String?> start() async {
    final lifecycle = ++_lifecycle;
    try {
      pin = (100000 + Random.secure().nextInt(900000)).toString();
      _failedPins = 0;
      HttpServer server;
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      } catch (_) {
        server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      if (lifecycle != _lifecycle) {
        await server.close(force: true);
        return null;
      }
      _server = server;
      _server!.listen(_handle, onError: (_) {});
      final ip = await _localIp();
      if (ip == null || lifecycle != _lifecycle) {
        await server.close(force: true);
        return null;
      }
      return 'http://$ip:${_server!.port}';
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    ++_lifecycle;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }

  Future<String?> _localIp() async {
    final ifs = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    String? fallback;
    for (final i in ifs) {
      for (final a in i.addresses) {
        final ip = a.address;
        if (a.isLoopback) continue;
        if (ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
          return ip;
        }
        fallback ??= ip;
      }
    }
    return fallback;
  }

  Future<void> _respond(HttpRequest req, int code, String html) async {
    req.response.statusCode = code;
    req.response.headers.contentType = ContentType.html;
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    req.response.headers.set('X-Content-Type-Options', 'nosniff');
    req.response.write(html);
    await req.response.close();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method == 'GET') {
        await _respond(req, 200, _formPage());
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/add') {
        if (_failedPins >= 5) {
          await _respond(req, 429,
              _msgPage('Reopen Add Source on the TV to try again.', ok: false));
          return;
        }
        final bytes = <int>[];
        await for (final chunk in req.timeout(const Duration(seconds: 15))) {
          if (bytes.length + chunk.length > 16384) {
            await _respond(req, 413, _msgPage('Request too large', ok: false));
            return;
          }
          bytes.addAll(chunk);
        }
        final body = utf8.decode(bytes);
        final p = Uri.splitQueryString(body);
        if ((p['pin'] ?? '').trim() != pin) {
          _failedPins++;
          await _respond(
              req, 403, _msgPage('رمز PIN غير صحيح / Wrong PIN', ok: false));
          return;
        }
        final type = p['type'] == 'xtream' ? 'xtream' : 'm3u';
        final url = (p['url'] ?? '').trim();
        final user = (p['username'] ?? '').trim();
        final pass = p['password'] ?? '';
        if (url.isEmpty ||
            (type == 'xtream' && (user.isEmpty || pass.isEmpty))) {
          await _respond(
              req, 400, _msgPage('بيانات ناقصة / Missing fields', ok: false));
          return;
        }
        final tmdb = (p['tmdb'] ?? '').trim();
        if (tmdb.isNotEmpty) {
          await store.prefs.setString('tmdbKey', tmdb);
        }
        final name = (p['name'] ?? '').trim();
        store.addSource(Source(
          id: store.newId(),
          name: name.isEmpty ? (type == 'm3u' ? 'Playlist' : 'Server') : name,
          type: type,
          url: url,
          username: user,
          password: pass,
        ));
        await _respond(
            req,
            200,
            _msgPage(
                'تمت الإضافة، تابع على التلفاز / Added, continue on the TV',
                ok: true));
        onAdded?.call();
        return;
      }
      await _respond(req, 404, _msgPage('Not found', ok: false));
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  static const String _style =
      'body{font-family:-apple-system,Segoe UI,Tahoma,sans-serif;background:#000;color:#fff;margin:0;padding:20px;max-width:520px}'
      'h2{margin:0 0 16px}label{display:block;margin:14px 0 6px;color:#aaa;font-size:14px}'
      'input,select{width:100%;box-sizing:border-box;padding:12px;border-radius:10px;border:1px solid #333;background:#111;color:#fff;font-size:16px}'
      'button{margin-top:22px;width:100%;padding:14px;border:0;border-radius:12px;background:#0057FF;color:#fff;font-size:17px;font-weight:700}'
      '.m{padding:18px;border-radius:12px;font-size:17px}';

  String _formPage() =>
      '<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1"><title>RaM tv</title>'
      '<style>$_style</style></head><body><h2>RaM tv — إضافة مصدر / Add source</h2>'
      '<form method="post" action="/add">'
      '<label>PIN (الظاهر على التلفاز / shown on the TV)</label><input name="pin" inputmode="numeric" autocomplete="off" required>'
      '<label>النوع / Type</label><select name="type"><option value="m3u">M3U</option><option value="xtream">Xtream</option></select>'
      '<label>الاسم / Name</label><input name="name">'
      '<label>رابط القائمة أو السيرفر / Playlist or server URL</label><input name="url" autocapitalize="none" autocorrect="off" required>'
      '<label>اسم المستخدم (Xtream) / Username</label><input name="username" autocapitalize="none" autocorrect="off">'
      '<label>كلمة المرور (Xtream) / Password</label><input name="password" type="password" autocapitalize="none">'
      '<label>مفتاح TMDB (اختياري) / TMDB key (optional)</label><input name="tmdb" autocapitalize="none" autocorrect="off">'
      '<button type="submit">إضافة / Add</button></form></body></html>';

  String _msgPage(String msg, {required bool ok}) =>
      '<!doctype html><html dir="rtl"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1"><style>$_style</style></head><body>'
      '<div class="m" style="background:${ok ? '#0b3d1f' : '#4a1111'}">$msg</div></body></html>';
}
