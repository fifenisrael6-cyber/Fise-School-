# Fise School — migration finale sécurité/admin

Cette migration ajoute :
- promotion du compte administrateur existant par e-mail (sans stocker son mot de passe) ;
- rôle admin dans `profiles` et `auth.users.app_metadata` ;
- restriction d'un enseignant aux classes qui lui sont affectées ;
- contrôle du sous-système et du secteur enseignant/classe/matière ;
- accès enseignant à son portefeuille et à ses transactions ;
- accès administrateur aux portefeuilles et paiements ;
- module publicitaire + bucket Supabase Storage ;
- RLS administrateur pour les publicités.

## Déploiement

1. Décompresser le projet.
2. Copier ce fichier dans `supabase/migrations/` avec les autres migrations.
3. Se connecter au bon projet Supabase.
4. Exécuter `supabase db push`.
5. Si le compte administrateur n'existe pas encore dans Supabase Auth, créer d'abord l'utilisateur avec l'adresse e-mail prévue, puis relancer `supabase db push`.
6. Se déconnecter/reconnecter du compte administrateur pour que le JWT récupère `app_metadata.role = admin`.

Le mot de passe n'est jamais écrit dans une migration et ne doit jamais être ajouté à GitHub.
