# Thiết kế CSDL: Sàn Thương mại Điện tử Đa kênh & Kho Thông minh

Hệ quản trị: PostgreSQL 14+. Tài liệu đi kèm: `schema.sql` (tạo CSDL), `seed_nho.sql` (dữ liệu mẫu), `erd.dbml` (dán vào dbdiagram.io), `erd.png` (sơ đồ thực thể quan hệ).

## 1. Giả định và quyết định thiết kế

Các giả định dưới đây nên ghi nguyên văn vào báo cáo để giảng viên biết nhóm hiểu đề như thế nào.

1. **Mỗi đơn hàng thuộc đúng một gian hàng**, và mọi dòng hàng trong đơn phải thuộc gian hàng đó (được ép bằng trigger `trg_kiem_tra_chi_tiet`).
2. **Mỗi đơn xuất từ một kho** (`don_hang.ma_kho_xuat`), kho do hệ thống chỉ định. Chưa tách một dòng hàng ra nhiều kho.
3. **Đa kênh** thể hiện ở ba chiều: nhiều gian hàng, nhiều kho, và cột `kenh_ban` (Web / CuaHang / DoiTac).
4. **Tồn kho tách hai số liệu**: `so_luong_vat_ly` (hàng thực tế trong kho) và `so_luong_giu` (đã giữ cho đơn chưa xuất). Tồn khả dụng = vật lý - giữ (view `v_ton_kha_dung`).
5. **Hiểu yêu cầu "tồn kho giảm khi đơn sang DaXacNhan"**: khi đơn sang `DaXacNhan`, hệ thống *giữ hàng* nên **tồn khả dụng giảm ngay**; tồn vật lý giảm khi hàng được xuất (đơn sang `DangGiao`). Nếu giảng viên muốn tồn vật lý giảm ngay tại `DaXacNhan`, chỉ cần đổi trigger, không đổi bảng.
6. **Vòng đời đơn**: `ChoXacNhan` → `DaXacNhan` → `DangGiao` → `DaGiao`; được phép hủy (`DaHuy`) từ ba trạng thái đầu. Đề ghi trạng thái hủy là `'Cancelled'`; thiết kế này dùng `DaHuy` cho đồng bộ tiếng Việt, truy vấn 4 dùng giá trị này.
7. **Doanh thu thuần** = `tong_tien_hang - tien_giam`, không gồm phí vận chuyển, và chỉ tính các đơn `DaGiao`.
8. **Snapshot**: giá bán, tổng tiền, tiền giảm và thông tin nhận hàng được chụp lại tại thời điểm đặt, để việc đổi giá hay đổi địa chỉ về sau không làm sai đơn cũ.
9. **Tiền tệ** dùng `NUMERIC(14,0)` (VNĐ không có phần lẻ), không dùng số thực.
10. **Danh mục phân cấp** nhiều tầng bằng khóa ngoại tự tham chiếu; truy vấn dùng `WITH RECURSIVE` để gom cả cây con.
11. **Kỳ dữ liệu mô phỏng (Deterministic Simulation Period)**:
    - Tập dữ liệu mẫu nhỏ (`seed_nho.sql`, 161 đơn hàng) tập trung trong tháng `10/2026` để kiểm chứng từng truy vấn Q1–Q8.
    - Tập dữ liệu lớn (`seed_lon.sql`, 400.161 đơn hàng) là tập dữ liệu mô phỏng cố định và tái lập được 100% (`deterministic seed`), trải dài trọn vẹn 12 tháng từ `2025-12-01` đến hết ngày chốt kỳ mô phỏng `2026-11-30 23:59:59` (gồm các cao điểm mùa vụ tháng 10/2026 và 11.11/2026). Do đây là kỳ mô phỏng cố định kết thúc vào `30/11/2026`, các mốc ngày trong khoảng `13/11/2026 – 30/11/2026` thuộc nửa cuối tháng 11 của kỳ mô phỏng 12 tháng chứ không phải lỗi đồng hồ hệ thống. Dashboard và báo cáo hiển thị rõ ngày chốt kỳ mô phỏng này (`30/11/2026`).

## 2. Thực thể và quan hệ

| Quan hệ | Bản số | Cài đặt |
|---|---|---|
| danh_muc – danh_muc | 1 – N (cha – con) | `danh_muc.ma_danh_muc_cha` |
| danh_muc – san_pham | 1 – N | `san_pham.ma_danh_muc` |
| gian_hang – san_pham | 1 – N | `san_pham.ma_gian_hang` |
| nha_cung_cap – san_pham | 1 – N | `san_pham.ma_ncc` |
| san_pham – bien_the | 1 – N | `bien_the.ma_san_pham` |
| kho – bien_the | N – M | bảng nối `ton_kho` |
| ton_kho – bien_dong_kho | 1 – N | khóa ngoại ghép (ma_kho, ma_bien_the) |
| khach_hang – don_hang | 1 – N | `don_hang.ma_khach_hang` |
| gian_hang – don_hang | 1 – N | `don_hang.ma_gian_hang` |
| kho – don_hang | 1 – N | `don_hang.ma_kho_xuat` |
| voucher – don_hang | 1 – N (đơn có thể không dùng voucher) | `don_hang.ma_voucher` (null được) |
| gian_hang – voucher | 1 – N (null = voucher của sàn) | `voucher.ma_gian_hang` |
| don_hang – bien_the | N – M | bảng nối `chi_tiet_don_hang` |
| don_hang – lich_su_trang_thai | 1 – N | `lich_su_trang_thai.ma_don_hang` |
| don_hang – thanh_toan | 1 – N | `thanh_toan.ma_don_hang` |
| don_hang – van_chuyen | 1 – 0..1 | `van_chuyen.ma_don_hang` (UNIQUE) |
| chi_tiet_don_hang – danh_gia | 1 – 0..1 | khóa ngoại ghép (ma_don_hang, ma_bien_the), UNIQUE |
| don_hang – bien_dong_kho | 1 – N | `bien_dong_kho.ma_don_hang` |

