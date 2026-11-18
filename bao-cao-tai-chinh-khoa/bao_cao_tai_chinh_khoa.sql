-- =====================================================
-- TỔNG HỢP BÁO CÁO TÀI CHÍNH KHOA - department_revenue_view
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

CREATE TABLE IF NOT EXISTS invoices (
    invoice_id INT PRIMARY KEY,
    patient_id INT,
    amount     DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
);

INSERT IGNORE INTO departments (department_id, department_name) VALUES
    (1, 'Khoa Noi'),
    (2, 'Khoa Ngoai');

INSERT IGNORE INTO patients (patient_id, full_name, age, phone, room_number, hiv_status, mental_health_history, department_id) VALUES
    (1, 'Nguyen Van A', 45, '0901234567', '101A', 'Negative', 'None', 1),
    (2, 'Tran Thi B',   30, '0912345678', '102B', 'Positive', 'Depression 2020', 1),
    (3, 'Le Hoang C',   50, '0923456789', '103A', 'Negative', 'Anxiety', 2);

INSERT IGNORE INTO invoices (invoice_id, patient_id, amount) VALUES
    (101, 1,  500000),
    (102, 2,  300000),
    (103, 3, 1000000);

-- =====================================================
-- PHẦN B - TRIỂN KHAI CODE & KIỂM THỬ
-- =====================================================

-- B1. Tạo View báo cáo tài chính theo khoa
CREATE OR REPLACE VIEW department_revenue_view AS
SELECT d.department_id,
       d.department_name,
       COUNT(DISTINCT p.patient_id)  AS total_patients,
       COALESCE(SUM(i.amount), 0)    AS total_revenue
FROM departments AS d
LEFT JOIN patients AS p ON p.department_id = d.department_id
LEFT JOIN invoices AS i ON i.patient_id   = p.patient_id
GROUP BY d.department_id, d.department_name;

-- B2. Kiểm thử luồng chuẩn: xem báo cáo
SELECT *
FROM department_revenue_view
ORDER BY department_id;
-- Kết quả mong đợi:
--   1  Khoa Noi    2   800000.00
--   2  Khoa Ngoai  1  1000000.00

-- B3. Kiểm thử bẫy dữ liệu: cố tình sửa tổng doanh thu qua View
-- MySQL từ chối vì View chứa GROUP BY và hàm tập hợp (SUM, COUNT):
-- ERROR 1288 (HY000): The target table department_revenue_view of the UPDATE is not updatable
UPDATE department_revenue_view
SET total_revenue = 999999999
WHERE department_id = 1;
