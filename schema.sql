-- =====================================================================
-- SAN THUONG MAI DIEN TU DA KENH & KHO THONG MINH  (PostgreSQL 14+)  -- v3
-- v3 (chuan hoa 3NF): bo bang dia_chi + dat_giu_hang, bo danh_gia.ma_khach_hang,
--     don_hang luu snapshot dia chi giao; them rang buoc gian hang cua chi tiet don.
-- Gia dinh: moi don hang thuoc dung 1 gian hang, xuat tu 1 kho.
-- Ton kho: so_luong_vat_ly (on_hand), so_luong_giu (reserved),
--          kha dung = vat_ly - giu.
--   ChoXacNhan -> DaXacNhan : GIU hang (kha dung giam ngay)
--   DaXacNhan  -> DangGiao  : XUAT kho (vat ly va giu cung giam)
--   DaXacNhan  -> DaHuy     : NHA giu
--   DangGiao   -> DaHuy     : HOAN hang ve kho (vat ly tang)
-- Chay: psql -U postgres -d ecom -f schema.sql
-- =====================================================================

DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

-- ---------------------------------------------------------------------
-- 1. DANH MUC (tu tham chieu)
-- ---------------------------------------------------------------------
CREATE TABLE danh_muc (
    ma_danh_muc      SERIAL PRIMARY KEY,
    ten_danh_muc     VARCHAR(100) NOT NULL,
    ma_danh_muc_cha  INT REFERENCES danh_muc(ma_danh_muc) ON DELETE RESTRICT,
    CONSTRAINT uq_danh_muc_cha_ten UNIQUE (ma_danh_muc_cha, ten_danh_muc),
    CONSTRAINT ck_danh_muc_khong_tu_cha CHECK (ma_danh_muc_cha IS NULL OR ma_danh_muc_cha <> ma_danh_muc)
);

-- ---------------------------------------------------------------------
-- 2. NHA CUNG CAP, GIAN HANG (SELLER), KHO
-- ---------------------------------------------------------------------
CREATE TABLE nha_cung_cap (
    ma_ncc      SERIAL PRIMARY KEY,
    ten_ncc     VARCHAR(150) NOT NULL UNIQUE,
    dien_thoai  VARCHAR(20),
    dia_chi     VARCHAR(255)
);

