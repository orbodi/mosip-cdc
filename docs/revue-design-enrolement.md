# Revue de design : maquette v2 de la page Enrôlement (25/10/2026)

Objet : la maquette proposée en conversation le 25/10/2026, version refaite d'après la branche `dashboard`.
Revue menée avec le skill `revue-design-bi-anid`. Références :
- jetons : `frontend/src/styles/jetons.css` (branche `dashboard`) ;
- charte : `docs/charte.md` ;
- maquette validée : `maquette/captures/Enrolement-1440.png` (branche `main`) ;
- règles : `CLAUDE.md` racine (`main`) et `frontend/CLAUDE.md` ;
- catalogue : `docs/releve-enrolement.md` ;
- contrastes calculés à partir des valeurs des jetons.

## Bloquants

1. **Les chiffres des blocs ne concordent pas.**
   - Les rejets par étape totalisent 156 899, contre 157 649 rejetées dans le Devenir : il manque une ligne « Autres
     étapes » (750).
   - Les en-cours par étape totalisent 67 896, contre 71 441 : il manque « Autres étapes » (3 545).
   - Les en-cours par étape viennent du relevé de 23 h 45 (statut PROCESSING, dossiers ayant déjà un NIU compris),
     alors que le Devenir applique la règle I4.
   - **Correction** : une seule source (`dwh.suivi_inscription`), une ligne « Autres étapes » partout, et un test
     d'égalité « somme des étapes = Devenir ».
2. **« Synchronisés non reçus : 513 en transit, 505 perdus » ne suit pas la règle I10** (en transit = moins de
   7 jours). Ces chiffres sont un découpage par mois du relevé 5.1. **Correction** : calculer selon I10, ou retirer
   la répartition de la maquette.

## Majeurs

3. **Suivi d'un dossier**
   - **Place** : le bloc coupe le récit de la page, entre le profil des pré-inscrits et le Devenir. C'est un outil,
     pas un indicateur. **Proposition** : panneau latéral ou page dédiée, ouvert par le bouton du bandeau.
   - **Champ de saisie** : il est de type `password`, donc le navigateur propose d'enregistrer le RID dans son
     gestionnaire de mots de passe, et le RID resterait stocké sur le poste. **Proposition** :
     - champ texte (`inputmode="numeric"`, `autocomplete="off"`, contrôle de 29 chiffres) ;
     - champ vidé après la recherche ;
     - le résultat ne réaffiche jamais le RID.
   - **États non dessinés** : format invalide, dossier introuvable, dossier hors de la région de l'utilisateur,
     plafond de recherches atteint, chargement.
4. **Devenir des inscriptions : écart à la maquette.**
   - La maquette met en avant le nombre de NIU (« 3 058 886 NIU générés, soit 93,3 % des 3 278 239 inscriptions »),
     la proposition met le total des inscriptions.
   - La page actuelle dit « Échoués » et « Rejetés », la proposition « Échouées » et « Rejetées ».
   - **Proposition** : reprendre le patron et les libellés de la page actuelle.
5. **Nombre d'abord** : « Remontée des centres 91,8 % » et « Nationalités 98,9 % » affichent un pourcentage seul.
   **Proposition** : le nombre d'abord, puis le pourcentage (ex. « 5 839 074 paquets reçus en moins de 24 h,
   91,8 % »).
6. **En cours par étape : couleurs et valeurs.**
   - La part « plus de 30 jours » est en rouge `--statut-rejete`, couleur des rejets sur toute la page.
   - Seul le total de chaque étape est écrit : la part bloquée n'a pas de valeur en texte.
   - **Proposition** : une teinte foncée de la famille « en cours » ou des hachures, et les deux valeurs écrites
     (ex. « 56 347 bloqués, 2 251 récents »).
7. **Codes MOSIP visibles seulement au survol** : inaccessibles au clavier et au toucher. **Proposition** : le code
   en petit sous le libellé français (« Refus au poste · VALIDATE_PACKET »).
8. **Profil des NIU : 4 tranches d'âge au lieu des 8 décidées le 20/10/2026.** **Proposition** : les 8 tranches de
   la maquette, plus « Âge inconnu », comme le profil des pré-inscrits.
