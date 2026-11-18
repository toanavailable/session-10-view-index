-- =====================================================
-- TỐI ƯU HÓA TRUY XUẤT KHO DƯỢC PHẨM BẰNG COMPOSITE INDEX
-- =====================================================

-- 0. Dữ liệu mẫu (trích từ script rikkei_clinic_db, có kiểm tra tồn tại)
CREATE DATABASE IF NOT EXISTS rikkei_clinic_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE rikkei_clinic_db;

CREATE TABLE IF NOT EXISTS pharmacy_inventory (
    inventory_id INT PRIMARY KEY AUTO_INCREMENT,
    drug_name    VARCHAR(255) NOT NULL,
    batch_number VARCHAR(50) NOT NULL,
    expiry_date  DATE NOT NULL,
    quantity     INT NOT NULL
);

-- Ghi rõ inventory_id để INSERT IGNORE không chèn trùng khi chạy lại script
INSERT IGNORE INTO pharmacy_inventory (inventory_id, drug_name, batch_number, expiry_date, quantity) VALUES
    (1, 'Paracetamol', 'B001', '2026-12-31',  500),
    (2, 'Amoxicillin', 'B002', '2025-10-15',  300),
    (3, 'Ibuprofen',   'B003', '2027-01-20', 1000),
    (4, 'Paracetamol', 'B004', '2025-08-01',  200);

-- -----------------------------------------------------
-- 1. HIỆN TRẠNG KỊCH BẢN 1: chưa có Index
-- -----------------------------------------------------
EXPLAIN
SELECT inventory_id, drug_name, batch_number, expiry_date, quantity
FROM pharmacy_inventory
WHERE drug_name = 'Paracetamol'
  AND expiry_date <= '2026-12-31';
-- type = ALL, key = NULL, rows = 4  -> quét toàn bảng

-- -----------------------------------------------------
-- 2. TRIỂN KHAI: Composite Index (drug_name, expiry_date)
-- Cột so sánh bằng (=) đặt trước, cột so sánh khoảng (<=) đặt sau
-- -----------------------------------------------------
CREATE INDEX idx_drug_name_expiry ON pharmacy_inventory (drug_name, expiry_date);

-- -----------------------------------------------------
-- 3. NGHIỆM THU KỊCH BẢN 1
-- -----------------------------------------------------
EXPLAIN
SELECT inventory_id, drug_name, batch_number, expiry_date, quantity
FROM pharmacy_inventory
WHERE drug_name = 'Paracetamol'
  AND expiry_date <= '2026-12-31'
ORDER BY expiry_date ASC;
-- type = range, key = idx_drug_name_expiry, rows = 2
-- -> không còn quét toàn bảng, chỉ đọc 2 lô Paracetamol thỏa điều kiện.
-- ORDER BY expiry_date cũng được phục vụ từ Index (không có "Using filesort"):
-- lô sắp hết hạn được cấp phát trước.

SELECT inventory_id, drug_name, batch_number, expiry_date, quantity
FROM pharmacy_inventory
WHERE drug_name = 'Paracetamol'
  AND expiry_date <= '2026-12-31'
ORDER BY expiry_date ASC;
-- Kết quả: B004 (2025-08-01), B001 (2026-12-31)

-- -----------------------------------------------------
-- 4. NGHIỆM THU KỊCH BẢN 2: tìm kiếm tương đối bằng LIKE
-- -----------------------------------------------------
-- 4.1 Cách viết gây Full Table Scan: ký tự % ở ĐẦU chuỗi
EXPLAIN
SELECT inventory_id, drug_name, batch_number, expiry_date
FROM pharmacy_inventory
WHERE drug_name LIKE '%Paracetamol%';
-- type = index hoặc ALL, phải duyệt mọi giá trị -> không tận dụng được tìm kiếm trên cây B-Tree

-- 4.2 Cách viết hợp lệ: chỉ dùng % ở CUỐI chuỗi (tìm theo tiền tố)
EXPLAIN
SELECT inventory_id, drug_name, batch_number, expiry_date
FROM pharmacy_inventory
WHERE drug_name LIKE 'Paracetamol%';
-- type = range, key = idx_drug_name_expiry -> dùng được Index

SELECT inventory_id, drug_name, batch_number, expiry_date
FROM pharmacy_inventory
WHERE drug_name LIKE 'Paracetamol%'
ORDER BY expiry_date;
-- Kết quả: B004, B001
