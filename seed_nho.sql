-- =====================================================================
-- DU LIEU MAU NHO (chay SAU schema.sql)
-- Chay: psql -U postgres -d ecom -f seed_nho.sql
-- Co chu y de kiem tra 8 truy van:
--   Q1  San pham thuoc "Dien thoai" (ca danh muc con), diem TB >= 4.5
--   Q2  Khach "Nguyen Van A" co don hang
--   Q3/Q4 Don thang 10/2026, co don huy theo tung gian hang
--   Q5  Danh muc cap 1 "Sach" khong co san pham
--   Q6  Khach dang ky > 1 nam chua tung dat don (Tran Thi B)
--   Q7  Cung nha cung cap co nhieu san pham, gia khac nhau
--   Q8  Doanh thu luy ke thang 10/2026 vuot 1 ty
-- Du lieu ngau nhien co dinh (setseed) nen chay lai se ra ket qua giong nhau.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Danh muc (3 cap), NCC, gian hang, kho
-- ---------------------------------------------------------------------
INSERT INTO danh_muc(ma_danh_muc, ten_danh_muc, ma_danh_muc_cha) VALUES
 (1, 'Điện tử', NULL),
 (2, 'Điện thoại', 1),
 (3, 'Laptop', 1),
 (4, 'Điện thoại cao cấp', 2),
 (5, 'Thời trang', NULL),
 (6, 'Áo', 5),
 (7, 'Quần', 5),
 (8, 'Gia dụng', NULL),
 (9, 'Sách', NULL);              -- cap 1 chua co san pham (Q5)
SELECT setval('danh_muc_ma_danh_muc_seq', 9);

INSERT INTO nha_cung_cap(ma_ncc, ten_ncc, dien_thoai, dia_chi) VALUES
 (1, 'Công ty Aurora Việt Nam', '0281111111', 'Quận 7, TP.HCM'),
 (2, 'Nimbus Distribution',     '0282222222', 'Thủ Đức, TP.HCM'),
 (3, 'May mặc Sao Mai',         '0243333333', 'Hà Đông, Hà Nội'),
 (4, 'Gia dụng Hòa Bình',       '0244444444', 'Long Biên, Hà Nội');
SELECT setval('nha_cung_cap_ma_ncc_seq', 4);

INSERT INTO gian_hang(ma_gian_hang, ten_gian_hang, email, ngay_tham_gia) VALUES
 (1, 'Aurora Official Store', 'aurora@shop.vn',   '2024-03-01'),
 (2, 'TechZone HCM',          'techzone@shop.vn', '2024-06-15'),
 (3, 'Thời trang Sao Mai',    'saomai@shop.vn',   '2025-01-10'),
 (4, 'Nhà Bếp Xinh',          'nhabep@shop.vn',   '2025-05-20');
SELECT setval('gian_hang_ma_gian_hang_seq', 4);

INSERT INTO kho(ma_kho, ten_kho, tinh_tp, dia_chi) VALUES
 (1, 'Kho Thủ Đức', 'TP.HCM',  'KCN Linh Trung, Thủ Đức'),
 (2, 'Kho Hà Nội',  'Hà Nội',  'KCN Quang Minh, Mê Linh');
SELECT setval('kho_ma_kho_seq', 2);

-- ---------------------------------------------------------------------
-- San pham + bien the
-- ---------------------------------------------------------------------
INSERT INTO san_pham(ma_san_pham, ma_gian_hang, ma_danh_muc, ma_ncc, ten_san_pham, mo_ta) VALUES
 (1, 1, 2, 1, 'Điện thoại Aurora X1',     'Màn hình 6.5 inch, pin 5000mAh'),
 (2, 1, 4, 1, 'Điện thoại Aurora X1 Pro', 'Camera 108MP, sạc nhanh 67W'),
 (3, 2, 2, 2, 'Điện thoại Nimbus N5',     'Thiết kế mỏng nhẹ'),
 (4, 2, 3, 2, 'Laptop Nimbus Air 14',     'Mỏng nhẹ cho văn phòng'),
 (5, 3, 6, 3, 'Áo thun cotton basic',     'Cotton 100%'),
 (6, 3, 7, 3, 'Quần jeans slim fit',      'Co giãn nhẹ'),
 (7, 4, 8, 4, 'Nồi chiên không dầu 5L',   'Công suất 1700W');
