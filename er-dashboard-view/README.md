# Thiết kế Bảng điều khiển Cấp cứu (ER Dashboard)

Xây dựng View `er_dashboard_view` hiển thị nhịp tim **mới nhất** của mọi bệnh nhân kèm mức độ khẩn cấp, dùng Composite Index để truy vấn nhanh trên bảng hàng triệu dòng, và chứng minh View tự động ở chế độ chỉ đọc.

## 1. Đề bài

- **Bối cảnh:** máy đo ở Phòng Cấp cứu liên tục ghi nhịp tim vào bảng `vitals_logs`. Y tá tìm thẳng trên bảng hàng triệu dòng sẽ làm phần mềm bị treo.
- **Mục tiêu:** tạo View `er_dashboard_view` hiển thị tình trạng **mới nhất** của **tất cả** bệnh nhân, phản hồi tức thì và không cho sửa, xóa dữ liệu qua View.
- **Logic cần có:**

| Logic | Yêu cầu |
|---|---|
| Đủ danh sách bệnh nhân | `LEFT JOIN` từ `patients` sang dữ liệu nhịp tim, không bỏ sót bệnh nhân chưa gắn máy đo |
| Chỉ lần đo mới nhất | Truy vấn con dùng `MAX(record_time)` theo từng `patient_id`, rồi mới JOIN |
| `hr_display` | Có số đo thì hiện số, chưa có thì hiện `'Pending'` |
| `urgency_level` | `> 120` hoặc `< 50` là `'CRITICAL'`; từ 50 đến 120 là `'STABLE'`; `NULL` là `'UNKNOWN'` |
| Chống treo máy | Composite Index trên `(patient_id, record_time)` |
| Chỉ đọc | Chứng minh `UPDATE` qua View bị chặn |

## 2. Phân tích

### Luồng xử lý dữ liệu

```
patients (tất cả bệnh nhân)
   │  LEFT JOIN
   ▼
latest: SELECT patient_id, MAX(record_time) FROM vitals_logs GROUP BY patient_id
   │  (mỗi bệnh nhân 1 dòng: thời điểm đo cuối cùng)
   │  LEFT JOIN theo patient_id + record_time
   ▼
vitals_logs (lấy đúng nhịp tim của lần đo cuối)
   │
   ▼
COALESCE → hr_display        CASE WHEN → urgency_level
```

1. **Truy vấn con `latest`** tính thời điểm đo cuối cùng của từng bệnh nhân. `MAX(record_time)` chỉ trả về **thời điểm**, không trả về nhịp tim, nên phải JOIN ngược lại `vitals_logs` theo cặp `(patient_id, record_time)` để lấy đúng nhịp tim của lần đo đó.
2. **Hai lần `LEFT JOIN`** giữ lại mọi bệnh nhân. Bệnh nhân chưa có lần đo nào vẫn xuất hiện, với các cột của `vitals_logs` là `NULL`.
3. **`hr_display`**: `heart_rate` là kiểu số, còn `'Pending'` là chuỗi, nên phải đổi nhịp tim sang chuỗi bằng `CAST(... AS CHAR)` trước khi dùng `COALESCE`, để cột có cùng một kiểu dữ liệu.
4. **`urgency_level`**: kiểm tra trên cột số nguyên `heart_rate`, không kiểm tra trên `hr_display` vì đó là chuỗi. Nhánh `IS NULL` phải đặt **đầu tiên**: mọi phép so sánh với `NULL` đều cho UNKNOWN, nên nếu đặt sau, giá trị `NULL` sẽ rơi xuống nhánh `ELSE` và bị gán nhầm thành `'STABLE'`.

### Vì sao cần Composite Index `(patient_id, record_time)`?

Truy vấn con `GROUP BY patient_id` + `MAX(record_time)` là phần tốn kém nhất. Không có Index, MySQL phải đọc **toàn bộ** hàng triệu lần đo để tìm thời điểm lớn nhất của từng bệnh nhân.

Với Index sắp xếp theo `patient_id` rồi đến `record_time`, các lần đo của mỗi bệnh nhân nằm liền nhau và đã xếp theo thời gian. Lần đo cuối luôn nằm ở **cuối nhóm**, nên MySQL chỉ cần nhảy tới cuối mỗi nhóm (loose index scan, `Using index for group-by`). Cùng Index đó cũng phục vụ lần JOIN thứ hai theo cặp `(patient_id, record_time)`.

### Vì sao View tự động chỉ đọc?

View chứa **bảng tạm có `GROUP BY`** (truy vấn con trong `FROM`) và các **cột tính toán** (`COALESCE`, `CASE`). Một dòng của View được ghép từ nhiều dòng của nhiều bảng, nên MySQL không thể ánh xạ một thay đổi trên View về đúng dòng của bảng gốc. Vì vậy MySQL đánh dấu View là **không thể cập nhật** (non-updatable), không cần cấu hình gì thêm.

## 3. Lời giải

### 3.1. Tạo bảng `vitals_logs` và Composite Index

```sql
CREATE TABLE vitals_logs (
    log_id      INT PRIMARY KEY AUTO_INCREMENT,
    patient_id  INT,
    heart_rate  INT CHECK (heart_rate > 0),
    record_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
);

CREATE INDEX idx_vitals_patient_time ON vitals_logs (patient_id, record_time);
```

Kiểm tra Index được dùng cho truy vấn con:

