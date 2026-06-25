-- ============================================================
-- Hospital Operations & Patient Analytics — Seed Data
-- 100% SYNTHETIC data, generated in pure SQL.
--
--   psql -d healthcare -f seed.sql
--
-- Safe to re-run: it truncates the tables first.
-- ============================================================

BEGIN;

-- Reproducible randomness (so everyone who clones gets the same data)
SELECT setseed(0.42);

TRUNCATE billing, prescriptions, diagnoses, appointments,
         patients, doctors, medications, insurance_providers, departments
         RESTART IDENTITY CASCADE;

-- ------------------------------------------------------------
-- Reference data
-- ------------------------------------------------------------

INSERT INTO departments (name, floor) VALUES
    ('Cardiology', 3),
    ('Orthopedics', 2),
    ('Pediatrics', 1),
    ('Neurology', 4),
    ('Oncology', 5),
    ('Emergency', 1),
    ('General Medicine', 2),
    ('Dermatology', 3);

INSERT INTO insurance_providers (name, avg_coverage_rate) VALUES
    ('BlueShield Health', 0.80),
    ('MediCare Plus',     0.75),
    ('UnitedWell',        0.70),
    ('GreenCross',        0.85),
    ('Apex Insurance',    0.65);

INSERT INTO medications (name, drug_class, unit_cost) VALUES
    ('Atorvastatin',  'Statin',            0.40),
    ('Lisinopril',    'ACE Inhibitor',     0.25),
    ('Metformin',     'Antidiabetic',      0.30),
    ('Amoxicillin',   'Antibiotic',        0.50),
    ('Ibuprofen',     'NSAID',             0.10),
    ('Omeprazole',    'PPI',               0.35),
    ('Albuterol',     'Bronchodilator',    1.20),
    ('Sertraline',    'SSRI',              0.45),
    ('Levothyroxine', 'Thyroid Hormone',   0.30),
    ('Amlodipine',    'Calcium Blocker',   0.28),
    ('Prednisone',    'Corticosteroid',    0.22),
    ('Gabapentin',    'Anticonvulsant',    0.55),
    ('Hydrochlorothiazide','Diuretic',     0.18),
    ('Insulin Glargine','Antidiabetic',    8.50),
    ('Ondansetron',   'Antiemetic',        1.10);

-- ------------------------------------------------------------
-- Doctors (40), each assigned to a department
-- ------------------------------------------------------------

INSERT INTO doctors (full_name, specialty, department_id, hire_date)
SELECT
    'Dr. '
      || (ARRAY['Sofia','Liam','Noah','Emma','Lucas','Mia','Ethan','Ava',
                'Mateo','Isla','Hugo','Nora','Leo','Clara','Theo','Ines',
                'Bruno','Lena','Felix','Maya'])[1 + floor(random()*20)::int]
      || ' '
      || (ARRAY['Silva','Costa','Nguyen','Patel','Kim','Rossi','Haddad','Oliveira',
                'Schmidt','Garcia','Khan','Ferreira','Andersen','Yilmaz'])[1 + floor(random()*14)::int],
    (ARRAY['Consultant','Attending','Resident','Specialist'])[1 + floor(random()*4)::int],
    1 + floor(random()*8)::int,                       -- department_id in 1..8
    DATE '2012-01-01' + (floor(random()*4200))::int   -- hired sometime in the last ~11 yrs
FROM generate_series(1,40) AS g;

-- ------------------------------------------------------------
-- Patients (600)
-- ------------------------------------------------------------

INSERT INTO patients (full_name, date_of_birth, sex, registration_date, insurance_id)
SELECT
    (ARRAY['James','Mary','Robert','Patricia','John','Jennifer','Michael','Linda',
           'David','Elizabeth','William','Barbara','Richard','Susan','Joseph','Jessica',
           'Thomas','Sarah','Carlos','Ana','Wei','Fatima','Yuki','Omar'])[1 + floor(random()*24)::int]
      || ' '
      || (ARRAY['Smith','Johnson','Williams','Brown','Jones','Miller','Davis','Wilson',
                'Moore','Taylor','Lee','Martin','Lopez','Gonzalez','Wang','Ali'])[1 + floor(random()*16)::int],
    -- age roughly 1–90
    DATE '2024-06-01' - ((365 * (1 + floor(random()*89)))::int + floor(random()*365)::int),
    (ARRAY['M','F'])[1 + floor(random()*2)::int],
    DATE '2022-01-01' + (floor(random()*900))::int,   -- registered over ~2.5 yrs
    CASE WHEN random() < 0.15 THEN NULL                -- ~15% self-pay (no insurance)
         ELSE 1 + floor(random()*5)::int END
