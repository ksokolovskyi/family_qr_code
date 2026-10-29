import 'dart:ui';

/// A vertical color gradient over the card, used for every effect.
///
/// [colors] sit at the heights in [stops]. Above the first stop and below the
/// last one the color holds.
class QrPalette {
  const QrPalette(
    this.name,
    this.colors,
  );

  final String name;
  final List<Color> colors;

  /// Heights of the color stops, in card units, shared by every palette: the
  /// finder centers, the logo, and a row of dots halfway between each.
  ///
  /// Sampled from screenshots of the Family app at these heights. Some of its
  /// gradients bend (they look clipped to sRGB), so two stops are not enough.
  static const List<double> stops = [0.165, 0.35, 0.5, 0.65, 0.835];

  /// Color at height [t] on the card (0 = top, 1 = bottom).
  Color at(double t) {
    if (t <= stops.first) {
      return colors.first;
    }
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i]) {
        final f = (t - stops[i - 1]) / (stops[i] - stops[i - 1]);
        return Color.lerp(colors[i - 1], colors[i], f)!;
      }
    }
    return colors.last;
  }

  @override
  String toString() => 'QrPalette($name)';
}

/// The Family app's palettes, in the order a center tap cycles through them.
/// The first one is the initial color.
const List<QrPalette> qrPalettes = [
  QrPalette('sky', [
    Color(0xFF0189FF),
    Color(0xFF0084FF),
    Color(0xFF0D7CFF),
    Color(0xFF2477FF),
    Color(0xFF446DFC),
  ]),
  QrPalette('pink', [
    Color(0xFFFF00AC),
    Color(0xFFFF009F),
    Color(0xFFFF008C),
    Color(0xFFFF0081),
    Color(0xFFFE006B),
  ]),
  QrPalette('orange', [
    Color(0xFFFF6A00),
    Color(0xFFFF5300),
    Color(0xFFFF4001),
    Color(0xFFFF2C00),
    Color(0xFFFF1301),
  ]),
  QrPalette('green', [
    Color(0xFF01EC09),
    Color(0xFF01EA00),
    Color(0xFF2FE600),
    Color(0xFF62E800),
    Color(0xFFA1E100),
  ]),
  QrPalette('orange-red', [
    Color(0xFFFF6400),
    Color(0xFFFF4600),
    Color(0xFFFF2600),
    Color(0xFFFF0B00),
    Color(0xFFFF0100),
  ]),
  QrPalette('periwinkle', [
    Color(0xFF626BEC),
    Color(0xFF6373E6),
    Color(0xFF677BDD),
    Color(0xFF6783D7),
    Color(0xFF6C8ACB),
  ]),
  QrPalette('indigo-red', [
    Color(0xFF2C00D5),
    Color(0xFF5900A8),
    Color(0xFF7E017D),
    Color(0xFFAB0059),
    Color(0xFFD40128),
  ]),
];
