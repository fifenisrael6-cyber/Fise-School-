import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as pdfjsLib from "npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
const encoder = new TextEncoder();

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(normalized);
  const output = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) output[i] = binary.charCodeAt(i);
  return output;
}

function base64Url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  return bytesToBase64(bytes).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

async function googleAccessToken(): Promise<string> {
  const raw = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("Secret GOOGLE_SERVICE_ACCOUNT_JSON manquant.");
  const account = JSON.parse(raw);
  if (!account.client_email || !account.private_key) {
    throw new Error("Le compte de service Google est incomplet.");
  }

  const issuedAt = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/cloud-platform",
    aud: account.token_uri || "https://oauth2.googleapis.com/token",
    iat: issuedAt,
    exp: issuedAt + 3600,
  }));
  const unsigned = header + "." + claims;
  const pem = String(account.private_key)
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    base64ToBytes(pem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(unsigned)),
  );
  const assertion = unsigned + "." + base64Url(signature);
  const tokenUri = account.token_uri || "https://oauth2.googleapis.com/token";
  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const data = await response.json();
  if (!response.ok || !data.access_token) {
    throw new Error(data.error_description || data.error || "Authentification Google impossible.");
  }
  return String(data.access_token);
}

async function getPdfPageCount(bytes: Uint8Array): Promise<number> {
  const document = await pdfjsLib.getDocument({
    data: bytes,
    disableWorker: true,
    useSystemFonts: true,
  }).promise;
  const count = document.numPages;
  await document.destroy();
  return count;
}

function textFromAnchor(documentText: string, anchor: any): string {
  const segments = anchor?.textSegments;
  if (!Array.isArray(segments)) return "";
  return segments.map((segment: any) => {
    const start = Number(segment.startIndex ?? 0);
    const end = Number(segment.endIndex ?? start);
    return documentText.slice(start, end);
  }).join("").trim();
}

function blockText(block: any, documentText: string): string {
  const direct = block?.textBlock?.text;
  if (typeof direct === "string" && direct.trim()) return direct.trim();
  const layout = block?.textBlock?.layout ?? block?.layout;
  return textFromAnchor(documentText, layout?.textAnchor);
}

function cellText(cell: any, documentText: string): string {
  if (typeof cell === "string") return cell.trim();
  if (typeof cell?.content === "string") return cell.content.trim();
  if (typeof cell?.text === "string") return cell.text.trim();
  const pieces: string[] = [];
  const nested = Array.isArray(cell?.blocks) ? cell.blocks : [];
  for (const part of nested) {
    const value = blockText(part, documentText);
    if (value) pieces.push(value);
  }
  if (pieces.length) return pieces.join(" ").trim();
  return textFromAnchor(documentText, cell?.layout?.textAnchor);
}

function tableMarkdown(table: any, documentText: string): string {
  const rows = [
    ...(Array.isArray(table?.headerRows) ? table.headerRows : []),
    ...(Array.isArray(table?.bodyRows) ? table.bodyRows : []),
  ];
  const matrix = rows.map((row: any) =>
    (Array.isArray(row?.cells) ? row.cells : []).map((cell: any) => cellText(cell, documentText))
  ).filter((row: string[]) => row.some((cell) => cell.length > 0));
  if (!matrix.length) return "";
  const width = Math.max(...matrix.map((row: string[]) => row.length));
  const normalized = matrix.map((row: string[]) =>
    Array.from({ length: width }, (_, index) => (row[index] ?? "").replace(/\|/g, "\\|").replace(/\n/g, " "))
  );
  const lines = ["| " + normalized[0].join(" | ") + " |"];
  lines.push("| " + Array.from({ length: width }, () => "---").join(" | ") + " |");
  for (const row of normalized.slice(1)) lines.push("| " + row.join(" | ") + " |");
  return lines.join("\n");
}

function annotationText(value: any): string {
  const annotations = Array.isArray(value?.annotations) ? value.annotations : [];
  return annotations.map((annotation: any) =>
    String(annotation?.description ?? annotation?.text ?? "").trim()
  ).filter(Boolean).join("\n");
}

function headingPrefix(type: string): string {
  if (type === "title" || type === "heading-1" || type === "heading_1") return "# ";
  if (type === "subtitle" || type === "heading-2" || type === "heading_2") return "## ";
  if (type.startsWith("heading")) return "### ";
  return "";
}

