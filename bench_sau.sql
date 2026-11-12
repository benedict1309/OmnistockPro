-- =====================================================================
-- DO HIEU NANG SAU KHI TAO INDEX TOI UU (bench_sau.sql)
-- Chay SAU schema.sql + seed_nho.sql + seed_lon.sql + index_toi_uu.sql:
--   psql -v ON_ERROR_STOP=1 -U postgres -d ecom -f bench_sau.sql > ket_qua_bench_sau.txt
--
-- Nguyen tac do (muc 4.2 cua brief):
--   * Chay dung 8 truy van Q1..Q8 tren cung du lieu va cau hinh voi bench_truoc.sql.
--   * Moi truy van chay 6 lan bang EXPLAIN (ANALYZE, BUFFERS):
--     bo lan 1 (lam nong cache), lay TRUNG VI cua 5 lan (lan 2..6).
-- =====================================================================
\set ON_ERROR_STOP on
\pset pager off

VACUUM ANALYZE;

\echo '=== DANH SACH CHI MUC TOI UU KHUYEN NGHI DANG CO ==='
SELECT tablename AS bang,
       indexname AS ten_index,
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS dung_luong,
       indexdef  AS dinh_nghia
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
      'idx_khach_hang_ho_ten',
      'idx_don_hang_khach_ngay',
      'idx_don_hang_dagiao_ngay_gh',
      'idx_don_hang_gh_ngay_tt',
      'idx_don_hang_ngay_gh_tt',
      'idx_danh_gia_bien_the_sao',
      'idx_ton_kho_bien_the_inc',
      'idx_khach_hang_ngay_dk',
      'idx_bien_the_sp_giaban'
  )
ORDER BY tablename, indexname;

\echo '=== TOAN BO TAP CHI MUC DANG TON TAI KHI DO (BENCH_SAU) ==='
SELECT tablename AS bang,
       indexname AS ten_index,
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS dung_luong,
       indexdef  AS dinh_nghia
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- =====================================================================
-- Q1 (6 lan: Lan 1 warm-up, Lan 2..6 lay trung vi)
-- =====================================================================
\echo '=== BENCH_SAU Q1 - LAN 1 (WARM-UP) ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE cay AS (
    SELECT ma_danh_muc FROM danh_muc WHERE ten_danh_muc = 'Điện thoại'
    UNION ALL
    SELECT c.ma_danh_muc FROM danh_muc c JOIN cay ON c.ma_danh_muc_cha = cay.ma_danh_muc
)
SELECT s.ma_san_pham, s.ten_san_pham,
       ROUND(AVG(g.so_sao), 2) AS diem_trung_binh,
       COUNT(g.ma_danh_gia)    AS so_luot_danh_gia
FROM san_pham s
JOIN cay        ON cay.ma_danh_muc = s.ma_danh_muc
JOIN bien_the b ON b.ma_san_pham = s.ma_san_pham
JOIN danh_gia g ON g.ma_bien_the = b.ma_bien_the
GROUP BY s.ma_san_pham, s.ten_san_pham
HAVING AVG(g.so_sao) >= 4.5
ORDER BY diem_trung_binh DESC, s.ma_san_pham;

\echo '=== BENCH_SAU Q1 - LAN 2 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE cay AS (
    SELECT ma_danh_muc FROM danh_muc WHERE ten_danh_muc = 'Điện thoại'
    UNION ALL
    SELECT c.ma_danh_muc FROM danh_muc c JOIN cay ON c.ma_danh_muc_cha = cay.ma_danh_muc
)
SELECT s.ma_san_pham, s.ten_san_pham,
       ROUND(AVG(g.so_sao), 2) AS diem_trung_binh,
       COUNT(g.ma_danh_gia)    AS so_luot_danh_gia
FROM san_pham s
JOIN cay        ON cay.ma_danh_muc = s.ma_danh_muc
JOIN bien_the b ON b.ma_san_pham = s.ma_san_pham
JOIN danh_gia g ON g.ma_bien_the = b.ma_bien_the
GROUP BY s.ma_san_pham, s.ten_san_pham
HAVING AVG(g.so_sao) >= 4.5
ORDER BY diem_trung_binh DESC, s.ma_san_pham;

\echo '=== BENCH_SAU Q1 - LAN 3 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE cay AS (
    SELECT ma_danh_muc FROM danh_muc WHERE ten_danh_muc = 'Điện thoại'
    UNION ALL
    SELECT c.ma_danh_muc FROM danh_muc c JOIN cay ON c.ma_danh_muc_cha = cay.ma_danh_muc
)
SELECT s.ma_san_pham, s.ten_san_pham,
       ROUND(AVG(g.so_sao), 2) AS diem_trung_binh,
       COUNT(g.ma_danh_gia)    AS so_luot_danh_gia
FROM san_pham s
JOIN cay        ON cay.ma_danh_muc = s.ma_danh_muc
JOIN bien_the b ON b.ma_san_pham = s.ma_san_pham
JOIN danh_gia g ON g.ma_bien_the = b.ma_bien_the
GROUP BY s.ma_san_pham, s.ten_san_pham
HAVING AVG(g.so_sao) >= 4.5
ORDER BY diem_trung_binh DESC, s.ma_san_pham;

