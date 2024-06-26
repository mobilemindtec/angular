import 'package:_tests/compiler.dart';
import 'package:ngcompiler/v2/context.dart';
import 'package:test/test.dart';

void main() {
  CompileContext.overrideForTesting();

  test('should not crash on null class names', () async {
    await compilesNormally("""
      import '$ngImport';

      @Component(
        selector: 'null-class',
        template: '<div class></div>',
      )
      class NullClassComponent {}
    """);
  });
}