SELECT setval('san_pham_ma_san_pham_seq', 7);

INSERT INTO bien_the(ma_bien_the, ma_san_pham, sku, mau_sac, kich_co, gia_nhap, gia_ban) VALUES
 ( 1, 1, 'AX1-DEN-128',  'Đen',   '128GB',  6500000,  8900000),
 ( 2, 1, 'AX1-TRG-128',  'Trắng', '128GB',  6500000,  8900000),
 ( 3, 1, 'AX1-DEN-256',  'Đen',   '256GB',  7800000, 10500000),
 ( 4, 2, 'AX1P-XAM-256', 'Xám',   '256GB', 18000000, 24900000),
 ( 5, 2, 'AX1P-XAM-512', 'Xám',   '512GB', 22000000, 29900000),
 ( 6, 3, 'N5-XNH-128',   'Xanh',  '128GB',  5200000,  7400000),
 ( 7, 3, 'N5-DEN-256',   'Đen',   '256GB',  6900000,  9200000),
 ( 8, 4, 'NA14-BAC-16',  'Bạc',   '16GB',  17000000, 22900000),
 ( 9, 4, 'NA14-XAM-32',  'Xám',   '32GB',  21000000, 28500000),
 (10, 5, 'AT-TRG-S',     'Trắng', 'S',        70000,    159000),
 (11, 5, 'AT-TRG-M',     'Trắng', 'M',        70000,    159000),
 (12, 5, 'AT-TRG-L',     'Trắng', 'L',        70000,    159000),
 (13, 5, 'AT-DEN-M',     'Đen',   'M',        70000,    159000),
 (14, 6, 'QJ-XNH-30',    'Xanh',  '30',      180000,    399000),
 (15, 6, 'QJ-XNH-32',    'Xanh',  '32',      180000,    399000),
 (16, 7, 'NCK-DEN-5L',   'Đen',   '5L',      800000,   1490000);
SELECT setval('bien_the_ma_bien_the_seq', 16);

-- Nhap kho dau ky: 400 cai moi bien the o moi kho (qua ham nen co so cai)
SELECT fn_nhap_kho(k.ma_kho, b.ma_bien_the, 400, 'Nhap kho dau ky')
FROM kho k CROSS JOIN bien_the b;

-- ---------------------------------------------------------------------
-- Khach hang + dia chi
-- ---------------------------------------------------------------------
INSERT INTO khach_hang(ma_khach_hang, ho_ten, email, dien_thoai, dia_chi, ngay_dang_ky) VALUES
 (1, 'Nguyễn Văn A', 'nguyenvana@mail.vn', '0901000001', '12 Lê Lợi, Quận 1, TP.HCM',        '2025-01-15'),
 (2, 'Lê Minh Cường', 'leminhcuong@mail.vn', '0901000002', '45 Trần Phú, Hà Đông, Hà Nội',   '2025-02-20'),
 (3, 'Phạm Thu Dung', 'phamthudung@mail.vn', '0901000003', '8 Nguyễn Huệ, Quận 1, TP.HCM',   '2025-06-05'),
 (4, 'Vũ Quang Phúc', 'vuquangphuc@mail.vn', '0901000004', '99 Láng Hạ, Đống Đa, Hà Nội',    '2025-09-12'),
 (5, 'Trần Thị B', 'tranthib@mail.vn', '0901000005', '3 Hai Bà Trưng, Quận 3, TP.HCM',       '2025-03-10'),   -- >1 nam, chua mua (Q6)
 (6, 'Hoàng Gia Em', 'hoanggiaem@mail.vn', '0901000006', '27 Cầu Giấy, Cầu Giấy, Hà Nội',    '2026-10-20');   -- moi, chua mua
