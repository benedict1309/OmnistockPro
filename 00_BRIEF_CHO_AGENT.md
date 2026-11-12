# BRIEF GIAO VIỆC: Đồ án CSDL "Sàn TMĐT Đa kênh & Kho Thông minh"

Bạn là agent làm việc chính cho nhóm 2 sinh viên (năm 3 CNTT). Đồ án chấm theo đề gốc trong `01_DE_BAI_GOC.md`. **Phần thiết kế và truy vấn đã xong và đã kiểm tra**; việc của bạn là hai hạng mục còn lại bên dưới. Tiếng Việt toàn bộ. Còn khoảng 2,5 tuần tính từ 2026-11-10.

## 1. Hiện trạng (đã xong, đã chạy thử trên PostgreSQL 16)

| File | Nội dung |
|---|---|
| `schema.sql` | 16 bảng, CHECK/UNIQUE/FK, 6 trigger, view đối soát kho, hàm `fn_nhap_kho` và `fn_tao_don_hang` |
| `seed_nho.sql` | Dữ liệu mẫu nhỏ (161 đơn) có chủ ý cho 8 truy vấn |
| `seed_lon.sql` | Dữ liệu mô phỏng quy mô lớn (400.161 đơn, 1.000.195 chi tiết, kỳ mô phỏng cố định `2025-12-01` -> `2026-11-30`) |
| `index_toi_uu.sql` | 4 chỉ mục tối ưu được giữ lại sau thực nghiệm (cho Q2, Q3, Q4, Q8) |
| `bench_truoc.sql`, `bench_sau.sql`, `bang_do.md` | Script đo 6 lần/truy vấn và báo cáo kết quả `EXPLAIN (ANALYZE, BUFFERS)` thực tế |
| `web_dashboard.py` | Giao diện Web Dashboard trực quan phục vụ trình diễn trực tiếp |
| `queries.sql` | 8 truy vấn đúng đề (+ Q7b là cách hiểu thứ hai) |
| `kiem_tra_cheo.sql` | Viết lại các truy vấn theo cách khác để đối chiếu, kiểm tra bất biến |
| `demo_concurrency.sh` | Demo hai phiên tranh chiếc hàng cuối + stress 30 phiên |
| `thiet_ke_csdl.md` | Giả định, bản số, từ điển dữ liệu, chứng minh 3NF, vòng đời tồn kho |
| `erd.dbml`, `erd.png` | Sơ đồ thực thể quan hệ |

Kết quả đã xác nhận trên dữ liệu nhỏ: doanh thu thuần tháng 10/2026 = 1.547.421.000 VNĐ, chạm mốc 1 tỷ ngày 18/10; stress test luôn ra đúng 10 đơn thành công / 20 bị từ chối, không deadlock, sổ cái khớp.

## 2. Dựng môi trường và chạy kiểm tra

Cần PostgreSQL 14+ chạy trên máy của nhóm. Nếu dùng Docker:

```bash
docker run --name ecom-pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16
docker exec ecom-pg createdb -U postgres ecom
export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=ecom
psql -v ON_ERROR_STOP=1 -f schema.sql
psql -v ON_ERROR_STOP=1 -f seed_nho.sql
psql -f queries.sql
psql -f kiem_tra_cheo.sql          # phải in "OK: tat ca doi chieu khop"
bash demo_concurrency.sh           # phải in "DEMO 1 DAT" và "DEMO 2 DAT"
```

`schema.sql` bắt đầu bằng `DROP SCHEMA public CASCADE`, nên mỗi lần chạy sẽ làm sạch DB. `kiem_tra_cheo.sql` chỉ dùng cho **seed nhỏ vừa nạp xong** (có số cố định); chạy sau `demo_concurrency.sh` thì dòng cuối sẽ lệch.

## 3. LUẬT KHÔNG ĐƯỢC PHÁ

