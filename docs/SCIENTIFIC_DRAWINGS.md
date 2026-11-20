# Scientific drawings in Fise School

## Goal
Render textbook-style, read-only scientific figures inside the existing structured course notebook. This feature is additive: it does not replace the course catalog, chapter folders, existing text/math/table/image blocks, PDF fallback, offline cache, media folders, or QCM flows.

## Rendering path
1. Course content continues to be stored in the existing `chapter_content_items.pages_json` / `courses.pages_json` JSONB fields.
2. A page block with `type: graph` is rendered by `ScientificFigureBlock` using Flutter `CustomPainter`. Curves are sampled numerically; they are not AI-generated raster pictures.
3. A page block with `type: diagram` and no `storage_path` is rendered as a vector-style Flutter drawing.
4. A diagram/image block with `storage_path` continues to use the existing Supabase Storage image resolver and offline image cache.
5. The existing `RichLessonText` continues to render LaTeX, headings, paragraphs and tables.
6. Existing page JSON and images continue to use the current offline caching and pagination pipeline.

## Supported graph block
```json
{
  "type": "graph",
  "function": "exp",
  "title_fr": "Courbe de la fonction exponentielle",
  "title_en": "Exponential function",
  "caption_fr": "La courbe passe par le point (0 ; 1).",
  "x_min": -4,
  "x_max": 3,
  "y_min": -1,
  "y_max": 8
}
```

Supported function identifiers: `exp`, `exponential`, `ln`, `log`, `sin`, `cos`, `tan`, `sqrt`, `quadratic`, `parabola`, `linear`, `line`, `inverse`, `absolute`, `abs`. Optional coefficients: `a`, `b`, `c`.

## Supported diagram block
```json
{
  "type": "diagram",
  "diagram_kind": "unit_circle",
  "title_fr": "Cercle trigonométrique",
  "caption_fr": "Cercle de rayon 1 dans un repère orthonormé."
}
```

Initial vector diagram identifiers: `circle`, `geometry_circle`, `unit_circle`, `trigonometric_circle`, `triangle`, `right_triangle`, `geometry_triangle`, `plant_cell`, `animal_cell`, `cell`, `circuit`, `electric_circuit`, `lens`, `converging_lens`, `optics`.

## Important authoring rules
- Keep the original course text and existing blocks. Insert figure blocks at the correct pedagogical position in the page's `blocks` array.
- Do not replace a complete PDF page with a generated drawing.
- Use a Storage-backed `image` / `diagram` block for a complex, source-specific anatomical or experimental figure that is not yet represented by a native vector diagram.
- Graph coordinates and ranges must come from the mathematical definition or the course source; never guess a graph from a title alone.
- Students see figures in read-only mode. No drawing editor or student mutation API is introduced.
- No database migration is needed for this first integration because the existing JSONB page blocks already store typed structured content.