SELECT setval('khach_hang_ma_khach_hang_seq', 6);

-- ---------------------------------------------------------------------
-- Voucher
-- ---------------------------------------------------------------------
INSERT INTO voucher(ma_voucher, ma_code, ma_gian_hang, phan_tram_giam, gia_tri_toi_thieu, giam_toi_da, ngay_bat_dau, ngay_het_han) VALUES
 (1, 'THANG10',  NULL, 10, 1000000,  500000, '2026-10-01', '2026-10-31'),  -- voucher san
 (2, 'AURORA5',  1,     5, 5000000,    NULL, '2026-09-15', '2026-11-30'),  -- voucher shop
 (3, 'HETHAN20', NULL, 20,  500000, 1000000, '2026-01-01', '2026-06-30');  -- da het han (de test)
SELECT setval('voucher_ma_voucher_seq', 3);

-- ---------------------------------------------------------------------
-- Ham tao don fn_tao_don_hang(...) duoc dinh nghia CHINH THUC trong schema.sql
-- (kiem tra dau vao: danh sach rong, SKU khong ton tai, so luong <= 0, SKU trung;
--  khoa chong trung theo (khach, idempotency_key)). File seed chi goi ham.
-- p_items vi du: '[{"bt":1,"sl":2},{"bt":3,"sl":1}]'
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- Don ro rang de test tay: khach "Nguyen Van A" mua dien thoai (Q2)
-- ---------------------------------------------------------------------
DO $$
DECLARE d INT;
BEGIN
    d := fn_tao_don_hang(1, 1, 1, '2026-10-02 09:30', 1,
            '[{"bt":1,"sl":2},{"bt":3,"sl":1}]', 'Web', 'demo-A-001');
    UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = d;
    UPDATE don_hang SET trang_thai = 'DangGiao'  WHERE ma_don_hang = d;
    UPDATE don_hang SET trang_thai = 'DaGiao'    WHERE ma_don_hang = d;
END $$;

-- ---------------------------------------------------------------------
-- 160 don ngau nhien thang 10/2026 (co dinh bang setseed)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    i INT; r FLOAT; target TEXT;
    v_khach INT; v_gh INT; v_kho INT; v_bt INT; v_bt2 INT; v_sl INT;
    v_ngay TIMESTAMP; v_vc INT; v_don INT; v_tong NUMERIC; v_items JSONB;