\echo '=== BENCH_SAU Q1 - LAN 4 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE cay AS (
    SELECT ma_danh_muc FROM danh_muc WHERE ten_danh_muc = 'Điện thoại'
    UNION ALL
    SELECT c.ma_danh_muc FROM danh_muc c JOIN cay ON c.ma_danh_muc_cha = cay.ma_danh_muc
)
SELECT s.ma_san_pham, s.ten_san_pham,
       ROUND(AVG(g.so_sao), 2) AS diem_trung_binh,
       COUNT(g.ma_danh_gia)    AS so_luot_danh_gia
FROM san_pham s
JOIN cay        ON cay.ma_danh_muc = s.ma_danh_muc
JOIN bien_the b ON b.ma_san_pham = s.ma_san_pham
JOIN danh_gia g ON g.ma_bien_the = b.ma_bien_the
GROUP BY s.ma_san_pham, s.ten_san_pham
HAVING AVG(g.so_sao) >= 4.5
ORDER BY diem_trung_binh DESC, s.ma_san_pham;

\echo '=== BENCH_SAU Q1 - LAN 5 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE cay AS (
    SELECT ma_danh_muc FROM danh_muc WHERE ten_danh_muc = 'Điện thoại'
    UNION ALL
    SELECT c.ma_danh_muc FROM danh_muc c JOIN cay ON c.ma_danh_muc_cha = cay.ma_danh_muc
)
SELECT s.ma_san_pham, s.ten_san_pham,
       ROUND(AVG(g.so_sao), 2) AS diem_trung_binh,
       COUNT(g.ma_danh_gia)    AS so_luot_danh_gia
FROM san_pham s
JOIN cay        ON cay.ma_danh_muc = s.ma_danh_muc
JOIN bien_the b ON b.ma_san_pham = s.ma_san_pham
JOIN danh_gia g ON g.ma_bien_the = b.ma_bien_the
GROUP BY s.ma_san_pham, s.ten_san_pham
HAVING AVG(g.so_sao) >= 4.5
ORDER BY diem_trung_binh DESC, s.ma_san_pham;

\echo '=== BENCH_SAU Q1 - LAN 6 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE cay AS (
    SELECT ma_danh_muc FROM danh_muc WHERE ten_danh_muc = 'Điện thoại'
    UNION ALL
    SELECT c.ma_danh_muc FROM danh_muc c JOIN cay ON c.ma_danh_muc_cha = cay.ma_danh_muc
)
SELECT s.ma_san_pham, s.ten_san_pham,
       ROUND(AVG(g.so_sao), 2) AS diem_trung_binh,
       COUNT(g.ma_danh_gia)    AS so_luot_danh_gia
FROM san_pham s
JOIN cay        ON cay.ma_danh_muc = s.ma_danh_muc
JOIN bien_the b ON b.ma_san_pham = s.ma_san_pham
JOIN danh_gia g ON g.ma_bien_the = b.ma_bien_the
GROUP BY s.ma_san_pham, s.ten_san_pham
HAVING AVG(g.so_sao) >= 4.5
ORDER BY diem_trung_binh DESC, s.ma_san_pham;

-- =====================================================================
-- Q2 (6 lan: Lan 1 warm-up, Lan 2..6 lay trung vi)
-- =====================================================================
\echo '=== BENCH_SAU Q2 - LAN 1 (WARM-UP) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT d.ma_don_hang, d.ngay_dat::date AS ngay_dat, d.trang_thai,
       s.ten_san_pham, b.mau_sac, b.kich_co, c.so_luong, c.don_gia AS gia_ban
FROM khach_hang k
JOIN don_hang d          ON d.ma_khach_hang = k.ma_khach_hang
JOIN chi_tiet_don_hang c ON c.ma_don_hang   = d.ma_don_hang
JOIN bien_the b          ON b.ma_bien_the   = c.ma_bien_the
JOIN san_pham s          ON s.ma_san_pham   = b.ma_san_pham
WHERE k.ho_ten = 'Nguyễn Văn A'
ORDER BY d.ngay_dat, d.ma_don_hang, s.ten_san_pham
LIMIT 10;

\echo '=== BENCH_SAU Q2 - LAN 2 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT d.ma_don_hang, d.ngay_dat::date AS ngay_dat, d.trang_thai,
       s.ten_san_pham, b.mau_sac, b.kich_co, c.so_luong, c.don_gia AS gia_ban
FROM khach_hang k
JOIN don_hang d          ON d.ma_khach_hang = k.ma_khach_hang
JOIN chi_tiet_don_hang c ON c.ma_don_hang   = d.ma_don_hang
JOIN bien_the b          ON b.ma_bien_the   = c.ma_bien_the
JOIN san_pham s          ON s.ma_san_pham   = b.ma_san_pham
WHERE k.ho_ten = 'Nguyễn Văn A'
ORDER BY d.ngay_dat, d.ma_don_hang, s.ten_san_pham
LIMIT 10;

\echo '=== BENCH_SAU Q2 - LAN 3 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT d.ma_don_hang, d.ngay_dat::date AS ngay_dat, d.trang_thai,
       s.ten_san_pham, b.mau_sac, b.kich_co, c.so_luong, c.don_gia AS gia_ban
FROM khach_hang k
JOIN don_hang d          ON d.ma_khach_hang = k.ma_khach_hang
JOIN chi_tiet_don_hang c ON c.ma_don_hang   = d.ma_don_hang
JOIN bien_the b          ON b.ma_bien_the   = c.ma_bien_the
JOIN san_pham s          ON s.ma_san_pham   = b.ma_san_pham
WHERE k.ho_ten = 'Nguyễn Văn A'
ORDER BY d.ngay_dat, d.ma_don_hang, s.ten_san_pham
LIMIT 10;