1. **Không đổi tên bảng/cột sang tiếng Anh**, không đổi tên trạng thái (`ChoXacNhan`, `DaXacNhan`, `DangGiao`, `DaGiao`, `DaHuy`). Đề dùng tiếng Việt.
2. **Không sửa `schema.sql` âm thầm.** Nếu thấy cần sửa, ghi đề xuất (lý do, thay đổi, ảnh hưởng) vào file `DE_XUAT_SUA_SCHEMA.md` để nhóm duyệt. Lý do: schema đã được chuẩn hóa 3NF có chủ đích (xem `thiet_ke_csdl.md` mục 5.3); đừng thêm lại `dia_chi`, `dat_giu_hang` hay cột `danh_gia.ma_khach_hang`.
3. **Không sửa nội dung `seed_nho.sql` và `queries.sql`**, vì `kiem_tra_cheo.sql` gắn với chúng. Dữ liệu lớn làm ở file riêng.
4. **Doanh thu thuần** = `tong_tien_hang - tien_giam`, chỉ tính đơn `DaGiao`, không gồm phí vận chuyển.
5. **Bất biến phải luôn đúng** sau mọi lần nạp dữ liệu (kể cả dữ liệu lớn):
   - `SELECT bool_and(khop) FROM v_doi_soat_kho;` trả `t`
   - `tong_tien_hang` = tổng `so_luong * don_gia` của các dòng trong đơn
   - Không có dòng `ton_kho` nào vi phạm `0 <= so_luong_giu <= so_luong_vat_ly`
6. **Không bịa số liệu.** Mọi con số trong báo cáo/slide phải lấy từ kết quả đã chạy thật; ghi rõ máy, phiên bản PostgreSQL, kích thước dữ liệu.
7. **Không khẳng định điều chưa kiểm tra.** Ví dụ: không viết "tăng tốc 100 lần" nếu chưa đo; không viết hệ thống "chịu tải production".

## 4. VIỆC 1 (mục 6): Dữ liệu lớn, index, bảng đo EXPLAIN ANALYZE

**Mục tiêu:** chứng minh bằng số đo rằng index giúp các truy vấn của đề, và trung thực kể cả khi index không giúp.

### 4.1 Sinh dữ liệu lớn: `seed_lon.sql` (file mới)
- Quy mô gợi ý: 300.000 đến 500.000 `don_hang`, khoảng 1 triệu dòng `chi_tiet_don_hang`, vài nghìn khách, vài trăm sản phẩm; dữ liệu trải trên 12 tháng, có mùa vụ (tháng 10 và 11.11 nhiều hơn), tỉ lệ hủy 8-15%, tên và địa chỉ tiếng Việt.
- Nạp bằng SQL theo tập (`generate_series`, `INSERT ... SELECT`), không dùng vòng lặp từng dòng. Nên chạy trên DB đã nạp `schema.sql` + `seed_nho.sql`.
- Để nạp nhanh có thể tạm tắt trigger người dùng: `ALTER TABLE don_hang DISABLE TRIGGER USER;` (giữ nguyên CHECK và FK), **nhất định bật lại** bằng `ENABLE TRIGGER USER` khi xong.
- Gợi ý giữ sổ cái khớp: chèn `ton_kho` với số 0 trước, chèn các dòng `bien_dong_kho` theo trạng thái đơn (`GIU` khi từ `DaXacNhan`, thêm `XUAT` khi từ `DangGiao`, `NHA_GIU`/`HOAN` khi hủy), rồi `UPDATE ton_kho` từ tổng sổ cái. Nhập kho đủ lớn để tồn không âm.
- Voucher: chỉ gán cho đơn thỏa `tong_tien_hang >= gia_tri_toi_thieu` và `ngay_dat` trong hạn (vì khi tắt trigger, không có gì chặn nếu bạn sinh sai).
- Sau khi nạp: chạy các kiểm tra ở luật số 5 ở mục 3, báo thời gian nạp, `ANALYZE`.
- Lưu ý Q8: với dữ liệu lớn, doanh thu lũy kế tháng 10 sẽ đạt 1 tỷ ngay những ngày đầu tháng. Đó là bình thường; ghi chú trong báo cáo, hoặc chạy Q8 với mốc lớn hơn qua tham số, không đổi định nghĩa của đề.

