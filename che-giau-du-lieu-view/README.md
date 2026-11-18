# Kiến trúc Che giấu Dữ liệu (Data Masking) bằng View

Phân quyền truy xuất bảng `medical_records` ngay tại tầng Database mà không tạo thêm bảng nào: Bác sĩ chỉ xem chẩn đoán, Thu ngân chỉ xem thông tin tài chính kèm cột trạng thái thanh toán tự động, và mọi thao tác nhập số tiền âm qua View đều bị chặn.

## 1. Đề bài

- **Bài toán:** bảng `medical_records` lưu chung chẩn đoán bệnh và chi phí điều trị. Cần phân quyền: **Bác sĩ** chỉ xem chẩn đoán, **Thu ngân** chỉ xem thông tin tài chính.
- **Ràng buộc:**
  - **Zero-Duplication:** không tạo bảng mới, bắt buộc dùng View.
  - **Cột ảo:** View của Thu ngân tự sinh cột `payment_status`: 'Còn nợ' nếu `paid_amount < total_cost`, ngược lại là 'Hoàn tất'.
  - **Cập nhật:** Thu ngân được cập nhật `paid_amount` qua View, nhưng phải chặn số âm.

## 2. Phần A – Thiết kế kiến trúc

### 2.1. Chiến lược ảo hóa

Cần tạo **2 View** trên cùng bảng gốc `medical_records`. Dữ liệu vẫn chỉ nằm ở một nơi, mỗi View là một "cửa sổ" nhìn vào đúng phần dữ liệu của từng bộ phận.

```
                        medical_records (bảng gốc duy nhất)
          record_id | patient_name | diagnosis | total_cost | paid_amount
                 │                                        │
      ┌──────────┴─────────┐                   ┌──────────┴───────────┐
      ▼                    │                   ▼                      │
doctor_medical_view        │          cashier_payment_view            │
(Bác sĩ)                   │          (Thu ngân)                      │
```

| Cột | Bảng gốc `medical_records` | `doctor_medical_view` (Bác sĩ) | `cashier_payment_view` (Thu ngân) |
|---|---|---|---|
| `record_id` | ✅ | ✅ | ✅ |
| `patient_name` | ✅ | ✅ | ✅ |
| `diagnosis` | ✅ | ✅ | ❌ Che giấu |
| `total_cost` | ✅ | ❌ Che giấu | ✅ |
| `paid_amount` | ✅ | ❌ Che giấu | ✅ |
| `payment_status` | Không có | Không có | ✅ Cột ảo, tính tự động |

- `record_id` và `patient_name` có ở cả hai View để mỗi bộ phận xác định đúng hồ sơ đang làm việc.
- Thông tin **chéo** của bộ phận kia không có mặt trong View, nên không thể truy vấn được, kể cả khi cố tình gọi tên cột.

### 2.2. Giải pháp kỹ thuật

**Cột ảo `payment_status`:** dùng biểu thức `CASE WHEN` trong mệnh đề `SELECT` của View:

```sql
CASE
    WHEN paid_amount < total_cost THEN 'Còn nợ'
    ELSE 'Hoàn tất'
END AS payment_status
```

Cột này **không được lưu** ở đâu cả. Mỗi lần Thu ngân truy vấn View, giá trị được tính lại từ `paid_amount` và `total_cost` hiện tại, nên luôn chính xác ngay sau khi số tiền thay đổi. Vì là cột tính toán, MySQL không cho cập nhật trực tiếp cột này. Thu ngân chỉ cập nhật được `paid_amount`, và trạng thái tự đổi theo.

**Chặn cập nhật số âm:** kết hợp điều kiện `WHERE` với `WITH CHECK OPTION`:

```sql
WHERE paid_amount >= 0
WITH CHECK OPTION
```

- `WHERE paid_amount >= 0` định nghĩa điều kiện hợp lệ của dữ liệu trong View.
- `WITH CHECK OPTION` buộc mọi lệnh `INSERT` / `UPDATE` thực hiện qua View phải tạo ra dòng **vẫn thỏa** điều kiện `WHERE`. Cập nhật `paid_amount = -500000` làm dòng đó vi phạm `paid_amount >= 0`, nên MySQL từ chối và báo lỗi `CHECK OPTION failed`.

View của Thu ngân vẫn **cập nhật được** vì chỉ lấy dữ liệu từ một bảng, không có hàm tập hợp, `GROUP BY` hay `DISTINCT`. Cột `CASE` chỉ là cột chỉ đọc bên trong View, không làm cả View mất khả năng cập nhật.

View của Bác sĩ chỉ dùng để xem. Để đảm bảo Bác sĩ không sửa được dữ liệu, chỉ cấp quyền `SELECT` trên View này.

## 3. Phần B – Triển khai Code & Nghiệm thu

### 3.1. Mã nguồn

