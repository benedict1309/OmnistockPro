-- =====================================================================
-- DU LIEU MAU LON (300.000 - 500.000 don hang, ~1 trieu dong chi tiet)
-- Chay SAU schema.sql + seed_nho.sql:
--   psql -v ON_ERROR_STOP=1 -U postgres -d ecom -f seed_lon.sql
--
-- Quy mo sinh them:
--   + 16 nha cung cap (tong 20), 16 gian hang (tong 20), 3 kho (tong 5)
--   + 240 san pham (tong 247; danh muc 9 'Sach' giu nguyen 0 san pham cho Q5)
--   + 720 bien the (tong 736)
--   + 5.000 khach hang (tong 5.006; co nhom khach >1 nam chua mua cho Q6)
--   + 3 voucher toan san (tong 6)
--   + 400.000 don hang moi (tong 400.161 don), trai tren 12 thang
--     cua ky mo phong co dinh: 2025-12-01 -> 2026-11-30
--     (NGAY CHOT KY MO PHONG = 2026-11-30 23:59:59; giu co dinh khoang ngay
--      va ham bam hashtext() de ket qua tai lap giong het nhau tren moi may,
--      khong phu thuoc ngay thuc te chay lenh),
--     co mua vu cao diem thang 10/2026 va 11/11,
--     ty le huy toan san ~11.4% (nam trong khoang 8-15%)
--   + ~1.000.000 dong chi_tiet_don_hang moi
--   + So cai bien_dong_kho day du (NHAP, GIU, XUAT, NHA_GIU, HOAN),
--     khop tuyet doi 100% voi ton_kho (v_doi_soat_kho.khop = true)
--   + Day du lich_su_trang_thai, thanh_toan, van_chuyen, danh_gia
--
-- Tinh chat:
--   * Sinh theo tap (generate_series + INSERT ... SELECT), khong dung vong lap.
--   * Bam tat dinh (hashtext) va tu don sach phan du lieu lon neu chay lai,
--     nen seed_lon.sql chay lai duoc nhieu lan tren cung DB va cho cung ket qua.
-- =====================================================================
\set ON_ERROR_STOP on
\timing on

BEGIN;

SET LOCAL synchronous_commit = off;
SET LOCAL work_mem = '64MB';
SET LOCAL maintenance_work_mem = '128MB';

-- Tam tat trigger nguoi dung de nap theo tap nhanh (FK va CHECK van hoat dong)
ALTER TABLE don_hang          DISABLE TRIGGER USER;
ALTER TABLE chi_tiet_don_hang DISABLE TRIGGER USER;
ALTER TABLE bien_dong_kho     DISABLE TRIGGER USER;
ALTER TABLE danh_gia          DISABLE TRIGGER USER;

-- ---------------------------------------------------------------------
-- 0. Neu chay lai seed_lon.sql tren DB da nap hoac sau demo_concurrency:
--    xoa phan du lieu ngoai seed_nho (ma_don_hang > 161, ma_bien_the > 16...)
--    va khoi phuc ton_kho theo dung so cai goc cua seed_nho.
--    (Dung session_replication_role = replica chi cho buoc don dep de tranh
--     quet Seq Scan tren lich_su_trang_thai/thanh_toan khi xoa 400.000 don;
--     ngay sau do tra ve origin de giu nguyen FK & CHECK khi INSERT).
-- ---------------------------------------------------------------------
SET LOCAL session_replication_role = 'replica';

DELETE FROM danh_gia           WHERE ma_don_hang > 161;
DELETE FROM van_chuyen         WHERE ma_don_hang > 161;
DELETE FROM thanh_toan         WHERE ma_don_hang > 161;
DELETE FROM lich_su_trang_thai WHERE ma_don_hang > 161;
DELETE FROM bien_dong_kho      WHERE ma_don_hang > 161
                                  OR ma_kho > 2
                                  OR ma_bien_the > 16
                                  OR ly_do IN ('Nhap kho bo sung seed_lon', 'Demo concurrency');
DELETE FROM chi_tiet_don_hang  WHERE ma_don_hang > 161;
DELETE FROM don_hang           WHERE ma_don_hang > 161;
DELETE FROM voucher            WHERE ma_voucher > 3;
DELETE FROM khach_hang         WHERE ma_khach_hang > 6;
DELETE FROM ton_kho            WHERE ma_kho > 2 OR ma_bien_the > 16;
DELETE FROM bien_the           WHERE ma_bien_the > 16;
DELETE FROM san_pham           WHERE ma_san_pham > 7;
DELETE FROM kho                WHERE ma_kho > 2;
DELETE FROM gian_hang          WHERE ma_gian_hang > 4;
DELETE FROM nha_cung_cap       WHERE ma_ncc > 4;

UPDATE ton_kho t
SET so_luong_vat_ly = COALESCE(s.vl, 0),
    so_luong_giu    = COALESCE(s.giu, 0)