BEGIN
    PERFORM setseed(0.42);
    FOR i IN 1..160 LOOP
        v_khach := 1 + floor(random() * 4)::INT;            -- khach 1..4
        v_kho   := 1 + floor(random() * 2)::INT;
        r := random();
        v_gh := CASE WHEN r < 0.30 THEN 1 WHEN r < 0.60 THEN 2 WHEN r < 0.80 THEN 3 ELSE 4 END;

        SELECT b.ma_bien_the INTO v_bt
        FROM bien_the b JOIN san_pham s ON s.ma_san_pham = b.ma_san_pham
        WHERE s.ma_gian_hang = v_gh ORDER BY random() LIMIT 1;
        v_sl := 1 + floor(random() * 2)::INT;
        v_items := jsonb_build_array(jsonb_build_object('bt', v_bt, 'sl', v_sl));

        IF random() < 0.3 THEN                               -- them dong thu 2 khac bien the
            SELECT b.ma_bien_the INTO v_bt2
            FROM bien_the b JOIN san_pham s ON s.ma_san_pham = b.ma_san_pham
            WHERE s.ma_gian_hang = v_gh AND b.ma_bien_the <> v_bt ORDER BY random() LIMIT 1;
            IF v_bt2 IS NOT NULL THEN
                v_items := v_items || jsonb_build_array(jsonb_build_object('bt', v_bt2, 'sl', 1));
            END IF;
        END IF;

        SELECT SUM(b.gia_ban * (e->>'sl')::INT) INTO v_tong
        FROM jsonb_array_elements(v_items) e JOIN bien_the b ON b.ma_bien_the = (e->>'bt')::INT;

        v_vc := NULL;
        IF v_tong >= 1000000 AND random() < 0.4 THEN v_vc := 1; END IF;

        v_ngay := timestamp '2026-10-01 08:00' + random() * interval '30 days 12 hours';
        v_don := fn_tao_don_hang(v_khach, v_gh, v_kho, v_ngay, v_vc, v_items,
                                 (ARRAY['Web','CuaHang','DoiTac'])[1 + floor(random()*3)::INT]);

        r := random();
        target := CASE WHEN r < 0.62 THEN 'DaGiao'
                       WHEN r < 0.72 THEN 'DaHuy'
                       WHEN r < 0.86 THEN 'DangGiao'
                       WHEN r < 0.94 THEN 'DaXacNhan'
                       ELSE 'ChoXacNhan' END;

        IF target = 'DaHuy' THEN
            IF random() < 0.5 THEN
                UPDATE don_hang SET trang_thai = 'DaHuy' WHERE ma_don_hang = v_don;
            ELSE
                UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = v_don;
                UPDATE don_hang SET trang_thai = 'DaHuy' WHERE ma_don_hang = v_don;
            END IF;
        ELSIF target <> 'ChoXacNhan' THEN
            UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = v_don;
            IF target IN ('DangGiao','DaGiao') THEN
                UPDATE don_hang SET trang_thai = 'DangGiao' WHERE ma_don_hang = v_don;
            END IF;
            IF target = 'DaGiao' THEN
                UPDATE don_hang SET trang_thai = 'DaGiao' WHERE ma_don_hang = v_don;
            END IF;
        END IF;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Thanh toan, van chuyen, danh gia (suy ra tu trang thai don)
-- ---------------------------------------------------------------------
INSERT INTO thanh_toan(ma_don_hang, phuong_thuc, so_tien, trang_thai, thoi_diem)
SELECT ma_don_hang,
       (ARRAY['COD','ChuyenKhoan','TheTinDung','ViDienTu'])[1 + floor(random()*4)::INT],
       tong_tien_hang - tien_giam + phi_van_chuyen,
       CASE trang_thai WHEN 'DaGiao' THEN 'ThanhCong' WHEN 'DaHuy' THEN 'ThatBai' ELSE 'ChoThanhToan' END,
       ngay_dat
FROM don_hang
WHERE trang_thai <> 'ChoXacNhan';

INSERT INTO van_chuyen(ma_don_hang, don_vi_vc, ma_van_don, ngay_giao_du_kien, ngay_giao_thuc_te)
SELECT ma_don_hang,
       (ARRAY['GHN','GHTK','ViettelPost'])[1 + floor(random()*3)::INT],
       'VD' || lpad(ma_don_hang::text, 8, '0'),
       ngay_dat::date + 3,
       CASE WHEN trang_thai = 'DaGiao' THEN ngay_dat::date + 3 + floor(random()*2)::INT END
FROM don_hang
WHERE trang_thai IN ('DangGiao','DaGiao');

-- Dien thoai Aurora (san pham 1, 2) co diem cao: 4-5 sao; con lai 3-5 sao
INSERT INTO danh_gia(ma_don_hang, ma_bien_the, so_sao, noi_dung, ngay_danh_gia)
SELECT c.ma_don_hang, c.ma_bien_the,
       CASE WHEN b.ma_san_pham IN (1, 2) THEN 4 + (random() < 0.7)::INT
            ELSE 3 + floor(random() * 3)::INT END,
       'Sản phẩm đúng mô tả, giao hàng nhanh',
       d.ngay_dat + interval '5 days'
FROM chi_tiet_don_hang c
JOIN don_hang d ON d.ma_don_hang = c.ma_don_hang
JOIN bien_the b ON b.ma_bien_the = c.ma_bien_the
WHERE d.trang_thai = 'DaGiao' AND random() < 0.6;

-- Cap nhat thong ke de planner dung so lieu moi
ANALYZE;
