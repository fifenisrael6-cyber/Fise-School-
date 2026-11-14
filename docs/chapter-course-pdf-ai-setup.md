# Configuration de l'extraction IA des cours de chapitre

Cette fonction ne traite que les lignes de \`chapter_content_items\` avec
\`content_type = 'course'\` et un \`source_pdf_path\`. Elle ne touche pas à
\`courses\`, \`course_resources\`, à l'espace d'envoi administrateur ou aux autres chapitres.

## Google Cloud

1. Activez l'API Document AI dans un projet Google Cloud avec facturation.
2. Créez un processeur **Layout Parser** dans la région \`eu\` ou \`us\`.
3. Créez un compte de service dédié et accordez-lui le rôle IAM
   **Document AI API User** (\`roles/documentai.apiUser\`) sur ce projet.
4. Téléchargez la clé JSON du compte de service et gardez-la privée.
5. Copiez le nom complet du processeur, par exemple :
   \`projects/PROJECT_ID/locations/eu/processors/PROCESSOR_ID/processorVersions/pretrained-layout-parser-v3.1-lite-2026-08-11\`.

Le nom de version doit correspondre à une version réellement activée pour votre processeur.
Le modèle layout parser v3.1-lite est en préversion ; sélectionnez une version disponible
dans votre console si cette version n'est pas proposée.

## Secrets Supabase

Ajoutez ces secrets dans Supabase Dashboard > Edge Functions > Secrets :

- \`DOCUMENT_AI_PROCESSOR_NAME\` : nom complet du processeur.
- \`DOCUMENT_AI_LOCATION\` : \`eu\` (ou la région choisie).
- \`GOOGLE_SERVICE_ACCOUNT_JSON\` : contenu intégral du fichier JSON du compte de service.

Les valeurs \`SUPABASE_URL\`, \`SUPABASE_ANON_KEY\` et
\`SUPABASE_SERVICE_ROLE_KEY\` sont fournies à l'exécution par Supabase dans
l'environnement Edge Functions. Ne les placez jamais dans Flutter.

## Migration et déploiement

Depuis le dossier racine du dépôt, après avoir vérifié le projet Supabase lié :

\`\`\`bash
supabase db push
supabase functions deploy process-chapter-course-pdf
\`\`\`

Ne lancez pas \`supabase db push\` sur un projet de production sans vérifier
le projet lié et disposer d'une sauvegarde récente.

## Limite actuelle

La fonction utilise le traitement en ligne Document AI : maximum 15 pages par PDF
et maximum 40 Mo. Le PDF original reste enregistré même si le traitement échoue.
Pour les documents de plus de 15 pages, il faudra activer un worker Cloud Run avec
le traitement par lots Document AI (jusqu'à 500 pages par document pour Layout Parser),
un bucket Google Cloud Storage dédié et une file de tâches. Cette étape exige un
projet Google Cloud et des droits de déploiement qui ne sont pas contenus dans GitHub.

Les résultats sont enregistrés avec le statut \`review_required\` : l'extraction
ne change jamais automatiquement le statut publié/masqué du cours. Une vérification
administrateur reste recommandée, notamment pour les formules, les tableaux complexes
et les schémas.