### 4.2 Đo trước/sau index
- `bench_truoc.sql`: tạo trạng thái **chỉ có index mặc định** (PK, UNIQUE, và các index FK đã có sẵn trong `schema.sql`). Đo các truy vấn nặng: tối thiểu Q2, Q3, Q4, Q8, và nên thêm Q1, Q5.
- `index_toi_uu.sql`: tạo các index đề xuất. Gợi ý để cân nhắc (đo rồi mới giữ): `don_hang(ngay_dat)`; `don_hang(ma_gian_hang, ngay_dat)`; chỉ mục một phần `WHERE trang_thai = 'DaGiao'` kèm `INCLUDE (tong_tien_hang, tien_giam)` cho Q3 và Q8; index cho `danh_gia(ma_bien_the)` nếu cần cho Q1. Có thể thử partition `don_hang` theo tháng như một mục mở rộng, chỉ khi còn thời gian.
- `bench_sau.sql`: chạy lại đúng các truy vấn đó.
- Phương pháp: dùng `EXPLAIN (ANALYZE, BUFFERS)`; mỗi truy vấn chạy ít nhất 5 lần, lấy **trung vị** thời gian thực thi và bỏ lần đầu (làm nóng cache); cùng máy, cùng dữ liệu, đã `ANALYZE`; ghi `SELECT version()`, RAM/CPU, `shared_buffers`.
- Ghi lại cả những chỗ index **không** giúp hoặc làm chậm, kèm giải thích ngắn (vì sao planner chọn Seq Scan, v.v.). Đó là điểm cộng về độ trung thực.

### 4.3 Tiêu chí nghiệm thu
- `seed_lon.sql` chạy lại được trên DB sạch; luật số 5 ở mục 3 đều đạt.
- `bang_do.md`: bảng cho từng truy vấn (kế hoạch trước/sau, thời gian trung vị, số buffer, nhận xét một dòng) và một đoạn kết luận không quá tay.
- Kèm kế hoạch thực thi dạng văn bản của từng truy vấn (trích Seq Scan → Index Scan), để dán vào báo cáo.

## 5. VIỆC 2 (mục 7): Báo cáo, slide, kịch bản demo

Nội dung kỹ thuật **lấy từ `thiet_ke_csdl.md`** (đã đúng và đã kiểm tra), không viết lại theo trí nhớ. Hỏi nhóm định dạng báo cáo trước khi dựng (mặc định: Word `.docx`, hoặc theo mẫu của khoa nếu có).

### 5.1 Báo cáo
Dàn ý: 1) Giới thiệu và phạm vi; 2) Giả định (mục 1 của `thiet_ke_csdl.md`); 3) Thiết kế E/R (nhúng `erd.png`); 4) Từ điển dữ liệu; 5) Chuẩn hóa 3NF, **gồm bảng "các chỗ đã sửa" (mục 5.3)**, đây là phần cho thấy quá trình chuẩn hóa thật sự; 6) Ràng buộc và business rule (bảng đối chiếu yêu cầu của đề); 7) Quản lý tồn kho: giữ hàng, sổ cái, vòng đời; 8) 8 truy vấn: mỗi câu có đề, SQL, kết quả mẫu; 9) Concurrency: kịch bản và kết quả demo; 10) Index và bảng đo (từ việc 1); 11) Hạn chế và hướng phát triển (mục 7 của `thiet_ke_csdl.md`); 12) Phân công thành viên.

### 5.2 Slide
8 đến 10 slide, ít chữ. Gợi ý: bài toán, ERD, 3NF (trước/sau), ràng buộc và trigger, vòng đời tồn kho, kết quả 8 truy vấn, demo concurrency, bảng đo index, hạn chế. Mỗi con số phải có nguồn trong file chạy thật.

### 5.3 Kịch bản demo 5-8 phút (`kich_ban_demo.md`)
Từng bước, kèm lệnh cụ thể: (1) mở ERD; (2) chạy một truy vấn (Q8 mốc 1 tỷ); (3) chạy `demo_concurrency.sh` phần 1 và giải thích vì sao phiên B bị chặn; (4) cho xem bảng đo index; (5) phương án dự phòng nếu demo lỗi (ảnh chụp/kết quả đã lưu).

### 5.4 Danh sách câu hỏi vấn đáp
Viết khoảng 15 câu giảng viên có thể hỏi (vì sao tách `so_luong_giu`, vì sao snapshot giá, vì sao không dùng CHECK cho rule voucher, tại sao BCNF, làm sao tránh deadlock…) kèm câu trả lời ngắn, dựa vào tài liệu thiết kế.

## 6. KHÔNG làm

API/giao diện web, dashboard, phân quyền, đơn nhiều gian hàng, chuyển kho, microservices, AI. Các mục này chỉ làm nếu nhóm yêu cầu sau.

## 7. Cách báo cáo lại cho nhóm

Mỗi lần dừng: nêu (1) đã làm gì, (2) lệnh để chạy lại, (3) kết quả đo/kiểm tra thật, (4) điều chưa chắc hoặc cần nhóm quyết định. Đừng tóm tắt thành công nếu chưa chạy kiểm tra ở luật số 5 ở mục 3.