## 3. Yêu cầu của đề và cơ chế thực hiện trong CSDL

| Yêu cầu của đề | Cơ chế | Tên trong schema |
|---|---|---|
| `GiaBan > GiaNhap` | CHECK | `ck_gia_ban_lon_hon_gia_nhap` (bảng `bien_the`) |
| `PhanTramGiamGia` trong [1, 100] | CHECK | `ck_voucher_phan_tram` (bảng `voucher`) |
| `SoLuongTonKho >= 0` | CHECK | `ck_ton_vat_ly_khong_am`, thêm `ck_ton_giu_khong_am` và `ck_giu_khong_vuot_vat_ly` |
| Mã SKU duy nhất | UNIQUE | `uq_bien_the_sku` |
| (MaDonHang, MaBienThe) duy nhất trong chi tiết đơn | PRIMARY KEY ghép | khóa chính của `chi_tiet_don_hang` |
| Voucher chỉ áp dụng khi tổng tiền >= tối thiểu và ngày dùng <= ngày hết hạn | Trigger | `trg_kiem_tra_voucher` |
| Chỉ ghi nhận đánh giá khi đơn `DaGiao` | Trigger | `trg_kiem_tra_danh_gia` |
| Tồn kho giảm tương ứng khi đơn sang `DaXacNhan` | Trigger (cập nhật có điều kiện, nguyên tử) | `trg_cap_nhat_ton_kho` |

Các trigger và ràng buộc bổ sung do thiết kế thêm vào:

| Bảng | Trigger | Hàm |
|---|---|---|
| bien_dong_kho | `trg_khong_sua_so_cai` | `fn_khong_sua_so_cai()` |
| chi_tiet_don_hang | `trg_kiem_tra_chi_tiet` | `fn_kiem_tra_chi_tiet()` |
| danh_gia | `trg_kiem_tra_danh_gia` | `fn_kiem_tra_danh_gia()` |
| don_hang | `trg_cap_nhat_ton_kho` | `fn_cap_nhat_ton_kho()` |
| don_hang | `trg_chuyen_trang_thai` | `fn_chuyen_trang_thai()` |
| don_hang | `trg_kiem_tra_voucher` | `fn_kiem_tra_voucher()` |

Ngoài ra có hai chỉ mục duy nhất một phần trên sổ cái: `uq_bien_dong_giu_1_lan` và `uq_bien_dong_xuat_1_lan`, bảo đảm mỗi dòng hàng chỉ được giữ một lần và xuất một lần dù yêu cầu bị gửi lặp.

Các chỉ mục khóa ngoại và tra cứu cơ bản được tạo sẵn trong `schema.sql` gồm:
- `idx_san_pham_gian_hang`, `idx_san_pham_danh_muc`, `idx_san_pham_ncc`, `idx_bien_the_san_pham`, `idx_ton_kho_bien_the`
- `idx_bien_dong_kho_bt_thoi_diem`, `idx_bien_dong_don_hang`
- `idx_don_hang_khach`, `idx_don_hang_gian_hang`, `idx_don_hang_ngay_dat`, `idx_chi_tiet_bien_the`
- `idx_lich_su_tt_don ON lich_su_trang_thai(ma_don_hang)` và `idx_thanh_toan_don ON thanh_toan(ma_don_hang)`: hỗ trợ tra cứu lịch sử trạng thái/thanh toán theo đơn hàng và tránh quét tuần tự (`Seq Scan`) bảng con hơn 1 triệu dòng khi kiểm tra khóa ngoại (`ON DELETE CASCADE`) trên `don_hang`.
- Hàm nghiệp vụ `fn_nhap_kho` và `fn_tao_don_hang` (kèm kiểm tra đầu vào nghiêm ngặt và khóa tư vấn giao dịch `pg_advisory_xact_lock` theo `(ma_khach_hang, idempotency_key)` để chống tạo đơn trùng đồng thời) được định nghĩa tập trung ngay trong `schema.sql`.


## 4. Từ điển dữ liệu

Phần này được **sinh tự động từ chính CSDL** (kiểu dữ liệu, NOT NULL, giá trị mặc định, ràng buộc lấy từ `pg_catalog`), nên luôn khớp với `schema.sql`. Có 16 bảng, 98 cột.

### danh_muc

Danh mục sản phẩm phân cấp nhiều tầng (tự tham chiếu qua ma_danh_muc_cha; NULL = danh mục cấp 1).

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_danh_muc** | integer | có |  | Khóa chính |
| ten_danh_muc | varchar(100) | có |  | Tên danh mục |
| ma_danh_muc_cha | integer |  |  | Danh mục cha; NULL nếu là cấp 1 |

Ràng buộc:

- **CHECK** `ck_danh_muc_khong_tu_cha`: `CHECK (((ma_danh_muc_cha IS NULL) OR (ma_danh_muc_cha <> ma_danh_muc)))`
- **FK** `danh_muc_ma_danh_muc_cha_fkey`: `FOREIGN KEY (ma_danh_muc_cha) REFERENCES danh_muc(ma_danh_muc) ON DELETE RESTRICT`
- **PK** `danh_muc_pkey`: `PRIMARY KEY (ma_danh_muc)`
- **UNIQUE** `uq_danh_muc_cha_ten`: `UNIQUE (ma_danh_muc_cha, ten_danh_muc)`

