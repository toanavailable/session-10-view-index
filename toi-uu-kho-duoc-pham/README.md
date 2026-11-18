# Tối ưu hóa Truy xuất Kho Dược phẩm

So sánh hai kiến trúc chỉ mục (2 Single Index và 1 Composite Index) cho truy vấn tìm thuốc theo tên và hạn sử dụng, triển khai giải pháp tối ưu, và viết lại điều kiện `LIKE` để vẫn tận dụng được Index.

## 1. Đề bài

- **Bối cảnh:** kho dược truy xuất danh sách thuốc ưu tiên cấp phát theo 2 tiêu chí: tên thuốc (`drug_name`) và hạn sử dụng (`expiry_date`). Bảng `pharmacy_inventory` có hàng triệu bản ghi nên truy vấn rất chậm.
- **Quy tắc:** kế hoạch thực thi bắt buộc dùng Index, không quét toàn bảng; xử lý tốt cả tìm kiếm chính xác (`=`) lẫn tương đối (`LIKE`).
- **Kịch bản 1:** `WHERE drug_name = 'Paracetamol' AND expiry_date <= '2026-12-31'` đang có `type = ALL`.
- **Kịch bản 2:** dược sĩ tìm bằng `LIKE '%Paracetamol%'`, khiến Index bị vô hiệu hóa.

## 2. Phần A – Phân tích & Đề xuất đa giải pháp

### 2.1. Phân tích truy vấn Kịch bản 1

```sql
WHERE drug_name = 'Paracetamol'        -- điều kiện so sánh BẰNG
  AND expiry_date <= '2026-12-31'      -- điều kiện so sánh KHOẢNG
```

Truy vấn lọc đồng thời trên 2 cột, với 2 loại điều kiện khác nhau. Index tốt phải giúp MySQL thu hẹp cùng lúc theo cả hai điều kiện.

### 2.2. Giải pháp 1: Hai Single Index độc lập

```sql
CREATE INDEX idx_drug_name   ON pharmacy_inventory (drug_name);
CREATE INDEX idx_expiry_date ON pharmacy_inventory (expiry_date);
```

Mỗi cột có một cây B-Tree riêng. Khi chạy truy vấn, MySQL thường **chỉ chọn một** Index (thường là `idx_drug_name`), lấy ra **mọi lô Paracetamol**, rồi mới quay về bảng để lọc tiếp `expiry_date` từng dòng. Kỹ thuật Index Merge (giao kết quả 2 Index) chỉ áp dụng trong một số trường hợp hạn chế, và thường không dùng được khi một điều kiện là so sánh khoảng như `<=`.

### 2.3. Giải pháp 2: Một Composite Index

```sql
CREATE INDEX idx_drug_name_expiry ON pharmacy_inventory (drug_name, expiry_date);
```

Một cây B-Tree sắp xếp theo `drug_name` trước, trong cùng một tên thuốc thì sắp tiếp theo `expiry_date`. Các lô Paracetamol nằm liền nhau và đã được xếp sẵn theo hạn sử dụng, nên MySQL nhảy thẳng tới nhóm `'Paracetamol'` rồi đọc một **đoạn liên tục** đến `2026-12-31`, không đọc thừa dòng nào.

Thứ tự cột quan trọng: cột so sánh **bằng** (`drug_name`) đặt trước, cột so sánh **khoảng** (`expiry_date`) đặt sau. Nếu đảo thứ tự, điều kiện khoảng trên cột đầu sẽ "chặn" Index không dùng được cho cột thứ hai.

### 2.4. So sánh và lựa chọn

| Tiêu chí | Giải pháp 1: 2 Single Index | Giải pháp 2: 1 Composite Index |
|---|---|---|
| **Tốc độ đọc (SELECT)** | ⚠️ Trung bình. Chỉ thu hẹp được theo 1 cột, phải đọc **mọi** lô của thuốc đó rồi lọc hạn sử dụng trên từng dòng. Thuốc phổ biến có hàng chục nghìn lô thì vẫn đọc thừa rất nhiều | ✅ Nhanh nhất. Thu hẹp **đồng thời** theo cả 2 cột, chỉ đọc đúng các dòng thỏa điều kiện. Còn hỗ trợ sẵn `ORDER BY expiry_date` mà không cần sắp xếp lại (không có `Using filesort`) |
| **Tốc độ ghi (INSERT / UPDATE)** | ❌ Chậm hơn. Mỗi lệnh ghi phải cập nhật **2 cây** B-Tree | ✅ Nhanh hơn. Mỗi lệnh ghi chỉ cập nhật **1 cây** |
| **Dung lượng lưu trữ** | ❌ 2 cây Index, mỗi cây có bản sao khóa chính riêng | ✅ 1 cây Index, gọn hơn |
| **Tính linh hoạt** | ✅ Dùng được cho truy vấn chỉ lọc theo `expiry_date` | ⚠️ Chỉ dùng được khi có điều kiện trên cột đầu `drug_name` (quy tắc **tiền tố trái nhất**). Truy vấn chỉ lọc theo `expiry_date` không dùng được Index này |

