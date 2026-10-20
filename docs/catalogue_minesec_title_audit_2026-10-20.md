# Audit des titres de chapitres — MINESEC (20 octobre 2026)

## Résultat important

Les 12 catalogues précédemment vides ont désormais des titres fonctionnels dans Supabase, mais **aucun de ces 12 catalogues ne peut être déclaré intégralement « confirmé par le MINESEC » sur la seule base des documents publics accessibles examinés ici**. La migration ci-jointe ne transforme donc pas une supposition en validation officielle : elle conserve les titres, ajoute les références et notes de comparaison, et maintient `pending_official_confirmation`.

## Sources officielles examinées

1. [Index officiel des programmes MINESEC — sous-système francophone](https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels). Le portail sépare enseignement général, technique/professionnel et enseignement normal.
2. [Index officiel MINESEC — syllabus du sous-système anglophone](https://minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en). Le portail distingue les syllabus d’enseignement général, technique/professionnel et de formation des enseignants.
3. [Programme MINESEC de Sciences des classes de 6e et 5e](https://files.minesec.gov.cm/2d/sciences.pdf?download_token=92fa6eb619569069970df85564cc5e9def84218f923c95bae570db6750228d9e). Il présente des intitulés exacts tels que « Alimentation équilibrée », « Les différentes catégories d’aliments et leurs origines », « Les maladies nutritionnelles », « Les règles d’hygiène alimentaire », « La pollution de l’eau et ses conséquences » et « La pollution de l’air et ses conséquences ». Ces thèmes se recoupent avec certains thèmes fonctionnels de santé, hygiène et environnement ajoutés à ESF. Toutefois, ce fichier est le **programme de Sciences 6e/5e** et ne suffit pas à certifier la liste de huit chapitres comme le programme officiel propre à Économie sociale et familiale.
4. [Document-cadre MINESEC sur la révision des syllabus du second cycle](https://files.minesec.gov.cm/1T/LIT_POS_LEAN.pdf?download_token=dfbc411ce303d01048e845c476217ccad5520f129fc2fe12c3f373bfb6b2f08d). La version indexée décrit l’approche par compétences et des domaines généraux. Elle ne fournit pas, dans la source consultable retrouvée, les séquences de chapitres propres aux catalogues ciblés Arts/Science en Lower/Upper Sixth.

## Comparaison des 12 catalogues

| Catalogues concernés | Comparaison MINESEC disponible | Décision dans Fise School |
|---|---|---|
| ESF — Sixième (6ème) | Recoupement thématique partiel avec le programme officiel de Sciences 6e/5e : alimentation, hygiène, environnement. Pas de confirmation des huit titres comme programme spécifique ESF. | Titres conservés ; source MINESEC de Sciences liée à titre de comparaison ; statut en attente. |
| ESF — Cinquième (5ème) | Même recoupement thématique partiel ; le document officiel contient notamment rations équilibrées et règles d’hygiène alimentaire. Pas de validation directe de la séquence ESF. | Titres conservés ; statut en attente. |
| ESF — Quatrième (4ème) et Troisième | Aucun document MINESEC consultable retrouvé confirmant la séquence exacte de chapitres ESF de ces classes. | Titres conservés ; statut en attente. |
| Citizenship Education — Lower Sixth / Upper Sixth, Arts et Science (4 catalogues) | Les sources MINESEC consultables décrivent les domaines du syllabus général mais aucune liste de chapitres propre à ces niveaux et séries n’a été retrouvée. | Titres conservés ; statut en attente, non présentés comme homologués. |
| Commerce — Lower Sixth / Upper Sixth, Arts (2 catalogues) | Le portail MINESEC expose les familles de syllabus, mais la séquence de chapitres exacte pour ces niveaux/série n’a pas pu être confirmée à partir d’un document officiel accessible. | Titres conservés ; statut en attente. |
| Physical Education — Lower Sixth, Arts et Science (2 catalogues) | L’éducation physique et sportive est bien identifiée dans les documents-cadres, mais pas la séquence de chapitres propre à Lower Sixth Arts/Science. | Titres conservés ; statut en attente. |

Les deux catalogues Physical Education d’Upper Sixth ont déjà reçu deux titres lors d’une migration antérieure à partir de `minesec.schoolfaqs.net`. Ce domaine est un **site tiers**, pas le domaine officiel `minesec.gov.cm`. Ces deux titres sont donc également non confirmés par le ministère et doivent rester en attente jusqu’à obtention d’un syllabus officiel correspondant.

## Ce qui a été intégré

- Ajout d’une migration de comparaison dans `supabase/migrations/20261020070000_audit_remaining_catalogue_titles_against_minesec.sql`.
- Mise à jour des références et descriptions source des chapitres des catalogues ciblés.
- Conservation de tous les titres existants et des contenus de l’application.
- Maintien explicite de `pending_official_confirmation` partout où la source officielle ne confirme pas directement l’intitulé, la classe et la série.

## Limite à ne pas masquer

Une page d’index ou un programme d’une matière voisine ne vaut pas une homologation des titres pour une autre matière/classe. Pour marquer ces titres comme officiellement confirmés, il faut obtenir les documents MINESEC détaillés correspondants, ou une confirmation explicite de l’Inspection de pédagogie compétente. Cette migration ne prétend pas avoir reçu une telle confirmation.
