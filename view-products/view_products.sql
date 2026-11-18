-- =====================================================
-- TẠO VÀ QUẢN TRỊ VIEW TRÊN BẢNG PRODUCTS
-- Cơ sở dữ liệu mẫu: classicmodels
-- =====================================================

USE classicmodels;

-- Bước 1: Khởi tạo View thông tin sản phẩm
CREATE VIEW view_product_info AS
SELECT productCode, productName, productLine, buyPrice, MSRP
FROM products;

-- Bước 2: Kiểm tra dữ liệu (5 cột)
SELECT * FROM view_product_info;

-- Bước 3: Chỉnh sửa cấu trúc View, loại bỏ cột MSRP
ALTER VIEW view_product_info AS
SELECT productCode, productName, productLine, buyPrice
FROM products;

SELECT * FROM view_product_info;   -- còn 4 cột

-- Bước 4: Chỉ hiển thị sản phẩm tồn kho > 3000, kèm ràng buộc WITH CHECK OPTION
CREATE OR REPLACE VIEW view_product_info AS
SELECT productCode, productName, productLine, buyPrice, quantityInStock
FROM products
WHERE quantityInStock > 3000
WITH CHECK OPTION;

SELECT * FROM view_product_info;   -- chỉ còn các sản phẩm có quantityInStock > 3000

-- Bước 5: Kiểm tra tính toàn vẹn - giảm tồn kho của S10_1678 xuống 1000 qua View
-- Kết quả mong đợi:
-- ERROR 1369 (HY000): CHECK OPTION failed 'classicmodels.view_product_info'
UPDATE view_product_info
SET quantityInStock = 1000
WHERE productCode = 'S10_1678';
