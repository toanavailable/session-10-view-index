-- =====================================================
-- BẢO MẬT THÔNG TIN QUA TẦNG VIEW - reception_patient_view
-- =====================================================

-- 0. Dữ liệu mẫu (trích từ script rikkei_clinic_db: chỉ các bảng bài này dùng)
DROP DATABASE IF EXISTS rikkei_clinic_db;
CREATE DATABASE rikkei_clinic_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE rikkei_clinic_db;

CREATE TABLE departments (
    department_id   INT PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL
);

CREATE TABLE patients (
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

INSERT INTO departments (department_id, department_name) VALUES
    (1, 'Khoa Noi'),
    (2, 'Khoa Ngoai');

INSERT INTO patients (patient_id, full_name, age, phone, room_number, hiv_status, mental_health_history, department_id) VALUES
    (1, 'Nguyen Van A', 45, '0901234567', '101A', 'Negative', 'None', 1),
    (2, 'Tran Thi B',   30, '0912345678', '102B', 'Positive', 'Depression 2020', 1),
    (3, 'Le Hoang C',   50, '0923456789', '103A', 'Negative', 'Anxiety', 2);

-- View hiện tại (đang vi phạm cả 2 quy tắc)
CREATE VIEW reception_patient_view AS
SELECT patient_id, full_name, age, room_number, hiv_status, mental_health_history
FROM patients;

-- =====================================================
-- PHẦN A - PHÂN TÍCH & TÁI HIỆN LỖI
-- =====================================================

-- A1. Truy vấn View hiện tại: lộ 2 cột nhạy cảm hiv_status, mental_health_history
SELECT * FROM reception_patient_view;

-- A2. Cập nhật tuổi thành -5 qua View: hệ thống KHÔNG chặn
UPDATE reception_patient_view
SET age = -5
WHERE patient_id = 1;

-- Kiểm tra: dữ liệu GỐC trong bảng patients đã bị hỏng (age = -5)
SELECT patient_id, full_name, age FROM patients WHERE patient_id = 1;

-- Khôi phục dữ liệu bị hỏng trước khi sửa View
UPDATE patients SET age = 45 WHERE patient_id = 1;

-- =====================================================
-- PHẦN B - SỬA CHỮA MÃ NGUỒN
-- =====================================================

-- B1. Xóa View cũ (chỉ xóa định nghĩa, dữ liệu bảng patients không bị ảnh hưởng)
DROP VIEW IF EXISTS reception_patient_view;

-- B2. Tạo View mới: chỉ 4 cột hợp lệ + chặn cập nhật tuổi <= 0
CREATE VIEW reception_patient_view AS
SELECT patient_id, full_name, age, room_number
FROM patients
WHERE age > 0
WITH CHECK OPTION;

-- =====================================================
-- KIỂM THỬ SAU KHI SỬA
-- =====================================================

-- T1. Chỉ còn 4 cột được phép
SELECT * FROM reception_patient_view;

-- T2. Cập nhật hợp lệ: vẫn được phép
UPDATE reception_patient_view
SET age = 46
WHERE patient_id = 1;

-- T3. Cập nhật sai quy tắc: bị chặn
-- ERROR 1369 (HY000): CHECK OPTION failed 'rikkei_clinic_db.reception_patient_view'
-- UPDATE reception_patient_view SET age = -5 WHERE patient_id = 1;

-- T4. Truy cập cột nhạy cảm qua View: báo lỗi vì cột không tồn tại trong View
-- ERROR 1054 (42S22): Unknown column 'hiv_status' in 'field list'
-- SELECT hiv_status FROM reception_patient_view;