FROM (
    SELECT ma_kho, ma_bien_the,
           SUM(delta_vat_ly)::INT AS vl,
           SUM(delta_giu)::INT    AS giu
    FROM bien_dong_kho
    GROUP BY ma_kho, ma_bien_the
) s
WHERE t.ma_kho = s.ma_kho AND t.ma_bien_the = s.ma_bien_the;

SET LOCAL session_replication_role = 'origin';

-- ---------------------------------------------------------------------
-- 1. Mo rong Nha cung cap (5..20), Gian hang (5..20), Kho (3..5)
-- ---------------------------------------------------------------------
INSERT INTO nha_cung_cap(ma_ncc, ten_ncc, dien_thoai, dia_chi)
SELECT g,
       'Nhà cung cấp Việt Hưng ' || lpad(g::text, 2, '0'),
       '0283800' || lpad(g::text, 4, '0'),
       (ARRAY['Quận 1, TP.HCM','Quận 3, TP.HCM','Cầu Giấy, Hà Nội','Hải Châu, Đà Nẵng','Ninh Kiều, Cần Thơ'])[1 + (g % 5)]
FROM generate_series(5, 20) AS g;
SELECT setval('nha_cung_cap_ma_ncc_seq', 20);

INSERT INTO gian_hang(ma_gian_hang, ten_gian_hang, email, ngay_tham_gia)
SELECT g,
       (ARRAY['VietTech','Sài Gòn Mall','Hà Nội Plaza','Đông Á Store','Phương Nam Shop',
              'Đại Việt Official','Tân Thời Đại','Bách Hóa Xanh Plus','MegaMart VN','Hoàng Long Store',
              'Thiên Minh Shop','An Phát Official','Phúc Lộc Store','Vạn Xuân Mall','Ánh Dương Shop','Bình Minh Official'])[g - 4]
       || ' #' || g,
       'shop' || g || '@omnistock.vn',
       DATE '2024-01-01' + ((g * 17) % 365)
FROM generate_series(5, 20) AS g;
SELECT setval('gian_hang_ma_gian_hang_seq', 20);

INSERT INTO kho(ma_kho, ten_kho, tinh_tp, dia_chi) VALUES
 (3, 'Kho Đà Nẵng',   'Đà Nẵng',   'KCN Hòa Khánh, Liên Chiểu, Đà Nẵng'),
 (4, 'Kho Cần Thơ',   'Cần Thơ',   'KCN Trà Nóc, Bình Thủy, Cần Thơ'),
 (5, 'Kho Hải Phòng', 'Hải Phòng', 'KCN VSIP, Thủy Nguyên, Hải Phòng');
SELECT setval('kho_ma_kho_seq', 5);

-- ---------------------------------------------------------------------
-- 2. Mo rong San pham (8..247: 240 san pham, moi gian hang 1..20 co them 12 SP)
--    Danh muc: chi dung danh muc 1..8 (GIU NGUYEN danh muc 9 'Sach' = 0 SP cho Q5)
-- ---------------------------------------------------------------------
INSERT INTO san_pham(ma_san_pham, ma_gian_hang, ma_danh_muc, ma_ncc, ten_san_pham, mo_ta, ngay_tao)
SELECT sp_id,
       gh_id,
       dm_id,
       ncc_id,
       CASE dm_id
           WHEN 1 THEN 'Thiết bị điện tử thông minh Model ' || sp_id
           WHEN 2 THEN 'Điện thoại thông minh Galaxy/Vina Series ' || sp_id
           WHEN 3 THEN 'Laptop văn phòng UltraBook Pro ' || sp_id
           WHEN 4 THEN 'Điện thoại cao cấp Flagship ' || sp_id
           WHEN 5 THEN 'Bộ trang phục thời trang công sở ' || sp_id
           WHEN 6 THEN 'Áo sơ mi / Áo khoác cao cấp mã ' || sp_id
           WHEN 7 THEN 'Quần âu / Quần kaki form chuẩn mã ' || sp_id
           WHEN 8 THEN 'Thiết bị gia dụng nhà bếp thông minh ' || sp_id
       END,
       'Sản phẩm chính hãng phân phối bởi gian hàng ' || gh_id,
       TIMESTAMP '2025-01-01 08:00:00' + (sp_id || ' hours')::interval
FROM (
    SELECT sp_id,
           ((sp_id - 8) % 20) + 1 AS gh_id,
           ((sp_id - 8) % 8) + 1  AS dm_id,
           -- Tranh gan them SP gia cao vao NCC 2 de Q7 (so voi max NCC 2 = 28.500.000) giu ket qua gon
           CASE WHEN ((sp_id - 8) % 20) + 1 = 2 THEN 1
                ELSE ((sp_id - 8) % 20) + 1
           END AS ncc_id
    FROM generate_series(8, 247) AS sp_id
) t;
SELECT setval('san_pham_ma_san_pham_seq', 247);