CREATE TABLE gian_hang (
    ma_gian_hang  SERIAL PRIMARY KEY,
    ten_gian_hang VARCHAR(150) NOT NULL UNIQUE,
    email         VARCHAR(150) NOT NULL UNIQUE,
    ngay_tham_gia DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE kho (
    ma_kho    SERIAL PRIMARY KEY,
    ten_kho   VARCHAR(100) NOT NULL UNIQUE,
    tinh_tp   VARCHAR(100) NOT NULL,
    dia_chi   VARCHAR(255)
);

-- ---------------------------------------------------------------------
-- 3. SAN PHAM & BIEN THE
-- ---------------------------------------------------------------------
CREATE TABLE san_pham (
    ma_san_pham   SERIAL PRIMARY KEY,
    ma_gian_hang  INT NOT NULL REFERENCES gian_hang(ma_gian_hang),
    ma_danh_muc   INT NOT NULL REFERENCES danh_muc(ma_danh_muc),
    ma_ncc        INT NOT NULL REFERENCES nha_cung_cap(ma_ncc),
    ten_san_pham  VARCHAR(200) NOT NULL,
    mo_ta         TEXT,
    ngay_tao      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE bien_the (
    ma_bien_the  SERIAL PRIMARY KEY,
    ma_san_pham  INT NOT NULL REFERENCES san_pham(ma_san_pham) ON DELETE CASCADE,
    sku          VARCHAR(50) NOT NULL,
    mau_sac      VARCHAR(50),
    kich_co      VARCHAR(30),
    gia_nhap     NUMERIC(14,0) NOT NULL CHECK (gia_nhap >= 0),
    gia_ban      NUMERIC(14,0) NOT NULL,
    CONSTRAINT uq_bien_the_sku UNIQUE (sku),
    CONSTRAINT uq_bien_the_thuoc_tinh UNIQUE (ma_san_pham, mau_sac, kich_co),
    CONSTRAINT ck_gia_ban_lon_hon_gia_nhap CHECK (gia_ban > gia_nhap)
);

-- Ton kho theo tung kho: vat ly + dang giu
CREATE TABLE ton_kho (
    ma_kho           INT NOT NULL REFERENCES kho(ma_kho),
    ma_bien_the      INT NOT NULL REFERENCES bien_the(ma_bien_the),
    so_luong_vat_ly  INT NOT NULL DEFAULT 0,
    so_luong_giu     INT NOT NULL DEFAULT 0,
    PRIMARY KEY (ma_kho, ma_bien_the),
    CONSTRAINT ck_ton_vat_ly_khong_am CHECK (so_luong_vat_ly >= 0),
    CONSTRAINT ck_ton_giu_khong_am    CHECK (so_luong_giu >= 0),
    CONSTRAINT ck_giu_khong_vuot_vat_ly CHECK (so_luong_giu <= so_luong_vat_ly)
);

-- So cai bien dong kho: chi them, khong sua/xoa
CREATE TABLE bien_dong_kho (
    ma_bien_dong  BIGSERIAL PRIMARY KEY,
    ma_kho        INT NOT NULL,
    ma_bien_the   INT NOT NULL,
    loai          VARCHAR(12) NOT NULL,
    delta_vat_ly  INT NOT NULL DEFAULT 0,
    delta_giu     INT NOT NULL DEFAULT 0,
    ma_don_hang   INT,                       -- NULL voi nhap kho / dieu chinh
    ly_do         VARCHAR(200),
    thoi_diem     TIMESTAMP NOT NULL DEFAULT now(),
    FOREIGN KEY (ma_kho, ma_bien_the) REFERENCES ton_kho(ma_kho, ma_bien_the),
    CONSTRAINT ck_bien_dong_loai CHECK (loai IN ('NHAP','GIU','NHA_GIU','XUAT','HOAN','DIEU_CHINH')),
    CONSTRAINT ck_bien_dong_khac_khong CHECK (delta_vat_ly <> 0 OR delta_giu <> 0)
);

-- ---------------------------------------------------------------------
-- 4. KHACH HANG, DIA CHI, VOUCHER
-- ---------------------------------------------------------------------
CREATE TABLE khach_hang (
    ma_khach_hang  SERIAL PRIMARY KEY,
    ho_ten         VARCHAR(100) NOT NULL,
    email          VARCHAR(150) NOT NULL UNIQUE,
    dien_thoai     VARCHAR(20),
    dia_chi        VARCHAR(255),             -- dia chi giao hang mac dinh
    ngay_dang_ky   DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE voucher (
    ma_voucher            SERIAL PRIMARY KEY,
    ma_code               VARCHAR(30) NOT NULL UNIQUE,
    ma_gian_hang          INT REFERENCES gian_hang(ma_gian_hang),  -- NULL = voucher cua san
    phan_tram_giam        INT NOT NULL,
    gia_tri_toi_thieu     NUMERIC(14,0) NOT NULL DEFAULT 0,
    giam_toi_da           NUMERIC(14,0),
    ngay_bat_dau          DATE NOT NULL,
    ngay_het_han          DATE NOT NULL,
    CONSTRAINT ck_voucher_phan_tram CHECK (phan_tram_giam BETWEEN 1 AND 100),
    CONSTRAINT ck_voucher_gia_tri_min CHECK (gia_tri_toi_thieu >= 0),
    CONSTRAINT ck_voucher_ngay CHECK (ngay_het_han >= ngay_bat_dau)
);

-- ---------------------------------------------------------------------
-- 5. DON HANG
-- ---------------------------------------------------------------------
CREATE TABLE don_hang (
    ma_don_hang     SERIAL PRIMARY KEY,
    ma_khach_hang   INT NOT NULL REFERENCES khach_hang(ma_khach_hang),
    ma_gian_hang    INT NOT NULL REFERENCES gian_hang(ma_gian_hang),
    ma_kho_xuat     INT NOT NULL REFERENCES kho(ma_kho),
    ma_voucher      INT REFERENCES voucher(ma_voucher),
    -- snapshot thong tin nhan hang tai thoi diem dat (khong doi khi khach doi dia chi)
    nguoi_nhan      VARCHAR(100) NOT NULL,
    dien_thoai_nhan VARCHAR(20)  NOT NULL,
    dia_chi_giao    VARCHAR(255) NOT NULL,
    kenh_ban        VARCHAR(10) NOT NULL DEFAULT 'Web',
    idempotency_key VARCHAR(64),             -- chong tao don trung khi retry
    ngay_dat        TIMESTAMP NOT NULL DEFAULT now(),
    trang_thai      VARCHAR(20) NOT NULL DEFAULT 'ChoXacNhan',
    tong_tien_hang  NUMERIC(14,0) NOT NULL CHECK (tong_tien_hang >= 0), -- tong truoc giam (snapshot)
    tien_giam       NUMERIC(14,0) NOT NULL DEFAULT 0 CHECK (tien_giam >= 0),
    phi_van_chuyen  NUMERIC(14,0) NOT NULL DEFAULT 0 CHECK (phi_van_chuyen >= 0),
    CONSTRAINT ck_don_hang_trang_thai CHECK
        (trang_thai IN ('ChoXacNhan','DaXacNhan','DangGiao','DaGiao','DaHuy')),
    CONSTRAINT ck_don_hang_kenh CHECK (kenh_ban IN ('Web','CuaHang','DoiTac')),
    CONSTRAINT ck_don_hang_giam_hop_le CHECK (tien_giam <= tong_tien_hang),
    CONSTRAINT uq_don_hang_idempotency UNIQUE (ma_khach_hang, idempotency_key)
);

CREATE TABLE chi_tiet_don_hang (
    ma_don_hang  INT NOT NULL REFERENCES don_hang(ma_don_hang) ON DELETE CASCADE,
    ma_bien_the  INT NOT NULL REFERENCES bien_the(ma_bien_the),
    so_luong     INT NOT NULL CHECK (so_luong > 0),
    don_gia      NUMERIC(14,0) NOT NULL CHECK (don_gia > 0),  -- gia ban tai thoi diem dat
    PRIMARY KEY (ma_don_hang, ma_bien_the)
);

-- so cai bien dong kho tham chieu don hang (RESTRICT: khong xoa duoc don da co bien dong)
ALTER TABLE bien_dong_kho
    ADD CONSTRAINT fk_bien_dong_don_hang FOREIGN KEY (ma_don_hang) REFERENCES don_hang(ma_don_hang);

-- Moi dong don chi duoc GIU 1 lan va XUAT 1 lan (chong giu trung khi retry)
CREATE UNIQUE INDEX uq_bien_dong_giu_1_lan  ON bien_dong_kho(ma_don_hang, ma_bien_the) WHERE loai = 'GIU';
CREATE UNIQUE INDEX uq_bien_dong_xuat_1_lan ON bien_dong_kho(ma_don_hang, ma_bien_the) WHERE loai = 'XUAT';

CREATE TABLE lich_su_trang_thai (
    ma_lich_su    BIGSERIAL PRIMARY KEY,
    ma_don_hang   INT NOT NULL REFERENCES don_hang(ma_don_hang) ON DELETE CASCADE,
    trang_thai_cu VARCHAR(20),
    trang_thai_moi VARCHAR(20) NOT NULL,
    thoi_diem     TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE thanh_toan (
    ma_thanh_toan  SERIAL PRIMARY KEY,
    ma_don_hang    INT NOT NULL REFERENCES don_hang(ma_don_hang) ON DELETE CASCADE,
    phuong_thuc    VARCHAR(20) NOT NULL CHECK (phuong_thuc IN ('COD','ChuyenKhoan','TheTinDung','ViDienTu')),
    so_tien        NUMERIC(14,0) NOT NULL CHECK (so_tien > 0),
    trang_thai     VARCHAR(20) NOT NULL DEFAULT 'ChoThanhToan'
                   CHECK (trang_thai IN ('ChoThanhToan','ThanhCong','ThatBai','HoanTien')),
    thoi_diem      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE van_chuyen (
    ma_van_chuyen  SERIAL PRIMARY KEY,
    ma_don_hang    INT NOT NULL UNIQUE REFERENCES don_hang(ma_don_hang) ON DELETE CASCADE,
    don_vi_vc      VARCHAR(50) NOT NULL,
    ma_van_don     VARCHAR(50) UNIQUE,
    ngay_giao_du_kien DATE,
    ngay_giao_thuc_te DATE
);

CREATE TABLE danh_gia (
    ma_danh_gia    SERIAL PRIMARY KEY,
    ma_don_hang    INT NOT NULL,
    ma_bien_the    INT NOT NULL,
    so_sao         INT NOT NULL CHECK (so_sao BETWEEN 1 AND 5),
    noi_dung       TEXT,
    ngay_danh_gia  TIMESTAMP NOT NULL DEFAULT now(),
    FOREIGN KEY (ma_don_hang, ma_bien_the)
        REFERENCES chi_tiet_don_hang(ma_don_hang, ma_bien_the),
    CONSTRAINT uq_moi_mon_danh_gia_1_lan UNIQUE (ma_don_hang, ma_bien_the)
);

-- ---------------------------------------------------------------------
-- 6. INDEX CO BAN CHO KHOA NGOAI (index nang cao lam o buoc benchmark)
-- ---------------------------------------------------------------------
CREATE INDEX idx_san_pham_danh_muc   ON san_pham(ma_danh_muc);
CREATE INDEX idx_san_pham_gian_hang  ON san_pham(ma_gian_hang);
CREATE INDEX idx_san_pham_ncc        ON san_pham(ma_ncc);
CREATE INDEX idx_bien_the_san_pham   ON bien_the(ma_san_pham);
CREATE INDEX idx_don_hang_khach      ON don_hang(ma_khach_hang);
CREATE INDEX idx_don_hang_gian_hang  ON don_hang(ma_gian_hang);
CREATE INDEX idx_ctdh_bien_the       ON chi_tiet_don_hang(ma_bien_the);
CREATE INDEX idx_bien_dong_kho_bt    ON bien_dong_kho(ma_kho, ma_bien_the);
CREATE INDEX idx_bien_dong_kho_don   ON bien_dong_kho(ma_don_hang);
-- FK ma_don_hang cua lich_su_trang_thai va thanh_toan (ON DELETE CASCADE tu don_hang):
-- tra cuu lich su / thanh toan theo don va tranh Seq Scan khi xoa don hoac don dep seed_lon.
-- (van_chuyen.ma_don_hang da co UNIQUE nen da co index.)
CREATE INDEX idx_lich_su_tt_don      ON lich_su_trang_thai(ma_don_hang);
CREATE INDEX idx_thanh_toan_don      ON thanh_toan(ma_don_hang);

-- ---------------------------------------------------------------------
-- 7. VIEW: ton kha dung + doi soat so cai
-- ---------------------------------------------------------------------
CREATE VIEW v_ton_kha_dung AS
SELECT ma_kho, ma_bien_the, so_luong_vat_ly, so_luong_giu,
       so_luong_vat_ly - so_luong_giu AS so_luong_kha_dung
FROM ton_kho;

-- khop = TRUE nghia la ton hien tai bang tong cac dong so cai
CREATE VIEW v_doi_soat_kho AS
SELECT t.ma_kho, t.ma_bien_the, t.so_luong_vat_ly, t.so_luong_giu,
       COALESCE(SUM(b.delta_vat_ly),0) AS vat_ly_theo_so_cai,
       COALESCE(SUM(b.delta_giu),0)    AS giu_theo_so_cai,
       (t.so_luong_vat_ly = COALESCE(SUM(b.delta_vat_ly),0)
        AND t.so_luong_giu = COALESCE(SUM(b.delta_giu),0)) AS khop
FROM ton_kho t
LEFT JOIN bien_dong_kho b ON b.ma_kho = t.ma_kho AND b.ma_bien_the = t.ma_bien_the
GROUP BY t.ma_kho, t.ma_bien_the, t.so_luong_vat_ly, t.so_luong_giu;

-- =====================================================================
-- HAM TIEN ICH
-- =====================================================================

-- Nhap kho: tao dong ton neu chua co, cong ton, ghi so cai
CREATE OR REPLACE FUNCTION fn_nhap_kho(p_kho INT, p_bien_the INT, p_sl INT, p_ly_do TEXT DEFAULT 'Nhap hang')
RETURNS VOID AS $$
BEGIN
    IF p_sl <= 0 THEN
        RAISE EXCEPTION 'So luong nhap phai > 0';
    END IF;

    INSERT INTO ton_kho(ma_kho, ma_bien_the, so_luong_vat_ly)
    VALUES (p_kho, p_bien_the, p_sl)
    ON CONFLICT (ma_kho, ma_bien_the)
    DO UPDATE SET so_luong_vat_ly = ton_kho.so_luong_vat_ly + EXCLUDED.so_luong_vat_ly;

    INSERT INTO bien_dong_kho(ma_kho, ma_bien_the, loai, delta_vat_ly, delta_giu, ly_do)
    VALUES (p_kho, p_bien_the, 'NHAP', p_sl, 0, p_ly_do);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_ghi_bien_dong(
    p_kho INT, p_bt INT, p_loai TEXT, p_d_vl INT, p_d_giu INT, p_don INT, p_ly_do TEXT)
RETURNS VOID AS $$
BEGIN
    INSERT INTO bien_dong_kho(ma_kho, ma_bien_the, loai, delta_vat_ly, delta_giu, ma_don_hang, ly_do)
    VALUES (p_kho, p_bt, p_loai, p_d_vl, p_d_giu, p_don, p_ly_do);
END;
$$ LANGUAGE plpgsql;

-- Ham tao don: kiem tra dau vao chat che, tinh tong tien, tien giam, snapshot don_gia
CREATE OR REPLACE FUNCTION fn_tao_don_hang(
    p_khach INT, p_gian_hang INT, p_kho INT, p_ngay TIMESTAMP,
    p_voucher INT, p_items JSONB, p_kenh TEXT DEFAULT 'Web', p_idem TEXT DEFAULT NULL)
RETURNS INT AS $$
DECLARE
    v_tong  NUMERIC;
    v_giam  NUMERIC := 0;
    v_don   INT;
    v       voucher%ROWTYPE;
    v_elem  JSONB;
    v_bt_id INT;
    v_sl    INT;
BEGIN
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Danh sach san pham (p_items) khong duoc rong va phai la mang JSON';
    END IF;

    FOR v_elem IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        IF jsonb_typeof(v_elem) <> 'object'
           OR (v_elem->>'bt') IS NULL
           OR (v_elem->>'bt') !~ '^-?[0-9]+$' THEN
            RAISE EXCEPTION 'Ma bien the (SKU) khong hop le: %', COALESCE(v_elem->>'bt', 'NULL');
        END IF;

        v_bt_id := (v_elem->>'bt')::INT;
        IF v_bt_id <= 0 OR NOT EXISTS (SELECT 1 FROM bien_the WHERE ma_bien_the = v_bt_id) THEN
            RAISE EXCEPTION 'Ma bien the (SKU) % khong ton tai trong he thong', v_bt_id;
        END IF;

        IF (v_elem->>'sl') IS NULL OR (v_elem->>'sl') !~ '^-?[0-9]+$' THEN
            RAISE EXCEPTION 'So luong dat hang khong hop le cho bien the %: %', v_bt_id, COALESCE(v_elem->>'sl', 'NULL');
        END IF;

        v_sl := (v_elem->>'sl')::INT;
        IF v_sl <= 0 THEN
            RAISE EXCEPTION 'So luong dat hang phai > 0 cho bien the % (nhan duoc: %)', v_bt_id, v_sl;
        END IF;
    END LOOP;

    IF (SELECT COUNT(*) <> COUNT(DISTINCT (e->>'bt')::INT) FROM jsonb_array_elements(p_items) e) THEN
        RAISE EXCEPTION 'Danh sach san pham chua ma bien the (SKU) bi trung lap';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM khach_hang WHERE ma_khach_hang = p_khach) THEN
        RAISE EXCEPTION 'Khach hang % khong ton tai', p_khach;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM kho WHERE ma_kho = p_kho) THEN
        RAISE EXCEPTION 'Kho xuat % khong ton tai', p_kho;
    END IF;

    SELECT SUM(b.gia_ban * (e->>'sl')::INT) INTO v_tong
    FROM jsonb_array_elements(p_items) e
    JOIN bien_the b ON b.ma_bien_the = (e->>'bt')::INT;

    IF p_voucher IS NOT NULL THEN
        SELECT * INTO v FROM voucher WHERE ma_voucher = p_voucher;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Voucher % khong ton tai', p_voucher;
        END IF;
        v_giam := LEAST(ROUND(v_tong * v.phan_tram_giam / 100.0),
                        COALESCE(v.giam_toi_da, v_tong));
    END IF;

    -- Chong tao don trung theo (khach, idempotency_key): khoa tu van cap giao dich
    -- (cung khoa voi tang ung dung web_dashboard.py) de 2 lan goi dong thoi cung khoa
    -- duoc xep hang; lan sau nhan loi ro rang thay vi loi UNIQUE tho.
    -- Tang ung dung kiem tra truoc va tra lai dung ma don cu neu noi dung trung khop.
    IF p_idem IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('omnistock_idem_' || p_khach || '_' || p_idem));
        SELECT ma_don_hang INTO v_don FROM don_hang
         WHERE ma_khach_hang = p_khach AND idempotency_key = p_idem;
        IF FOUND THEN
            RAISE EXCEPTION 'IDEM_CONFLICT: Khoa chong trung % cua khach % da dung cho don #%', p_idem, p_khach, v_don;
        END IF;
    END IF;

    INSERT INTO don_hang(ma_khach_hang, ma_gian_hang, ma_kho_xuat, ma_voucher,
                         nguoi_nhan, dien_thoai_nhan, dia_chi_giao,
                         kenh_ban, idempotency_key, ngay_dat, tong_tien_hang, tien_giam, phi_van_chuyen)
    SELECT k.ma_khach_hang, p_gian_hang, p_kho, p_voucher,
           k.ho_ten, k.dien_thoai, k.dia_chi,
           p_kenh, p_idem, p_ngay, v_tong, v_giam, 30000
    FROM khach_hang k WHERE k.ma_khach_hang = p_khach
    RETURNING ma_don_hang INTO v_don;

    INSERT INTO chi_tiet_don_hang(ma_don_hang, ma_bien_the, so_luong, don_gia)
    SELECT v_don, b.ma_bien_the, (e->>'sl')::INT, b.gia_ban
    FROM jsonb_array_elements(p_items) e
    JOIN bien_the b ON b.ma_bien_the = (e->>'bt')::INT;

    RETURN v_don;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- TRIGGERS - BUSINESS RULES
-- =====================================================================

-- RULE 1: Voucher chi ap dung neu tong tien >= gia tri toi thieu
--         va ngay su dung (ngay dat) nam trong han voucher.
CREATE OR REPLACE FUNCTION fn_kiem_tra_voucher() RETURNS trigger AS $$
DECLARE
    v voucher%ROWTYPE;
BEGIN
    IF NEW.ma_voucher IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v FROM voucher WHERE ma_voucher = NEW.ma_voucher;

    IF NEW.tong_tien_hang < v.gia_tri_toi_thieu THEN
        RAISE EXCEPTION 'Voucher % can don toi thieu %, don hien tai chi %',
            v.ma_code, v.gia_tri_toi_thieu, NEW.tong_tien_hang;
    END IF;

    IF NEW.ngay_dat::date > v.ngay_het_han OR NEW.ngay_dat::date < v.ngay_bat_dau THEN
        RAISE EXCEPTION 'Voucher % khong con hieu luc vao ngay %', v.ma_code, NEW.ngay_dat::date;
    END IF;

    IF v.ma_gian_hang IS NOT NULL AND v.ma_gian_hang <> NEW.ma_gian_hang THEN
        RAISE EXCEPTION 'Voucher % khong ap dung cho gian hang nay', v.ma_code;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_kiem_tra_voucher
BEFORE INSERT OR UPDATE OF ma_voucher, tong_tien_hang, ngay_dat ON don_hang
FOR EACH ROW EXECUTE FUNCTION fn_kiem_tra_voucher();

-- RULE 2: Chi duoc danh gia khi don hang o trang thai DaGiao.
--         Nguoi danh gia chinh la khach dat don (suy ra qua don_hang.ma_khach_hang,
--         khong luu lai trong danh_gia de khong vi pham 2NF/3NF).
CREATE OR REPLACE FUNCTION fn_kiem_tra_danh_gia() RETURNS trigger AS $$
DECLARE
    v_trang_thai VARCHAR(20);
BEGIN
    SELECT trang_thai INTO v_trang_thai FROM don_hang WHERE ma_don_hang = NEW.ma_don_hang;

    IF v_trang_thai <> 'DaGiao' THEN
        RAISE EXCEPTION 'Don hang % o trang thai %, chi duoc danh gia khi DaGiao',
            NEW.ma_don_hang, v_trang_thai;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_kiem_tra_danh_gia
BEFORE INSERT ON danh_gia
FOR EACH ROW EXECUTE FUNCTION fn_kiem_tra_danh_gia();

-- RANG BUOC LIEN BANG: san pham trong chi tiet phai thuoc dung gian hang cua don
CREATE OR REPLACE FUNCTION fn_kiem_tra_chi_tiet() RETURNS trigger AS $$
DECLARE
    v_gh_don INT;
    v_gh_sp  INT;
BEGIN
    SELECT ma_gian_hang INTO v_gh_don FROM don_hang WHERE ma_don_hang = NEW.ma_don_hang;
    SELECT s.ma_gian_hang INTO v_gh_sp
      FROM bien_the b JOIN san_pham s ON s.ma_san_pham = b.ma_san_pham
     WHERE b.ma_bien_the = NEW.ma_bien_the;

    IF v_gh_don IS DISTINCT FROM v_gh_sp THEN
        RAISE EXCEPTION 'Bien the % thuoc gian hang %, khong thuoc gian hang % cua don %',
            NEW.ma_bien_the, v_gh_sp, v_gh_don, NEW.ma_don_hang;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_kiem_tra_chi_tiet
BEFORE INSERT OR UPDATE OF ma_don_hang, ma_bien_the ON chi_tiet_don_hang
FOR EACH ROW EXECUTE FUNCTION fn_kiem_tra_chi_tiet();

-- RULE 3: Ton kho thay doi ngay khi don doi trang thai.
--   GIU bang UPDATE co dieu kien (kha dung >= sl): nguyen tu, chong ban vuot ton
--   khi 2 giao dich chay dong thoi (row lock). Khoa theo thu tu ma_bien_the
--   de tranh deadlock voi don nhieu SKU.
CREATE OR REPLACE FUNCTION fn_cap_nhat_ton_kho() RETURNS trigger AS $$
DECLARE
    ct RECORD;
BEGIN
    -- (1) Xac nhan don: GIU hang
    IF OLD.trang_thai = 'ChoXacNhan' AND NEW.trang_thai = 'DaXacNhan' THEN
        FOR ct IN
            SELECT ma_bien_the, so_luong FROM chi_tiet_don_hang
            WHERE ma_don_hang = NEW.ma_don_hang ORDER BY ma_bien_the
        LOOP
            UPDATE ton_kho
               SET so_luong_giu = so_luong_giu + ct.so_luong
             WHERE ma_kho = NEW.ma_kho_xuat
               AND ma_bien_the = ct.ma_bien_the
               AND so_luong_vat_ly - so_luong_giu >= ct.so_luong;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Khong du ton kha dung cho bien the % tai kho %',
                    ct.ma_bien_the, NEW.ma_kho_xuat;
            END IF;

            PERFORM fn_ghi_bien_dong(NEW.ma_kho_xuat, ct.ma_bien_the, 'GIU',
                                     0, ct.so_luong, NEW.ma_don_hang, 'Giu hang khi xac nhan don');
        END LOOP;

    -- (2) Giao cho van chuyen: XUAT kho
    ELSIF OLD.trang_thai = 'DaXacNhan' AND NEW.trang_thai = 'DangGiao' THEN
        FOR ct IN
            SELECT ma_bien_the, so_luong FROM chi_tiet_don_hang
            WHERE ma_don_hang = NEW.ma_don_hang ORDER BY ma_bien_the
        LOOP
            UPDATE ton_kho
               SET so_luong_vat_ly = so_luong_vat_ly - ct.so_luong,
                   so_luong_giu    = so_luong_giu    - ct.so_luong
             WHERE ma_kho = NEW.ma_kho_xuat AND ma_bien_the = ct.ma_bien_the;

            PERFORM fn_ghi_bien_dong(NEW.ma_kho_xuat, ct.ma_bien_the, 'XUAT',
                                     -ct.so_luong, -ct.so_luong, NEW.ma_don_hang, 'Xuat kho giao van chuyen');
        END LOOP;

    -- (3) Huy don da giu hang: NHA giu
    ELSIF OLD.trang_thai = 'DaXacNhan' AND NEW.trang_thai = 'DaHuy' THEN
        FOR ct IN
            SELECT ma_bien_the, so_luong FROM chi_tiet_don_hang
            WHERE ma_don_hang = NEW.ma_don_hang ORDER BY ma_bien_the
        LOOP
            UPDATE ton_kho
               SET so_luong_giu = so_luong_giu - ct.so_luong
             WHERE ma_kho = NEW.ma_kho_xuat AND ma_bien_the = ct.ma_bien_the;

            PERFORM fn_ghi_bien_dong(NEW.ma_kho_xuat, ct.ma_bien_the, 'NHA_GIU',
                                     0, -ct.so_luong, NEW.ma_don_hang, 'Huy don, nha giu hang');
        END LOOP;

    -- (4) Huy don da xuat kho (dang giao): HOAN hang ve kho
    ELSIF OLD.trang_thai = 'DangGiao' AND NEW.trang_thai = 'DaHuy' THEN
        FOR ct IN
            SELECT ma_bien_the, so_luong FROM chi_tiet_don_hang
            WHERE ma_don_hang = NEW.ma_don_hang ORDER BY ma_bien_the
        LOOP
            UPDATE ton_kho
               SET so_luong_vat_ly = so_luong_vat_ly + ct.so_luong
             WHERE ma_kho = NEW.ma_kho_xuat AND ma_bien_the = ct.ma_bien_the;

            PERFORM fn_ghi_bien_dong(NEW.ma_kho_xuat, ct.ma_bien_the, 'HOAN',
                                     ct.so_luong, 0, NEW.ma_don_hang, 'Huy khi dang giao, hoan hang ve kho');
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cap_nhat_ton_kho
AFTER UPDATE OF trang_thai ON don_hang
FOR EACH ROW WHEN (OLD.trang_thai IS DISTINCT FROM NEW.trang_thai)
EXECUTE FUNCTION fn_cap_nhat_ton_kho();

-- PHU TRO: ghi lich su trang thai + chan chuyen trang thai sai thu tu
CREATE OR REPLACE FUNCTION fn_chuyen_trang_thai() RETURNS trigger AS $$
BEGIN
    IF NOT (
        (OLD.trang_thai = 'ChoXacNhan' AND NEW.trang_thai IN ('DaXacNhan','DaHuy')) OR
        (OLD.trang_thai = 'DaXacNhan'  AND NEW.trang_thai IN ('DangGiao','DaHuy'))  OR
        (OLD.trang_thai = 'DangGiao'   AND NEW.trang_thai IN ('DaGiao','DaHuy'))
    ) THEN
        RAISE EXCEPTION 'Khong duoc chuyen trang thai tu % sang %', OLD.trang_thai, NEW.trang_thai;
    END IF;

    INSERT INTO lich_su_trang_thai(ma_don_hang, trang_thai_cu, trang_thai_moi)
    VALUES (NEW.ma_don_hang, OLD.trang_thai, NEW.trang_thai);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_chuyen_trang_thai
BEFORE UPDATE OF trang_thai ON don_hang
FOR EACH ROW WHEN (OLD.trang_thai IS DISTINCT FROM NEW.trang_thai)
EXECUTE FUNCTION fn_chuyen_trang_thai();

-- SO CAI CHI THEM: chan sua/xoa bien dong kho
CREATE OR REPLACE FUNCTION fn_khong_sua_so_cai() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'bien_dong_kho la so cai chi them, khong duoc % ', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_khong_sua_so_cai
BEFORE UPDATE OR DELETE ON bien_dong_kho
FOR EACH ROW EXECUTE FUNCTION fn_khong_sua_so_cai();
