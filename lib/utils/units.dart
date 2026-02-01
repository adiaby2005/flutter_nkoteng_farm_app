class Units {
  // Marché
  static const int alveolesPerCarton = 12; // 1 carton = 12 alvéoles
  static const int eggsPerAlveole = 30;    // 1 alvéole = 30 oeufs

  static int cartonsToAlveoles(int cartons) => cartons * alveolesPerCarton;

  static int alveolesToFullCartons(int alveoles) {
    if (alveoles <= 0) return 0;
    return alveoles ~/ alveolesPerCarton;
  }

  static int alveolesRemainder(int alveoles) {
    if (alveoles <= 0) return 0;
    return alveoles % alveolesPerCarton;
  }

  static String formatCartonsAlveoles(int alveoles) {
    final c = alveolesToFullCartons(alveoles);
    final r = alveolesRemainder(alveoles);
    if (alveoles == 0) return "0";
    if (r == 0) return "$c carton(s)";
    if (c == 0) return "$r alvéole(s)";
    return "$c carton(s) + $r alvéole(s)";
  }

  // Si tu veux afficher aussi en oeufs (optionnel)
  static int alveolesToEggs(int alveoles) => alveoles * eggsPerAlveole;
}
