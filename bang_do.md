# BÁO CÁO ĐO HIỆU NĂNG TRƯỚC VÀ SAU KHI ĐÁNH CHỈ MỤC (`bang_do.md`)

Tài liệu này ghi nhận kết quả đo thực nghiệm các truy vấn `Q1..Q8` trong [`queries.sql`](queries.sql) trên tập dữ liệu lớn ([`seed_lon.sql`](seed_lon.sql)) trước và sau khi áp dụng bộ chỉ mục tối ưu ([`index_toi_uu.sql`](index_toi_uu.sql)). Toàn bộ con số và cây kế hoạch (`EXPLAIN (ANALYZE, BUFFERS)`) dưới đây được trích xuất trực tiếp từ lần chạy thực tế của [`bench_truoc.sql`](bench_truoc.sql) và [`bench_sau.sql`](bench_sau.sql) sau khi đồng bộ định nghĩa chỉ mục.

---

## 1. Cấu hình môi trường, Quy mô dữ liệu & Phương pháp đo

### 1.1. Phần cứng & Hệ điều hành thực nghiệm
- **CPU**: 12th Gen Intel(R) Core(TM) i5-12450H (8 nhân vật lý, 12 luồng xử lý)
- **RAM**: 16 GB (15,73 GB khả dụng)
- **Hệ điều hành**: Windows 64-bit (chạy trên cùng máy trạm với tiến trình kiểm thử; tham chiếu đối chiếu độc lập trên PostgreSQL 16 / Linux được ghi chú riêng ở Mục 1.6 để so sánh hành vi bộ lập lịch và page cache)

### 1.2. Phiên bản & Tham số PostgreSQL (`SELECT version()`, `pg_settings`)
- **Phiên bản**: `PostgreSQL 16.6, compiled by Visual C++ build 1942, 64-bit`
- **`shared_buffers`**: `128MB`
- **`work_mem`**: `4MB`
- **`effective_cache_size`**: `4GB`
- **`maintenance_work_mem`**: `64MB`
- **`random_page_cost`**: `4`
- **`seq_page_cost`**: `1`
- **`max_parallel_workers_per_gather`**: `2`

### 1.3. Quy mô dữ liệu & Kỳ mô phỏng sau khi nạp `seed_nho.sql` + `seed_lon.sql` + `VACUUM ANALYZE`

- **Khung thời gian dữ liệu mô phỏng (Deterministic 12-month simulation)**:
  - **Ngày bắt đầu**: `2025-12-01 00:00:07`
  - **Ngày chốt kỳ mô phỏng (`Simulation Cutoff Date`)**: `2026-11-30 23:59:59` (đơn muộn nhất lúc `2026-11-30 23:59:58`).
  - **Giải thích về mốc ngày `13–30/11/2026`**: Tập dữ liệu sinh cố định trọn 12 tháng (`01/12/2025 – 30/11/2026`) để đảm bảo tính tất định (reproducible) bất kể ngày chấm bài. Trong tổng số `400.161` đơn hàng (`278.469` đơn `DaGiao`, doanh thu thuần `8.666.863.667.500 VNĐ`), giai đoạn `01/12/2025 – 12/11/2026` có `376.127` đơn và giai đoạn `13/11/2026 – 30/11/2026` có `24.034` đơn (`6,01%`, gồm `16.670` đơn `DaGiao` tương ứng `514.111.949.300 VNĐ`). Các truy vấn phân tích theo tháng mục tiêu (`Q3, Q4, Q8`) đều khóa cố định vào kỳ đã khép sổ **tháng 10/2026 (`2026-10-01 .. 2026-10-31`)** với `56.445` đơn (`39.156` đơn `DaGiao`, doanh thu thuần `1.216.498.566.200 VNĐ`).

| Bảng | Số dòng (`reltuples`) | Dung lượng bảng (Heap) | Dung lượng Index (Trước tối ưu) | Tổng dung lượng (Trước tối ưu) | Dung lượng Index (Sau tối ưu) | Tổng dung lượng (Sau tối ưu) |
|---|---:|---:|---:|---:|---:|---:|
| `bien_dong_kho` | 1.810.701 | 175 MB | 257 MB | 432 MB | 257 MB | 432 MB |
| `don_hang` | 400.161 | 78 MB | 74 MB | 152 MB | 122 MB | 200 MB |
| `lich_su_trang_thai` | 1.010.582 | 69 MB | 78 MB | 147 MB | 78 MB | 147 MB |
| `chi_tiet_don_hang` | 1.000.195 | 50 MB | 63 MB | 113 MB | 63 MB | 113 MB |
| `thanh_toan` | 382.000 | 27 MB | 16 MB | 43 MB | 16 MB | 43 MB |
| `van_chuyen` | 314.100 | 19 MB | 23 MB | 42 MB | 23 MB | 42 MB |
| `danh_gia` | 110.914 | 14 MB | 4.880 kB | 18 MB | 4.880 kB | 18 MB |
| `khach_hang` | 5.006 | 784 kB | 960 kB | 1.744 kB | 1.032 kB | 1.816 kB |
| `ton_kho` | 3.680 | 352 kB | 424 kB | 776 kB | 424 kB | 776 kB |
| `bien_the` | 736 | 88 kB | 312 kB | 400 kB | 312 kB | 400 kB |
| `san_pham` | 247 | 80 kB | 64 kB | 144 kB | 64 kB | 144 kB |
| `gian_hang` | 20 | 40 kB | 48 kB | 88 kB | 48 kB | 88 kB |
| `danh_muc` | 9 | 40 kB | 32 kB | 72 kB | 32 kB | 72 kB |
| `nha_cung_cap` | 20 | 40 kB | 32 kB | 72 kB | 32 kB | 72 kB |
| `voucher` | 6 | 40 kB | 32 kB | 72 kB | 32 kB | 72 kB |
| `kho` | 5 | 40 kB | 32 kB | 72 kB | 32 kB | 72 kB |

### 1.4. Tập chỉ mục nền tảng có sẵn trong `schema.sql` (27 chỉ mục tồn tại ở cả `bench_truoc.sql` và `bench_sau.sql`)
Trước khi chạy `bench_truoc.sql`, kịch bản chủ động `DROP INDEX IF EXISTS` toàn bộ các chỉ mục tối ưu và chỉ mục thử nghiệm (bao gồm cả 2 tên `idx_don_hang_gh_ngay_tt` và `idx_don_hang_ngay_gh_tt`), chỉ giữ lại đúng **27 chỉ mục nền tảng của `schema.sql`**:
- **Trên `don_hang` (5 chỉ mục, tổng 74 MB)**: `don_hang_pkey (ma_don_hang)` (22 MB), `idx_don_hang_khach (ma_khach_hang)` (13 MB), `idx_don_hang_gian_hang (ma_gian_hang)` (5.112 kB), `idx_don_hang_kho_tt (ma_kho, trang_thai)` (6.368 kB), `uq_don_hang_idempotency (idempotency_key) WHERE idempotency_key IS NOT NULL` (27 MB).
- **Trên `bien_dong_kho` (5 chỉ mục, tổng 257 MB)**: `bien_dong_kho_pkey`, `idx_bien_dong_kho_bt (ma_kho, ma_bien_the)`, `idx_bien_dong_kho_don (ma_don_hang)`, `uq_bien_dong_giu_1_lan`, `uq_bien_dong_xuat_1_lan`.
- **Trên `lich_su_trang_thai` & `thanh_toan`**: `lich_su_trang_thai_pkey`, `idx_lich_su_tt_don (ma_don_hang)`, `thanh_toan_pkey`, `idx_thanh_toan_don (ma_don_hang)`.
- **Trên các bảng còn lại**: khóa chính (`pkey`), ràng buộc duy nhất (`UNIQUE`) và chỉ mục khóa ngoại cơ bản (`idx_bien_the_san_pham`, `idx_ctdh_bien_the`, `idx_san_pham_danh_muc`, `idx_san_pham_ncc`).

