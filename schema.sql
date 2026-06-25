-- ============================================================
-- Hospital Operations & Patient Analytics — Schema
-- PostgreSQL 16
--
-- All data in this project is SYNTHETIC. No real patient
-- information is used. Generated for portfolio/demo purposes.
-- ============================================================

-- Run this on a fresh database, e.g.:
--   createdb healthcare
--   psql -d healthcare -f schema.sql

BEGIN;

-- Drop in reverse-dependency order so the script is re-runnable
DROP TABLE IF EXISTS billing CASCADE;
DROP TABLE IF EXISTS prescriptions CASCADE;
DROP TABLE IF EXISTS diagnoses CASCADE;
DROP TABLE IF EXISTS appointments CASCADE;
DROP TABLE IF EXISTS medications CASCADE;
DROP TABLE IF EXISTS doctors CASCADE;
DROP TABLE IF EXISTS departments CASCADE;
DROP TABLE IF EXISTS insurance_providers CASCADE;
DROP TABLE IF EXISTS patients CASCADE;

-- ------------------------------------------------------------
-- Reference / dimension tables
-- ------------------------------------------------------------

CREATE TABLE departments (
    department_id   SERIAL PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    floor           INT  NOT NULL CHECK (floor BETWEEN 1 AND 12)
);

CREATE TABLE insurance_providers (
    insurance_id        SERIAL PRIMARY KEY,
    name                TEXT NOT NULL UNIQUE,
    -- average share (0–1) of a bill this provider covers; used by seed/billing
    avg_coverage_rate   NUMERIC(3,2) NOT NULL CHECK (avg_coverage_rate BETWEEN 0 AND 1)
);

CREATE TABLE medications (
    medication_id   SERIAL PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    drug_class      TEXT NOT NULL,
    unit_cost       NUMERIC(8,2) NOT NULL CHECK (unit_cost >= 0)
);

-- ------------------------------------------------------------
-- Core entities
-- ------------------------------------------------------------

CREATE TABLE doctors (
    doctor_id       SERIAL PRIMARY KEY,
    full_name       TEXT NOT NULL,
    specialty       TEXT NOT NULL,
    department_id   INT  NOT NULL REFERENCES departments(department_id),
    hire_date       DATE NOT NULL
);

CREATE TABLE patients (
    patient_id          SERIAL PRIMARY KEY,
    full_name           TEXT NOT NULL,
    date_of_birth       DATE NOT NULL,
    sex                 CHAR(1) NOT NULL CHECK (sex IN ('M','F')),
    registration_date   DATE NOT NULL,
    insurance_id        INT REFERENCES insurance_providers(insurance_id) -- NULL = self-pay
);

-- ------------------------------------------------------------
-- Events / facts
-- ------------------------------------------------------------

CREATE TABLE appointments (
    appointment_id      SERIAL PRIMARY KEY,
    patient_id          INT  NOT NULL REFERENCES patients(patient_id),
    doctor_id           INT  NOT NULL REFERENCES doctors(doctor_id),
    scheduled_at        TIMESTAMP NOT NULL,
    duration_minutes    INT  NOT NULL CHECK (duration_minutes > 0),
    status              TEXT NOT NULL
                        CHECK (status IN ('completed','no_show','cancelled')),
    is_inpatient        BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE diagnoses (
    diagnosis_id    SERIAL PRIMARY KEY,
    appointment_id  INT  NOT NULL REFERENCES appointments(appointment_id),
    icd_code        TEXT NOT NULL,         -- e.g. 'E11.9'
    description     TEXT NOT NULL
);

CREATE TABLE prescriptions (
    prescription_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id  INT NOT NULL REFERENCES appointments(appointment_id),
    medication_id   INT NOT NULL REFERENCES medications(medication_id),
    quantity        INT NOT NULL CHECK (quantity > 0)
);

CREATE TABLE billing (
    bill_id             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id      INT NOT NULL UNIQUE REFERENCES appointments(appointment_id),
    total_charge        NUMERIC(10,2) NOT NULL CHECK (total_charge >= 0),
    insurance_covered   NUMERIC(10,2) NOT NULL CHECK (insurance_covered >= 0),
    patient_responsibility NUMERIC(10,2) NOT NULL CHECK (patient_responsibility >= 0),
    CHECK (insurance_covered + patient_responsibility = total_charge)
);

-- ------------------------------------------------------------
-- Indexes that match the analytical queries we'll write
-- ------------------------------------------------------------

CREATE INDEX idx_appointments_patient   ON appointments(patient_id);
CREATE INDEX idx_appointments_doctor    ON appointments(doctor_id);
CREATE INDEX idx_appointments_time      ON appointments(scheduled_at);
CREATE INDEX idx_appointments_status    ON appointments(status);
CREATE INDEX idx_prescriptions_appt     ON prescriptions(appointment_id);
CREATE INDEX idx_diagnoses_appt         ON diagnoses(appointment_id);

COMMIT;
