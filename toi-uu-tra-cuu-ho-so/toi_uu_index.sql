-- =====================================================
-- TỐI ƯU HIỆU NĂNG TRA CỨU HỒ SƠ BỆNH NHÂN BẰNG INDEX
-- =====================================================

-- 0. Dữ liệu mẫu (trích từ script rikkei_clinic_db, có kiểm tra tồn tại)
CREATE DATABASE IF NOT EXISTS rikkei_clinic_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE rikkei_clinic_db;

CREATE TABLE IF NOT EXISTS departments (
    department_id   INT PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS patients (
    patient_id            INT PRIMARY KEY,
    full_name             VARCHAR(100) NOT NULL,
    age                   INT NOT NULL,
    phone                 VARCHAR(15) NOT NULL,
    room_number           VARCHAR(10),
    hiv_status            VARCHAR(20),
    mental_health_history TEXT,
    department_id         INT,
    FOREIGN KEY (department_id) REFERENCES departments(department_id)
);

-- INSERT IGNORE: bỏ qua nếu dữ liệu đã tồn tại (tránh lỗi trùng khóa chính khi chạy lại)
INSERT IGNORE INTO departments (department_id, department_name) VALUES
    (1, 'Khoa Noi'),
    (2, 'Khoa Ngoai');

INSERT IGNORE INTO patients (patient_id, full_name, age, phone, room_number, hiv_status, mental_health_history, department_id) VALUES
    (1, 'Nguyen Van A', 45, '0901234567', '101A', 'Negative', 'None', 1),
    (2, 'Tran Thi B',   30, '0912345678', '102B', 'Positive', 'Depression 2020', 1),
    (3, 'Le Hoang C',   50, '0923456789', '103A', 'Negative', 'Anxiety', 2);

-- -----------------------------------------------------
-- 1. EXPLAIN TRƯỚC KHI TẠO INDEX
-- -----------------------------------------------------
EXPLAIN
SELECT patient_id, full_name, age, room_number
FROM patients
WHERE full_name = 'Tran Thi B';
-- Kết quả (trước khi có Index):
--   type          = ALL    -> Full Table Scan: quét toàn bộ bảng
--   possible_keys = NULL   -> không có Index nào dùng được cho cột full_name
--   key           = NULL   -> không sử dụng Index
--   rows          = 3      -> phải đọc cả 3 dòng (toàn bộ bảng) để tìm 1 bệnh nhân
--   Extra         = Using where
-- Với hàng trăm nghìn bản ghi, rows sẽ bằng toàn bộ số dòng của bảng -> giao diện bị "treo".

-- -----------------------------------------------------
-- 2. TẠO INDEX TRÊN CỘT full_name
-- -----------------------------------------------------
CREATE INDEX idx_patient_name ON patients (full_name);

-- -----------------------------------------------------
-- 3. EXPLAIN SAU KHI TẠO INDEX
-- -----------------------------------------------------
EXPLAIN
SELECT patient_id, full_name, age, room_number
FROM patients
WHERE full_name = 'Tran Thi B';
-- Kết quả (sau khi có Index):
--   type          = ref               -> tra cứu qua Index theo giá trị bằng, không còn quét toàn bảng
--   possible_keys = idx_patient_name
--   key           = idx_patient_name  -> Optimizer đã chọn dùng Index vừa tạo
--   rows          = 1                 -> chỉ cần đọc 1 dòng khớp tên
--   Extra         = NULL
-- Thay đổi: type ALL -> ref, rows 3 -> 1.
-- Số dòng phải đọc không còn tăng theo kích thước bảng: với hàng trăm nghìn bản ghi,
-- B-Tree chỉ cần vài bước tra cứu nên thời gian phản hồi đạt mức milliseconds.
