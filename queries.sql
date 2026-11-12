-- =====================================================================
-- 8 TRUY VAN THEO DE (PostgreSQL)  -- chay sau schema.sql + seed_nho.sql
-- Chay tung cau trong psql/DBeaver, hoac ca file: psql -d ecom -f queries.sql
-- Quy uoc:
--   * Doanh thu thuan = tong_tien_hang - tien_giam (khong gom phi van chuyen),
--     chi tinh don DaGiao.
--   * Trang thai huy trong CSDL la 'DaHuy' (de ghi 'Cancelled').
-- =====================================================================
\set ON_ERROR_STOP on
-- Q7: ma nha cung cap X (doi gia tri nay de thu)
\set ncc_x 2
-- Q8: nguong doanh thu luy ke mac dinh = 1 ty VND theo de (co the truyen -v moc_q8=500000000000 tren seed_lon)
\if :{?moc_q8}
\else
\set moc_q8 1000000000
\endif

-- ---------------------------------------------------------------------
-- Q1. CO BAN: san pham thuoc danh muc "Dien thoai" co diem danh gia
--     trung binh >= 4.5. Lay ca danh muc con (vd "Dien thoai cao cap")
--     bang CTE de quy.
-- ---------------------------------------------------------------------
\echo '=== Q1: San pham Dien thoai co diem TB >= 4.5 ==='
WITH RECURSIVE cay AS (
    SELECT ma_danh_muc FROM danh_muc WHERE ten_danh_muc = 'Điện thoại'
    UNION ALL
    SELECT c.ma_danh_muc FROM danh_muc c JOIN cay ON c.ma_danh_muc_cha = cay.ma_danh_muc
)
SELECT s.ma_san_pham,
       s.ten_san_pham,
       ROUND(AVG(g.so_sao), 2) AS diem_trung_binh,
       COUNT(g.ma_danh_gia)    AS so_luot_danh_gia
FROM san_pham s
JOIN cay            ON cay.ma_danh_muc = s.ma_danh_muc
JOIN bien_the b     ON b.ma_san_pham = s.ma_san_pham
JOIN danh_gia g     ON g.ma_bien_the = b.ma_bien_the
GROUP BY s.ma_san_pham, s.ten_san_pham
HAVING AVG(g.so_sao) >= 4.5
ORDER BY diem_trung_binh DESC, s.ma_san_pham;

-- ---------------------------------------------------------------------
-- Q2. INNER JOIN: chi tiet don hang cua khach "Nguyen Van A"
-- ---------------------------------------------------------------------
\echo '=== Q2: Chi tiet don hang cua Nguyen Van A (10 dong dau) ==='
SELECT d.ma_don_hang,
       d.ngay_dat::date AS ngay_dat,
       d.trang_thai,
       s.ten_san_pham,
       b.mau_sac,
       b.kich_co,
       c.so_luong,
       c.don_gia AS gia_ban
FROM khach_hang k
JOIN don_hang d          ON d.ma_khach_hang = k.ma_khach_hang
JOIN chi_tiet_don_hang c ON c.ma_don_hang   = d.ma_don_hang
JOIN bien_the b          ON b.ma_bien_the   = c.ma_bien_the
JOIN san_pham s          ON s.ma_san_pham   = b.ma_san_pham
WHERE k.ho_ten = 'Nguyễn Văn A'
ORDER BY d.ngay_dat, d.ma_don_hang, s.ten_san_pham
LIMIT 10;

-- ---------------------------------------------------------------------
-- Q3. GROUP BY + AGGREGATE: doanh thu thuan tung gian hang thang 10/2026
--     LEFT JOIN de gian hang chua co don van hien thi (0 dong).
-- ---------------------------------------------------------------------
\echo '=== Q3: Doanh thu thuan tung gian hang, thang 10/2026 ==='
SELECT g.ma_gian_hang,
       g.ten_gian_hang,
       COUNT(d.ma_don_hang)                                  AS so_don_da_giao,
       COALESCE(SUM(d.tong_tien_hang), 0)                    AS doanh_thu_truoc_giam,
       COALESCE(SUM(d.tien_giam), 0)                         AS tong_voucher,
       COALESCE(SUM(d.tong_tien_hang - d.tien_giam), 0)      AS doanh_thu_thuan
FROM gian_hang g
LEFT JOIN don_hang d
       ON d.ma_gian_hang = g.ma_gian_hang
      AND d.trang_thai = 'DaGiao'
      AND d.ngay_dat >= DATE '2026-10-01'
      AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
ORDER BY doanh_thu_thuan DESC;