### 1.5. Phương pháp đo & Cách đọc các chỉ số (`shared hit`, `shared read`, `Execution Time`)
1. **Quy trình chạy**:
   - Chạy `VACUUM ANALYZE;` toàn bộ cơ sở dữ liệu ngay sau khi xóa chỉ mục (ở `bench_truoc.sql`) và ngay sau khi tạo chỉ mục (ở `bench_sau.sql`) để cập nhật Visibility Map (phục vụ `Index Only Scan` với `Heap Fetches = 0`) và thống kê histogram.
   - Mỗi truy vấn `Q1..Q8` được chạy **6 lần liên tiếp** bằng `EXPLAIN (ANALYZE, BUFFERS)`.
   - Báo cáo ghi nhận đầy đủ **Lần 1 (warm-up)**, **5 lần chạy tiếp theo (Lần 2..6)** và lấy **trung vị (median) của Lần 2..6** làm đại diện so sánh.
2. **Phân biệt rõ các chỉ số bộ đệm (Buffers) và thời gian thực thi**:
   - **`shared hit`**: Số lần truy cập trang 8KB tìm thấy ngay trong bộ đệm `shared_buffers` (128 MB) của PostgreSQL.
   - **`shared read`**: Số lần trang 8KB không nằm trong `shared_buffers` nên PostgreSQL phải gọi hệ điều hành đọc vào `shared_buffers` (có thể được phục vụ từ **OS page cache** trên RAM 16 GB hoặc từ ổ đĩa vật lý). Do đó, **không gọi toàn bộ buffers là lượt đọc đĩa vật lý**.
   - **Tổng số lượt chạm trang (`Total Buffers = shared hit + shared read`)**: Phản ánh chính xác **khối lượng công việc dữ liệu (logical I/O work)** mà kế hoạch thực thi phải xử lý. Chỉ số này bất biến theo tải CPU và hệ điều hành khi cây kế hoạch không đổi.
   - **`Execution Time` (ms)**: Thời gian thực thi thực tế (wall-clock time). Trên máy có 16 GB RAM, bảng `don_hang` (78 MB heap) nằm gọn trong `shared_buffers` (128 MB) sau lần chạy đầu tiên (`shared read = 0`, toàn bộ là `shared hit = 9.967`). Tuy nhiên, trên Windows khi có các tiến trình nền hoặc khi chạy `Parallel Seq Scan` (khởi tạo 2 background workers qua cơ chế tiến trình của Windows), thời gian wall-clock giữa các lần chạy có thể dao động mạnh hơn so với Linux.
   - **Nguyên tắc kết luận**: Chỉ kết luận chỉ mục cải thiện hiệu năng khi **cả kế hoạch thực thi (plan) thay đổi theo hướng giảm số trang buffer chạm (`shared hit + read`) lẫn thời gian thực thi giảm có ý nghĩa**. Với các truy vấn có cùng cây kế hoạch và cùng số buffers (như `Q1, Q5, Q6`) hoặc chênh lệch thời gian `< 1 ms` trên bảng cực nhỏ (như `Q7`), sự khác biệt thời gian giữa hai lượt chạy là nhiễu lập lịch CPU/cache chứ không phải do chỉ mục mới.

---

## 2. Danh sách chỉ mục tối ưu & Quyết định lựa chọn

### 2.1. Bốn (04) chỉ mục khuyến nghị được giữ lại trong `index_toi_uu.sql`

| Tên chỉ mục | Bảng | Định nghĩa chính xác trong `index_toi_uu.sql` | Dung lượng | Truy vấn mục tiêu | Kết quả thực nghiệm & Lý do giữ lại |
|---|---|---|---:|---|---|
| `idx_don_hang_dagiao_ngay_gh` | `don_hang` | `ON don_hang(ngay_dat, ma_gian_hang) INCLUDE (ma_don_hang, tong_tien_hang, tien_giam) WHERE trang_thai = 'DaGiao'` | 13 MB | **Q3, Q8** | **Giữ lại**: Chuyển `Seq Scan` (`9.967` trang heap) sang `Index Only Scan` (`Heap Fetches = 0`, `236` trang index); giảm **97,6%** buffers; tăng tốc **11,50x** cho Q3 và **3,53x** cho Q8. |
| `idx_don_hang_gh_ngay_tt` | `don_hang` | `ON don_hang(ma_gian_hang, ngay_dat) INCLUDE (trang_thai)` | 16 MB | **Q4** | **Giữ lại**: Chuyển `Parallel Seq Scan` (`9.990` trang) sang `Nested Loop + Index Only Scan` (`354` trang, `Heap Fetches = 0`); giảm **96,5%** buffers; tăng tốc **12,91x** cho Q4 và **không gây thoái hóa kế hoạch Q2** (xem Mục 5.5). |
| `idx_khach_hang_ho_ten` | `khach_hang` | `ON khach_hang(ho_ten)` | 72 kB | **Q2** | **Giữ lại**: Chuyển `Seq Scan on khach_hang` (`93` trang) sang `Bitmap Index Scan` (`3` trang, giảm **96,8%** buffers tìm khách). |
| `idx_don_hang_khach_ngay` | `don_hang` | `ON don_hang(ma_khach_hang, ngay_dat, ma_don_hang) INCLUDE (trang_thai)` | 19 MB | **Q2** | **Giữ lại**: Chuyển `Bitmap Heap Scan on don_hang` (`232` trang cho khách 265 đơn) sang `Index Only Scan` (`5` trang, `Heap Fetches = 0`), giảm tổng buffers trên `khach_hang + don_hang` từ **325** xuống **8** trang (**-97,5%**). |

### 2.2. Bốn (04) chỉ mục thử nghiệm đã kiểm chứng và loại bỏ khỏi `index_toi_uu.sql`

Trong quá trình nghiên cứu, nhóm đã thử nghiệm thêm 4 chỉ mục cho `Q1, Q5, Q6, Q7` (xem chi tiết tại Mục 5.1 – 5.4). Kết quả đo thực tế cho thấy chúng không giúp giảm số trang đọc hoặc làm planner chọn kế hoạch chạm nhiều buffer hơn, nên đã được **loại bỏ khỏi `index_toi_uu.sql`** để tránh lãng phí dung lượng đĩa và chi phí ghi (`INSERT/UPDATE`):

| Tên chỉ mục thử nghiệm | Bảng | Định nghĩa đã thử nghiệm | Dung lượng | Truy vấn mục tiêu | Quyết định & Lý do kỹ thuật |
|---|---|---|---:|---|---|
| `idx_danh_gia_bien_the_sao` | `danh_gia` | `ON danh_gia(ma_bien_the) INCLUDE (so_sao, ma_danh_gia)` | 3.440 kB | **Q1** | **Loại bỏ**: Planner vẫn chọn `Seq Scan on danh_gia` (`1.744` buffers) vì CTE đệ quy + nhánh `'Điện thoại'` lấy tới `25,1%` số dòng bảng `danh_gia` (`27.894 / 110.914` dòng). |
| `idx_ton_kho_bien_the_inc` | `ton_kho` | `ON ton_kho(ma_bien_the) INCLUDE (so_luong_vat_ly, so_luong_giu)` | 136 kB | **Q5** | **Loại bỏ**: Q5 tổng hợp 100% bảng `ton_kho` (`3.680` dòng / `40` trang heap), `Seq Scan + Hash Join` (`99` buffers) luôn rẻ hơn quét B-tree. |
| `idx_khach_hang_ngay_dk` | `khach_hang` | `ON khach_hang(ngay_dang_ky)` | 72 kB | **Q6** | **Loại bỏ**: Điều kiện `ngay_dang_ky < CURRENT_DATE - INTERVAL '1 year'` giữ lại `4.979 / 5.006` khách hàng (`99,46%`), planner luôn dùng `Seq Scan on khach_hang` (`93` trang). |
| `idx_bien_the_sp_giaban` | `bien_the` | `ON bien_the(ma_san_pham, gia_ban DESC)` | 40 kB | **Q7** | **Loại bỏ**: Làm planner đổi từ `Nested Loop + Hash Join` (`23` buffers, `0,342 ms`) sang `Merge Join + Index Scan` chạm tới **`739` buffers** (`0,618 ms`). |

---

## 3. Bảng tổng hợp kết quả đo thực tế (`bench_truoc.sql` vs `bench_sau.sql`)