### nha_cung_cap

Nhà cung cấp hàng hóa (nguồn nhập), khác với gian hàng là bên bán trên sàn.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_ncc** | integer | có |  | Khóa chính |
| ten_ncc | varchar(150) | có |  | Tên nhà cung cấp (duy nhất) |
| dien_thoai | varchar(20) |  |  | Số điện thoại liên hệ |
| dia_chi | varchar(255) |  |  | Địa chỉ |

Ràng buộc:

- **PK** `nha_cung_cap_pkey`: `PRIMARY KEY (ma_ncc)`
- **UNIQUE** `nha_cung_cap_ten_ncc_key`: `UNIQUE (ten_ncc)`

### gian_hang

Gian hàng (Seller) bán sản phẩm trên sàn.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_gian_hang** | integer | có |  | Khóa chính |
| ten_gian_hang | varchar(150) | có |  | Tên gian hàng (duy nhất) |
| email | varchar(150) | có |  | Email liên hệ (duy nhất) |
| ngay_tham_gia | date | có | `CURRENT_DATE` | Ngày gian hàng tham gia sàn |

Ràng buộc:

- **PK** `gian_hang_pkey`: `PRIMARY KEY (ma_gian_hang)`
- **UNIQUE** `gian_hang_email_key`: `UNIQUE (email)`
- **UNIQUE** `gian_hang_ten_gian_hang_key`: `UNIQUE (ten_gian_hang)`

### san_pham

Sản phẩm (mô tả chung); giá và tồn kho nằm ở biến thể.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_san_pham** | integer | có |  | Khóa chính |
| ma_gian_hang | integer | có |  | Gian hàng bán sản phẩm |
| ma_danh_muc | integer | có |  | Danh mục của sản phẩm |
| ma_ncc | integer | có |  | Nhà cung cấp của sản phẩm |
| ten_san_pham | varchar(200) | có |  | Tên sản phẩm |
| mo_ta | text |  |  | Mô tả |
| ngay_tao | timestamp | có | `now()` | Thời điểm tạo |

Ràng buộc:

- **FK** `san_pham_ma_danh_muc_fkey`: `FOREIGN KEY (ma_danh_muc) REFERENCES danh_muc(ma_danh_muc)`
- **FK** `san_pham_ma_gian_hang_fkey`: `FOREIGN KEY (ma_gian_hang) REFERENCES gian_hang(ma_gian_hang)`
- **FK** `san_pham_ma_ncc_fkey`: `FOREIGN KEY (ma_ncc) REFERENCES nha_cung_cap(ma_ncc)`
- **PK** `san_pham_pkey`: `PRIMARY KEY (ma_san_pham)`

### bien_the

Biến thể sản phẩm (SKU): màu sắc, kích cỡ, giá nhập, giá bán.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_bien_the** | integer | có |  | Khóa chính |
| ma_san_pham | integer | có |  | Sản phẩm mà biến thể thuộc về |
| sku | varchar(50) | có |  | Mã SKU, duy nhất toàn hệ thống |
| mau_sac | varchar(50) |  |  | Màu sắc |
| kich_co | varchar(30) |  |  | Kích cỡ / dung lượng |
| gia_nhap | numeric(14,0) | có |  | Giá nhập (VNĐ) |
| gia_ban | numeric(14,0) | có |  | Giá bán hiện hành (VNĐ), luôn lớn hơn giá nhập |

Ràng buộc:

- **CHECK** `bien_the_gia_nhap_check`: `CHECK ((gia_nhap >= (0)::numeric))`
- **CHECK** `ck_gia_ban_lon_hon_gia_nhap`: `CHECK ((gia_ban > gia_nhap))`
- **FK** `bien_the_ma_san_pham_fkey`: `FOREIGN KEY (ma_san_pham) REFERENCES san_pham(ma_san_pham) ON DELETE CASCADE`
- **PK** `bien_the_pkey`: `PRIMARY KEY (ma_bien_the)`
- **UNIQUE** `uq_bien_the_sku`: `UNIQUE (sku)`
- **UNIQUE** `uq_bien_the_thuoc_tinh`: `UNIQUE (ma_san_pham, mau_sac, kich_co)`

### kho

Kho hàng vật lý.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_kho** | integer | có |  | Khóa chính |
| ten_kho | varchar(100) | có |  | Tên kho (duy nhất) |
| tinh_tp | varchar(100) | có |  | Tỉnh/thành phố của kho |
| dia_chi | varchar(255) |  |  | Địa chỉ kho |

Ràng buộc:

- **PK** `kho_pkey`: `PRIMARY KEY (ma_kho)`
- **UNIQUE** `kho_ten_kho_key`: `UNIQUE (ten_kho)`

### ton_kho

Tồn kho hiện tại của từng biến thể tại từng kho: tồn vật lý và số đang giữ cho đơn.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_kho** | integer | có |  | Kho (thành phần khóa chính) |
| **ma_bien_the** | integer | có |  | Biến thể (thành phần khóa chính) |
| so_luong_vat_ly | integer | có | `0` | Số lượng thực tế đang có trong kho (on_hand) |
| so_luong_giu | integer | có | `0` | Số lượng đã giữ cho đơn đã xác nhận nhưng chưa xuất (reserved) |

Ràng buộc:

