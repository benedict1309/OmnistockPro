#!/usr/bin/env bash
# =====================================================================
# DEMO CHONG BAN VUOT TON (concurrency) - chay SAU schema.sql + seed_nho.sql
#
# Cach chay (ket noi qua bien moi truong chuan cua psql):
#   export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGDATABASE=ecom
#   bash demo_concurrency.sh
#
# Gom 2 phan:
#   Demo 1: 2 phien tranh CHIEC HANG CUOI (ton kha dung = 1) -> dung 1 phien thang
#   Demo 2: 30 phien dong thoi, don 2 san pham, ton moi san pham = 10
#           -> dung 10 don thanh cong, 20 bi tu choi, khong deadlock, ton khong am
# Moi lan chay tao san pham demo moi (ma SKU co hau to thoi gian) nen chay lai duoc.
# =====================================================================
set -u
export PGTZ=UTC                      # gio in ra tu CSDL va tu shell cung mot mui gio
PSQL="psql -X -q -v ON_ERROR_STOP=1"
RUN=$(date +%H%M%S)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

sql()  { $PSQL -At -c "$1"; }
line() { printf '%*s\n' 70 '' | tr ' ' '-'; }

# ham tao 1 bien the demo co ton = $2 tai kho 1, tra ve ma_bien_the
tao_bien_the() {
  sql "WITH b AS (
         INSERT INTO bien_the(ma_san_pham, sku, mau_sac, kich_co, gia_nhap, gia_ban)
         VALUES (1, '$1-$RUN', 'Demo', '$1-$RUN', 100000, 200000) RETURNING ma_bien_the)
       SELECT ma_bien_the FROM b"
}
can_co() {   # dung ngay neu mot buoc tao du lieu bi loi (gia tri rong)
  [ -n "$1" ] || { echo "LOI: tao du lieu demo that bai, dung lai." >&2; exit 2; }
}
nhap() { sql "SELECT fn_nhap_kho(1, $1, $2, 'Demo concurrency')" >/dev/null; }

# tao don 1 gian hang 1, kho 1, cho khach $1 gom cac dong JSON $2, khoa idempotency $3
tao_don() {
  sql "SELECT fn_tao_don_hang($1, 1, 1, now()::timestamp, NULL, '$2'::jsonb, 'Web', '$3')"
}

trangthai_kho() {   # $1 = ma_bien_the
  $PSQL -c "SELECT so_luong_vat_ly AS vat_ly, so_luong_giu AS dang_giu, so_luong_vat_ly - so_luong_giu AS kha_dung
            FROM ton_kho WHERE ma_kho = 1 AND ma_bien_the = $1"
}

# =====================================================================
line; echo "DEMO 1: HAI PHIEN TRANH CHIEC HANG CUOI"; line
BT=$(tao_bien_the LAST); can_co "$BT"; nhap "$BT" 1
DON_A=$(tao_don 1 "[{\"bt\":$BT,\"sl\":1}]" "demoA-$RUN"); can_co "$DON_A"
DON_B=$(tao_don 2 "[{\"bt\":$BT,\"sl\":1}]" "demoB-$RUN"); can_co "$DON_B"
echo "Bien the demo = $BT (ton 1 cai). Don A = $DON_A (khach 1), Don B = $DON_B (khach 2)."
echo "Truoc khi chay:"; trangthai_kho "$BT"

# Phien A: xac nhan don A, GIU transaction mo 4 giay roi COMMIT
(
  $PSQL -At <<SQL > "$WORK/A.out" 2> "$WORK/A.err"
BEGIN;
SELECT to_char(clock_timestamp(),'HH24:MI:SS.MS') || '  A  bat dau';
UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = $DON_A;
SELECT to_char(clock_timestamp(),'HH24:MI:SS.MS') || '  A  da giu hang (chua COMMIT, dang giu khoa dong ton_kho)';
SELECT pg_sleep(4);
COMMIT;
SELECT to_char(clock_timestamp(),'HH24:MI:SS.MS') || '  A  COMMIT xong';
SQL
) &
PID_A=$!
sleep 1   # de chac chan A da lay khoa truoc

# Phien B: cung muc tieu, bat dau sau 1 giay -> phai cho A
(
  $PSQL -At <<SQL > "$WORK/B.out" 2> "$WORK/B.err"
SELECT to_char(clock_timestamp(),'HH24:MI:SS.MS') || '  B  bat dau (xin giu hang cho don B)';
UPDATE don_hang SET trang_thai = 'DaXacNhan' WHERE ma_don_hang = $DON_B;
SELECT to_char(clock_timestamp(),'HH24:MI:SS.MS') || '  B  thanh cong';
SQL
  echo "$(date -u +%H:%M:%S.%3N)  B  KET QUA -> $(tr '\n' ' ' < "$WORK/B.err" | sed 's/psql:<stdin>:[0-9]*: //;s/CONTEXT.*//')" >> "$WORK/B.out"
) &
PID_B=$!
wait $PID_A $PID_B

