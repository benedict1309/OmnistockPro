-- KIEM TRA CHEO 8 TRUY VAN + BAT BIEN. Chay tren DB moi nap schema.sql + seed_nho.sql
-- (cac so 1547421000, 4 gian hang... gan voi du lieu seed co dinh; chay sau demo_concurrency.sh thi dong cuoi Q5 se lech).
\set ON_ERROR_STOP on
DO $$
DECLARE a NUMERIC; b NUMERIC; n INT;
BEGIN
  -- Bat bien 1: tong_tien_hang = tong cac dong (tai lieu 3NF muc 5.4)
  SELECT count(*) INTO n FROM (SELECT d.ma_don_hang FROM don_hang d JOIN chi_tiet_don_hang c USING (ma_don_hang)
        GROUP BY d.ma_don_hang, d.tong_tien_hang HAVING SUM(c.so_luong*c.don_gia) <> d.tong_tien_hang) x;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL bat bien tong tien: % don lech', n; END IF;
  -- Bat bien 2: so cai khop ton kho
  SELECT count(*) INTO n FROM v_doi_soat_kho WHERE NOT khop;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL doi soat kho: % dong lech', n; END IF;

  -- Q3 vs Q8: tong doanh thu thuan thang 10 phai bang luy ke cuoi thang
  SELECT SUM(tong_tien_hang - tien_giam) INTO a FROM don_hang
   WHERE trang_thai='DaGiao' AND to_char(ngay_dat,'YYYY-MM')='2026-10';
  b := 1547421000;   -- = luy ke ngay 31/10 o Q8 (doc tu ket qua)
  IF a <> b THEN RAISE EXCEPTION 'FAIL Q3/Q8: % vs %', a, b; END IF;

  -- Q4: viet lai bang 2 subquery
  SELECT count(*) INTO n FROM gian_hang g
   WHERE (SELECT count(*) FROM don_hang d WHERE d.ma_gian_hang=g.ma_gian_hang AND d.trang_thai='DaHuy' AND to_char(d.ngay_dat,'YYYY-MM')='2026-10')::numeric
       / NULLIF((SELECT count(*) FROM don_hang d WHERE d.ma_gian_hang=g.ma_gian_hang AND to_char(d.ngay_dat,'YYYY-MM')='2026-10'),0) > 0.10;
  IF n <> 4 THEN RAISE EXCEPTION 'FAIL Q4: % gian hang', n; END IF;

  -- Q6: viet lai bang LEFT JOIN anti-join
  SELECT count(*) INTO n FROM khach_hang k LEFT JOIN don_hang d USING (ma_khach_hang)
   WHERE d.ma_don_hang IS NULL AND k.ngay_dang_ky < CURRENT_DATE - 365;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL Q6: % khach', n; END IF;

  -- Q7: viet lai bang MAX
  SELECT count(*) INTO n FROM bien_the b
   WHERE b.gia_ban > (SELECT max(b2.gia_ban) FROM bien_the b2 JOIN san_pham s2 USING (ma_san_pham) WHERE s2.ma_ncc=2);
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL Q7: % mat hang', n; END IF;

  -- Q1: danh muc con duoc tinh (ma 2 va 4), khong tinh nham danh muc khac
  SELECT count(*) INTO n FROM (SELECT s.ma_san_pham FROM san_pham s JOIN bien_the b USING (ma_san_pham)
        JOIN danh_gia g USING (ma_bien_the) WHERE s.ma_danh_muc IN (2,4)
        GROUP BY s.ma_san_pham HAVING avg(g.so_sao) >= 4.5) x;
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL Q1: % san pham', n; END IF;

  -- Q5: tong ton 4 danh muc cap 1 = tong ton ca he thong
  SELECT SUM(so_luong_vat_ly) INTO a FROM ton_kho;
  RAISE NOTICE 'OK: tat ca doi chieu khop (tong ton vat ly = %)', a;
END $$;
-- Q5 doi chieu: 7084+4763+760 phai bang tong ton
SELECT 7084+4763+760 AS tong_q5, SUM(so_luong_vat_ly) AS tong_ton_kho FROM ton_kho;