\echo '=== BENCH_SAU Q2 - LAN 4 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT d.ma_don_hang, d.ngay_dat::date AS ngay_dat, d.trang_thai,
       s.ten_san_pham, b.mau_sac, b.kich_co, c.so_luong, c.don_gia AS gia_ban
FROM khach_hang k
JOIN don_hang d          ON d.ma_khach_hang = k.ma_khach_hang
JOIN chi_tiet_don_hang c ON c.ma_don_hang   = d.ma_don_hang
JOIN bien_the b          ON b.ma_bien_the   = c.ma_bien_the
JOIN san_pham s          ON s.ma_san_pham   = b.ma_san_pham
WHERE k.ho_ten = 'Nguyễn Văn A'
ORDER BY d.ngay_dat, d.ma_don_hang, s.ten_san_pham
LIMIT 10;

\echo '=== BENCH_SAU Q2 - LAN 5 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT d.ma_don_hang, d.ngay_dat::date AS ngay_dat, d.trang_thai,
       s.ten_san_pham, b.mau_sac, b.kich_co, c.so_luong, c.don_gia AS gia_ban
FROM khach_hang k
JOIN don_hang d          ON d.ma_khach_hang = k.ma_khach_hang
JOIN chi_tiet_don_hang c ON c.ma_don_hang   = d.ma_don_hang
JOIN bien_the b          ON b.ma_bien_the   = c.ma_bien_the
JOIN san_pham s          ON s.ma_san_pham   = b.ma_san_pham
WHERE k.ho_ten = 'Nguyễn Văn A'
ORDER BY d.ngay_dat, d.ma_don_hang, s.ten_san_pham
LIMIT 10;

\echo '=== BENCH_SAU Q2 - LAN 6 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT d.ma_don_hang, d.ngay_dat::date AS ngay_dat, d.trang_thai,
       s.ten_san_pham, b.mau_sac, b.kich_co, c.so_luong, c.don_gia AS gia_ban
FROM khach_hang k
JOIN don_hang d          ON d.ma_khach_hang = k.ma_khach_hang
JOIN chi_tiet_don_hang c ON c.ma_don_hang   = d.ma_don_hang
JOIN bien_the b          ON b.ma_bien_the   = c.ma_bien_the
JOIN san_pham s          ON s.ma_san_pham   = b.ma_san_pham
WHERE k.ho_ten = 'Nguyễn Văn A'
ORDER BY d.ngay_dat, d.ma_don_hang, s.ten_san_pham
LIMIT 10;

-- =====================================================================
-- Q3 (6 lan: Lan 1 warm-up, Lan 2..6 lay trung vi)
-- =====================================================================
\echo '=== BENCH_SAU Q3 - LAN 1 (WARM-UP) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(d.ma_don_hang)                             AS so_don_da_giao,
       COALESCE(SUM(d.tong_tien_hang), 0)               AS doanh_thu_truoc_giam,
       COALESCE(SUM(d.tien_giam), 0)                    AS tong_voucher,
       COALESCE(SUM(d.tong_tien_hang - d.tien_giam), 0) AS doanh_thu_thuan
FROM gian_hang g
LEFT JOIN don_hang d
       ON d.ma_gian_hang = g.ma_gian_hang
      AND d.trang_thai = 'DaGiao'
      AND d.ngay_dat >= DATE '2026-10-01'
      AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
ORDER BY doanh_thu_thuan DESC;

\echo '=== BENCH_SAU Q3 - LAN 2 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(d.ma_don_hang)                             AS so_don_da_giao,
       COALESCE(SUM(d.tong_tien_hang), 0)               AS doanh_thu_truoc_giam,
       COALESCE(SUM(d.tien_giam), 0)                    AS tong_voucher,
       COALESCE(SUM(d.tong_tien_hang - d.tien_giam), 0) AS doanh_thu_thuan
FROM gian_hang g
LEFT JOIN don_hang d
       ON d.ma_gian_hang = g.ma_gian_hang
      AND d.trang_thai = 'DaGiao'
      AND d.ngay_dat >= DATE '2026-10-01'
      AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
ORDER BY doanh_thu_thuan DESC;

\echo '=== BENCH_SAU Q3 - LAN 3 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(d.ma_don_hang)                             AS so_don_da_giao,
       COALESCE(SUM(d.tong_tien_hang), 0)               AS doanh_thu_truoc_giam,
       COALESCE(SUM(d.tien_giam), 0)                    AS tong_voucher,
       COALESCE(SUM(d.tong_tien_hang - d.tien_giam), 0) AS doanh_thu_thuan
FROM gian_hang g
LEFT JOIN don_hang d
       ON d.ma_gian_hang = g.ma_gian_hang
      AND d.trang_thai = 'DaGiao'
      AND d.ngay_dat >= DATE '2026-10-01'
      AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
ORDER BY doanh_thu_thuan DESC;

\echo '=== BENCH_SAU Q3 - LAN 4 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(d.ma_don_hang)                             AS so_don_da_giao,
       COALESCE(SUM(d.tong_tien_hang), 0)               AS doanh_thu_truoc_giam,
       COALESCE(SUM(d.tien_giam), 0)                    AS tong_voucher,
       COALESCE(SUM(d.tong_tien_hang - d.tien_giam), 0) AS doanh_thu_thuan
