import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> cacheFile(String name) async {
  final d = await getApplicationCacheDirectory();
  return File('${d.path}${Platform.pathSeparator}$name');
}
