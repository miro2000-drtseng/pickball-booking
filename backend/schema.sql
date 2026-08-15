-- =============================================
-- 匹克球場地預約系統 - Supabase Schema（完整版）
-- 在 Supabase > SQL Editor 執行此檔案（全新資料庫用這份即可）
-- =============================================

-- 會員表
CREATE TABLE members (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  phone VARCHAR(20) UNIQUE,             -- 純 LINE 登入的會員可能沒有手機號碼
  name VARCHAR(50) NOT NULL,
  email VARCHAR(100) UNIQUE,
  password_hash TEXT,
  line_user_id VARCHAR(64) UNIQUE,      -- LINE 登入的使用者識別碼
  line_display_name VARCHAR(100),
  line_avatar_url TEXT,
  is_member BOOLEAN DEFAULT false,
  member_expire_at TIMESTAMPTZ,
  points_balance INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 密碼重設請求
CREATE TABLE password_resets (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  member_id UUID REFERENCES members(id),
  token VARCHAR(64) UNIQUE NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 管理員表
CREATE TABLE admins (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  email VARCHAR(100) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  name VARCHAR(50) NOT NULL DEFAULT '管理員',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 場地設定表
CREATE TABLE courts (
  id SERIAL PRIMARY KEY,
  name VARCHAR(20) NOT NULL,
  description TEXT,
  price_override JSONB,  -- 若有各場地個別定價 {member: N, non_member: N}
  is_active BOOLEAN DEFAULT true
);

-- 插入 8 面場地
INSERT INTO courts (name) VALUES
  ('場地 1'), ('場地 2'), ('場地 3'), ('場地 4'),
  ('場地 5'), ('場地 6'), ('場地 7'), ('場地 8');

-- 假日表（手動指定的國定假日等，週六日系統會自動視為假日）
CREATE TABLE holidays (
  id SERIAL PRIMARY KEY,
  date DATE UNIQUE NOT NULL,
  name VARCHAR(50) NOT NULL
);

-- 時段定價規則表（分平日／假日兩組）
CREATE TABLE price_rules (
  id SERIAL PRIMARY KEY,
  day_type VARCHAR(10) NOT NULL DEFAULT 'weekday', -- weekday | holiday
  label VARCHAR(30) NOT NULL,        -- e.g. '離峰', '正常', '尖峰'
  hour_start INTEGER NOT NULL,       -- 0-23
  hour_end INTEGER NOT NULL,         -- 0-23 inclusive
  price_member INTEGER NOT NULL,
  price_non_member INTEGER NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 初始定價（平日、假日各一組，可在後台調整）
INSERT INTO price_rules (day_type, label, hour_start, hour_end, price_member, price_non_member) VALUES
  ('weekday', '深夜離峰', 0,  5,  400, 500),
  ('weekday', '白天正常', 6, 18,  640, 800),
  ('weekday', '晚間時段', 19, 23, 480, 600),
  ('holiday', '深夜離峰', 0,  5,  450, 550),
  ('holiday', '白天正常', 6, 18,  700, 850),
  ('holiday', '晚間時段', 19, 23, 550, 650);

-- 封場時段（一次性或每週固定，管理員可設定維修、包場等）
CREATE TABLE blocked_slots (
  id SERIAL PRIMARY KEY,
  label VARCHAR(50) DEFAULT '封場',
  court_ids INTEGER[] NOT NULL,
  hour_start INTEGER NOT NULL,
  hour_end INTEGER NOT NULL,
  block_date DATE,                   -- 一次性封場填此欄
  day_of_week INTEGER,               -- 每週固定封場填 0-6（0=週日）
  valid_from DATE,                   -- 每週固定封場的生效起日（選填）
  valid_until DATE,                  -- 每週固定封場的生效迄日（選填）
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 預約表
CREATE TABLE bookings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  member_id UUID REFERENCES members(id),
  court_id INTEGER REFERENCES courts(id),
  date DATE NOT NULL,
  hour INTEGER NOT NULL CHECK (hour >= 0 AND hour <= 23),
  price INTEGER NOT NULL,
  is_member_price BOOLEAN NOT NULL DEFAULT false,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  -- status: pending | paid | cancelled
  payment_method VARCHAR(20),
  -- payment_method: ecpay | linepay | cash | points | null
  payment_ref VARCHAR(100),
  order_id VARCHAR(50),              -- 同一批預約共用的訂單編號
  points_used INTEGER DEFAULT 0,     -- 本筆折抵的點數
  cancel_reason VARCHAR(50),         -- 例如 payment_timeout（逾時自動取消）
  created_at TIMESTAMPTZ DEFAULT NOW(),
  paid_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  UNIQUE(court_id, date, hour)
);

-- 通知 log 表
CREATE TABLE notify_logs (
  id SERIAL PRIMARY KEY,
  booking_id UUID REFERENCES bookings(id),
  message TEXT,
  sent_at TIMESTAMPTZ DEFAULT NOW()
);

-- 點數儲值倍率級距（依儲值金額給不同倍率點數）
CREATE TABLE topup_tiers (
  id SERIAL PRIMARY KEY,
  label VARCHAR(30),
  min_amount INTEGER NOT NULL,
  max_amount INTEGER,                -- NULL 代表無上限
  multiplier NUMERIC(4,2) NOT NULL DEFAULT 1.0,
  sort_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true
);

INSERT INTO topup_tiers (label, min_amount, max_amount, multiplier, sort_order) VALUES
  ('基本', 1, 999, 1.0, 1),
  ('加碼', 1000, NULL, 1.1, 2);

-- 點數儲值訂單
CREATE TABLE topup_orders (
  id SERIAL PRIMARY KEY,
  member_id UUID REFERENCES members(id),
  plan_id INTEGER,
  amount INTEGER NOT NULL,
  points INTEGER NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending | paid | cancelled
  payment_method VARCHAR(20),                    -- cash | ecpay | linepay
  payment_ref VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  paid_at TIMESTAMPTZ
);

-- 點數異動明細
CREATE TABLE points_transactions (
  id SERIAL PRIMARY KEY,
  member_id UUID REFERENCES members(id),
  type VARCHAR(20) NOT NULL,          -- topup | spend | refund | admin_adjust
  points INTEGER NOT NULL,            -- 正數為增加，負數為扣除
  balance_after INTEGER NOT NULL,
  note TEXT,
  ref_order_id VARCHAR(50),
  payment_method VARCHAR(20),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 球敘活動
CREATE TABLE events (
  id SERIAL PRIMARY KEY,
  title VARCHAR(100) NOT NULL,
  description TEXT,
  event_date DATE NOT NULL,
  start_hour INTEGER,
  end_hour INTEGER,
  location VARCHAR(100),
  capacity INTEGER NOT NULL,
  fee INTEGER NOT NULL DEFAULT 0,
  registration_deadline TIMESTAMPTZ,
  status VARCHAR(20) NOT NULL DEFAULT 'open', -- open | cancelled
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 活動報名（含候補）
CREATE TABLE event_registrations (
  id SERIAL PRIMARY KEY,
  event_id INTEGER REFERENCES events(id),
  member_id UUID REFERENCES members(id),  -- 免登入報名時可能為 NULL
  guest_name VARCHAR(50) NOT NULL,
  guest_phone VARCHAR(20),
  fee INTEGER NOT NULL DEFAULT 0,
  points_used INTEGER DEFAULT 0,
  status VARCHAR(20) NOT NULL DEFAULT 'confirmed', -- confirmed | waitlist | pending | cancelled
  queue_position INTEGER,
  payment_method VARCHAR(20),
  payment_ref VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  paid_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ
);

-- INDEX
CREATE INDEX idx_bookings_date ON bookings(date);
CREATE INDEX idx_bookings_member ON bookings(member_id);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_order_id ON bookings(order_id);
CREATE INDEX idx_members_line_user_id ON members(line_user_id);
CREATE INDEX idx_event_registrations_event ON event_registrations(event_id);
CREATE INDEX idx_points_transactions_member ON points_transactions(member_id);

-- RLS: 關閉（後端用 service_role key，不走 RLS）
ALTER TABLE members DISABLE ROW LEVEL SECURITY;
ALTER TABLE bookings DISABLE ROW LEVEL SECURITY;
ALTER TABLE courts DISABLE ROW LEVEL SECURITY;
ALTER TABLE price_rules DISABLE ROW LEVEL SECURITY;
ALTER TABLE admins DISABLE ROW LEVEL SECURITY;
ALTER TABLE holidays DISABLE ROW LEVEL SECURITY;
ALTER TABLE blocked_slots DISABLE ROW LEVEL SECURITY;
ALTER TABLE topup_tiers DISABLE ROW LEVEL SECURITY;
ALTER TABLE topup_orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE points_transactions DISABLE ROW LEVEL SECURITY;
ALTER TABLE events DISABLE ROW LEVEL SECURITY;
ALTER TABLE event_registrations DISABLE ROW LEVEL SECURITY;
ALTER TABLE password_resets DISABLE ROW LEVEL SECURITY;
ALTER TABLE notify_logs DISABLE ROW LEVEL SECURITY;