FROM gian_hang g
LEFT JOIN don_hang d
       ON d.ma_gian_hang = g.ma_gian_hang
      AND d.trang_thai = 'DaGiao'
      AND d.ngay_dat >= DATE '2026-10-01'
      AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
ORDER BY doanh_thu_thuan DESC;

\echo '=== BENCH_SAU Q3 - LAN 5 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(d.ma_don_hang)                             AS so_don_da_giao,
       COALESCE(SUM(d.tong_tien_hang), 0)               AS doanh_thu_truoc_giam,
       COALESCE(SUM(d.tien_giam), 0)                    AS tong_voucher,
       COALESCE(SUM(d.tong_tien_hang - d.tien_giam), 0) AS doanh_thu_thuan
FROM gian_hang g
LEFT JOIN don_hang d
       ON d.ma_gian_hang = g.ma_gian_hang
      AND d.trang_thai = 'DaGiao'
      AND d.ngay_dat >= DATE '2026-10-01'
      AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
ORDER BY doanh_thu_thuan DESC;

\echo '=== BENCH_SAU Q3 - LAN 6 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(d.ma_don_hang)                             AS so_don_da_giao,
       COALESCE(SUM(d.tong_tien_hang), 0)               AS doanh_thu_truoc_giam,
       COALESCE(SUM(d.tien_giam), 0)                    AS tong_voucher,
       COALESCE(SUM(d.tong_tien_hang - d.tien_giam), 0) AS doanh_thu_thuan
FROM gian_hang g
LEFT JOIN don_hang d
       ON d.ma_gian_hang = g.ma_gian_hang
      AND d.trang_thai = 'DaGiao'
      AND d.ngay_dat >= DATE '2026-10-01'
      AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
ORDER BY doanh_thu_thuan DESC;

-- =====================================================================
-- Q4 (6 lan: Lan 1 warm-up, Lan 2..6 lay trung vi)
-- =====================================================================
\echo '=== BENCH_SAU Q4 - LAN 1 (WARM-UP) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(*)                                       AS tong_don,
       COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') AS don_huy,
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') / COUNT(*), 2) AS ty_le_huy_pct
FROM gian_hang g
JOIN don_hang d ON d.ma_gian_hang = g.ma_gian_hang
WHERE d.ngay_dat >= DATE '2026-10-01'
  AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
HAVING COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') * 10 > COUNT(*)
ORDER BY ty_le_huy_pct DESC;

\echo '=== BENCH_SAU Q4 - LAN 2 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(*)                                       AS tong_don,
       COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') AS don_huy,
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') / COUNT(*), 2) AS ty_le_huy_pct
FROM gian_hang g
JOIN don_hang d ON d.ma_gian_hang = g.ma_gian_hang
WHERE d.ngay_dat >= DATE '2026-10-01'
  AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
HAVING COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') * 10 > COUNT(*)
ORDER BY ty_le_huy_pct DESC;

\echo '=== BENCH_SAU Q4 - LAN 3 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(*)                                       AS tong_don,
       COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') AS don_huy,
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') / COUNT(*), 2) AS ty_le_huy_pct
FROM gian_hang g
JOIN don_hang d ON d.ma_gian_hang = g.ma_gian_hang
WHERE d.ngay_dat >= DATE '2026-10-01'
  AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
HAVING COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') * 10 > COUNT(*)
ORDER BY ty_le_huy_pct DESC;

\echo '=== BENCH_SAU Q4 - LAN 4 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(*)                                       AS tong_don,
       COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') AS don_huy,
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') / COUNT(*), 2) AS ty_le_huy_pct
FROM gian_hang g
JOIN don_hang d ON d.ma_gian_hang = g.ma_gian_hang
WHERE d.ngay_dat >= DATE '2026-10-01'
  AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
HAVING COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') * 10 > COUNT(*)
ORDER BY ty_le_huy_pct DESC;

\echo '=== BENCH_SAU Q4 - LAN 5 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(*)                                       AS tong_don,
       COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') AS don_huy,
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') / COUNT(*), 2) AS ty_le_huy_pct
FROM gian_hang g
JOIN don_hang d ON d.ma_gian_hang = g.ma_gian_hang
WHERE d.ngay_dat >= DATE '2026-10-01'
  AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
HAVING COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') * 10 > COUNT(*)
ORDER BY ty_le_huy_pct DESC;

\echo '=== BENCH_SAU Q4 - LAN 6 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT g.ma_gian_hang, g.ten_gian_hang,
       COUNT(*)                                       AS tong_don,
       COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') AS don_huy,
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') / COUNT(*), 2) AS ty_le_huy_pct
FROM gian_hang g
JOIN don_hang d ON d.ma_gian_hang = g.ma_gian_hang
WHERE d.ngay_dat >= DATE '2026-10-01'
  AND d.ngay_dat <  DATE '2026-11-01'
GROUP BY g.ma_gian_hang, g.ten_gian_hang
HAVING COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') * 10 > COUNT(*)
ORDER BY ty_le_huy_pct DESC;