- **CHECK** `ck_giu_khong_vuot_vat_ly`: `CHECK ((so_luong_giu <= so_luong_vat_ly))`
- **CHECK** `ck_ton_giu_khong_am`: `CHECK ((so_luong_giu >= 0))`
- **CHECK** `ck_ton_vat_ly_khong_am`: `CHECK ((so_luong_vat_ly >= 0))`
- **FK** `ton_kho_ma_bien_the_fkey`: `FOREIGN KEY (ma_bien_the) REFERENCES bien_the(ma_bien_the)`
- **FK** `ton_kho_ma_kho_fkey`: `FOREIGN KEY (ma_kho) REFERENCES kho(ma_kho)`
- **PK** `ton_kho_pkey`: `PRIMARY KEY (ma_kho, ma_bien_the)`

### bien_dong_kho

Sổ cái biến động kho, chỉ thêm, không sửa/xóa; mỗi lần nhập, giữ, xuất, hoàn đều có dòng.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_bien_dong** | bigint | có |  | Khóa chính |
| ma_kho | integer | có |  | Kho phát sinh biến động |
| ma_bien_the | integer | có |  | Biến thể bị biến động |
| loai | varchar(12) | có |  | NHAP, GIU, NHA_GIU, XUAT, HOAN hoặc DIEU_CHINH |
| delta_vat_ly | integer | có | `0` | Thay đổi của tồn vật lý (âm là giảm) |
| delta_giu | integer | có | `0` | Thay đổi của số đang giữ (âm là giảm) |
| ma_don_hang | integer |  |  | Đơn gây ra biến động; NULL với nhập kho và điều chỉnh |
| ly_do | varchar(200) |  |  | Ghi chú lý do |
| thoi_diem | timestamp | có | `now()` | Thời điểm ghi sổ |

Ràng buộc:

- **CHECK** `ck_bien_dong_khac_khong`: `CHECK (((delta_vat_ly <> 0) OR (delta_giu <> 0)))`
- **CHECK** `ck_bien_dong_loai`: `CHECK (((loai)::text = ANY ((ARRAY['NHAP'::character varying, 'GIU'::character varying, 'NHA_GIU'::character varying, 'XUAT'::character varying, 'HOAN'::character varying, 'DIEU_CHINH'::character varying])::text[])))`
- **FK** `bien_dong_kho_ma_kho_ma_bien_the_fkey`: `FOREIGN KEY (ma_kho, ma_bien_the) REFERENCES ton_kho(ma_kho, ma_bien_the)`
- **FK** `fk_bien_dong_don_hang`: `FOREIGN KEY (ma_don_hang) REFERENCES don_hang(ma_don_hang)`
- **PK** `bien_dong_kho_pkey`: `PRIMARY KEY (ma_bien_dong)`
- **UNIQUE (một phần)** `uq_bien_dong_giu_1_lan`: `bien_dong_kho USING btree (ma_don_hang, ma_bien_the) WHERE ((loai)::text = 'GIU'::text)`
- **UNIQUE (một phần)** `uq_bien_dong_xuat_1_lan`: `bien_dong_kho USING btree (ma_don_hang, ma_bien_the) WHERE ((loai)::text = 'XUAT'::text)`

### khach_hang

Khách hàng mua hàng.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_khach_hang** | integer | có |  | Khóa chính |
| ho_ten | varchar(100) | có |  | Họ tên |
| email | varchar(150) | có |  | Email (duy nhất) |
| dien_thoai | varchar(20) |  |  | Số điện thoại |
| dia_chi | varchar(255) |  |  | Địa chỉ giao hàng mặc định |
| ngay_dang_ky | date | có | `CURRENT_DATE` | Ngày đăng ký tài khoản |

Ràng buộc:

- **PK** `khach_hang_pkey`: `PRIMARY KEY (ma_khach_hang)`
- **UNIQUE** `khach_hang_email_key`: `UNIQUE (email)`

### voucher

Mã giảm giá theo phần trăm, của sàn hoặc của một gian hàng.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_voucher** | integer | có |  | Khóa chính |
| ma_code | varchar(30) | có |  | Mã nhập khi áp dụng (duy nhất) |
| ma_gian_hang | integer |  |  | Gian hàng áp dụng; NULL là voucher của sàn |
| phan_tram_giam | integer | có |  | Phần trăm giảm, từ 1 đến 100 |
| gia_tri_toi_thieu | numeric(14,0) | có | `0` | Giá trị đơn tối thiểu để áp dụng (VNĐ) |
| giam_toi_da | numeric(14,0) |  |  | Mức giảm tối đa (VNĐ); NULL là không giới hạn |
| ngay_bat_dau | date | có |  | Ngày bắt đầu hiệu lực |
| ngay_het_han | date | có |  | Ngày hết hạn |

Ràng buộc:

- **CHECK** `ck_voucher_gia_tri_min`: `CHECK ((gia_tri_toi_thieu >= (0)::numeric))`
- **CHECK** `ck_voucher_ngay`: `CHECK ((ngay_het_han >= ngay_bat_dau))`
- **CHECK** `ck_voucher_phan_tram`: `CHECK (((phan_tram_giam >= 1) AND (phan_tram_giam <= 100)))`
- **FK** `voucher_ma_gian_hang_fkey`: `FOREIGN KEY (ma_gian_hang) REFERENCES gian_hang(ma_gian_hang)`
- **PK** `voucher_pkey`: `PRIMARY KEY (ma_voucher)`
- **UNIQUE** `voucher_ma_code_key`: `UNIQUE (ma_code)`

### don_hang