echo; echo "Dien bien (thoi gian cho thay B bi chan cho den khi A COMMIT):"
cat "$WORK/A.out" "$WORK/B.out" | sort
echo; echo "Sau khi chay:"; trangthai_kho "$BT"
$PSQL -c "SELECT ma_don_hang, trang_thai FROM don_hang WHERE ma_don_hang IN ($DON_A, $DON_B) ORDER BY 1"
RES1=$($PSQL -At -c "SELECT count(*) FROM don_hang WHERE ma_don_hang IN ($DON_A,$DON_B) AND trang_thai='DaXacNhan'")
[ "$RES1" = "1" ] && echo "==> DEMO 1 DAT: dung 1 don giu duoc hang." || echo "==> DEMO 1 SAI: $RES1 don thanh cong!"

# =====================================================================
N=30; STOCK=10
line; echo "DEMO 2: $N PHIEN DONG THOI, DON 2 SAN PHAM, TON MOI SAN PHAM = $STOCK"; line
S1=$(tao_bien_the STRESS1); can_co "$S1"
S2=$(tao_bien_the STRESS2); can_co "$S2"
nhap "$S1" $STOCK; nhap "$S2" $STOCK
: > "$WORK/ids"
for i in $(seq 1 $N); do
  K=$(( (i % 4) + 1 ))
  # nua so don liet ke san pham theo thu tu nguoc de thu deadlock
  if [ $((i % 2)) -eq 0 ]; then ITEMS="[{\"bt\":$S1,\"sl\":1},{\"bt\":$S2,\"sl\":1}]"
  else                          ITEMS="[{\"bt\":$S2,\"sl\":1},{\"bt\":$S1,\"sl\":1}]"; fi
  DID=$(tao_don "$K" "$ITEMS" "stress-$RUN-$i"); can_co "$DID"
  echo "$DID" >> "$WORK/ids"
done
echo "Da tao $N don ChoXacNhan (moi don mua 1 cai moi san pham)."
echo "Truoc khi chay:"; $PSQL -c "SELECT ma_bien_the, so_luong_vat_ly AS vat_ly, so_luong_giu AS dang_giu FROM ton_kho WHERE ma_bien_the IN ($S1,$S2) ORDER BY 1"

START=$(sql "SELECT to_char(clock_timestamp() + interval '3 seconds', 'YYYY-MM-DD HH24:MI:SS.MS')")
run_one() {
  id=$1
  if out=$(psql -X -q -v ON_ERROR_STOP=1 -At -c \
     "SELECT pg_sleep_until('$START'::timestamp::timestamptz); UPDATE don_hang SET trang_thai='DaXacNhan' WHERE ma_don_hang=$id;" 2>&1 >/dev/null); then
    echo "OK $id"
  else
    echo "LOI $id $(echo "$out" | head -1 | sed 's/psql:.*ERROR: *//;s/^ERROR: *//')"
  fi
}
export -f run_one; export START
xargs -P $N -I{} bash -c 'run_one {}' < "$WORK/ids" > "$WORK/kq.txt"

OK=$(grep -c '^OK' "$WORK/kq.txt"); LOI=$(grep -c '^LOI' "$WORK/kq.txt")
HET=$(grep '^LOI' "$WORK/kq.txt" | grep -c 'Khong du ton')
DL=$(grep -ci 'deadlock' "$WORK/kq.txt")
echo "Ket qua: thanh cong = $OK, bi tu choi = $LOI (trong do het hang = $HET, deadlock = $DL)"
echo "Sau khi chay:"
$PSQL -c "SELECT ma_bien_the, so_luong_vat_ly AS vat_ly, so_luong_giu AS dang_giu,
                 so_luong_vat_ly - so_luong_giu AS kha_dung FROM ton_kho WHERE ma_bien_the IN ($S1,$S2) ORDER BY 1"
$PSQL -c "SELECT trang_thai, count(*) FROM don_hang WHERE ma_don_hang IN ($(paste -sd, "$WORK/ids")) GROUP BY 1 ORDER BY 1"

KHOP=$($PSQL -At -c "SELECT bool_and(khop) FROM v_doi_soat_kho WHERE ma_bien_the IN ($S1,$S2)")
TOT=1
[ "$OK" = "$STOCK" ] && [ "$HET" = "$((N-STOCK))" ] && [ "$DL" = "0" ] && [ "$KHOP" = "t" ] && TOT=0
if [ $TOT -eq 0 ]; then
  echo "==> DEMO 2 DAT: dung $STOCK don thanh cong, $((N-STOCK)) bi tu choi do het hang, khong deadlock, so cai khop."
else
  echo "==> DEMO 2 CHUA DAT (OK=$OK het=$HET deadlock=$DL doi_soat=$KHOP). Xem $WORK/kq.txt"; trap - EXIT; echo "$WORK"
fi
line
echo "Doi soat toan he thong:"; $PSQL -c "SELECT bool_and(khop) AS toan_bo_so_cai_khop FROM v_doi_soat_kho"
exit $TOT
