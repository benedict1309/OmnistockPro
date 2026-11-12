# Đề bài gốc (nguồn sự thật, mọi thứ khác phải bám theo đề này)

## Sàn Thương mại Điện tử Đa kênh & Kho Thông minh

**Nghiệp vụ thực tế:** Quản lý quy trình kinh doanh E-commerce: Danh mục sản phẩm phân cấp (Self-referencing), Biến thể sản phẩm (Màu sắc, Size), Người bán (Seller), Kho hàng, Mã giảm giá (Voucher), Đơn hàng, Thanh toán, Vận chuyển và Đánh giá (Review).

**Thiết kế CSDL chi tiết:** Thiết kế CSDL theo phương pháp E/R, đạt chuẩn 3NF và các ràng buộc:

1. CHECK: GiaBan > GiaNhap; PhanTramGiamGia in [1, 100]; SoLuongTonKho >= 0.
2. UNIQUE: Mã SKU sản phẩm duy nhất; (MaDonHang, MaBienThe) là khóa chính/duy nhất trong chi tiết đơn hàng.
3. Business Rules: Mã giảm giá chỉ được áp dụng nếu TongTienDonHang >= GiaTriToiThieuVoucher và NgaySuDung <= NgayHetHanVoucher; Đơn hàng ở trạng thái DaGiao mới được phép ghi nhận DanhGia; Tồn kho biến thể phải giảm tương ứng ngay khi đơn hàng chuyển sang trạng thái DaXacNhan.

**Hệ thống 8 Truy vấn dữ liệu:**

1. Cơ bản: Tìm các sản phẩm thuộc danh mục "Điện thoại" có lượt đánh giá trung bình từ 4.5 sao trở lên.
2. Inner Join: Hiển thị chi tiết đơn hàng (Tên sản phẩm, màu sắc, size, số lượng, giá bán) của khách hàng "Nguyễn Văn A".
3. Group By & Aggregate: Tính tổng doanh thu thuần (đã trừ Voucher) của từng gian hàng trong tháng 10/2026.
4. Having: Tìm các gian hàng có tổng số đơn bị hủy (Status = 'Cancelled') chiếm trên 10% tổng số đơn hàng nhận được trong tháng.
5. Outer Join: Hiển thị toàn bộ danh mục sản phẩm cấp 1 và số lượng sản phẩm tồn kho tương ứng (kể cả danh mục chưa có sản phẩm nào).
6. Subquery với NOT EXISTS: Tìm các khách hàng đăng ký tài khoản trên 1 năm nhưng chưa từng đặt bất kỳ đơn hàng nào.
7. Complex Subquery: Tìm danh sách các mặt hàng có giá bán cao hơn tất cả các mặt hàng thuộc cùng nhà cung cấp X.
8. Window Functions & CTE: Sử dụng SUM() OVER(PARTITION BY ... ORDER BY ...) để tính doanh thu lũy kế từng ngày trong tháng của sàn và xác định mốc ngày đạt mốc doanh thu 1 tỷ VNĐ.

## Chưa biết (cần nhóm hỏi giảng viên, agent không tự đoán)

- Hình thức nộp: chỉ báo cáo + script SQL, hay có demo ứng dụng.
- Định dạng báo cáo (Word, PDF, mẫu của khoa).
- Thời lượng bảo vệ.