Đơn hàng: mỗi đơn thuộc đúng một gian hàng, xuất từ một kho; lưu snapshot nhận hàng và số tiền.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_don_hang** | integer | có |  | Khóa chính |
| ma_khach_hang | integer | có |  | Khách đặt đơn |
| ma_gian_hang | integer | có |  | Gian hàng nhận đơn |
| ma_kho_xuat | integer | có |  | Kho xuất hàng |
| ma_voucher | integer |  |  | Voucher áp dụng; NULL nếu không dùng |
| nguoi_nhan | varchar(100) | có |  | Người nhận (snapshot tại lúc đặt) |
| dien_thoai_nhan | varchar(20) | có |  | SĐT người nhận (snapshot) |
| dia_chi_giao | varchar(255) | có |  | Địa chỉ giao (snapshot) |
| kenh_ban | varchar(10) | có | `'Web'` | Kênh bán: Web, CuaHang hoặc DoiTac |
| idempotency_key | varchar(64) |  |  | Khóa chống tạo trùng đơn khi client gửi lại yêu cầu |
| ngay_dat | timestamp | có | `now()` | Thời điểm đặt (cũng là ngày sử dụng voucher) |
| trang_thai | varchar(20) | có | `'ChoXacNhan'` | ChoXacNhan, DaXacNhan, DangGiao, DaGiao hoặc DaHuy |
| tong_tien_hang | numeric(14,0) | có |  | Tổng tiền hàng trước giảm (snapshot, VNĐ) |
| tien_giam | numeric(14,0) | có | `0` | Số tiền được giảm nhờ voucher (snapshot, VNĐ) |
| phi_van_chuyen | numeric(14,0) | có | `0` | Phí vận chuyển (VNĐ) |

Ràng buộc:

- **CHECK** `ck_don_hang_giam_hop_le`: `CHECK ((tien_giam <= tong_tien_hang))`
- **CHECK** `ck_don_hang_kenh`: `CHECK (((kenh_ban)::text = ANY ((ARRAY['Web'::character varying, 'CuaHang'::character varying, 'DoiTac'::character varying])::text[])))`
- **CHECK** `ck_don_hang_trang_thai`: `CHECK (((trang_thai)::text = ANY ((ARRAY['ChoXacNhan'::character varying, 'DaXacNhan'::character varying, 'DangGiao'::character varying, 'DaGiao'::character varying, 'DaHuy'::character varying])::text[])))`
- **CHECK** `don_hang_phi_van_chuyen_check`: `CHECK ((phi_van_chuyen >= (0)::numeric))`
- **CHECK** `don_hang_tien_giam_check`: `CHECK ((tien_giam >= (0)::numeric))`
- **CHECK** `don_hang_tong_tien_hang_check`: `CHECK ((tong_tien_hang >= (0)::numeric))`
- **FK** `don_hang_ma_gian_hang_fkey`: `FOREIGN KEY (ma_gian_hang) REFERENCES gian_hang(ma_gian_hang)`
- **FK** `don_hang_ma_khach_hang_fkey`: `FOREIGN KEY (ma_khach_hang) REFERENCES khach_hang(ma_khach_hang)`
- **FK** `don_hang_ma_kho_xuat_fkey`: `FOREIGN KEY (ma_kho_xuat) REFERENCES kho(ma_kho)`
- **FK** `don_hang_ma_voucher_fkey`: `FOREIGN KEY (ma_voucher) REFERENCES voucher(ma_voucher)`
- **PK** `don_hang_pkey`: `PRIMARY KEY (ma_don_hang)`
- **UNIQUE** `uq_don_hang_idempotency`: `UNIQUE (ma_khach_hang, idempotency_key)`

### chi_tiet_don_hang

Dòng hàng của đơn (đơn hàng - biến thể), lưu giá bán tại thời điểm đặt.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_don_hang** | integer | có |  | Đơn hàng (thành phần khóa chính) |
| **ma_bien_the** | integer | có |  | Biến thể (thành phần khóa chính) |
| so_luong | integer | có |  | Số lượng đặt, lớn hơn 0 |
| don_gia | numeric(14,0) | có |  | Giá bán tại thời điểm đặt (snapshot, VNĐ) |

Ràng buộc:

- **CHECK** `chi_tiet_don_hang_don_gia_check`: `CHECK ((don_gia > (0)::numeric))`
- **CHECK** `chi_tiet_don_hang_so_luong_check`: `CHECK ((so_luong > 0))`
- **FK** `chi_tiet_don_hang_ma_bien_the_fkey`: `FOREIGN KEY (ma_bien_the) REFERENCES bien_the(ma_bien_the)`
- **FK** `chi_tiet_don_hang_ma_don_hang_fkey`: `FOREIGN KEY (ma_don_hang) REFERENCES don_hang(ma_don_hang) ON DELETE CASCADE`
- **PK** `chi_tiet_don_hang_pkey`: `PRIMARY KEY (ma_don_hang, ma_bien_the)`

### lich_su_trang_thai

Nhật ký chuyển trạng thái của đơn hàng (ghi tự động bằng trigger).

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_lich_su** | bigint | có |  | Khóa chính |
| ma_don_hang | integer | có |  | Đơn hàng |
| trang_thai_cu | varchar(20) |  |  | Trạng thái trước (NULL nếu mới tạo) |
| trang_thai_moi | varchar(20) | có |  | Trạng thái sau |
| thoi_diem | timestamp | có | `now()` | Thời điểm chuyển |

Ràng buộc:

