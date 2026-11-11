# Import PDF pédagogique depuis l'administration

## Parcours dans Fise School

1. Se connecter avec un compte dont le profil possède le rôle `admin`.
2. Ouvrir **Administration → Chapitres et contenus**.
3. Sélectionner la salle, la matière, le programme et le chapitre de départ.
4. Choisir **Ajouter un contenu → PDF → leçons natives (IA)**.
5. Sélectionner le PDF et enregistrer.

L'application dépose le document dans le bucket privé/public déjà utilisé `chapter-content`, crée sa ligne source dans `chapter_content_items`, puis appelle l'Edge Function `import-chapter-pdf`.

## Traitement

- Vérifie le JWT et le rôle administrateur côté serveur.
- Vérifie le type, le chapitre et le programme de destination.
- Vérifie la signature PDF, puis extrait le texte (jusqu'à 120 pages et 25 Mo).
- Utilise Gemini pour structurer le document en chapitres et leçons.
- Crée les chapitres manquants dans le programme choisi.
- Enregistre les leçons dans `chapter_content_items` avec `is_published = false`.
- Le trigger de partage existant associe les leçons aux chapitres équivalents : même matière, niveau, sous-système, secteur, spécialité et flux d'enseignement. La série n'est volontairement pas utilisée comme filtre afin de partager les contenus communs entre séries compatibles.

## Validation et publication

Les leçons importées sont des brouillons. L'administrateur doit ouvrir chaque chapitre, vérifier le texte et utiliser **Publier** pour rendre le contenu accessible aux élèves. Le PDF original est conservé comme source.

## Mise à jour immédiate

La migration `20261108030000_chapter_content_realtime.sql` ajoute les tables de chapitres et de contenus officiels à Supabase Realtime. Les écrans élèves actualisent automatiquement la liste des chapitres et le contenu lorsqu'un administrateur importe ou publie.

## Déploiement requis

Le workflow GitHub **Deploy Supabase Edge Functions** déploie désormais `import-chapter-pdf` après un push sur `main`. Il exige les secrets GitHub `SUPABASE_ACCESS_TOKEN` et `SUPABASE_PROJECT_REF`.

Le workflow **Supabase Migrations** applique la migration. Le secret `SUPABASE_DB_URL` (ou `SUPABASE_DATABASE_URL`) est obligatoire : s'il manque, le workflow échoue explicitement au lieu de signaler un succès trompeur.

L'Edge Function utilise les secrets Supabase habituels `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` et `GEMINI_API_KEY` (ainsi que `GEMINI_MODEL` en option). Vérifier dans **Supabase → Edge Functions → Secrets** que `GEMINI_API_KEY` est défini. Ne jamais mettre ces clés dans le code Flutter ou dans Git. Le workflow GitHub de déploiement exige aussi `SUPABASE_ACCESS_TOKEN` et `SUPABASE_PROJECT_REF`.

## Limites à contrôler après déploiement

- Les PDF composés uniquement d'images dépendent de la lecture PDF multimodale de Gemini.
- Les tableaux et formules complexes doivent être relus par l'administrateur après extraction.
- Chaque leçon importée conserve désormais le chemin du PDF source et les numéros de pages associés. L'élève peut ouvrir ces pages originales dans une présentation de manuel A4/mobile : les schémas, images, tableaux et leur position sur la page restent fidèles au document.
- Le PDF original est mis en cache localement lors de l'ouverture du chapitre pour permettre la consultation ultérieure hors connexion. Les pages sources ne sont accessibles que si la leçon correspondante est publiée et que l'élève est autorisé à lire le chapitre.
- Tester avec un compte administrateur, puis avec un compte élève de chaque sous-système/série concerné.

## Cahiers numériques A4

- Dans **Administration → Envoi des cours**, sélectionnez un chapitre puis ouvrez **Créer le cours comme un cahier A4**.
- Chaque page est indépendante. L'administrateur peut écrire le texte, insérer des images, ajouter ou supprimer des pages et basculer vers l'aperçu avant publication.
- Les cours déjà présents dans `chapter_content_items` sont conservés. La migration `20261111120000_course_notebook_pages.sql` les représente initialement par une page modifiable à partir de leur texte existant.
- Les élèves ouvrent les cours dans un lecteur à pages tournantes. Les images insérées dans les pages restent protégées par les règles d'accès du chapitre et sont disponibles après préchargement/cache.
- Les PDF ouverts depuis les ressources hors connexion sont rendus en feuilles A4 individuelles, avec navigation page précédente/suivante. Le fichier PDF original reste intact.
- Les migrations `20261111120000_course_notebook_pages.sql` et `20261111121000_notebook_page_image_storage_access.sql` sont additives ; elles ne suppriment aucun cours ni aucune ressource.
