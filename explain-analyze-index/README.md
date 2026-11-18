# Tối ưu hóa truy vấn với Index và EXPLAIN ANALYZE

Dùng `EXPLAIN ANALYZE` để đo chi phí (`cost`) và thời gian thực thi (`actual time`) của truy vấn tìm khách hàng theo thành phố và họ người liên hệ trên bảng `customers` (CSDL mẫu `classicmodels`), so sánh trước và sau khi tạo chỉ mục đơn và chỉ mục phức hợp.

## 1. Đề bài

- **Mục tiêu:** dùng `EXPLAIN ANALYZE` đo hiệu năng truy vấn; tạo chỉ mục đơn và chỉ mục phức hợp; so sánh `cost` và thời gian trước, sau khi đánh chỉ mục.
- **Truy vấn cần tối ưu:**

```sql
SELECT * FROM customers
WHERE city = 'Nantes' AND contactLastName = 'Labrune';
```

- **Yêu cầu:** đo hiệu năng ban đầu → tạo `idx_city` → tạo `idx_customer_search (city, contactLastName)` → đo lại và so sánh → xóa chỉ mục.

**Môi trường:** MySQL 8.0.18 trở lên (phiên bản bắt đầu hỗ trợ `EXPLAIN ANALYZE`), đã nạp CSDL mẫu `classicmodels`.

## 2. Phân tích

`EXPLAIN ANALYZE` **chạy thật** câu truy vấn và in ra cây kế hoạch thực thi, với mỗi bước gồm:

| Thông số | Ý nghĩa |
|---|---|
| `cost` | Chi phí **ước tính** của Optimizer. Càng nhỏ càng tốt |
| `rows` (trong ngoặc đầu) | Số dòng **ước tính** sẽ xử lý |
| `actual time=a..b` | Thời gian **thực tế** (ms): `a` là thời điểm trả dòng đầu tiên, `b` là thời điểm trả hết các dòng |
| `rows` (trong ngoặc sau) | Số dòng **thực tế** đã xử lý |
| `loops` | Số lần bước đó được thực thi |

Truy vấn lọc trên 2 cột bằng phép so sánh **bằng** (`=`), nên một chỉ mục phức hợp chứa cả 2 cột cho phép MySQL tìm thẳng tới đúng dòng cần lấy.

## 3. Lời giải

### Bước 1: Đo hiệu năng ban đầu

```sql
EXPLAIN ANALYZE
SELECT * FROM customers
WHERE city = 'Nantes' AND contactLastName = 'Labrune';
```

Kế hoạch mong đợi:

```
-> Filter: ((customers.contactLastName = 'Labrune') and (customers.city = 'Nantes'))
    -> Table scan on customers  (rows=122)
```

MySQL **quét toàn bộ 122 khách hàng** (`Table scan`) rồi lọc từng dòng để tìm 1 người.

### Bước 2: Tạo chỉ mục đơn

```sql
CREATE INDEX idx_city ON customers(city);
```

Đo lại, kế hoạch mong đợi:

```
-> Filter: (customers.contactLastName = 'Labrune')
    -> Index lookup on customers using idx_city (city='Nantes')  (rows=2)
```

MySQL chỉ đọc 2 khách hàng ở Nantes qua chỉ mục, nhưng vẫn phải **lọc tiếp** `contactLastName` trên từng dòng.

### Bước 3: Tạo chỉ mục phức hợp

```sql
CREATE INDEX idx_customer_search ON customers(city, contactLastName);
```

### Bước 4: Kiểm tra và so sánh hiệu năng

```sql
EXPLAIN ANALYZE
SELECT * FROM customers
WHERE city = 'Nantes' AND contactLastName = 'Labrune';
```

Kế hoạch mong đợi:

```
-> Index lookup on customers using idx_customer_search (city='Nantes', contactLastName='Labrune')  (rows=1)
```

- `Table scan` đã được thay bằng **`Index lookup`**.
- Bước `Filter` biến mất, vì cả 2 điều kiện đều được giải quyết ngay trên chỉ mục.
- Khi có cả `idx_city` và `idx_customer_search`, Optimizer chọn chỉ mục phức hợp vì nó thu hẹp được theo cả 2 cột.

### Bước 5: Dọn dẹp hệ thống

```sql
DROP INDEX idx_customer_search ON customers;
DROP INDEX idx_city ON customers;
```

Đề bài chỉ yêu cầu xóa `idx_customer_search`. Lời giải xóa thêm `idx_city` để bảng `customers` trở về **đúng trạng thái ban đầu**. Ngoài ra, `idx_customer_search` bắt đầu bằng cột `city`, nên theo quy tắc **tiền tố trái nhất** nó đã thay thế được hoàn toàn `idx_city`; trong thực tế giữ cả hai là thừa.

## 4. Kết quả

Bảng ghi nhận (điền số liệu đo được trên máy của bạn):

| Thời điểm | Kiểu truy cập | Số dòng phải đọc | `cost` | `actual time` (ms) |
|---|---|---|---|---|
| Bước 1 – chưa có chỉ mục | Table scan | 122 | ~12.5 | ……… |
| Bước 2 – có `idx_city` | Index lookup + Filter | 2 | ~0.7 | ……… |
| Bước 4 – có `idx_customer_search` | Index lookup | 1 | ~0.35 | ……… |

Các giá trị `cost` trong bảng là **mức ước tính tham khảo**: con số chính xác phụ thuộc phiên bản MySQL và thống kê của bảng. `actual time` thay đổi theo từng máy và từng lần chạy, nên cần đo và điền trực tiếp. Xu hướng quan trọng là `cost` và số dòng phải đọc **giảm mạnh** từ Bước 1 sang Bước 4.

| Tiêu chí đánh giá | Kết quả |
|---|---|
| Đúng đối tượng: bảng `customers`, cột `city`, `contactLastName` | ✅ |
| Đúng kết quả: `cost` Bước 4 thấp hơn đáng kể so với Bước 1 | ✅ |
| Đúng kỹ thuật: dùng `EXPLAIN ANALYZE` | ✅ |
| Quy chuẩn: tên chỉ mục bắt đầu bằng `idx_` | ✅ |

## 5. Bài học rút ra

- `EXPLAIN` chỉ **ước tính** kế hoạch, còn `EXPLAIN ANALYZE` **chạy thật** và cho biết thời gian, số dòng thực tế. Lưu ý không chạy `EXPLAIN ANALYZE` với `UPDATE` / `DELETE` trên dữ liệu thật mà không cẩn thận, vì câu lệnh sẽ được thực thi.
- `Table scan` là dấu hiệu cần cân nhắc thêm chỉ mục. `Index lookup` cho thấy chỉ mục đang được dùng.
- Khi truy vấn lọc trên nhiều cột, chỉ mục phức hợp loại bỏ được bước `Filter` và thường tốt hơn chỉ mục đơn.
- Chỉ mục phức hợp `(a, b)` đã bao hàm chỉ mục đơn `(a)`, nên không cần giữ cả hai.
