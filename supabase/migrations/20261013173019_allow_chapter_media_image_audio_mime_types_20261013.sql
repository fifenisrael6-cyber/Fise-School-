-- Matches the live Supabase Storage configuration for the chapter-content bucket.
-- Teachers may upload course media from phone storage: PDF, photos, audio and video.
update storage.buckets
set allowed_mime_types = array[
  'application/pdf',
  'image/jpeg','image/png','image/gif','image/webp','image/bmp',
  'video/mp4','video/webm','video/quicktime','video/x-msvideo',
  'video/x-matroska','video/mov','video/avi',
  'audio/mpeg','audio/mp3','audio/wav','audio/x-wav','audio/mp4',
  'audio/aac','audio/ogg'
]
where id = 'chapter-content';