-- ---------------------------------------------------------------------
-- 3. Mo rong Bien the (17..736: 3 bien the / san pham moi = 720 bien the)
--    Gia ban duoc thiet ke:
--      * Luon > gia_nhap
--      * Moi bien the co chenh lech nho theo ma_bien_the de trong cung 1 NCC
--        luon co 1 bien the dat gia cao nhat duy nhat (phuc vu Q7b)
--      * Khong vuot moc 28.500.000 cua NCC 2 (tru bien the 5 cua seed_nho)
--        de Q7 giu nguyen tinh minh hoa ro rang.
-- ---------------------------------------------------------------------
INSERT INTO bien_the(ma_bien_the, ma_san_pham, sku, mau_sac, kich_co, gia_nhap, gia_ban)
SELECT bt_id,
       sp_id,
       'SKU-SP' || lpad(sp_id::text, 3, '0') || '-' || v_idx,
       (ARRAY['Đen','Trắng','Xanh','Xám','Bạc','Đỏ'])[1 + ((sp_id + v_idx) % 6)],
       (ARRAY['S','M','L','XL','128GB','256GB','512GB','Tiêu chuẩn'])[1 + ((sp_id * 3 + v_idx) % 8)],
       gia_goc,
       gia_goc + ROUND(gia_goc * 0.35, -3) + (bt_id * 1000)
FROM (
    SELECT 16 + (s.ma_san_pham - 8) * 3 + v_idx AS bt_id,
           s.ma_san_pham AS sp_id,
           v_idx,
           CASE
               WHEN s.ma_danh_muc IN (2, 3, 4) THEN (3000000 + ((s.ma_san_pham * 130000) % 12000000) + v_idx * 500000)::numeric(14,0)
               WHEN s.ma_danh_muc IN (1, 8)    THEN (500000  + ((s.ma_san_pham * 45000)  % 3000000)  + v_idx * 150000)::numeric(14,0)
               ELSE                                 (120000  + ((s.ma_san_pham * 15000)  % 600000)   + v_idx * 40000)::numeric(14,0)
           END AS gia_goc
    FROM san_pham s
    CROSS JOIN generate_series(1, 3) AS v_idx
    WHERE s.ma_san_pham >= 8
) sub;
SELECT setval('bien_the_ma_bien_the_seq', 736);

-- ---------------------------------------------------------------------
-- 4. Mo rong Khach hang (7..5006: 5.000 khach hang, ten & dia chi tieng Viet)
--    Khach 7..4950 se dat don; khach 4951..5006 khong dat don (trong do
--    khach 4951..4980 dang ky > 1 nam truoc de cung khach 5 phuc vu Q6).
-- ---------------------------------------------------------------------
INSERT INTO khach_hang(ma_khach_hang, ho_ten, email, dien_thoai, dia_chi, ngay_dang_ky)
SELECT cid,
       (ARRAY['Nguyễn','Trần','Lê','Phạm','Hoàng','Huỳnh','Phan','Vũ','Võ','Đặng','Bùi','Đỗ','Hồ','Ngô','Dương','Lý'])[1 + (cid % 16)]
       || ' ' ||
       (ARRAY['Văn','Thị','Minh','Hoàng','Quốc','Thanh','Ngọc','Đức','Gia','Thu','Hữu','Tuấn','Phương','Anh','Bảo'])[1 + ((cid * 7) % 15)]
       || ' ' ||
       (ARRAY['An','Bình','Châu','Dũng','Đạt','Giang','Hải','Hùng','Hương','Khánh','Lan','Linh','Long','Mai','Nam',
              'Nga','Nhung','Oanh','Phúc','Quân','Quỳnh','Sơn','Tâm','Thảo','Thắng','Thịnh','Trang','Trinh','Tú','Việt','Vy','Yến'])[1 + ((cid * 13) % 32)],
       'khachhang' || cid || '@mail.vn',
       '09' || lpad((10000000 + cid)::text, 8, '0'),
       'Số ' || ((cid % 300) + 1) || ' đường ' ||
       (ARRAY['Lê Lợi','Nguyễn Huệ','Trần Hưng Đạo','Hai Bà Trưng','Điện Biên Phủ','Cách Mạng Tháng 8','Nguyễn Trãi','Lý Thường Kiệt','Phan Đình Phùng','Võ Văn Tần'])[1 + (cid % 10)]
       || ', ' ||
       (ARRAY['Quận 1, TP.HCM','Quận 7, TP.HCM','Thủ Đức, TP.HCM','Cầu Giấy, Hà Nội','Đống Đa, Hà Nội',
              'Hà Đông, Hà Nội','Hải Châu, Đà Nẵng','Ninh Kiều, Cần Thơ','Lê Chân, Hải Phòng','TP. Biên Hòa, Đồng Nai'])[1 + ((cid / 10) % 10)],
       CASE
           WHEN cid BETWEEN 4951 AND 4980 THEN DATE '2024-06-01' + (cid % 180)
           WHEN cid > 4980                THEN DATE '2026-06-01' + (cid % 120)
           ELSE                                DATE '2024-01-01' + ((cid * 7) % 680)
       END
