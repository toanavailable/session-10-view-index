-- =====================================================
-- TỐI ƯU HÓA TRUY VẤN VỚI INDEX VÀ EXPLAIN ANALYZE
-- Cơ sở dữ liệu mẫu: classicmodels (bảng customers)
-- Yêu cầu: MySQL 8.0.18+ (hỗ trợ EXPLAIN ANALYZE)
-- =====================================================

USE classicmodels;

-- Bước 1: Đo lường hiệu năng ban đầu (chưa có Index)
EXPLAIN ANALYZE
SELECT * FROM customers
WHERE city = 'Nantes' AND contactLastName = 'Labrune';
-- Kế hoạch mong đợi:
--   -> Filter: ((customers.contactLastName = 'Labrune') and (customers.city = 'Nantes'))
--       -> Table scan on customers  (cost ~12.5  rows=122)
-- => Quét toàn bộ 122 dòng để tìm 1 khách hàng.
-- Ghi lại: cost = ............   actual time = ............

-- Bước 2: Tạo chỉ mục đơn (Single Index) cho cột city
CREATE INDEX idx_city ON customers(city);

-- (Đo thêm để so sánh) Sau khi có idx_city
EXPLAIN ANALYZE
SELECT * FROM customers
WHERE city = 'Nantes' AND contactLastName = 'Labrune';
-- Kế hoạch mong đợi:
--   -> Filter: (customers.contactLastName = 'Labrune')
--       -> Index lookup on customers using idx_city (city='Nantes')  (rows=2)
-- => Chỉ đọc 2 khách ở Nantes, nhưng vẫn phải lọc contactLastName trên từng dòng.
-- Ghi lại: cost = ............   actual time = ............

-- Bước 3: Tạo chỉ mục phức hợp (Composite Index) cho city và contactLastName
CREATE INDEX idx_customer_search ON customers(city, contactLastName);

-- Bước 4: Kiểm tra và so sánh hiệu năng
EXPLAIN ANALYZE
SELECT * FROM customers
WHERE city = 'Nantes' AND contactLastName = 'Labrune';
-- Kế hoạch mong đợi:
--   -> Index lookup on customers using idx_customer_search
--        (city='Nantes', contactLastName='Labrune')  (cost ~0.35  rows=1)
-- => "Table scan" đã được thay bằng "Index lookup", không còn bước Filter.
-- Ghi lại: cost = ............   actual time = ............
-- So sánh: cost giảm từ ~12.5 (Bước 1) xuống ~0.35 (Bước 4).

-- Bước 5: Dọn dẹp hệ thống, đưa bảng về trạng thái ban đầu
DROP INDEX idx_customer_search ON customers;
DROP INDEX idx_city ON customers;   -- xóa luôn chỉ mục đơn tạo ở Bước 2

-- Kiểm tra: bảng customers không còn 2 chỉ mục trên
SHOW INDEX FROM customers;
