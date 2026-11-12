# =====================================================================
# DEMO LIVE HE THONG CSDL - OMNISTOCK (demo_live.ps1)
# =====================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$psql = $env:PSQL_PATH
if (-not $psql -or -not (Test-Path $psql)) {
    $cmdPsql = Get-Command psql -ErrorAction SilentlyContinue
    if ($cmdPsql) { $psql = $cmdPsql.Source }
}
if (-not $psql -or -not (Test-Path $psql)) {
    $candidates = @(
        (Join-Path $scriptDir "pgsql\bin\psql.exe"),
        (Join-Path (Split-Path -Parent $scriptDir) "pgsql\bin\psql.exe"),
        "C:\Program Files\PostgreSQL\17\bin\psql.exe",
        "C:\Program Files\PostgreSQL\16\bin\psql.exe",
        "C:\Program Files\PostgreSQL\15\bin\psql.exe",
        "C:\Program Files\PostgreSQL\14\bin\psql.exe",
        "/usr/bin/psql",
        "/usr/local/bin/psql"
    )
    $pfMatches = Get-Item "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    if ($pfMatches) { $candidates += ($pfMatches | ForEach-Object { $_.FullName }) }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { $psql = $c; break }
    }
}

if (-not $psql -or -not (Test-Path $psql)) {
    Write-Host "Khong tim thay psql.exe! Vui long cai dat PostgreSQL hoac dat bien moi truong PSQL_PATH." -ForegroundColor Red
    exit 1
}

if (-not $env:PGHOST) { $env:PGHOST = "127.0.0.1" }
if (-not $env:PGPORT) { $env:PGPORT = "5432" }
if (-not $env:PGUSER) { $env:PGUSER = "postgres" }
if (-not $env:PGDATABASE) { $env:PGDATABASE = "ecom" }
$env:PGCLIENTENCODING = "UTF8"

function Run-Sql($sqlText) {
    $tempFile = [System.IO.Path]::GetTempFileName() + ".sql"
    [System.IO.File]::WriteAllText($tempFile, $sqlText, [System.Text.Encoding]::UTF8)
    & $psql -X -q -P pager=off -f $tempFile
    Remove-Item -Force $tempFile -ErrorAction SilentlyContinue
}