-- =====================================================================
-- Q5 (6 lan: Lan 1 warm-up, Lan 2..6 lay trung vi)
-- =====================================================================
\echo '=== BENCH_SAU Q5 - LAN 1 (WARM-UP) ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE goc AS (
    SELECT ma_danh_muc, ma_danh_muc AS ma_goc FROM danh_muc WHERE ma_danh_muc_cha IS NULL
    UNION ALL
    SELECT c.ma_danh_muc, goc.ma_goc FROM danh_muc c JOIN goc ON c.ma_danh_muc_cha = goc.ma_danh_muc
),
ton AS (
    SELECT b.ma_san_pham,
           COUNT(DISTINCT b.ma_bien_the)           AS so_bien_the,
           SUM(t.so_luong_vat_ly)                  AS ton_vat_ly,
           SUM(t.so_luong_vat_ly - t.so_luong_giu) AS ton_kha_dung
    FROM bien_the b
    JOIN ton_kho t ON t.ma_bien_the = b.ma_bien_the
    GROUP BY b.ma_san_pham
)
SELECT dm.ma_danh_muc, dm.ten_danh_muc,
       COUNT(DISTINCT s.ma_san_pham)      AS so_san_pham,
       COALESCE(SUM(ton.ton_vat_ly), 0)   AS ton_vat_ly,
       COALESCE(SUM(ton.ton_kha_dung), 0) AS ton_kha_dung
FROM danh_muc dm
LEFT JOIN goc        ON goc.ma_goc = dm.ma_danh_muc
LEFT JOIN san_pham s ON s.ma_danh_muc = goc.ma_danh_muc
LEFT JOIN ton        ON ton.ma_san_pham = s.ma_san_pham
WHERE dm.ma_danh_muc_cha IS NULL
GROUP BY dm.ma_danh_muc, dm.ten_danh_muc
ORDER BY dm.ma_danh_muc;

\echo '=== BENCH_SAU Q5 - LAN 2 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE goc AS (
    SELECT ma_danh_muc, ma_danh_muc AS ma_goc FROM danh_muc WHERE ma_danh_muc_cha IS NULL
    UNION ALL
    SELECT c.ma_danh_muc, goc.ma_goc FROM danh_muc c JOIN goc ON c.ma_danh_muc_cha = goc.ma_danh_muc
),
ton AS (
    SELECT b.ma_san_pham,
           COUNT(DISTINCT b.ma_bien_the)           AS so_bien_the,
           SUM(t.so_luong_vat_ly)                  AS ton_vat_ly,
           SUM(t.so_luong_vat_ly - t.so_luong_giu) AS ton_kha_dung
    FROM bien_the b
    JOIN ton_kho t ON t.ma_bien_the = b.ma_bien_the
    GROUP BY b.ma_san_pham
)
SELECT dm.ma_danh_muc, dm.ten_danh_muc,
       COUNT(DISTINCT s.ma_san_pham)      AS so_san_pham,
       COALESCE(SUM(ton.ton_vat_ly), 0)   AS ton_vat_ly,
       COALESCE(SUM(ton.ton_kha_dung), 0) AS ton_kha_dung
FROM danh_muc dm
LEFT JOIN goc        ON goc.ma_goc = dm.ma_danh_muc
LEFT JOIN san_pham s ON s.ma_danh_muc = goc.ma_danh_muc
LEFT JOIN ton        ON ton.ma_san_pham = s.ma_san_pham
WHERE dm.ma_danh_muc_cha IS NULL
GROUP BY dm.ma_danh_muc, dm.ten_danh_muc
ORDER BY dm.ma_danh_muc;

\echo '=== BENCH_SAU Q5 - LAN 3 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE goc AS (
    SELECT ma_danh_muc, ma_danh_muc AS ma_goc FROM danh_muc WHERE ma_danh_muc_cha IS NULL
    UNION ALL
    SELECT c.ma_danh_muc, goc.ma_goc FROM danh_muc c JOIN goc ON c.ma_danh_muc_cha = goc.ma_danh_muc
),
ton AS (
    SELECT b.ma_san_pham,
           COUNT(DISTINCT b.ma_bien_the)           AS so_bien_the,
           SUM(t.so_luong_vat_ly)                  AS ton_vat_ly,
           SUM(t.so_luong_vat_ly - t.so_luong_giu) AS ton_kha_dung
    FROM bien_the b
    JOIN ton_kho t ON t.ma_bien_the = b.ma_bien_the
    GROUP BY b.ma_san_pham
)
SELECT dm.ma_danh_muc, dm.ten_danh_muc,
       COUNT(DISTINCT s.ma_san_pham)      AS so_san_pham,
       COALESCE(SUM(ton.ton_vat_ly), 0)   AS ton_vat_ly,
       COALESCE(SUM(ton.ton_kha_dung), 0) AS ton_kha_dung
FROM danh_muc dm
LEFT JOIN goc        ON goc.ma_goc = dm.ma_danh_muc
LEFT JOIN san_pham s ON s.ma_danh_muc = goc.ma_danh_muc
LEFT JOIN ton        ON ton.ma_san_pham = s.ma_san_pham
WHERE dm.ma_danh_muc_cha IS NULL
GROUP BY dm.ma_danh_muc, dm.ten_danh_muc
ORDER BY dm.ma_danh_muc;

\echo '=== BENCH_SAU Q5 - LAN 4 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE goc AS (
    SELECT ma_danh_muc, ma_danh_muc AS ma_goc FROM danh_muc WHERE ma_danh_muc_cha IS NULL
    UNION ALL
    SELECT c.ma_danh_muc, goc.ma_goc FROM danh_muc c JOIN goc ON c.ma_danh_muc_cha = goc.ma_danh_muc
),
ton AS (
    SELECT b.ma_san_pham,
           COUNT(DISTINCT b.ma_bien_the)           AS so_bien_the,
           SUM(t.so_luong_vat_ly)                  AS ton_vat_ly,
           SUM(t.so_luong_vat_ly - t.so_luong_giu) AS ton_kha_dung
    FROM bien_the b
    JOIN ton_kho t ON t.ma_bien_the = b.ma_bien_the
    GROUP BY b.ma_san_pham
)
SELECT dm.ma_danh_muc, dm.ten_danh_muc,
       COUNT(DISTINCT s.ma_san_pham)      AS so_san_pham,
       COALESCE(SUM(ton.ton_vat_ly), 0)   AS ton_vat_ly,
       COALESCE(SUM(ton.ton_kha_dung), 0) AS ton_kha_dung