- **FK** `lich_su_trang_thai_ma_don_hang_fkey`: `FOREIGN KEY (ma_don_hang) REFERENCES don_hang(ma_don_hang) ON DELETE CASCADE`
- **PK** `lich_su_trang_thai_pkey`: `PRIMARY KEY (ma_lich_su)`

### thanh_toan

Giao dịch thanh toán của đơn; một đơn có thể có nhiều giao dịch.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_thanh_toan** | integer | có |  | Khóa chính |
| ma_don_hang | integer | có |  | Đơn hàng được thanh toán |
| phuong_thuc | varchar(20) | có |  | COD, ChuyenKhoan, TheTinDung hoặc ViDienTu |
| so_tien | numeric(14,0) | có |  | Số tiền giao dịch (VNĐ) |
| trang_thai | varchar(20) | có | `'ChoThanhToan'` | ChoThanhToan, ThanhCong, ThatBai hoặc HoanTien |
| thoi_diem | timestamp | có | `now()` | Thời điểm giao dịch |

Ràng buộc:

- **CHECK** `thanh_toan_phuong_thuc_check`: `CHECK (((phuong_thuc)::text = ANY ((ARRAY['COD'::character varying, 'ChuyenKhoan'::character varying, 'TheTinDung'::character varying, 'ViDienTu'::character varying])::text[])))`
- **CHECK** `thanh_toan_so_tien_check`: `CHECK ((so_tien > (0)::numeric))`
- **CHECK** `thanh_toan_trang_thai_check`: `CHECK (((trang_thai)::text = ANY ((ARRAY['ChoThanhToan'::character varying, 'ThanhCong'::character varying, 'ThatBai'::character varying, 'HoanTien'::character varying])::text[])))`
- **FK** `thanh_toan_ma_don_hang_fkey`: `FOREIGN KEY (ma_don_hang) REFERENCES don_hang(ma_don_hang) ON DELETE CASCADE`
- **PK** `thanh_toan_pkey`: `PRIMARY KEY (ma_thanh_toan)`

### van_chuyen

Thông tin vận chuyển của đơn (tối đa một bản ghi cho mỗi đơn).

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_van_chuyen** | integer | có |  | Khóa chính |
| ma_don_hang | integer | có |  | Đơn hàng (duy nhất: 1 đơn tối đa 1 vận đơn) |
| don_vi_vc | varchar(50) | có |  | Đơn vị vận chuyển |
| ma_van_don | varchar(50) |  |  | Mã vận đơn (duy nhất) |
| ngay_giao_du_kien | date |  |  | Ngày giao dự kiến |
| ngay_giao_thuc_te | date |  |  | Ngày giao thực tế |

Ràng buộc:

- **FK** `van_chuyen_ma_don_hang_fkey`: `FOREIGN KEY (ma_don_hang) REFERENCES don_hang(ma_don_hang) ON DELETE CASCADE`
- **PK** `van_chuyen_pkey`: `PRIMARY KEY (ma_van_chuyen)`
- **UNIQUE** `van_chuyen_ma_don_hang_key`: `UNIQUE (ma_don_hang)`
- **UNIQUE** `van_chuyen_ma_van_don_key`: `UNIQUE (ma_van_don)`

### danh_gia

Đánh giá của khách cho một dòng hàng trong đơn đã giao.

| Cột | Kiểu | Bắt buộc | Mặc định | Ý nghĩa |
|---|---|:---:|---|---|
| **ma_danh_gia** | integer | có |  | Khóa chính |
| ma_don_hang | integer | có |  | Đơn hàng được đánh giá |
| ma_bien_the | integer | có |  | Biến thể được đánh giá (cùng ma_don_hang tạo khóa ngoại tới dòng đơn) |
| so_sao | integer | có |  | Điểm từ 1 đến 5 |
| noi_dung | text |  |  | Nội dung nhận xét |
| ngay_danh_gia | timestamp | có | `now()` | Thời điểm đánh giá |

Ràng buộc:

- **CHECK** `danh_gia_so_sao_check`: `CHECK (((so_sao >= 1) AND (so_sao <= 5)))`
- **FK** `danh_gia_ma_don_hang_ma_bien_the_fkey`: `FOREIGN KEY (ma_don_hang, ma_bien_the) REFERENCES chi_tiet_don_hang(ma_don_hang, ma_bien_the)`
- **PK** `danh_gia_pkey`: `PRIMARY KEY (ma_danh_gia)`
- **UNIQUE** `uq_moi_mon_danh_gia_1_lan`: `UNIQUE (ma_don_hang, ma_bien_the)`

## 5. Chứng minh đạt chuẩn 3NF

### 5.1 Cách chứng minh

- **1NF**: mọi thuộc tính đơn trị, không có nhóm lặp; mọi bảng có khóa chính.
- **2NF**: không có thuộc tính không khóa nào phụ thuộc vào *một phần* của một khóa ứng viên (chỉ cần xét bảng có khóa ghép).
- **3NF**: không có thuộc tính không khóa nào phụ thuộc bắc cầu vào khóa; nói cách khác, với mọi phụ thuộc hàm X → A thì X là siêu khóa, hoặc A là thuộc tính khóa.

Cách làm: với từng bảng liệt kê khóa ứng viên và các phụ thuộc hàm (PTH) thực sự có trong nghiệp vụ, rồi kiểm tra vế trái của mọi PTH. Kết quả: **mọi PTH đều có vế trái là khóa ứng viên, nên các bảng đạt BCNF (mạnh hơn 3NF)**.

### 5.2 Kết quả từng bảng

