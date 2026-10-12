import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ramtv/lan_add.dart';

void main() {
  test('LAN source portal bounds uploads and limits PIN guessing', () async {
    final server = LanAddServer();
    final client = HttpClient();
    try {
      final address = await server.start();
      expect(address, isNotNull);
      expect(server.pin, matches(RegExp(r'^\d{6}$')));
      final uri = Uri.parse(address!).replace(host: '127.0.0.1', path: '/add');
      final oversized = await client.postUrl(uri);
      oversized.write('x' * 16385);
      final oversizedResponse = await oversized.close();
      expect(oversizedResponse.statusCode, 413);
      await oversizedResponse.drain<void>();
      for (var i = 0; i < 5; i++) {
        final request = await client.postUrl(uri);
        request.write('pin=wrong');
        final response = await request.close();
        expect(response.statusCode, 403);
        expect(
            response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
        await response.drain<void>();
      }
      final request = await client.postUrl(uri);
      request.write('pin=wrong');
      final response = await request.close();
      expect(response.statusCode, 429);
      await response.drain<void>();
    } finally {
      client.close(force: true);
      await server.stop();
    }
  });

  test('closing the dialog during bind cannot leave a server running',
      () async {
    final server = LanAddServer();
    final pending = server.start();
    await server.stop();
    expect(await pending, isNull);
  });
}
