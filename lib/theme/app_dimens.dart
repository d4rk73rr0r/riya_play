/// Shared spacing/radius scale.
///
/// Before this, border-radius alone had 9 different hand-picked values
/// scattered across the app (4, 6, 8, 10, 12, 15, 16, 20, 30px) with no
/// system behind them. New/updated UI should pull from here instead of
/// inventing another one-off number.
class AppRadius {
  AppRadius._();

  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
}