function Show-Header {
    Clear-Host
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "   DO AN CSDL: SAN THUONG MAI DIEN TU DA KENH & KHO THONG MINH           " -ForegroundColor Yellow
    Write-Host "   TRINH DIEN HOAT DONG DONG THOI GIAN THUC (LIVE CSDL RUNNER)            " -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Pause-Step($msg = "Nhan phim Enter de tiep tuc...") {
    Write-Host ""
    Write-Host $msg -ForegroundColor DarkGray
    $null = [Console]::ReadKey($true)
}

function Scenario-1 {
    Show-Header
    Write-Host ">>> KICH BAN 1: VONG DOI 1 DON HANG (DAT HANG -> GIU -> XUAT -> GIAO THANH CONG)" -ForegroundColor Yellow
    Write-Host "Chung minh: Trigger tu dong giu kho, ghi so cai bien dong va cap nhat doanh thu." -ForegroundColor Gray
    Write-Host "--------------------------------------------------------------------------"
    
    Write-Host "[Buoc 1] Xem ton kho ban dau cua Bien the 1 (Dien thoai Aurora X1 Den 128GB tai Kho 1):" -ForegroundColor Cyan
    Run-Sql @'
    SELECT t.ma_kho, k.ten_kho, b.ma_bien_the, s.ten_san_pham, b.mau_sac,
           t.so_luong_vat_ly, t.so_luong_giu,
           (t.so_luong_vat_ly - t.so_luong_giu) AS so_luong_kha_dung
    FROM ton_kho t
    JOIN kho k ON k.ma_kho = t.ma_kho
    JOIN bien_the b ON b.ma_bien_the = t.ma_bien_the
    JOIN san_pham s ON s.ma_san_pham = b.ma_san_pham
    WHERE t.ma_kho = 1 AND t.ma_bien_the = 1;
'@
    Pause-Step

    Write-Host "[Buoc 2] Khach hang 'Nguyen Van A' dat don hang moi mua 2 chiec (fn_tao_don_hang):" -ForegroundColor Cyan
    Run-Sql @'
    DO $$
    DECLARE
        v_ma_don INT;
    BEGIN
        v_ma_don := fn_tao_don_hang(1, 1, 1, now()::timestamp, NULL, '[{"bt":1, "sl":2}]'::jsonb, 'Web');
        RAISE NOTICE 'Da tao thanh cong don hang moi: ma_don_hang = % (Trang thai: ChoXacNhan)', v_ma_don;
    END $$;
'@
    Write-Host "-> Don vua tao o trang thai ChoXacNhan (Chua giu kho)." -ForegroundColor Green
    Pause-Step

    Write-Host "[Buoc 3] He thong xac nhan don (ChoXacNhan -> DaXacNhan):" -ForegroundColor Cyan
    Run-Sql @'
    DO $$
    DECLARE
        v_ma_don INT;
    BEGIN
        SELECT max(ma_don_hang) INTO v_ma_don FROM don_hang WHERE ma_khach_hang = 1;
        UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = v_ma_don;
        RAISE NOTICE 'Cap nhat don % sang DaXacNhan (Kho bat dau GIU HANG)', v_ma_don;
    END $$;

    SELECT t.ma_kho, b.ma_bien_the, t.so_luong_vat_ly, t.so_luong_giu,
           (t.so_luong_vat_ly - t.so_luong_giu) AS so_luong_kha_dung
    FROM ton_kho t
    JOIN bien_the b ON b.ma_bien_the = t.ma_bien_the
    WHERE t.ma_kho = 1 AND t.ma_bien_the = 1;

    SELECT ma_bien_dong, loai, delta_vat_ly, delta_giu, ma_don_hang, ly_do, thoi_diem
    FROM bien_dong_kho
    WHERE ma_don_hang = (SELECT max(ma_don_hang) FROM don_hang WHERE ma_khach_hang = 1);
'@
    Write-Host "=> GIAI THICH: Trigger fn_cap_nhat_ton_kho da tu dong tang so_luong_giu len +2 va ghi dong GIU vao so cai!" -ForegroundColor Magenta
    Pause-Step

    Write-Host "[Buoc 4] Kho dong goi va giao cho shipper (DaXacNhan -> DangGiao):" -ForegroundColor Cyan
    Run-Sql @'
    DO $$
    DECLARE
        v_ma_don INT;
    BEGIN
        SELECT max(ma_don_hang) INTO v_ma_don FROM don_hang WHERE ma_khach_hang = 1;
        UPDATE don_hang SET trang_thai = 'DangGiao' WHERE ma_don_hang = v_ma_don;
        RAISE NOTICE 'Cap nhat don % sang DangGiao (Hang xuat kho)', v_ma_don;
    END $$;

    SELECT t.ma_kho, b.ma_bien_the, t.so_luong_vat_ly, t.so_luong_giu,
           (t.so_luong_vat_ly - t.so_luong_giu) AS so_luong_kha_dung
    FROM ton_kho t
    JOIN bien_the b ON b.ma_bien_the = t.ma_bien_the
    WHERE t.ma_kho = 1 AND t.ma_bien_the = 1;

    SELECT ma_bien_dong, loai, delta_vat_ly, delta_giu, ma_don_hang, ly_do, thoi_diem
    FROM bien_dong_kho
    WHERE ma_don_hang = (SELECT max(ma_don_hang) FROM don_hang WHERE ma_khach_hang = 1)
    ORDER BY ma_bien_dong;
'@
    Write-Host "=> GIAI THICH: Hang roi kho -> so_luong_vat_ly giam -2, so_luong_giu tra ve 0, so cai ghi nhan XUAT!" -ForegroundColor Magenta
    Pause-Step

    Write-Host "[Buoc 5] Khach nhan hang thanh cong (DangGiao -> DaGiao):" -ForegroundColor Cyan
    Run-Sql @'
    DO $$
    DECLARE
        v_ma_don INT;
    BEGIN
        SELECT max(ma_don_hang) INTO v_ma_don FROM don_hang WHERE ma_khach_hang = 1;
        UPDATE don_hang SET trang_thai = 'DaGiao' WHERE ma_don_hang = v_ma_don;
        RAISE NOTICE 'Cap nhat don % sang DaGiao (Giao thanh cong!)', v_ma_don;
    END $$;

    SELECT ma_lich_su, ma_don_hang, trang_thai_cu, trang_thai_moi, thoi_diem
    FROM lich_su_trang_thai
    WHERE ma_don_hang = (SELECT max(ma_don_hang) FROM don_hang WHERE ma_khach_hang = 1)
    ORDER BY ma_lich_su;
'@
    Pause-Step "Hoan thanh Kich ban 1. Nhan Enter de quay ve Menu..."
}

function Scenario-2 {
    Show-Header
    Write-Host ">>> KICH BAN 2: KHACH BOM HANG / HUY DON (ROLLBACK & NHA TON KHO)" -ForegroundColor Yellow
    Write-Host "Chung minh: Khi don da giu hang bi huy, trigger tu dong tra lai ton kha dung." -ForegroundColor Gray
    Write-Host "--------------------------------------------------------------------------"

    Write-Host "[Buoc 1] Tao don moi va xac nhan don de giu hang (5 chiec Bien the 2):" -ForegroundColor Cyan
    Run-Sql @'
    DO $$
    DECLARE
        v_ma_don INT;
    BEGIN
        v_ma_don := fn_tao_don_hang(2, 1, 1, now()::timestamp, NULL, '[{"bt":2, "sl":5}]'::jsonb, 'Web');
        UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = v_ma_don;
        RAISE NOTICE 'Da tao va xac nhan don hang % giu 5 chiec', v_ma_don;
    END $$;

    SELECT ma_kho, ma_bien_the, so_luong_vat_ly, so_luong_giu,
           (so_luong_vat_ly - so_luong_giu) AS so_luong_kha_dung
    FROM ton_kho
    WHERE ma_kho = 1 AND ma_bien_the = 2;
'@
    Pause-Step

    Write-Host "[Buoc 2] Khach yeu cau huy don (DaXacNhan -> DaHuy):" -ForegroundColor Cyan
    Run-Sql @'
    DO $$
    DECLARE
        v_ma_don INT;
    BEGIN
        SELECT max(ma_don_hang) INTO v_ma_don FROM don_hang WHERE ma_khach_hang = 2;
        UPDATE don_hang SET trang_thai = 'DaHuy' WHERE ma_don_hang = v_ma_don;
        RAISE NOTICE 'Don hang % da chuyen sang DaHuy', v_ma_don;
    END $$;

    SELECT ma_kho, ma_bien_the, so_luong_vat_ly, so_luong_giu,
           (so_luong_vat_ly - so_luong_giu) AS so_luong_kha_dung
    FROM ton_kho
    WHERE ma_kho = 1 AND ma_bien_the = 2;

    SELECT ma_bien_dong, loai, delta_vat_ly, delta_giu, ma_don_hang, ly_do, thoi_diem
    FROM bien_dong_kho
    WHERE ma_don_hang = (SELECT max(ma_don_hang) FROM don_hang WHERE ma_khach_hang = 2)
    ORDER BY ma_bien_dong;
'@
    Write-Host "=> GIAI THICH: Trigger fn_cap_nhat_ton_kho phat hien DaHuy -> Tu dong tru so_luong_giu ve lai cu va ghi dong NHA_GIU!" -ForegroundColor Magenta
    Pause-Step "Hoan thanh Kich ban 2. Nhan Enter de quay ve Menu..."
}

function Scenario-3 {
    Show-Header
    Write-Host ">>> KICH BAN 3: TRANH MUA FLASH SALE (LIVE RACE CONDITION / CONCURRENCY)" -ForegroundColor Yellow
    Write-Host "Chung minh: 2 khach tranh nhau mua 1 san pham cuoi cung, CSDL khoa hang va chan khong bao gio am kho." -ForegroundColor Gray
    Write-Host "--------------------------------------------------------------------------"

    Write-Host "[Buoc 1] Nhap kho san pham Flash Sale moi: dung 1 chiec duy nhat vao Kho 1:" -ForegroundColor Cyan
    Run-Sql @'
    DO $$
    DECLARE
        v_bt INT;
        v_sku TEXT := 'FLASH-' || to_char(now(), 'HH24MISS');
    BEGIN
        INSERT INTO bien_the(ma_san_pham, sku, mau_sac, kich_co, gia_nhap, gia_ban)
        VALUES (1, v_sku, 'Titan Sa Mac', '512GB', 25000000, 32000000)
        RETURNING ma_bien_the INTO v_bt;

        PERFORM fn_nhap_kho(1, v_bt, 1, 'Nhap kho san pham Flash Sale');
        RAISE NOTICE 'Da tao san pham Flash Sale SKU: %, ma_bien_the = % (Ton = 1)', v_sku, v_bt;
    END $$;

    SELECT t.ma_kho, b.ma_bien_the, b.sku, b.mau_sac,
           t.so_luong_vat_ly, t.so_luong_giu,
           (t.so_luong_vat_ly - t.so_luong_giu) AS so_luong_kha_dung
    FROM ton_kho t
    JOIN bien_the b ON b.ma_bien_the = t.ma_bien_the
    WHERE t.ma_kho = 1 AND b.ma_bien_the = (SELECT max(ma_bien_the) FROM bien_the);
'@
    Pause-Step

    Write-Host "[Buoc 2] Gia lap 2 giao dich dong thoi tranh mua mon hang cuoi cung:" -ForegroundColor Cyan
    Write-Host "  - Khach A dat mua 1 chiec." -ForegroundColor White
    Write-Host "  - Khach B dat mua 1 chiec tai cung thoi diem." -ForegroundColor White
    Write-Host "Dang thuc hien kiem tra khoa hang va xac nhan..." -ForegroundColor DarkYellow

    Run-Sql @'
    DO $$
    DECLARE
        v_bt INT;
        don_a INT;
        don_b INT;
        err_msg TEXT;
    BEGIN
        SELECT max(ma_bien_the) INTO v_bt FROM bien_the;

        -- Tao 2 don hang
        don_a := fn_tao_don_hang(3, 1, 1, now()::timestamp, NULL, jsonb_build_array(jsonb_build_object('bt', v_bt, 'sl', 1)), 'Web');
        don_b := fn_tao_don_hang(4, 1, 1, now()::timestamp, NULL, jsonb_build_array(jsonb_build_object('bt', v_bt, 'sl', 1)), 'Web');

        -- Don A xac nhan truoc -> Giu duoc chiec cuoi cung
        UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = don_a;
        RAISE NOTICE '>>> KHACH A: Xac nhan thanh cong! Don hang % da giu duoc san pham.', don_a;

        -- Don B co xac nhan -> Bi chan ngay lap tuc vi ton kha dung = 0
        BEGIN
            UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = don_b;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
            RAISE NOTICE '>>> KHACH B BI CHAN BOI CSDL: %', err_msg;
            UPDATE don_hang SET trang_thai = 'DaHuy' WHERE ma_don_hang = don_b;
        END;
    END $$;

    SELECT t.ma_kho, b.ma_bien_the, b.sku, t.so_luong_vat_ly, t.so_luong_giu,
           (t.so_luong_vat_ly - t.so_luong_giu) AS so_luong_kha_dung
    FROM ton_kho t
    JOIN bien_the b ON b.ma_bien_the = t.ma_bien_the
    WHERE t.ma_kho = 1 AND b.ma_bien_the = (SELECT max(ma_bien_the) FROM bien_the);
'@
    Write-Host "=> KET LUAN: Chi duy nhat Khach A giu duoc hang. Ton kha dung ve 0, so_luong_giu = 1, khong bao gio bi am!" -ForegroundColor Magenta
    Pause-Step "Hoan thanh Kich ban 3. Nhan Enter de quay ve Menu..."
}

function Scenario-4 {
    Show-Header
    Write-Host ">>> KICH BAN 4: THU NGHIEM TINH TOAN VEN & RANG BUOC (DATABASE GUARDRAIL)" -ForegroundColor Yellow
    Write-Host "Chung minh: CSDL chu dong tu bao ve, chan dung moi hanh vi gian lan hoac du lieu sai lech." -ForegroundColor Gray
    Write-Host "--------------------------------------------------------------------------"

    Write-Host "[Thu nghiem 1] Co tinh nhay coc trang thai (ChoXacNhan nhay thang sang DaGiao):" -ForegroundColor Cyan
    Run-Sql @'
    DO $$
    DECLARE
        v_ma_don INT;
    BEGIN
        v_ma_don := fn_tao_don_hang(1, 1, 1, now()::timestamp, NULL, '[{"bt":1, "sl":1}]'::jsonb, 'Web');
        BEGIN
            UPDATE don_hang SET trang_thai = 'DaGiao' WHERE ma_don_hang = v_ma_don;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'CSDL TU CHOI THANH CONG: %', SQLERRM;
        END;
    END $$;
'@
    Write-Host "=> Giai thich: Trigger fn_chuyen_trang_thai chan dung vi pham quy trinh nghiep vu!" -ForegroundColor Green
    Pause-Step

    Write-Host "[Thu nghiem 2] Co tinh ap dung Voucher gian lan (Don 100k doi ap Voucher yeu cau toi thieu 500k):" -ForegroundColor Cyan
    Run-Sql @'
    DO $$
    BEGIN
        INSERT INTO don_hang(ma_khach_hang, ma_gian_hang, ma_kho_xuat, ma_voucher, nguoi_nhan, dien_thoai_nhan, dia_chi_giao, kenh_ban, trang_thai, tong_tien_hang, tien_giam, ngay_dat)
        VALUES (1, 1, 1, 1, 'Hack Voucher', '0999999999', 'Ha Noi', 'Web', 'ChoXacNhan', 100000, 50000, now());
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'CSDL TU CHOI VOUCHER GIAN LAN: %', SQLERRM;
    END $$;
'@
    Write-Host "=> Giai thich: Trigger fn_kiem_tra_voucher tu kiem tra gia_tri_toi_thieu va han dung truoc khi cho insert!" -ForegroundColor Green
    Pause-Step

    Write-Host "[Thu nghiem 3] Co tinh danh gia san pham khi don hang CHUA GIAO THANH CONG:" -ForegroundColor Cyan
    Run-Sql @'
    DO $$
    DECLARE
        v_ma_don INT;
    BEGIN
        SELECT max(ma_don_hang) INTO v_ma_don FROM don_hang WHERE trang_thai <> 'DaGiao';
        INSERT INTO danh_gia(ma_don_hang, ma_bien_the, so_sao, noi_dung)
        VALUES (v_ma_don, 1, 5, 'Hang rat tot!');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'CSDL TU CHOI DANH GIA: %', SQLERRM;
    END $$;
'@
    Write-Host "=> Giai thich: Trigger fn_kiem_tra_danh_gia ngan chan seeding danh gia ao cho don chua giao!" -ForegroundColor Green
    Pause-Step "Hoan thanh Kich ban 4. Nhan Enter de quay ve Menu..."
}

function Scenario-5 {
    Show-Header
    Write-Host ">>> KICH BAN 5: BANG DIEU KHIEN THOI GIAN THUC (REAL-TIME ANALYTICS DASHBOARD)" -ForegroundColor Yellow
    Write-Host "Chung minh: Cac truy van phan tich phuc tap tren nua trieu dong du lieu." -ForegroundColor Gray
    Write-Host "--------------------------------------------------------------------------"

    Write-Host "[1] Tinh trang doi soat so cai toan bo 5 kho hang (v_doi_soat_kho):" -ForegroundColor Cyan
    Run-Sql @'
    SELECT bool_and(khop) AS toan_bo_so_cai_khop,
           COUNT(*) AS tong_so_dong_ton_kho,
           COUNT(*) FILTER (WHERE NOT khop) AS so_dong_lech
    FROM v_doi_soat_kho;
'@

    Write-Host "[2] Top 5 san pham ban chay nhat (theo tong so luong da giao):" -ForegroundColor Cyan
    Run-Sql @'
    SELECT s.ma_san_pham, s.ten_san_pham, dm.ten_danh_muc,
           SUM(ct.so_luong) AS tong_da_ban,
           to_char(SUM(ct.so_luong * ct.don_gia), 'FM999,999,999,999,999') || ' VND' AS tong_doanh_thu
    FROM chi_tiet_don_hang ct
    JOIN don_hang d ON d.ma_don_hang = ct.ma_don_hang
    JOIN bien_the b ON b.ma_bien_the = ct.ma_bien_the
    JOIN san_pham s ON s.ma_san_pham = b.ma_san_pham
    JOIN danh_muc dm ON dm.ma_danh_muc = s.ma_danh_muc
    WHERE d.trang_thai = 'DaGiao'
    GROUP BY s.ma_san_pham, s.ten_san_pham, dm.ten_danh_muc
    ORDER BY tong_da_ban DESC
    LIMIT 5;
'@

    Write-Host "[3] Ty le phan bo doanh thu thuan theo kenh ban hang (don DaGiao, Toan ky mo phong chot 2026-11-30):" -ForegroundColor Cyan
    Run-Sql @'
    SELECT d.kenh_ban,
           COUNT(d.ma_don_hang) AS so_don_giao,
           to_char(SUM(d.tong_tien_hang - d.tien_giam), 'FM999,999,999,999,999') || ' VND' AS doanh_thu_thuan,
           ROUND(100.0 * SUM(d.tong_tien_hang - d.tien_giam) / NULLIF((SELECT SUM(tong_tien_hang - tien_giam) FROM don_hang WHERE trang_thai = 'DaGiao'), 0), 2) || '%' AS ty_trong
    FROM don_hang d
    WHERE d.trang_thai = 'DaGiao'
    GROUP BY d.kenh_ban
    ORDER BY SUM(d.tong_tien_hang - d.tien_giam) DESC;
'@

    Write-Host "[4] Truy van Q8 (Doanh thu luy ke Thang 10/2026 & ngay cham moc 1 ty VND):" -ForegroundColor Cyan
    Write-Host "    - Tren tap seed_nho (161 don goc): cham moc 1 ty VND vao ngay 2026-10-18." -ForegroundColor Gray
    Write-Host "    - Tren tap seed_lon (400.161 don): cham moc 1 ty VND ngay 2026-10-01 (~39,18 ty VND) va cham 500 ty VND vao ngay 2026-10-13." -ForegroundColor Gray
    Run-Sql @'
    WITH doanh_thu_ngay AS (
        SELECT d.ngay_dat::date AS ngay,
               DATE_TRUNC('month', d.ngay_dat)::date AS thang,
               SUM(d.tong_tien_hang - d.tien_giam) AS doanh_thu
        FROM don_hang d
        WHERE d.ma_don_hang <= 161
          AND d.trang_thai = 'DaGiao'
          AND d.ngay_dat >= DATE '2026-10-01' AND d.ngay_dat < DATE '2026-11-01'
        GROUP BY d.ngay_dat::date, DATE_TRUNC('month', d.ngay_dat)::date
    ),
    luy_ke AS (
        SELECT ngay, thang, doanh_thu,
               SUM(doanh_thu) OVER (PARTITION BY thang ORDER BY ngay) AS luy_ke
        FROM doanh_thu_ngay
    )
    SELECT ngay,
           to_char(doanh_thu, 'FM999,999,999,999,999') AS doanh_thu_ngay_seed_nho,
           to_char(luy_ke, 'FM999,999,999,999,999')    AS luy_ke_seed_nho,
           CASE WHEN luy_ke >= 1000000000
                 AND COALESCE(LAG(luy_ke) OVER (PARTITION BY thang ORDER BY ngay), 0) < 1000000000
                THEN '<== DAT MOC 1 TY (seed_nho)' END AS ghi_chu
    FROM luy_ke
    WHERE ngay BETWEEN DATE '2026-10-14' AND DATE '2026-10-20'
    ORDER BY ngay;
'@
    Pause-Step "Hoan thanh Kich ban 5. Nhan Enter de quay ve Menu..."
}

# Vong lap Menu chinh
do {
    Show-Header
    Write-Host "Chon kich ban can theo doi hoat dong CSDL:" -ForegroundColor White
    Write-Host "  [1] Vong doi 1 don hang (Dat -> Giu kho -> Xuat kho -> Giao thanh cong)" -ForegroundColor Cyan
    Write-Host "  [2] Bom hang / Huy don (Tu dong nha giu kho -> Hoan so cai)" -ForegroundColor Cyan
    Write-Host "  [3] Tranh mua Flash Sale (2 khach tranh nhau 1 mon cuoi -> Khoa hang, khong am kho)" -ForegroundColor Cyan
    Write-Host "  [4] Kiem tra tinh toan ven (Chan nhay coc trang thai, chan voucher gian lan, chan danh gia ao)" -ForegroundColor Cyan
    Write-Host "  [5] Bang thong ke phan tich thoi gian thuc tren 400.000 don hang" -ForegroundColor Cyan
    Write-Host "  [0] Thoat" -ForegroundColor Yellow
    Write-Host ""
    $choice = Read-Host "Nhap lua chon cua ban (0-5)"

    switch ($choice) {
        "1" { Scenario-1 }
        "2" { Scenario-2 }
        "3" { Scenario-3 }
        "4" { Scenario-4 }
        "5" { Scenario-5 }
        "0" { Write-Host "Tam biet!"; break }
        default { Write-Host "Lua chon khong hop le!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
} while ($choice -ne "0")
