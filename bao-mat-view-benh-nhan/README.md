# Bảo mật thông tin qua tầng View

Phân tích và sửa View `reception_patient_view` của bộ phận tiếp tân: View cũ làm lộ thông tin y tế nhạy cảm và cho phép cập nhật tuổi sai quy tắc. View mới chỉ hiển thị đúng 4 cột được phép và dùng `WITH CHECK OPTION` để chặn dữ liệu không hợp lệ.

## 1. Đề bài

Bộ phận tiếp tân dùng View `reception_patient_view` để tra cứu bệnh nhân nội trú. Hệ thống có 2 quy tắc:

| Quy tắc | Nội dung |
|---|---|
| Giới hạn hiển thị | Chỉ được xem 4 trường: `patient_id`, `full_name`, `age`, `room_number` |
| Toàn vẹn dữ liệu | Mọi thao tác cập nhật `age` qua View phải đảm bảo giá trị lớn hơn 0 |

View hiện tại chạy không lỗi cú pháp nhưng vi phạm cả 2 quy tắc:

```sql
CREATE VIEW reception_patient_view AS
SELECT patient_id, full_name, age, room_number, hiv_status, mental_health_history
FROM patients;
```

## 2. Phần A – Phân tích & Tái hiện lỗi

### A1. Lỗi bảo mật: View làm lộ thông tin y tế nhạy cảm

```sql
SELECT * FROM reception_patient_view;
```

Kết quả:

| patient_id | full_name | age | room_number | hiv_status | mental_health_history |
|---|---|---|---|---|---|
| 1 | Nguyen Van A | 45 | 101A | Negative | None |
| 2 | Tran Thi B | 30 | 102B | **Positive** | **Depression 2020** |
| 3 | Le Hoang C | 50 | 103A | Negative | Anxiety |

**Các cột vi phạm quy tắc bảo mật:**

| Cột | Vì sao vi phạm |
|---|---|
| `hiv_status` | Tình trạng HIV là thông tin y tế đặc biệt nhạy cảm. Bị lộ có thể dẫn tới kỳ thị và vi phạm quyền riêng tư của bệnh nhân. Tiếp tân không cần thông tin này để xếp phòng hay đón tiếp |
| `mental_health_history` | Tiền sử sức khỏe tâm thần là thông tin bí mật y tế, chỉ bác sĩ điều trị được phép xem |

View được dùng như một lớp **phân quyền dữ liệu**: người dùng chỉ thấy những gì View cho phép. Khi View chọn thừa cột, mọi tài khoản tiếp tân đều đọc được hồ sơ bệnh án nhạy cảm của toàn bộ bệnh nhân, dù họ không có quyền truy cập trực tiếp vào bảng `patients`.

### A2. Lỗi toàn vẹn: cập nhật tuổi thành -5 qua View

```sql
UPDATE reception_patient_view
SET age = -5
WHERE patient_id = 1;

SELECT patient_id, full_name, age FROM patients WHERE patient_id = 1;
```

Kết quả: lệnh `UPDATE` chạy **thành công** (1 row affected), và dữ liệu **trong bảng gốc** bị hỏng:

| patient_id | full_name | age |
|---|---|---|
| 1 | Nguyen Van A | -5 |

**Phân tích:**

- View này lấy dữ liệu từ đúng một bảng, không có hàm tổng hợp, `GROUP BY` hay `DISTINCT`, nên MySQL coi nó là **View có thể cập nhật** (updatable view). Lệnh `UPDATE` trên View được chuyển thẳng xuống bảng `patients`.
- Bảng `patients` chỉ khai báo `age INT NOT NULL`, không có ràng buộc `CHECK`. View cũng không có điều kiện `WHERE` hay `WITH CHECK OPTION`. Vì vậy không có lớp nào chặn giá trị âm.
- Hậu quả: tuổi -5 là vô nghĩa về mặt y khoa, có thể làm sai liều thuốc tính theo tuổi, sai báo cáo thống kê, và làm mất niềm tin vào dữ liệu gốc.