FROM danh_muc dm
LEFT JOIN goc        ON goc.ma_goc = dm.ma_danh_muc
LEFT JOIN san_pham s ON s.ma_danh_muc = goc.ma_danh_muc
LEFT JOIN ton        ON ton.ma_san_pham = s.ma_san_pham
WHERE dm.ma_danh_muc_cha IS NULL
GROUP BY dm.ma_danh_muc, dm.ten_danh_muc
ORDER BY dm.ma_danh_muc;

\echo '=== BENCH_SAU Q5 - LAN 5 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE goc AS (
    SELECT ma_danh_muc, ma_danh_muc AS ma_goc FROM danh_muc WHERE ma_danh_muc_cha IS NULL
    UNION ALL
    SELECT c.ma_danh_muc, goc.ma_goc FROM danh_muc c JOIN goc ON c.ma_danh_muc_cha = goc.ma_danh_muc
),
ton AS (
    SELECT b.ma_san_pham,
           COUNT(DISTINCT b.ma_bien_the)           AS so_bien_the,
           SUM(t.so_luong_vat_ly)                  AS ton_vat_ly,
           SUM(t.so_luong_vat_ly - t.so_luong_giu) AS ton_kha_dung
    FROM bien_the b
    JOIN ton_kho t ON t.ma_bien_the = b.ma_bien_the
    GROUP BY b.ma_san_pham
)
SELECT dm.ma_danh_muc, dm.ten_danh_muc,
       COUNT(DISTINCT s.ma_san_pham)      AS so_san_pham,
       COALESCE(SUM(ton.ton_vat_ly), 0)   AS ton_vat_ly,
       COALESCE(SUM(ton.ton_kha_dung), 0) AS ton_kha_dung
FROM danh_muc dm
LEFT JOIN goc        ON goc.ma_goc = dm.ma_danh_muc
LEFT JOIN san_pham s ON s.ma_danh_muc = goc.ma_danh_muc
LEFT JOIN ton        ON ton.ma_san_pham = s.ma_san_pham
WHERE dm.ma_danh_muc_cha IS NULL
GROUP BY dm.ma_danh_muc, dm.ten_danh_muc
ORDER BY dm.ma_danh_muc;

\echo '=== BENCH_SAU Q5 - LAN 6 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE goc AS (
    SELECT ma_danh_muc, ma_danh_muc AS ma_goc FROM danh_muc WHERE ma_danh_muc_cha IS NULL
    UNION ALL
    SELECT c.ma_danh_muc, goc.ma_goc FROM danh_muc c JOIN goc ON c.ma_danh_muc_cha = goc.ma_danh_muc
),
ton AS (
    SELECT b.ma_san_pham,
           COUNT(DISTINCT b.ma_bien_the)           AS so_bien_the,
           SUM(t.so_luong_vat_ly)                  AS ton_vat_ly,
           SUM(t.so_luong_vat_ly - t.so_luong_giu) AS ton_kha_dung
    FROM bien_the b
    JOIN ton_kho t ON t.ma_bien_the = b.ma_bien_the
    GROUP BY b.ma_san_pham
)
SELECT dm.ma_danh_muc, dm.ten_danh_muc,
       COUNT(DISTINCT s.ma_san_pham)      AS so_san_pham,
       COALESCE(SUM(ton.ton_vat_ly), 0)   AS ton_vat_ly,
       COALESCE(SUM(ton.ton_kha_dung), 0) AS ton_kha_dung
FROM danh_muc dm
LEFT JOIN goc        ON goc.ma_goc = dm.ma_danh_muc
LEFT JOIN san_pham s ON s.ma_danh_muc = goc.ma_danh_muc
LEFT JOIN ton        ON ton.ma_san_pham = s.ma_san_pham
WHERE dm.ma_danh_muc_cha IS NULL
GROUP BY dm.ma_danh_muc, dm.ten_danh_muc
ORDER BY dm.ma_danh_muc;

-- =====================================================================
-- Q6 (6 lan: Lan 1 warm-up, Lan 2..6 lay trung vi)
-- =====================================================================
\echo '=== BENCH_SAU Q6 - LAN 1 (WARM-UP) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT k.ma_khach_hang, k.ho_ten, k.email, k.ngay_dang_ky
FROM khach_hang k
WHERE k.ngay_dang_ky < CURRENT_DATE - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM don_hang d WHERE d.ma_khach_hang = k.ma_khach_hang)
ORDER BY k.ngay_dang_ky;

\echo '=== BENCH_SAU Q6 - LAN 2 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT k.ma_khach_hang, k.ho_ten, k.email, k.ngay_dang_ky
FROM khach_hang k
WHERE k.ngay_dang_ky < CURRENT_DATE - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM don_hang d WHERE d.ma_khach_hang = k.ma_khach_hang)
ORDER BY k.ngay_dang_ky;

