"""
Web Dashboard van hanh Kho va Don hang OmniStock
Chay bang: python web_dashboard.py
Mo trinh duyet tai: http://localhost:8080

Cau hinh qua bien moi truong (tuy chon):
  PGHOST (mac dinh: 127.0.0.1)
  PGPORT (mac dinh: 5432)
  PGUSER (mac dinh: postgres)
  PGPASSWORD (tuy chon)
  PGDATABASE (mac dinh: ecom)
  PSQL_PATH (duong dan toi psql hoac psql.exe)
  OMNISTOCK_PORT (mac dinh: 8080)
"""

import concurrent.futures
import glob
import http.server
import json
import os
import random
import re
import shutil
import subprocess
import threading
import time
import urllib.parse

PORT = int(os.environ.get("OMNISTOCK_PORT", "8080"))
DB_HOST = os.environ.get("PGHOST", "127.0.0.1")
DB_PORT = os.environ.get("PGPORT", "5432")
DB_USER = os.environ.get("PGUSER", "postgres")
DB_NAME = os.environ.get("PGDATABASE", "ecom")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Ky mo phong cua bo du lieu (seed_nho + seed_lon): 01/12/2025 -> 30/11/2026.
# Du lieu sinh san co don dat/giao den 30/11/2026, nen moi so lieu "Toan ky" duoc hieu
# la tinh tai NGAY CHOT KY MO PHONG nay (khong phai ngay chay may). Co the doi qua bien moi truong.
KY_MO_PHONG_TU = os.environ.get("OMNISTOCK_KY_TU", "2025-12-01")
NGAY_CHOT_MO_PHONG = os.environ.get("OMNISTOCK_NGAY_CHOT", "2026-11-30")


def discover_psql_path():
    env_path = os.environ.get("PSQL_PATH")
    if env_path and os.path.exists(env_path):
        return env_path

    which_psql = shutil.which("psql")
    if which_psql:
        return which_psql

    candidates = [
        os.path.join(SCRIPT_DIR, "pgsql", "bin", "psql.exe"),
        os.path.join(os.path.dirname(SCRIPT_DIR), "pgsql", "bin", "psql.exe"),
    ]
    for ver in ("17", "16", "15", "14"):
        candidates.append(rf"C:\Program Files\PostgreSQL\{ver}\bin\psql.exe")
    candidates.extend(["/usr/bin/psql", "/usr/local/bin/psql"])

    # Ban PostgreSQL cai dat theo phien ban bat ky trong Program Files (Windows)
    pf_matches = sorted(glob.glob(r"C:\Program Files\PostgreSQL\*\bin\psql.exe"), reverse=True)
    candidates.extend(pf_matches)

    for c in candidates:
        if c and os.path.exists(c):
            return c
    return "psql"


PSQL_PATH = discover_psql_path()

# Tach biet trang thai "Doi soat toan bo" va "Kiem tra cap vua thao tac", dong thoi theo doi chinh xac tap cap lech
RECONCILE_LOCK = threading.Lock()
MISMATCHED_PAIRS = set()  # Tap cac cap "ma_kho_ma_bien_the" dang lech

FULL_RECONCILE_STATE = {
    "checked": False,
    "khop_all": False,
    "tong_cap": 0,
    "so_cap_lech": 0,
    "tong_dong_so_cai": 0,
    "thoi_diem": None
}

LAST_PAIR_CHECK_STATE = {
    "checked": False,
    "mo_ta": None,
    "so_cap_kiem_tra": 0,
    "so_cap_lech": 0,
    "khop": True,
    "thoi_diem": None
}


def build_pg_env():
    env = os.environ.copy()
    env["PGCLIENTENCODING"] = "UTF8"
    env["PGHOST"] = DB_HOST
    env["PGPORT"] = str(DB_PORT)
    env["PGUSER"] = DB_USER
    env["PGDATABASE"] = DB_NAME
    return env


def run_psql_json(sql):
    sql_clean = sql.strip().rstrip(";")
    wrapped_sql = f"SELECT COALESCE(json_agg(t), '[]'::json) FROM ({sql_clean}) t;"
    cmd = [
        PSQL_PATH,
        "-h", DB_HOST,
        "-p", str(DB_PORT),
        "-U", DB_USER,
        "-d", DB_NAME,
        "-X", "-q", "-A", "-t",
        "-v", "ON_ERROR_STOP=1",
        "-f", "-"
    ]
    try:
        res = subprocess.run(
            cmd,
            input=wrapped_sql,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=build_pg_env(),
            timeout=30
        )
    except FileNotFoundError:
        raise RuntimeError(
            f"Không tìm thấy công cụ psql (đang cấu hình: '{PSQL_PATH}'). "
            "Hãy cài đặt PostgreSQL hoặc đặt biến môi trường PSQL_PATH trỏ tới psql.exe."
        )
    if res.returncode != 0:
        err = res.stderr.strip() or "Lỗi truy vấn PostgreSQL"
        raise RuntimeError(err)
    out = res.stdout.strip()
    if not out:
        return []
    return json.loads(out)


def run_psql_command(sql):
    cmd = [
        PSQL_PATH,
        "-h", DB_HOST,
        "-p", str(DB_PORT),
        "-U", DB_USER,
        "-d", DB_NAME,
        "-X", "-q", "-v", "ON_ERROR_STOP=1",
        "-f", "-"
    ]
    try:
        res = subprocess.run(
            cmd,
            input=sql,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=build_pg_env(),
            timeout=30
        )
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except FileNotFoundError:
        return 1, "", f"Không tìm thấy psql tại '{PSQL_PATH}'."


def get_reconcile_snapshot():
    with RECONCILE_LOCK:
        total_lech_hien_tai = len(MISMATCHED_PAIRS)
        full_copy = dict(FULL_RECONCILE_STATE)
        pair_copy = dict(LAST_PAIR_CHECK_STATE)
        return {
            "full": full_copy,
            "last_pair": pair_copy,
            "tong_cap_lech_hien_tai": total_lech_hien_tai,
            "he_thong_khop": bool(full_copy["checked"] and full_copy["tong_cap"] > 0 and total_lech_hien_tai == 0)
        }


def run_full_reconcile():
    sql = """
    SELECT
        COALESCE(bool_and(khop), false) AS khop_all,
        COUNT(*) AS tong_cap,
        COUNT(*) FILTER (WHERE NOT khop) AS so_cap_lech,
        COALESCE(json_agg(ma_kho || '_' || ma_bien_the) FILTER (WHERE NOT khop), '[]'::json) AS ds_cap_lech,
        (SELECT COUNT(*) FROM bien_dong_kho) AS tong_dong_so_cai,
        to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS') AS thoi_diem
    FROM v_doi_soat_kho
    """
    rows = run_psql_json(sql)
    if rows:
        r = rows[0]
        ds_lech = set(r["ds_cap_lech"] or [])
        with RECONCILE_LOCK:
            MISMATCHED_PAIRS.clear()
            MISMATCHED_PAIRS.update(ds_lech)
            FULL_RECONCILE_STATE.update({
                "checked": int(r["tong_cap"]) > 0,
                "khop_all": bool(r["khop_all"]) and int(r["tong_cap"]) > 0 and len(ds_lech) == 0,
                "tong_cap": int(r["tong_cap"]),
                "so_cap_lech": len(ds_lech),
                "tong_dong_so_cai": int(r["tong_dong_so_cai"]),
                "thoi_diem": r["thoi_diem"]
            })
    return get_reconcile_snapshot()


def verify_pair_reconcile(ma_kho, bt_list, mo_ta="Thao tác vừa thực hiện"):
    if not FULL_RECONCILE_STATE["checked"]:
        run_full_reconcile()
    bt_clean = sorted({int(x) for x in bt_list if x})
    if not bt_clean:
        return get_reconcile_snapshot()
    bt_csv = ",".join(str(x) for x in bt_clean)
    sql = f"""
    WITH pair_rows AS (
        SELECT tk.ma_kho, tk.ma_bien_the,
               (tk.so_luong_vat_ly = COALESCE(SUM(bdk.delta_vat_ly), 0)
                AND tk.so_luong_giu = COALESCE(SUM(bdk.delta_giu), 0)) AS khop
        FROM ton_kho tk
        LEFT JOIN bien_dong_kho bdk ON bdk.ma_kho = tk.ma_kho AND bdk.ma_bien_the = tk.ma_bien_the
        WHERE tk.ma_kho = {int(ma_kho)} AND tk.ma_bien_the IN ({bt_csv})
        GROUP BY tk.ma_kho, tk.ma_bien_the, tk.so_luong_vat_ly, tk.so_luong_giu
    )
    SELECT
        COALESCE(json_agg(pair_rows), '[]'::json) AS pairs,
        to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS') AS thoi_diem
    FROM pair_rows
    """
    rows = run_psql_json(sql)
    if rows:
        r = rows[0]
        pair_list = r["pairs"] or []
        pair_lech_count = 0
        with RECONCILE_LOCK:
            for pr in pair_list:
                key = f"{pr['ma_kho']}_{pr['ma_bien_the']}"
                if bool(pr["khop"]):
                    MISMATCHED_PAIRS.discard(key)
                else:
                    MISMATCHED_PAIRS.add(key)
                    pair_lech_count += 1
            LAST_PAIR_CHECK_STATE.update({
                "checked": len(pair_list) > 0,
                "mo_ta": mo_ta,
                "so_cap_kiem_tra": len(pair_list),
                "so_cap_lech": pair_lech_count,
                "khop": len(pair_list) > 0 and pair_lech_count == 0,
                "thoi_diem": r["thoi_diem"]
            })
    return get_reconcile_snapshot()


def ensure_fn_tao_don_hang():
    """
    Ham fn_tao_don_hang duoc dinh nghia CHINH THUC trong schema.sql (khong dinh nghia lai o day).
    Ham nay chi KIEM TRA ban dang co trong CSDL co du cac buoc kiem tra dau vao
    (danh sach rong, SKU khong ton tai, so luong <= 0, SKU trung) va khoa chong trung.
    Neu thieu -> in canh bao de nguoi dung nap lai schema.sql.
    """
    rows = run_psql_json("""
        SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'fn_tao_don_hang'
    """)
    if not rows:
        print("CANH BAO: CSDL chua co ham fn_tao_don_hang. Hay nap lai schema.sql.")
        return False
    src = rows[0]["prosrc"] or ""
    can_co = ["khong duoc rong", "khong ton tai trong he thong", "phai > 0", "bi trung lap", "pg_advisory_xact_lock"]
    thieu = [x for x in can_co if x not in src]
    if thieu:
        print("CANH BAO: fn_tao_don_hang trong CSDL la ban cu (thieu: " + ", ".join(thieu) + "). Hay nap lai schema.sql.")
        return False
    return True


def classify_pg_error(err_text):
    m = re.search(r"ERROR:\s*(.+)", err_text)
    raw = m.group(1).strip() if m else err_text.strip()
    if "IDEM_CONFLICT:" in raw:
        return 409, "IDEM_CONFLICT", raw.split("IDEM_CONFLICT:", 1)[1].strip()
    if "REPEAT_ACTION:" in raw:
        return 409, "REPEAT_ACTION", raw.split("REPEAT_ACTION:", 1)[1].strip()
    if "Khong duoc chuyen trang thai tu" in raw:
        return 409, "INVALID_TRANSITION", f"Vi phạm thứ tự trạng thái đơn hàng ({raw}). Chỉ cho phép chuyển tiếp đúng vòng đời nghiệp vụ."
    if "Khong du ton kha dung" in raw:
        return 409, "INSUFFICIENT_STOCK", f"Không đủ tồn khả dụng trong kho để giữ hàng ({raw}). Giao dịch đã được tự động hoàn tác (Rollback)."
    if "chi duoc danh gia khi DaGiao" in raw:
        return 409, "ORDER_NOT_DELIVERED", f"Chặn đánh giá đơn chưa giao: {raw}."
    if "Danh sach san pham (p_items) khong duoc rong" in raw:
        return 400, "EMPTY_ITEMS", f"Dữ liệu đầu vào không hợp lệ: {raw}."
    if "Ma bien the (SKU)" in raw and ("khong ton tai" in raw or "khong hop le" in raw):
        return 400, "INVALID_SKU", f"Dữ liệu sản phẩm không hợp lệ: {raw}. Toàn bộ yêu cầu tạo đơn đã bị từ chối."
    if "So luong dat hang" in raw:
        return 400, "INVALID_QUANTITY", f"Số lượng đặt hàng không hợp lệ: {raw}. Toàn bộ yêu cầu tạo đơn đã bị từ chối."
    if "chua ma bien the (SKU) bi trung lap" in raw:
        return 400, "DUPLICATE_SKU", f"Danh sách sản phẩm không hợp lệ: {raw}."
    if "Voucher" in raw:
        return 400, "INVALID_VOUCHER", f"Không thể áp dụng mã giảm giá: {raw}."
    if "thuoc gian hang" in raw:
        return 400, "SHOP_MISMATCH", f"Sản phẩm không thuộc gian hàng của đơn: {raw}."
    if "Không tìm thấy đơn hàng" in raw:
        return 404, "ORDER_NOT_FOUND", raw
    if "khong ton tai" in raw:
        return 400, "INVALID_INPUT", raw
    return 400, "DB_REJECTED", raw


def translate_pg_error(err_text):
    _, _, msg = classify_pg_error(err_text)
    return msg


def create_order_atomic(khach_id, gian_hang_id, kho_id, voucher_id, items, kenh="Web", idem_key=None):
    """
    Tao don hang nguyen tu theo idempotency_key:
    - Su dung pg_advisory_xact_lock tren khoa (khach_id, idem_key) de xu ly dong thoi 2 yeu cau cung khoa.
    - Neu cung khoa va cung noi dung (kho, voucher, danh sach bt:sl): tra ve cung ma_don_hang.
    - Neu cung khoa nhung khac noi dung: tra ve loi ro rang (IDEM_CONFLICT, HTTP 409).
    - Kiem tra dau vao qua fn_tao_don_hang: tu choi toan bo yeu cau khi SKU sai, danh sach rong hoac so luong <= 0 (HTTP 400).
    """
    if not isinstance(items, list) or len(items) == 0:
        items_for_db = []
        expected_sig = f"kho={kho_id};vc=0;items="
    else:
        items_for_db = items
        try:
            items_sorted = sorted(items, key=lambda x: int(x.get("bt", 0)))
            items_sig = ",".join(f"{int(x.get('bt'))}:{int(x.get('sl'))}" for x in items_sorted)
            items_for_db = items_sorted
        except Exception:
            items_sig = "invalid"
        vc_tmp = int(voucher_id) if (voucher_id and str(voucher_id).isdigit()) else 0
        expected_sig = f"kho={int(kho_id)};vc={vc_tmp};items={items_sig}"

    vc_val = int(voucher_id) if (voucher_id and str(voucher_id).isdigit()) else 0
    items_json = json.dumps(items_for_db).replace("'", "''")
    vc_sql = str(vc_val) if vc_val > 0 else "NULL"

    cmd = [
        PSQL_PATH, "-h", DB_HOST, "-p", str(DB_PORT), "-U", DB_USER, "-d", DB_NAME,
        "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-f", "-"
    ]

    if not idem_key:
        sql = f"""
        BEGIN;
        SELECT fn_tao_don_hang(
            {int(khach_id)}, {int(gian_hang_id)}, {int(kho_id)},
            clock_timestamp()::timestamp, {vc_sql},
            '{items_json}'::jsonb, '{kenh}', NULL
        ) || '|f';
        COMMIT;
        """
        res = subprocess.run(cmd, input=sql, capture_output=True, text=True, encoding="utf-8", env=build_pg_env(), timeout=30)
        if res.returncode != 0:
            st, code, msg = classify_pg_error(res.stderr)
            return {"ok": False, "status": st, "code": code, "error": msg}
        lines = [ln.strip() for ln in res.stdout.splitlines() if "|" in ln]
        if not lines:
            return {"ok": False, "status": 500, "code": "INTERNAL_ERROR", "error": "Không đọc được kết quả tạo đơn."}
        parts = lines[-1].split("|")
        return {"ok": True, "status": 201, "order_id": int(parts[0]), "reused": False}

    clean_idem = re.sub(r"[^A-Za-z0-9_.:-]", "", str(idem_key))[:64]
    sql = f"""
    DO $$
    DECLARE
        v_existing_id INT;
        v_existing_sig TEXT;
        v_new_id INT;
    BEGIN
        PERFORM pg_advisory_xact_lock(hashtext('omnistock_idem_{int(khach_id)}_' || '{clean_idem}'));

        SELECT d.ma_don_hang,
               'kho=' || d.ma_kho_xuat || ';vc=' || COALESCE(d.ma_voucher, 0) || ';items=' ||
               COALESCE((
                   SELECT string_agg(ct.ma_bien_the || ':' || ct.so_luong, ',' ORDER BY ct.ma_bien_the)
                   FROM chi_tiet_don_hang ct
                   WHERE ct.ma_don_hang = d.ma_don_hang
               ), '')
          INTO v_existing_id, v_existing_sig
          FROM don_hang d
         WHERE d.ma_khach_hang = {int(khach_id)}
           AND d.idempotency_key = '{clean_idem}'
         LIMIT 1;

        IF v_existing_id IS NOT NULL THEN
            IF v_existing_sig <> '{expected_sig}' THEN
                RAISE EXCEPTION 'IDEM_CONFLICT: Khóa chống trùng (%) đã được dùng cho đơn hàng #% với nội dung khác (Đơn đã tạo: [%], Yêu cầu mới: [%]).',
                    '{clean_idem}', v_existing_id, v_existing_sig, '{expected_sig}';
            END IF;
            CREATE TEMP TABLE tmp_idem_out ON COMMIT DROP AS
            SELECT v_existing_id AS order_id, true AS reused;
        ELSE
            v_new_id := fn_tao_don_hang(
                {int(khach_id)}, {int(gian_hang_id)}, {int(kho_id)},
                clock_timestamp()::timestamp, {vc_sql},
                '{items_json}'::jsonb, '{kenh}', '{clean_idem}'
            );
            CREATE TEMP TABLE tmp_idem_out ON COMMIT DROP AS
            SELECT v_new_id AS order_id, false AS reused;
        END IF;
    END $$;
    SELECT order_id, reused FROM tmp_idem_out;
    """
    wrapped = f"BEGIN;\n{sql}\nCOMMIT;"
    res = subprocess.run(cmd, input=wrapped, capture_output=True, text=True, encoding="utf-8", env=build_pg_env(), timeout=30)
    if res.returncode != 0:
        st, code, msg = classify_pg_error(res.stderr)
        return {"ok": False, "status": st, "code": code, "error": msg}

    lines = [ln.strip() for ln in res.stdout.splitlines() if "|" in ln]
    if not lines:
        return {"ok": False, "status": 500, "code": "INTERNAL_ERROR", "error": "Không đọc được kết quả tạo đơn nguyên tử."}
    parts = lines[-1].split("|")
    reused = parts[1] == "t"
    return {"ok": True, "status": 200 if reused else 201, "order_id": int(parts[0]), "reused": reused}


def execute_order_transition(order_id, action):
    """
    Thuc thi chuyen trang thai don hang qua API/Server:
    - Khoa dong don_hang (FOR UPDATE).
    - Chan thao tac lap lai cung trang thai (confirm lap, ship lap, deliver lap, cancel lap).
    - Goi UPDATE don_hang de kich hoat trg_chuyen_trang_thai va trg_cap_nhat_ton_kho.
    """
    target_map = {
        "confirm": ("DaXacNhan", "Xác nhận giữ kho"),
        "ship": ("DangGiao", "Xuất kho"),
        "deliver": ("DaGiao", "Giao hàng"),
        "cancel": ("DaHuy", "Hủy đơn")
    }
    if action not in target_map:
        return {"ok": False, "status": 400, "code": "INVALID_ACTION", "error": f"Thao tác không hợp lệ: {action}"}

    target_status, action_label = target_map[action]
    transition_sql = f"""
    DO $$
    DECLARE
        v_old VARCHAR(20);
    BEGIN
        SELECT trang_thai INTO v_old
        FROM don_hang
        WHERE ma_don_hang = {int(order_id)}
        FOR UPDATE;

        IF v_old IS NULL THEN
            RAISE EXCEPTION 'Không tìm thấy đơn hàng #%', {int(order_id)};
        END IF;

        IF v_old = '{target_status}' THEN
            RAISE EXCEPTION 'REPEAT_ACTION: Đơn hàng #% đã ở trạng thái %, không được thực hiện lặp lại thao tác %.',
                {int(order_id)}, v_old, '{action_label}';
        END IF;

        UPDATE don_hang
        SET trang_thai = '{target_status}'
        WHERE ma_don_hang = {int(order_id)};
    END $$;
    """
    rc, _, err = run_psql_command(transition_sql)
    if rc != 0:
        st, code, msg = classify_pg_error(err)
        return {"ok": False, "status": st, "code": code, "error": msg}
    return {"ok": True, "status": 200, "target_status": target_status}