FROM generate_series(7, 5006) AS cid;
SELECT setval('khach_hang_ma_khach_hang_seq', 5006);

-- ---------------------------------------------------------------------
-- 5. Mo rong Voucher (4..6: voucher toan san hieu luc 2025-2026)
-- ---------------------------------------------------------------------
INSERT INTO voucher(ma_voucher, ma_code, ma_gian_hang, phan_tram_giam, gia_tri_toi_thieu, giam_toi_da, ngay_bat_dau, ngay_het_han) VALUES
 (4, 'OMNI5',   NULL,  5,   500000,  200000, DATE '2025-01-01', DATE '2026-12-31'),
 (5, 'OMNI10',  NULL, 10,  2000000,  500000, DATE '2025-01-01', DATE '2026-12-31'),
 (6, 'OMNIVIP', NULL, 15, 10000000, 1500000, DATE '2025-01-01', DATE '2026-12-31');
SELECT setval('voucher_ma_voucher_seq', 6);

-- ---------------------------------------------------------------------
-- 6. Bang tam anh xa (ma_gian_hang, thu_tu) -> (ma_bien_the, gia_ban)
--    de sinh nhanh 400.000 don va ~1.000.000 dong chi tiet ma:
--      * 100% dong chi tiet thuoc dung ma_gian_hang cua don (trg_kiem_tra_chi_tiet)
--      * Khong bao gio trung (ma_don_hang, ma_bien_the) trong cung 1 don
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_bt_gian_hang AS
SELECT s.ma_gian_hang,
       ROW_NUMBER() OVER (PARTITION BY s.ma_gian_hang ORDER BY b.ma_bien_the)::INT AS rn,
       COUNT(*)     OVER (PARTITION BY s.ma_gian_hang)::INT                        AS cnt,
       b.ma_bien_the,
       b.gia_ban
FROM bien_the b
JOIN san_pham s ON s.ma_san_pham = b.ma_san_pham;

CREATE UNIQUE INDEX idx_tmp_bt_gh ON tmp_bt_gian_hang(ma_gian_hang, rn);
ANALYZE tmp_bt_gian_hang;

-- ---------------------------------------------------------------------
-- 7. Sinh khung 400.000 don hang (ma_don_hang 162..400161)
--    Dung ham bam hashtext() tat dinh de phan bo tu nhien giua cac gian hang,
--    khach hang, kho, ngay dat va trang thai:
--      * ~70% don rai deu tu 2025-12-01 den 2026-09-30 (10 thang)
--      * ~14% don (~56.000 don) trong thang 10/2026 (cao diem thang 10)
--      * ~16% don (~64.000 don) trong thang 11/2026 (cao diem sieu sale 11.11)
--    Ty le huy:
--      * Gian hang 1..12: ty le huy ~13.0% - 14.5% (> 10% de xuat hien trong Q4)
--      * Gian hang 13..20: ty le huy ~7.5% - 8.5% (< 10% de Q4 loc bo)
--      * Toan san: trung binh ~11.4% (nam trong khoang 8-15% cua brief)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_don_khung AS
SELECT oid AS ma_don_hang,
       CASE
           WHEN (h1 % 2000) = 0 THEN 1  -- Khach Nguyen Van A co them ~200 don
           ELSE 7 + (h1 % 4944)
       END AS ma_khach_hang,
       gh_id AS ma_gian_hang,
       1 + (h2 % 5) AS ma_kho_xuat,
       (ARRAY['Web','CuaHang','DoiTac'])[1 + (h3 % 3)] AS kenh_ban,
       ngay_dat,
       trang_thai,
       -- so dong chi tiet: 20% 1 dong, 30% 2 dong, 30% 3 dong, 20% 4 dong => TB 2.5 dong/don = ~1.000.000 dong
       CASE (oid % 10)
           WHEN 0 THEN 1 WHEN 1 THEN 1
           WHEN 2 THEN 2 WHEN 3 THEN 2 WHEN 4 THEN 2
           WHEN 5 THEN 3 WHEN 6 THEN 3 WHEN 7 THEN 3
           ELSE 4
       END AS so_dong,
       (h2 % 97) AS bt_offset