**Lựa chọn: Giải pháp 2 – Composite Index `(drug_name, expiry_date)`.** Truy vấn cấp phát thuốc luôn lọc theo cả tên thuốc và hạn sử dụng, nên Composite Index cho tốc độ đọc tốt nhất, đồng thời ghi nhanh và tốn ít dung lượng hơn. Nếu sau này có nghiệp vụ lọc **chỉ** theo hạn sử dụng (ví dụ quét các lô sắp hết hạn của mọi loại thuốc), có thể bổ sung riêng một Index trên `expiry_date`.

### 2.5. Giải thích Kịch bản 2

`LIKE '%Paracetamol%'` có ký tự `%` ở **đầu chuỗi**, nghĩa là "Paracetamol" có thể nằm ở bất kỳ vị trí nào trong tên thuốc. Index B-Tree sắp xếp theo **các ký tự đầu tiên** (giống từ điển xếp theo chữ cái đầu), nên MySQL không biết bắt đầu tìm từ đâu và buộc phải duyệt toàn bộ giá trị, tức Full Table Scan (hoặc quét toàn bộ Index).

Viết lại thành `LIKE 'Paracetamol%'` (chỉ dùng `%` ở **cuối**): MySQL biết chắc tên thuốc bắt đầu bằng "Paracetamol", nên có thể nhảy thẳng tới đoạn tương ứng trên cây Index và chỉ đọc một khoảng liên tục.

## 3. Phần B – Thiết kế & Triển khai

### 3.1. Tạo Index

```sql
CREATE INDEX idx_drug_name_expiry ON pharmacy_inventory (drug_name, expiry_date);
```

### 3.2. Nghiệm thu Kịch bản 1

```sql
EXPLAIN
SELECT inventory_id, drug_name, batch_number, expiry_date, quantity
FROM pharmacy_inventory
WHERE drug_name = 'Paracetamol'
  AND expiry_date <= '2026-12-31'
ORDER BY expiry_date ASC;
```

| Cột | Trước khi có Index | Sau khi có Index |
|---|---|---|
| `type` | `ALL` | `range` |
| `key` | `NULL` | `idx_drug_name_expiry` |
| `rows` | 4 | 2 |

`ORDER BY expiry_date ASC` được thêm vào để lô **sắp hết hạn được cấp phát trước**. Thứ tự này lấy sẵn từ Composite Index, không cần sắp xếp thêm.

| inventory_id | drug_name | batch_number | expiry_date | quantity |
|---|---|---|---|---|
| 4 | Paracetamol | B004 | 2025-08-01 | 200 |
| 1 | Paracetamol | B001 | 2026-12-31 | 500 |

### 3.3. Nghiệm thu Kịch bản 2

```sql
-- Gây Full Table Scan
SELECT inventory_id, drug_name, batch_number, expiry_date
FROM pharmacy_inventory
WHERE drug_name LIKE '%Paracetamol%';

-- Viết lại hợp lệ: tận dụng được Index
EXPLAIN
SELECT inventory_id, drug_name, batch_number, expiry_date
FROM pharmacy_inventory
WHERE drug_name LIKE 'Paracetamol%';
```

| Cách viết | Kết quả EXPLAIN mong đợi |
|---|---|
| `LIKE '%Paracetamol%'` | `type = index` hoặc `ALL`, phải duyệt mọi giá trị |
| `LIKE 'Paracetamol%'` | `type = range`, `key = idx_drug_name_expiry` |

Nếu nghiệp vụ thật sự cần tìm "Paracetamol" ở **giữa** tên thuốc, giải pháp phù hợp là **FULLTEXT Index** (`MATCH ... AGAINST`) chứ không phải B-Tree Index.

## 4. Kết quả

File `toi_uu_kho_duoc.sql` chạy từ đầu đến cuối: tạo bảng (có kiểm tra tồn tại) → nhập dữ liệu → `EXPLAIN` trước khi có Index → tạo Composite Index → nghiệm thu Kịch bản 1 → nghiệm thu Kịch bản 2. Phần `INSERT` ghi rõ `inventory_id` để `INSERT IGNORE` không chèn trùng dữ liệu khi chạy lại script.

Lưu ý: bảng mẫu chỉ có 4 dòng. Với bảng quá nhỏ, Optimizer của MySQL đôi khi vẫn chọn quét toàn bảng vì thấy rẻ hơn. Nếu kết quả `EXPLAIN` thực tế khác bảng trên, cần thêm nhiều dữ liệu hơn để Optimizer chọn dùng Index.

## 5. Bài học rút ra

- Khi truy vấn lọc trên nhiều cột cùng lúc, **Composite Index** thường hiệu quả hơn nhiều Single Index riêng lẻ.
- Thứ tự cột trong Composite Index: cột so sánh **bằng** trước, cột so sánh **khoảng** sau.
- Composite Index tuân theo quy tắc **tiền tố trái nhất**: phải có điều kiện trên cột đầu tiên thì Index mới được dùng.
- `LIKE` chỉ dùng được B-Tree Index khi `%` nằm ở **cuối** chuỗi. Cần tìm chuỗi ở giữa thì dùng FULLTEXT Index.
