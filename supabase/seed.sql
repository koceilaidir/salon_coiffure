-- Données de départ (exemples tirés des maquettes) — à adapter avec les vrais prix du salon.
-- Montants en centimes : 150000 = 1 500,00 DA.

insert into public.services (name, category, duration_min, price_cents, sort_order) values
  ('Brushing',          'Coiffure', 45,  150000, 1),
  ('Coupe + brushing',  'Coiffure', 60,  250000, 2),
  ('Coupe enfant',      'Coiffure', 30,   80000, 3),
  ('Shampoing seul',    'Coiffure', 15,   40000, 4),
  ('Chignon mariée',    'Coiffure', 90,  600000, 5),
  ('Couleur racines',   'Couleur',  90,  350000, 1),
  ('Mèches / balayage', 'Couleur', 150,  700000, 2),
  ('Lissage kératine',  'Soins',   180, 1200000, 1),
  ('Soin profond',      'Soins',    30,  120000, 2);

insert into public.products (name, category, unit, quantity, min_quantity, cost_cents, sale_price_cents) values
  ('Coloration 6.0',           'Couleur',      'tube',    2, 6,  90000, null),
  ('Oxydant 20 vol. 1 L',      'Couleur',      'flacon',  0, 4, 120000, null),
  ('Shampoing kératine 1 L',   'Soins',        'flacon',  1, 3, 250000, null),
  ('Masque réparateur',        'Soins',        'pot',     9, 4, 180000, null),
  ('Laque fixation forte',     'Coiffage',     'bombe',  14, 5,  70000, null),
  ('Gants nitrile (boîte)',    'Consommables', 'boîte',   1, 3,  85000, null),
  ('Papier aluminium mèches',  'Consommables', 'rouleau', 7, 3,  60000, null),
  ('Sérum brillance',          'Vente',        'flacon', 11, 4, 110000, 220000);
