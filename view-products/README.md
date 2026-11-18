# Tạo và quản trị View trên bảng Products

Thực hành vòng đời của một View trên bảng `products` (CSDL mẫu `classicmodels`): tạo View, sửa cấu trúc bằng `ALTER VIEW`, thay thế bằng `CREATE OR REPLACE VIEW` có điều kiện lọc, và kiểm chứng cơ chế chặn dữ liệu của `WITH CHECK OPTION`.

## 1. Đề bài

- **Mục tiêu:** tạo, sửa, xóa View trên bảng `products`; dùng `ALTER VIEW` thay đổi số cột hiển thị; hiểu cơ chế chặn dữ liệu của `WITH CHECK OPTION` qua ngưỡng tồn kho.
- **Yêu cầu:**

| Bước | Nội dung |
|---|---|
| 1 | Tạo View `view_product_info` gồm `productCode`, `productName`, `productLine`, `buyPrice`, `MSRP` |
| 2 | Truy vấn View, kiểm tra đủ 5 cột |
| 3 | Dùng `ALTER VIEW` bỏ cột `MSRP` |
| 4 | Dùng `CREATE OR REPLACE` chỉ hiển thị sản phẩm có `quantityInStock > 3000`, thêm cột `quantityInStock` và `WITH CHECK OPTION` |
| 5 | `UPDATE` tồn kho của sản phẩm `S10_1678` xuống 1000 qua View và quan sát lỗi |

**Môi trường:** MySQL 8.0, đã nạp CSDL mẫu `classicmodels`.

## 2. Phân tích

| Lệnh | Khi nào dùng |
|---|---|
| `CREATE VIEW` | Tạo View mới. Báo lỗi nếu View đã tồn tại |
| `ALTER VIEW` | Sửa định nghĩa của View **đã tồn tại**. Báo lỗi nếu View chưa có |
| `CREATE OR REPLACE VIEW` | Tạo mới nếu chưa có, thay thế nếu đã có |
| `DROP VIEW` | Xóa định nghĩa View, dữ liệu bảng gốc không bị ảnh hưởng |

`ALTER VIEW` và `CREATE OR REPLACE VIEW` đều **thay toàn bộ** câu `SELECT` của View, không phải thêm hay bớt từng cột. Vì vậy muốn bỏ cột `MSRP`, phải viết lại cả câu `SELECT` không có cột đó.

Ở Bước 4, cột `quantityInStock` phải có trong View. Với `WITH CHECK OPTION`, mọi lệnh `UPDATE` qua View phải để dòng dữ liệu **vẫn thỏa** `quantityInStock > 3000`. Theo dữ liệu mẫu, sản phẩm `S10_1678` có tồn kho trên 3000 nên đang hiện trong View. Giảm xuống 1000 sẽ làm nó vi phạm điều kiện, nên MySQL từ chối.

## 3. Lời giải

### Bước 1: Khởi tạo View

```sql
CREATE VIEW view_product_info AS
SELECT productCode, productName, productLine, buyPrice, MSRP
FROM products;
```

### Bước 2: Kiểm tra dữ liệu

```sql
SELECT * FROM view_product_info;
```

Kết quả gồm đúng 5 cột: `productCode`, `productName`, `productLine`, `buyPrice`, `MSRP`.

### Bước 3: Chỉnh sửa cấu trúc View

```sql
ALTER VIEW view_product_info AS
SELECT productCode, productName, productLine, buyPrice
FROM products;
```

Truy vấn lại View, cột `MSRP` không còn xuất hiện, chỉ còn 4 cột.

### Bước 4: Thiết lập điều kiện lọc và ràng buộc

```sql
CREATE OR REPLACE VIEW view_product_info AS
SELECT productCode, productName, productLine, buyPrice, quantityInStock
FROM products
WHERE quantityInStock > 3000
WITH CHECK OPTION;
```

`SELECT * FROM view_product_info;` giờ chỉ trả về các sản phẩm có tồn kho lớn hơn 3000.

### Bước 5: Kiểm tra tính toàn vẹn

```sql
UPDATE view_product_info
SET quantityInStock = 1000
WHERE productCode = 'S10_1678';
```

Kết quả mong đợi:

```
ERROR 1369 (HY000): CHECK OPTION failed 'classicmodels.view_product_info'
```

Nếu được phép, dòng `S10_1678` sau khi cập nhật sẽ có `quantityInStock = 1000`, không còn thỏa `> 3000`, tức sẽ "biến mất" khỏi View ngay sau khi người dùng sửa nó. `WITH CHECK OPTION` chặn thay đổi này, và dữ liệu trong bảng `products` không bị thay đổi.

## 4. Kết quả

| Tiêu chí đánh giá | Kết quả |
|---|---|
| Đúng đối tượng: bảng `products`, View `view_product_info` | ✅ |
| Đúng logic: Bước 4 chỉ còn sản phẩm có `quantityInStock > 3000` | ✅ |
| Đúng phản hồi: Bước 5 báo lỗi `CHECK OPTION failed` | ✅ |
| Quy chuẩn: mã SQL trong khối code, từ khóa viết hoa | ✅ |

Lệnh `UPDATE` ở Bước 5 nằm ở cuối file `view_products.sql`, nên mọi bước trước chạy bình thường rồi script dừng ở lỗi trên, đúng như yêu cầu chứng minh.

## 5. Bài học rút ra

- `ALTER VIEW` chỉ sửa View đã tồn tại. `CREATE OR REPLACE VIEW` dùng được trong cả hai trường hợp.
- Sửa View là thay **toàn bộ** câu `SELECT`, không thêm hay bớt riêng từng cột.
- Muốn ràng buộc theo một cột bằng `WITH CHECK OPTION`, điều kiện `WHERE` của View phải dùng đúng cột đó.
- `WITH CHECK OPTION` ngăn người dùng sửa dữ liệu qua View thành những giá trị nằm ngoài phạm vi View cho phép.