| Truy vấn | Kế hoạch chính TRƯỚC tối ưu | Kế hoạch chính SAU tối ưu | Lần 1 Warm-up TRƯỚC (ms) | Lần 2..6 TRƯỚC (ms) | Trung vị TRƯỚC (ms) | Lần 1 Warm-up SAU (ms) | Lần 2..6 SAU (ms) | Trung vị SAU (ms) | Buffers TRƯỚC (trang 8KB) | Buffers SAU (trang 8KB) | Kết luận kỹ thuật & Đánh giá hiệu năng |
|---|---|---|---:|---|---:|---:|---|---:|---|---|---|
| **Q1** | `Seq Scan on danh_gia` + `Hash Join` | `Seq Scan on danh_gia` + `Hash Join` (giữ nguyên) | 305,080 | 46,189; 53,781; 53,986; 56,270; 49,798 | **53,781** | 17,263 | 18,315; 19,575; 19,321; 36,653; 26,513 | **19,575** | `hit=1744` (**1.744**) | `hit=1744` (**1.744**) | **Không đổi về kế hoạch và I/O (`1.744` buffers)**: Không tạo index mới trên `danh_gia`. Chênh lệch thời gian giữa hai lượt chạy là do dao động CPU/cache của hệ điều hành. |
| **Q2** *(Nguyễn Văn A — 265 đơn)* | `Seq Scan on khach_hang` + `Bitmap Heap Scan on don_hang` | `Bitmap Index Scan (idx_khach_hang_ho_ten)` + `Index Only Scan (idx_don_hang_khach_ngay)` | 6,637 | 5,930; 5,660; 6,690; 6,073; 5,972 | **5,972** | 2,433 (`hit=1081 read=3`) | 2,089; 1,984; 2,735; 2,777; 2,893 | **2,735** | `hit=1401` (**1.401**; phần `khach_hang + don_hang` = **325**) | `hit=1084` (**1.084**; phần `khach_hang + don_hang` = **8**) | **Nhanh hơn 2,18x (-54,2% thời gian), giảm 97,5% buffers trên `khach_hang + don_hang` (325 $\rightarrow$ 8 trang, `Heap Fetches = 0`)**. Khi cả hai đều dưới vài ms (như trên Linux ~1,2 ms), chênh lệch thời gian tuyệt đối nhỏ nhưng lợi ích giảm 317 trang heap là chắc chắn. |
| **Q2b** *(Lê Minh Cường — 43 đơn)* | `Seq Scan on khach_hang` + `Bitmap Heap Scan on don_hang` | `Bitmap Index Scan (idx_khach_hang_ho_ten)` + `Index Only Scan (idx_don_hang_khach_ngay)` | — | — | **3,229** | — | — | **1,235** | `hit=291` (`khach_hang + don_hang` = **107**) | `hit=190 read=1` (**191**; `khach_hang + don_hang` = **7**) | **Giảm 93,5% buffers trên `khach_hang + don_hang` (107 $\rightarrow$ 7 trang)**; tránh hoàn toàn lỗi quét `287.245` dòng của index ngược cột (Mục 5.5). |
| **Q3** | `Seq Scan on don_hang` (lọc bỏ 361.005 dòng) + `Hash Right Join` | `Index Only Scan (idx_don_hang_dagiao_ngay_gh)` (`Heap Fetches = 0`) | 201,721 | 212,664; 231,818; 342,335; 229,543; 1826,320 | **231,818** | 23,231 (`hit=5 read=235`) | 20,161; 20,668; 19,589; 18,461; 31,220 | **20,161** | `hit=9968` (**9.968**) | `hit=237` (**237**) | **Nhanh hơn 11,50x (-91,3% thời gian), giảm 97,6% buffers (9.968 $\rightarrow$ 237 trang)**: Partial covering index loại bỏ hoàn toàn việc quét bảng heap `don_hang` 78 MB. |
| **Q4** | `Parallel Seq Scan on don_hang` (2 workers) + `Partial HashAggregate` | `Nested Loop` + `Index Only Scan (idx_don_hang_gh_ngay_tt)` + `GroupAggregate` | 129,588 | 154,570; 141,543; 238,769; 252,909; 313,151 | **238,769** | 19,823 (`hit=32 read=322`) | 16,831; 22,200; 24,003; 18,491; 15,499 | **18,491** | `hit=9990` (**9.990**) | `hit=354` (**354**) | **Nhanh hơn 12,91x (-92,3% thời gian), giảm 96,5% buffers (9.990 $\rightarrow$ 354 trang)**: Gom nhóm trực tiếp theo thứ tự `ma_gian_hang` mà không cần khởi tạo 2 parallel workers. |
| **Q5** | `Seq Scan on ton_kho` + `Seq Scan on bien_the` + `Hash Join` | `Seq Scan on ton_kho` + `Seq Scan on bien_the` + `Hash Join` (giữ nguyên) | 13,914 | 7,803; 9,051; 6,250; 11,657; 10,788 | **9,051** | 1,941 | 1,728; 1,845; 2,248; 4,463; 5,091 | **2,248** | `hit=99` (**99**) | `hit=99` (**99**) | **Không đổi về kế hoạch và I/O (`99` buffers)**: Truy vấn đọc 100% tồn kho (`3.680` dòng / `40` trang), `Seq Scan` đã tối ưu. |
| **Q6** | `Seq Scan on khach_hang` + `Index Only Scan (idx_don_hang_khach)` | `Seq Scan on khach_hang` + `Index Only Scan (idx_don_hang_khach)` (giữ nguyên) | 43,653 | 29,637; 29,063; 33,037; 33,753; 30,263 | **30,263** | 18,094 | 8,626; 8,613; 13,643; 7,379; 5,354 | **8,613** | `hit=15031` (**15.031**) | `hit=15031` (**15.031**) | **Không đổi về kế hoạch và I/O (`15.031` buffers)**: Đã được tối ưu sẵn bởi `idx_don_hang_khach` (`Heap Fetches = 0`) trong `schema.sql`. |
| **Q7** | `Nested Loop` + `Seq Scan on bien_the` + `SubPlan 1 (Hash Join)` | `Nested Loop` + `Seq Scan on bien_the` + `SubPlan 1 (Hash Join)` (giữ nguyên) | 0,980 | 1,000; 3,528; 2,635; 0,950; 0,947 | **1,000** | 0,326 | 0,324; 0,349; 0,325; 0,342; 0,366 | **0,342** | `hit=23` (**23**) | `hit=23` (**23**) | **Không đổi về kế hoạch và I/O (`23` buffers)**: Chênh lệch `< 1 ms` trên bảng 7 trang (`736` dòng) chưa đủ bằng chứng về khác biệt hiệu năng thực thi. |
| **Q8** | `Parallel Seq Scan on don_hang` (2 workers) + `GroupAggregate` + `WindowAgg` | `Index Only Scan (idx_don_hang_dagiao_ngay_gh)` + `GroupAggregate` + `WindowAgg` | 143,947 | 166,005; 190,171; 250,771; 390,517; 311,029 | **250,771** | 65,396 | 77,538; 63,204; 76,199; 70,582; 70,946 | **70,946** | `hit=10041` (**10.041**) | `hit=236` (**236**) | **Nhanh hơn 3,53x (-71,7% thời gian), giảm 97,6% buffers (10.041 $\rightarrow$ 236 trang)**: Loại bỏ hoàn toàn `Parallel Seq Scan` trên `don_hang`. |

---

## 4. Chi tiết kế hoạch thực thi (`EXPLAIN (ANALYZE, BUFFERS)`) trước và sau

### 4.1. Truy vấn Q3 — Doanh thu thuần từng gian hàng tháng 10/2026