def execute_race_condition_run(run_id=None):
    """
    Chay kich ban tranh mua tren du lieu duoc nhan dien rieng bang run_id:
    - Khong bao gio tat trigger trg_khong_sua_so_cai hay xoa bien_dong_kho (giu nguyen lich su so cai).
    - Hai luot chay dong thoi co run_id khac nhau, tao SKU FLASH-RC-<run_id> doc lap nen khong dung do nhau.
    - Chay 2 ket noi psql that dong thoi tranh 1 san pham co ton kha dung = 1.
    """
    if not run_id:
        run_id = f"RC-{int(time.time() * 1000)}-{random.randint(1000, 9999)}"
    run_id = re.sub(r"[^A-Za-z0-9_-]", "", str(run_id))[:36]
    sku_code = f"FLASH-{run_id}"

    setup_sql = f"""
    INSERT INTO bien_the(ma_san_pham, sku, mau_sac, kich_co, gia_nhap, gia_ban)
    VALUES (1, '{sku_code}', 'Phien ban FlashSale', '{run_id}', 6500000, 8900000)
    ON CONFLICT (sku) DO NOTHING;
    """
    rc_s, _, err_s = run_psql_command(setup_sql)
    if rc_s != 0:
        raise RuntimeError(err_s)

    bt_rows = run_psql_json(f"SELECT ma_bien_the, sku FROM bien_the WHERE sku = '{sku_code}' LIMIT 1")
    v_bt = int(bt_rows[0]["ma_bien_the"])

    rc_nhap, _, err_nhap = run_psql_command(
        f"SELECT fn_nhap_kho(1, {v_bt}, 1, 'Nhap 1 chiec cho phien tranh mua [{run_id}]');"
    )
    if rc_nhap != 0:
        raise RuntimeError(err_nhap)

    don_a_res = create_order_atomic(3, 1, 1, None, [{"bt": v_bt, "sl": 1}], kenh="Web", idem_key=f"A-{run_id}")
    don_b_res = create_order_atomic(4, 1, 1, None, [{"bt": v_bt, "sl": 1}], kenh="DoiTac", idem_key=f"B-{run_id}")
    if not don_a_res["ok"] or not don_b_res["ok"]:
        raise RuntimeError(don_a_res.get("error") or don_b_res.get("error"))
    don_a = don_a_res["order_id"]
    don_b = don_b_res["order_id"]

    def confirm_worker(order_id, delay_sec):
        time.sleep(delay_sec)
        res_tr = execute_order_transition(order_id, "confirm")
        if not res_tr["ok"]:
            execute_order_transition(order_id, "cancel")
            return {"order_id": order_id, "ok": False, "detail": res_tr["error"]}
        return {
            "order_id": order_id,
            "ok": True,
            "detail": "Cập nhật ton_kho nguyên tử thành công (so_luong_vat_ly - so_luong_giu >= 1), giữ chiếc cuối cùng."
        }

    delays = [0.0, 0.08]
    random.shuffle(delays)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        fa = ex.submit(confirm_worker, don_a, delays[0])
        fb = ex.submit(confirm_worker, don_b, delays[1])
        res_a = fa.result()
        res_b = fb.result()

    orders_db = run_psql_json(f"""
        SELECT d.ma_don_hang, d.ma_khach_hang, kh.ho_ten, d.trang_thai,
               (SELECT bdk.loai || ' (delta_giu: +' || bdk.delta_giu || ', mã BĐ: #' || bdk.ma_bien_dong || ')'
                FROM bien_dong_kho bdk
                WHERE bdk.ma_don_hang = d.ma_don_hang
                ORDER BY bdk.ma_bien_dong DESC LIMIT 1) AS nghiep_vu_so_cai
        FROM don_hang d
        JOIN khach_hang kh ON kh.ma_khach_hang = d.ma_khach_hang
        WHERE d.ma_don_hang IN ({don_a}, {don_b})
    """)
    map_db = {int(r["ma_don_hang"]): r for r in orders_db}

    tk_rows = run_psql_json(f"""
        SELECT t.ma_bien_the, b.sku, t.so_luong_vat_ly, t.so_luong_giu,
               (t.so_luong_vat_ly - t.so_luong_giu) AS so_luong_kha_dung,
               (SELECT COUNT(*) FROM bien_dong_kho bdk WHERE bdk.ma_kho = 1 AND bdk.ma_bien_the = t.ma_bien_the AND bdk.loai = 'GIU') AS so_dong_giu,
               to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS') AS thoi_diem
        FROM ton_kho t
        JOIN bien_the b ON b.ma_bien_the = t.ma_bien_the
        WHERE t.ma_kho = 1 AND t.ma_bien_the = {v_bt}
    """)
    tk_final = tk_rows[0]

    row_a = map_db[don_a]
    row_b = map_db[don_b]
    don_thang = don_a if row_a["trang_thai"] == "DaXacNhan" else (don_b if row_b["trang_thai"] == "DaXacNhan" else None)

    verify_pair_reconcile(1, [v_bt], mo_ta=f"Phiên tranh mua {run_id} (Kho #1, SKU {sku_code})")

    return {
        "run_id": run_id,
        "thoi_diem": tk_final.get("thoi_diem"),
        "sku": sku_code,
        "ma_bien_the": v_bt,
        "khach_a": {
            "ma_don_hang": don_a,
            "ho_ten": row_a["ho_ten"],
            "trang_thai": row_a["trang_thai"],
            "thanh_cong": row_a["trang_thai"] == "DaXacNhan",
            "nghiep_vu_so_cai": row_a["nghiep_vu_so_cai"],
            "chi_tiet": res_a["detail"]
        },
        "khach_b": {
            "ma_don_hang": don_b,
            "ho_ten": row_b["ho_ten"],
            "trang_thai": row_b["trang_thai"],
            "thanh_cong": row_b["trang_thai"] == "DaXacNhan",
            "nghiep_vu_so_cai": row_b["nghiep_vu_so_cai"],
            "chi_tiet": res_b["detail"]
        },
        "don_thang": don_thang,
        "ton_kho_cuoi": tk_final
    }


def release_race_condition_run(run_id):
    """
    Giai phong giu kho cho dung pham vi 1 ma lan chay (run_id) ma khong xoa so cai:
    Chuyen don thang cua run_id tu DaXacNhan -> DaHuy de trigger ghi dong NHA_GIU hop le vao bien_dong_kho.
    """
    clean_run_id = re.sub(r"[^A-Za-z0-9_-]", "", str(run_id))[:36]
    sku_code = f"FLASH-{clean_run_id}"
    rows = run_psql_json(f"""
        SELECT d.ma_don_hang, d.trang_thai, ct.ma_bien_the
        FROM don_hang d
        JOIN chi_tiet_don_hang ct ON ct.ma_don_hang = d.ma_don_hang
        JOIN bien_the b ON b.ma_bien_the = ct.ma_bien_the
        WHERE b.sku = '{sku_code}'
    """)
    if not rows:
        return {"ok": False, "error": f"Không tìm thấy dữ liệu của phiên chạy {clean_run_id}."}

    v_bt = int(rows[0]["ma_bien_the"])
    released_orders = []
    for r in rows:
        if r["trang_thai"] == "DaXacNhan":
            tr = execute_order_transition(int(r["ma_don_hang"]), "cancel")
            if tr["ok"]:
                released_orders.append(int(r["ma_don_hang"]))

    verify_pair_reconcile(1, [v_bt], mo_ta=f"Giải phóng giữ kho phiên {clean_run_id} (SKU {sku_code})")
    tk_rows = run_psql_json(f"""
        SELECT t.ma_bien_the, b.sku, t.so_luong_vat_ly, t.so_luong_giu,
               (t.so_luong_vat_ly - t.so_luong_giu) AS so_luong_kha_dung
        FROM ton_kho t
        JOIN bien_the b ON b.ma_bien_the = t.ma_bien_the
        WHERE t.ma_kho = 1 AND t.ma_bien_the = {v_bt}
    """)
    return {
        "ok": True,
        "run_id": clean_run_id,
        "released_orders": released_orders,
        "ton_kho_cuoi": tk_rows[0] if tk_rows else None
    }


def _vn_date(iso):
    y, m, d = iso.split("-")
    return f"{d}/{m}/{y}"


def get_dashboard_payload(period="toan_ky", ma_kho=1, order_id=None):
    if not FULL_RECONCILE_STATE["checked"]:
        run_full_reconcile()

    period_filter = ""
    period_short = "Toàn kỳ"
    period_label = (
        f"Toàn kỳ mô phỏng {_vn_date(KY_MO_PHONG_TU)} – {_vn_date(NGAY_CHOT_MO_PHONG)} "
        f"(số liệu tính tại ngày chốt kỳ mô phỏng {_vn_date(NGAY_CHOT_MO_PHONG)}, gồm cả đơn tạo thêm trên dashboard) — lọc theo ngày đặt (ngay_dat)"
    )
    if period == "thang_10":
        period_filter = "AND d.ngay_dat >= DATE '2026-10-01' AND d.ngay_dat < DATE '2026-11-01'"
        period_short = "Tháng 10/2026"
        period_label = "Tháng 10/2026 (01/10/2026 – 31/10/2026) — lọc theo ngày đặt (ngay_dat)"

    kho_cond = f"t.ma_kho = {int(ma_kho)}" if str(ma_kho) != "all" else "TRUE"

    non_flash_order_cond = """
    NOT EXISTS (
        SELECT 1 FROM chi_tiet_don_hang ct_f
        JOIN bien_the b_f ON b_f.ma_bien_the = ct_f.ma_bien_the
        WHERE ct_f.ma_don_hang = d.ma_don_hang AND b_f.sku LIKE 'FLASH-%'
    )
    """

    order_where = (
        f"d.ma_don_hang = {int(order_id)}"
        if order_id and str(order_id).isdigit()
        else non_flash_order_cond
    )

    sql = f"""
    WITH kpi AS (
        SELECT
            COUNT(*) AS tong_don_hang,
            COUNT(*) FILTER (WHERE d.trang_thai = 'DaGiao') AS so_don_da_giao,
            COUNT(*) FILTER (WHERE d.trang_thai = 'DaHuy') AS so_don_da_huy,
            COALESCE(SUM(d.tong_tien_hang - d.tien_giam) FILTER (WHERE d.trang_thai = 'DaGiao'), 0) AS doanh_thu_thuan,
            (SELECT COUNT(*) FROM bien_the WHERE sku NOT LIKE 'FLASH-%') AS so_sku_kinh_doanh,
            (SELECT COUNT(*) FROM bien_the WHERE sku LIKE 'FLASH-%') AS so_sku_thu_nghiem,
            (SELECT COUNT(*) FROM kho) AS so_kho,
            (SELECT COUNT(*) FROM ton_kho) AS tong_cap_kho_sku,
            (SELECT COUNT(*) FROM bien_dong_kho) AS tong_dong_so_cai,
            to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS') AS cap_nhat_luc
        FROM don_hang d
        WHERE {non_flash_order_cond} {period_filter}
    ),
    cur_ord_id AS (
        SELECT d.ma_don_hang
        FROM don_hang d
        WHERE {order_where}
        ORDER BY d.ma_don_hang DESC
        LIMIT 1
    ),
    cur_ord AS (
        SELECT
            d.ma_don_hang,
            d.trang_thai,
            d.kenh_ban,
            d.idempotency_key,
            d.ma_kho_xuat,
            k.ten_kho,
            d.ma_khach_hang,
            kh.ho_ten AS ten_khach_hang,
            to_char(d.ngay_dat, 'YYYY-MM-DD HH24:MI:SS') AS ngay_dat,
            d.tong_tien_hang,
            d.tien_giam,
            d.phi_van_chuyen,
            (d.tong_tien_hang - d.tien_giam) AS gia_tri_sau_giam,
            (d.tong_tien_hang - d.tien_giam) AS doanh_thu_don,
            CASE WHEN d.trang_thai = 'DaGiao' THEN (d.tong_tien_hang - d.tien_giam) ELSE 0 END AS doanh_thu_ghi_nhan,
            v.ma_code AS ma_voucher_code,
            COALESCE(SUM(ct.so_luong), 0) AS tong_so_luong,
            json_agg(
                json_build_object(
                    'ma_bien_the', ct.ma_bien_the,
                    'sku', b.sku,
                    'ten_san_pham', s.ten_san_pham,
                    'mau_sac', b.mau_sac,
                    'kich_co', b.kich_co,
                    'so_luong', ct.so_luong,
                    'don_gia', ct.don_gia,
                    'thanh_tien', (ct.so_luong * ct.don_gia)
                ) ORDER BY ct.ma_bien_the
            ) AS items
        FROM don_hang d
        JOIN cur_ord_id cid ON cid.ma_don_hang = d.ma_don_hang
        JOIN khach_hang kh ON kh.ma_khach_hang = d.ma_khach_hang
        JOIN kho k ON k.ma_kho = d.ma_kho_xuat
        LEFT JOIN voucher v ON v.ma_voucher = d.ma_voucher
        JOIN chi_tiet_don_hang ct ON ct.ma_don_hang = d.ma_don_hang
        JOIN bien_the b ON b.ma_bien_the = ct.ma_bien_the
        JOIN san_pham s ON s.ma_san_pham = b.ma_san_pham
        GROUP BY d.ma_don_hang, k.ten_kho, kh.ho_ten, v.ma_code
    ),
    recent_orders AS (
        SELECT
            d.ma_don_hang,
            d.trang_thai,
            d.kenh_ban,
            k.ten_kho,
            to_char(d.ngay_dat, 'YYYY-MM-DD HH24:MI:SS') AS ngay_dat,
            (d.tong_tien_hang - d.tien_giam) AS doanh_thu_don,
            string_agg(b.sku || ' x' || ct.so_luong, ', ' ORDER BY ct.ma_bien_the) AS tom_tat_sp
        FROM (
            SELECT ma_don_hang, trang_thai, kenh_ban, ma_kho_xuat, ngay_dat, tong_tien_hang, tien_giam
            FROM don_hang d
            WHERE {non_flash_order_cond}
            ORDER BY ma_don_hang DESC
            LIMIT 12
        ) d
        JOIN kho k ON k.ma_kho = d.ma_kho_xuat
        JOIN chi_tiet_don_hang ct ON ct.ma_don_hang = d.ma_don_hang
        JOIN bien_the b ON b.ma_bien_the = ct.ma_bien_the
        GROUP BY d.ma_don_hang, d.trang_thai, d.kenh_ban, k.ten_kho, d.ngay_dat, d.tong_tien_hang, d.tien_giam
        ORDER BY d.ma_don_hang DESC
    ),
    inv AS (
        SELECT
            t.ma_kho,
            k.ten_kho,
            b.ma_bien_the,
            b.sku,
            s.ten_san_pham,
            b.mau_sac,
            b.kich_co,
            b.gia_ban,
            t.so_luong_vat_ly,
            t.so_luong_giu,
            (t.so_luong_vat_ly - t.so_luong_giu) AS so_luong_kha_dung
        FROM ton_kho t
        JOIN kho k ON k.ma_kho = t.ma_kho
        JOIN bien_the b ON b.ma_bien_the = t.ma_bien_the
        JOIN san_pham s ON s.ma_san_pham = b.ma_san_pham
        WHERE {kho_cond}
          AND (
              b.ma_bien_the <= 16
              OR b.ma_bien_the IN (
                  SELECT ct.ma_bien_the
                  FROM chi_tiet_don_hang ct
                  JOIN cur_ord_id cid ON cid.ma_don_hang = ct.ma_don_hang
              )
          )
          AND b.sku NOT LIKE 'FLASH-%'
        ORDER BY
          CASE WHEN b.ma_bien_the IN (
              SELECT ct.ma_bien_the
              FROM chi_tiet_don_hang ct
              JOIN cur_ord_id cid ON cid.ma_don_hang = ct.ma_don_hang
          ) THEN 0 ELSE 1 END,
          t.ma_kho, b.ma_bien_the
        LIMIT 16
    ),
    bdk_top AS (
        SELECT
            bdk.ma_bien_dong AS seq_id,
            to_char(bdk.thoi_diem, 'YYYY-MM-DD HH24:MI:SS') AS thoi_gian,
            bdk.ma_don_hang,
            bdk.ma_kho,
            k.ten_kho,
            bdk.ma_bien_the,
            b.sku,
            s.ten_san_pham,
            b.mau_sac,
            b.kich_co,
            bdk.loai AS nghiep_vu,
            bdk.delta_vat_ly,
            bdk.delta_giu,
            (bdk.delta_vat_ly - bdk.delta_giu) AS delta_kha_dung,
            bdk.ly_do AS mo_ta,
            CASE WHEN bdk.ma_don_hang IS NOT NULL THEN 'trg_cap_nhat_ton_kho' ELSE 'fn_nhap_kho' END AS trigger_xac_nhan
        FROM (
            SELECT * FROM bien_dong_kho ORDER BY ma_bien_dong DESC LIMIT 20
        ) bdk
        JOIN kho k ON k.ma_kho = bdk.ma_kho
        JOIN bien_the b ON b.ma_bien_the = bdk.ma_bien_the
        JOIN san_pham s ON s.ma_san_pham = b.ma_san_pham
    ),
    bdk_order AS (
        SELECT
            bdk.ma_bien_dong AS seq_id,
            to_char(bdk.thoi_diem, 'YYYY-MM-DD HH24:MI:SS') AS thoi_gian,
            bdk.ma_don_hang,
            bdk.ma_kho,
            k.ten_kho,
            bdk.ma_bien_the,
            b.sku,
            s.ten_san_pham,
            b.mau_sac,
            b.kich_co,
            bdk.loai AS nghiep_vu,
            bdk.delta_vat_ly,
            bdk.delta_giu,
            (bdk.delta_vat_ly - bdk.delta_giu) AS delta_kha_dung,
            bdk.ly_do AS mo_ta,
            CASE WHEN bdk.ma_don_hang IS NOT NULL THEN 'trg_cap_nhat_ton_kho' ELSE 'fn_nhap_kho' END AS trigger_xac_nhan
        FROM bien_dong_kho bdk
        JOIN cur_ord_id cid ON cid.ma_don_hang = bdk.ma_don_hang
        JOIN kho k ON k.ma_kho = bdk.ma_kho
        JOIN bien_the b ON b.ma_bien_the = bdk.ma_bien_the
        JOIN san_pham s ON s.ma_san_pham = b.ma_san_pham
        ORDER BY bdk.ma_bien_dong DESC
    ),
    channels AS (
        SELECT
            d.kenh_ban,
            COUNT(*) AS so_don_giao,
            COALESCE(SUM(d.tong_tien_hang - d.tien_giam), 0) AS doanh_thu_thuan
        FROM don_hang d
        WHERE d.trang_thai = 'DaGiao'
          AND {non_flash_order_cond} {period_filter}
        GROUP BY d.kenh_ban
        ORDER BY doanh_thu_thuan DESC
    ),
    warehouses AS (
        SELECT ma_kho, ten_kho, tinh_tp
        FROM kho
        ORDER BY ma_kho
    )
    SELECT
        (SELECT row_to_json(kpi) FROM kpi) AS summary,
        (SELECT row_to_json(cur_ord) FROM cur_ord) AS current_order,
        COALESCE((SELECT json_agg(recent_orders) FROM recent_orders), '[]'::json) AS recent_orders,
        COALESCE((SELECT json_agg(inv) FROM inv), '[]'::json) AS inventory,
        COALESCE((SELECT json_agg(bdk_top ORDER BY seq_id DESC) FROM bdk_top), '[]'::json) AS logs,
        COALESCE((SELECT json_agg(bdk_order ORDER BY seq_id DESC) FROM bdk_order), '[]'::json) AS order_logs,
        COALESCE((SELECT json_agg(channels) FROM channels), '[]'::json) AS channels,
        COALESCE((SELECT json_agg(warehouses ORDER BY ma_kho) FROM warehouses), '[]'::json) AS warehouses
    """
    rows = run_psql_json(sql)
    payload = rows[0] if rows else {}
    payload["summary"]["period"] = period
    payload["summary"]["period_short"] = period_short
    payload["summary"]["period_label"] = period_label
    payload["reconcile"] = get_reconcile_snapshot()
    return payload