-- ---------------------------------------------------------------------
-- Q4. HAVING: gian hang co don huy chiem tren 10% tong so don nhan duoc
--     trong thang (thang 10/2026).
-- ---------------------------------------------------------------------
\echo '=== Q4: Gian hang co ty le huy > 10% (thang 10/2026) ==='
SELECT g.ma_gian_hang,
       g.ten_gian_hang,
       COUNT(*)                                              AS tong_don,
       COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy')        AS don_huy,
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') / COUNT(*), 2) AS ty_le_huy_pct
FROM gian_hang g
JOIN don_hang d ON d.ma_gian_hang = g.ma_gian_hang
WHERE d.ngay_dat >= DATE '2026-10-01'
  AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
HAVING COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') * 10 > COUNT(*)   -- huy/tong > 10%
ORDER BY ty_le_huy_pct DESC;

-- ---------------------------------------------------------------------
-- Q5. OUTER JOIN: moi danh muc cap 1 + so san pham va ton kho (gom ca
--     danh muc con, ke ca danh muc chua co san pham nao).
--     CTE de quy gan moi danh muc ve danh muc goc (cap 1) cua no.
-- ---------------------------------------------------------------------
\echo '=== Q5: Danh muc cap 1 va ton kho ==='
WITH RECURSIVE goc AS (
    SELECT ma_danh_muc, ma_danh_muc AS ma_goc FROM danh_muc WHERE ma_danh_muc_cha IS NULL
    UNION ALL
    SELECT c.ma_danh_muc, goc.ma_goc FROM danh_muc c JOIN goc ON c.ma_danh_muc_cha = goc.ma_danh_muc
),
ton AS (   -- ton theo tung san pham (cong don moi kho, moi bien the)
    SELECT b.ma_san_pham,
           COUNT(DISTINCT b.ma_bien_the)                 AS so_bien_the,
           SUM(t.so_luong_vat_ly)                        AS ton_vat_ly,
           SUM(t.so_luong_vat_ly - t.so_luong_giu)       AS ton_kha_dung
    FROM bien_the b
    JOIN ton_kho t ON t.ma_bien_the = b.ma_bien_the
    GROUP BY b.ma_san_pham
)
SELECT dm.ma_danh_muc,
       dm.ten_danh_muc,
       COUNT(DISTINCT s.ma_san_pham)       AS so_san_pham,
       COALESCE(SUM(ton.ton_vat_ly), 0)    AS ton_vat_ly,
       COALESCE(SUM(ton.ton_kha_dung), 0)  AS ton_kha_dung
FROM danh_muc dm
LEFT JOIN goc        ON goc.ma_goc = dm.ma_danh_muc
LEFT JOIN san_pham s ON s.ma_danh_muc = goc.ma_danh_muc
LEFT JOIN ton        ON ton.ma_san_pham = s.ma_san_pham
WHERE dm.ma_danh_muc_cha IS NULL
GROUP BY dm.ma_danh_muc, dm.ten_danh_muc
ORDER BY dm.ma_danh_muc;

-- ---------------------------------------------------------------------
-- Q6. NOT EXISTS: khach dang ky tren 1 nam nhung chua tung dat don nao
-- ---------------------------------------------------------------------
\echo '=== Q6: Khach dang ky > 1 nam, chua tung dat don ==='
SELECT k.ma_khach_hang, k.ho_ten, k.email, k.ngay_dang_ky
FROM khach_hang k
WHERE k.ngay_dang_ky < CURRENT_DATE - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM don_hang d WHERE d.ma_khach_hang = k.ma_khach_hang)
ORDER BY k.ngay_dang_ky;

-- ---------------------------------------------------------------------
-- Q7. COMPLEX SUBQUERY: mat hang (bien the) co gia ban cao hon TAT CA
--     mat hang cua nha cung cap X (bien :ncc_x o dau file).
--     Doc 2 (7b) la cach hieu khac cua de: mat hang dat gia cao nhat
--     trong chinh nha cung cap cua no.
-- ---------------------------------------------------------------------
\echo '=== Q7: Mat hang co gia cao hon tat ca mat hang cua NCC X ==='
SELECT s.ten_san_pham, b.sku, b.mau_sac, b.kich_co, b.gia_ban, n.ten_ncc AS nha_cung_cap
FROM bien_the b
JOIN san_pham s     ON s.ma_san_pham = b.ma_san_pham
JOIN nha_cung_cap n ON n.ma_ncc = s.ma_ncc
WHERE b.gia_ban > ALL (
        SELECT b2.gia_ban
        FROM bien_the b2
        JOIN san_pham s2 ON s2.ma_san_pham = b2.ma_san_pham
        WHERE s2.ma_ncc = :ncc_x
      )
ORDER BY b.gia_ban DESC;

\echo '=== Q7b: Mat hang co gia cao hon moi mat hang khac cung NCC cua no ==='
SELECT s.ten_san_pham, b.sku, b.gia_ban, n.ten_ncc AS nha_cung_cap
FROM bien_the b
JOIN san_pham s     ON s.ma_san_pham = b.ma_san_pham
JOIN nha_cung_cap n ON n.ma_ncc = s.ma_ncc
WHERE b.gia_ban > ALL (
        SELECT b2.gia_ban
        FROM bien_the b2
        JOIN san_pham s2 ON s2.ma_san_pham = b2.ma_san_pham
        WHERE s2.ma_ncc = s.ma_ncc AND b2.ma_bien_the <> b.ma_bien_the
      )
