-- Fise School: native SVT course content for Terminale D.
-- Additive and idempotent: creates only the missing SVT/Terminale/Série D
-- chapter and its lesson cards. Existing classes, subjects and content are kept.

begin;

do $migration$
declare
  v_subject_id uuid;
  v_level_id uuid;
  v_series_id uuid;
  v_curriculum_id uuid;
  v_chapter_id uuid;
begin
  select id into v_subject_id
  from public.subjects
  where code = 'svt'
    and subsystem = 'francophone'
    and sector = 'general'
    and is_active
  limit 1;

  select id into v_level_id
  from public.exam_levels
  where code = 'fr_general_terminale' and active
  limit 1;

  select id into v_series_id
  from public.series
  where code = 'd' and active
  limit 1;

  if v_subject_id is null or v_level_id is null or v_series_id is null then
    raise exception 'SVT Terminale D catalog context is missing; no course content was inserted.';
  end if;

  select id into v_curriculum_id
  from public.curricula
  where subject_id = v_subject_id
    and subsystem = 'francophone'
    and sector = 'general'
    and exam_level_id = v_level_id
    and series_id = v_series_id
    and specialty_id is null
    and is_active
    and is_catalog_container
  order by created_at
  limit 1;

  if v_curriculum_id is null then
    insert into public.curricula
      (subject_id, subsystem, sector, exam_level_id, series_id, specialty_id,
       title_fr, title_en, description_fr, description_en, is_active,
       is_catalog_container)
    values
      (v_subject_id, 'francophone', 'general', v_level_id, v_series_id, null,
       'SVT — Terminale — Série D',
       'Life and Earth Sciences — Terminale — Series D',
       'Catalogue de chapitres et leçons de SVT pour la série D.',
       'Life and Earth Sciences chapter and lesson catalogue for Series D.',
       true, true)
    returning id into v_curriculum_id;
  end if;

  select id into v_chapter_id
  from public.course_chapters
  where curriculum_id = v_curriculum_id
    and lower(trim(title_fr)) = lower('Les échanges cellulaires')
    and is_active
  limit 1;

  if v_chapter_id is null then
    insert into public.course_chapters
      (curriculum_id, title_fr, title_en, description_fr, description_en,
       position, is_active)
    values
      (v_curriculum_id,
       'Les échanges cellulaires',
       'Cellular exchanges',
       'Séquence structurée en cinq leçons : eau, substances dissoutes, particules, importance biologique et applications.',
       'Five lessons: water, dissolved substances, particles, biological importance and applications.',
       (select coalesce(max(position), 0) + 1
          from public.course_chapters
         where curriculum_id = v_curriculum_id),
       true)
    returning id into v_chapter_id;
  end if;

  insert into public.chapter_content_items
    (chapter_id, content_type, title_fr, title_en, body_text_fr,
     position, is_published)
  select v_chapter_id, 'course', lesson.title_fr, lesson.title_en,
         lesson.body_text_fr, lesson.position, true
  from (values
    (1,
     'Leçon 1 — Les échanges d’eau',
     'Lesson 1 — Water exchanges',
     $lesson1$
## Introduction
Les cellules sont constamment en contact avec leur milieu extérieur. Elles peuvent absorber ou perdre de l’eau selon la concentration du milieu.

**Problème biologique :** comment l’eau traverse-t-elle la membrane plasmique et quels sont les effets de ces échanges sur les cellules ?

## I. Mise en évidence
On place des cellules de l’épiderme d’oignon dans trois milieux : eau distillée, solution de concentration voisine du contenu cellulaire et solution concentrée de chlorure de sodium (NaCl).

| Milieu | Observation | Interprétation |
|---|---|---|
| Eau distillée | Cellule turgescente | Entrée nette d’eau |
| Concentration voisine | État stable | Flux globalement équilibrés |
| Solution concentrée | Plasmolyse | Sortie nette d’eau |

**Conclusion :** le passage sélectif de l’eau à travers une membrane est appelé **osmose**.

## II. Mécanisme de l’osmose
L’osmose est le passage de l’eau à travers une membrane sélectivement perméable, du milieu le moins concentré en solutés vers le milieu le plus concentré, jusqu’à l’équilibre.

| Milieu | Définition | Mouvement net de l’eau |
|---|---|---|
| Hypotonique | Moins concentré en solutés que le contenu cellulaire | Entrée |
| Hypertonique | Plus concentré en solutés | Sortie |
| Isotonique | Concentration osmotique efficace équivalente | Aucun mouvement net |

**À retenir :** hypotonique = entrée d’eau ; hypertonique = sortie d’eau ; isotonique = équilibre.

## III. États cellulaires
### Cellules végétales
- **Turgescence :** la cellule absorbe de l’eau ; la vacuole augmente de volume, le cytoplasme s’applique contre la paroi et la cellule devient ferme.
- **Plasmolyse :** après une perte d’eau, le protoplaste se rétracte et se détache partiellement de la paroi ; la vacuole diminue de volume.
- **Déplasmolyse :** une cellule plasmolysée replacée dans un milieu moins concentré absorbe de nouveau de l’eau et revient vers son état initial.

### Cellules animales
- **Cytolyse ou hémolyse :** en milieu hypotonique, la cellule absorbe de l’eau et peut éclater ; pour les globules rouges, on parle d’hémolyse.
- **Crénation :** en milieu hypertonique, le globule rouge perd de l’eau et se rétracte.
- En milieu isotonique, le globule rouge conserve approximativement sa forme normale.

| Milieu | État du globule rouge |
|---|---|
| Hypotonique | Gonflement ; hémolyse possible |
| Isotonique | Forme approximativement normale |
| Hypertonique | Rétraction ; crénation |

## IV. Repères historiques
- **Dutrochet :** met en évidence l’osmose avec une membrane semi-perméable séparant deux milieux de concentrations différentes.
- **Pfeffer :** étudie la pression osmotique. Le passage de l’eau peut engendrer une pression appelée pression osmotique.

## V. Importance et applications
Chez les végétaux, les échanges d’eau assurent la turgescence, l’absorption racinaire et la croissance. Chez les animaux, ils contribuent à l’équilibre hydrique des cellules et au fonctionnement des tissus. Ils sont utilisés dans la salaison, le sucrage, l’osmose inverse, les perfusions adaptées et l’irrigation.

## Exercices d’application
1. Définir osmose, turgescence, plasmolyse, crénation et hémolyse.
2. Citer les trois milieux osmotiques et préciser le sens du déplacement net de l’eau.
3. Distinguer une cellule turgescente d’une cellule plasmolysée.
4. Décrire l’état de cellules d’oignon placées dans l’eau distillée, une solution isotonique et une solution concentrée de NaCl.
5. Un agriculteur arrose ses tomates avec une solution d’engrais trop concentrée. Expliquer le flétrissement et proposer une mesure corrective.
$lesson1$),
    (2,
     'Leçon 2 — Les échanges des substances dissoutes',
     'Lesson 2 — Dissolved substance exchanges',
     $lesson2$
## Introduction
Les cellules échangent avec leur milieu des ions minéraux (Na⁺, K⁺, Ca²⁺, Cl⁻), du glucose, des acides aminés, du dioxygène (O₂) et du dioxyde de carbone (CO₂).

**Problème biologique :** comment les substances dissoutes traversent-elles la membrane plasmique ?

## I. Structure de la membrane plasmique
La membrane plasmique délimite la cellule et contrôle les échanges entre les milieux intracellulaire et extracellulaire. Elle est constituée principalement d’une bicouche de phospholipides, de protéines membranaires, de cholestérol (notamment dans les membranes animales) et de glucides associés aux lipides et aux protéines.

Sa **perméabilité sélective** lui permet de contrôler le passage des substances.

## II. Les modes de transport
### 1. Transport passif
C’est le passage des substances sans dépense directe d’énergie par la cellule. Il se réalise généralement dans le sens du gradient électrochimique.

- **Diffusion simple :** déplacement spontané de molécules d’une zone de forte concentration vers une zone de faible concentration. Exemples : O₂, CO₂ et certaines petites molécules liposolubles.
- **Diffusion facilitée :** passage grâce à des protéines membranaires, sans dépense directe d’ATP. Elle utilise des protéines canaux ou des transporteurs. Exemple : transport du glucose par certaines protéines GLUT.

### 2. Transport actif
C’est le passage d’une substance contre son gradient électrochimique grâce à des protéines de transport et à un apport d’énergie, souvent fourni par l’hydrolyse de l’ATP.

**Exemple : pompe sodium-potassium (Na⁺/K⁺).** Elle permet généralement la sortie de trois ions sodium (3 Na⁺), l’entrée de deux ions potassium (2 K⁺) et utilise une molécule d’ATP. Elle maintient les différences de concentration, participe au potentiel de membrane et contribue au fonctionnement des cellules nerveuses et musculaires.

## III. Comparaison
| Transport passif | Transport actif |
|---|---|
| Pas de dépense directe d’ATP | Nécessite un apport d’énergie |
| Suit le gradient électrochimique | Peut aller contre le gradient |
| Diffusion simple ou facilitée | Systèmes de transport spécifiques |
| Exemple : diffusion de O₂ | Exemple : pompe Na⁺/K⁺ |

## IV. Dialyse
La dialyse est la séparation de substances dissoutes à travers une membrane sélectivement perméable. Les petites molécules et certains ions peuvent passer ; les grosses molécules et les éléments figurés du sang sont retenus selon les caractéristiques de la membrane.

| Osmose | Dialyse |
|---|---|
| Concerne l’eau | Concerne les substances dissoutes diffusibles |
| Passage de l’eau | Passage de petits solutés |
| Membrane sélectivement perméable | Membrane sélectivement perméable |

## Bilan
Les substances dissoutes traversent la membrane par diffusion simple, diffusion facilitée ou transport actif. Le mécanisme dépend de la nature de la substance, de son gradient électrochimique et des protéines de transport disponibles.

## Exercices d’application
1. Définir transport passif et transport actif.
2. Citer les deux types de diffusion.
3. Donner deux exemples de protéines membranaires.
4. Expliquer le fonctionnement de la pompe sodium-potassium.
5. Distinguer osmose et dialyse.
6. Une cellule possède des transporteurs spécifiques du glucose. Quel mécanisme permet son entrée si le gradient est favorable ? Nécessite-t-il une dépense directe d’ATP ?
7. Quel mécanisme maintient une forte concentration de potassium à l’intérieur et de sodium à l’extérieur de la cellule ? Quel est le rôle de l’ATP ?
$lesson2$),
    (3,
     'Leçon 3 — Les échanges de particules',
     'Lesson 3 — Particle exchanges',
     $lesson3$
## Introduction
Les échanges cellulaires concernent aussi des particules ou des vésicules. Ces échanges nécessitent des modifications de la membrane plasmique.

**Problème biologique :** comment les cellules réalisent-elles les échanges de particules avec leur milieu extérieur ?

## I. Les deux grands phénomènes
- **Endocytose :** entrée de substances dans la cellule.
- **Exocytose :** sortie de substances vers le milieu extérieur.

## II. Endocytose
L’endocytose fait entrer des substances provenant du milieu extérieur en les enfermant dans des vésicules formées à partir de la membrane plasmique. Elle comprend notamment la phagocytose et la pinocytose.

### 1. Phagocytose
La phagocytose est l’absorption de particules solides grâce à des prolongements cytoplasmiques appelés **pseudopodes**.

Étapes : reconnaissance et fixation de la particule ; émission de pseudopodes ; encerclement ; formation d’un **phagosome** ; fusion avec un lysosome ; digestion ; rejet éventuel des déchets.

Exemples : les macrophages absorbent des microorganismes ; certains globules blancs détruisent des agents pathogènes ; certaines cellules éliminent des débris cellulaires.

### 2. Pinocytose
La pinocytose est l’absorption de liquides extracellulaires et des substances qu’ils contiennent grâce à de petites vésicules. Elle comprend l’invagination de la membrane, la capture du liquide, la formation d’une vésicule puis le traitement de son contenu.

| Phagocytose | Pinocytose |
|---|---|
| Absorption de particules solides | Absorption de liquides |
| Formation de phagosomes | Formation de petites vésicules |
| Exemple : bactéries | Exemple : liquide extracellulaire |

## III. Exocytose
L’exocytose permet à une cellule de rejeter des substances grâce à la fusion de vésicules intracellulaires avec la membrane plasmique.

Étapes : formation d’une vésicule contenant une substance ; déplacement vers la membrane ; fusion ; libération du contenu dans le milieu extracellulaire.

Exemples : libération d’hormones, de neurotransmetteurs, sécrétion d’enzymes digestives et élimination de certains déchets.

## IV. Importance
Absorption de particules alimentaires ; défense contre les microorganismes ; sécrétion des hormones ; transmission des messages nerveux ; élimination de certaines substances.

**Bilan :** l’endocytose permet l’entrée de substances et l’exocytose leur rejet. Ce sont des transports en masse réalisés par déformation de la membrane plasmique.

## Exercices d’application
1. Définir endocytose, exocytose, phagocytose, pinocytose et phagosome.
2. Un globule blanc entoure une bactérie à l’aide de prolongements, l’absorbe puis la digère. Identifier le phénomène, les prolongements, la vésicule et l’organite intervenant dans la digestion.
3. Une cellule glandulaire libère une hormone dans le sang. Quel mécanisme permet cette libération et quel est le rôle des vésicules ?
$lesson3$),
    (4,
     'Leçon 4 — Importance des échanges cellulaires',
     'Lesson 4 — Importance of cellular exchanges',
     $lesson4$
## Introduction
Les cellules dépendent de leur environnement. Elles doivent recevoir des substances nutritives et rejeter les déchets issus de leurs activités métaboliques.

**Problème biologique :** quelle est l’importance des échanges cellulaires chez les végétaux et les animaux ?

## I. Chez les végétaux
### 1. Eau et sels minéraux
Les végétaux absorbent l’eau et les sels minéraux du sol principalement au niveau des poils absorbants des racines. L’eau pénètre par osmose ; les ions minéraux entrent par différents mécanismes membranaires.

Ces échanges assurent l’hydratation, la nutrition minérale, la croissance et le maintien de la turgescence.

### 2. Dioxyde de carbone
Les feuilles absorbent le CO₂ de l’air principalement à travers les stomates. Il est utilisé pendant la photosynthèse pour fabriquer de la matière organique.

### 3. Dioxygène et vapeur d’eau
Les cellules chlorophylliennes produisent du dioxygène au cours de la photosynthèse. Les végétaux perdent également de la vapeur d’eau par transpiration, notamment au niveau des stomates.

Bilan chez les végétaux : nutrition hydrominérale ; photosynthèse ; respiration ; croissance et développement ; maintien de la turgescence.

## II. Chez les animaux
### 1. Nutrition
Les cellules reçoivent les nutriments provenant de la digestion. Le glucose fournit une source d’énergie ; les acides aminés servent à fabriquer les protéines ; les acides gras participent à la constitution des membranes et aux réserves énergétiques.

### 2. Respiration cellulaire
Les cellules absorbent le dioxygène nécessaire à la respiration aérobie et rejettent le CO₂ produit. La respiration permet notamment la production d’ATP, source d’énergie utilisable par la cellule. Elle utilise notamment le glucose et le dioxygène et produit de l’ATP, du CO₂ et de l’eau.

### 3. Défense immunitaire
Les macrophages et certaines cellules immunitaires utilisent la phagocytose pour absorber et détruire des microorganismes.

### 4. Transmission nerveuse
Les neurones utilisent des échanges ioniques à travers leur membrane pour produire et transmettre les messages nerveux. La pompe sodium-potassium et les canaux ioniques participent à leur fonctionnement électrique.

### 5. Élimination des déchets
Les cellules rejettent certains déchets métaboliques dans le milieu extracellulaire. Ils sont transportés par le sang puis éliminés par les organes appropriés, notamment les reins et les poumons.

## III. Tableau récapitulatif
| Échange | Importance biologique |
|---|---|
| Entrée de l’eau | Hydratation |
| Entrée des sels minéraux | Nutrition minérale |
| Entrée du glucose | Production d’énergie |
| Entrée du dioxygène | Respiration |
| Entrée du CO₂ chez les végétaux | Photosynthèse |
| Sortie du CO₂ chez les animaux | Élimination des déchets respiratoires |
| Phagocytose | Défense immunitaire |
| Exocytose | Sécrétion cellulaire |

## Exercices d’application
1. Citer quatre rôles des échanges cellulaires chez les végétaux.
2. Expliquer leur rôle dans la photosynthèse.
3. Quel est le rôle du dioxygène dans la respiration cellulaire ?
4. Expliquer comment la phagocytose participe à la défense de l’organisme.
5. Une plante de maïs pousse dans un sol pauvre en eau et en sels minéraux. Expliquer le flétrissement et le ralentissement de croissance ; proposer deux mesures correctives.
6. Pourquoi les cellules musculaires ont-elles besoin de glucose et de dioxygène ? Quel produit énergétique est fabriqué et pourquoi le muscle rejette-t-il du CO₂ ?
$lesson4$),
    (5,
     'Leçon 5 — Applications des échanges cellulaires dans la vie courante',
     'Lesson 5 — Everyday applications of cellular exchanges',
     $lesson5$
## Introduction
Les échanges cellulaires sont exploités dans la vie courante, notamment en agriculture, en médecine, dans l’industrie alimentaire et dans le traitement de l’eau.

**Problème biologique :** comment les connaissances sur les échanges cellulaires sont-elles exploitées dans la vie quotidienne ?

## I. Agriculture
- **Irrigation :** une irrigation adaptée maintient l’hydratation des cellules et favorise la croissance des plantes.
- **Engrais :** une concentration excessive peut rendre le sol hypertonique par rapport aux cellules racinaires. L’eau sort alors des cellules ; elles peuvent subir une plasmolyse et la plante se flétrir. Les engrais doivent être utilisés à des concentrations adaptées.

## II. Conservation des aliments
- **Salaison :** l’ajout de sel rend le milieu très concentré en solutés. Les mouvements d’eau contribuent à limiter le développement de nombreux microorganismes.
- **Sucrage :** une forte quantité de sucre dans les confitures réduit la disponibilité de l’eau et crée un milieu défavorable à de nombreux microorganismes.
- Autres applications : déshydratation et fabrication d’aliments concentrés.

## III. Médecine
- **Perfusion :** la concentration osmotique des solutions doit être adaptée à l’organisme. Une solution inadaptée peut provoquer des mouvements excessifs d’eau entre le sang et les cellules.
- **Hémodialyse :** le sang est séparé du liquide de dialyse par une membrane semi-perméable. Des déchets diffusibles, notamment l’urée, passent vers le liquide selon leur gradient de concentration ; les cellules sanguines et la majorité des grosses protéines sont retenues. L’hémodialyse élimine certains déchets, aide à corriger des déséquilibres électrolytiques et participe au contrôle de l’excès d’eau.
- **Osmose inverse :** une pression supérieure à la pression osmotique fait passer l’eau à travers une membrane adaptée qui retient une grande partie des sels dissous. Cette technique sert à purifier ou dessaler l’eau.

## IV. Industrie
Purification de l’eau ; traitement de certains produits alimentaires ; séparation de substances ; production de certaines préparations pharmaceutiques.

## V. Tableau général
| Domaine | Application | Phénomène impliqué |
|---|---|---|
| Agriculture | Irrigation | Osmose |
| Agriculture | Absorption des sels minéraux | Transport membranaire |
| Alimentation | Salaison | Effet osmotique |
| Alimentation | Sucrage | Effet osmotique |
| Médecine | Hémodialyse | Dialyse |
| Médecine | Perfusion | Équilibre osmotique |
| Traitement de l’eau | Dessalement | Osmose inverse |

## Exercices d’application
1. Citer cinq applications des échanges cellulaires et préciser le phénomène concerné.
2. Un cultivateur constate le flétrissement de plants de maïs après une application excessive d’engrais. Expliquer le mécanisme, préciser l’état des cellules et proposer des mesures correctives.
3. Un malade souffrant d’une insuffisance rénale subit des séances d’hémodialyse. Quel est le rôle normal des reins ? Pourquoi le sang doit-il être purifié ? Expliquer le rôle de la membrane du dialyseur et nommer le phénomène permettant le passage de certains déchets.
$lesson5$),
    (6,
     'Fiche de révision — Les échanges cellulaires',
     'Revision sheet — Cellular exchanges',
     $revision$
## 1. Les échanges d’eau
**Osmose :** passage de l’eau à travers une membrane sélectivement perméable.
- Hypotonique : entrée nette d’eau.
- Hypertonique : sortie nette d’eau.
- Isotonique : équilibre osmotique.

## 2. Les substances dissoutes
Diffusion simple ; diffusion facilitée ; transport actif ; dialyse.

## 3. Les échanges de particules
Endocytose : entrée ; phagocytose : absorption de particules solides ; pinocytose : absorption de liquides ; exocytose : sortie.

## 4. Importance biologique
Nutrition ; respiration ; photosynthèse ; défense immunitaire ; élimination des déchets.

## 5. Applications
Agriculture ; conservation des aliments ; perfusion ; hémodialyse ; dessalement de l’eau.

## Travaux dirigés généraux
### Exercice 1 — Maîtrise des connaissances
Définir : échange cellulaire, osmose, plasmolyse, turgescence, diffusion facilitée, transport actif, dialyse, phagocytose, pinocytose et exocytose.

### Exercice 2 — QCM
1. Le passage de l’eau du milieu le moins concentré vers le milieu le plus concentré est appelé : A. Diffusion simple ; B. Osmose ; C. Phagocytose ; D. Exocytose.
2. Une cellule végétale placée dans un milieu hypertonique subit : A. Turgescence ; B. Plasmolyse ; C. Hémolyse ; D. Division cellulaire.
3. Le transport actif nécessite généralement : A. Une dépense d’énergie ; B. Uniquement de l’eau ; C. Aucune protéine membranaire ; D. Une destruction de la membrane.
4. L’absorption des particules solides par une cellule est appelée : A. Pinocytose ; B. Osmose ; C. Phagocytose ; D. Dialyse.
5. La libération du contenu d’une vésicule vers l’extérieur est appelée : A. Exocytose ; B. Endocytose ; C. Plasmolyse ; D. Crénation.

### Exercice 3 — Étude de documents
On place des cellules végétales dans deux solutions : dans A, elles sont turgescentes ; dans B, elles sont plasmolysées.
1. Identifier le type de milieu de chaque cellule.
2. Expliquer le déplacement de l’eau.
3. Réaliser un schéma légendé de chaque cellule.
4. Donner une conclusion générale sur l’osmose.

### Exercice 4 — Évaluation des compétences
Un agriculteur de la région du Centre cultive du maïs. Ses plants se flétrissent après une application excessive d’engrais.
1. Expliquer le mécanisme responsable du flétrissement.
2. Réaliser un schéma légendé d’une cellule végétale plasmolysée.
3. Proposer trois conseils à l’agriculteur.

*Note pédagogique : ce contenu est un support structuré à approfondir avec les travaux pratiques, les corrections détaillées et les consignes du professeur. Il ne constitue pas une reproduction certifiée d’un document officiel MINESEC.*
$revision$)
  ) as lesson(position, title_fr, title_en, body_text_fr)
  where not exists (
    select 1
    from public.chapter_content_items existing
    where existing.chapter_id = v_chapter_id
      and existing.content_type = 'course'
      and lower(trim(existing.title_fr)) = lower(trim(lesson.title_fr))
  );
end
$migration$;

commit;