File `.sql` khôi phục lại tuổi đúng (`age = 45`) ngay sau bước tái hiện lỗi, trước khi sửa View.

## 3. Phần B – Sửa chữa mã nguồn

### B1. Xóa View cũ

```sql
DROP VIEW IF EXISTS reception_patient_view;
```

`DROP VIEW` chỉ xóa **định nghĩa** của View. Dữ liệu trong bảng `patients` không bị ảnh hưởng.

### B2. Tạo View mới

```sql
CREATE VIEW reception_patient_view AS
SELECT patient_id, full_name, age, room_number
FROM patients
WHERE age > 0
WITH CHECK OPTION;
```

| Thành phần | Tác dụng |
|---|---|
| `SELECT patient_id, full_name, age, room_number` | Chỉ lấy đúng 4 cột được phép. Hai cột `hiv_status` và `mental_health_history` không còn tồn tại trong View, nên tiếp tân không thể truy cập dù cố tình viết `SELECT hiv_status` |
| `WHERE age > 0` | Định nghĩa điều kiện hợp lệ của dữ liệu trong View |
| `WITH CHECK OPTION` | Buộc mọi lệnh `INSERT` / `UPDATE` qua View phải tạo ra dòng **vẫn thỏa** `age > 0`. Nếu không, MySQL từ chối và báo lỗi |

### Kiểm thử sau khi sửa

| Thao tác | Kết quả |
|---|---|
| `SELECT * FROM reception_patient_view;` | Chỉ còn 4 cột: `patient_id`, `full_name`, `age`, `room_number` |
| `UPDATE reception_patient_view SET age = 46 WHERE patient_id = 1;` | ✅ Thành công, vì 46 > 0 |
| `UPDATE reception_patient_view SET age = -5 WHERE patient_id = 1;` | ❌ `ERROR 1369 (HY000): CHECK OPTION failed 'rikkei_clinic_db.reception_patient_view'` |
| `SELECT hiv_status FROM reception_patient_view;` | ❌ `ERROR 1054 (42S22): Unknown column 'hiv_status' in 'field list'` |

### Đề xuất bổ sung

- **Phân quyền:** chỉ cấp cho tài khoản tiếp tân quyền trên View, không cấp quyền trên bảng gốc, ví dụ `GRANT SELECT, UPDATE ON rikkei_clinic_db.reception_patient_view TO 'reception'@'%';`. Nếu không, tiếp tân vẫn có thể đọc thẳng bảng `patients`.
- **Ràng buộc ở bảng gốc:** `WITH CHECK OPTION` chỉ bảo vệ các thao tác **đi qua View**. Thêm `ALTER TABLE patients ADD CONSTRAINT chk_patients_age CHECK (age > 0);` (MySQL 8.0.16+) để chặn tuổi không hợp lệ ở mọi đường ghi dữ liệu.

## 4. Kết quả

| Quy tắc | View cũ | View mới |
|---|---|---|
| Chỉ hiển thị 4 trường được phép | ❌ Lộ `hiv_status`, `mental_health_history` | ✅ |
| Cập nhật `age` phải lớn hơn 0 | ❌ Cho phép `age = -5` | ✅ Bị chặn bởi `WITH CHECK OPTION` |

File `bao_mat_view.sql` chạy từ đầu đến cuối: tạo CSDL và bảng → nhập dữ liệu mẫu → tạo View cũ → Phần A → Phần B → kiểm thử. Các lệnh cố tình gây lỗi (T3, T4) để ở dạng chú thích để script không bị dừng giữa chừng.

## 5. Bài học rút ra

- View là công cụ **bảo mật theo cột**: chỉ đưa vào View những cột mà người dùng thực sự cần.
- View đơn giản trên một bảng có thể cập nhật được, và mọi thay đổi qua View sẽ ghi thẳng xuống bảng gốc.
- Luôn dùng `WITH CHECK OPTION` khi cho phép cập nhật qua View, để dữ liệu ghi vào luôn thỏa điều kiện của View.
- Kết hợp View với **phân quyền** và **ràng buộc `CHECK` ở bảng gốc** để bảo vệ dữ liệu nhiều lớp.