| Bảng | Khóa ứng viên | Phụ thuộc hàm | Kết luận |
|---|---|---|---|
| danh_muc | ma_danh_muc; (ma_danh_muc_cha, ten_danh_muc) | khóa → ten_danh_muc, ma_danh_muc_cha | BCNF |
| nha_cung_cap | ma_ncc; ten_ncc | khóa → dien_thoai, dia_chi | BCNF |
| gian_hang | ma_gian_hang; ten_gian_hang; email | khóa → các cột còn lại | BCNF |
| kho | ma_kho; ten_kho | khóa → tinh_tp, dia_chi | BCNF |
| san_pham | ma_san_pham | ma_san_pham → gian hàng, danh mục, NCC, tên, mô tả, ngày tạo. Không có PTH nào khác: danh mục không xác định NCC, tên không xác định gian hàng | BCNF |
| bien_the | ma_bien_the; sku; (ma_san_pham, mau_sac, kich_co) | khóa → gia_nhap, gia_ban và các cột còn lại | BCNF |
| ton_kho | (ma_kho, ma_bien_the) | khóa → so_luong_vat_ly, so_luong_giu. Cả hai phụ thuộc vào toàn bộ khóa ghép, không phụ thuộc riêng kho hay riêng biến thể | BCNF |
| bien_dong_kho | ma_bien_dong | ma_bien_dong → mọi cột. Không có PTH giữa các cột còn lại | BCNF |
| khach_hang | ma_khach_hang; email | khóa → ho_ten, dien_thoai, dia_chi, ngay_dang_ky | BCNF |
| voucher | ma_voucher; ma_code | khóa → phần trăm, mức tối thiểu, mức tối đa, ngày, gian hàng | BCNF |
| don_hang | ma_don_hang; (ma_khach_hang, idempotency_key) | khóa → mọi cột. Không có PTH giữa các cột không khóa (xem 5.3) | BCNF |
| chi_tiet_don_hang | (ma_don_hang, ma_bien_the) | khóa → so_luong, don_gia. `don_gia` là giá chụp lại lúc đặt nên **không** suy ra từ `ma_bien_the` (giá hiện hành đổi theo thời gian) | BCNF |
| lich_su_trang_thai | ma_lich_su | ma_lich_su → mọi cột | BCNF |
| thanh_toan | ma_thanh_toan | ma_thanh_toan → mọi cột | BCNF |
| van_chuyen | ma_van_chuyen; ma_don_hang; ma_van_don | khóa → các cột còn lại | BCNF |
| danh_gia | ma_danh_gia; (ma_don_hang, ma_bien_the) | khóa → so_sao, noi_dung, ngay_danh_gia. Không có cột nào chỉ phụ thuộc `ma_don_hang` (xem 5.3) | BCNF |

### 5.3 Các chỗ đã sửa trong quá trình chuẩn hóa

Bản thiết kế đầu tiên có bốn điểm chưa đạt chuẩn hoặc dư thừa; chúng đã được sửa trong `schema.sql`. Nên đưa phần này vào báo cáo vì nó cho thấy quá trình chuẩn hóa thật sự.

| # | Vấn đề ở bản đầu | Vì sao sai | Cách sửa |
|---|---|---|---|
| 1 | `danh_gia` có cột `ma_khach_hang` | `ma_don_hang → ma_khach_hang`, mà `ma_don_hang` chỉ là một phần của khóa ứng viên (ma_don_hang, ma_bien_the): **vi phạm 2NF** | Bỏ cột; người đánh giá chính là `don_hang.ma_khach_hang` |
| 2 | `don_hang` có cả `ma_khach_hang` và `ma_dia_chi` (bảng `dia_chi` thuộc về khách) | `ma_dia_chi → ma_khach_hang`, tức `ma_don_hang → ma_dia_chi → ma_khach_hang`: **phụ thuộc bắc cầu, vi phạm 3NF** | Bỏ bảng `dia_chi`; đơn lưu snapshot nhận hàng (`nguoi_nhan`, `dien_thoai_nhan`, `dia_chi_giao`) |
| 3 | Bảng `dat_giu_hang` có `so_luong` | Trùng `chi_tiet_don_hang.so_luong` (dư thừa); trạng thái giữ suy ra được từ trạng thái đơn và sổ cái | Bỏ bảng; chống giữ trùng bằng chỉ mục duy nhất một phần trên `bien_dong_kho` |
| 4 | Sản phẩm trong chi tiết có thể thuộc gian hàng khác với gian hàng của đơn | Không phải lỗi chuẩn hóa mà là lỗ hổng toàn vẹn liên bảng | Thêm trigger `trg_kiem_tra_chi_tiet` |

Lý do snapshot ở mục 2 là hợp lệ: cùng một khách có thể giao cho người nhận khác nhau ở mỗi đơn, nên `ma_khach_hang` **không** xác định `nguoi_nhan` hay `dia_chi_giao`; không tồn tại PTH giữa chúng trong `don_hang`.

### 5.4 Phi chuẩn hóa có chủ đích

Ba nơi lưu giá trị có thể tính lại từ bảng khác. Đây là lựa chọn có lý do, không phải lỗi chuẩn hóa, và đều có truy vấn đối chiếu:

