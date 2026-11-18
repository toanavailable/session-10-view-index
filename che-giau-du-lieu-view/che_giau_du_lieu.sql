-- =====================================================
-- KIẾN TRÚC CHE GIẤU DỮ LIỆU (DATA MASKING) BẰNG VIEW
-- =====================================================

-- 0. Dữ liệu mẫu (trích từ script rikkei_clinic_db, có kiểm tra tồn tại)
CREATE DATABASE IF NOT EXISTS rikkei_clinic_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE rikkei_clinic_db;

CREATE TABLE IF NOT EXISTS medical_records (
    record_id    INT PRIMARY KEY AUTO_INCREMENT,
    patient_name VARCHAR(100) NOT NULL,
    diagnosis    TEXT NOT NULL,
    total_cost   DECIMAL(10, 2) NOT NULL,
    paid_amount  DECIMAL(10, 2) DEFAULT 0
);

-- Ghi rõ record_id để INSERT IGNORE không chèn trùng khi chạy lại script
INSERT IGNORE INTO medical_records (record_id, patient_name, diagnosis, total_cost, paid_amount) VALUES
    (1, 'Nguyen Van A', 'Nhiem trung duong ruot',  1500000,   500000),
    (2, 'Tran Thi B',   'Giai phau tham my',      50000000, 50000000),
    (3, 'Le Hoang C',   'Viem da co dia',          2000000,        0);

-- =====================================================
-- PHẦN B - TRIỂN KHAI CODE
-- =====================================================

-- View 1: Bác sĩ - chỉ xem thông tin chẩn đoán
CREATE OR REPLACE VIEW doctor_medical_view AS
SELECT record_id,
       patient_name,
       diagnosis
FROM medical_records;

-- View 2: Thu ngân - chỉ xem thông tin tài chính + cột ảo payment_status
CREATE OR REPLACE VIEW cashier_payment_view AS
SELECT record_id,
       patient_name,
       total_cost,
       paid_amount,
       CASE
           WHEN paid_amount < total_cost THEN 'Còn nợ'
           ELSE 'Hoàn tất'
       END AS payment_status
FROM medical_records
WHERE paid_amount >= 0
WITH CHECK OPTION;

-- =====================================================
-- NGHIỆM THU
-- =====================================================

-- T1. Bác sĩ: thấy chẩn đoán, KHÔNG thấy chi phí
SELECT * FROM doctor_medical_view ORDER BY record_id;
-- Kết quả: record_id, patient_name, diagnosis (không có total_cost, paid_amount)

-- T2. Thu ngân: thấy tài chính + trạng thái, KHÔNG thấy chẩn đoán
SELECT * FROM cashier_payment_view ORDER BY record_id;
-- Kết quả mong đợi:
--   1  Nguyen Van A   1500000.00    500000.00  Còn nợ
--   2  Tran Thi B    50000000.00  50000000.00  Hoàn tất
--   3  Le Hoang C     2000000.00         0.00  Còn nợ

-- T3. Truy cập chéo bị chặn vì cột không tồn tại trong View
-- ERROR 1054 (42S22): Unknown column 'total_cost' in 'field list'
-- SELECT total_cost FROM doctor_medical_view;
-- ERROR 1054 (42S22): Unknown column 'diagnosis' in 'field list'
-- SELECT diagnosis FROM cashier_payment_view;

-- T4. Thu ngân cập nhật số tiền hợp lệ qua View: thành công, trạng thái tự đổi
UPDATE cashier_payment_view
SET paid_amount = 1500000
WHERE record_id = 1;

SELECT * FROM cashier_payment_view WHERE record_id = 1;
-- Kết quả: paid_amount = 1500000.00, payment_status = 'Hoàn tất'

-- T5. Thu ngân nhập số âm: bị chặn bởi WITH CHECK OPTION
-- ERROR 1369 (HY000): CHECK OPTION failed 'rikkei_clinic_db.cashier_payment_view'
UPDATE cashier_payment_view
SET paid_amount = -500000
WHERE record_id = 3;