FROM (
    SELECT oid,
           gh_id,
           h1, h2, h3,
           -- Ngay dat co mua vu
           CASE
               WHEN bucket < 700 THEN
                   TIMESTAMP '2025-12-01 00:00:00'
                   + ((h1 % 304) || ' days')::interval
                   + ((h2 % 86400) || ' seconds')::interval
               WHEN bucket < 840 THEN
                   TIMESTAMP '2026-10-01 00:00:00'
                   + ((h1 % 31) || ' days')::interval
                   + ((h2 % 86400) || ' seconds')::interval
               WHEN bucket < 900 THEN
                   -- Rieng ngay 11/11 cao diem
                   TIMESTAMP '2026-11-11 00:00:00'
                   + ((h2 % 86400) || ' seconds')::interval
               ELSE
                   TIMESTAMP '2026-11-01 00:00:00'
                   + ((h1 % 30) || ' days')::interval
                   + ((h2 % 86400) || ' seconds')::interval
           END AS ngay_dat,
           -- Trang thai don
           CASE
               WHEN gh_id <= 12 THEN
                   CASE
                       WHEN st_roll < 680 THEN 'DaGiao'
                       WHEN st_roll < 815 THEN 'DaHuy'       -- ~13.5% huy (>10%)
                       WHEN st_roll < 900 THEN 'DangGiao'
                       WHEN st_roll < 955 THEN 'DaXacNhan'
                       ELSE                    'ChoXacNhan'
                   END
               ELSE
                   CASE
                       WHEN st_roll < 720 THEN 'DaGiao'
                       WHEN st_roll < 800 THEN 'DaHuy'       -- ~8.0% huy (<10%)
                       WHEN st_roll < 895 THEN 'DangGiao'
                       WHEN st_roll < 955 THEN 'DaXacNhan'
                       ELSE                    'ChoXacNhan'
                   END
           END AS trang_thai
    FROM (
        SELECT oid,
               1 + (abs(hashtext('gh-' || oid::text)) % 20)     AS gh_id,
               abs(hashtext('h1-' || oid::text))                AS h1,
               abs(hashtext('h2-' || oid::text))                AS h2,
               abs(hashtext('h3-' || oid::text))                AS h3,
               abs(hashtext('bk-' || oid::text)) % 1000         AS bucket,
               abs(hashtext('st-' || oid::text)) % 1000         AS st_roll
        FROM generate_series(162, 400161) AS oid
    ) raw
) framed;

CREATE UNIQUE INDEX idx_tmp_don_khung ON tmp_don_khung(ma_don_hang);
ANALYZE tmp_don_khung;

-- ---------------------------------------------------------------------
-- 8. Sinh ~1.000.000 dong chi_tiet_don_hang vao bang tam truoc de tinh
--    chinh xac tong_tien_hang cho tung don hang
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_ctdh AS
SELECT d.ma_don_hang,
       m.ma_bien_the,
       1 + ((d.ma_don_hang + k.dong_thu) % 3) AS so_luong,
       m.gia_ban                              AS don_gia
FROM tmp_don_khung d
CROSS JOIN LATERAL generate_series(1, d.so_dong) AS k(dong_thu)
JOIN tmp_bt_gian_hang m
  ON m.ma_gian_hang = d.ma_gian_hang
 AND m.rn = ((d.bt_offset + k.dong_thu * 7) % m.cnt) + 1;

ANALYZE tmp_ctdh;

CREATE TEMP TABLE tmp_tong_don AS
SELECT ma_don_hang,
       SUM(so_luong * don_gia)::numeric(14,0) AS tong_tien_hang
FROM tmp_ctdh
GROUP BY ma_don_hang;

CREATE UNIQUE INDEX idx_tmp_tong_don ON tmp_tong_don(ma_don_hang);
ANALYZE tmp_tong_don;

-- ---------------------------------------------------------------------
-- 9. Nap bang don_hang (400.000 don moi) va chi_tiet_don_hang (1.000.000 dong)
-- ---------------------------------------------------------------------
INSERT INTO don_hang(
    ma_don_hang, ma_khach_hang, ma_gian_hang, ma_kho_xuat, ma_voucher,
    nguoi_nhan, dien_thoai_nhan, dia_chi_giao,
    kenh_ban, idempotency_key, ngay_dat, trang_thai,
    tong_tien_hang, tien_giam, phi_van_chuyen
)
SELECT d.ma_don_hang,
       d.ma_khach_hang,
       d.ma_gian_hang,
       d.ma_kho_xuat,
       vc.ma_voucher,
       k.ho_ten,
       k.dien_thoai,
       k.dia_chi,
       d.kenh_ban,
       'idem-bulk-' || d.ma_don_hang,
       d.ngay_dat,
       d.trang_thai,
       t.tong_tien_hang,
       COALESCE(vc.tien_giam, 0),
       CASE (d.ma_don_hang % 3) WHEN 0 THEN 15000 WHEN 1 THEN 30000 ELSE 45000 END