FROM generate_series(1,600);

-- ------------------------------------------------------------
-- Appointments: ~2800 total, randomly assigned across patients
-- (600) and doctors (40), spread over 18 months. Random
-- assignment gives a realistic spread — some patients visit
-- often, some not at all.
-- ------------------------------------------------------------

INSERT INTO appointments
    (patient_id, doctor_id, scheduled_at, duration_minutes, status, is_inpatient)
SELECT
    1 + floor(random()*600)::int,    -- patient_id in 1..600
    1 + floor(random()*40)::int,     -- doctor_id  in 1..40
    -- random business-hours timestamp between 2024-01-01 and ~2025-06
    (DATE '2024-01-01' + (floor(random()*545))::int)
        + make_time(8 + floor(random()*9)::int, (floor(random()*4)*15)::int, 0),
    (ARRAY[15,20,30,30,45,60])[1 + floor(random()*6)::int],
    CASE
        WHEN random() < 0.80 THEN 'completed'
        WHEN random() < 0.92 THEN 'no_show'
        ELSE 'cancelled'
    END,
    (random() < 0.08)        -- ~8% inpatient
FROM generate_series(1, 2800);

-- ------------------------------------------------------------
-- Diagnoses: ~90% of completed appointments get one.
-- Code+description are kept matched by picking a single
-- 'code|description' entry inline, then splitting it.
-- ------------------------------------------------------------

INSERT INTO diagnoses (appointment_id, icd_code, description)
SELECT
    a.appointment_id,
    split_part(pick, '|', 1) AS icd_code,
    split_part(pick, '|', 2) AS description
FROM appointments a
CROSS JOIN LATERAL (
    SELECT (ARRAY[
        'E11.9|Type 2 diabetes mellitus',
        'I10|Essential hypertension',
        'J45.909|Asthma, unspecified',
        'M54.5|Low back pain',
        'E78.5|Hyperlipidemia',
        'F41.1|Generalized anxiety disorder',
        'K21.9|Gastro-esophageal reflux',
        'J02.9|Acute pharyngitis',
        'N39.0|Urinary tract infection',
        'R51|Headache',
        'E03.9|Hypothyroidism',
        'L20.9|Atopic dermatitis'
    ])[1 + ((a.appointment_id + floor(random()*12))::int % 12)] AS pick
) AS dx
WHERE a.status = 'completed' AND random() < 0.90;

-- ------------------------------------------------------------
-- Prescriptions: ~60% of completed appointments, 1–3 meds each
-- ------------------------------------------------------------

INSERT INTO prescriptions (appointment_id, medication_id, quantity)
SELECT
    a.appointment_id,
    1 + floor(random()*15)::int,     -- medication_id in 1..15
    (ARRAY[10,14,20,28,30,60,90])[1 + floor(random()*7)::int]
FROM appointments a
CROSS JOIN LATERAL generate_series(1, (1 + floor(random()*3))::int) AS rx
WHERE a.status = 'completed' AND random() < 0.60;

-- ------------------------------------------------------------
-- Billing: one bill per completed appointment.
-- Coverage uses the patient's insurer rate (self-pay => 0).
-- ------------------------------------------------------------

INSERT INTO billing
    (appointment_id, total_charge, insurance_covered, patient_responsibility)
SELECT
    appointment_id,
    total_charge,
    covered,
    total_charge - covered
FROM (
    SELECT
        a.appointment_id,
        t.total_charge,
        ROUND(t.total_charge * COALESCE(ip.avg_coverage_rate, 0), 2) AS covered
    FROM appointments a
    JOIN patients p ON p.patient_id = a.patient_id
    LEFT JOIN insurance_providers ip ON ip.insurance_id = p.insurance_id
    CROSS JOIN LATERAL (
        SELECT ROUND(
            (
              (80 + random()*420)                                    -- base visit charge
              + CASE WHEN a.is_inpatient THEN random()*3500 ELSE 0 END -- inpatient surcharge
            )::numeric,
        2) AS total_charge
    ) AS t
    WHERE a.status = 'completed'
) s;

COMMIT;

-- Quick row counts so you can confirm the load worked
SELECT 'departments'  AS table, count(*) FROM departments
UNION ALL SELECT 'doctors',       count(*) FROM doctors
UNION ALL SELECT 'patients',      count(*) FROM patients
UNION ALL SELECT 'appointments',  count(*) FROM appointments
UNION ALL SELECT 'diagnoses',     count(*) FROM diagnoses
UNION ALL SELECT 'prescriptions', count(*) FROM prescriptions
UNION ALL SELECT 'billing',       count(*) FROM billing
ORDER BY 1;