**Trước khi tạo chỉ mục tối ưu (Lần trung vị — `231,818 ms`, `shared hit=9968`):**
```text
 Sort  (cost=17676.32..17676.37 rows=20 width=128) (actual time=231.724..231.728 rows=20 loops=1)
   Sort Key: (COALESCE(sum((d.tong_tien_hang - d.tien_giam)), '0'::numeric)) DESC
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=9968
   ->  HashAggregate  (cost=17675.54..17675.89 rows=20 width=128) (actual time=231.678..231.699 rows=20 loops=1)
         Group Key: g.ma_gian_hang
         Batches: 1  Memory Usage: 48kB
         Buffers: shared hit=9968
         ->  Hash Right Join  (cost=1.45..17094.50 rows=38736 width=37) (actual time=0.060..188.950 rows=39156 loops=1)
               Hash Cond: (d.ma_gian_hang = g.ma_gian_hang)
               Buffers: shared hit=9968
               ->  Seq Scan on don_hang d  (cost=0.00..16969.82 rows=38736 width=17) (actual time=0.015..158.500 rows=39156 loops=1)
                     Filter: ((ngay_dat >= '2026-10-01'::date) AND (ngay_dat < '2026-11-01'::date) AND ((trang_thai)::text = 'DaGiao'::text))
                     Rows Removed by Filter: 361005
                     Buffers: shared hit=9967
               ->  Hash  (cost=1.20..1.20 rows=20 width=24) (actual time=0.036..0.037 rows=20 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     Buffers: shared hit=1
                     ->  Seq Scan on gian_hang g  (cost=0.00..1.20 rows=20 width=24) (actual time=0.023..0.027 rows=20 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=7
 Planning Time: 0.490 ms
 Execution Time: 231.818 ms
```

**Sau khi tạo `idx_don_hang_dagiao_ngay_gh` (Lần trung vị — `20,161 ms`, `shared hit=237`):**
```text
 Sort  (cost=2451.37..2451.42 rows=20 width=128) (actual time=20.111..20.114 rows=20 loops=1)
   Sort Key: (COALESCE(sum((d.tong_tien_hang - d.tien_giam)), '0'::numeric)) DESC
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=237
   ->  HashAggregate  (cost=2450.59..2450.94 rows=20 width=128) (actual time=20.089..20.099 rows=20 loops=1)
         Group Key: g.ma_gian_hang
         Batches: 1  Memory Usage: 48kB
         Buffers: shared hit=237
         ->  Hash Right Join  (cost=1.87..1859.44 rows=39410 width=37) (actual time=0.036..9.129 rows=39156 loops=1)
               Hash Cond: (d.ma_gian_hang = g.ma_gian_hang)
               Buffers: shared hit=237
               ->  Index Only Scan using idx_don_hang_dagiao_ngay_gh on don_hang d  (cost=0.42..1732.62 rows=39410 width=17) (actual time=0.016..3.848 rows=39156 loops=1)
                     Index Cond: ((ngay_dat >= '2026-10-01'::date) AND (ngay_dat < '2026-11-01'::date))
                     Heap Fetches: 0
                     Buffers: shared hit=236
               ->  Hash  (cost=1.20..1.20 rows=20 width=24) (actual time=0.013..0.014 rows=20 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     Buffers: shared hit=1
                     ->  Seq Scan on gian_hang g  (cost=0.00..1.20 rows=20 width=24) (actual time=0.007..0.008 rows=20 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=7
 Planning Time: 0.254 ms
 Execution Time: 20.161 ms
```
- **Phân tích**: Trong [`schema.sql`](schema.sql), bảng `don_hang` chỉ có chỉ mục khóa ngoại đơn cột `idx_don_hang_gian_hang ON don_hang(ma_gian_hang)` (không có `ngay_dat`, `trang_thai`, `tong_tien_hang`, `tien_giam`). Do đó trước khi tối ưu, PostgreSQL buộc phải `Seq Scan` toàn bộ `9.967` trang heap của `don_hang` và lọc bỏ `361.005` dòng. Khi tạo partial covering index `idx_don_hang_dagiao_ngay_gh` lọc sẵn `WHERE trang_thai = 'DaGiao'` và `INCLUDE (ma_don_hang, tong_tien_hang, tien_giam)`, PostgreSQL thực hiện `Index Only Scan` với `Heap Fetches: 0`, chỉ chạm đúng **236 trang index** (ở Lần 1 warm-up là `shared hit=5 read=235`, từ Lần 2..6 là `shared hit=237`), giảm **97,6%** số trang buffer và rút ngắn thời gian đọc `don_hang` từ **158,50 ms** xuống **3,85 ms**.

---

### 4.2. Truy vấn Q4 — Tỷ lệ hủy đơn theo gian hàng tháng 10/2026 (> 10%)

**Trước khi tạo chỉ mục tối ưu (Lần trung vị — `238,769 ms`, `shared hit=9990`):**
```text
 Sort  (cost=13781.83..13781.85 rows=7 width=72) (actual time=219.336..238.408 rows=12 loops=1)
   Sort Key: (round(((100.0 * (count(*) FILTER (WHERE ((d.trang_thai)::text = 'DaHuy'::text)))::numeric) / (count(*))::numeric), 2)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=9990
   ->  Finalize GroupAggregate  (cost=13776.38..13781.74 rows=7 width=72) (actual time=219.240..238.369 rows=12 loops=1)
         Group Key: g.ma_gian_hang
         Filter: ((count(*) FILTER (WHERE ((d.trang_thai)::text = 'DaHuy'::text)) * 10) > count(*))
         Rows Removed by Filter: 8
         Buffers: shared hit=9990
         ->  Gather Merge  (cost=13776.38..13781.05 rows=40 width=40) (actual time=219.180..238.271 rows=60 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               Buffers: shared hit=9990
               ->  Sort  (cost=12776.36..12776.41 rows=20 width=40) (actual time=105.708..105.713 rows=20 loops=3)
                     Sort Key: g.ma_gian_hang
                     Sort Method: quicksort  Memory: 26kB
                     Buffers: shared hit=9990
                     Worker 0:  Sort Method: quicksort  Memory: 26kB
                     Worker 1:  Sort Method: quicksort  Memory: 26kB
                     ->  Partial HashAggregate  (cost=12775.73..12775.93 rows=20 width=40) (actual time=105.645..105.658 rows=20 loops=3)
                           Group Key: g.ma_gian_hang
                           Batches: 1  Memory Usage: 24kB
                           Buffers: shared hit=9976
                           ->  Hash Join  (cost=1.45..12543.38 rows=23235 width=31) (actual time=0.756..94.581 rows=18815 loops=3)
                                 Hash Cond: (d.ma_gian_hang = g.ma_gian_hang)
                                 Buffers: shared hit=9976
                                 ->  Parallel Seq Scan on don_hang d  (cost=0.00..12468.01 rows=23235 width=11) (actual time=0.029..87.280 rows=18815 loops=3)
                                       Filter: ((ngay_dat >= '2026-10-01'::date) AND (ngay_dat < '2026-11-01'::date))
                                       Rows Removed by Filter: 114572
                                       Buffers: shared hit=9967
                                 ->  Hash  (cost=1.20..1.20 rows=20 width=24) (actual time=0.696..0.697 rows=20 loops=3)
                                       Buckets: 1024  Batches: 1  Memory Usage: 10kB
                                       Buffers: shared hit=3
                                       ->  Seq Scan on gian_hang g  (cost=0.00..1.20 rows=20 width=24) (actual time=0.663..0.671 rows=20 loops=3)
                                             Buffers: shared hit=3
 Planning:
   Buffers: shared hit=7
 Planning Time: 6.650 ms
 Execution Time: 238.769 ms
```