function positionOf(block: any): any {
  const box = block?.boundingBox ?? block?.layout?.boundingBox;
  if (!box) return null;
  return {
    normalizedVertices: box.normalizedVertices ?? [],
    vertices: box.vertices ?? [],
  };
}

async function createPageContent(doc: any, pageCount: number, chapterId: string, itemId: string, db: any) {
  const documentText = String(doc?.text ?? "");
  const layoutBlocks = Array.isArray(doc?.documentLayout?.blocks)
    ? doc.documentLayout.blocks
    : [];
  if (!layoutBlocks.length && !documentText.trim()) {
    throw new Error("Document AI n'a retourné aucun texte ni bloc structuré.");
  }

  const assets = new Map<string, any>();
  for (const asset of Array.isArray(doc?.blobAssets) ? doc.blobAssets : []) {
    const id = String(asset?.assetId ?? asset?.id ?? "");
    if (id) assets.set(id, asset);
  }

  const pages: any[] = Array.from({ length: pageCount }, (_, index) => ({
    id: "pdf-page-" + (index + 1),
    position: index + 1,
    source_page_number: index + 1,
    format: "original-pdf-page",
    blocks: [],
  }));
  const imagePaths = new Map<string, string>();
  let extractedImageCount = 0;
  let tableCount = 0;
  let textCount = 0;

  for (const block of layoutBlocks) {
    const span = block?.pageSpan ?? block?.page_span ?? {};
    const pageStart = Number(span.pageStart ?? span.page_start ?? 1);
    const pageEnd = Number(span.pageEnd ?? span.page_end ?? pageStart);
    const pageNumber = Number.isFinite(pageStart) ? Math.max(1, Math.min(pageCount, pageStart)) : 1;
    const destination = pages[pageNumber - 1];
    const pos = positionOf(block);

    if (block?.textBlock) {
      const raw = blockText(block, documentText);
      if (!raw) continue;
      const kind = String(block.textBlock.type ?? "paragraph").toLowerCase();
      const text = headingPrefix(kind) + raw;
      destination.blocks.push({
        type: "text",
        text_fr: text,
        text_en: text,
        semantic_type: kind,
        position: pos,
        source_block_id: block.blockId ?? block.block_id ?? null,
      });
      textCount++;
      continue;
    }

    if (block?.tableBlock) {
      const markdown = tableMarkdown(block.tableBlock, documentText);
      if (!markdown) {
        const caption = String(block.tableBlock.caption ?? "").trim();
        if (caption) destination.blocks.push({
          type: "text", text_fr: "Tableau : " + caption, text_en: "Table: " + caption,
          semantic_type: "table-caption", position: pos,
        });
        continue;
      }
      destination.blocks.push({
        type: "text",
        text_fr: markdown,
        text_en: markdown,
        semantic_type: "table",
        table_json: block.tableBlock,
        position: pos,
      });
      tableCount++;
      textCount++;
      continue;
    }

    if (block?.listBlock) {
      const entries = Array.isArray(block.listBlock.listEntries)
        ? block.listBlock.listEntries
        : [];
      const lines = entries.map((entry: any) => {
        const direct = String(entry?.text ?? "").trim();
        if (direct) return (entry?.listType === "ORDERED" ? "1. " : "- ") + direct;
        const child = Array.isArray(entry?.blocks)
          ? entry.blocks.map((part: any) => blockText(part, documentText)).filter(Boolean).join(" ")
          : "";
        return child ? "- " + child : "";
      }).filter(Boolean);
      if (lines.length) {
        const value = lines.join("\n");
        destination.blocks.push({
          type: "text", text_fr: value, text_en: value,
          semantic_type: "list", position: pos,
        });
        textCount++;
      }
      continue;
    }

    if (block?.imageBlock) {
      const image = block.imageBlock;
      const assetId = String(image.blobAssetId ?? image.blob_asset_id ?? "");
      const annotation = annotationText(image);
      let storagePath = imagePaths.get(assetId) ?? "";
      const asset = assets.get(assetId);
      if (!storagePath && asset?.content && assetId) {
        const imageBytes = base64ToBytes(String(asset.content));
        const mime = String(asset.mimeType ?? image.mimeType ?? "image/png");
        const extension = mime.includes("jpeg") || mime.includes("jpg")
          ? "jpg"
          : mime.includes("webp") ? "webp" : "png";
        storagePath = chapterId + "/course-assets/" + itemId + "/" + assetId + "." + extension;
        const upload = await db.storage.from("chapter-content").upload(
          storagePath,
          imageBytes,
          { contentType: mime, upsert: true },
        );
        if (upload.error) throw new Error("Impossible d'enregistrer une figure extraite : " + upload.error.message);
        imagePaths.set(assetId, storagePath);
        extractedImageCount++;
      }
      if (storagePath) {
        destination.blocks.push({
          type: "image",
          storage_path: storagePath,
          caption_fr: annotation,
          caption_en: annotation,
          alt_text: annotation,
          position: pos,
          source_block_id: block.blockId ?? block.block_id ?? null,
        });
      } else if (annotation) {
        destination.blocks.push({
          type: "text",
          text_fr: "Illustration : " + annotation,
          text_en: "Illustration: " + annotation,
          semantic_type: "figure-description",
          position: pos,
        });
        textCount++;
      }
    }
  }

  for (const page of pages) {
    if (!page.blocks.length) {
      const sourcePage = Array.isArray(doc?.pages) ? doc.pages[page.position - 1] : null;
      const paragraphTexts = Array.isArray(sourcePage?.paragraphs)
        ? sourcePage.paragraphs.map((paragraph: any) =>
            textFromAnchor(documentText, paragraph?.layout?.textAnchor)
          ).filter(Boolean)
        : [];
      if (paragraphTexts.length) {
        page.blocks.push({
          type: "text",
          text_fr: paragraphTexts.join("\n\n"),
          text_en: paragraphTexts.join("\n\n"),
          semantic_type: "paragraph",
        });
      }
    }
  }

  const fullText = pages.map((page) =>
    page.blocks.filter((block: any) => block.type === "text")
      .map((block: any) => String(block.text_fr ?? "")).join("\n\n")
  ).filter(Boolean).join("\n\n").trim();

  if (!fullText && extractedImageCount === 0) {
    throw new Error("Le document a été reconnu, mais aucun contenu modifiable n'a pu être construit.");
  }

  const contentBlocks: any[] = [];
  for (const page of pages) {
    for (const block of page.blocks) {
      if (block.type === "image") {
        contentBlocks.push({
          type: "IMAGE",
          storage_path: block.storage_path,
          caption: block.caption_fr ?? "",
          source_page_number: page.source_page_number,
        });
      } else {
        const text = String(block.text_fr ?? "").trim();
        if (!text) continue;
        const formulaPattern = /(\$\$[\s\S]+?\$\$|\$[^$\n]+\$)/g;
        let cursor = 0;
        for (const match of text.matchAll(formulaPattern)) {
          const index = match.index ?? 0;
          const before = text.slice(cursor, index).trim();
          if (before) contentBlocks.push({ type: "TEXT", text: before, source_page_number: page.source_page_number });
          const formula = match[0];
          contentBlocks.push({
            type: "FORMULA",
            latex: formula.startsWith("$$") ? formula.slice(2, -2) : formula.slice(1, -1),
            source_page_number: page.source_page_number,
          });
          cursor = index + formula.length;
        }
        const remaining = text.slice(cursor).trim();
        if (remaining) contentBlocks.push({ type: "TEXT", text: remaining, source_page_number: page.source_page_number });
      }
    }
  }

  return {
    pages,
    fullText,
    contentBlocks,
    metadata: {
      processor: Deno.env.get("DOCUMENT_AI_PROCESSOR_NAME") ?? "layout-parser",
      page_count: pageCount,
      layout_block_count: layoutBlocks.length,
      text_block_count: textCount,
      table_count: tableCount,
      extracted_image_count: extractedImageCount,
      extracted_at: new Date().toISOString(),
    },
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);

  let db: ReturnType<typeof createClient> | null = null;
  let contentItemId = "";
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const processorName = Deno.env.get("DOCUMENT_AI_PROCESSOR_NAME");
    const location = Deno.env.get("DOCUMENT_AI_LOCATION") || "eu";
    if (!url || !anon || !service) return json({ error: "Configuration Supabase incomplète." }, 500);

    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json({ error: "Connexion administrateur requise." }, 401);
    const token = auth.slice(7).trim();
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: "Bearer " + token } },
      auth: { persistSession: false },
    });
    const authResult = await userClient.auth.getUser(token);
    if (authResult.error || !authResult.data.user) return json({ error: "Session invalide." }, 401);
    const profile = await userClient.from("profiles").select("role")
      .eq("id", authResult.data.user.id).maybeSingle();
    if (profile.error || profile.data?.role !== "admin") {
      return json({ error: "Cette extraction est réservée à l'administrateur." }, 403);
    }

    const body = await req.json();
    contentItemId = String(body?.content_item_id ?? "").trim();
    if (!contentItemId) return json({ error: "content_item_id manquant." }, 400);
    db = createClient(url, service);

    const sourceResult = await db.from("chapter_content_items")
      .select("id,chapter_id,content_type,title_fr,source_pdf_path,is_published,processing_status")
      .eq("id", contentItemId).single();
    if (sourceResult.error || !sourceResult.data) return json({ error: "Cours introuvable." }, 404);
    const source = sourceResult.data;
    if (source.content_type !== "course" || !source.source_pdf_path) {
      return json({ error: "Le cours sélectionné ne possède pas de PDF original." }, 400);
    }

    await db.from("chapter_content_items").update({
      processing_status: "processing",
      processing_error: null,
    }).eq("id", contentItemId);
    if (!processorName) throw new Error("Secret DOCUMENT_AI_PROCESSOR_NAME manquant.");

    const fileResult = await db.storage.from("chapter-content").download(source.source_pdf_path);
    if (fileResult.error || !fileResult.data) {
      throw new Error(fileResult.error?.message ?? "Téléchargement du PDF original impossible.");
    }
    const bytes = new Uint8Array(await fileResult.data.arrayBuffer());
    if (bytes.length < 5 || new TextDecoder().decode(bytes.subarray(0, 5)) !== "%PDF-") {
      throw new Error("Le fichier source n'est pas un PDF valide.");
    }
    if (bytes.length > 40 * 1024 * 1024) {
      throw new Error("Le PDF dépasse la limite de 40 Mo du traitement en ligne Document AI.");
    }

    const pageCount = await getPdfPageCount(bytes);
    if (pageCount < 1) throw new Error("Le PDF ne contient aucune page.");
    if (pageCount > 15) {
      throw new Error(
        "Ce PDF contient " + pageCount + " pages. Le traitement en ligne Layout Parser est limité à 15 pages. Le PDF original est conservé ; un traitement par lots Cloud Run sera nécessaire pour ce document.",
      );
    }

    const accessToken = await googleAccessToken();
    const apiUrl = "https://" + location + "-documentai.googleapis.com/v1beta3/" +
      processorName + ":process";
    const response = await fetch(apiUrl, {
      method: "POST",
      headers: {
        Authorization: "Bearer " + accessToken,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        rawDocument: {
          content: bytesToBase64(bytes),
          mimeType: "application/pdf",
        },
        processOptions: {
          layoutConfig: {
            enableTableAnnotation: true,
            enableImageAnnotation: true,
            chunkingConfig: {
              chunkSize: 1024,
              includeAncestorHeadings: true,
            },
          },
        },
      }),
    });
    const parsedResponse = await response.json();
    if (!response.ok) {
      throw new Error(parsedResponse?.error?.message ?? "Document AI n'a pas pu analyser le PDF.");
    }
    const document = parsedResponse?.document ?? parsedResponse;
    const result = await createPageContent(
      document, pageCount, String(source.chapter_id), contentItemId, db,
    );

    const { error: updateError } = await db.from("chapter_content_items")
      .update({
        body_text_fr: result.fullText,
        body_text_en: result.fullText,
        content_blocks_fr: result.contentBlocks,
        content_blocks_en: result.contentBlocks,
        pages_json: result.pages,
        source_page_start: 1,
        source_page_end: pageCount,
        processing_status: "review_required",
        processing_error: null,
        processed_at: new Date().toISOString(),
        processing_metadata: result.metadata,
      })
      .eq("id", contentItemId);
    if (updateError) throw updateError;

    return json({
      success: true,
      content_item_id: contentItemId,
      page_count: pageCount,
      layout_block_count: result.metadata.layout_block_count,
      text_block_count: result.metadata.text_block_count,
      table_count: result.metadata.table_count,
      extracted_image_count: result.metadata.extracted_image_count,
      processing_status: "review_required",
      message: "Extraction terminée. Vérifiez le contenu structuré avant de confirmer sa publication.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Erreur pendant l'extraction du PDF.";
    if (db && contentItemId) {
      try {
        await db.from("chapter_content_items").update({
          processing_status: "failed",
          processing_error: message.slice(0, 1800),
        }).eq("id", contentItemId);
      } catch (_) {
        // Preserve the original processing error.
      }
    }
    return json({ success: false, error: message }, 500);
  }
});
