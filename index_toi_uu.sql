-- =====================================================================
-- TAO BO CHI MUC (INDEX) TOI UU KHUYEN NGHI (index_toi_uu.sql)
-- Chay SAU schema.sql + seed_nho.sql + seed_lon.sql:
--   psql -v ON_ERROR_STOP=1 -U postgres -d ecom -f index_toi_uu.sql
--
-- A. BO 4 CHI MUC KHUYEN NGHI CHINH THUC (da chung minh loi ich qua do luong):
--   1. idx_khach_hang_ho_ten (Q2):
--      ON khach_hang(ho_ten)
--      Giup tim khach theo ho_ten bang Index Scan / Bitmap Index Scan
--      thay vi Seq Scan toan bang khach_hang (5.006 dong).
--
--   2. idx_don_hang_khach_ngay (Q2):
--      ON don_hang(ma_khach_hang, ngay_dat, ma_don_hang) INCLUDE (trang_thai)
--      Giup Q2 doc don hang cua khach theo dung thu tu (ngay_dat, ma_don_hang)
--      bang Index Only Scan (Heap Fetches = 0).
--
--   3. idx_don_hang_dagiao_ngay_gh (Q3 va Q8):
--      ON don_hang(ngay_dat, ma_gian_hang)
--      INCLUDE (ma_don_hang, tong_tien_hang, tien_giam)
--      WHERE trang_thai = 'DaGiao'
--      Partial covering index chi luu don 'DaGiao', giup Q3 va Q8 doc thang 10/2026
--      bang Index Only Scan (Heap Fetches = 0) thay vi Seq Scan 400.161 dong.
--
--   4. idx_don_hang_gh_ngay_tt (Q4):
--      ON don_hang(ma_gian_hang, ngay_dat) INCLUDE (trang_thai)
--      Dat ma_gian_hang dung truoc ngay_dat de:
--        (a) Q4 ket hop Index Scan (gian_hang) + Index Only Scan (idx_don_hang_gh_ngay_tt)
--            va GroupAggregate truc tiep theo thu tu ma_gian_hang (Heap Fetches = 0).
--        (b) Khong tao chi muc co ngay_dat dung dau tren toan bang don_hang (nhu
--            idx_don_hang_ngay_gh_tt), tranh viec planner o Q2 bi danh lua chon
--            Incremental Sort quet don_hang theo ngay_dat toan cuc.
--
-- B. 4 CHI MUC THU NGHIEM DA TACH KHOI BO KHUYEN NGHI (xem cuoi file & bang_do.md):
--   * idx_danh_gia_bien_the_sao (Q1) : Loai bo — planner van chon Seq Scan do CTE de quy va do chon loc 25,4%.
--   * idx_ton_kho_bien_the_inc  (Q5) : Loai bo — Q5 doc 100% bang ton_kho (chi 20 trang 8KB).
--   * idx_khach_hang_ngay_dk    (Q6) : Loai bo — loc ngay_dang_ky giu lai 99,46% bang khach_hang.
--   * idx_bien_the_sp_giaban    (Q7) : Loai bo — khien planner doi Hash Join (23 buffers) sang Merge Join (738 buffers).
-- =====================================================================
\set ON_ERROR_STOP on
\timing on

-- Don sach cac ten chi muc thu nghiem hoac ten cu (neu tung tao o phien truoc)
DROP INDEX IF EXISTS idx_don_hang_ngay_gh_tt;
DROP INDEX IF EXISTS idx_danh_gia_bien_the_sao;
DROP INDEX IF EXISTS idx_ton_kho_bien_the_inc;
DROP INDEX IF EXISTS idx_khach_hang_ngay_dk;
DROP INDEX IF EXISTS idx_bien_the_sp_giaban;

-- 1. Phuc vu Q2: tra cuu khach hang theo ho_ten va don hang theo (ma_khach_hang, ngay_dat, ma_don_hang)
CREATE INDEX IF NOT EXISTS idx_khach_hang_ho_ten
    ON khach_hang(ho_ten);

CREATE INDEX IF NOT EXISTS idx_don_hang_khach_ngay
    ON don_hang(ma_khach_hang, ngay_dat, ma_don_hang)
    INCLUDE (trang_thai);

-- 2. Phuc vu Q3 va Q8: partial covering index cho don DaGiao theo (ngay_dat, ma_gian_hang)
CREATE INDEX IF NOT EXISTS idx_don_hang_dagiao_ngay_gh
    ON don_hang(ngay_dat, ma_gian_hang)
    INCLUDE (ma_don_hang, tong_tien_hang, tien_giam)
    WHERE trang_thai = 'DaGiao';

-- 3. Phuc vu Q4: covering index theo (ma_gian_hang, ngay_dat) INCLUDE (trang_thai)
CREATE INDEX IF NOT EXISTS idx_don_hang_gh_ngay_tt
    ON don_hang(ma_gian_hang, ngay_dat)
    INCLUDE (trang_thai);

-- Cap nhat Visibility Map va thong ke de Index Only Scan dat Heap Fetches = 0
VACUUM ANALYZE khach_hang;
VACUUM ANALYZE don_hang;
ANALYZE;

-- =====================================================================
-- PHAN THAM KHAO (KHONG TAO TRONG BO KHUYEN NGHI):
-- 4 chi muc thu nghiem da duoc do kiem chung va QUYET DINH LOAI BO
-- (xem so lieu chi tiet trong bang_do.md muc 5.1 -> 5.4):
--
-- CREATE INDEX idx_danh_gia_bien_the_sao ON danh_gia(ma_bien_the) INCLUDE (so_sao, ma_danh_gia);
-- CREATE INDEX idx_ton_kho_bien_the_inc  ON ton_kho(ma_bien_the) INCLUDE (so_luong_vat_ly, so_luong_giu);
-- CREATE INDEX idx_khach_hang_ngay_dk    ON khach_hang(ngay_dang_ky);
-- CREATE INDEX idx_bien_the_sp_giaban    ON bien_the(ma_san_pham, gia_ban DESC);
-- =====================================================================