**Sau khi tạo `idx_don_hang_gh_ngay_tt` (Lần trung vị — `18,491 ms`, `shared hit=354`):**
```text
 Sort  (cost=3548.48..3548.50 rows=7 width=72) (actual time=18.442..18.446 rows=12 loops=1)
   Sort Key: (round(((100.0 * (count(*) FILTER (WHERE ((d.trang_thai)::text = 'DaHuy'::text)))::numeric) / (count(*))::numeric), 2)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=354
   ->  GroupAggregate  (cost=0.56..3548.38 rows=7 width=72) (actual time=0.752..18.425 rows=12 loops=1)
         Group Key: g.ma_gian_hang
         Filter: ((count(*) FILTER (WHERE ((d.trang_thai)::text = 'DaHuy'::text)) * 10) > count(*))
         Rows Removed by Filter: 8
         Buffers: shared hit=354
         ->  Nested Loop  (cost=0.56..2981.69 rows=56631 width=31) (actual time=0.023..12.807 rows=56445 loops=1)
               Buffers: shared hit=354
               ->  Index Scan using gian_hang_pkey on gian_hang g  (cost=0.14..12.44 rows=20 width=24) (actual time=0.005..0.013 rows=20 loops=1)
                     Buffers: shared hit=2
               ->  Index Only Scan using idx_don_hang_gh_ngay_tt on don_hang d  (cost=0.42..120.14 rows=2832 width=11) (actual time=0.009..0.369 rows=2822 loops=20)
                     Index Cond: ((ma_gian_hang = g.ma_gian_hang) AND (ngay_dat >= '2026-10-01'::date) AND (ngay_dat < '2026-11-01'::date))
                     Heap Fetches: 0
                     Buffers: shared hit=352
 Planning:
   Buffers: shared hit=7
 Planning Time: 0.324 ms
 Execution Time: 18.491 ms
```
- **Phân tích**: Khác với Q3 và Q8 (chỉ tính đơn `'DaGiao'`), Q4 phải đếm tổng số đơn ở **mọi trạng thái** và số đơn `'DaHuy'`. Nhờ đặt `ma_gian_hang` đứng đầu trong `idx_don_hang_gh_ngay_tt ON don_hang(ma_gian_hang, ngay_dat) INCLUDE (trang_thai)`, PostgreSQL duyệt 20 gian hàng theo `gian_hang_pkey`, quét `Index Only Scan` đúng đoạn tháng 10/2026 của từng gian hàng (`352` trang index, `Heap Fetches: 0`) và `GroupAggregate` ngay trên luồng dữ liệu đã có thứ tự `ma_gian_hang`, giảm **96,5%** buffers (`9.990` $\rightarrow$ `354`) và giảm thời gian từ **238,769 ms** xuống **18,491 ms** (**nhanh hơn 12,91 lần**).

---

### 4.3. Truy vấn Q8 — Doanh thu thuần theo ngày, doanh thu lũy kế đầu tháng & đánh dấu ngày đầu tiên chạm mốc 1 tỷ VNĐ (Window Functions)

**Trước khi tạo chỉ mục tối ưu (Lần trung vị — `250,771 ms`, `shared hit=10041`):**
```text
 Sort  (cost=30524.79..30621.50 rows=38685 width=104) (actual time=250.229..250.358 rows=31 loops=1)
   Sort Key: ((d.ngay_dat)::date)
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=10041
   ->  WindowAgg  (cost=23428.63..25459.59 rows=38685 width=104) (actual time=250.087..250.321 rows=31 loops=1)
         Buffers: shared hit=10041
         ->  WindowAgg  (cost=23428.63..24202.33 rows=38685 width=72) (actual time=250.071..250.259 rows=31 loops=1)
               Buffers: shared hit=10041
               ->  Sort  (cost=23428.63..23525.34 rows=38685 width=40) (actual time=250.043..250.172 rows=31 loops=1)
                     Sort Key: ((date_trunc('month'::text, d.ngay_dat))::date), ((d.ngay_dat)::date)
                     Sort Method: quicksort  Memory: 26kB
                     Buffers: shared hit=10041
                     ->  Finalize GroupAggregate  (cost=15133.97..20480.93 rows=38685 width=40) (actual time=215.578..250.127 rows=31 loops=1)
                           Group Key: ((d.ngay_dat)::date), ((date_trunc('month'::text, d.ngay_dat))::date)
                           Buffers: shared hit=10041
                           ->  Gather Merge  (cost=15133.97..19384.43 rows=32280 width=40) (actual time=215.497..249.952 rows=93 loops=1)
                                 Workers Planned: 2
                                 Workers Launched: 2
                                 Buffers: shared hit=10041
                                 ->  Partial GroupAggregate  (cost=14133.94..14658.49 rows=16140 width=40) (actual time=99.068..112.487 rows=31 loops=3)
                                       Group Key: ((d.ngay_dat)::date), ((date_trunc('month'::text, d.ngay_dat))::date)
                                       Buffers: shared hit=10041
                                       ->  Sort  (cost=14133.94..14174.29 rows=16140 width=17) (actual time=98.966..99.604 rows=13052 loops=3)
                                             Sort Key: ((d.ngay_dat)::date), ((date_trunc('month'::text, d.ngay_dat))::date)
                                             Sort Method: quicksort  Memory: 478kB
                                             Buffers: shared hit=10041
                                             Worker 0:  Sort Method: quicksort  Memory: 1616kB
                                             Worker 1:  Sort Method: quicksort  Memory: 1064kB
                                             ->  Parallel Seq Scan on don_hang d  (cost=0.00..13005.89 rows=16140 width=17) (actual time=0.440..95.056 rows=13052 loops=3)
                                                   Filter: ((ngay_dat >= '2026-10-01'::date) AND (ngay_dat < '2026-11-01'::date) AND ((trang_thai)::text = 'DaGiao'::text))
                                                   Rows Removed by Filter: 120335
                                                   Buffers: shared hit=9967
 Planning Time: 0.417 ms
 Execution Time: 250.771 ms
```

**Sau khi tạo `idx_don_hang_dagiao_ngay_gh` (Lần trung vị — `70,946 ms`, `shared hit=236`):**
```text
 Sort  (cost=16539.15..16637.51 rows=39343 width=104) (actual time=70.257..70.261 rows=31 loops=1)
   Sort Key: ((d.ngay_dat)::date)
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=236
   ->  WindowAgg  (cost=9318.52..11384.03 rows=39343 width=104) (actual time=70.149..70.227 rows=31 loops=1)
         Buffers: shared hit=236
         ->  WindowAgg  (cost=9318.52..10105.38 rows=39343 width=72) (actual time=70.127..70.175 rows=31 loops=1)
               Buffers: shared hit=236
               ->  Sort  (cost=9318.52..9416.88 rows=39343 width=40) (actual time=70.084..70.088 rows=31 loops=1)
                     Sort Key: ((date_trunc('month'::text, d.ngay_dat))::date), ((d.ngay_dat)::date)
                     Sort Method: quicksort  Memory: 26kB
                     Buffers: shared hit=236
                     ->  GroupAggregate  (cost=5036.42..6315.90 rows=39343 width=40) (actual time=45.270..70.035 rows=31 loops=1)
                           Group Key: ((d.ngay_dat)::date), ((date_trunc('month'::text, d.ngay_dat))::date)
                           Buffers: shared hit=236
                           ->  Sort  (cost=5036.42..5134.94 rows=39410 width=17) (actual time=44.654..47.180 rows=39156 loops=1)
                                 Sort Key: ((d.ngay_dat)::date), ((date_trunc('month'::text, d.ngay_dat))::date)
                                 Sort Method: quicksort  Memory: 3190kB
                                 Buffers: shared hit=236
                                 ->  Index Only Scan using idx_don_hang_dagiao_ngay_gh on don_hang d  (cost=0.42..2028.20 rows=39410 width=17) (actual time=0.064..27.313 rows=39156 loops=1)
                                       Index Cond: ((ngay_dat >= '2026-10-01'::date) AND (ngay_dat < '2026-11-01'::date))
                                       Heap Fetches: 0
                                       Buffers: shared hit=236
 Planning Time: 0.607 ms
 Execution Time: 70.946 ms
```
- **Phân tích**:
  - Q8 tính doanh thu thuần theo ngày của tháng 10/2026, dùng hàm cửa sổ `SUM(...) OVER (PARTITION BY thang ORDER BY ngay)` để tính doanh thu lũy kế từ đầu tháng, và dùng thêm hàm cửa sổ `MIN(CASE WHEN luy_ke >= 1000000000 THEN ngay END) OVER (PARTITION BY thang)` để đánh dấu đúng **ngày đầu tiên trong tháng chạm mốc 1 tỷ VNĐ** (`la_ngay_dau_tien_vuot_1_ty = true`).
  - Nhờ dùng chung `idx_don_hang_dagiao_ngay_gh`, Q8 giảm số trang buffer từ **10.041** xuống **236** (**-97,6%**) và giảm thời gian trung vị từ **250,771 ms** xuống **70,946 ms** (**nhanh hơn 3,53 lần**).
  - **Ý nghĩa mốc 1 tỷ VNĐ trên 2 tập dữ liệu**:
    - Trên **`seed_nho.sql`** (161 đơn mẫu; hoặc khi chạy phần mở rộng **`Q8a`** với `d.ma_don_hang <= 161` ngay trên DB đã nạp `seed_lon.sql`), doanh thu lũy kế tăng dần qua 18 ngày đầu tháng và chạm mốc `1.000.000.000 VNĐ` vào đúng ngày **`2026-10-18`** (lũy kế đạt `1.055.280.000 VNĐ`).
    - Trên **`seed_lon.sql`** (`39.156` đơn `DaGiao` trong tháng 10/2026, trung bình `~39,2 tỷ VNĐ/ngày`), doanh thu thuần ngay ngày đầu tháng **`2026-10-01`** đã đạt `36.889.811.000 VNĐ` nên vượt mốc 1 tỷ VNĐ ngay tại `2026-10-01`. Trong [`queries.sql`](queries.sql), tham số `\set moc_q8 1000000000` được đặt mặc định đúng đề bài, đồng thời hỗ trợ đổi sang `\set moc_q8 500000000000` (500 tỷ VNĐ — chạm mốc vào ngày **`2026-10-13`** với lũy kế `507.619.222.500 VNĐ`) khi muốn trình diễn bước nhảy giữa tháng trên tập dữ liệu lớn.