ORDER BY n.ten_ncc;

-- ---------------------------------------------------------------------
-- Q8. WINDOW FUNCTION + CTE: doanh thu luy ke tung ngay trong thang
--     (toan san) va ngay dau tien cham moc 1 ty VND.
--     PARTITION BY thang => cung cau tinh duoc cho nhieu thang.
--     Phan biet ket qua tren 2 bo du lieu:
--       * Tren seed_nho.sql (161 don, doanh thu thang 10 = 1.547.421.000 VND):
--         doanh thu luy ke tang dan va cham moc 1 ty VND vao ngay 2026-10-18
--         (luy_ke = 1.074.597.000 VND).
--       * Tren seed_lon.sql (400.161 don, doanh thu thang 10 = 1.216.498.566.200 VND):
--         ngay 2026-10-01 da dat 39.180.680.150 VND (~39,18 ty VND) nen cham moc
--         1 ty VND ngay ngay dau thang (2026-10-01).
--       * De quan sat qua trinh luy ke nhieu ngay khi da nap seed_lon.sql:
--         (a) Xem Q8a ben duoi (loc 161 don goc cua seed_nho -> cham moc 1 ty ngay 18/10), hoac
--         (b) Truyen tham so nguong: psql -v moc_q8=500000000000 -d ecom -f queries.sql
--             (nguong 500 ty VND tren seed_lon cham moc vao ngay 2026-10-13).
-- ---------------------------------------------------------------------
\echo '=== Q8: Doanh thu luy ke thang 10/2026 va moc 1 ty (mac dinh :moc_q8 = 1.000.000.000 VND) ==='
WITH doanh_thu_ngay AS (
    SELECT d.ngay_dat::date                           AS ngay,
           DATE_TRUNC('month', d.ngay_dat)::date      AS thang,
           SUM(d.tong_tien_hang - d.tien_giam)        AS doanh_thu
    FROM don_hang d
    WHERE d.trang_thai = 'DaGiao'
      AND d.ngay_dat >= DATE '2026-10-01'
      AND d.ngay_dat <  DATE '2026-11-01'
    GROUP BY d.ngay_dat::date, DATE_TRUNC('month', d.ngay_dat)::date
),
luy_ke AS (
    SELECT ngay, thang, doanh_thu,
           SUM(doanh_thu) OVER (PARTITION BY thang ORDER BY ngay) AS luy_ke
    FROM doanh_thu_ngay
)
SELECT ngay,
       doanh_thu,
       luy_ke,
       CASE WHEN luy_ke >= (:moc_q8)::numeric
             AND COALESCE(LAG(luy_ke) OVER (PARTITION BY thang ORDER BY ngay), 0) < (:moc_q8)::numeric
            THEN '<== DAT MOC (' || to_char((:moc_q8)::numeric, 'FM999,999,999,999,999') || ' VND)' END AS ghi_chu
FROM luy_ke
ORDER BY ngay;

-- Q8a (Minh hoa qua trinh luy ke cham moc 1 ty VND ngay 2026-10-18 tren 161 don seed_nho,
--      chay duoc ngay ca khi DB da nap seed_lon.sql):
\echo '=== Q8a ( Minh hoa tren tap seed_nho ma_don_hang <= 161: cham moc 1 ty ngay 2026-10-18 ) ==='
WITH doanh_thu_ngay AS (
    SELECT d.ngay_dat::date                           AS ngay,
           DATE_TRUNC('month', d.ngay_dat)::date      AS thang,
           SUM(d.tong_tien_hang - d.tien_giam)        AS doanh_thu
    FROM don_hang d
    WHERE d.ma_don_hang <= 161
      AND d.trang_thai = 'DaGiao'
      AND d.ngay_dat >= DATE '2026-10-01'
      AND d.ngay_dat <  DATE '2026-11-01'
    GROUP BY d.ngay_dat::date, DATE_TRUNC('month', d.ngay_dat)::date
),
luy_ke AS (
    SELECT ngay, thang, doanh_thu,
           SUM(doanh_thu) OVER (PARTITION BY thang ORDER BY ngay) AS luy_ke
    FROM doanh_thu_ngay
)
SELECT ngay,
       doanh_thu,
       luy_ke,
       CASE WHEN luy_ke >= 1000000000
             AND COALESCE(LAG(luy_ke) OVER (PARTITION BY thang ORDER BY ngay), 0) < 1000000000
            THEN '<== DAT MOC 1 TY (seed_nho)' END AS ghi_chu
FROM luy_ke
ORDER BY ngay;