| Dữ liệu | Vì sao lưu | Đối chiếu |
|---|---|---|
| `chi_tiet_don_hang.don_gia` | Giá bán đổi theo thời gian; đơn cũ phải giữ giá lúc mua | — |
| `don_hang.tong_tien_hang`, `tien_giam` | Chụp lại số tiền lúc đặt (voucher hoặc giá có thể đổi sau); trigger voucher cần tổng tiền ngay lúc tạo đơn | `SELECT d.ma_don_hang FROM don_hang d JOIN chi_tiet_don_hang c USING (ma_don_hang) GROUP BY d.ma_don_hang, d.tong_tien_hang HAVING SUM(c.so_luong * c.don_gia) <> d.tong_tien_hang;` (phải trả về 0 dòng) |
| `ton_kho.so_luong_vat_ly`, `so_luong_giu` | Bản tổng hợp của sổ cái, để đọc nhanh thay vì cộng hàng nghìn dòng | `SELECT * FROM v_doi_soat_kho WHERE NOT khop;` (phải trả về 0 dòng) |

## 6. Vòng đời tồn kho

Ví dụ biến thể có `so_luong_vat_ly = 10`, `so_luong_giu = 0`:

| Sự kiện | Chuyển trạng thái đơn | Vật lý | Giữ | Khả dụng | Dòng sổ cái |
|---|---|---:|---:|---:|---|
| Ban đầu | | 10 | 0 | 10 | NHAP |
| Xác nhận đơn 2 cái | ChoXacNhan → DaXacNhan | 10 | 2 | 8 | GIU |
| Hủy khi chưa xuất | DaXacNhan → DaHuy | 10 | 0 | 10 | NHA_GIU |
| Xác nhận lại 2 cái | ChoXacNhan → DaXacNhan | 10 | 2 | 8 | GIU |
| Giao cho vận chuyển | DaXacNhan → DangGiao | 8 | 0 | 8 | XUAT |
| Hủy khi đang giao (hàng về kho) | DangGiao → DaHuy | 10 | 0 | 10 | HOAN |

Bất biến luôn đúng: `0 <= so_luong_giu <= so_luong_vat_ly`, và tồn hiện tại bằng tổng các dòng sổ cái tương ứng.

## 7. Hạn chế đã biết

- Mỗi đơn chỉ thuộc một gian hàng và một kho; khách mua của nhiều gian hàng phải tách thành nhiều đơn.
- Chưa có giao hàng một phần, trả hàng sau khi đã giao, hay chuyển kho giữa các kho.
- `trg_cap_nhat_ton_kho` xử lý bằng một lệnh UPDATE có điều kiện; khi đơn nhiều biến thể, khóa hàng được lấy theo thứ tự `ma_bien_the` để tránh deadlock giữa các đơn.
- Voucher mỗi đơn dùng tối đa một mã; chưa giới hạn số lần dùng trên mỗi khách.

## 8. Quy trình khôi phục dữ liệu sạch trước buổi bảo vệ (Demo Reset)

Khi thao tác thử nghiệm trên Web Dashboard (`web_dashboard.py`), một số chức năng sẽ ghi thêm dữ liệu kiểm thử vào cơ sở dữ liệu:
- **Nút "Tạo đơn mới" / chuyển trạng thái đơn**: tạo thêm bản ghi trong `don_hang`, `chi_tiet_don_hang`, `lich_su_trang_thai` và ghi sổ cái `bien_dong_kho` (`GIU`, `XUAT`, `NHA_GIU`, `HOAN`).
- **Nút "Mô phỏng tranh mua" (Flash Sale Concurrency)**: tạo sản phẩm và biến thể riêng theo từng mã lượt chạy (`FLASH-<run_id>`, tồn kho = 1) và 2 đơn hàng đồng thời tranh mua chiếc cuối cùng để giữ nguyên lịch sử sổ cái phục vụ kiểm chứng.
- **Nút "Kiểm thử 8 quy tắc" (`/api/verify-rules`)**: các ca kiểm thử vi phạm ràng buộc đều chạy trong giao dịch `ROLLBACK` hoặc điểm lưu (`SAVEPOINT`), riêng ca tranh mua thực tế cũng sinh một lượt `FLASH-VR8-<run_id>` cô lập.

Để đưa cơ sở dữ liệu `ecom` về trạng thái sạch chuẩn trước khi bước vào buổi bảo vệ hoặc trước khi chạy lại benchmark:

1. **Khôi phục trạng thái chuẩn 161 đơn (`seed_nho.sql` — dùng để chạy `kiem_tra_cheo.sql` và `demo_concurrency.sh`)**:
   ```bash
   psql -h localhost -p 5432 -U postgres -d ecom -v ON_ERROR_STOP=1 -f schema.sql
   psql -h localhost -p 5432 -U postgres -d ecom -v ON_ERROR_STOP=1 -f seed_nho.sql
   psql -h localhost -p 5432 -U postgres -d ecom -v ON_ERROR_STOP=1 -f kiem_tra_cheo.sql
   ```
2. **Khôi phục trạng thái chuẩn 400.161 đơn kèm bộ chỉ mục tối ưu (`seed_lon.sql` + `index_toi_uu.sql` — dùng để trình diễn Web Dashboard và báo cáo hiệu năng)**:
   ```bash
   psql -h localhost -p 5432 -U postgres -d ecom -v ON_ERROR_STOP=1 -f schema.sql
   psql -h localhost -p 5432 -U postgres -d ecom -v ON_ERROR_STOP=1 -f seed_nho.sql
   psql -h localhost -p 5432 -U postgres -d ecom -v ON_ERROR_STOP=1 -f seed_lon.sql
   psql -h localhost -p 5432 -U postgres -d ecom -v ON_ERROR_STOP=1 -f index_toi_uu.sql
   ```
   Sau bước này, cơ sở dữ liệu có đúng **400.161 đơn hàng**, **736 biến thể (SKU)**, **5 kho**, và `SELECT COUNT(*) FROM v_doi_soat_kho WHERE NOT khop;` trả về `0`.
