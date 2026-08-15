-- =============================================
-- 新增 LINE 登入支援
-- 在 Supabase > SQL Editor 執行此檔案（一次即可，可重複執行不會出錯）
-- =============================================

-- 允許純 LINE 登入的會員沒有手機號碼
ALTER TABLE members ALTER COLUMN phone DROP NOT NULL;

-- LINE 使用者識別碼與顯示資訊
ALTER TABLE members ADD COLUMN IF NOT EXISTS line_user_id VARCHAR(64) UNIQUE;
ALTER TABLE members ADD COLUMN IF NOT EXISTS line_display_name VARCHAR(100);
ALTER TABLE members ADD COLUMN IF NOT EXISTS line_avatar_url TEXT;

CREATE INDEX IF NOT EXISTS idx_members_line_user_id ON members(line_user_id);
