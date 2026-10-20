# Audit des titres de chapitres — MINESEC (20 octobre 2026)

## Conclusion vérifiable

Les 12 catalogues précédemment vides ont des titres fonctionnels dans Supabase. Après la comparaison des sources, **aucun des 12 catalogues ne doit être marqué intégralement « confirmé par le MINESEC »** : aucun document officiel accessible identifié ne confirme à la fois la matière, le niveau, la série et les huit/dix titres insérés. Les chapitres restent visibles mais portent le statut `pending_official_confirmation`.

Il est important de séparer trois choses : la présence d’un thème dans un programme MINESEC, un intitulé exact trouvé dans un programme officiel, et l’approbation de cet intitulé pour la matière/le niveau/la série précis. Seul le deuxième point est démontrable pour certains thèmes de Sciences 6e/5e; le troisième n’a pas été établi pour ces catalogues.

## Sources officielles examinées

1. [Index officiel des programmes MINESEC — sous-système francophone](https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels). Le portail distingue l’enseignement général, l’enseignement technique et professionnel et l’enseignement normal.
2. [Index officiel MINESEC — syllabus du sous-système anglophone](https://minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en). Le portail distingue les syllabus d’enseignement général, technique/professionnel et de formation des enseignants.
3. [Programme MINESEC de Sciences des classes de 6e et 5e](https://files.minesec.gov.cm/2d/sciences.pdf?download_token=92fa6eb619569069970df85564cc5e9def84218f923c95bae570db6750228d9e). Le document publié sur le domaine officiel contient des titres détaillés de sciences et des sujets de santé, alimentation, hygiène et environnement.
4. [Cadre MINESEC sur la révision des syllabus du second cycle](https://files.minesec.gov.cm/1T/LIT_POS_LEAN.pdf?download_token=dfbc411ce303d01048e845c476217ccad5520f129fc2fe12c3f373bfb6b2f08d). Le texte indexé décrit l’approche par compétences et les domaines généraux de formation, mais ne fournit pas la séquence de chapitres propre à chacun des catalogues ciblés. Le gestionnaire de fichiers MINESEC n’a pas permis de relire le PDF directement lors de cette vérification, donc cette source est utilisée comme référence de cadre, pas comme validation des titres.

## Comparaison détaillée des 12 catalogues à compléter

### 1. Économie sociale et familiale — Sixième et Cinquième

Les huit titres fonctionnels insérés étaient :

| Titre actuel dans Fise School | Comparaison avec un titre exact du programme MINESEC de Sciences 6e/5e | Évaluation |
|---|---|---|
| Hygiène individuelle et collective | Le programme comprend « Les règles d’hygiène alimentaire » et « Quelques règles d’hygiène en rapport avec l’eau ». | Recoupement partiel, pas une correspondance exacte. |
| Alimentation et nutrition équilibrée | Le programme contient « Alimentation équilibrée », « Les différentes catégories d’aliments et leurs origines », « Les maladies nutritionnelles » et « Rations alimentaires équilibrées (classe de 5e) ». | Recoupement fort, mais le document source est le programme de Sciences, pas un syllabus détaillé propre à ESF. |
| Habitat, entretien et sécurité domestique | Aucun intitulé exact correspondant n’a été identifié dans ce document de Sciences. | Non confirmé. |
| Vêtements, textiles et entretien du linge | Aucun intitulé exact correspondant n’a été identifié. | Non confirmé. |
| Organisation du budget familial | Aucun intitulé exact correspondant n’a été identifié. | Non confirmé. |
| Santé familiale et prévention des risques | Le programme de Sciences présente notamment « La santé de la reproduction » et des thèmes de prévention sanitaire. | Recoupement partiel, pas une confirmation de chapitre ESF. |
| Consommation responsable et protection du consommateur | Aucun intitulé exact correspondant n’a été identifié. | Non confirmé. |
| Environnement familial et développement durable | Le programme contient « La pollution de l’eau et ses conséquences » et « La pollution de l’air et ses conséquences ». | Recoupement partiel; le titre actuel reste non confirmé pour ESF. |

**Décision :** je n’ai pas remplacé ces titres par ceux de Sciences, car cela ferait passer une correspondance transversale pour un programme ESF officiel. Les huit titres restent provisoires en Sixième et Cinquième. Pour Quatrième et Troisième, je n’ai pas retrouvé de document officiel accessible confirmant cette séquence ESF.

### 2. Citizenship Education — Lower Sixth et Upper Sixth, Arts et Science (4 catalogues)

Le cadre général MINESEC consultable associe « Citizenship Education » au domaine Sciences humaines/Social Sciences du premier cycle. Je n’ai pas retrouvé dans les sources officielles accessibles une liste de chapitres propre à Lower Sixth/Upper Sixth et ventilée par série Arts/Science. Les titres généraux ajoutés dans ces quatre catalogues ne sont donc pas validés pour ces niveaux.

**Décision :** titres conservés, mais non certifiés. Il faut le syllabus correspondant à ces classes ou la confirmation de l’Inspection de pédagogie pour pouvoir les marquer officiels.

### 3. Commerce — Lower Sixth et Upper Sixth, Arts (2 catalogues)

Le portail officiel MINESEC donne accès aux familles de syllabus, mais je n’ai pas retrouvé dans un document officiel accessible la séquence exacte des chapitres Commerce pour Lower Sixth et Upper Sixth Arts.

**Décision :** titres conservés en attente. Aucune mention « conforme au MINESEC » ne doit être affichée pour le moment.

### 4. Physical Education — Lower Sixth, Arts et Science (2 catalogues)

Le cadre MINESEC fait bien apparaître l’éducation physique et sportive comme domaine de formation, mais je n’ai pas retrouvé une liste de chapitres correspondant précisément à Lower Sixth Arts/Science.

**Décision :** titres conservés en attente; l’appartenance de la matière à un domaine officiel ne prouve pas que la séquence de huit titres est exacte.

### Point de contrôle supplémentaire — Physical Education, Upper Sixth

Ces deux catalogues existaient déjà avec deux titres : « L’individu par rapport à lui-même » et « L’individu par rapport à son environnement physique ». La migration antérieure attribuait ces titres à `minesec.schoolfaqs.net`. Ce domaine est un **site tiers**, pas le domaine gouvernemental officiel `minesec.gov.cm`. Les titres ne peuvent donc pas être présentés comme approuvés par le ministère. Ils restent également en attente de confirmation officielle.

## Ce qui a été intégré dans le dépôt et Supabase

- Migration ajoutée : `supabase/migrations/20261020070000_audit_remaining_catalogue_titles_against_minesec.sql`.
- Rapport ajouté : `docs/catalogue_minesec_title_audit_2026-10-20.md`.
- Métadonnées source et descriptions mises à jour pour les catalogues ciblés, afin d’indiquer clairement le niveau de preuve disponible.
- Les titres existants et les contenus de l’application ont été conservés; aucun cours, fichier, QCM ou média n’a été supprimé.
- Le statut `pending_official_confirmation` est maintenu pour les lignes concernées.

## Ce qu’il manque pour une confirmation ministérielle réelle

Un titre ne peut être « confirmé par le MINESEC » que si un syllabus ou une confirmation ministérielle correspond précisément à la matière, à la classe et à la série. Les index officiels et les programmes d’une matière voisine ne suffisent pas. Il faut obtenir les documents détaillés manquants, ou la réponse écrite de l’Inspection de pédagogie concernée. Je n’affirme pas que le ministère a donné cette approbation.