---

### 4.4. Truy vấn Q2 — Chi tiết đơn hàng của khách hàng (10 dòng đầu)

**Trước khi tạo chỉ mục tối ưu (Khách `'Nguyễn Văn A'` — 265 đơn, Lần trung vị — `5,972 ms`, `shared hit=1401`):**
```text
 Limit  (cost=3731.28..3731.30 rows=10 width=87) (actual time=5.732..5.742 rows=10 loops=1)
   Buffers: shared hit=1401
   ->  Sort  (cost=3731.28..3736.27 rows=1997 width=87) (actual time=5.729..5.737 rows=10 loops=1)
         Sort Key: d.ngay_dat, d.ma_don_hang, s.ten_san_pham
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=1401
         ->  Hash Join  (cost=39.59..3688.12 rows=1997 width=87) (actual time=0.739..5.254 rows=623 loops=1)
               Hash Cond: (b.ma_san_pham = s.ma_san_pham)
               Buffers: shared hit=1401
               ->  Hash Join  (cost=29.04..3667.24 rows=1997 width=43) (actual time=0.571..4.679 rows=623 loops=1)
                     Hash Cond: (c.ma_bien_the = b.ma_bien_the)
                     Buffers: shared hit=1396
                     ->  Nested Loop  (cost=5.48..3638.41 rows=1997 width=33) (actual time=0.143..3.882 rows=623 loops=1)
                           Buffers: shared hit=1389
                           ->  Nested Loop  (cost=5.05..3137.30 rows=799 width=19) (actual time=0.122..1.682 rows=265 loops=1)
                                 Buffers: shared hit=325
                                 ->  Seq Scan on khach_hang k  (cost=0.00..155.57 rows=10 width=4) (actual time=0.021..0.860 rows=1 loops=1)
                                       Filter: ((ho_ten)::text = 'Nguyễn Văn A'::text)
                                       Rows Removed by Filter: 5005
                                       Buffers: shared hit=93
                                 ->  Bitmap Heap Scan on don_hang d  (cost=5.05..297.36 rows=81 width=23) (actual time=0.090..0.591 rows=265 loops=1)
                                       Recheck Cond: (k.ma_khach_hang = ma_khach_hang)
                                       Heap Blocks: exact=229
                                       Buffers: shared hit=232
                                       ->  Bitmap Index Scan on idx_don_hang_khach  (cost=0.00..5.03 rows=81 width=0) (actual time=0.049..0.049 rows=265 loops=1)
                                             Index Cond: (ma_khach_hang = k.ma_khach_hang)
                                             Buffers: shared hit=3
                           ->  Index Scan using chi_tiet_don_hang_pkey on chi_tiet_don_hang c  (cost=0.42..0.60 rows=3 width=18) (actual time=0.006..0.007 rows=2 loops=265)
                                 Index Cond: (ma_don_hang = d.ma_don_hang)
                                 Buffers: shared hit=1064
```

**Sau khi tạo `idx_khach_hang_ho_ten` & `idx_don_hang_khach_ngay` (Khách `'Nguyễn Văn A'` — 265 đơn, Lần trung vị — `2,735 ms`, `shared hit=1084`):**
```text
 Limit  (cost=695.13..695.15 rows=10 width=87) (actual time=2.575..2.582 rows=10 loops=1)
   Buffers: shared hit=1084
   ->  Sort  (cost=695.13..700.12 rows=1997 width=87) (actual time=2.574..2.579 rows=10 loops=1)
         Sort Key: d.ngay_dat, d.ma_don_hang, s.ten_san_pham
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=1084
         ->  Hash Join  (cost=39.32..651.97 rows=1997 width=87) (actual time=0.345..2.293 rows=623 loops=1)
               Hash Cond: (b.ma_san_pham = s.ma_san_pham)
               Buffers: shared hit=1084
               ->  Hash Join  (cost=28.77..631.09 rows=1997 width=43) (actual time=0.245..1.963 rows=623 loops=1)
                     Hash Cond: (c.ma_bien_the = b.ma_bien_the)
                     Buffers: shared hit=1079
                     ->  Nested Loop  (cost=5.21..602.26 rows=1997 width=33) (actual time=0.042..1.514 rows=623 loops=1)
                           Buffers: shared hit=1072
                           ->  Nested Loop  (cost=4.78..101.15 rows=799 width=19) (actual time=0.032..0.119 rows=265 loops=1)
                                 Buffers: shared hit=8
                                 ->  Bitmap Heap Scan on khach_hang k  (cost=4.36..34.65 rows=10 width=4) (actual time=0.012..0.014 rows=1 loops=1)
                                       Recheck Cond: ((ho_ten)::text = 'Nguyễn Văn A'::text)
                                       Heap Blocks: exact=1
                                       Buffers: shared hit=3
                                       ->  Bitmap Index Scan on idx_khach_hang_ho_ten  (cost=0.00..4.36 rows=10 width=0) (actual time=0.008..0.009 rows=1 loops=1)
                                             Index Cond: ((ho_ten)::text = 'Nguyễn Văn A'::text)
                                             Buffers: shared hit=2
                                 ->  Index Only Scan using idx_don_hang_khach_ngay on don_hang d  (cost=0.42..5.84 rows=81 width=23) (actual time=0.017..0.064 rows=265 loops=1)
                                       Index Cond: (ma_khach_hang = k.ma_khach_hang)
                                       Heap Fetches: 0
                                       Buffers: shared hit=5
                           ->  Index Scan using chi_tiet_don_hang_pkey on chi_tiet_don_hang c  (cost=0.42..0.60 rows=3 width=18) (actual time=0.004..0.005 rows=2 loops=265)
                                 Index Cond: (ma_don_hang = d.ma_don_hang)
                                 Buffers: shared hit=1064
```
- **Phân tích**:
  - Bước tìm khách hàng `'Nguyễn Văn A'` chuyển từ `Seq Scan on khach_hang` (`93` trang) sang `Bitmap Index Scan on idx_khach_hang_ho_ten` (`3` trang).
  - Bước lấy danh sách đơn hàng của khách chuyển từ `Bitmap Heap Scan on don_hang` (`232` trang) sang `Index Only Scan using idx_don_hang_khach_ngay` (`Heap Fetches: 0`, `5` trang). Tổng số trang chạm trên hai bảng `khach_hang + don_hang` giảm từ **325** xuống **8** trang (**-97,5%**).
  - Với khách hàng ít đơn như `'Lê Minh Cường'` (`43` đơn) và `'Vũ Quang Phúc'` (`31` đơn), tổng số trang chạm trên `khach_hang + don_hang` cũng giảm từ **107 trang** (`93 + 14`) và **106 trang** (`93 + 13`) xuống chỉ còn **7 trang** (`3 + 4`, `Heap Fetches: 0`), tổng buffers toàn truy vấn giảm từ `291` xuống `191` (với `'Lê Minh Cường'`) và từ `242` xuống `143` (với `'Vũ Quang Phúc'`).