\echo '=== BENCH_SAU Q6 - LAN 3 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT k.ma_khach_hang, k.ho_ten, k.email, k.ngay_dang_ky
FROM khach_hang k
WHERE k.ngay_dang_ky < CURRENT_DATE - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM don_hang d WHERE d.ma_khach_hang = k.ma_khach_hang)
ORDER BY k.ngay_dang_ky;

\echo '=== BENCH_SAU Q6 - LAN 4 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT k.ma_khach_hang, k.ho_ten, k.email, k.ngay_dang_ky
FROM khach_hang k
WHERE k.ngay_dang_ky < CURRENT_DATE - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM don_hang d WHERE d.ma_khach_hang = k.ma_khach_hang)
ORDER BY k.ngay_dang_ky;

\echo '=== BENCH_SAU Q6 - LAN 5 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT k.ma_khach_hang, k.ho_ten, k.email, k.ngay_dang_ky
FROM khach_hang k
WHERE k.ngay_dang_ky < CURRENT_DATE - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM don_hang d WHERE d.ma_khach_hang = k.ma_khach_hang)
ORDER BY k.ngay_dang_ky;

\echo '=== BENCH_SAU Q6 - LAN 6 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT k.ma_khach_hang, k.ho_ten, k.email, k.ngay_dang_ky
FROM khach_hang k
WHERE k.ngay_dang_ky < CURRENT_DATE - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM don_hang d WHERE d.ma_khach_hang = k.ma_khach_hang)
ORDER BY k.ngay_dang_ky;

-- =====================================================================
-- Q7 (6 lan: Lan 1 warm-up, Lan 2..6 lay trung vi)
-- =====================================================================
\echo '=== BENCH_SAU Q7 - LAN 1 (WARM-UP) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.ten_san_pham, b.sku, b.mau_sac, b.kich_co, b.gia_ban, n.ten_ncc AS nha_cung_cap
FROM bien_the b
JOIN san_pham s     ON s.ma_san_pham = b.ma_san_pham
JOIN nha_cung_cap n ON n.ma_ncc = s.ma_ncc
WHERE b.gia_ban > ALL (
        SELECT b2.gia_ban
        FROM bien_the b2
        JOIN san_pham s2 ON s2.ma_san_pham = b2.ma_san_pham
        WHERE s2.ma_ncc = 2
      )
ORDER BY b.gia_ban DESC;

\echo '=== BENCH_SAU Q7 - LAN 2 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.ten_san_pham, b.sku, b.mau_sac, b.kich_co, b.gia_ban, n.ten_ncc AS nha_cung_cap
FROM bien_the b
JOIN san_pham s     ON s.ma_san_pham = b.ma_san_pham
JOIN nha_cung_cap n ON n.ma_ncc = s.ma_ncc
WHERE b.gia_ban > ALL (
        SELECT b2.gia_ban
        FROM bien_the b2
        JOIN san_pham s2 ON s2.ma_san_pham = b2.ma_san_pham
        WHERE s2.ma_ncc = 2
      )
ORDER BY b.gia_ban DESC;

\echo '=== BENCH_SAU Q7 - LAN 3 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.ten_san_pham, b.sku, b.mau_sac, b.kich_co, b.gia_ban, n.ten_ncc AS nha_cung_cap
FROM bien_the b
JOIN san_pham s     ON s.ma_san_pham = b.ma_san_pham
JOIN nha_cung_cap n ON n.ma_ncc = s.ma_ncc
WHERE b.gia_ban > ALL (
        SELECT b2.gia_ban
        FROM bien_the b2
        JOIN san_pham s2 ON s2.ma_san_pham = b2.ma_san_pham
        WHERE s2.ma_ncc = 2
      )
ORDER BY b.gia_ban DESC;

\echo '=== BENCH_SAU Q7 - LAN 4 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.ten_san_pham, b.sku, b.mau_sac, b.kich_co, b.gia_ban, n.ten_ncc AS nha_cung_cap
FROM bien_the b
JOIN san_pham s     ON s.ma_san_pham = b.ma_san_pham
JOIN nha_cung_cap n ON n.ma_ncc = s.ma_ncc
WHERE b.gia_ban > ALL (
        SELECT b2.gia_ban
        FROM bien_the b2
        JOIN san_pham s2 ON s2.ma_san_pham = b2.ma_san_pham
        WHERE s2.ma_ncc = 2
      )
ORDER BY b.gia_ban DESC;

\echo '=== BENCH_SAU Q7 - LAN 5 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.ten_san_pham, b.sku, b.mau_sac, b.kich_co, b.gia_ban, n.ten_ncc AS nha_cung_cap
FROM bien_the b
JOIN san_pham s     ON s.ma_san_pham = b.ma_san_pham
JOIN nha_cung_cap n ON n.ma_ncc = s.ma_ncc
WHERE b.gia_ban > ALL (
        SELECT b2.gia_ban
        FROM bien_the b2
        JOIN san_pham s2 ON s2.ma_san_pham = b2.ma_san_pham
        WHERE s2.ma_ncc = 2
      )
ORDER BY b.gia_ban DESC;

\echo '=== BENCH_SAU Q7 - LAN 6 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.ten_san_pham, b.sku, b.mau_sac, b.kich_co, b.gia_ban, n.ten_ncc AS nha_cung_cap
FROM bien_the b
JOIN san_pham s     ON s.ma_san_pham = b.ma_san_pham
JOIN nha_cung_cap n ON n.ma_ncc = s.ma_ncc
WHERE b.gia_ban > ALL (
        SELECT b2.gia_ban
        FROM bien_the b2
        JOIN san_pham s2 ON s2.ma_san_pham = b2.ma_san_pham
        WHERE s2.ma_ncc = 2
      )