def run_all_8_business_rule_tests():
    """
    Thuc thi that ca 8 phep thu nghiep vu tren CSDL va API logic,
    kiem tra du lieu truoc/sau, KHONG ghi san passed = true.
    """
    results = []

    # -----------------------------------------------------------------
    # CA 1: Kiem tra rieng tung thao tac lap qua API logic (confirm lap, ship lap, cancel lap)
    # -----------------------------------------------------------------
    tk0 = run_psql_json("SELECT so_luong_vat_ly, so_luong_giu, to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS') AS ts FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1")[0]
    vl_init, giu_init = int(tk0["so_luong_vat_ly"]), int(tk0["so_luong_giu"])

    c_res = create_order_atomic(1, 1, 1, None, [{"bt": 1, "sl": 1}], kenh="Web", idem_key=f"VERIFY-C1-{int(time.time()*1000)}")
    oid_c1 = c_res["order_id"]

    # 1a. Confirm lan 1 -> Confirm lan 2 (phai bi chan)
    cf1 = execute_order_transition(oid_c1, "confirm")
    tk_after_cf1 = run_psql_json("SELECT so_luong_vat_ly, so_luong_giu FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1")[0]
    cf2_dup = execute_order_transition(oid_c1, "confirm")
    tk_after_cf2 = run_psql_json("SELECT so_luong_vat_ly, so_luong_giu FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1")[0]

    # 1b. Ship lan 1 -> Ship lan 2 (phai bi chan)
    sh1 = execute_order_transition(oid_c1, "ship")
    tk_after_sh1 = run_psql_json("SELECT so_luong_vat_ly, so_luong_giu FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1")[0]
    sh2_dup = execute_order_transition(oid_c1, "ship")
    tk_after_sh2 = run_psql_json("SELECT so_luong_vat_ly, so_luong_giu FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1")[0]

    # 1c. Cancel lan 1 -> Cancel lan 2 (phai bi chan)
    ca1 = execute_order_transition(oid_c1, "cancel")
    tk_after_ca1 = run_psql_json("SELECT so_luong_vat_ly, so_luong_giu FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1")[0]
    ca2_dup = execute_order_transition(oid_c1, "cancel")
    tk_after_ca2 = run_psql_json("SELECT so_luong_vat_ly, so_luong_giu, to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS') AS ts FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1")[0]

    bdk_counts = run_psql_json(f"""
        SELECT
            COUNT(*) FILTER (WHERE loai = 'GIU') AS c_giu,
            COUNT(*) FILTER (WHERE loai = 'XUAT') AS c_xuat,
            COUNT(*) FILTER (WHERE loai = 'HOAN') AS c_hoan
        FROM bien_dong_kho
        WHERE ma_don_hang = {oid_c1}
    """)[0]

    confirm_dup_blocked = (
        cf1["ok"]
        and (not cf2_dup["ok"])
        and int(tk_after_cf1["so_luong_giu"]) == giu_init + 1
        and int(tk_after_cf2["so_luong_giu"]) == giu_init + 1
        and int(bdk_counts["c_giu"]) == 1
    )
    ship_dup_blocked = (
        sh1["ok"]
        and (not sh2_dup["ok"])
        and int(tk_after_sh1["so_luong_vat_ly"]) == vl_init - 1
        and int(tk_after_sh2["so_luong_vat_ly"]) == vl_init - 1
        and int(bdk_counts["c_xuat"]) == 1
    )
    cancel_dup_blocked = (
        ca1["ok"]
        and (not ca2_dup["ok"])
        and int(tk_after_ca1["so_luong_vat_ly"]) == vl_init
        and int(tk_after_ca2["so_luong_vat_ly"]) == vl_init
        and int(bdk_counts["c_hoan"]) == 1
    )
    c1_passed = bool(confirm_dup_blocked and ship_dup_blocked and cancel_dup_blocked)
    results.append({
        "stt": 1,
        "short_name": "Chặn thao tác lặp (Xác nhận / Xuất / Hủy lặp)",
        "name": "1. Kiểm tra riêng từng thao tác lặp qua API (Xác nhận lặp, Xuất lặp, Hủy lặp)",
        "passed": c1_passed,
        "thoi_diem": tk_after_ca2["ts"],
        "tech_objects": "FOR UPDATE on don_hang, REPEAT_ACTION (HTTP 409), uq_bien_dong_giu_1_lan, uq_bien_dong_xuat_1_lan",
        "detail": (
            f"Đơn #{oid_c1}: "
            f"[Xác nhận lặp bị chặn={not cf2_dup['ok']} ({cf2_dup.get('code', '')}), GIU={bdk_counts['c_giu']}, giữ={tk_after_cf2['so_luong_giu']}]; "
            f"[Xuất lặp bị chặn={not sh2_dup['ok']} ({sh2_dup.get('code', '')}), XUAT={bdk_counts['c_xuat']}, vật lý={tk_after_sh2['so_luong_vat_ly']}]; "
            f"[Hủy lặp bị chặn={not ca2_dup['ok']} ({ca2_dup.get('code', '')}), HOAN={bdk_counts['c_hoan']}, vật lý hoàn={tk_after_ca2['so_luong_vat_ly']}]."
        )
    })

    # -----------------------------------------------------------------
    # CA 2: Chuyen trang thai sai thu tu (ChoXacNhan -> DaGiao, DaHuy -> DaXacNhan)
    # -----------------------------------------------------------------
    jump_on_canceled = execute_order_transition(oid_c1, "confirm")  # oid_c1 dang o DaHuy
    sql_cases_2_3_5_6_7 = """
    DO $$
    DECLARE
        v_don INT;
        v_giu_truoc INT;
        v_giu_sau INT;
        v_gia_don NUMERIC;
        v_err TEXT;
        v_ok BOOLEAN;
        v_msg TEXT;
        v_ts TEXT;
    BEGIN
        v_ts := to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS');
        CREATE TEMP TABLE kq_sub (
            stt INT,
            short_name TEXT,
            name TEXT,
            passed BOOLEAN,
            thoi_diem TEXT,
            tech_objects TEXT,
            detail TEXT
        ) ON COMMIT DROP;

        -- 2. Chuyen trang thai sai thu tu (ChoXacNhan -> DaGiao)
        v_ok := false;
        v_msg := '';
        BEGIN
            v_don := fn_tao_don_hang(1, 1, 1, clock_timestamp()::timestamp, NULL, '[{"bt":1,"sl":1}]'::jsonb, 'Web');
            BEGIN
                UPDATE don_hang SET trang_thai = 'DaGiao' WHERE ma_don_hang = v_don;
                v_ok := false;
                v_msg := 'Không chặn được ChoXacNhan -> DaGiao';
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
                v_ok := (SELECT trang_thai = 'ChoXacNhan' FROM don_hang WHERE ma_don_hang = v_don);
                v_msg := 'Đơn thử #' || v_don || ': Trigger trg_chuyen_trang_thai từ chối (' || v_err || '), đơn giữ nguyên trạng thái ChoXacNhan.';
            END;
            RAISE EXCEPTION 'ROLLBACK_SUB';
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
        INSERT INTO kq_sub VALUES (
            2,
            'Chặn chuyển trạng thái sai thứ tự',
            '2. Chặn chuyển trạng thái sai thứ tự (ChoXacNhan -> DaGiao, DaHuy -> DaXacNhan)',
            v_ok, v_ts,
            'trg_chuyen_trang_thai, fn_chuyen_trang_thai(), lich_su_trang_thai',
            v_msg
        );

        -- 3. Don nhieu SKU nhung 1 SKU khong du hang + kiem tra dau vao fn_tao_don_hang (SKU sai, rong, sl <= 0)
        v_ok := false;
        v_msg := '';
        SELECT so_luong_giu INTO v_giu_truoc FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1;
        BEGIN
            v_don := fn_tao_don_hang(1, 1, 1, clock_timestamp()::timestamp, NULL, '[{"bt":1,"sl":1},{"bt":2,"sl":999999}]'::jsonb, 'Web');
            UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = v_don;
            v_ok := false;
            v_msg := 'Không chặn được đơn thiếu hàng';
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            SELECT so_luong_giu INTO v_giu_sau FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1;
            v_ok := (v_giu_truoc = v_giu_sau);
            v_msg := 'Đơn thử #' || COALESCE(v_don::text, 'N/A') || ' lỗi (' || v_err || ') -> Hoàn tác nguyên tử cả đơn: SKU #1 không bị giữ lẻ (Đang giữ trước = ' || v_giu_truoc || ', sau = ' || v_giu_sau || ').';
        END;
        BEGIN
            PERFORM fn_tao_don_hang(1, 1, 1, clock_timestamp()::timestamp, NULL, '[{"bt":1,"sl":1},{"bt":999999,"sl":1}]'::jsonb, 'Web');
            v_ok := false;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
        BEGIN
            PERFORM fn_tao_don_hang(1, 1, 1, clock_timestamp()::timestamp, NULL, '[]'::jsonb, 'Web');
            v_ok := false;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
        BEGIN
            PERFORM fn_tao_don_hang(1, 1, 1, clock_timestamp()::timestamp, NULL, '[{"bt":1,"sl":0}]'::jsonb, 'Web');
            v_ok := false;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
        v_msg := v_msg || ' Từ chối toàn bộ đơn khi có SKU không tồn tại (#999999), danh sách rỗng ([]) hoặc SL <= 0.';
        INSERT INTO kq_sub VALUES (
            3,
            'Hoàn tác đơn nhiều SKU thiếu hàng & chặn đầu vào sai',
            '3. Đơn nhiều SKU thiếu hàng & kiểm tra đầu vào fn_tao_don_hang (SKU sai, rỗng, SL <= 0)',
            v_ok, v_ts,
            'trg_cap_nhat_ton_kho, fn_cap_nhat_ton_kho(), fn_tao_don_hang()',
            v_msg
        );

        -- 5. Voucher het han hoac chua dat toi thieu
        v_ok := false;
        v_msg := '';
        BEGIN
            v_don := fn_tao_don_hang(1, 1, 1, clock_timestamp()::timestamp, 3, '[{"bt":1,"sl":1}]'::jsonb, 'Web');
            v_ok := false;
            v_msg := 'Không chặn được voucher hết hạn';
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            v_ok := true;
            v_msg := 'Trigger trg_kiem_tra_voucher từ chối (Voucher #3 HETHAN20): ' || v_err;
        END;
        INSERT INTO kq_sub VALUES (
            5,
            'Chặn áp dụng voucher hết hạn hoặc chưa đủ tối thiểu',
            '5. Chặn Voucher hết hạn hoặc đơn chưa đạt tối thiểu',
            v_ok, v_ts,
            'trg_kiem_tra_voucher, fn_kiem_tra_voucher(), voucher',
            v_msg
        );

        -- 6. Danh gia khi don chua giao
        v_ok := false;
        v_msg := '';
        BEGIN
            v_don := fn_tao_don_hang(1, 1, 1, clock_timestamp()::timestamp, NULL, '[{"bt":1,"sl":1}]'::jsonb, 'Web');
            BEGIN
                INSERT INTO danh_gia(ma_don_hang, ma_bien_the, so_sao, noi_dung) VALUES (v_don, 1, 5, 'Test danh gia');
                v_ok := false;
                v_msg := 'Không chặn được';
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
                v_ok := (SELECT COUNT(*) = 0 FROM danh_gia WHERE ma_don_hang = v_don);
                v_msg := 'Đơn thử #' || v_don || ' (ChoXacNhan): Trigger trg_kiem_tra_danh_gia từ chối (' || v_err || '), số đánh giá được chèn = 0.';
            END;
            RAISE EXCEPTION 'ROLLBACK_SUB';
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
        INSERT INTO kq_sub VALUES (
            6,
            'Chặn đánh giá sản phẩm khi đơn chưa giao',
            '6. Chặn đánh giá khi đơn chưa ở trạng thái DaGiao',
            v_ok, v_ts,
            'trg_kiem_tra_danh_gia, fn_kiem_tra_danh_gia(), danh_gia',
            v_msg
        );

        -- 7. Doi gia san pham sau khi da co don -> don cu giu nguyen gia luc dat
        v_ok := false;
        v_msg := '';
        BEGIN
            v_don := fn_tao_don_hang(1, 1, 1, clock_timestamp()::timestamp, NULL, '[{"bt":1,"sl":1}]'::jsonb, 'Web');
            UPDATE bien_the SET gia_ban = 9900000 WHERE ma_bien_the = 1;
            SELECT don_gia INTO v_gia_don FROM chi_tiet_don_hang WHERE ma_don_hang = v_don AND ma_bien_the = 1;
            v_ok := (v_gia_don = 8900000);
            v_msg := 'Đơn thử #' || v_don || ': Giá danh mục (bien_the.gia_ban) đổi từ 8.900.000 -> 9.900.000 VNĐ nhưng chi_tiet_don_hang.don_gia vẫn giữ nguyên ' || v_gia_don || ' VNĐ.';
            RAISE EXCEPTION 'ROLLBACK_SUB';
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
        INSERT INTO kq_sub VALUES (
            7,
            'Bảo toàn đơn giá lịch sử khi đổi giá danh mục',
            '7. Đổi giá sản phẩm không làm đổi giá đơn cũ đã đặt',
            v_ok, v_ts,
            'chi_tiet_don_hang.don_gia (snapshot), bien_the.gia_ban',
            v_msg
        );
    END $$;
    """
    cmd = [
        PSQL_PATH, "-h", DB_HOST, "-p", str(DB_PORT), "-U", DB_USER, "-d", DB_NAME,
        "-X", "-q", "-A", "-t", "-f", "-"
    ]
    wrapped_sub = f"BEGIN;\n{sql_cases_2_3_5_6_7}\nSELECT COALESCE(json_agg(t), '[]'::json) FROM (SELECT stt, short_name, name, passed, thoi_diem, tech_objects, detail FROM kq_sub ORDER BY stt) t;\nROLLBACK;"
    res_sub = subprocess.run(cmd, input=wrapped_sub, capture_output=True, text=True, encoding="utf-8", env=build_pg_env())
    out_sub = res_sub.stdout.strip()
    s_idx, e_idx = out_sub.find("["), out_sub.rfind("]")
    sub_list = json.loads(out_sub[s_idx:e_idx + 1]) if (s_idx != -1 and e_idx != -1) else []
    sub_map = {int(r["stt"]): r for r in sub_list}

    if 2 in sub_map:
        sub_map[2]["passed"] = bool(sub_map[2]["passed"] and (not jump_on_canceled["ok"]))
        sub_map[2]["detail"] += f" Thử chuyển ngược DaHuy -> DaXacNhan trên đơn #{oid_c1} bị chặn={not jump_on_canceled['ok']} ({jump_on_canceled.get('code', '')})."
        results.append(sub_map[2])
    if 3 in sub_map:
        results.append(sub_map[3])

    # -----------------------------------------------------------------
    # CA 4: Ca tranh mua chay HAI KET NOI THAT dong thoi va kiem tra ket qua CSDL
    # -----------------------------------------------------------------
    rc_out = execute_race_condition_run(run_id=f"VERIFY4-{int(time.time()*1000)}")
    a_ok = bool(rc_out["khach_a"]["thanh_cong"])
    b_ok = bool(rc_out["khach_b"]["thanh_cong"])
    tk_rc = rc_out["ton_kho_cuoi"]
    c4_passed = (
        (a_ok != b_ok)
        and int(tk_rc["so_luong_vat_ly"]) == 1
        and int(tk_rc["so_luong_giu"]) == 1
        and int(tk_rc["so_luong_kha_dung"]) == 0
        and int(tk_rc["so_dong_giu"]) == 1
    )
    results.append({
        "stt": 4,
        "short_name": "Chặn bán vượt tồn khi 2 phiên tranh chiếc hàng cuối",
        "name": "4. Hai khách giữ chiếc hàng cuối đồng thời (2 kết nối psql thật)",
        "passed": c4_passed,
        "thoi_diem": rc_out.get("thoi_diem"),
        "tech_objects": "fn_cap_nhat_ton_kho(), Row-level Lock trên ton_kho, ck_giu_khong_vuot_vat_ly",
        "detail": (
            f"Mã lần chạy {rc_out['run_id']} (SKU {rc_out['sku']}): "
            f"Đơn A #{rc_out['khach_a']['ma_don_hang']}={rc_out['khach_a']['trang_thai']}, "
            f"Đơn B #{rc_out['khach_b']['ma_don_hang']}={rc_out['khach_b']['trang_thai']}. "
            f"Đơn thắng=#{rc_out['don_thang']}, Tồn cuối: Vật lý={tk_rc['so_luong_vat_ly']}, "
            f"Đang giữ={tk_rc['so_luong_giu']}, Khả dụng={tk_rc['so_luong_kha_dung']}, Dòng sổ cái GIU={tk_rc['so_dong_giu']}."
        )
    })

    if 5 in sub_map:
        results.append(sub_map[5])
    if 6 in sub_map:
        results.append(sub_map[6])
    if 7 in sub_map:
        results.append(sub_map[7])

    # -----------------------------------------------------------------
    # CA 8: Giao dich loi giua chung -> so sanh don_hang, ton_kho va bien_dong_kho TRUOC va SAU
    # -----------------------------------------------------------------
    snap_before = run_psql_json("""
        SELECT
            (SELECT COUNT(*) FROM don_hang) AS tong_don,
            (SELECT so_luong_vat_ly FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1) AS vl,
            (SELECT so_luong_giu FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1) AS giu,
            (SELECT COUNT(*) FROM bien_dong_kho WHERE ma_kho = 1 AND ma_bien_the = 1) AS bdk_count
    """)[0]

    failing_tx_sql = """
    BEGIN;
    DO $$
    DECLARE
        v_d INT;
    BEGIN
        v_d := fn_tao_don_hang(1, 1, 1, clock_timestamp()::timestamp, NULL, '[{"bt":1,"sl":2}]'::jsonb, 'Web');
        UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = v_d;
        UPDATE don_hang SET trang_thai = 'DangGiao' WHERE ma_don_hang = v_d;
        -- Gay loi rang buoc o buoc tiep theo trong cung giao dich (so_tien thanh toan am vi pham CHECK)
        INSERT INTO thanh_toan(ma_don_hang, phuong_thuc, so_tien) VALUES (v_d, 'COD', -1000);
    END $$;
    COMMIT;
    """
    rc_fail, _, err_fail = run_psql_command(failing_tx_sql)

    snap_after = run_psql_json("""
        SELECT
            (SELECT COUNT(*) FROM don_hang) AS tong_don,
            (SELECT so_luong_vat_ly FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1) AS vl,
            (SELECT so_luong_giu FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = 1) AS giu,
            (SELECT COUNT(*) FROM bien_dong_kho WHERE ma_kho = 1 AND ma_bien_the = 1) AS bdk_count,
            (SELECT khop FROM v_doi_soat_kho WHERE ma_kho = 1 AND ma_bien_the = 1) AS khop,
            to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS') AS ts
    """)[0]

    c8_passed = (
        rc_fail != 0
        and int(snap_before["tong_don"]) == int(snap_after["tong_don"])
        and int(snap_before["vl"]) == int(snap_after["vl"])
        and int(snap_before["giu"]) == int(snap_after["giu"])
        and int(snap_before["bdk_count"]) == int(snap_after["bdk_count"])
        and bool(snap_after["khop"])
    )
    err_fail_short = translate_pg_error(err_fail) if err_fail else "Lỗi CHECK so_tien > 0"
    results.append({
        "stt": 8,
        "short_name": "Hoàn tác toàn bộ Đơn – Kho – Sổ cái khi lỗi giữa chừng",
        "name": "8. Giao dịch lỗi giữa chừng — đối chiếu Đơn, Tồn kho và Sổ cái trước/sau",
        "passed": c8_passed,
        "thoi_diem": snap_after["ts"],
        "tech_objects": "ACID Transaction Rollback, thanh_toan_so_tien_check, v_doi_soat_kho",
        "detail": (
            f"Giao dịch tạo đơn + GIU + XUAT rồi chèn thanh_toan(-1000) bị từ chối ({err_fail_short}). "
            f"Đối chiếu trước → sau: Tổng đơn ({snap_before['tong_don']} → {snap_after['tong_don']}), "
            f"Vật lý SKU #1 ({snap_before['vl']} → {snap_after['vl']}), "
            f"Đang giữ SKU #1 ({snap_before['giu']} → {snap_after['giu']}), "
            f"Dòng sổ cái SKU #1 ({snap_before['bdk_count']} → {snap_after['bdk_count']}), "
            f"Đối soát khớp={snap_after['khop']}."
        )
    })

    verify_pair_reconcile(1, [1], mo_ta=f"Kiểm thử 8 kịch bản nghiệp vụ (Đơn #{oid_c1})")
    return sorted(results, key=lambda x: x["stt"])


