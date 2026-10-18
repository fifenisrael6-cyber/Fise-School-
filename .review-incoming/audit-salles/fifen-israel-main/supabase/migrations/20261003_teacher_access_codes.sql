-- Table pour les codes d'accès uniques des enseignants
CREATE TABLE teacher_access_codes (
  id TEXT PRIMARY KEY NOT NULL,
  teacher_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  class_id TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
  updated_at TIMESTAMP,
  is_active BOOLEAN DEFAULT true NOT NULL,
  UNIQUE(teacher_id, class_id),
  UNIQUE(code),
  CHECK (char_length(code) >= 3)
);

-- Index pour les recherches fréquentes
CREATE INDEX teacher_access_codes_teacher_idx ON teacher_access_codes(teacher_id);
CREATE INDEX teacher_access_codes_class_idx ON teacher_access_codes(class_id);
CREATE INDEX teacher_access_codes_code_idx ON teacher_access_codes(code);
CREATE INDEX teacher_access_codes_active_idx ON teacher_access_codes(is_active);