```sql
EXPLAIN
SELECT patient_id, MAX(record_time) AS last_record_time
FROM vitals_logs
GROUP BY patient_id;
-- key = idx_vitals_patient_time, Extra = Using index for group-by
```

### 3.2. Tạo View

```sql
CREATE OR REPLACE VIEW er_dashboard_view AS
SELECT p.patient_id,
       p.full_name,
       p.room_number,
       v.record_time                                  AS last_record_time,
       COALESCE(CAST(v.heart_rate AS CHAR), 'Pending') AS hr_display,
       CASE
           WHEN v.heart_rate IS NULL                          THEN 'UNKNOWN'
           WHEN v.heart_rate > 120 OR v.heart_rate < 50       THEN 'CRITICAL'
           ELSE                                                    'STABLE'
       END                                            AS urgency_level
FROM patients AS p
LEFT JOIN (
    SELECT patient_id, MAX(record_time) AS last_record_time
    FROM vitals_logs
    GROUP BY patient_id
) AS latest ON latest.patient_id = p.patient_id
LEFT JOIN vitals_logs AS v
       ON v.patient_id  = latest.patient_id
      AND v.record_time = latest.last_record_time;
```

View chỉ hiển thị các cột y tá cần (`patient_id`, `full_name`, `room_number`, thời điểm đo, nhịp tim, mức độ khẩn cấp), không đưa các cột nhạy cảm của `patients` như `hiv_status` hay `mental_health_history` vào bảng điều khiển.

### 3.3. Kiểm thử 3 trạng thái

```sql
SELECT *
FROM er_dashboard_view
ORDER BY patient_id;
```

| patient_id | full_name | room_number | last_record_time | hr_display | urgency_level |
|---|---|---|---|---|---|
| 1 | Nguyen Van A | 101A | 2026-05-14 08:15:00 | 130 | **CRITICAL** |
| 2 | Tran Thi B | 102B | 2026-05-14 08:10:00 | 75 | **STABLE** |
| 3 | Le Hoang C | 103A | NULL | Pending | **UNKNOWN** |

- **Nguyen Van A** có 2 lần đo (80 lúc 08:00 và 130 lúc 08:15). View chỉ lấy lần **mới nhất** là 130, nên trạng thái là CRITICAL, dù lần đo trước đó bình thường.
- **Tran Thi B** có nhịp tim 75, nằm trong khoảng 50–120, nên STABLE.
- **Le Hoang C** chưa có lần đo nào nhưng vẫn xuất hiện nhờ `LEFT JOIN`, hiển thị `Pending` / `UNKNOWN`.

### 3.4. Kiểm thử chế độ chỉ đọc

```sql
UPDATE er_dashboard_view
SET hr_display = '60'
WHERE patient_id = 1;
```

Kết quả mong đợi trên MySQL 8.0:

```
ERROR 1288 (HY000): The target table er_dashboard_view of the UPDATE is not updatable
```

Lệnh bị từ chối, dữ liệu trong `vitals_logs` không bị thay đổi. Lệnh này được đặt ở **cuối** file `er_dashboard.sql`, nên mọi phần trước chạy bình thường rồi script dừng ở lỗi trên, đúng như yêu cầu chứng minh.

## 4. Kết quả

| Yêu cầu | Kết quả |
|---|---|
| Không bỏ sót bệnh nhân chưa đo | ✅ Le Hoang C vẫn xuất hiện nhờ `LEFT JOIN` |
| Chỉ lấy lần đo mới nhất | ✅ Nguyen Van A hiển thị 130 (lần đo 08:15), không hiển thị 80 |
| `hr_display` | ✅ Hiện số hoặc `Pending` |
| `urgency_level` | ✅ Đủ 3 trạng thái CRITICAL, STABLE, UNKNOWN |
| Composite Index | ✅ `idx_vitals_patient_time (patient_id, record_time)` |
| Chỉ đọc | ✅ `UPDATE` qua View bị chặn |

File `er_dashboard.sql` dùng `CREATE ... IF NOT EXISTS` và `INSERT IGNORE` cho các bảng nền. Riêng `vitals_logs` được `DROP` và tạo lại để lệnh `CREATE INDEX` chạy được nhiều lần (MySQL không hỗ trợ `CREATE INDEX IF NOT EXISTS`).

Lưu ý: nếu một bệnh nhân có **hai lần đo trùng đúng thời điểm** `record_time`, View sẽ hiện 2 dòng cho bệnh nhân đó. Có thể xử lý bằng cách lấy `MAX(log_id)` thay cho `MAX(record_time)`, hoặc thêm ràng buộc `UNIQUE (patient_id, record_time)`.

## 5. Bài học rút ra

- Để lấy **bản ghi mới nhất theo nhóm**, tính `MAX(thời gian)` trong truy vấn con rồi JOIN ngược lại bảng gốc theo cặp khóa nhóm và thời gian.
- Dùng `LEFT JOIN` từ bảng "trục" (`patients`) để không bỏ sót đối tượng chưa có dữ liệu.
- `COALESCE` cần các giá trị cùng kiểu, nên phải `CAST` số sang chuỗi trước khi ghép với `'Pending'`.
- Trong `CASE`, luôn kiểm tra `IS NULL` **trước**, vì `NULL` không thỏa mọi phép so sánh.
- Composite Index `(cột nhóm, cột thời gian)` giúp truy vấn "bản ghi mới nhất" chạy nhanh trên bảng rất lớn.
- View có JOIN với bảng tạm `GROUP BY` hoặc có hàm tập hợp tự động là **chỉ đọc**.
