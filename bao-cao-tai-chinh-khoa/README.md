# Tổng hợp Báo cáo Tài chính Khoa

Thiết kế View `department_revenue_view` tổng hợp số bệnh nhân và doanh thu theo từng khoa, giúp kế toán xem báo cáo mà không chạm vào dữ liệu y tế cá nhân, đồng thời chứng minh View này là **chỉ đọc**: mọi lệnh `UPDATE` đều bị MySQL từ chối.

## 1. Đề bài

- **Vấn đề:** kế toán cần báo cáo tổng bệnh nhân và tổng doanh thu theo khoa. Cho kế toán truy vấn trực tiếp bảng `patients`, `invoices` sẽ làm lộ dữ liệu y tế cá nhân.
- **Quy tắc nghiệp vụ:** báo cáo trả về 4 trường `department_id`, `department_name`, `total_patients`, `total_revenue`, gom nhóm chính xác theo từng khoa.
- **Ràng buộc:** báo cáo là bản tổng hợp **chỉ đọc**. Lệnh `UPDATE` sửa `total_revenue` qua View phải bị hệ thống chặn.

## 2. Phần A – Báo cáo Phân tích & Thiết kế

### 2.1. Phân tích I/O

**Đầu vào:**

| Bảng | Cột sử dụng | Vai trò |
|---|---|---|
| `departments` | `department_id`, `department_name` | Danh sách khoa, là "trục" của báo cáo |
| `patients` | `patient_id`, `department_id` | Xác định bệnh nhân thuộc khoa nào, dùng để đếm số bệnh nhân |
| `invoices` | `patient_id`, `amount` | Số tiền của từng hóa đơn, dùng để tính doanh thu |

Các cột nhạy cảm của `patients` như `full_name`, `phone`, `hiv_status`, `mental_health_history` **không được dùng**. `patient_id` chỉ tham gia vào phép nối và phép đếm, không xuất hiện trong kết quả.

**Đầu ra:**

| Cột | Ý nghĩa | Cách tính |
|---|---|---|
| `department_id` | Mã khoa | Lấy từ `departments` |
| `department_name` | Tên khoa | Lấy từ `departments` |
| `total_patients` | Tổng số bệnh nhân của khoa | `COUNT(DISTINCT patient_id)` |
| `total_revenue` | Tổng doanh thu của khoa | `SUM(amount)` |

Chuỗi liên kết dữ liệu: `departments` (1) → (N) `patients` (1) → (N) `invoices`.

### 2.2. Đề xuất giải pháp

| Vấn đề | Giải pháp |
|---|---|
| Bảo mật dữ liệu thô | Tạo **View**. Kế toán chỉ được cấp quyền trên View, không được cấp quyền trên bảng gốc. View chỉ chứa số liệu tổng hợp, không có thông tin của từng bệnh nhân |
| Liên kết 3 bảng | `LEFT JOIN` từ `departments` → `patients` → `invoices`. Dùng `LEFT JOIN` thay vì `INNER JOIN` để khoa **chưa có bệnh nhân hoặc hóa đơn** vẫn xuất hiện trong báo cáo với giá trị 0, thay vì bị mất khỏi báo cáo |
| Đếm bệnh nhân | `COUNT(DISTINCT p.patient_id)`. Một bệnh nhân có thể có nhiều hóa đơn, nên sau khi JOIN sẽ xuất hiện nhiều dòng; `DISTINCT` tránh đếm trùng |
| Tính doanh thu | `SUM(i.amount)`, bọc trong `COALESCE(..., 0)` để khoa không có hóa đơn hiển thị 0 thay vì `NULL` |
| Gom nhóm | `GROUP BY d.department_id, d.department_name` |
| Tính chất chỉ đọc | Không cần cấu hình thêm. MySQL tự coi View có `GROUP BY` và hàm tập hợp là **không thể cập nhật** (non-updatable), vì một dòng của View được tổng hợp từ nhiều dòng gốc nên không có cách nào ánh xạ ngược một thay đổi về bảng gốc |

## 3. Phần B – Triển khai Code & Kiểm thử

