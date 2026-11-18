# Tối ưu hiệu năng tra cứu hồ sơ

Dùng `EXPLAIN` để phát hiện truy vấn tìm bệnh nhân theo tên đang quét toàn bộ bảng (Full Table Scan), tạo Index `idx_patient_name` trên cột `full_name`, và chứng minh truy vấn đã được tối ưu qua sự thay đổi của cột `type` và `rows`.

## 1. Đề bài

- **Nghiệp vụ:** nhân viên quầy tiếp đón tìm hồ sơ bệnh nhân cũ theo tên. Thời gian phản hồi phải ở mức milliseconds.
- **Vấn đề:** khi bảng `patients` có hàng trăm nghìn bản ghi, tìm kiếm bị chậm vài giây vì Database phải quét toàn bộ bảng.
- **Câu truy vấn:**

```sql
SELECT patient_id, full_name, age, room_number
FROM patients
WHERE full_name = 'Tran Thi B';
```

- **Yêu cầu:** chạy `EXPLAIN` trước và sau khi tạo Index `idx_patient_name` trên `full_name`, ghi chú sự thay đổi của `type` và `rows` ngay trong code.

## 2. Phân tích

Cột `full_name` chưa có Index. Để tìm `'Tran Thi B'`, MySQL không biết dòng đó nằm ở đâu, nên phải đọc **từng dòng** của bảng và so sánh tên. Số dòng phải đọc tăng tỉ lệ thuận với kích thước bảng: 100.000 bệnh nhân thì đọc 100.000 dòng cho mỗi lượt tìm kiếm.

Index trên `full_name` là một cây B-Tree chứa các tên **đã sắp xếp** kèm con trỏ tới dòng dữ liệu. MySQL tra cây để nhảy thẳng tới các dòng có tên cần tìm, chỉ mất vài bước dù bảng lớn tới đâu.

Cột `full_name` phù hợp để đánh Index vì:

- Xuất hiện trực tiếp trong điều kiện `WHERE` của tính năng tìm kiếm được dùng thường xuyên.
- Có **độ phân tán cao**: hầu hết bệnh nhân có tên khác nhau, nên mỗi lần tra chỉ trả về rất ít dòng.
- Ít bị thay đổi sau khi tạo hồ sơ, nên chi phí cập nhật Index thấp.

## 3. Lời giải

### Bước 1: EXPLAIN trước khi tạo Index

```sql
EXPLAIN
SELECT patient_id, full_name, age, room_number
FROM patients
WHERE full_name = 'Tran Thi B';
```

| id | select_type | table | type | possible_keys | key | rows | Extra |
|---|---|---|---|---|---|---|---|
| 1 | SIMPLE | patients | **ALL** | NULL | NULL | **3** | Using where |

`type = ALL` nghĩa là **Full Table Scan**: MySQL đọc cả 3 dòng, tức toàn bộ bảng.

### Bước 2: Tạo Index

```sql
CREATE INDEX idx_patient_name ON patients (full_name);
```

### Bước 3: EXPLAIN sau khi tạo Index

```sql
EXPLAIN
SELECT patient_id, full_name, age, room_number
FROM patients
WHERE full_name = 'Tran Thi B';
```

| id | select_type | table | type | possible_keys | key | rows | Extra |
|---|---|---|---|---|---|---|---|
| 1 | SIMPLE | patients | **ref** | idx_patient_name | **idx_patient_name** | **1** | NULL |

## 4. Kết quả

| Cột | Trước khi có Index | Sau khi có Index | Ý nghĩa |
|---|---|---|---|
| `type` | `ALL` | `ref` | Từ quét toàn bảng chuyển sang tra cứu qua Index theo giá trị bằng |
| `key` | `NULL` | `idx_patient_name` | Optimizer đã chọn dùng Index vừa tạo |
| `rows` | 3 | 1 | Chỉ đọc đúng dòng cần tìm thay vì toàn bộ bảng |

Với dữ liệu mẫu chỉ có 3 dòng, chênh lệch nhìn có vẻ nhỏ. Nhưng với hàng trăm nghìn bản ghi, `rows` khi không có Index bằng **toàn bộ** số dòng của bảng, còn khi có Index vẫn chỉ xấp xỉ số bệnh nhân trùng tên. Đây là lý do thời gian phản hồi giảm từ vài giây xuống mức milliseconds.

File `toi_uu_index.sql` dùng `CREATE ... IF NOT EXISTS` và `INSERT IGNORE` theo lưu ý "kiểm tra bảng tồn tại" của đề, nên chạy được cả trên CSDL `rikkei_clinic_db` đã tạo từ bài trước. Kết quả `EXPLAIN` trong README là kết quả mong đợi trên MySQL 8.0. Các giá trị phụ như `filtered` hay `key_len` có thể khác đôi chút tùy phiên bản và thống kê của bảng.

## 5. Bài học rút ra

- Dùng `EXPLAIN` để xem kế hoạch thực thi trước khi tối ưu. `type = ALL` là dấu hiệu của Full Table Scan.
- Đánh Index cho các cột thường xuyên dùng để **tìm kiếm** và có **độ phân tán cao**.
- Sau khi tạo Index, chạy lại `EXPLAIN` để xác nhận Optimizer thực sự dùng Index (cột `key`) và số dòng phải đọc (`rows`) đã giảm.
- Index tăng tốc `SELECT` nhưng tốn thêm dung lượng và làm chậm `INSERT` / `UPDATE`, nên chỉ đánh Index cho các cột thật sự cần.