FROM tmp_don_khung d
JOIN tmp_tong_don t ON t.ma_don_hang = d.ma_don_hang
JOIN khach_hang k   ON k.ma_khach_hang = d.ma_khach_hang
LEFT JOIN LATERAL (
    SELECT CASE
               WHEN (d.ma_don_hang % 3) = 0 AND t.tong_tien_hang >= 10000000 THEN 6
               WHEN (d.ma_don_hang % 3) = 0 AND t.tong_tien_hang >= 2000000  THEN 5
               WHEN (d.ma_don_hang % 3) = 0 AND t.tong_tien_hang >= 500000   THEN 4
               ELSE NULL
           END AS ma_voucher,
           CASE
               WHEN (d.ma_don_hang % 3) = 0 AND t.tong_tien_hang >= 10000000
                   THEN LEAST(ROUND(t.tong_tien_hang * 0.15), 1500000)::numeric(14,0)
               WHEN (d.ma_don_hang % 3) = 0 AND t.tong_tien_hang >= 2000000
                   THEN LEAST(ROUND(t.tong_tien_hang * 0.10), 500000)::numeric(14,0)
               WHEN (d.ma_don_hang % 3) = 0 AND t.tong_tien_hang >= 500000
                   THEN LEAST(ROUND(t.tong_tien_hang * 0.05), 200000)::numeric(14,0)
               ELSE 0::numeric(14,0)
           END AS tien_giam
) vc ON TRUE;

SELECT setval('don_hang_ma_don_hang_seq', 400161);

INSERT INTO chi_tiet_don_hang(ma_don_hang, ma_bien_the, so_luong, don_gia)
SELECT ma_don_hang, ma_bien_the, so_luong, don_gia
FROM tmp_ctdh;

-- ---------------------------------------------------------------------
-- 10. Cap nhat ton_kho va so cai bien_dong_kho dam bao khop 100%
--     Quy tac so cai cho don moi (ma_don_hang > 161):
--       * ChoXacNhan : khong co bien dong kho
--       * DaXacNhan  : GIU (0, +sl)
--       * DangGiao   : GIU (0, +sl) + XUAT (-sl, -sl)
--       * DaGiao     : GIU (0, +sl) + XUAT (-sl, -sl)
--       * DaHuy      :
--           - (ma_don_hang % 5) IN (0,1): huy tu ChoXacNhan -> khong co bien dong
--           - (ma_don_hang % 5) IN (2,3): huy tu DaXacNhan  -> GIU (0,+sl) + NHA_GIU (0,-sl)
--           - (ma_don_hang % 5) = 4     : huy tu DangGiao   -> GIU (0,+sl) + XUAT (-sl,-sl) + HOAN (+sl,0)
-- ---------------------------------------------------------------------

-- 10a. Khoi tao dong ton_kho = 0 cho cac cap (ma_kho, ma_bien_the) chua co
INSERT INTO ton_kho(ma_kho, ma_bien_the, so_luong_vat_ly, so_luong_giu)
SELECT k.ma_kho, b.ma_bien_the, 0, 0
FROM kho k
CROSS JOIN bien_the b
ON CONFLICT (ma_kho, ma_bien_the) DO NOTHING;

-- 10b. Tinh nhu cau xuat + giu theo tung (ma_kho, ma_bien_the) va NHAP kho du lon
INSERT INTO bien_dong_kho(ma_kho, ma_bien_the, loai, delta_vat_ly, delta_giu, ma_don_hang, ly_do, thoi_diem)
SELECT k.ma_kho,
       b.ma_bien_the,
       'NHAP',
       COALESCE(nhu_cau.tong_can, 0) + 500,
       0,
       NULL,
       'Nhap kho bo sung seed_lon',
       TIMESTAMP '2025-11-25 08:00:00'
FROM kho k
CROSS JOIN bien_the b
LEFT JOIN (
    SELECT d.ma_kho_xuat AS ma_kho,
           c.ma_bien_the,
           SUM(c.so_luong)::INT AS tong_can
    FROM tmp_don_khung d
    JOIN tmp_ctdh c ON c.ma_don_hang = d.ma_don_hang
    WHERE d.trang_thai IN ('DaXacNhan', 'DangGiao', 'DaGiao')
       OR (d.trang_thai = 'DaHuy' AND (d.ma_don_hang % 5) IN (2, 3, 4))
    GROUP BY d.ma_kho_xuat, c.ma_bien_the
) nhu_cau ON nhu_cau.ma_kho = k.ma_kho AND nhu_cau.ma_bien_the = b.ma_bien_the;

-- 10c. Ghi tat ca bien dong GIU, XUAT, NHA_GIU, HOAN trong 1 luot quet
INSERT INTO bien_dong_kho(ma_kho, ma_bien_the, loai, delta_vat_ly, delta_giu, ma_don_hang, ly_do, thoi_diem)
SELECT d.ma_kho_xuat,
       c.ma_bien_the,
       ev.loai,
       ev.d_vl,
       ev.d_giu,
       d.ma_don_hang,
       ev.ly_do,
       ev.thoi_diem