### 3.1. Tạo View

```sql
CREATE OR REPLACE VIEW department_revenue_view AS
SELECT d.department_id,
       d.department_name,
       COUNT(DISTINCT p.patient_id)  AS total_patients,
       COALESCE(SUM(i.amount), 0)    AS total_revenue
FROM departments AS d
LEFT JOIN patients AS p ON p.department_id = d.department_id
LEFT JOIN invoices AS i ON i.patient_id   = p.patient_id
GROUP BY d.department_id, d.department_name;
```

### 3.2. Kiểm thử luồng chuẩn

```sql
SELECT *
FROM department_revenue_view
ORDER BY department_id;
```

| department_id | department_name | total_patients | total_revenue |
|---|---|---|---|
| 1 | Khoa Noi | 2 | 800.000,00 |
| 2 | Khoa Ngoai | 1 | 1.000.000,00 |

Đối chiếu với dữ liệu gốc:

| Khoa | Bệnh nhân | Hóa đơn | Tổng |
|---|---|---|---|
| Khoa Noi | Nguyen Van A, Tran Thi B | 500.000 + 300.000 | 800.000 |
| Khoa Ngoai | Le Hoang C | 1.000.000 | 1.000.000 |

### 3.3. Kiểm thử bẫy dữ liệu

```sql
UPDATE department_revenue_view
SET total_revenue = 999999999
WHERE department_id = 1;
```

Kết quả: MySQL **từ chối** câu lệnh:

```
ERROR 1288 (HY000): The target table department_revenue_view of the UPDATE is not updatable
```

**Giải thích:** `total_revenue` không phải là một giá trị được lưu ở đâu cả. Nó được **tính ra** bằng `SUM` từ nhiều hóa đơn khác nhau. Nếu đổi tổng thành 999.999.999, Database không biết phải sửa hóa đơn nào, mỗi hóa đơn thêm bao nhiêu. Vì vậy, theo quy tắc của MySQL, View chứa hàm tập hợp (`SUM`, `COUNT`…), `GROUP BY`, `DISTINCT` hay `HAVING` là **không thể cập nhật**. Lệnh `UPDATE` bị chặn ngay, dữ liệu gốc trong `invoices` không bị ảnh hưởng.

Lệnh `UPDATE` này được đặt ở **cuối** file `bao_cao_tai_chinh_khoa.sql`, nên khi chạy, toàn bộ phần trước thực thi bình thường, rồi script dừng ở dòng cuối với lỗi trên, đúng như yêu cầu chứng minh.

## 4. Kết quả

| Kiểm thử | Kết quả |
|---|---|
| Báo cáo trả về đủ 4 trường, gom nhóm theo khoa | ✅ Khoa Noi: 2 bệnh nhân, 800.000. Khoa Ngoai: 1 bệnh nhân, 1.000.000 |
| Không lộ dữ liệu y tế cá nhân | ✅ View chỉ chứa số liệu tổng hợp |
| `UPDATE total_revenue` qua View | ✅ Bị chặn với `ERROR 1288` |

Đề xuất bổ sung: cấp quyền cho tài khoản kế toán **chỉ trên View**, ví dụ `GRANT SELECT ON rikkei_clinic_db.department_revenue_view TO 'accountant'@'%';`, để kế toán không thể truy vấn trực tiếp bảng gốc.

## 5. Bài học rút ra

- View là công cụ phù hợp để cung cấp **báo cáo tổng hợp** mà không làm lộ dữ liệu chi tiết.
- Dùng `LEFT JOIN` từ bảng "trục" để không bỏ sót các nhóm chưa có dữ liệu, kết hợp `COALESCE` để hiển thị 0 thay cho `NULL`.
- Khi JOIN quan hệ một – nhiều rồi đếm, dùng `COUNT(DISTINCT ...)` để tránh đếm trùng.
- View chứa hàm tập hợp hoặc `GROUP BY` tự động là View **chỉ đọc**. MySQL báo lỗi `ERROR 1288` khi có lệnh ghi dữ liệu qua View này.