ORDER BY b.gia_ban DESC;

-- =====================================================================
-- Q8 (6 lan: Lan 1 warm-up, Lan 2..6 lay trung vi)
-- =====================================================================
\echo '=== BENCH_SAU Q8 - LAN 1 (WARM-UP) ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH doanh_thu_ngay AS (
    SELECT d.ngay_dat::date                      AS ngay,
           DATE_TRUNC('month', d.ngay_dat)::date AS thang,
           SUM(d.tong_tien_hang - d.tien_giam)   AS doanh_thu
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
SELECT ngay, doanh_thu, luy_ke,
       CASE WHEN luy_ke >= 1000000000
             AND COALESCE(LAG(luy_ke) OVER (PARTITION BY thang ORDER BY ngay), 0) < 1000000000
            THEN '<== DAT MOC 1 TY' END AS ghi_chu
FROM luy_ke
ORDER BY ngay;

\echo '=== BENCH_SAU Q8 - LAN 2 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH doanh_thu_ngay AS (
    SELECT d.ngay_dat::date                      AS ngay,
           DATE_TRUNC('month', d.ngay_dat)::date AS thang,
           SUM(d.tong_tien_hang - d.tien_giam)   AS doanh_thu
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
SELECT ngay, doanh_thu, luy_ke,
       CASE WHEN luy_ke >= 1000000000
             AND COALESCE(LAG(luy_ke) OVER (PARTITION BY thang ORDER BY ngay), 0) < 1000000000
            THEN '<== DAT MOC 1 TY' END AS ghi_chu
FROM luy_ke
ORDER BY ngay;

\echo '=== BENCH_SAU Q8 - LAN 3 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH doanh_thu_ngay AS (
    SELECT d.ngay_dat::date                      AS ngay,
           DATE_TRUNC('month', d.ngay_dat)::date AS thang,
           SUM(d.tong_tien_hang - d.tien_giam)   AS doanh_thu
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
SELECT ngay, doanh_thu, luy_ke,
       CASE WHEN luy_ke >= 1000000000
             AND COALESCE(LAG(luy_ke) OVER (PARTITION BY thang ORDER BY ngay), 0) < 1000000000
            THEN '<== DAT MOC 1 TY' END AS ghi_chu
FROM luy_ke
ORDER BY ngay;

\echo '=== BENCH_SAU Q8 - LAN 4 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH doanh_thu_ngay AS (
    SELECT d.ngay_dat::date                      AS ngay,
           DATE_TRUNC('month', d.ngay_dat)::date AS thang,
           SUM(d.tong_tien_hang - d.tien_giam)   AS doanh_thu
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
SELECT ngay, doanh_thu, luy_ke,
       CASE WHEN luy_ke >= 1000000000
             AND COALESCE(LAG(luy_ke) OVER (PARTITION BY thang ORDER BY ngay), 0) < 1000000000
            THEN '<== DAT MOC 1 TY' END AS ghi_chu
FROM luy_ke
ORDER BY ngay;

\echo '=== BENCH_SAU Q8 - LAN 5 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH doanh_thu_ngay AS (
    SELECT d.ngay_dat::date                      AS ngay,
           DATE_TRUNC('month', d.ngay_dat)::date AS thang,
           SUM(d.tong_tien_hang - d.tien_giam)   AS doanh_thu
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
SELECT ngay, doanh_thu, luy_ke,
       CASE WHEN luy_ke >= 1000000000
             AND COALESCE(LAG(luy_ke) OVER (PARTITION BY thang ORDER BY ngay), 0) < 1000000000
            THEN '<== DAT MOC 1 TY' END AS ghi_chu
FROM luy_ke
ORDER BY ngay;

\echo '=== BENCH_SAU Q8 - LAN 6 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH doanh_thu_ngay AS (
    SELECT d.ngay_dat::date                      AS ngay,
           DATE_TRUNC('month', d.ngay_dat)::date AS thang,
           SUM(d.tong_tien_hang - d.tien_giam)   AS doanh_thu
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
SELECT ngay, doanh_thu, luy_ke,
       CASE WHEN luy_ke >= 1000000000
             AND COALESCE(LAG(luy_ke) OVER (PARTITION BY thang ORDER BY ngay), 0) < 1000000000
            THEN '<== DAT MOC 1 TY' END AS ghi_chu
FROM luy_ke
ORDER BY ngay;

-- =====================================================================
-- PHU LUC KIEM TRA Q2 VOI KHACH IT DON ('Lê Minh Cường' — 43 don & 'Vũ Quang Phúc' — 31 don)
-- =====================================================================
\echo '=== BENCH_SAU Q2_KHACH_IT_DON (Le Minh Cuong - 43 don) ==='
EXPLAIN (ANALYZE, BUFFERS)
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
WHERE k.ho_ten = 'Lê Minh Cường'
ORDER BY d.ngay_dat, d.ma_don_hang, s.ten_san_pham
LIMIT 10;

\echo '=== BENCH_SAU Q2_KHACH_1_DON (Vu Quang Phuc - 31 don) ==='
EXPLAIN (ANALYZE, BUFFERS)
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
WHERE k.ho_ten = 'Vũ Quang Phúc'
ORDER BY d.ngay_dat, d.ma_don_hang, s.ten_san_pham
LIMIT 10;