9. **Contraste des barres « En cours » et « Échoués »** : `--statut-en-cours` #FAB219 donne 1,8:1 sur blanc,
   `--statut-echoue` #EC835A 2,6:1, sous le seuil de 3:1 des éléments graphiques (WCAG 1.4.11). Les valeurs écrites
   à côté limitent le problème, mais les jetons existants ont le même défaut dans la page actuelle. **À trancher pour
   toute l'application** : contour `--encre-2` sur ces barres, ou teintes plus foncées.
10. **Mobile (390 px)** :
    - la frise de 6 jalons en 6 colonnes devient illisible : frise verticale sous 700 px ;
    - le bouton « Suivre un dossier » fait environ 28 px de haut, sous les 44 px exigés sur mobile.
11. **Périmètre non signalé** : les nouveaux blocs n'ont pas la pastille « Ensemble du Togo » (ou le nom de la
    région), alors que le Devenir actuel l'a et qu'un utilisateur régional ne voit que sa zone.

## Mineurs

12. Tailles hors échelle dans la maquette en conversation : 11 px (pastilles, jalons), KPI à 22 px au lieu de 26,
    titre à 20 px au lieu de 30. Au développement, utiliser les jetons `--t-*`.
13. Couleur en dur (#412402) sur la pastille de mise à jour : utiliser `--encre` (10:1 sur `--or`).
14. Unités de délai mélangées : « 8 h » dans la carte, « 5,6 j » dans le tableau du Territoire. Fixer une règle
    unique dans `lib/format.ts` (en jours avec une décimale partout, ou en heures sous un jour).
15. « Validation opérateur » pour OSI_VALIDATE : l'étape valide l'opérateur, le superviseur et l'introducteur.
    Libellé plus juste : « Validation opérateur et superviseur ».

## Conforme

- Bandeau sans filtres, avec le lien vers l'Exploration et la pastille de mise à jour au bon format.
- Couleurs de statut du Devenir prises dans les jetons.
- Textes contrastés : `--encre` sur `--or` 10:1, blanc sur `--bleu` 8,3:1.
- Valeurs écrites à côté des barres.
- RID jamais réaffiché ; aucune liste de dossiers.

## Questions pour le responsable

- Suivi d'un dossier : panneau latéral ou page dédiée ?
- Contraste des barres « En cours » et « Échoués » : corriger les jetons pour toute l'application ?
- Unité des délais : jours partout, ou heures sous un jour ?
- Genre des libellés : « Échoués » et « Rejetés » (les dossiers), comme aujourd'hui, ou « Échouées » et
  « Rejetées » (les inscriptions) ?

## Décisions du responsable (25/10/2026, 2 h 05) et maquette v3

1. **Suivi d'un dossier dans une fenêtre modale**, ouverte par le bouton « Suivre un dossier » du bandeau. La saisie et
   le résultat sont dans la fenêtre. Frise verticale des jalons, lisible à toutes les largeurs.
2. **Couleurs corrigées pour toute l'application** (jetons de `jetons.css`, branche `dashboard`), au moins 3:1 sur
   blanc :
   - `--statut-en-cours` : #FAB219 → **#B07D00** (valeur de `--or-texte`, 3,6:1) ;
   - `--statut-echoue` : #EC835A → **#D2632A** (3,8:1) ;
   - nouveau jeton pour « bloqués depuis plus de 30 jours » : **#6B4A00** (8:1).
3. **Délais en heures** (« 8 h », « 246 h »), y compris dans la colonne « Délai médian » du Territoire.
4. **On parle de paquets** : « paquets reçus », « Échoués », « Rejetés » (masculin), bloc « Où s'arrêtent les
   paquets ». Le titre « Devenir des inscriptions » de la maquette est gardé.

**Corrections reprises dans la maquette v3** (conversation, 25/10/2026) :
- bloquants 1 et 2 (lignes « Autres étapes », sommes égales au Devenir ; « au moins 505 depuis plus de 7 jours ») ;
- majeurs 3 à 8, 10 et 11.

Reste pour le développement : les tailles et polices de la charte (mineur 12), à appliquer avec les jetons.
