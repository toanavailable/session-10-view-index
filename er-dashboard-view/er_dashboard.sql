-- =====================================================
-- THIẾT KẾ BẢNG ĐIỀU KHIỂN CẤP CỨU - er_dashboard_view
-- =====================================================

-- 0. Dữ liệu nền (trích từ script rikkei_clinic_db, có kiểm tra tồn tại)
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

INSERT IGNORE INTO departments (department_id, department_name) VALUES
    (1, 'Khoa Noi'),
    (2, 'Khoa Ngoai');

INSERT IGNORE INTO patients (patient_id, full_name, age, phone, room_number, hiv_status, mental_health_history, department_id) VALUES
    (1, 'Nguyen Van A', 45, '0901234567', '101A', 'Negative', 'None', 1),
    (2, 'Tran Thi B',   30, '0912345678', '102B', 'Positive', 'Depression 2020', 1),
    (3, 'Le Hoang C',   50, '0923456789', '103A', 'Negative', 'Anxiety', 2);

-- =====================================================
-- 1. TẠO BẢNG vitals_logs VÀ COMPOSITE INDEX
-- =====================================================
DROP VIEW IF EXISTS er_dashboard_view;
DROP TABLE IF EXISTS vitals_logs;

CREATE TABLE vitals_logs (
    log_id      INT PRIMARY KEY AUTO_INCREMENT,
    patient_id  INT,
    heart_rate  INT CHECK (heart_rate > 0),
    record_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
);

-- Composite Index: patient_id (gom nhóm / JOIN) đứng trước, record_time (lấy MAX) đứng sau
CREATE INDEX idx_vitals_patient_time ON vitals_logs (patient_id, record_time);

-- BN1 có 2 lần đo, lần đo cuối nhịp tim 130
INSERT INTO vitals_logs (patient_id, heart_rate, record_time) VALUES
    (1,  80, '2026-05-14 08:00:00'),
    (1, 130, '2026-05-14 08:15:00');

-- BN2 có 1 lần đo, nhịp tim 75
INSERT INTO vitals_logs (patient_id, heart_rate, record_time) VALUES
    (2,  75, '2026-05-14 08:10:00');

-- BN3 chưa có dữ liệu đo (bệnh nhân mới nhập viện)

-- Kiểm tra truy vấn con lấy thời điểm đo cuối có dùng Index
EXPLAIN
SELECT patient_id, MAX(record_time) AS last_record_time
FROM vitals_logs
GROUP BY patient_id;
-- key = idx_vitals_patient_time, Extra = Using index for group-by
-- -> MySQL nhảy thẳng tới bản ghi cuối của từng bệnh nhân trên cây Index (loose index scan),
--    không cần đọc toàn bộ hàng triệu lần đo.

-- =====================================================
-- 2. TẠO VIEW er_dashboard_view
-- =====================================================
CREATE OR REPLACE VIEW er_dashboard_view AS
SELECT p.patient_id,
       p.full_name,
       p.room_number,
       v.record_time                                  AS last_record_time,
       COALESCE(CAST(v.heart_rate AS CHAR), 'Pending') AS hr_display,
       CASE
           WHEN v.heart_rate IS NULL                          THEN 'UNKNOWN'
           WHEN v.heart_rate > 120 OR v.heart_rate < 50       THEN 'CRITICAL'
           ELSE                                                    'STABLE'
       END                                            AS urgency_level
FROM patients AS p
LEFT JOIN (
    SELECT patient_id, MAX(record_time) AS last_record_time
    FROM vitals_logs
    GROUP BY patient_id
) AS latest ON latest.patient_id = p.patient_id
LEFT JOIN vitals_logs AS v
       ON v.patient_id  = latest.patient_id
      AND v.record_time = latest.last_record_time;

-- =====================================================
-- 3. KIỂM THỬ: đủ 3 trạng thái CRITICAL, STABLE, UNKNOWN/Pending
-- =====================================================
SELECT *
FROM er_dashboard_view
ORDER BY patient_id;
-- Kết quả mong đợi:
--   1  Nguyen Van A  101A  2026-05-14 08:15:00  130      CRITICAL
--   2  Tran Thi B    102B  2026-05-14 08:10:00  75       STABLE
--   3  Le Hoang C    103A  NULL                 Pending  UNKNOWN

-- =====================================================
-- 4. KIỂM THỬ READ-ONLY: sửa nhịp tim qua View bị chặn
-- =====================================================
-- View chứa bảng tạm có GROUP BY (subquery trong FROM) nên MySQL đánh dấu là không thể cập nhật:
-- ERROR 1288 (HY000): The target table er_dashboard_view of the UPDATE is not updatable
UPDATE er_dashboard_view
SET hr_display = '60'
WHERE patient_id = 1;