---

## 5. Phân tích chuyên sâu các trường hợp Index KHÔNG giúp được hoặc ảnh hưởng chéo giữa các truy vấn

### 5.1. Q1 — Vì sao có `idx_danh_gia_bien_the_sao` nhưng Planner vẫn chọn `Seq Scan on danh_gia`?
- **Hiện tượng**: Khi thử tạo covering index `idx_danh_gia_bien_the_sao ON danh_gia(ma_bien_the) INCLUDE (so_sao, ma_danh_gia)` và chạy `VACUUM ANALYZE danh_gia`, kế hoạch thực thi của Q1 vẫn giữ nguyên `Seq Scan on danh_gia` (`1.729` trang heap, tổng `1.744` buffers).
- **Nguyên nhân kỹ thuật**:
  1. **Ước lượng số dòng của CTE đệ quy (`WITH RECURSIVE cay`)**: Biểu thức đệ quy không có thống kê histogram tĩnh nên planner ước lượng `CTE Scan on cay` trả về `rows=51` (thực tế nhánh `'Điện thoại'` có `2` danh mục), kéo theo ước lượng phép nối trả về toàn bộ `736` biến thể và `110.914` dòng đánh giá.
  2. **Độ chọn lọc thực tế vẫn lớn (25,1% bảng)**: Ngay cả trong thực tế, nhánh `'Điện thoại'` có `187 / 736` biến thể (`25,4%`) và khớp với `27.894 / 110.914` dòng đánh giá (`25,1%`). Khi cần đọc hơn 1/4 số dòng của một bảng chỉ rộng `1.729` trang (14 MB), việc quét tuần tự (`Seq Scan`) kết hợp `Hash Join` hiệu quả hơn việc lặp 187 vòng `Nested Loop + Index Scan`. Vì vậy nhóm không đưa chỉ mục này vào `index_toi_uu.sql`.

### 5.2. Q5 — Vì sao `idx_ton_kho_bien_the_inc` không được sử dụng?
- **Hiện tượng**: Planner giữ nguyên `Seq Scan on ton_kho` (`40` trang) và `Seq Scan on bien_the` (`7` trang), tổng cộng `99` buffers.
- **Nguyên nhân kỹ thuật**: Q5 tính tổng tồn kho của **tất cả** danh mục gốc (không có mệnh đề `WHERE` lọc theo kho hay biến thể). Khi truy vấn cần đọc 100% số dòng của `ton_kho` (`3.680` dòng gói gọn trong `40` trang 8KB), đọc tuần tự 40 trang heap rồi `Hash Join` luôn rẻ hơn việc duyệt cây B-tree.

### 5.3. Q6 — Vì sao `idx_khach_hang_ngay_dk` không được sử dụng?
- **Hiện tượng**: Planner giữ nguyên `Seq Scan on khach_hang k` (`93` trang) kết hợp `Index Only Scan using idx_don_hang_khach` (`14.938` trang, `Heap Fetches: 0`, tổng `15.031` buffers).
- **Nguyên nhân kỹ thuật**: Điều kiện `k.ngay_dang_ky < CURRENT_DATE - INTERVAL '1 year'` khớp tới **4.979 / 5.006 khách hàng (99,46%)**, chỉ loại bỏ 27 khách mới đăng ký. Với độ chọn lọc lấy 99,46% bảng, `Seq Scan` trên 93 trang (`cost=180.61`) luôn rẻ hơn đọc index rồi quay lại đọc gần như toàn bộ 93 trang heap. Trong khi đó, chỉ mục khóa ngoại `idx_don_hang_khach` có sẵn trong `schema.sql` đã giúp phép `Nested Loop Anti Join` (`NOT EXISTS`) đạt `Index Only Scan` với `Heap Fetches = 0`.

### 5.4. Q7 — Vì sao thêm `idx_bien_the_sp_giaban` lại làm tăng số trang buffer chạm từ 23 lên 739?
- **Hiện tượng thực nghiệm**:
  - **Khi không có `idx_bien_the_sp_giaban` (trạng thái giữ lại trong `index_toi_uu.sql`)**: Truy vấn dùng `Nested Loop` + `Seq Scan on bien_the b` kết hợp `Materialize -> Hash Join` trong `SubPlan 1`, chạm tổng cộng đúng **23 buffers** (trung vị **0,342 ms**).
  - **Khi thử tạo `idx_bien_the_sp_giaban ON bien_the(ma_san_pham, gia_ban DESC)`**: Truy vấn con `SubPlan 1` đổi sang `Index Only Scan using idx_bien_the_sp_giaban`, làm giảm nhẹ ước lượng cost của `SubPlan 1`. Sự thay đổi ước lượng này khiến planner đổi kế hoạch ngoài từ `Hash Join / Seq Scan` sang `Merge Join` theo thứ tự `ma_san_pham` bằng cách quét `Index Scan using idx_bien_the_san_pham on bien_the b`, dẫn đến việc truy cập lặp lại các trang của `bien_the` và `SubPlan 1` tới **739 buffers** (`0,618 ms`).
- **Quyết định**: Loại bỏ `idx_bien_the_sp_giaban` khỏi `index_toi_uu.sql` để giữ kế hoạch `23 buffers`.

### 5.5. Phân tích thực nghiệm thứ tự cột chỉ mục Q4: `idx_don_hang_gh_ngay_tt (ma_gian_hang, ngay_dat)` so với `idx_don_hang_ngay_gh_tt (ngay_dat, ma_gian_hang)` và tác động nghiêm trọng lên Q2

Đây là phát hiện quan trọng nhất khi đồng bộ `index_toi_uu.sql`, `bench_truoc.sql`, `bench_sau.sql` và `bang_do.md`. Nhóm đã chạy thực nghiệm đối chứng trực tiếp hai phương án thứ tự cột cho chỉ mục phục vụ Q4:
- **Phương án A (Đã chọn trong `index_toi_uu.sql`)**: `idx_don_hang_gh_ngay_tt ON don_hang(ma_gian_hang, ngay_dat) INCLUDE (trang_thai)`
- **Phương án B (Đảo cột `ngay_dat` lên đầu)**: `idx_don_hang_ngay_gh_tt ON don_hang(ngay_dat, ma_gian_hang) INCLUDE (trang_thai)`

**Bảng kết quả đo đối chứng trực tiếp trên cùng CSDL `ecom` (`400.161` đơn):**

| Kịch bản truy vấn | Phương án A: `idx_don_hang_gh_ngay_tt (ma_gian_hang, ngay_dat)` | Phương án B: `idx_don_hang_ngay_gh_tt (ngay_dat, ma_gian_hang)` | Đánh giá so sánh |
|---|---|---|---|
| **Q4** (Tỷ lệ hủy đơn tháng 10/2026 theo gian hàng) | `GroupAggregate` + `Nested Loop` + `Index Only Scan (idx_don_hang_gh_ngay_tt)`: **18,491 ms** (`shared hit=354`, `Heap Fetches=0`) | `HashAggregate` + `Hash Join` + `Index Only Scan (idx_don_hang_ngay_gh_tt)`: **22,702 – 23,772 ms** (`shared hit=283`, `Heap Fetches=0`) | Phương án A nhanh hơn (`18,49 ms` vs `22,70 ms`) vì dữ liệu ra khỏi index đã có sẵn thứ tự `ma_gian_hang` cho `GroupAggregate`. |
| **Q2 — Khách `'Nguyễn Văn A'`** (265 đơn, đơn đầu ngày `2025-12-01`) | `Bitmap Index Scan (idx_khach_hang_ho_ten)` $\rightarrow$ `Index Only Scan (idx_don_hang_khach_ngay)`: **2,735 ms**, đọc đúng **265 dòng `don_hang`**, tổng **`1.084` buffers** (`khach_hang + don_hang` = **8 buffers**) | `Incremental Sort` $\rightarrow$ `Index Scan using idx_don_hang_ngay_gh_tt on don_hang`: **5,404 ms**, quét **418 dòng `don_hang`** từ đầu năm để gom đủ 10 dòng chi tiết, tổng **`1.172` buffers** | Phương án B làm planner bỏ `idx_don_hang_khach_ngay` và quét mò `don_hang` theo ngày đặt! |
| **Q2 — Khách `'Lê Minh Cường'`** (43 đơn, đơn đầu tiên rơi vào giữa năm) | `Bitmap Index Scan (idx_khach_hang_ho_ten)` $\rightarrow$ `Index Only Scan (idx_don_hang_khach_ngay)`: **1,235 ms**, đọc đúng **43 dòng `don_hang`**, tổng **`191` buffers** (`khach_hang + don_hang` = **7 buffers**) | `Incremental Sort` $\rightarrow$ `Index Scan using idx_don_hang_ngay_gh_tt on don_hang`: **299,845 ms**, quét tới **287.245 dòng `don_hang`** và chạm **`303.569` buffers** (`288.634` trang `don_hang` + `14.844` trang `khach_hang_pkey`)! | **Phương án B gây thoái hóa nghiêm trọng (chậm hơn 242 lần, đọc hơn 303 nghìn trang)** với khách ít đơn hoặc mới mua gần đây! |