FROM tmp_don_khung d
JOIN tmp_ctdh c ON c.ma_don_hang = d.ma_don_hang
CROSS JOIN LATERAL (
    VALUES
        ('GIU', 0, c.so_luong, 'Giu hang khi xac nhan don', d.ngay_dat + INTERVAL '15 minutes',
         d.trang_thai IN ('DaXacNhan', 'DangGiao', 'DaGiao') OR (d.trang_thai = 'DaHuy' AND (d.ma_don_hang % 5) IN (2, 3, 4))),
        ('XUAT', -c.so_luong, -c.so_luong, 'Xuat kho giao van chuyen', d.ngay_dat + INTERVAL '2 hours',
         d.trang_thai IN ('DangGiao', 'DaGiao') OR (d.trang_thai = 'DaHuy' AND (d.ma_don_hang % 5) = 4)),
        ('NHA_GIU', 0, -c.so_luong, 'Huy don, nha giu hang', d.ngay_dat + INTERVAL '3 hours',
         d.trang_thai = 'DaHuy' AND (d.ma_don_hang % 5) IN (2, 3)),
        ('HOAN', c.so_luong, 0, 'Huy khi dang giao, hoan hang ve kho', d.ngay_dat + INTERVAL '1 day',
         d.trang_thai = 'DaHuy' AND (d.ma_don_hang % 5) = 4)
) AS ev(loai, d_vl, d_giu, ly_do, thoi_diem, co_ghi)
WHERE ev.co_ghi;

-- 10d. Dong bo ton_kho tu tong so cai bien_dong_kho
UPDATE ton_kho t
SET so_luong_vat_ly = s.vl,
    so_luong_giu    = s.giu
FROM (
    SELECT ma_kho, ma_bien_the,
           SUM(delta_vat_ly)::INT AS vl,
           SUM(delta_giu)::INT    AS giu
    FROM bien_dong_kho
    GROUP BY ma_kho, ma_bien_the
) s
WHERE t.ma_kho = s.ma_kho AND t.ma_bien_the = s.ma_bien_the;

-- ---------------------------------------------------------------------
-- 11. Lich su trang thai, Thanh toan, Van chuyen, Danh gia
-- ---------------------------------------------------------------------
INSERT INTO lich_su_trang_thai(ma_don_hang, trang_thai_cu, trang_thai_moi, thoi_diem)
SELECT d.ma_don_hang, ls.tt_cu, ls.tt_moi, ls.thoi_diem
FROM tmp_don_khung d
CROSS JOIN LATERAL (
    VALUES
        ('ChoXacNhan', 'DaXacNhan', d.ngay_dat + INTERVAL '15 minutes',
         d.trang_thai IN ('DaXacNhan', 'DangGiao', 'DaGiao') OR (d.trang_thai = 'DaHuy' AND (d.ma_don_hang % 5) IN (2, 3, 4))),
        ('DaXacNhan', 'DangGiao', d.ngay_dat + INTERVAL '2 hours',
         d.trang_thai IN ('DangGiao', 'DaGiao') OR (d.trang_thai = 'DaHuy' AND (d.ma_don_hang % 5) = 4)),
        ('DangGiao', 'DaGiao', d.ngay_dat + INTERVAL '3 days',
         d.trang_thai = 'DaGiao'),
        (CASE
             WHEN (d.ma_don_hang % 5) IN (0, 1) THEN 'ChoXacNhan'
             WHEN (d.ma_don_hang % 5) IN (2, 3) THEN 'DaXacNhan'
             ELSE 'DangGiao'
         END, 'DaHuy', d.ngay_dat + INTERVAL '1 day',
         d.trang_thai = 'DaHuy')
) AS ls(tt_cu, tt_moi, thoi_diem, co_ghi)
WHERE ls.co_ghi;

INSERT INTO thanh_toan(ma_don_hang, phuong_thuc, so_tien, trang_thai, thoi_diem)
SELECT d.ma_don_hang,
       (ARRAY['COD','ChuyenKhoan','TheTinDung','ViDienTu'])[1 + (d.ma_don_hang % 4)],
       d.tong_tien_hang - d.tien_giam + d.phi_van_chuyen,
       CASE d.trang_thai
           WHEN 'DaGiao' THEN 'ThanhCong'
           WHEN 'DaHuy'  THEN 'ThatBai'
           ELSE 'ChoThanhToan'
       END,
       d.ngay_dat + INTERVAL '5 minutes'
FROM don_hang d
WHERE d.ma_don_hang > 161 AND d.trang_thai <> 'ChoXacNhan';

