import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:letopis/services/update_check.dart';

void main() {
  MockClient serve(int status, String body, {void Function(http.Request)? seen}) => MockClient((r) async {
    seen?.call(r);
    return http.Response(body, status);
  });

  test('newer build on the site is reported', () async {
    http.Request? req;
    final u = await checkForUpdate(
      currentBuild: 3,
      client: serve(200, '{"version": "1.2.0", "build": 4}', seen: (r) => req = r),
    );
    expect(u?.version, '1.2.0');
    expect(u?.build, 4);
    // Fixed address, plain GET: nothing from the diary goes out.
    expect(req!.method, 'GET');
    expect(req!.url.toString(), 'https://letopis.recalltwin.com/version.json');
    expect(req!.body, isEmpty);
  });

  test('same or older build means up to date', () async {
    expect(await checkForUpdate(currentBuild: 4, client: serve(200, '{"version": "1.2.0", "build": 4}')), isNull);
    expect(await checkForUpdate(currentBuild: 9, client: serve(200, '{"version": "1.2.0", "build": 4}')), isNull);
  });

  test('broken answers are errors, not updates', () async {
    for (final body in ['', 'not json', '[]', '{"version": "1.2", "build": 4}', '{"version": "1.2.0", "build": "4"}']) {
      await expectLater(
        checkForUpdate(currentBuild: 1, client: serve(200, body)),
        throwsA(isA<UpdateCheckException>()),
        reason: body,
      );
    }
    await expectLater(
      checkForUpdate(currentBuild: 1, client: serve(404, 'nope')),
      throwsA(isA<UpdateCheckException>()),
    );
  });
}
