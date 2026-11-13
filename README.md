# Salon de coiffure — application Windows (gérante)

Logiciel de caisse et de gestion pour la gérante du salon : caisse avec impression des reçus,
stock, dépenses et factures, comptabilité au centime près, paie des employées.
Les données sont dans Supabase et seront lues par le site web du propriétaire.

## Contenu

```
lib/
  main.dart                 démarrage + connexion à Supabase
  app.dart                  connexion / vérification du compte
  data/models.dart          modèles (Prestation, Produit, Employée…)
  data/repo.dart            tous les appels Supabase
  printing/receipt_printer.dart   reçus 58 mm, reçu de paie, bon de commande
  screens/                  Caisse, Stock, Dépenses, Compta & paie, Réglages
  util/money.dart           montants en centimes (aucun arrondi)
supabase/
  migrations/0001_init.sql  tables, droits, fonctions métier
  seed.sql                  prestations et produits d'exemple
```

## 1. Supabase (une seule fois)

1. Créer un projet sur supabase.com.
2. **SQL Editor** : coller et exécuter, dans l'ordre, `supabase/migrations/0001_init.sql`,
   `supabase/migrations/0002_credit_contenance.sql`, puis `supabase/seed.sql`
   (le seed contient les exemples des maquettes, à remplacer par les vrais prix).
3. **Authentication > Sign In / Providers** : désactiver « Allow new users to sign up »
   (seuls le propriétaire et la gérante ont un compte).
4. **Authentication > Users > Add user** : créer le compte du propriétaire, puis celui de la gérante
   (cocher « Auto confirm user »).
5. **SQL Editor** : donner un rôle à chaque compte (remplacer les e-mails) :

   ```sql
   insert into public.profiles (id, full_name, role)
   select id, 'Nom du propriétaire', 'owner' from auth.users where email = 'proprio@exemple.com';

   insert into public.profiles (id, full_name, role, can_pay_salaries)
   select id, 'Samira', 'manager', true from auth.users where email = 'gerante@exemple.com';
   ```

   `can_pay_salaries` : mettre `false` si la gérante ne doit pas pouvoir payer les salaires.

6. **Project Settings > API** : copier l'URL du projet et la clé **anon public**.

## 2. Projet Flutter

```bash
# dans ce dossier
flutter create --platforms=windows --org dz.minerva --project-name salon_coiffure .
flutter pub get
copy env.example.json env.json      # puis y coller l'URL et la clé anon
flutter run -d windows --dart-define-from-file=env.json
```

`flutter create .` ajoute seulement le dossier `windows/` (il ne remplace pas les fichiers existants).
Dans VS Code, la configuration « Salon (Windows) » de `.vscode/launch.json` passe déjà `env.json`.

`env.json` est dans `.gitignore` : il ne part pas sur GitHub. Ne jamais y mettre la clé `service_role`.

## 3. Matériels (Réglages > Matériels)

- **Imprimante de tickets 58 mm** : brancher en USB, installer son pilote Windows, la choisir puis « Ticket de test ».
- **Tiroir-caisse** : branché sur l'imprimante (prise RJ11). Activer « Tiroir-caisse branché » puis « Tester l'ouverture ».
  Il peut s'ouvrir automatiquement à chaque paiement en espèces.
- **Afficheur client** : le type se choisit dès maintenant, le branchement sera ajouté quand le modèle sera acheté.
- **PC tactile** : « Mode tactile » agrandit les boutons et les champs.

Ces réglages sont mémorisés sur le PC du salon.

## 4. Version à installer au salon

```bash
flutter build windows --release --dart-define-from-file=env.json
```

Le programme est dans `build/windows/x64/runner/Release/` : copier **tout le dossier** sur le PC du salon
(ou publier un zip dans les Releases GitHub).

## Règles de calcul

- Les montants sont stockés en centimes (`bigint`) : 1 500,00 DA = 150000. Aucun nombre à virgule pour l'argent.
- L'encaissement passe par la fonction `create_sale` : les prix sont relus dans la base, la remise fidélité
  est calculée côté serveur, le stock est déduit, et tout est annulé si une étape échoue.
- Stock : chaque prestation peut consommer des produits (Réglages > Prestations > Produits consommés).
  La quantité en stock ne peut changer que par une vente, une entrée de marchandise ou un inventaire (historique dans `stock_movements`).
- Commission d'une employée = % × total de ses prestations du mois (avant remise fidélité).
- Crédit client : si une cliente ne paie pas tout, le reste est noté sur sa fiche (avec l'historique).
  À son prochain passage, son crédit s'ajoute au ticket (désactivable) ; elle peut aussi venir juste rembourser
  (Réglages > Clientes > sa fiche). Un crédit n'est possible que pour une cliente enregistrée.
- Chiffre d'affaires = valeur des tickets ; « Encaissé » = argent réellement reçu (tickets + remboursements).
- Contenance : chaque produit a un conditionnement (flacon de 1 L, tube de 60 ml…). La consommation d'une prestation
  se règle en ml / g / pièces. Le logiciel déduit automatiquement ; le « Constat » dans Stock recale sur le comptage réel.
- Caisse du jour : attendu = dernier comptage + ventes en espèces − dépenses en espèces − salaires en espèces.
  Clôturer chaque soir pour que le fond de caisse du lendemain soit juste.

## Reste à faire

- Logo du salon (écran de connexion, menu, reçus) et couleur définitive.
- Annulation d'un ticket (à décider : réservée au propriétaire ?).
- Branchement de l'afficheur client (selon le modèle choisi).
- Mode hors ligne (copie locale des ventes si internet coupe).
- Site web du propriétaire (Flutter web) + fonction Supabase pour créer le compte de la gérante depuis le site.