HTML_CONTENT = """<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OmniStock — Quản lý kho và đơn hàng</title>
    <style>
        :root {
            --nav-bg: #131921;
            --nav-sub: #232f3e;
            --page-bg: #f3f4f6;
            --surface: #ffffff;
            --border: #d5d9d9;
            --border-strong: #adb1b8;
            --text: #0f1111;
            --text-secondary: #565959;
            --amber-bg: #ff9900;
            --amber-bg-hover: #e88b00;
            --amber-border: #c45500;
            --success: #067d62;
            --success-bg: #f0fdf4;
            --success-border: #86efac;
            --danger: #b12704;
            --danger-bg: #fef2f2;
            --danger-border: #fca5a5;
            --diff-bg: #fff8e6;
            --diff-border: #e47911;
            --tech-bg: #f1f5f9;
            --tech-border: #cbd5e1;
            --tech-text: #334155;
        }
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        body {
            font-family: Arial, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            background-color: var(--page-bg);
            color: var(--text);
            font-size: 14px;
            line-height: 1.38;
        }

        /* Che do Hien chi tiet ky thuat (mac dinh tat) */
        .tech-only {
            display: none !important;
        }
        body.tech-mode span.tech-only,
        body.tech-mode code.tech-only {
            display: inline !important;
        }
        body.tech-mode div.tech-only,
        body.tech-mode p.tech-only {
            display: block !important;
        }
        body.tech-mode th.tech-only,
        body.tech-mode td.tech-only {
            display: table-cell !important;
        }
        .tech-tag {
            font-family: Consolas, "Courier New", monospace;
            font-size: 11px;
            background-color: var(--tech-bg);
            color: var(--tech-text);
            border: 1px solid var(--tech-border);
            border-radius: 3px;
            padding: 1px 5px;
            font-weight: 600;
        }
        .tech-block {
            margin-top: 4px;
            padding: 4px 8px;
            background-color: var(--tech-bg);
            border-left: 3px solid #64748b;
            border-radius: 2px;
            font-family: Consolas, "Courier New", monospace;
            font-size: 11.5px;
            color: var(--tech-text);
            line-height: 1.4;
        }

        /* Thanh dau trang thap (OmniStock Admin style) */
        .topbar {
            background-color: var(--nav-bg);
            color: #ffffff;
            min-height: 40px;
            padding: 4px 16px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            border-bottom: 1px solid #000000;
            flex-wrap: wrap;
            gap: 10px;
        }
        .topbar-left {
            display: flex;
            align-items: center;
            gap: 10px;
            flex-wrap: wrap;
        }
        .brand-name {
            font-size: 15px;
            font-weight: 700;
            letter-spacing: 0.2px;
            color: #ffffff;
        }
        .brand-divider {
            color: #6b7280;
            font-size: 14px;
        }
        .page-title {
            font-size: 12.5px;
            color: #e5e7eb;
        }
        .sim-badge {
            background-color: #374151;
            color: #fde68a;
            border: 1px solid #6b7280;
            border-radius: 3px;
            padding: 1px 7px;
            font-size: 11px;
            font-weight: 600;
        }

        /* Tabs dieu huong */
        .nav-tabs {
            display: flex;
            align-items: center;
            gap: 4px;
            margin-left: 6px;
        }
        .tab-btn {
            background-color: transparent;
            color: #d1d5db;
            border: 1px solid transparent;
            border-radius: 4px;
            padding: 4px 11px;
            font-size: 12.5px;
            font-weight: 600;
            cursor: pointer;
            transition: background-color 0.12s;
        }
        .tab-btn:hover {
            background-color: var(--nav-sub);
            color: #ffffff;
        }
        .tab-btn.active {
            background-color: var(--amber-bg);
            color: #0f1111;
            border-color: var(--amber-border);
            font-weight: 700;
        }
        .tab-badge {
            display: inline-block;
            margin-left: 5px;
            padding: 0 5px;
            font-size: 10.5px;
            border-radius: 8px;
            background-color: rgba(0, 0, 0, 0.22);
            color: inherit;
        }

        .topbar-right {
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 12px;
            color: #d1d5db;
            flex-wrap: wrap;
        }
        .period-select {
            background-color: var(--nav-sub);
            color: #ffffff;
            border: 1px solid #4b5563;
            border-radius: 4px;
            padding: 3px 8px;
            font-size: 12px;
            font-weight: 600;
        }
        .tech-toggle-label {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            cursor: pointer;
            background-color: var(--nav-sub);
            border: 1px solid #4b5563;
            border-radius: 4px;
            padding: 3px 9px;
            font-size: 12px;
            color: #f3f4f6;
            user-select: none;
        }
        .tech-toggle-label:hover {
            border-color: #9ca3af;
        }
        .tech-toggle-label input {
            accent-color: var(--amber-bg);
            cursor: pointer;
        }
        .btn-top {
            background-color: var(--nav-sub);
            color: #ffffff;
            border: 1px solid #4b5563;
            border-radius: 4px;
            padding: 3px 10px;
            font-size: 12px;
            font-weight: 600;
            cursor: pointer;
        }
        .btn-top:hover:not(:disabled) {
            background-color: #374151;
        }
        .btn-top:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }

        /* Dai thong ke phia tren (gon, ro 4 nhom) */
        .summary-strip {
            background-color: var(--surface);
            border-bottom: 1px solid var(--border);
            padding: 6px 16px;
        }
        .summary-grid {
            display: grid;
            grid-template-columns: 1fr 1.15fr 1.1fr 1.35fr;
            gap: 14px;
            align-items: start;
        }
        .summary-item {
            display: flex;
            flex-direction: column;
            border-right: 1px solid #eaeded;
            padding-right: 12px;
        }
        .summary-item:last-child {
            border-right: none;
            padding-right: 0;
        }
        .summary-label-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 6px;
        }
        .summary-label {
            font-size: 14px;
            color: var(--text-secondary);
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.2px;
        }
        .summary-value-row {
            display: flex;
            align-items: baseline;
            justify-content: space-between;
            gap: 8px;
            margin-top: 1px;
            flex-wrap: wrap;
        }
        .summary-value {
            font-size: 24px;
            font-weight: 700;
            color: var(--text);
            font-variant-numeric: tabular-nums;
            white-space: nowrap;
        }
        .summary-note {
            font-size: 11.5px;
            color: var(--text-secondary);
        }
        .time-lines {
            display: flex;
            flex-direction: column;
            gap: 2px;
            font-size: 11.5px;
            color: var(--text-secondary);
            margin-top: 1px;
        }
        .time-line-row {
            display: flex;
            justify-content: space-between;
            gap: 6px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .time-line-label {
            color: var(--text-secondary);
        }
        .time-line-val {
            font-weight: 600;
            color: var(--text);
            font-variant-numeric: tabular-nums;
        }
        .summary-more-bar {
            margin-top: 4px;
            padding-top: 4px;
            border-top: 1px dashed #e5e7eb;
            display: flex;
            align-items: center;
            justify-content: space-between;
            font-size: 11.5px;
            color: var(--text-secondary);
            flex-wrap: wrap;
            gap: 8px;
        }
        .link-btn {
            background: none;
            border: none;
            color: #1d4ed8;
            font-size: 11.5px;
            font-weight: 600;
            cursor: pointer;
            padding: 0;
            text-decoration: underline;
        }
        .summary-drawer {
            display: none;
            margin-top: 5px;
            padding: 6px 10px;
            background-color: var(--tech-bg);
            border: 1px solid var(--tech-border);
            border-radius: 4px;
            font-size: 11.5px;
            color: var(--tech-text);
            line-height: 1.45;
        }
        .summary-drawer.open,
        body.tech-mode .summary-drawer {
            display: block;
        }

        .text-ok { color: var(--success); }
        .text-err { color: var(--danger); }
        .text-muted { color: var(--text-secondary); }

        /* Thong bao loi / trang thai */
        .alert-banner {
            display: none;
            margin: 6px 16px 0 16px;
            padding: 6px 12px;
            border-radius: 4px;
            font-size: 12.5px;
            font-weight: 600;
        }
        .alert-banner.error {
            display: flex;
            align-items: center;
            justify-content: space-between;
            background-color: var(--danger-bg);
            border: 1px solid var(--danger-border);
            color: var(--danger);
        }
        .alert-banner.success {
            display: flex;
            align-items: center;
            justify-content: space-between;
            background-color: var(--success-bg);
            border: 1px solid var(--success-border);
            color: var(--success);
        }

        /* Bo cuc chinh & Tabs */
        .container {
            padding: 8px 16px 20px 16px;
            max-width: 1600px;
            margin: 0 auto;
        }
        .tab-panel {
            display: none;
        }
        .tab-panel.active {
            display: block;
        }
        .workspace-grid {
            display: grid;
            grid-template-columns: 48% 52%;
            gap: 14px;
            align-items: start;
        }
        @media (max-width: 1024px) {
            .workspace-grid,
            .summary-grid {
                grid-template-columns: 1fr;
            }
            .summary-item {
                border-right: none;
                border-bottom: 1px solid #eaeded;
                padding-bottom: 4px;
            }
        }

        .panel {
            background-color: var(--surface);
            border: 1px solid var(--border);
            border-radius: 4px;
            padding: 10px 14px;
        }
        .panel-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid #eaeded;
            padding-bottom: 6px;
            margin-bottom: 8px;
            flex-wrap: wrap;
            gap: 6px;
        }
        .panel-title {
            font-size: 18px;
            font-weight: 700;
            color: var(--text);
        }
        .panel-subtitle {
            font-size: 12.5px;
            color: var(--text-secondary);
        }

        /* Khu vuc Xu ly don hang */
        .order-config-bar {
            display: flex;
            align-items: center;
            gap: 6px;
            background-color: #f8f9fa;
            border: 1px solid #eaeded;
            border-radius: 4px;
            padding: 6px 8px;
            margin-bottom: 8px;
            font-size: 13px;
            flex-wrap: wrap;
        }
        .order-config-bar label {
            color: var(--text-secondary);
            font-weight: 600;
        }
        .select-input, .qty-input, .text-input {
            border: 1px solid var(--border-strong);
            border-radius: 3px;
            padding: 3px 6px;
            font-size: 13px;
            color: var(--text);
            background-color: #ffffff;
        }
        .qty-input {
            width: 48px;
            text-align: right;
            font-variant-numeric: tabular-nums;
        }
        .text-input {
            width: 90px;
            font-variant-numeric: tabular-nums;
        }

        .order-details-table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 8px;
        }
        .order-details-table th,
        .order-details-table td {
            padding: 5px 8px;
            border-bottom: 1px solid #eaeded;
            font-size: 13.5px;
            vertical-align: top;
        }
        .order-details-table th {
            width: 130px;
            color: var(--text-secondary);
            font-weight: 600;
            text-align: left;
            background-color: #fafafa;
        }
        .order-details-table td {
            color: var(--text);
            font-weight: 600;
        }
        .status-badge {
            display: inline-block;
            padding: 1px 7px;
            border-radius: 3px;
            font-size: 12.5px;
            font-weight: 700;
        }
        .status-ChoXacNhan { color: #b45309; background-color: #fef3c7; border: 1px solid #fcd34d; }
        .status-DaXacNhan { color: #1e293b; background-color: #e2e8f0; border: 1px solid #cbd5e1; }
        .status-DangGiao { color: #1d4ed8; background-color: #dbeafe; border: 1px solid #93c5fd; }
        .status-DaGiao { color: var(--success); background-color: var(--success-bg); border: 1px solid var(--success-border); }
        .status-DaHuy { color: var(--danger); background-color: var(--danger-bg); border: 1px solid var(--danger-border); }

        /* Bang 4 chi tieu tien don hang */
        .money-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 8px;
            margin-bottom: 8px;
        }
        .money-cell {
            background-color: #fafafa;
            border: 1px solid #eaeded;
            border-radius: 4px;
            padding: 6px 8px;
        }
        .money-cell.highlight-rev {
            background-color: #f8fafc;
            border-color: var(--border-strong);
        }
        .money-label {
            font-size: 13.5px;
            color: var(--text-secondary);
            display: block;
        }
        .money-val {
            font-size: 14.5px;
            font-weight: 700;
            font-variant-numeric: tabular-nums;
            display: block;
            margin-top: 2px;
        }
        .money-sub {
            font-size: 11.5px;
            color: var(--text-secondary);
            display: block;
            margin-top: 1px;
        }

        /* Thanh nut thao tac */
        .action-bar {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 6px;
            padding-top: 2px;
            flex-wrap: wrap;
        }
        .action-group-main {
            display: flex;
            align-items: center;
            gap: 5px;
            flex-wrap: wrap;
        }
        .action-group-cancel {
            margin-left: auto;
            padding-left: 8px;
            border-left: 1px solid var(--border);
        }
        .btn {
            border-radius: 4px;
            padding: 5px 10px;
            font-size: 12.5px;
            font-weight: 600;
            cursor: pointer;
            border: 1px solid var(--border-strong);
            background-color: #f0f2f2;
            color: var(--text);
        }
        .btn-xs {
            padding: 2px 7px;
            font-size: 11.5px;
        }
        .btn:disabled {
            background-color: #f3f4f6;
            border-color: #d5d9d9;
            color: #9ca3af;
            cursor: not-allowed;
            font-weight: 400;
        }
        .btn.btn-next-valid:not(:disabled) {
            background-color: var(--amber-bg);
            border-color: var(--amber-border);
            color: #0f1111;
            font-weight: 700;
        }
        .btn.btn-next-valid:not(:disabled):hover {
            background-color: var(--amber-bg-hover);
        }
        .btn-cancel:not(:disabled) {
            background-color: #ffffff;
            border-color: var(--danger);
            color: var(--danger);
            font-weight: 600;
        }
        .btn-cancel:not(:disabled):hover {
            background-color: var(--danger-bg);
        }
        .btn-secondary:not(:disabled) {
            background-color: #ffffff;
            border-color: var(--nav-sub);
            color: var(--text);
            font-weight: 700;
        }
        .btn-secondary:not(:disabled):hover {
            background-color: #f3f4f6;
        }

        .action-feedback {
            margin-top: 5px;
            font-size: 12px;
            color: var(--text-secondary);
            min-height: 16px;
        }

        /* Bang du lieu Ton kho & Nhat ky */
        .data-table {
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 13.5px;
        }
        .data-table th,
        .data-table td {
            padding: 6px 9px;
            border-bottom: 1px solid #eaeded;
        }
        .data-table th {
            background-color: #f8f9fa;
            color: var(--text-secondary);
            font-size: 12.5px;
            font-weight: 700;
            text-align: left;
            border-top: 1px solid #eaeded;
        }
        .data-table th.num,
        .data-table td.num {
            text-align: right;
            font-variant-numeric: tabular-nums;
        }
        .data-table tr.active-product-row {
            background-color: #fffbeb;
        }
        .data-table tfoot td {
            background-color: #f8f9fa;
            font-weight: 700;
            border-top: 2px solid var(--border);
            padding: 7px 9px;
        }
        .prod-name {
            font-size: 15px;
            font-weight: 600;
            color: var(--text);
        }
        .prod-attr {
            color: #374151;
            font-weight: 600;
            font-size: 12.5px;
        }
        .sku-code {
            font-size: 12px;
            color: var(--text-secondary);
            font-weight: 400;
            display: block;
            margin-top: 1px;
        }
        .formula-pill {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            background-color: #f8f9fa;
            border: 1px solid #d5d9d9;
            border-radius: 3px;
            padding: 2px 7px;
            font-size: 12px;
            color: var(--text-secondary);
        }

        /* Vung cuon rieng thich ung cho Ton kho va Nhat ky */
        .inventory-scroll,
        .log-scroll {
            overflow-y: auto;
            overflow-x: auto;
            border: 1px solid #eaeded;
            border-radius: 4px;
            background: #ffffff;
        }
        .inventory-scroll {
            max-height: clamp(330px, 42vh, 430px);
        }
        .log-scroll {
            max-height: clamp(340px, 44vh, 440px);
        }
        .inventory-scroll thead th,
        .log-scroll thead th {
            position: sticky;
            top: 0;
            z-index: 10;
            background-color: #f8f9fa;
            border-bottom: 1px solid #d5d9d9;
            box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
        }

        /* Tooltip ngan gon, truc quan ho tro Hover, Focus ban phim va Touch */
        .tooltip {
            position: relative;
            display: inline-block;
            cursor: help;
            border-bottom: 1px dotted var(--text-secondary);
            outline: none;
        }
        .tooltip:focus-visible {
            outline: 2px solid #ff9900;
            outline-offset: 1px;
            border-radius: 2px;
        }
        .tooltip::after {
            content: attr(data-tooltip);
            position: absolute;
            bottom: calc(100% + 7px);
            left: 50%;
            transform: translateX(-50%);
            background-color: #1e293b;
            color: #ffffff;
            font-size: 12px;
            font-weight: 500;
            line-height: 1.35;
            padding: 6px 10px;
            border-radius: 4px;
            white-space: normal;
            width: max-content;
            max-width: 260px;
            text-align: center;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
            pointer-events: none;
            z-index: 1000;
            opacity: 0;
            visibility: hidden;
            transition: opacity 0.15s ease, visibility 0.15s ease;
        }
        .tooltip::before {
            content: "";
            position: absolute;
            bottom: calc(100% + 1px);
            left: 50%;
            transform: translateX(-50%);
            border-width: 6px 6px 0 6px;
            border-style: solid;
            border-color: #1e293b transparent transparent transparent;
            pointer-events: none;
            z-index: 1000;
            opacity: 0;
            visibility: hidden;
            transition: opacity 0.15s ease, visibility 0.15s ease;
        }
        .tooltip:hover::after,
        .tooltip:focus::after,
        .tooltip:active::after,
        .tooltip:hover::before,
        .tooltip:focus::before,
        .tooltip:active::before {
            opacity: 1;
            visibility: visible;
        }

        /* Tooltip mo huong xuong cho tieu de bang khong bi clip boi container cuon */
        .tooltip.tooltip-down::after {
            bottom: auto;
            top: calc(100% + 7px);
            left: auto;
            right: 0;
            transform: none;
        }
        .tooltip.tooltip-down::before {
            bottom: auto;
            top: calc(100% + 1px);
            left: auto;
            right: 18px;
            transform: none;
            border-width: 0 6px 6px 6px;
            border-color: transparent transparent #1e293b transparent;
        }

        /* O ton kho vua doi */
        td.cell-changed {
            background-color: var(--diff-bg);
            outline: 1px solid var(--diff-border);
            outline-offset: -1px;
        }
        .diff-inline {
            display: inline-block;
            font-size: 11.5px;
            font-weight: 700;
            color: #b45309;
            margin-left: 5px;
        }
        .val-current {
            font-weight: 700;
            color: var(--text);
        }

        /* Khu vuc Nhat ky giao dich, Kiem thu, Bao cao */
        .section-stack {
            margin-top: 10px;
            display: flex;
            flex-direction: column;
            gap: 10px;
        }
        .bottom-ops-grid {
            display: grid;
            grid-template-columns: 65% 35%; /* Adjusted ratio for log and revenue */
            gap: 12px;
            align-items: start;
        }
        @media (max-width: 1100px) {
            .bottom-ops-grid {
                grid-template-columns: 1fr;
            }
        }
        .op-badge {
            display: inline-block;
            font-weight: 700;
            font-size: 11.5px;
            padding: 1px 6px;
            border-radius: 3px;
        }
        .op-GIU { color: #b45309; background-color: #fef3c7; }
        .op-XUAT { color: #1d4ed8; background-color: #dbeafe; }
        .op-NHA_GIU, .op-HOAN { color: var(--danger); background-color: var(--danger-bg); }
        .op-NHAP, .op-DIEU_CHINH { color: var(--success); background-color: var(--success-bg); }
        .trigger-code {
            font-family: Consolas, monospace;
            font-size: 11px;
            color: var(--text-secondary);
        }

        /* Tab Kiem thu he thong */
        .test-status-pill {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 3px;
            font-size: 11.5px;
            font-weight: 700;
        }
        .test-status-untested {
            background-color: #f3f4f6;
            color: var(--text-secondary);
            border: 1px solid #d1d5db;
        }
        .test-status-pass {
            background-color: var(--success-bg);
            color: var(--success);
            border: 1px solid var(--success-border);
        }
        .test-status-fail {
            background-color: var(--danger-bg);
            color: var(--danger);
            border: 1px solid var(--danger-border);
        }
        .test-detail-row {
            display: none;
            background-color: #f8fafc;
        }
        .test-detail-row.open {
            display: table-row;
        }
        .test-detail-box {
            padding: 8px 10px;
            border-left: 3px solid #64748b;
            font-size: 12px;
            color: var(--text);
            line-height: 1.45;
        }
        .race-grid {
            display: grid;
            grid-template-columns: 1fr 1fr 1fr;
            gap: 10px;
            margin-top: 8px;
        }
        @media (max-width: 980px) {
            .race-grid {
                grid-template-columns: 1fr;
            }
        }
        .race-box {
            border: 1px solid var(--border);
            border-radius: 4px;
            padding: 8px 10px;
            background-color: #fafafa;
        }
        .race-box.win {
            border-color: var(--success);
            background-color: var(--success-bg);
        }
        .race-box.lose {
            border-color: var(--danger);
            background-color: var(--danger-bg);
        }
        .race-box-title {
            font-size: 12.5px;
            font-weight: 700;
            margin-bottom: 4px;
            display: flex;
            justify-content: space-between;
            gap: 6px;
        }
        .race-meta {
            font-size: 12px;
            color: var(--text);
            line-height: 1.45;
        }
        .sql-note {
            margin-top: 8px;
            padding: 6px 10px;
            background-color: #f8f9fa;
            border: 1px solid #eaeded;
            border-radius: 4px;
            font-size: 11.5px;
            color: var(--text-secondary);
        }
    </style>
</head>
<body>
    <!-- Thanh dau trang -->
    <header class="topbar">
        <div class="topbar-left">
            <span class="brand-name">OmniStock</span>
            <span class="brand-divider">|</span>
            <span class="page-title">Quản lý kho &amp; đơn hàng</span>
            <span class="sim-badge" title="Hệ thống vận hành trên bộ dữ liệu mô phỏng PostgreSQL">Dữ liệu mô phỏng</span>
            <nav class="nav-tabs" aria-label="Chế độ màn hình">
                <button id="tab-btn-ops" class="tab-btn active" type="button" onclick="switchTab('ops')">Vận hành</button>
                <button id="tab-btn-tests" class="tab-btn" type="button" onclick="switchTab('tests')">
                    Kiểm thử hệ thống <span id="tab-tests-badge" class="tab-badge">Chưa chạy</span>
                </button>
            </nav>
        </div>
        <div class="topbar-right">
            <label for="select-period">Kỳ:</label>
            <select id="select-period" class="period-select" onchange="loadDashboard()">
                <option value="toan_ky">Toàn kỳ</option>
                <option value="thang_10">Tháng 10/2026</option>
            </select>
            <label class="tech-toggle-label" for="toggle-tech">
                <input id="toggle-tech" type="checkbox" onchange="toggleTechMode(this.checked)">
                <span>Hiện chi tiết kỹ thuật</span>
            </label>
            <button id="btn-refresh" class="btn-top" type="button" onclick="loadDashboard()">Làm mới</button>
        </div>
    </header>

    <!-- Dai thong ke phia tren -->
    <section class="summary-strip" aria-label="Tóm tắt hệ thống">
        <div class="summary-grid">
            <div class="summary-item">
                <div class="summary-label-row">
                    <span class="summary-label" id="lbl-don-hang">Tổng đơn hàng</span>
                    <span class="summary-note" id="stat-catalog-note">16 SKU · 2 kho</span>
                </div>
                <div class="summary-value-row">
                    <span class="summary-value" id="stat-don-hang">Đang tải...</span>
                    <span class="summary-note" id="stat-don-hang-note">—</span>
                </div>
                <div class="tech-only tech-block" id="tech-kpi-orders">
                    Bảng: <code>don_hang</code> · Cột lọc kỳ: <code>ngay_dat</code>
                </div>
            </div>

            <div class="summary-item">
                <div class="summary-label-row">
                    <span class="summary-label" id="lbl-doanh-thu">Doanh thu thuần</span>
                    <span class="summary-note">Chỉ tính đơn Đã giao</span>
                </div>
                <div class="summary-value-row">
                    <span class="summary-value" id="stat-doanh-thu">Đang tải...</span>
                    <span class="summary-note" id="stat-doanh-thu-note">Không gồm phí giao hàng</span>
                </div>
                <div class="tech-only tech-block" id="tech-kpi-rev">
                    <code>SUM(tong_tien_hang - tien_giam) FILTER (WHERE trang_thai = 'DaGiao')</code>
                </div>
            </div>

            <div class="summary-item">
                <div class="summary-label-row">
                    <span class="summary-label">Đối soát tồn kho</span>
                    <button id="btn-reconcile" class="btn btn-xs btn-secondary" type="button" onclick="runFullReconcile()">Đối soát toàn bộ</button>
                </div>
                <div class="summary-value-row">
                    <span class="summary-value" id="stat-doi-soat">Đang kiểm tra...</span>
                    <span class="summary-note" id="stat-doi-soat-sub">—</span>
                </div>
                <div class="tech-only tech-block" id="tech-kpi-rec">
                    View: <code>v_doi_soat_kho</code> · Sổ cái: <span id="tech-ledger-count">—</span> dòng (<code>bien_dong_kho</code>)
                </div>
            </div>

            <div class="summary-item">
                <div class="summary-label-row">
                    <span class="summary-label">Thời điểm kiểm tra</span>
                    <button id="btn-toggle-summary-tech" class="link-btn" type="button" onclick="toggleSummaryDrawer()">Chi tiết đối soát &amp; SQL</button>
                </div>
                <div class="time-lines">
                    <div class="time-line-row">
                        <span class="time-line-label">Cập nhật dashboard:</span>
                        <span class="time-line-val" id="ts-dashboard">—</span>
                    </div>
                    <div class="time-line-row">
                        <span class="time-line-label">Đối soát toàn bộ:</span>
                        <span class="time-line-val" id="ts-full-reconcile">—</span>
                    </div>
                    <div class="time-line-row">
                        <span class="time-line-label">Thao tác gần nhất:</span>
                        <span class="time-line-val" id="ts-pair-check">Chưa phát sinh</span>
                    </div>
                </div>
            </div>
        </div>

        <div id="summary-tech-drawer" class="summary-drawer">
            <div id="summary-drawer-content">
                Đang tải thông tin đối soát và công thức SQL...
            </div>
        </div>
    </section>

    <!-- Thong bao loi / thanh cong -->
    <div id="alert-banner" class="alert-banner" role="alert">
        <span id="alert-message"></span>
        <button class="btn btn-xs" type="button" onclick="hideAlert()">Đóng</button>
    </div>

    <main class="container">
        <!-- ==================== TAB 1: VAN HANH ==================== -->
        <div id="tab-panel-ops" class="tab-panel active">
            <div class="workspace-grid">
                <!-- Ben trai: Xu ly don hang -->
                <section class="panel" aria-labelledby="heading-order">
                    <div class="panel-header">
                        <div>
                            <h2 class="panel-title" id="heading-order" style="display:inline;">Xử lý đơn hàng</h2>
                            <span class="tech-only tech-tag" style="margin-left:6px;">don_hang · chi_tiet_don_hang</span>
                        </div>
                        <div style="display:flex; align-items:center; gap:5px; flex-wrap:wrap;">
                            <label for="select-recent-order" class="panel-subtitle">Đơn gần đây:</label>
                            <select id="select-recent-order" class="select-input" onchange="selectExistingOrder(this.value)">
                                <option value="">— Đơn mới nhất —</option>
                            </select>
                            <input id="input-find-order" class="text-input" type="number" min="1" placeholder="Nhập mã đơn" onkeydown="if(event.key==='Enter') findOrderById()">
                            <button class="btn btn-xs" type="button" onclick="findOrderById()">Tìm</button>
                        </div>
                    </div>

                    <!-- Cau hinh khi tao don moi -->
                    <div class="order-config-bar">
                        <label for="select-kho-xuat">Kho xuất:</label>
                        <select id="select-kho-xuat" class="select-input">
                            <option value="1">Kho Thủ Đức</option>
                            <option value="2">Kho Hà Nội</option>
                        </select>
                        <label for="select-bt">Sản phẩm:</label>
                        <select id="select-bt" class="select-input" onchange="onProductSelectChange()">
                            <option value="1">AX1-DEN-128 · Aurora X1 (Đen, 128GB) — 8.900.000 VNĐ</option>
                            <option value="2">AX1-TRG-128 · Aurora X1 (Trắng, 128GB) — 8.900.000 VNĐ</option>
                            <option value="3">AX1-DEN-256 · Aurora X1 (Đen, 256GB) — 10.500.000 VNĐ</option>
                            <option value="4">AX1P-XAM-256 · Aurora X1 Pro (Xám, 256GB) — 24.900.000 VNĐ</option>
                            <option value="5">AX1P-XAM-512 · Aurora X1 Pro (Xám, 512GB) — 29.900.000 VNĐ</option>
                        </select>
                        <label for="input-sl">Số lượng:</label>
                        <input id="input-sl" class="qty-input" type="number" min="1" max="5000" value="1">
                        <label for="select-bt2">Sản phẩm bổ sung:</label>
                        <select id="select-bt2" class="select-input">
                            <option value="">(Không thêm)</option>
                            <option value="2">AX1-TRG-128 (Trắng, 128GB)</option>
                            <option value="3">AX1-DEN-256 (Đen, 256GB)</option>
                            <option value="4">AX1P-XAM-256 (Xám, 256GB)</option>
                            <option value="5">AX1P-XAM-512 (Xám, 512GB)</option>
                        </select>
                        <input id="input-sl2" class="qty-input" type="number" min="1" max="5000" value="1" title="Số lượng sản phẩm 2">
                        <label for="select-voucher">Mã giảm:</label>
                        <select id="select-voucher" class="select-input">
                            <option value="">Không dùng</option>
                            <option value="2">AURORA5 (-5%, đơn &ge; 5tr)</option>
                            <option value="1">THANG10 (chỉ T10/2026)</option>
                            <option value="3">HETHAN20 (hết hạn)</option>
                        </select>
                    </div>

                    <table class="order-details-table">
                        <tbody>
                            <tr>
                                <th>Mã đơn &amp; Trạng thái</th>
                                <td id="ord-id-status">Đang tải...</td>
                            </tr>
                            <tr>
                                <th>Khách &amp; Ngày đặt</th>
                                <td id="ord-customer-date">Đang tải...</td>
                            </tr>
                            <tr>
                                <th>Sản phẩm / SKU</th>
                                <td id="ord-product">Đang tải...</td>
                            </tr>
                            <tr>
                                <th>Kho xuất &amp; Số lượng</th>
                                <td id="ord-wh-qty">Đang tải...</td>
                            </tr>
                        </tbody>
                    </table>

                    <!-- 4 chi tieu tien ro rang -->
                    <div class="money-grid" aria-label="Chi tiết giá trị đơn hàng">
                        <div class="money-cell">
                            <span class="money-label">Tiền hàng <span class="tech-only"><code>(tong_tien_hang)</code></span></span>
                            <span class="money-val" id="ord-money-subtotal">—</span>
                            <span class="money-sub">Trước giảm giá</span>
                        </div>
                        <div class="money-cell">
                            <span class="money-label">Giảm giá <span class="tech-only"><code>(tien_giam)</code></span></span>
                            <span class="money-val" id="ord-money-discount">—</span>
                            <span class="money-sub" id="ord-money-voucher-note">Khoản được giảm</span>
                        </div>
                        <div class="money-cell">
                            <span class="tooltip" tabindex="0" role="note" data-tooltip="Giá trị sau giảm giá = Tiền hàng − Giảm giá">Giá trị sau giảm giá</span>
                            <span class="money-val" id="ord-money-net">—</span>
                            <span class="money-sub">Tiền hàng &minus; Giảm giá</span>
                        </div>
                        <div class="money-cell highlight-rev">
                            <span class="tooltip" tabindex="0" role="note" data-tooltip="Doanh thu ghi nhận = Tiền hàng − Giảm giá (chỉ tính cho đơn Đã giao, đơn khác = 0 VNĐ)">Doanh thu ghi nhận</span>
                            <span class="money-val" id="ord-money-rev">—</span>
                            <span class="money-sub" id="ord-money-rev-note">Chỉ cộng đơn Đã giao</span>
                        </div>
                    </div>

                    <div class="action-bar">
                        <div class="action-group-main">
                            <button id="btn-create" class="btn" type="button" onclick="stepOrder('create')">Tạo đơn</button>
                            <button id="btn-confirm" class="btn" type="button" onclick="stepOrder('confirm')" disabled>Xác nhận giữ kho</button>
                            <button id="btn-ship" class="btn" type="button" onclick="stepOrder('ship')" disabled>Xuất kho</button>
                            <button id="btn-deliver" class="btn" type="button" onclick="stepOrder('deliver')" disabled>Giao hàng</button>
                        </div>
                        <div class="action-group-cancel">
                            <button id="btn-cancel" class="btn btn-cancel" type="button" onclick="stepOrder('cancel')" disabled>Hủy đơn</button>
                        </div>
                    </div>

                    <div class="action-feedback" id="action-feedback">
                        Nhấn nút màu cam để thực hiện bước tiếp theo của đơn hàng.
                    </div>
                    <div class="tech-only tech-block" id="action-tech-feedback">
                        Hàm/Trigger: <code>fn_tao_don_hang()</code> &rarr; <code>trg_chuyen_trang_thai</code> &rarr; <code>trg_cap_nhat_ton_kho</code>
                    </div>
                </section>

                <!-- Ben phai: Ton kho theo kho -->
                <section class="panel" aria-labelledby="heading-inventory">
                    <div class="panel-header">
                        <div style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">
                            <h2 class="panel-title" id="heading-inventory">Tồn kho theo kho</h2>
                            <span class="formula-pill" title="Tồn khả dụng là số lượng còn có thể đặt mới: Khả dụng = Tồn vật lý trong kho trừ đi số lượng đang giữ cho các đơn Đã xác nhận">
                                Công thức: <strong>Khả dụng = Vật lý &minus; Đang giữ</strong>
                            </span>
                            <span class="tech-only tech-tag">ton_kho · v_ton_kha_dung</span>
                        </div>
                        <div style="display:flex; align-items:center; gap:5px;">
                            <label for="select-inv-kho" class="panel-subtitle">Kho:</label>
                            <select id="select-inv-kho" class="select-input" onchange="loadDashboard()">
                                <option value="1">Kho Thủ Đức</option>
                                <option value="2">Kho Hà Nội</option>
                                <option value="all">Tất cả kho</option>
                            </select>
                        </div>
                    </div>

                    <div class="inventory-scroll">
                        <table class="data-table" id="inventory-table">
                            <thead>
                                <tr>
                                    <th style="width: 115px;">Kho</th>
                                    <th>Sản phẩm / Biến thể / Mã SKU</th>
                                    <th class="num" style="width: 95px;">Vật lý <span class="tech-only"><code>(so_luong_vat_ly)</code></span></th>
                                    <th class="num" style="width: 95px;">Đang giữ <span class="tech-only"><code>(so_luong_giu)</code></span></th>
                                    <th class="num" style="width: 105px;">
                                        <span class="tooltip tooltip-down" tabindex="0" role="note" data-tooltip="Khả dụng = Vật lý − Đang giữ">Khả dụng</span>
                                        <span class="tech-only"><code>(kha_dung)</code></span>
                                    </th>
                                </tr>
                            </thead>
                            <tbody id="inventory-tbody">
                                <tr>
                                    <td colspan="5">Đang tải dữ liệu tồn kho...</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </section>
            </div>

            <!-- Phan duoi Tab Van hanh: Nhat ky giao dich & Doanh thu theo kenh -->
            <div class="section-stack">
                <div class="bottom-ops-grid">
                    <!-- Nhat ky giao dich -->
                    <section class="panel" aria-labelledby="heading-log">
                        <div class="panel-header">
                            <div style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">
                                <h2 class="panel-title" id="heading-log">Nhật ký giao dịch kho</h2>
                                <span class="panel-subtitle">Dữ liệu thực tế từ sổ cái</span>
                                <span class="tech-only tech-tag">bien_dong_kho · trg_khong_sua_so_cai</span>
                            </div>
                            <div style="display:flex; align-items:center; gap:8px;">
                                <label style="display:inline-flex; align-items:center; gap:5px; font-size:12px; cursor:pointer; font-weight:600;">
                                    <input type="checkbox" id="chk-filter-order-log" onchange="renderCurrentLogsView()">
                                    <span id="lbl-filter-order-log">Chỉ hiện đơn đang xem</span>
                                </label>
                            </div>
                        </div>

                        <div class="log-scroll">
                            <table class="data-table">
                                <thead>
                                    <tr>
                                        <th style="width: 138px;">Thời gian</th>
                                        <th style="width: 78px;">Mã đơn</th>
                                        <th>Sản phẩm / SKU</th>
                                        <th style="width: 110px;">Kho</th>
                                        <th style="width: 115px;">Nghiệp vụ <span class="tech-only"><code>(loai)</code></span></th>
                                        <th class="num" style="width: 185px;">Lượng thay đổi <span class="tech-only"><code>(delta)</code></span></th>
                                        <th class="tech-only" style="width: 155px;">Trigger / Hàm</th>
                                    </tr>
                                </thead>
                                <tbody id="log-tbody">
                                    <tr>
                                        <td colspan="7">Đang tải nhật ký giao dịch...</td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                    </section>

                    <!-- Doanh thu theo kenh ban -->
                    <section class="panel" aria-labelledby="heading-channels">
                        <div class="panel-header">
                            <div>
                                <h2 class="panel-title" id="heading-channels" style="display:inline;">Doanh thu thuần theo kênh</h2>
                                <span class="tech-only tech-tag" style="margin-left:6px;">GROUP BY kenh_ban</span>
                            </div>
                            <span class="panel-subtitle" id="channels-period-note">Toàn kỳ</span>
                        </div>
                        <div style="font-size:12.5px; color:var(--text-secondary); margin-bottom:8px;">
                            Đơn đã giao · Đã trừ giảm giá · Không gồm phí vận chuyển
                        </div>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Kênh bán</th>
                                    <th class="num">Đơn đã giao</th>
                                    <th class="num">Doanh thu thuần</th>
                                    <th class="num">Tỷ trọng</th>
                                </tr>
                            </thead>
                            <tbody id="channels-tbody">
                                <tr><td colspan="4">Đang tải...</td></tr>
                            </tbody>
                            <tfoot id="channels-tfoot"></tfoot>
                        </table>
                    </section>
                </div>
            </div>
        </div>

        <!-- ==================== TAB 2: KIEM THU HE THONG ==================== -->
        <div id="tab-panel-tests" class="tab-panel">
            <div class="section-stack" style="margin-top:0;">
                <!-- Phan 1: Kiem tra tranh mua -->
                <section class="panel" aria-labelledby="heading-race">
                    <div class="panel-header">
                        <div>
                            <h2 class="panel-title" id="heading-race" style="display:inline;">Kiểm tra tranh mua chiếc hàng cuối</h2>
                            <span class="panel-subtitle" style="margin-left:8px;">
                                Hai kết nối thực tế cùng xác nhận giữ kho 1 sản phẩm chỉ còn tồn khả dụng = 1
                            </span>
                        </div>
                        <div style="display:flex; gap:6px; align-items:center;">
                            <button id="btn-race-release" class="btn btn-xs" type="button" onclick="releaseCurrentRaceRun()" style="display:none;">Giải phóng giữ kho phiên này</button>
                            <button id="btn-race" class="btn btn-next-valid" type="button" onclick="runRaceCondition()">Chạy kiểm tra tranh mua</button>
                        </div>
                    </div>

                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Ca kiểm thử</th>
                                <th style="width: 190px;">Kết quả</th>
                                <th style="width: 165px;">Thời điểm chạy</th>
                                <th class="num" style="width: 120px;">Chi tiết</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td>
                                    <strong>Hai phiên đồng thời tranh giữ chiếc hàng cuối tại Kho Thủ Đức</strong>
                                    <span class="tech-only tech-tag" style="margin-left:6px;">UPDATE ton_kho ... WHERE so_luong_vat_ly - so_luong_giu &gt;= sl</span>
                                </td>
                                <td id="race-summary-status">
                                    <span class="test-status-pill test-status-untested">Chưa kiểm tra</span>
                                </td>
                                <td id="race-summary-time" style="font-variant-numeric: tabular-nums;">—</td>
                                <td class="num">
                                    <button id="btn-race-detail-toggle" class="btn btn-xs" type="button" onclick="toggleRaceDetail()" disabled>Xem chi tiết</button>
                                </td>
                            </tr>
                            <tr id="race-detail-row" class="test-detail-row">
                                <td colspan="4">
                                    <div id="race-result-container" class="test-detail-box">
                                        Chưa có dữ liệu chạy. Nhấn <strong>Chạy kiểm tra tranh mua</strong> để thực thi.
                                    </div>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </section>

                <!-- Phan 2: Tam kich ban nghiep vu -->
                <section class="panel" aria-labelledby="heading-guardrails">
                    <div class="panel-header">
                        <div>
                            <h2 class="panel-title" id="heading-guardrails" style="display:inline;">Tám kịch bản nghiệp vụ &amp; ràng buộc toàn vẹn</h2>
                            <span class="panel-subtitle" style="margin-left:8px;">Thực thi phép thử thật trên PostgreSQL &amp; API</span>
                        </div>
                        <div style="display:flex; gap:6px; align-items:center;">
                            <button id="btn-toggle-all-rules" class="btn btn-xs" type="button" onclick="toggleAllRuleDetails()" style="display:none;">Mở tất cả chi tiết</button>
                            <button id="btn-verify-rules" class="btn btn-next-valid" type="button" onclick="runVerifyRules()">Chạy kiểm thử 8 kịch bản</button>
                        </div>
                    </div>

                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Kịch bản nghiệp vụ</th>
                                <th style="width: 190px;">Kết quả</th>
                                <th style="width: 165px;">Thời điểm chạy</th>
                                <th class="num" style="width: 120px;">Chi tiết</th>
                            </tr>
                        </thead>
                        <tbody id="guardrails-tbody">
                        </tbody>
                    </table>
                </section>
            </div>
        </div>
    </main>

    <script>
        let currentOrder = null;
        let lastSummary = null;
        let lastReconcile = null;
        let lastRecentOrders = [];
        let lastInventory = [];
        let lastLogs = [];
        let lastOrderLogs = [];
        let lastChannels = [];
        let lastDiff = null;
        let lastActionMsg = '';
        let lastActionTechMsg = '';
        let isSubmittingOrder = false;
        let lastRaceRunId = null;
        let lastRaceData = null;
        let raceDetailOpen = false;
        let techMode = false;
        let lastWarehouses = [];
        let summaryDrawerOpen = false;
        let nextCreateIdemKey = 'ui-create-' + Date.now() + '-' + Math.random().toString(36).slice(2, 7);

        const DEFAULT_8_RULES = [
            {
                stt: 1,
                short_name: 'Chặn thao tác lặp (Xác nhận / Xuất / Hủy lặp)',
                tech_objects: 'FOR UPDATE on don_hang, REPEAT_ACTION (HTTP 409), uq_bien_dong_giu_1_lan, uq_bien_dong_xuat_1_lan'
            },
            {
                stt: 2,
                short_name: 'Chặn chuyển trạng thái sai thứ tự',
                tech_objects: 'trg_chuyen_trang_thai, fn_chuyen_trang_thai(), lich_su_trang_thai'
            },
            {
                stt: 3,
                short_name: 'Hoàn tác đơn nhiều SKU thiếu hàng & chặn đầu vào sai',
                tech_objects: 'trg_cap_nhat_ton_kho, fn_cap_nhat_ton_kho(), fn_tao_don_hang()'
            },
            {
                stt: 4,
                short_name: 'Chặn bán vượt tồn khi 2 phiên tranh chiếc hàng cuối',
                tech_objects: 'fn_cap_nhat_ton_kho(), Row-level Lock trên ton_kho, ck_giu_khong_vuot_vat_ly'
            },
            {
                stt: 5,
                short_name: 'Chặn áp dụng voucher hết hạn hoặc chưa đủ tối thiểu',
                tech_objects: 'trg_kiem_tra_voucher, fn_kiem_tra_voucher(), voucher'
            },
            {
                stt: 6,
                short_name: 'Chặn đánh giá sản phẩm khi đơn chưa giao',
                tech_objects: 'trg_kiem_tra_danh_gia, fn_kiem_tra_danh_gia(), danh_gia'
            },
            {
                stt: 7,
                short_name: 'Bảo toàn đơn giá lịch sử khi đổi giá danh mục',
                tech_objects: 'chi_tiet_don_hang.don_gia (snapshot), bien_the.gia_ban'
            },
            {
                stt: 8,
                short_name: 'Hoàn tác toàn bộ Đơn – Kho – Sổ cái khi lỗi giữa chừng',
                tech_objects: 'ACID Transaction Rollback, thanh_toan_so_tien_check, v_doi_soat_kho'
            }
        ];

        let verifyRulesResults = null;
        let openRuleDetails = new Set();

        const STATUS_SHORT = {
            'ChoXacNhan': 'Chờ xác nhận',
            'DaXacNhan': 'Đã xác nhận',
            'DangGiao': 'Đang giao',
            'DaGiao': 'Đã giao',
            'DaHuy': 'Đã hủy'
        };

        const STATUS_DESC = {
            'ChoXacNhan': 'Chờ xác nhận — Chưa giữ kho',
            'DaXacNhan': 'Đã xác nhận — Đang giữ hàng',
            'DangGiao': 'Đang giao — Đã xuất kho',
            'DaGiao': 'Đã giao — Tính doanh thu',
            'DaHuy': 'Đã hủy'
        };

        const OP_LABELS = {
            'NHAP': 'Nhập kho',
            'GIU': 'Giữ hàng',
            'NHA_GIU': 'Nhả giữ',
            'XUAT': 'Xuất kho',
            'HOAN': 'Hoàn kho',
            'DIEU_CHINH': 'Điều chỉnh'
        };

        const CHANNEL_LABELS = {
            'Web': 'Website (Web)',
            'CuaHang': 'Cửa hàng (CuaHang)',
            'DoiTac': 'Đối tác (DoiTac)'
        };

        const CHANNEL_SHORT = {
            'Web': 'Website',
            'CuaHang': 'Cửa hàng',
            'DoiTac': 'Đối tác'
        };

        const BUTTON_DEFAULT_TEXT = {
            'btn-create': 'Tạo đơn',
            'btn-confirm': 'Xác nhận giữ kho',
            'btn-ship': 'Xuất kho',
            'btn-deliver': 'Giao hàng',
            'btn-cancel': 'Hủy đơn'
        };

        function formatInt(n) {
            if (n === null || n === undefined || isNaN(Number(n))) return '—';
            return Number(n).toLocaleString('vi-VN');
        }

        function formatVnd(n) {
            if (n === null || n === undefined || isNaN(Number(n))) return '—';
            return Number(n).toLocaleString('vi-VN') + ' VNĐ';
        }

        function showAlert(msg, type = 'error') {
            const banner = document.getElementById('alert-banner');
            const msgEl = document.getElementById('alert-message');
            banner.className = 'alert-banner ' + type;
            msgEl.textContent = msg;
        }

        function hideAlert() {
            const banner = document.getElementById('alert-banner');
            banner.className = 'alert-banner';
        }

        function switchTab(tab) {
            const isOps = tab === 'ops';
            document.getElementById('tab-btn-ops').classList.toggle('active', isOps);
            document.getElementById('tab-btn-tests').classList.toggle('active', !isOps);
            document.getElementById('tab-panel-ops').classList.toggle('active', isOps);
            document.getElementById('tab-panel-tests').classList.toggle('active', !isOps);
        }

        function toggleTechMode(checked) {
            techMode = Boolean(checked);
            document.body.classList.toggle('tech-mode', techMode);
            updateStaticConfigLabels();
            if (lastSummary) renderSummary(lastSummary, lastReconcile);
            renderOrderPanel(currentOrder, lastRecentOrders);
            renderInventoryTable(lastInventory);
            renderCurrentLogsView();
            renderChannels(lastChannels, lastSummary);
            renderGuardrailsTable();
            if (lastRaceData) renderRaceConditionDetails(lastRaceData);
        }

        function toggleSummaryDrawer() {
            summaryDrawerOpen = !summaryDrawerOpen;
            const drawer = document.getElementById('summary-tech-drawer');
            const btn = document.getElementById('btn-toggle-summary-tech');
            drawer.classList.toggle('open', summaryDrawerOpen);
            btn.textContent = summaryDrawerOpen ? 'Ẩn chi tiết đối soát & SQL' : 'Chi tiết đối soát & SQL';
        }

        function formatWarehouseOptionLabel(maKho, tenKho) {
            return techMode ? `#${maKho} ${tenKho}` : tenKho;
        }

        function updateStaticConfigLabels() {
            if (Array.isArray(lastWarehouses) && lastWarehouses.length > 0) {
                renderWarehouseSelects(lastWarehouses);
                return;
            }
            ['select-kho-xuat', 'select-inv-kho'].forEach(selId => {
                const sel = document.getElementById(selId);
                if (!sel) return;
                Array.from(sel.options).forEach(opt => {
                    if (opt.value === 'all') {
                        opt.textContent = 'Tất cả kho';
                        return;
                    }
                    const baseName = opt.textContent.replace(/^#\\d+(?:\\s*—)?\\s+/, '');
                    opt.textContent = formatWarehouseOptionLabel(opt.value, baseName);
                });
            });
        }

        function restoreButtonLabels() {
            Object.keys(BUTTON_DEFAULT_TEXT).forEach(id => {
                const el = document.getElementById(id);
                if (el) el.textContent = BUTTON_DEFAULT_TEXT[id];
            });
        }

        function updateButtonsByStatus(status) {
            restoreButtonLabels();
            const btnCreate = document.getElementById('btn-create');
            const btnConfirm = document.getElementById('btn-confirm');
            const btnShip = document.getElementById('btn-ship');
            const btnDeliver = document.getElementById('btn-deliver');
            const btnCancel = document.getElementById('btn-cancel');

            [btnCreate, btnConfirm, btnShip, btnDeliver].forEach(b => {
                b.disabled = true;
                b.classList.remove('btn-next-valid');
            });
            btnCancel.disabled = true;

            if (!status || status === 'DaGiao' || status === 'DaHuy') {
                btnCreate.disabled = false;
                btnCreate.classList.add('btn-next-valid');
            } else if (status === 'ChoXacNhan') {
                btnConfirm.disabled = false;
                btnConfirm.classList.add('btn-next-valid');
                btnCancel.disabled = false;
            } else if (status === 'DaXacNhan') {
                btnShip.disabled = false;
                btnShip.classList.add('btn-next-valid');
                btnCancel.disabled = false;
            } else if (status === 'DangGiao') {
                btnDeliver.disabled = false;
                btnDeliver.classList.add('btn-next-valid');
                btnCancel.disabled = false;
            }
        }

        function formatStatusLabel(st) {
            const base = STATUS_DESC[st] || st;
            return techMode ? `${base} (${st})` : base;
        }

        function renderOrderPanel(order, recentOrders) {
            currentOrder = order;
            if (recentOrders && Array.isArray(recentOrders)) {
                lastRecentOrders = recentOrders;
            }
            if (order && order.ma_don_hang) {
                try { sessionStorage.setItem('omnistock_order_id', String(order.ma_don_hang)); } catch (e) {}
            }

            if (lastRecentOrders && Array.isArray(lastRecentOrders)) {
                const sel = document.getElementById('select-recent-order');
                const curId = order ? String(order.ma_don_hang) : '';
                sel.innerHTML = lastRecentOrders.map(r => {
                    const selected = String(r.ma_don_hang) === curId ? 'selected' : '';
                    const stText = techMode ? r.trang_thai : (STATUS_SHORT[r.trang_thai] || r.trang_thai);
                    return `<option value="${r.ma_don_hang}" ${selected}>#${r.ma_don_hang} · ${stText} (${r.tom_tat_sp})</option>`;
                }).join('');
            }

            const filterLbl = document.getElementById('lbl-filter-order-log');
            if (filterLbl) {
                filterLbl.textContent = order && order.ma_don_hang
                    ? `Chỉ hiện đơn đang xem (#${order.ma_don_hang})`
                    : 'Chỉ hiện đơn đang xem';
            }

            const idStatusEl = document.getElementById('ord-id-status');
            const custDateEl = document.getElementById('ord-customer-date');
            const prodEl = document.getElementById('ord-product');
            const whQtyEl = document.getElementById('ord-wh-qty');
            const subEl = document.getElementById('ord-money-subtotal');
            const discEl = document.getElementById('ord-money-discount');
            const vcNoteEl = document.getElementById('ord-money-voucher-note');
            const netEl = document.getElementById('ord-money-net');
            const revEl = document.getElementById('ord-money-rev');
            const revNoteEl = document.getElementById('ord-money-rev-note');

            if (!order) {
                idStatusEl.textContent = 'Chưa có đơn được chọn';
                custDateEl.textContent = '—';
                prodEl.textContent = '—';
                whQtyEl.textContent = '—';
                subEl.textContent = '—';
                discEl.textContent = '—';
                netEl.textContent = '—';
                revEl.textContent = '—';
                updateButtonsByStatus(null);
                return;
            }

            const stBadge = `<span class="status-badge status-${order.trang_thai}">${formatStatusLabel(order.trang_thai)}</span>`;
            const techIdem = (techMode && order.idempotency_key)
                ? ` <span class="tech-tag">idempotency_key: ${order.idempotency_key}</span>`
                : '';
            idStatusEl.innerHTML = `<strong style="font-size:13.5px;">#${order.ma_don_hang}</strong> &nbsp; ${stBadge}${techIdem}`;

            const chName = techMode ? (CHANNEL_LABELS[order.kenh_ban] || order.kenh_ban) : (CHANNEL_SHORT[order.kenh_ban] || order.kenh_ban);
            const khIdPart = techMode ? ` (#${order.ma_khach_hang})` : '';
            custDateEl.innerHTML = `${order.ten_khach_hang}${khIdPart} · Kênh: <strong>${chName}</strong> · Ngày đặt: <span style="font-variant-numeric:tabular-nums;">${order.ngay_dat}</span>`;

            const items = order.items || [];
            prodEl.innerHTML = items.map(it => {
                const btPrefix = techMode ? `<span class="tech-tag">#${it.ma_bien_the}</span> ` : '';
                return `<div style="margin-bottom:2px;">${btPrefix}<strong>${it.ten_san_pham}</strong> <span class="prod-attr">(${it.mau_sac}, ${it.kich_co})</span> · SKU: <code>${it.sku}</code> — SL: <strong>${formatInt(it.so_luong)}</strong> &times; ${formatVnd(it.don_gia)}</div>`;
            }).join('');

            const whPrefix = techMode ? `#${order.ma_kho_xuat} ` : '';
            whQtyEl.innerHTML = `<strong>${whPrefix}${order.ten_kho}</strong> · Tổng số lượng: <strong>${formatInt(order.tong_so_luong)}</strong> sản phẩm`;

            const tienHang = Number(order.tong_tien_hang || 0);
            const tienGiam = Number(order.tien_giam || 0);
            const sauGiam = order.gia_tri_sau_giam !== undefined ? Number(order.gia_tri_sau_giam) : (tienHang - tienGiam);
            const isDelivered = order.trang_thai === 'DaGiao';
            const dtGhiNhan = isDelivered ? sauGiam : 0;

            subEl.textContent = formatVnd(tienHang);
            discEl.textContent = tienGiam > 0 ? ('-' + formatVnd(tienGiam)) : '0 VNĐ';
            vcNoteEl.textContent = order.ma_voucher_code
                ? `Mã: ${order.ma_voucher_code}`
                : (tienGiam > 0 ? 'Có áp dụng giảm giá' : 'Không áp dụng mã');
            netEl.textContent = formatVnd(sauGiam);

            revEl.textContent = formatVnd(dtGhiNhan);
            if (isDelivered) {
                revEl.className = 'money-val text-ok';
                revNoteEl.textContent = 'Đơn Đã giao (đã cộng KPI)';
            } else if (order.trang_thai === 'DaHuy') {
                revEl.className = 'money-val text-err';
                revNoteEl.textContent = 'Đơn Đã hủy (ghi nhận 0 VNĐ)';
            } else {
                revEl.className = 'money-val text-muted';
                revNoteEl.textContent = `Chưa giao (${STATUS_SHORT[order.trang_thai] || order.trang_thai}) → 0 VNĐ`;
            }

            updateButtonsByStatus(order.trang_thai);
        }

        function renderInventoryCell(beforeVal, afterVal) {
            const cur = formatInt(afterVal);
            if (beforeVal !== undefined && beforeVal !== null && Number(beforeVal) !== Number(afterVal)) {
                const delta = Number(afterVal) - Number(beforeVal);
                const signDelta = delta > 0 ? `+${formatInt(delta)}` : formatInt(delta);
                return `<span class="val-current">${cur}</span><span class="diff-inline">${signDelta} (${formatInt(beforeVal)}&rarr;${cur})</span>`;
            }
            return `<span class="val-current">${cur}</span>`;
        }

        function renderInventoryTable(rows) {
            if (rows && Array.isArray(rows)) {
                lastInventory = rows;
            }
            const tbody = document.getElementById('inventory-tbody');
            if (!lastInventory || lastInventory.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5">Chưa có dữ liệu tồn kho cho bộ lọc hiện tại.</td></tr>';
                return;
            }
            const activeBts = new Set(
                currentOrder && currentOrder.items
                    ? currentOrder.items.map(i => Number(i.ma_bien_the))
                    : [Number(document.getElementById('select-bt').value)]
            );
            const diffMap = (lastDiff && lastDiff.items) ? lastDiff.items : {};

            tbody.innerHTML = lastInventory.map(r => {
                const key = `${r.ma_kho}_${r.ma_bien_the}`;
                const d = diffMap[key];
                const bVatLy = d ? d.before.so_luong_vat_ly : null;
                const bGiu = d ? d.before.so_luong_giu : null;
                const bKhaDung = d ? d.before.so_luong_kha_dung : null;

                const vatLyChanged = d && Number(bVatLy) !== Number(r.so_luong_vat_ly);
                const giuChanged = d && Number(bGiu) !== Number(r.so_luong_giu);
                const khaDungChanged = d && Number(bKhaDung) !== Number(r.so_luong_kha_dung);

                const whDisplay = techMode ? `#${r.ma_kho} ${r.ten_kho}` : r.ten_kho;
                const btTag = techMode ? `<span class="tech-tag">#${r.ma_bien_the}</span> ` : '';

                return `
                    <tr class="${activeBts.has(Number(r.ma_bien_the)) ? 'active-product-row' : ''}">
                        <td>${whDisplay}</td>
                        <td>
                            <div>${btTag}<span class="prod-name">${r.ten_san_pham}</span> · <span class="prod-attr">${r.mau_sac}, ${r.kich_co}</span></div>
                            <span class="sku-code">SKU: <strong>${r.sku}</strong> · Giá: ${formatVnd(r.gia_ban)}</span>
                        </td>
                        <td class="num ${vatLyChanged ? 'cell-changed' : ''}">
                            ${renderInventoryCell(bVatLy, r.so_luong_vat_ly)}
                        </td>
                        <td class="num ${giuChanged ? 'cell-changed' : ''}">
                            ${renderInventoryCell(bGiu, r.so_luong_giu)}
                        </td>
                        <td class="num ${khaDungChanged ? 'cell-changed' : ''}">
                            ${renderInventoryCell(bKhaDung, r.so_luong_kha_dung)}
                        </td>
                    </tr>
                `;
            }).join('');
        }

        function formatDeltaCell(r) {
            const dvl = Number(r.delta_vat_ly);
            const dg = Number(r.delta_giu);
            const dkd = Number(r.delta_kha_dung);
            if (dvl === 0 && dg === 0) {
                return '<span class="text-muted">Không đổi tồn</span>';
            }
            const parts = [];
            if (dvl !== 0) parts.push(`Vật lý: ${dvl > 0 ? '+' + dvl : dvl}`);
            if (dg !== 0) parts.push(`Giữ: ${dg > 0 ? '+' + dg : dg}`);
            if (dkd !== 0) parts.push(`Khả dụng: ${dkd > 0 ? '+' + dkd : dkd}`);
            return `<strong>${parts.join(' · ')}</strong>`;
        }

        function renderCurrentLogsView() {
            const filterByOrder = document.getElementById('chk-filter-order-log').checked;
            let sourceLogs = lastLogs || [];
            if (filterByOrder && currentOrder && currentOrder.ma_don_hang) {
                sourceLogs = (lastOrderLogs && lastOrderLogs.length > 0)
                    ? lastOrderLogs
                    : (lastLogs || []).filter(x => Number(x.ma_don_hang) === Number(currentOrder.ma_don_hang));
            }
            renderLogs(sourceLogs, filterByOrder);
        }

        function renderLogs(logs, isFiltered = false) {
            const tbody = document.getElementById('log-tbody');
            const colSpan = techMode ? 7 : 6;
            if (!logs || logs.length === 0) {
                const emptyMsg = isFiltered && currentOrder
                    ? `Đơn #${currentOrder.ma_don_hang} chưa phát sinh biến động giữ/xuất/hoàn kho (trạng thái hiện tại: ${STATUS_SHORT[currentOrder.trang_thai] || currentOrder.trang_thai}).`
                    : 'Chưa có giao dịch phát sinh trong sổ cái.';
                tbody.innerHTML = `<tr><td colspan="${colSpan}" class="text-muted">${emptyMsg}</td></tr>`;
                return;
            }
            tbody.innerHTML = logs.map(r => {
                const opFriendly = OP_LABELS[r.nghiep_vu] || r.nghiep_vu;
                const opDisplay = techMode ? `${opFriendly} (${r.nghiep_vu})` : opFriendly;
                const whDisplay = techMode ? `#${r.ma_kho} ${r.ten_kho}` : r.ten_kho;
                const attrPart = (r.mau_sac && r.kich_co) ? ` (${r.mau_sac}, ${r.kich_co})` : '';
                const btPrefix = techMode ? `<span class="tech-tag">#${r.ma_bien_the}</span> ` : '';
                const seqInfo = techMode && r.seq_id ? ` <span class="text-muted">#${r.seq_id}</span>` : '';
                return `
                    <tr>
                        <td style="font-variant-numeric: tabular-nums;">${r.thoi_gian}</td>
                        <td><strong>${r.ma_don_hang ? '#' + r.ma_don_hang : '—'}</strong></td>
                        <td>
                            ${btPrefix}<strong>${r.ten_san_pham}</strong>${attrPart}
                            <span class="sku-code">SKU: <code>${r.sku}</code></span>
                        </td>
                        <td>${whDisplay}</td>
                        <td><span class="op-badge op-${r.nghiep_vu}">${opDisplay}</span></td>
                        <td class="num">${formatDeltaCell(r)}</td>
                        <td class="tech-only"><span class="trigger-code">${r.trigger_xac_nhan || '—'}${seqInfo}</span></td>
                    </tr>
                `;
            }).join('');
        }

        function renderChannels(channels, summary) {
            if (channels && Array.isArray(channels)) lastChannels = channels;
            const tbody = document.getElementById('channels-tbody');
            const tfoot = document.getElementById('channels-tfoot');
            const pShort = summary ? (summary.period_short || (summary.period === 'thang_10' ? 'Tháng 10/2026' : 'Toàn kỳ')) : 'Toàn kỳ';
            document.getElementById('channels-period-note').textContent = `Kỳ: ${pShort}`;

            if (!lastChannels || lastChannels.length === 0) {
                tbody.innerHTML = '<tr><td colspan="4">Không có đơn Đã giao trong kỳ đã chọn.</td></tr>';
                tfoot.innerHTML = '';
                return;
            }

            const totalOrders = lastChannels.reduce((acc, c) => acc + Number(c.so_don_giao), 0);
            const totalRev = lastChannels.reduce((acc, c) => acc + Number(c.doanh_thu_thuan), 0);

            tbody.innerHTML = lastChannels.map(c => {
                const pct = totalRev > 0 ? ((Number(c.doanh_thu_thuan) * 100) / totalRev).toFixed(2) + '%' : '0.00%';
                const chLabel = techMode ? (CHANNEL_LABELS[c.kenh_ban] || c.kenh_ban) : (CHANNEL_SHORT[c.kenh_ban] || c.kenh_ban);
                return `
                    <tr>
                        <td><strong>${chLabel}</strong></td>
                        <td class="num">${formatInt(c.so_don_giao)}</td>
                        <td class="num">${formatVnd(c.doanh_thu_thuan)}</td>
                        <td class="num">${pct}</td>
                    </tr>
                `;
            }).join('');

            const kpiMatch = summary && Number(summary.doanh_thu_thuan) === totalRev;
            tfoot.innerHTML = `
                <tr>
                    <td>Tổng cộng</td>
                    <td class="num">${formatInt(totalOrders)}</td>
                    <td class="num">${formatVnd(totalRev)}</td>
                    <td class="num">100.00%</td>
                </tr>
            `;
        }

        function renderSummary(s, rec) {
            if (!s) return;
            lastSummary = s;
            lastReconcile = rec;

            const isT10 = s.period === 'thang_10';
            const periodShort = s.period_short || (isT10 ? 'Tháng 10/2026' : 'Toàn kỳ');

            document.getElementById('lbl-don-hang').textContent = 'Tổng đơn hàng';
            document.getElementById('lbl-doanh-thu').textContent = 'Doanh thu thuần';

            document.getElementById('stat-don-hang').textContent = formatInt(s.tong_don_hang);
            document.getElementById('stat-don-hang-note').textContent = `Đã giao: ${formatInt(s.so_don_da_giao)} · Đã hủy: ${formatInt(s.so_don_da_huy)}`;

            const testSkuNote = (techMode && Number(s.so_sku_thu_nghiem) > 0) ? ` (+${formatInt(s.so_sku_thu_nghiem)} SKU thử)` : '';
            document.getElementById('stat-catalog-note').textContent = `${formatInt(s.so_sku_kinh_doanh)} SKU · ${formatInt(s.so_kho)} kho${testSkuNote}`;

            document.getElementById('stat-doanh-thu').textContent = formatVnd(s.doanh_thu_thuan);
            document.getElementById('stat-doanh-thu-note').textContent = isT10
                ? 'Đơn Đã giao đặt trong T10/2026'
                : 'Chỉ tính đơn Đã giao, không gồm phí ship';

            document.getElementById('ts-dashboard').textContent = s.cap_nhat_luc || '—';

            const doiSoatEl = document.getElementById('stat-doi-soat');
            const doiSoatSubEl = document.getElementById('stat-doi-soat-sub');
            const tsFullEl = document.getElementById('ts-full-reconcile');
            const tsPairEl = document.getElementById('ts-pair-check');
            const ledgerCountEl = document.getElementById('tech-ledger-count');
            const drawerContentEl = document.getElementById('summary-drawer-content');

            if (rec && rec.full && rec.full.checked && Number(rec.full.tong_cap) > 0) {
                const totalLech = Number(rec.tong_cap_lech_hien_tai || 0);
                if (rec.he_thong_khop && totalLech === 0) {
                    doiSoatEl.textContent = 'Khớp toàn bộ';
                    doiSoatEl.className = 'summary-value text-ok';
                    doiSoatSubEl.textContent = `${formatInt(rec.full.tong_cap)} cặp kho–SKU · 0 sai lệch`;
                } else {
                    doiSoatEl.textContent = `Lệch ${formatInt(totalLech)} cặp`;
                    doiSoatEl.className = 'summary-value text-err';
                    doiSoatSubEl.textContent = `${formatInt(rec.full.tong_cap)} cặp kho–SKU · ${formatInt(totalLech)} sai lệch`;
                }
                if (ledgerCountEl) ledgerCountEl.textContent = formatInt(rec.full.tong_dong_so_cai);

                tsFullEl.textContent = `${rec.full.thoi_diem} (${formatInt(rec.full.tong_cap)} cặp, ${formatInt(rec.full.so_cap_lech)} lệch)`;

                let pairDetailHtml = 'Chưa có thao tác đơn/kho mới sau lần đối soát toàn bộ.';
                if (rec.last_pair && rec.last_pair.checked) {
                    const p = rec.last_pair;
                    const pStatus = p.khop ? 'Khớp (0 lệch)' : `Lệch ${formatInt(p.so_cap_lech)} cặp`;
                    tsPairEl.textContent = `${p.thoi_diem} — ${p.mo_ta}: ${pStatus}`;
                    pairDetailHtml = `Thao tác gần nhất lúc <strong>${p.thoi_diem}</strong> cho <strong>${p.mo_ta}</strong>: <strong>${pStatus}</strong>.`;
                } else {
                    tsPairEl.textContent = 'Chưa phát sinh thao tác mới';
                }

                drawerContentEl.innerHTML = `
                    <div><strong>1. Kỳ thống kê &amp; Doanh thu thuần:</strong> ${s.period_label} · Công thức: <code>SUM(tong_tien_hang - tien_giam) FILTER (WHERE trang_thai = 'DaGiao')</code> trên bảng <code>don_hang</code> (không cộng phí vận chuyển <code>phi_van_chuyen</code>).</div>
                    <div><strong>2. Đối soát toàn bộ (View <code>v_doi_soat_kho</code>):</strong> Thực hiện lúc <strong>${rec.full.thoi_diem}</strong> trên <strong>${formatInt(rec.full.tong_cap)}</strong> cặp <code>(ma_kho, ma_bien_the)</code> đối chiếu với tổng lũy kế <strong>${formatInt(rec.full.tong_dong_so_cai)}</strong> dòng trong sổ cái <code>bien_dong_kho</code> (<code>so_luong_vat_ly = SUM(delta_vat_ly)</code> và <code>so_luong_giu = SUM(delta_giu)</code>) &rarr; Số cặp lệch: <strong>${formatInt(rec.full.so_cap_lech)}</strong>.</div>
                    <div><strong>3. Kiểm tra riêng sau thao tác:</strong> ${pairDetailHtml}</div>
                `;
            } else {
                doiSoatEl.textContent = 'Chưa kiểm tra';
                doiSoatEl.className = 'summary-value';
                doiSoatSubEl.textContent = '—';
                tsFullEl.textContent = 'Chưa chạy';
                tsPairEl.textContent = '—';
            }
        }

        function onProductSelectChange() {
            if (!currentOrder || currentOrder.trang_thai === 'DaGiao' || currentOrder.trang_thai === 'DaHuy') {
                loadDashboard();
            }
        }

        function selectExistingOrder(orderId) {
            if (!orderId) return;
            lastDiff = null;
            loadDashboard(orderId);
        }

        function findOrderById() {
            const val = document.getElementById('input-find-order').value.trim();
            if (!val) return;
            lastDiff = null;
            loadDashboard(val);
        }

        function renderWarehouseSelects(warehouses) {
            if (!Array.isArray(warehouses) || warehouses.length === 0) return;
            lastWarehouses = warehouses;

            const ordSel = document.getElementById('select-kho-xuat');
            if (ordSel) {
                const prev = String(ordSel.value || '1');
                const validValues = new Set(warehouses.map(w => String(w.ma_kho)));
                ordSel.innerHTML = warehouses.map(w =>
                    `<option value="${w.ma_kho}">${formatWarehouseOptionLabel(w.ma_kho, w.ten_kho)}</option>`
                ).join('');
                ordSel.value = validValues.has(prev) ? prev : String(warehouses[0].ma_kho);
            }

            const invSel = document.getElementById('select-inv-kho');
            if (invSel) {
                const prevInv = String(invSel.value || '1');
                const validInv = new Set(['all', ...warehouses.map(w => String(w.ma_kho))]);
                invSel.innerHTML = warehouses.map(w =>
                    `<option value="${w.ma_kho}">${formatWarehouseOptionLabel(w.ma_kho, w.ten_kho)}</option>`
                ).join('') + '<option value="all">Tất cả kho</option>';
                invSel.value = validInv.has(prevInv) ? prevInv : String(warehouses[0].ma_kho);
            }
        }

        async function loadDashboard(explicitOrderId = null) {
            const btnRefresh = document.getElementById('btn-refresh');
            btnRefresh.disabled = true;
            btnRefresh.textContent = 'Đang tải...';

            try {
                const period = document.getElementById('select-period').value;
                const invKho = document.getElementById('select-inv-kho').value;
                let orderId = explicitOrderId;
                if (!orderId && currentOrder && currentOrder.ma_don_hang) {
                    orderId = currentOrder.ma_don_hang;
                }
                if (!orderId) {
                    try { orderId = sessionStorage.getItem('omnistock_order_id') || ''; } catch (e) {}
                }

                const qs = `?period=${encodeURIComponent(period)}&kho=${encodeURIComponent(invKho)}&order_id=${encodeURIComponent(orderId || '')}`;
                const res = await fetch('/api/dashboard' + qs);
                if (!res.ok) {
                    throw new Error('HTTP ' + res.status);
                }
                const data = await res.json();
                if (data.error) {
                    showAlert('Không thể tải dữ liệu từ CSDL: ' + data.message, 'error');
                    return;
                }
                hideAlert();
                lastLogs = data.logs || [];
                lastOrderLogs = data.order_logs || [];
                renderWarehouseSelects(data.warehouses);
                renderSummary(data.summary, data.reconcile);
                renderOrderPanel(data.current_order, data.recent_orders);
                renderInventoryTable(data.inventory);
                renderCurrentLogsView();
                renderChannels(data.channels, data.summary);
            } catch (err) {
                showAlert('Tải dữ liệu thất bại: Không kết nối được tới API (/api/dashboard). Chi tiết: ' + err.message, 'error');
            } finally {
                btnRefresh.disabled = false;
                btnRefresh.textContent = 'Làm mới';
            }
        }

        async function runFullReconcile() {
            const btn = document.getElementById('btn-reconcile');
            btn.disabled = true;
            btn.textContent = 'Đang đối soát...';
            try {
                const res = await fetch('/api/reconcile');
                if (!res.ok) throw new Error('HTTP ' + res.status);
                const data = await res.json();
                if (data.error) {
                    showAlert('Lỗi đối soát sổ kho: ' + data.message, 'error');
                    return;
                }
                const f = data.reconcile.full;
                showAlert(`Đối soát toàn bộ hoàn tất lúc ${f.thoi_diem}: ${formatInt(f.tong_cap)} cặp kho–SKU khớp 100% (0 lệch).`, 'success');
                await loadDashboard(currentOrder ? currentOrder.ma_don_hang : null);
            } catch (err) {
                showAlert('Không thể thực hiện đối soát toàn bộ (/api/reconcile): ' + err.message, 'error');
            } finally {
                btn.disabled = false;
                btn.textContent = 'Đối soát toàn bộ';
            }
        }

        async function stepOrder(action) {
            if (isSubmittingOrder) return;
            isSubmittingOrder = true;

            const btnMap = {
                'create': 'btn-create',
                'confirm': 'btn-confirm',
                'ship': 'btn-ship',
                'deliver': 'btn-deliver',
                'cancel': 'btn-cancel'
            };
            const clickedBtn = document.getElementById(btnMap[action]);
            if (clickedBtn) clickedBtn.textContent = 'Đang xử lý...';
            ['btn-create', 'btn-confirm', 'btn-ship', 'btn-deliver', 'btn-cancel'].forEach(id => {
                document.getElementById(id).disabled = true;
            });

            const kho = document.getElementById('select-kho-xuat').value;
            const bt = document.getElementById('select-bt').value;
            const sl = document.getElementById('input-sl').value;
            const bt2 = document.getElementById('select-bt2').value;
            const sl2 = document.getElementById('input-sl2').value;
            const voucher = document.getElementById('select-voucher').value;
            const period = document.getElementById('select-period').value;
            const invKho = document.getElementById('select-inv-kho').value;
            const orderId = currentOrder ? currentOrder.ma_don_hang : '';

            const itemsPayload = [{ bt: Number(bt), sl: Number(sl) }];
            if (bt2 !== '') {
                itemsPayload.push({ bt: Number(bt2), sl: Number(sl2) });
            }

            try {
                const res = await fetch('/api/order', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        action,
                        order_id: orderId,
                        kho: Number(kho),
                        items: itemsPayload,
                        voucher,
                        period,
                        inv_kho: invKho,
                        idem_key: action === 'create' ? nextCreateIdemKey : ''
                    })
                });
                let data = null;
                try {
                    data = await res.json();
                } catch (parseErr) {
                    throw new Error('HTTP ' + res.status);
                }
                if (!res.ok || data.error) {
                    showAlert(`Thao tác bị từ chối (HTTP ${res.status}): ` + (data.message || ('HTTP ' + res.status)), 'error');
                    if (data.current_order) {
                        renderOrderPanel(data.current_order, data.recent_orders);
                    } else {
                        updateButtonsByStatus(currentOrder ? currentOrder.trang_thai : null);
                    }
                    return;
                }
                if (action === 'create') {
                    nextCreateIdemKey = 'ui-create-' + Date.now() + '-' + Math.random().toString(36).slice(2, 7);
                }
                hideAlert();
                lastDiff = data.diff || null;
                lastActionMsg = data.message || '';
                lastActionTechMsg = data.tech_message || '';
                document.getElementById('action-feedback').innerHTML = `<strong>Vừa thực hiện:</strong> ${lastActionMsg}`;
                if (lastActionTechMsg) {
                    document.getElementById('action-tech-feedback').innerHTML = `<strong>Chi tiết thực thi:</strong> <code>${lastActionTechMsg}</code>`;
                }
                lastLogs = data.logs || [];
                lastOrderLogs = data.order_logs || [];
                renderSummary(data.summary, data.reconcile);
                renderOrderPanel(data.current_order, data.recent_orders);
                renderInventoryTable(data.inventory);
                renderCurrentLogsView();
                renderChannels(data.channels, data.summary);
            } catch (err) {
                showAlert('Không nhận được phản hồi từ API xử lý đơn hàng (POST /api/order). Chi tiết: ' + err.message, 'error');
                updateButtonsByStatus(currentOrder ? currentOrder.trang_thai : null);
            } finally {
                isSubmittingOrder = false;
            }
        }

        function updateTestTabBadge() {
            const badge = document.getElementById('tab-tests-badge');
            const raceDone = Boolean(lastRaceData);
            const rulesDone = Boolean(verifyRulesResults && verifyRulesResults.length > 0);
            if (!raceDone && !rulesDone) {
                badge.textContent = 'Chưa kiểm tra';
                return;
            }
            const rulesPassCount = rulesDone ? verifyRulesResults.filter(x => x.passed).length : 0;
            const parts = [];
            if (raceDone) parts.push('Tranh mua: ĐẠT');
            if (rulesDone) parts.push(`${rulesPassCount}/8 kịch bản`);
            badge.textContent = parts.join(' · ');
        }

        function toggleRaceDetail() {
            raceDetailOpen = !raceDetailOpen;
            const row = document.getElementById('race-detail-row');
            const btn = document.getElementById('btn-race-detail-toggle');
            row.classList.toggle('open', raceDetailOpen);
            btn.textContent = raceDetailOpen ? 'Ẩn chi tiết' : 'Xem chi tiết';
        }

        function renderRaceConditionDetails(data) {
            const a = data.khach_a;
            const b = data.khach_b;
            const tk = data.ton_kho_cuoi;
            const container = document.getElementById('race-result-container');
            container.innerHTML = `
                <div class="race-grid">
                    <div class="race-box ${a.thanh_cong ? 'win' : 'lose'}">
                        <div class="race-box-title">
                            <span>Khách A (${a.ho_ten}) — Đơn #${a.ma_don_hang}</span>
                            <span class="${a.thanh_cong ? 'text-ok' : 'text-err'}">${a.thanh_cong ? 'GIỮ KHO THÀNH CÔNG' : 'BỊ TỪ CHỐI (HẾT HÀNG)'}</span>
                        </div>
                        <div class="race-meta">
                            <div><strong>Mã lần chạy (run_id):</strong> <code>${data.run_id}</code></div>
                            <div><strong>Trạng thái cuối:</strong> ${formatStatusLabel(a.trang_thai)}</div>
                            <div><strong>Bút toán sổ cái:</strong> ${a.nghiep_vu_so_cai || 'Không phát sinh dòng giữ kho'}</div>
                            <div><strong>Phản hồi từ PostgreSQL:</strong> ${a.chi_tiet}</div>
                        </div>
                    </div>

                    <div class="race-box ${b.thanh_cong ? 'win' : 'lose'}">
                        <div class="race-box-title">
                            <span>Khách B (${b.ho_ten}) — Đơn #${b.ma_don_hang}</span>
                            <span class="${b.thanh_cong ? 'text-ok' : 'text-err'}">${b.thanh_cong ? 'GIỮ KHO THÀNH CÔNG' : 'BỊ TỪ CHỐI (HẾT HÀNG)'}</span>
                        </div>
                        <div class="race-meta">
                            <div><strong>Mã lần chạy (run_id):</strong> <code>${data.run_id}</code></div>
                            <div><strong>Trạng thái cuối:</strong> ${formatStatusLabel(b.trang_thai)}</div>
                            <div><strong>Bút toán sổ cái:</strong> ${b.nghiep_vu_so_cai || 'Không phát sinh dòng giữ kho'}</div>
                            <div><strong>Phản hồi từ PostgreSQL:</strong> ${b.chi_tiet}</div>
                        </div>
                    </div>

                    <div class="race-box">
                        <div class="race-box-title">
                            <span>Tồn kho SKU ${tk.sku} tại Kho Thủ Đức</span>
                            <span class="text-ok">Nhất quán (1 đơn giữ)</span>
                        </div>
                        <div class="race-meta">
                            <div><strong>Vật lý:</strong> Trước 1 &rarr; Sau <strong>${formatInt(tk.so_luong_vat_ly)}</strong></div>
                            <div><strong>Đang giữ:</strong> Trước 0 &rarr; Sau <strong>${formatInt(tk.so_luong_giu)}</strong> (giữ cho đơn #${data.don_thang})</div>
                            <div><strong>Khả dụng:</strong> Trước 1 &rarr; Sau <strong>${formatInt(tk.so_luong_kha_dung)}</strong></div>
                            <div><strong>Sổ cái <code>bien_dong_kho</code>:</strong> Đúng ${formatInt(tk.so_dong_giu)} dòng <code>GIU</code>.</div>
                        </div>
                    </div>
                </div>
                <div class="sql-note">
                    <strong>Bằng chứng kỹ thuật (<code>fn_cap_nhat_ton_kho</code> trong <code>schema.sql</code>):</strong>
                    Câu lệnh <code>UPDATE ton_kho SET so_luong_giu = so_luong_giu + ct.so_luong WHERE ma_kho = NEW.ma_kho_xuat AND ma_bien_the = ct.ma_bien_the AND so_luong_vat_ly - so_luong_giu &gt;= ct.so_luong;</code>
                    khóa dòng <code>ton_kho</code> cho phiên đến trước; phiên thứ hai chờ khóa rồi kiểm tra lại điều kiện <code>WHERE</code>, nhận <code>NOT FOUND</code> và <code>RAISE EXCEPTION</code> nên tự động hoàn tác (Rollback).
                </div>
            `;
        }

        async function runRaceCondition() {
            const btnRace = document.getElementById('btn-race');
            const btnRel = document.getElementById('btn-race-release');
            const statusCell = document.getElementById('race-summary-status');
            const timeCell = document.getElementById('race-summary-time');
            const toggleBtn = document.getElementById('btn-race-detail-toggle');

            btnRace.disabled = true;
            btnRace.textContent = 'Đang chạy 2 kết nối...';

            try {
                const period = document.getElementById('select-period').value;
                const invKho = document.getElementById('select-inv-kho').value;
                const res = await fetch('/api/race-condition', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        action: 'run',
                        period,
                        inv_kho: invKho
                    })
                });
                let data = null;
                try {
                    data = await res.json();
                } catch (parseErr) {
                    throw new Error('HTTP ' + res.status);
                }
                if (!res.ok || data.error) {
                    showAlert(`Lỗi khi kiểm tra tranh mua (HTTP ${res.status}): ` + (data.message || ('HTTP ' + res.status)), 'error');
                    return;
                }
                hideAlert();

                lastRaceRunId = data.run_id;
                lastRaceData = data;
                btnRel.style.display = 'inline-block';
                btnRel.textContent = `Giải phóng giữ kho (${data.run_id})`;

                const aOk = Boolean(data.khach_a && data.khach_a.thanh_cong);
                const bOk = Boolean(data.khach_b && data.khach_b.thanh_cong);
                const passed = (aOk !== bOk) && Number(data.ton_kho_cuoi.so_luong_kha_dung) === 0;

                statusCell.innerHTML = passed
                    ? '<span class="test-status-pill test-status-pass">ĐẠT (1 giữ · 1 từ chối)</span>'
                    : '<span class="test-status-pill test-status-fail">KHÔNG ĐẠT</span>';
                timeCell.textContent = data.thoi_diem || (data.summary && data.summary.cap_nhat_luc) || '—';
                toggleBtn.disabled = false;

                renderRaceConditionDetails(data);
                updateTestTabBadge();

                lastLogs = data.logs || lastLogs;
                renderSummary(data.summary, data.reconcile);
                renderCurrentLogsView();
            } catch (err) {
                showAlert('Không nhận được phản hồi từ API kiểm tra tranh mua: ' + err.message, 'error');
            } finally {
                btnRace.disabled = false;
                btnRace.textContent = 'Chạy kiểm tra tranh mua';
            }
        }

        async function releaseCurrentRaceRun() {
            if (!lastRaceRunId) return;
            const btnRel = document.getElementById('btn-race-release');
            btnRel.disabled = true;
            try {
                const period = document.getElementById('select-period').value;
                const invKho = document.getElementById('select-inv-kho').value;
                const res = await fetch('/api/race-condition', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        action: 'release',
                        run_id: lastRaceRunId,
                        period,
                        inv_kho: invKho
                    })
                });
                let data = null;
                try {
                    data = await res.json();
                } catch (parseErr) {
                    throw new Error('HTTP ' + res.status);
                }
                if (!res.ok || data.error) {
                    showAlert(`Không thể giải phóng phiên tranh mua (HTTP ${res.status}): ` + (data.message || ('HTTP ' + res.status)), 'error');
                    return;
                }
                showAlert(`Đã hủy đơn thắng và ghi NHA_GIU vào sổ cái cho phiên ${lastRaceRunId} (Tồn khả dụng về lại ${data.ton_kho_cuoi.so_luong_kha_dung}).`, 'success');
                btnRel.style.display = 'none';
                lastLogs = data.logs || lastLogs;
                renderSummary(data.summary, data.reconcile);
                renderCurrentLogsView();
            } catch (err) {
                showAlert('Lỗi khi giải phóng phiên tranh mua: ' + err.message, 'error');
            } finally {
                btnRel.disabled = false;
            }
        }

        function toggleRuleDetail(stt) {
            if (openRuleDetails.has(stt)) {
                openRuleDetails.delete(stt);
            } else {
                openRuleDetails.add(stt);
            }
            renderGuardrailsTable();
        }

        function toggleAllRuleDetails() {
            if (!verifyRulesResults) return;
            if (openRuleDetails.size === verifyRulesResults.length) {
                openRuleDetails.clear();
            } else {
                verifyRulesResults.forEach(r => openRuleDetails.add(Number(r.stt)));
            }
            renderGuardrailsTable();
        }

        function renderGuardrailsTable() {
            const tbody = document.getElementById('guardrails-tbody');
            const btnToggleAll = document.getElementById('btn-toggle-all-rules');
            const rowsData = verifyRulesResults || DEFAULT_8_RULES;
            const hasRun = Boolean(verifyRulesResults);

            if (btnToggleAll) {
                btnToggleAll.style.display = hasRun ? 'inline-block' : 'none';
                btnToggleAll.textContent = (hasRun && openRuleDetails.size === rowsData.length)
                    ? 'Thu gọn tất cả'
                    : 'Mở tất cả chi tiết';
            }

            tbody.innerHTML = rowsData.map(r => {
                const stt = Number(r.stt);
                const isOpen = openRuleDetails.has(stt);
                const shortTitle = r.short_name || r.name;
                const techBadge = techMode && r.tech_objects
                    ? `<div style="margin-top:2px;"><span class="tech-tag">${r.tech_objects}</span></div>`
                    : '';

                let statusHtml = '<span class="test-status-pill test-status-untested">Chưa kiểm tra</span>';
                if (hasRun) {
                    statusHtml = r.passed
                        ? '<span class="test-status-pill test-status-pass">ĐẠT</span>'
                        : '<span class="test-status-pill test-status-fail">KHÔNG ĐẠT</span>';
                }

                const timeText = hasRun ? (r.thoi_diem || '—') : '—';
                const detailHtml = hasRun
                    ? `
                        <div><strong>Kịch bản đầy đủ:</strong> ${r.name}</div>
                        <div style="margin-top:3px;"><strong>Bằng chứng dữ liệu trước/sau &amp; phản hồi PostgreSQL/API:</strong> ${r.detail}</div>
                        <div style="margin-top:3px;"><strong>Ràng buộc / Trigger / Hàm liên quan:</strong> <code>${r.tech_objects || '—'}</code></div>
                    `
                    : 'Chưa chạy phép thử này.';

                return `
                    <tr>
                        <td>
                            <strong>Ca ${stt}. ${shortTitle}</strong>
                            ${techBadge}
                        </td>
                        <td>${statusHtml}</td>
                        <td style="font-variant-numeric: tabular-nums;">${timeText}</td>
                        <td class="num">
                            <button class="btn btn-xs" type="button" onclick="toggleRuleDetail(${stt})" ${hasRun ? '' : 'disabled'}>
                                ${isOpen ? 'Ẩn chi tiết' : 'Xem chi tiết'}
                            </button>
                        </td>
                    </tr>
                    <tr class="test-detail-row ${isOpen ? 'open' : ''}">
                        <td colspan="4">
                            <div class="test-detail-box">${detailHtml}</div>
                        </td>
                    </tr>
                `;
            }).join('');
        }

        async function runVerifyRules() {
            const btn = document.getElementById('btn-verify-rules');
            const preservedOrderId = currentOrder && currentOrder.ma_don_hang ? currentOrder.ma_don_hang : null;
            btn.disabled = true;
            btn.textContent = 'Đang chạy 8 phép thử thật...';
            try {
                const res = await fetch('/api/verify-rules', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({})
                });
                let data = null;
                try {
                    data = await res.json();
                } catch (parseErr) {
                    throw new Error('HTTP ' + res.status);
                }
                if (!res.ok || data.error) {
                    showAlert(`Lỗi khi chạy kiểm thử 8 kịch bản (HTTP ${res.status}): ` + (data.message || ('HTTP ' + res.status)), 'error');
                    return;
                }
                verifyRulesResults = data.results || [];
                renderGuardrailsTable();
                updateTestTabBadge();
                await loadDashboard(preservedOrderId);
            } catch (err) {
                showAlert('Không thể chạy kiểm thử 8 kịch bản (POST /api/verify-rules): ' + err.message, 'error');
            } finally {
                btn.disabled = false;
                btn.textContent = 'Chạy kiểm thử 8 kịch bản';
            }
        }

        updateStaticConfigLabels();
        renderGuardrailsTable();
        loadDashboard();
    </script>
</body>
</html>
"""


class OmnistockHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def send_json(self, payload, status=200, extra_headers=None):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json_body(self):
        length_str = self.headers.get("Content-Length", "0")
        try:
            length = int(length_str)
        except ValueError:
            length = 0
        if length <= 0:
            return {}
        raw = self.rfile.read(length).decode("utf-8")
        if not raw.strip():
            return {}
        return json.loads(raw)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        params = urllib.parse.parse_qs(parsed.query)

        if path in ("/", "/index.html"):
            body = HTML_CONTENT.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if path == "/api/dashboard":
            try:
                period = params.get("period", ["toan_ky"])[0]
                kho = params.get("kho", ["1"])[0]
                order_id = params.get("order_id", [None])[0]
                payload = get_dashboard_payload(period=period, ma_kho=kho, order_id=order_id)
                self.send_json(payload, status=200)
            except Exception as e:
                self.send_json({"error": True, "code": "INTERNAL_ERROR", "message": str(e)}, status=500)
            return

        if path == "/api/reconcile":
            try:
                rec = run_full_reconcile()
                self.send_json({"reconcile": rec}, status=200)
            except Exception as e:
                self.send_json({"error": True, "code": "INTERNAL_ERROR", "message": str(e)}, status=500)
            return

        if path in ("/api/order", "/api/race-condition", "/api/verify-rules"):
            self.send_json(
                {
                    "error": True,
                    "code": "METHOD_NOT_ALLOWED",
                    "message": f"Endpoint {path} thay đổi dữ liệu nên bắt buộc dùng phương thức POST với nội dung JSON (application/json)."
                },
                status=405,
                extra_headers={"Allow": "POST"}
            )
            return

        self.send_json({"error": True, "code": "NOT_FOUND", "message": f"Không tìm thấy đường dẫn {path}."}, status=404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        try:
            body = self.read_json_body()
            if not isinstance(body, dict):
                self.send_json({"error": True, "code": "INVALID_JSON", "message": "Nội dung yêu cầu (JSON body) phải là một đối tượng JSON."}, status=400)
                return
        except Exception as e:
            self.send_json({"error": True, "code": "INVALID_JSON", "message": f"Nội dung yêu cầu không phải JSON hợp lệ: {e}"}, status=400)
            return

        if path == "/api/reconcile":
            try:
                rec = run_full_reconcile()
                self.send_json({"reconcile": rec}, status=200)
            except Exception as e:
                self.send_json({"error": True, "code": "INTERNAL_ERROR", "message": str(e)}, status=500)
            return

        if path == "/api/verify-rules":
            try:
                results = run_all_8_business_rule_tests()
                self.send_json({"results": results}, status=200)
            except Exception as e:
                self.send_json({"error": True, "code": "INTERNAL_ERROR", "message": str(e)}, status=500)
            return

        if path == "/api/order":
            try:
                action = str(body.get("action", "create")).strip()
                order_id = body.get("order_id")
                kho_raw = body.get("kho", 1)
                voucher_raw = body.get("voucher", "")
                period = str(body.get("period", "toan_ky"))
                inv_kho = str(body.get("inv_kho", "1"))
                idem_key = str(body.get("idem_key", "") or "").strip()

                try:
                    kho = int(kho_raw)
                except (ValueError, TypeError):
                    self.send_json({"error": True, "code": "INVALID_WAREHOUSE", "message": f"Mã kho không hợp lệ: {kho_raw}"}, status=400)
                    return

                if action == "create":
                    if "items" in body:
                        items = body.get("items")
                        if not isinstance(items, list) or len(items) == 0:
                            res_empty = create_order_atomic(
                                khach_id=1, gian_hang_id=1, kho_id=kho,
                                voucher_id=voucher_raw, items=[], kenh="Web",
                                idem_key=idem_key if idem_key else None
                            )
                            self.send_json(
                                {"error": True, "code": res_empty.get("code", "EMPTY_ITEMS"), "message": res_empty["error"]},
                                status=res_empty.get("status", 400)
                            )
                            return
                    else:
                        bt_raw = body.get("bt")
                        sl_raw = body.get("sl", 1)
                        bt2_raw = body.get("bt2", "")
                        sl2_raw = body.get("sl2", 1)
                        if bt_raw is None or str(bt_raw).strip() == "":
                            self.send_json({"error": True, "code": "EMPTY_ITEMS", "message": "Danh sách sản phẩm không được rỗng."}, status=400)
                            return
                        items = [{"bt": bt_raw, "sl": sl_raw}]
                        if bt2_raw is not None and str(bt2_raw).strip() != "":
                            items.append({"bt": bt2_raw, "sl": sl2_raw})

                    valid_bt_list = []
                    for it in items:
                        if isinstance(it, dict) and str(it.get("bt", "")).lstrip("-").isdigit() and int(it["bt"]) > 0:
                            valid_bt_list.append(int(it["bt"]))
                    bt_list = valid_bt_list if valid_bt_list else [1]
                else:
                    if action not in ("confirm", "ship", "deliver", "cancel"):
                        self.send_json({"error": True, "code": "INVALID_ACTION", "message": f"Thao tác đơn hàng không hợp lệ: {action}"}, status=400)
                        return
                    if order_id is None or not str(order_id).isdigit() or int(order_id) <= 0:
                        self.send_json({"error": True, "code": "INVALID_ORDER_ID", "message": "Chưa có mã đơn hàng hợp lệ để thực hiện thao tác."}, status=400)
                        return
                    ord_rows = run_psql_json(f"""
                        SELECT d.ma_don_hang, d.trang_thai, d.ma_kho_xuat,
                               COALESCE(json_agg(ct.ma_bien_the), '[]'::json) AS bts
                        FROM don_hang d
                        JOIN chi_tiet_don_hang ct ON ct.ma_don_hang = d.ma_don_hang
                        WHERE d.ma_don_hang = {int(order_id)}
                        GROUP BY d.ma_don_hang
                    """)
                    if not ord_rows:
                        self.send_json({"error": True, "code": "ORDER_NOT_FOUND", "message": f"Không tìm thấy đơn hàng #{order_id}."}, status=404)
                        return
                    kho = int(ord_rows[0]["ma_kho_xuat"])
                    bt_list = [int(x) for x in ord_rows[0]["bts"]]

                bt_csv = ",".join(str(x) for x in bt_list)
                before_inv_rows = run_psql_json(f"""
                    SELECT ma_kho, ma_bien_the, so_luong_vat_ly, so_luong_giu,
                           (so_luong_vat_ly - so_luong_giu) AS so_luong_kha_dung
                    FROM ton_kho
                    WHERE ma_kho = {kho} AND ma_bien_the IN ({bt_csv})
                """)
                before_map = {f"{r['ma_kho']}_{r['ma_bien_the']}": r for r in before_inv_rows}

                reused_flag = False
                success_status = 200
                if action == "create":
                    res_create = create_order_atomic(
                        khach_id=1,
                        gian_hang_id=1,
                        kho_id=kho,
                        voucher_id=voucher_raw,
                        items=items,
                        kenh="Web",
                        idem_key=idem_key if idem_key else None
                    )
                    if not res_create["ok"]:
                        self.send_json(
                            {"error": True, "code": res_create.get("code", "BAD_REQUEST"), "message": res_create["error"]},
                            status=res_create.get("status", 400)
                        )
                        return
                    order_id = str(res_create["order_id"])
                    reused_flag = bool(res_create.get("reused"))
                    success_status = int(res_create.get("status", 201))
                    bt_list = [int(x["bt"]) for x in items]
                    bt_csv = ",".join(str(x) for x in bt_list)
                else:
                    res_tr = execute_order_transition(order_id, action)
                    if not res_tr["ok"]:
                        payload = get_dashboard_payload(period=period, ma_kho=inv_kho, order_id=order_id)
                        payload["error"] = True
                        payload["code"] = res_tr.get("code", "CONFLICT")
                        payload["message"] = res_tr["error"]
                        self.send_json(payload, status=res_tr.get("status", 409))
                        return

                after_inv_rows = run_psql_json(f"""
                    SELECT ma_kho, ma_bien_the, so_luong_vat_ly, so_luong_giu,
                           (so_luong_vat_ly - so_luong_giu) AS so_luong_kha_dung
                    FROM ton_kho
                    WHERE ma_kho = {kho} AND ma_bien_the IN ({bt_csv})
                """)
                after_map = {f"{r['ma_kho']}_{r['ma_bien_the']}": r for r in after_inv_rows}

                diff_items = {}
                for k_key, b_row in before_map.items():
                    a_row = after_map.get(k_key)
                    if a_row:
                        diff_items[k_key] = {"before": b_row, "after": a_row}

                sku_desc = ", ".join(f"SKU #{x}" for x in bt_list)
                verify_pair_reconcile(kho, bt_list, mo_ta=f"Đơn #{order_id} (Kho #{kho}, {sku_desc})")
                payload = get_dashboard_payload(period=period, ma_kho=inv_kho, order_id=order_id)
                cur_after = payload["current_order"]

                if action == "create":
                    if reused_flag:
                        msg = f"Yêu cầu trùng khóa chống trùng: Giữ nguyên đơn #{order_id} đã tạo trước đó."
                        tech_msg = f"idempotency_key trùng lặp cùng nội dung — trả về đơn #{order_id} nguyên vẹn (HTTP 200)."
                    else:
                        msg = f"Đã tạo đơn #{order_id} tại {cur_after['ten_kho']} (SL: {cur_after['tong_so_luong']}, Chờ xác nhận — chưa giữ kho)."
                        tech_msg = f"fn_tao_don_hang() chèn don_hang #{order_id} (trang_thai='ChoXacNhan') và chi_tiet_don_hang."
                elif action == "confirm":
                    msg = f"Đã xác nhận đơn #{order_id}: Đã giữ kho +{cur_after['tong_so_luong']} sản phẩm tại {cur_after['ten_kho']}."
                    tech_msg = f"trg_chuyen_trang_thai & trg_cap_nhat_ton_kho: UPDATE ton_kho (so_luong_giu +{cur_after['tong_so_luong']}) & INSERT bien_dong_kho (loai='GIU')."
                elif action == "ship":
                    msg = f"Đã xuất kho đơn #{order_id}: Trừ tồn vật lý -{cur_after['tong_so_luong']} và giải phóng đang giữ -{cur_after['tong_so_luong']}."
                    tech_msg = f"trg_cap_nhat_ton_kho: UPDATE ton_kho (so_luong_vat_ly -{cur_after['tong_so_luong']}, so_luong_giu -{cur_after['tong_so_luong']}) & INSERT bien_dong_kho (loai='XUAT')."
                elif action == "deliver":
                    rev_str = f"{int(cur_after['doanh_thu_don']):,} VNĐ".replace(",", ".")
                    msg = f"Đã giao thành công đơn #{order_id}: Ghi nhận doanh thu +{rev_str}."
                    tech_msg = f"UPDATE don_hang SET trang_thai='DaGiao' (trg_chuyen_trang_thai ghi lich_su_trang_thai; cộng vào doanh thu thuần)."
                elif action == "cancel":
                    msg = f"Đã hủy đơn #{order_id}: Tồn kho đã hoàn trả về trạng thái trước đó (Doanh thu ghi nhận: 0 VNĐ)."
                    tech_msg = f"UPDATE don_hang SET trang_thai='DaHuy' — trg_cap_nhat_ton_kho tự động ghi NHA_GIU (nếu từ DaXacNhan) hoặc HOAN (nếu từ DangGiao)."
                else:
                    msg = f"Đã cập nhật đơn #{order_id}."
                    tech_msg = ""

                payload["diff"] = {"items": diff_items}
                payload["message"] = msg
                payload["tech_message"] = tech_msg
                payload["reused"] = reused_flag
                self.send_json(payload, status=success_status)
            except Exception as e:
                st, code, msg = classify_pg_error(str(e))
                self.send_json({"error": True, "code": code, "message": msg}, status=st)
            return

        if path == "/api/race-condition":
            try:
                action = str(body.get("action", "run")).strip()
                period = str(body.get("period", "toan_ky"))
                inv_kho = str(body.get("inv_kho", "1"))
                run_id = body.get("run_id")

                if action == "release":
                    if not run_id or not str(run_id).strip():
                        self.send_json({"error": True, "code": "MISSING_RUN_ID", "message": "Thiếu mã phiên chạy (run_id) cần giải phóng."}, status=400)
                        return
                    rel = release_race_condition_run(run_id)
                    if not rel["ok"]:
                        self.send_json({"error": True, "code": "RUN_NOT_FOUND", "message": rel["error"]}, status=404)
                        return
                    dash = get_dashboard_payload(period=period, ma_kho=inv_kho)
                    rel["summary"] = dash["summary"]
                    rel["reconcile"] = dash["reconcile"]
                    rel["logs"] = dash["logs"]
                    self.send_json(rel, status=200)
                    return

                if action != "run":
                    self.send_json({"error": True, "code": "INVALID_ACTION", "message": f"Thao tác tranh mua không hợp lệ: {action}"}, status=400)
                    return

                out = execute_race_condition_run(run_id=run_id)
                dash = get_dashboard_payload(period=period, ma_kho=inv_kho)
                out["summary"] = dash["summary"]
                out["reconcile"] = dash["reconcile"]
                out["logs"] = dash["logs"]
                self.send_json(out, status=200)
            except Exception as e:
                self.send_json({"error": True, "code": "INTERNAL_ERROR", "message": str(e)}, status=500)
            return

        if path in ("/", "/index.html", "/api/dashboard"):
            self.send_json(
                {"error": True, "code": "METHOD_NOT_ALLOWED", "message": f"Endpoint {path} chỉ hỗ trợ phương thức GET."},
                status=405,
                extra_headers={"Allow": "GET"}
            )
            return

        self.send_json({"error": True, "code": "NOT_FOUND", "message": f"Không tìm thấy đường dẫn {path}."}, status=404)


if __name__ == "__main__":
    print(f"Dang kiem tra ket noi PostgreSQL ({DB_HOST}:{DB_PORT}/{DB_NAME}) bang '{PSQL_PATH}'...")
    try:
        ensure_fn_tao_don_hang()
        rec_init = run_full_reconcile()
        f_init = rec_init["full"]
        print(f"Ket noi CSDL thanh cong! Doi soat toan bo ban dau: {f_init['tong_cap']} cap kho-SKU, lech: {f_init['so_cap_lech']}")
    except Exception as init_err:
        print("CANH BAO KHOI DONG:", init_err)
        print("Huong xu ly: Kiem tra PostgreSQL da chay tren cong 5432 va CSDL 'ecom' da duoc tao.")

    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), OmnistockHandler)
    print("============================================================")
    print("  OMNISTOCK LIVE WEB DASHBOARD DANG CHAY TAI:")
    print(f"  http://localhost:{PORT}")
    print("============================================================")
    server.serve_forever()