**Cây kế hoạch bằng chứng khi dùng Phương án B (`idx_don_hang_ngay_gh_tt`) với khách `'Lê Minh Cường'` (`299,845 ms`, `303.569` buffers):**
```text
 Limit  (cost=171.60..609.02 rows=10 width=87) (actual time=133.903..299.811 rows=10 loops=1)
   Buffers: shared hit=303569
   ->  Incremental Sort  (cost=171.60..87525.73 rows=1997 width=87) (actual time=133.902..299.809 rows=10 loops=1)
         Sort Key: d.ngay_dat, d.ma_don_hang, s.ten_san_pham
         Presorted Key: d.ngay_dat
         Full-sort Groups: 1  Sort Method: quicksort  Average Memory: 26kB  Peak Memory: 26kB
         Buffers: shared hit=303569
         ->  Nested Loop  (cost=1.28..87451.78 rows=1997 width=87) (actual time=133.854..299.786 rows=11 loops=1)
               Buffers: shared hit=303569
               ->  Nested Loop  (cost=0.86..86961.99 rows=799 width=19) (actual time=133.835..299.729 rows=5 loops=1)
                     Buffers: shared hit=303478
                     ->  Index Scan using idx_don_hang_ngay_gh_tt on don_hang d  (cost=0.42..55250.33 rows=400161 width=23) (actual time=0.025..198.268 rows=287245 loops=1)
                           Buffers: shared hit=288634
                     ->  Memoize  (cost=0.43..0.52 rows=1 width=4) (actual time=0.000..0.000 rows=0 loops=287245)
                           Cache Key: d.ma_khach_hang
                           Hits: 282300  Misses: 4945  Evictions: 0  Overflows: 0  Memory Usage: 348kB
                           Buffers: shared hit=14844
                           ->  Index Scan using khach_hang_pkey on khach_hang k  (cost=0.42..0.51 rows=1 width=4) (actual time=0.002..0.002 rows=0 loops=4945)
                                 Index Cond: (ma_khach_hang = d.ma_khach_hang)
                                 Filter: ((ho_ten)::text = 'Lê Minh Cường'::text)
                                 Rows Removed by Filter: 1
                                 Buffers: shared hit=14844
```
- **Giải thích nguyên nhân**: Ở Q2 (`WHERE k.ho_ten = ... ORDER BY d.ngay_dat, d.ma_don_hang, s.ten_san_pham LIMIT 10`), cột `ho_ten` không có ràng buộc `UNIQUE` nên planner ước lượng `rows=10` khách hàng trùng tên (`799` đơn hàng, `1.997` dòng chi tiết) và giả định các đơn này phân bố đều từ đầu năm. Khi thấy `idx_don_hang_ngay_gh_tt` có cột đầu là `ngay_dat` khớp với khóa sắp xếp `ORDER BY d.ngay_dat`, planner tưởng rằng chỉ cần quét vài nghìn dòng đầu của `idx_don_hang_ngay_gh_tt` (`cost=171.60..609.02` cho `LIMIT 10`) là sẽ gặp đủ 10 dòng của khách! Thực tế chỉ có 1 khách `'Lê Minh Cường'` và các đơn của khách này nằm ở nửa cuối kỳ dữ liệu, khiến PostgreSQL phải quét tuần tự **287.245 dòng `don_hang`** theo index (`288.634` trang heap/index) trước khi gom đủ 10 dòng chi tiết đơn hàng.
- **Kết luận thiết kế**: Chọn **`idx_don_hang_gh_ngay_tt ON don_hang(ma_gian_hang, ngay_dat) INCLUDE (trang_thai)`** trong [`index_toi_uu.sql`](index_toi_uu.sql) là quyết định chính xác tuyệt đối vì vừa tối ưu `GroupAggregate` cho Q4 (`18,491 ms`), vừa giữ cho Q2 luôn đi theo đường `idx_khach_hang_ho_ten` $\rightarrow$ `idx_don_hang_khach_ngay` (`Index Only Scan`, chỉ tốn `7–8` buffers cho `khach_hang + don_hang` với mọi khách hàng).

---

## 6. Kết luận & Quy trình tái lập kết quả đo / Reset dữ liệu sạch

### 6.1. Tóm tắt hiệu quả của 4 chỉ mục khuyến nghị trong `index_toi_uu.sql`
1. **Giảm mạnh khối lượng trang bộ nhớ (Buffers) và thời gian chạy trên bảng lớn (`don_hang` — 400.161 dòng)**:
   - **Q4**: từ **238,769 ms** (`9.990` buffers) xuống **18,491 ms** (`354` buffers) — **nhanh hơn 12,91 lần, giảm 96,5% buffers**.
   - **Q3**: từ **231,818 ms** (`9.968` buffers) xuống **20,161 ms** (`237` buffers) — **nhanh hơn 11,50 lần, giảm 97,6% buffers**.
   - **Q8**: từ **250,771 ms** (`10.041` buffers) xuống **70,946 ms** (`236` buffers) — **nhanh hơn 3,53 lần, giảm 97,6% buffers**.
   - **Q2**: từ **5,972 ms** (`1.401` buffers; `325` buffers trên `khach_hang + don_hang`) xuống **2,735 ms** (`1.084` buffers; **`8` buffers** trên `khach_hang + don_hang`) — **nhanh hơn 2,18 lần, giảm 97,5% buffers tìm khách và đơn hàng**.
2. **Bảo toàn tính gọn nhẹ của bộ chỉ mục**: Chỉ giữ lại đúng **4 chỉ mục thực sự có tác dụng** (tổng dung lượng ~48 MB), loại bỏ 4 chỉ mục thử nghiệm dư thừa trên `danh_gia`, `ton_kho`, `khach_hang(ngay_dang_ky)` và `bien_the`.

### 6.2. Lệnh chạy lại toàn bộ phép đo và khôi phục trạng thái sạch trước buổi bảo vệ
- **Chạy lại phép đo trước và sau tối ưu**:
  ```bash
  psql -d ecom -f bench_truoc.sql > ket_qua_bench_truoc.txt
  psql -d ecom -f index_toi_uu.sql
  psql -d ecom -f bench_sau.sql > ket_qua_bench_sau.txt
  ```
- **Khôi phục CSDL `ecom` về trạng thái sạch chuẩn trước khi trình diễn**:
  - Chế độ dữ liệu mẫu gọn (`161` đơn, nạp trong ~2 giây):
    ```bash
    dropdb --if-exists ecom && createdb ecom
    psql -d ecom -v ON_ERROR_STOP=1 -f schema.sql
    psql -d ecom -v ON_ERROR_STOP=1 -f seed_nho.sql
    psql -d ecom -v ON_ERROR_STOP=1 -f kiem_tra_cheo.sql
    ```
  - Chế độ dữ liệu lớn đầy đủ (`400.161` đơn + bộ chỉ mục tối ưu, phục vụ cả Web Dashboard và `Q1..Q8`):
    ```bash
    psql -d ecom -v ON_ERROR_STOP=1 -f seed_lon.sql
    psql -d ecom -v ON_ERROR_STOP=1 -f index_toi_uu.sql
    ```