INSERT INTO van_chuyen(ma_don_hang, don_vi_vc, ma_van_don, ngay_giao_du_kien, ngay_giao_thuc_te)
SELECT d.ma_don_hang,
       (ARRAY['GHN','GHTK','ViettelPost','J&T Express'])[1 + (d.ma_don_hang % 4)],
       'VD' || lpad(d.ma_don_hang::text, 8, '0'),
       d.ngay_dat::date + 3,
       CASE WHEN d.trang_thai = 'DaGiao' THEN d.ngay_dat::date + 2 + (d.ma_don_hang % 3) END
FROM tmp_don_khung d
WHERE d.trang_thai IN ('DangGiao', 'DaGiao');

-- Danh gia: ~20% dong chi tiet cua don DaGiao (~140.000 danh gia)
-- San pham 1, 2 (seed_nho) va cac san pham dien thoai co ma_san_pham <= 20 duoc danh gia 4-5 sao (TB >= 4.5 cho Q1)
INSERT INTO danh_gia(ma_don_hang, ma_bien_the, so_sao, noi_dung, ngay_danh_gia)
SELECT c.ma_don_hang,
       c.ma_bien_the,
       CASE
           WHEN b.ma_san_pham IN (1, 2) OR b.ma_san_pham <= 20
               THEN CASE WHEN (c.ma_don_hang + c.ma_bien_the) % 5 = 0 THEN 4 ELSE 5 END
           ELSE 3 + ((c.ma_don_hang + c.ma_bien_the) % 3)
       END,
       (ARRAY[
           'Sản phẩm đúng mô tả, đóng gói cẩn thận, giao hàng nhanh.',
           'Chất lượng tốt trong tầm giá, sẽ ủng hộ shop lần sau.',
           'Hàng chính hãng, nguyên seal, nhân viên tư vấn nhiệt tình.',
           'Giao hàng đúng hẹn, sản phẩm hoạt động ổn định.'
       ])[1 + ((c.ma_don_hang + c.ma_bien_the) % 4)],
       d.ngay_dat + INTERVAL '5 days'
FROM tmp_ctdh c
JOIN tmp_don_khung d ON d.ma_don_hang = c.ma_don_hang
JOIN bien_the b      ON b.ma_bien_the = c.ma_bien_the
WHERE d.trang_thai = 'DaGiao'
  AND (c.ma_don_hang % 5) = 0;

DROP TABLE tmp_ctdh;
DROP TABLE tmp_tong_don;
DROP TABLE tmp_don_khung;
DROP TABLE tmp_bt_gian_hang;

-- Bat lai toan bo trigger nguoi dung
ALTER TABLE don_hang          ENABLE TRIGGER USER;
ALTER TABLE chi_tiet_don_hang ENABLE TRIGGER USER;
ALTER TABLE bien_dong_kho     ENABLE TRIGGER USER;
ALTER TABLE danh_gia          ENABLE TRIGGER USER;

COMMIT;

-- Cap nhat thong ke cho query planner
ANALYZE;

-- ---------------------------------------------------------------------
-- 12. Kiem tra bat bien bat buoc ngay sau khi nap
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_khop BOOLEAN;
    v_lech_tien INT;
    v_vi_pham_ton INT;
    v_tong_don BIGINT;
    v_tong_ct BIGINT;
BEGIN
    SELECT bool_and(khop) INTO v_khop FROM v_doi_soat_kho;
    IF v_khop IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FAIL: v_doi_soat_kho khong khop!';
    END IF;

    SELECT COUNT(*) INTO v_lech_tien
    FROM (
        SELECT d.ma_don_hang
        FROM don_hang d
        JOIN chi_tiet_don_hang c USING (ma_don_hang)
        GROUP BY d.ma_don_hang, d.tong_tien_hang
        HAVING SUM(c.so_luong * c.don_gia) <> d.tong_tien_hang
    ) x;
    IF v_lech_tien <> 0 THEN
        RAISE EXCEPTION 'FAIL: Co % don hang lech tong_tien_hang!', v_lech_tien;
    END IF;

    SELECT COUNT(*) INTO v_vi_pham_ton
    FROM ton_kho
    WHERE NOT (0 <= so_luong_giu AND so_luong_giu <= so_luong_vat_ly);
    IF v_vi_pham_ton <> 0 THEN
        RAISE EXCEPTION 'FAIL: Co % dong ton_kho vi pham 0 <= giu <= vat_ly!', v_vi_pham_ton;
    END IF;

    SELECT COUNT(*) INTO v_tong_don FROM don_hang;
    SELECT COUNT(*) INTO v_tong_ct  FROM chi_tiet_don_hang;
    RAISE NOTICE 'OK seed_lon: don_hang = %, chi_tiet_don_hang = %, bool_and(khop) = %',
        v_tong_don, v_tong_ct, v_khop;
END $$;