```sql
-- View 1: Bác sĩ - chỉ xem thông tin chẩn đoán
CREATE OR REPLACE VIEW doctor_medical_view AS
SELECT record_id,
       patient_name,
       diagnosis
FROM medical_records;

-- View 2: Thu ngân - chỉ xem thông tin tài chính + cột ảo payment_status
CREATE OR REPLACE VIEW cashier_payment_view AS
SELECT record_id,
       patient_name,
       total_cost,
       paid_amount,
       CASE
           WHEN paid_amount < total_cost THEN 'Còn nợ'
           ELSE 'Hoàn tất'
       END AS payment_status
FROM medical_records
WHERE paid_amount >= 0
WITH CHECK OPTION;
```

### 3.2. Kiểm thử phân quyền

```sql
SELECT * FROM doctor_medical_view ORDER BY record_id;
```

| record_id | patient_name | diagnosis |
|---|---|---|
| 1 | Nguyen Van A | Nhiem trung duong ruot |
| 2 | Tran Thi B | Giai phau tham my |
| 3 | Le Hoang C | Viem da co dia |

Bác sĩ **không thấy** chi phí và số tiền đã trả.

```sql
SELECT * FROM cashier_payment_view ORDER BY record_id;
```

| record_id | patient_name | total_cost | paid_amount | payment_status |
|---|---|---|---|---|
| 1 | Nguyen Van A | 1.500.000 | 500.000 | Còn nợ |
| 2 | Tran Thi B | 50.000.000 | 50.000.000 | Hoàn tất |
| 3 | Le Hoang C | 2.000.000 | 0 | Còn nợ |

Thu ngân **không thấy** chẩn đoán bệnh. Cột `payment_status` tính đúng: chỉ Tran Thi B đã trả đủ.

Truy cập chéo bị chặn:

| Lệnh | Kết quả |
|---|---|
| `SELECT total_cost FROM doctor_medical_view;` | ❌ `ERROR 1054: Unknown column 'total_cost' in 'field list'` |
| `SELECT diagnosis FROM cashier_payment_view;` | ❌ `ERROR 1054: Unknown column 'diagnosis' in 'field list'` |

### 3.3. Kiểm thử cập nhật

**Cập nhật hợp lệ:** khách Nguyen Van A thanh toán nốt phần còn nợ.

```sql
UPDATE cashier_payment_view
SET paid_amount = 1500000
WHERE record_id = 1;
```

Thành công. `payment_status` của hồ sơ 1 tự đổi từ 'Còn nợ' sang **'Hoàn tất'** mà không cần cập nhật gì thêm.

**Cập nhật số âm:**

```sql
UPDATE cashier_payment_view
SET paid_amount = -500000
WHERE record_id = 3;
```

Kết quả: MySQL **từ chối**:

```
ERROR 1369 (HY000): CHECK OPTION failed 'rikkei_clinic_db.cashier_payment_view'
```

Dữ liệu gốc của hồ sơ 3 vẫn giữ `paid_amount = 0`. Lệnh này được đặt ở **cuối** file `che_giau_du_lieu.sql`, nên mọi phần trước chạy bình thường rồi script dừng ở lỗi trên, đúng như yêu cầu chứng minh.

## 4. Kết quả

| Yêu cầu | Kết quả |
|---|---|
| Không tạo bảng mới | ✅ Chỉ dùng 2 View trên bảng gốc |
| Bác sĩ chỉ xem chẩn đoán | ✅ `doctor_medical_view` không có cột tài chính |
| Thu ngân chỉ xem tài chính | ✅ `cashier_payment_view` không có cột chẩn đoán |
| Cột ảo `payment_status` | ✅ Tính đúng và tự cập nhật khi `paid_amount` thay đổi |
| Chặn nhập số âm | ✅ `ERROR 1369: CHECK OPTION failed` |

Đề xuất bổ sung:

- **Phân quyền tài khoản:** chỉ cấp quyền trên View, không cấp quyền trên bảng gốc, ví dụ `GRANT SELECT ON rikkei_clinic_db.doctor_medical_view TO 'doctor'@'%';` và `GRANT SELECT, UPDATE (paid_amount) ON rikkei_clinic_db.cashier_payment_view TO 'cashier'@'%';`.
- **Chặn trả thừa:** nếu nghiệp vụ không cho phép thu vượt chi phí, mở rộng điều kiện thành `WHERE paid_amount BETWEEN 0 AND total_cost`.

## 5. Bài học rút ra

- View cho phép **phân tách luồng dữ liệu** theo từng bộ phận mà không nhân bản dữ liệu, nên dữ liệu luôn nhất quán.
- Cột ảo tạo bằng `CASE WHEN` luôn được tính lại theo dữ liệu mới nhất và không thể sửa trực tiếp.
- View đơn giản trên một bảng vẫn cập nhật được dù có thêm cột tính toán.
- `WITH CHECK OPTION` là "hàng rào" chặn dữ liệu không hợp lệ đi qua View. Kết hợp với phân quyền tài khoản để bảo vệ dữ liệu nhiều lớp.
